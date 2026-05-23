//+------------------------------------------------------------------+
//| Trade/ExecutionManager.mqh — v3.01                               |
//| Robust order execution: adaptive slippage, async retry, guard.  |
//|                                                                  |
//| CHANGELOG v3.01 (2026-05-24):                                   |
//|   BUG-T08: FlushPendingRetry() returned EXEC_OK for 'no pending'|
//|            Callers could confuse 'no retry pending' with 'trade  |
//|            succeeded'. Added EXEC_NO_PENDING enum value.         |
//|            Stage should call HasPendingRetry() first.           |
//| CHANGELOG v3.00 (2026-05-23):                                   |
//|   BUG-016: Sleep() removed from retry loop. Async SExecRetryState|
//+------------------------------------------------------------------+
#property strict
#ifndef __TRADE_EXECUTION_MANAGER_MQH__
#define __TRADE_EXECUTION_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "TradePlan.mqh"
#include <Trade/Trade.mqh>

#define EXEC_RETCODE_IS_RETRYABLE(rc) \
   ((rc)==TRADE_RETCODE_REQUOTE       || \
    (rc)==TRADE_RETCODE_PRICE_CHANGED || \
    (rc)==TRADE_RETCODE_OFF_QUOTES    || \
    (rc)==TRADE_RETCODE_PRICE_OFF     || \
    (rc)==TRADE_RETCODE_CONNECTION    || \
    (rc)==TRADE_RETCODE_TIMEOUT)

#define EXEC_MAX_RETRIES   3
#define EXEC_BACKOFF_BASE  100

enum ENUM_EXEC_STATUS
  {
   EXEC_OK            = 0,
   EXEC_BLOCKED       = 1,
   EXEC_FAILED        = 2,
   EXEC_PARTIAL       = 3,
   EXEC_RETRY_EXHAUST = 4,
   EXEC_PENDING       = 5,
   // BUG-T08 FIX: Distinguish 'no retry pending' from 'trade OK'.
   // FlushPendingRetry() returns this when HasPendingRetry()==false.
   // Callers MUST check HasPendingRetry() before calling Flush;
   // if they don't, EXEC_NO_PENDING makes the mis-call detectable.
   EXEC_NO_PENDING    = 6
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

struct SExecRetryState
  {
   bool       pending;
   TradePlan  plan;
   int        attempt;
   ulong      nextRetryMs;
   ExecResult lastResult;

   void Clear() { pending=false; attempt=0; nextRetryMs=0; lastResult.Clear(); }
  };

class CExecutionManager : public IManager
  {
private:
   CTrade           m_trade;
   int              m_maxRetries;
   int              m_backoffBaseMs;
   SExecRetryState  m_retry;

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
      for(int i=0; i<PositionsTotal(); i++)
        {
         if(PositionGetSymbol(i)!=_Symbol) continue;
         if((int)PositionGetInteger(POSITION_MAGIC)!=m_cfg.MagicNumber) continue;
         ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(direction>0 && pt==POSITION_TYPE_BUY)  return true;
         if(direction<0 && pt==POSITION_TYPE_SELL) return true;
        }
      return false;
     }

   bool SendOnce(const TradePlan &plan, ExecResult &result)
     {
      bool sent = (plan.direction==SIGNAL_BUY)
         ? m_trade.Buy (plan.lot, _Symbol, 0, plan.sl, plan.tp, plan.comment)
         : m_trade.Sell(plan.lot, _Symbol, 0, plan.sl, plan.tp, plan.comment);
      if(!sent)
        { result.reason=StringFormat("retcode=%d %s",(int)m_trade.ResultRetcode(),
                                     m_trade.ResultRetcodeDescription()); return false; }
      result.ticket      = m_trade.ResultOrder();
      result.filledLot   = m_trade.ResultVolume();
      result.filledPrice = m_trade.ResultPrice();
      double reqPrice = (plan.direction==SIGNAL_BUY)
         ? SymbolInfoDouble(_Symbol,SYMBOL_ASK)
         : SymbolInfoDouble(_Symbol,SYMBOL_BID);
      result.slippagePts = MathAbs(result.filledPrice-reqPrice)/_Point;
      if(m_debugMode || result.slippagePts>m_cfg.Execution.MaxDeviationPts)
         PrintFormat("[Exec] slip %.1fpts req=%.5f fill=%.5f",
                     result.slippagePts, reqPrice, result.filledPrice);
      return true;
     }

public:
   CExecutionManager()
      : IManager(), m_maxRetries(EXEC_MAX_RETRIES), m_backoffBaseMs(EXEC_BACKOFF_BASE)
     { m_retry.Clear(); }

   virtual string HandlerName() const override { return "ExecutionManager"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data,bus)) return false;
      m_trade.SetExpertMagicNumber(m_cfg.MagicNumber);
      m_trade.SetMarginMode();
      m_trade.SetTypeFillingBySymbol(_Symbol);
      m_trade.SetAsyncMode(false);
      m_retry.Clear();
      return true;
     }

   virtual void DeclareEvents() override { AddEvent(EVENT_ID_POSITION_UPDATE); }

   ExecResult Execute(const TradePlan &plan)
     {
      ExecResult result; result.Clear();
      int dir = (plan.direction==SIGNAL_BUY) ? 1 : -1;
      if(HasOpenPosition(dir)) { result.status=EXEC_BLOCKED; result.reason="Re-entry guard"; return result; }
      double atr = (m_data!=NULL) ? m_data.GetATRPoints() : 100.0;
      m_trade.SetDeviationInPoints(CalcMaxDeviation(atr));
      result.attempts=1;
      if(SendOnce(plan,result))
        {
         result.status = (result.filledLot<plan.lot-0.001) ? EXEC_PARTIAL : EXEC_OK;
         if(result.status==EXEC_PARTIAL)
           { PASREvent ev; ev.id=EVENT_ID_PARTIAL_FILL; ev.priority=8; ev.ticket=result.ticket; DispatchEvent(ev); }
         PrintFormat("[Exec] OK %s ticket=%d lot=%.2f @%.5f slip=%.1fpts",
                     plan.direction==SIGNAL_BUY?"BUY":"SELL",
                     result.ticket, result.filledLot, result.filledPrice, result.slippagePts);
         return result;
        }
      uint rc=(uint)m_trade.ResultRetcode();
      if(!EXEC_RETCODE_IS_RETRYABLE(rc) || m_maxRetries<=0) { result.status=EXEC_FAILED; return result; }
      m_retry.Clear();
      m_retry.pending     = true;
      m_retry.plan        = plan;
      m_retry.attempt     = 1;
      m_retry.nextRetryMs = GetTickCount64()+(ulong)(m_backoffBaseMs*(1<<0));
      m_retry.lastResult  = result;
      result.status=EXEC_PENDING;
      result.reason=StringFormat("Retry deferred (retcode=%d) next in %dms",rc,m_backoffBaseMs);
      return result;
     }

   ExecResult FlushPendingRetry()
     {
      ExecResult nothing; nothing.Clear();
      // BUG-T08 FIX: Return EXEC_NO_PENDING (not EXEC_OK) when no retry queued.
      // Caller should check HasPendingRetry() first; this makes mis-calls detectable.
      nothing.status = EXEC_NO_PENDING;
      if(!m_retry.pending) return nothing;

      ulong now=GetTickCount64();
      if(now < m_retry.nextRetryMs) return m_retry.lastResult;

      m_retry.lastResult.attempts++;
      if(SendOnce(m_retry.plan, m_retry.lastResult))
        {
         m_retry.lastResult.status = (m_retry.lastResult.filledLot<m_retry.plan.lot-0.001)
                                     ? EXEC_PARTIAL : EXEC_OK;
         PrintFormat("[Exec] Deferred OK attempt=%d ticket=%d",
                     m_retry.lastResult.attempts, m_retry.lastResult.ticket);
         ExecResult done=m_retry.lastResult; m_retry.Clear(); return done;
        }
      uint rc=(uint)m_trade.ResultRetcode();
      if(!EXEC_RETCODE_IS_RETRYABLE(rc) || m_retry.attempt>=m_maxRetries)
        {
         m_retry.lastResult.status=(m_retry.attempt>=m_maxRetries)?EXEC_RETRY_EXHAUST:EXEC_FAILED;
         ExecResult done=m_retry.lastResult; m_retry.Clear(); return done;
        }
      m_retry.attempt++;
      m_retry.nextRetryMs=now+(ulong)(m_backoffBaseMs*(1<<m_retry.attempt));
      m_retry.lastResult.status=EXEC_PENDING;
      return m_retry.lastResult;
     }

   bool HasPendingRetry() const { return m_retry.pending; }
   void SetMaxRetries(int n)    { m_maxRetries    = MathMax(0,n); }
   void SetBackoffMs(int ms)    { m_backoffBaseMs = MathMax(50,ms); }
  };

typedef CExecutionManager ExecutionManager;
#endif // __TRADE_EXECUTION_MANAGER_MQH__
