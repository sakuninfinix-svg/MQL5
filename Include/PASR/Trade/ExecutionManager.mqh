//+------------------------------------------------------------------+
//| Trade/ExecutionManager.mqh — v3.00                               |
//| Robust order execution: adaptive slippage, async retry, guard.   |
//|                                                                  |
//| CHANGELOG:                                                       |
//|   v3.00 (2026-05-23) — BUG-016 CRITICAL:                        |
//|     Sleep() REMOVED from retry loop.                            |
//|     Sleep() in OnTimer context blocks ALL MQL5 event handlers:  |
//|     no trailing stops, no EventBus drain, no price updates.     |
//|     Replaced with async deferred retry via SExecRetryState.     |
//|     FlushPendingRetry() called by pipeline Stage_Execution()    |
//|     on each tick to check if backoff window has elapsed.        |
//|     First attempt is still synchronous (zero latency for fills).|
//|   v2.00 (2026-05-21) — Phase 5 hardening (had Sleep bug)       |
//|   v1.00 (2026-05-20) — initial                                  |
//+------------------------------------------------------------------+
#property strict
#ifndef __TRADE_EXECUTION_MANAGER_MQH__
#define __TRADE_EXECUTION_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "TradePlan.mqh"
#include <Trade/Trade.mqh>

#define EXEC_RETCODE_IS_RETRYABLE(rc) \
   ((rc)==TRADE_RETCODE_REQUOTE        || \
    (rc)==TRADE_RETCODE_PRICE_CHANGED  || \
    (rc)==TRADE_RETCODE_OFF_QUOTES     || \
    (rc)==TRADE_RETCODE_PRICE_OFF      || \
    (rc)==TRADE_RETCODE_CONNECTION     || \
    (rc)==TRADE_RETCODE_TIMEOUT)

#define EXEC_MAX_RETRIES   3
#define EXEC_BACKOFF_BASE  100   // ms per retry level

enum ENUM_EXEC_STATUS
  {
   EXEC_OK            = 0,
   EXEC_BLOCKED       = 1,   // re-entry guard or risk block
   EXEC_FAILED        = 2,   // non-retryable broker rejection
   EXEC_PARTIAL       = 3,   // partially filled
   EXEC_RETRY_EXHAUST = 4,   // all retries used
   EXEC_PENDING       = 5    // BUG-016: retry deferred, not yet complete
  };

struct ExecResult
  {
   ENUM_EXEC_STATUS status;
   ulong            ticket;
   double           filledLot;
   double           filledPrice;
   double           slippagePts;
   int              attempts;
   string           reason;

   void Clear()
     { status=EXEC_FAILED; ticket=0; filledLot=0;
       filledPrice=0; slippagePts=0; attempts=0; reason=""; }
  };

//+------------------------------------------------------------------+
//| BUG-016 FIX: Async retry state — replaces Sleep() backoff       |
//| When attempt N fails with a retryable code, we store the plan,  |
//| current attempt count, and the timestamp when next retry is due. |
//| FlushPendingRetry() checks GetTickCount64() each tick/timer.    |
//+------------------------------------------------------------------+
struct SExecRetryState
  {
   bool      pending;
   TradePlan plan;
   int       attempt;        // next attempt index (1-based)
   ulong     nextRetryMs;    // GetTickCount64() threshold
   ExecResult lastResult;   // result so far (EXEC_PENDING until done)

   void Clear() { pending=false; attempt=0; nextRetryMs=0; lastResult.Clear(); }
  };

//+------------------------------------------------------------------+
//| CExecutionManager                                                |
//+------------------------------------------------------------------+
class CExecutionManager : public IManager
  {
private:
   CTrade           m_trade;
   int              m_maxRetries;
   int              m_backoffBaseMs;
   SExecRetryState  m_retry;   // BUG-016: single-slot async retry queue

   int CalcMaxDeviation(double atrPoints) const
     {
      double raw = atrPoints * m_cfg.Execution.DeviationAtrFactor;
      int dev = (int)MathRound(raw);
      dev = (int)MathMax(m_cfg.Execution.MinDeviationPts, dev);
      dev = (int)MathMin(m_cfg.Execution.MaxDeviationPts, dev);
      return dev;
     }

   bool HasOpenPosition(int direction) const
     {
      for(int i = 0; i < PositionsTotal(); i++)
        {
         if(PositionGetSymbol(i) != _Symbol) continue;
         if((int)PositionGetInteger(POSITION_MAGIC) != m_cfg.MagicNumber) continue;
         ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(direction > 0 && pt == POSITION_TYPE_BUY)  return true;
         if(direction < 0 && pt == POSITION_TYPE_SELL) return true;
        }
      return false;
     }

   //+---------------------------------------------------------------+
   //| SendOnce — single broker send. No Sleep(). No blocking.       |
   //+---------------------------------------------------------------+
   bool SendOnce(const TradePlan &plan, ExecResult &result)
     {
      bool sent = (plan.direction == SIGNAL_BUY)
         ? m_trade.Buy (plan.lot, _Symbol, 0, plan.sl, plan.tp, plan.comment)
         : m_trade.Sell(plan.lot, _Symbol, 0, plan.sl, plan.tp, plan.comment);

      if(!sent)
        {
         result.reason = StringFormat("retcode=%d %s",
                                      (int)m_trade.ResultRetcode(),
                                      m_trade.ResultRetcodeDescription());
         return false;
        }

      result.ticket      = m_trade.ResultOrder();
      result.filledLot   = m_trade.ResultVolume();
      result.filledPrice = m_trade.ResultPrice();

      double reqPrice = (plan.direction == SIGNAL_BUY)
         ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
         : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      result.slippagePts = MathAbs(result.filledPrice - reqPrice) / _Point;

      if(m_debugMode || result.slippagePts > m_cfg.Execution.MaxDeviationPts)
         PrintFormat("[Exec] slip %.1f pts | req=%.5f fill=%.5f",
                     result.slippagePts, reqPrice, result.filledPrice);
      return true;
     }

public:
   CExecutionManager()
      : IManager(),
        m_maxRetries(EXEC_MAX_RETRIES),
        m_backoffBaseMs(EXEC_BACKOFF_BASE)
     { m_retry.Clear(); }

   virtual string HandlerName() const override { return "ExecutionManager"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      m_trade.SetExpertMagicNumber(m_cfg.MagicNumber);
      m_trade.SetMarginMode();
      m_trade.SetTypeFillingBySymbol(_Symbol);
      m_trade.SetAsyncMode(false);
      m_retry.Clear();
      return true;
     }

   virtual void DeclareEvents() override
     { AddEvent(EVENT_ID_POSITION_UPDATE); }

   //+---------------------------------------------------------------+
   //| Execute — synchronous first attempt; defers retries async.    |
   //| Returns EXEC_PENDING if first attempt fails with a retryable  |
   //| error. Caller must poll FlushPendingRetry() each tick/timer.  |
   //+---------------------------------------------------------------+
   ExecResult Execute(const TradePlan &plan)
     {
      ExecResult result;
      result.Clear();

      // Re-entry guard
      int dir = (plan.direction == SIGNAL_BUY) ? 1 : -1;
      if(HasOpenPosition(dir))
        {
         result.status = EXEC_BLOCKED;
         result.reason = "Re-entry guard: position already open";
         return result;
        }

      // Setup deviation
      double atr = (m_data != NULL) ? m_data.GetATRPoints() : 100.0;
      m_trade.SetDeviationInPoints(CalcMaxDeviation(atr));

      result.attempts = 1;
      if(SendOnce(plan, result))
        {
         result.status = (result.filledLot < plan.lot - 0.001)
                         ? EXEC_PARTIAL : EXEC_OK;

         if(result.status == EXEC_PARTIAL)
           {
            PASREvent ev; ev.id=EVENT_ID_PARTIAL_FILL; ev.priority=8;
            ev.ticket=result.ticket;
            DispatchEvent(ev);
           }

         PrintFormat("[Exec] OK %s ticket=%d lot=%.2f @%.5f slip=%.1f pts",
                     plan.direction==SIGNAL_BUY?"BUY":"SELL",
                     result.ticket, result.filledLot,
                     result.filledPrice, result.slippagePts);
         return result;
        }

      // First attempt failed
      uint rc = (uint)m_trade.ResultRetcode();
      if(!EXEC_RETCODE_IS_RETRYABLE(rc) || m_maxRetries <= 0)
        {
         result.status = EXEC_FAILED;
         PrintFormat("[Exec] FAILED retcode=%d: %s", rc, result.reason);
         return result;
        }

      //--- BUG-016 FIX: Defer retry; NO Sleep().
      m_retry.Clear();
      m_retry.pending      = true;
      m_retry.plan         = plan;
      m_retry.attempt      = 1;   // attempt 0 done above; next = attempt 1
      m_retry.nextRetryMs  = GetTickCount64()
                             + (ulong)(m_backoffBaseMs * (1 << 0));  // 100ms
      m_retry.lastResult   = result;

      result.status = EXEC_PENDING;
      result.reason = StringFormat("Retry deferred (retcode=%d) next in %dms",
                                   rc, m_backoffBaseMs);
      PrintFormat("[Exec] Attempt 1 failed retcode=%d. Deferred retry in %dms.",
                  rc, m_backoffBaseMs);
      return result;
     }

   //+---------------------------------------------------------------+
   //| FlushPendingRetry — called by Stage_Execution() each tick.   |
   //| Checks if backoff window elapsed; if yes, attempts next send. |
   //| Returns: the completed ExecResult once done, or a PENDING one |
   //|          if still waiting. Returns Clear result if no pending.|
   //+---------------------------------------------------------------+
   ExecResult FlushPendingRetry()
     {
      ExecResult nothing; nothing.Clear(); nothing.status = EXEC_OK;

      if(!m_retry.pending) return nothing;

      ulong now = GetTickCount64();
      if(now < m_retry.nextRetryMs) return m_retry.lastResult; // still waiting

      // Time to retry
      m_retry.lastResult.attempts++;
      if(SendOnce(m_retry.plan, m_retry.lastResult))
        {
         m_retry.lastResult.status = (m_retry.lastResult.filledLot
                                      < m_retry.plan.lot - 0.001)
                                     ? EXEC_PARTIAL : EXEC_OK;
         PrintFormat("[Exec] Deferred retry OK attempt=%d ticket=%d",
                     m_retry.lastResult.attempts, m_retry.lastResult.ticket);
         ExecResult done = m_retry.lastResult;
         m_retry.Clear();
         return done;
        }

      uint rc = (uint)m_trade.ResultRetcode();
      if(!EXEC_RETCODE_IS_RETRYABLE(rc) || m_retry.attempt >= m_maxRetries)
        {
         m_retry.lastResult.status = (m_retry.attempt >= m_maxRetries)
                                     ? EXEC_RETRY_EXHAUST : EXEC_FAILED;
         PrintFormat("[Exec] Deferred retry EXHAUSTED attempt=%d retcode=%d",
                     m_retry.lastResult.attempts, rc);
         ExecResult done = m_retry.lastResult;
         m_retry.Clear();
         return done;
        }

      // Schedule next retry
      m_retry.attempt++;
      m_retry.nextRetryMs = now
         + (ulong)(m_backoffBaseMs * (1 << m_retry.attempt)); // 200, 400ms
      m_retry.lastResult.status = EXEC_PENDING;
      return m_retry.lastResult;
     }

   bool HasPendingRetry() const { return m_retry.pending; }

   void SetMaxRetries(int n)  { m_maxRetries    = MathMax(0, n); }
   void SetBackoffMs(int ms)  { m_backoffBaseMs = MathMax(50, ms); }
  };

typedef CExecutionManager ExecutionManager;
#endif // __TRADE_EXECUTION_MANAGER_MQH__
