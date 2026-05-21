//+------------------------------------------------------------------+
//| Trade/ExecutionManager.mqh — v2.00                               |
//| Robust order execution: adaptive slippage, retry, guard, audit.  |
//|                                                                  |
//| FEATURES:                                                        |
//|   • Adaptive max deviation  : ATR-based (not hardcoded pips)     |
//|   • Retry loop             : up to 3 attempts on transient errors |
//|   • Exponential backoff    : 100ms × 2^n between retries         |
//|   • Re-entry guard         : blocks duplicate open on same symbol |
//|   • Partial fill detection : fires EVENT_PARTIAL_FILL if short   |
//|   • Slippage audit log     : logs actual vs requested price delta |
//|                                                                  |
//| CHANGE LOG:                                                      |
//|   v2.00 (2026-05-21) — Phase 5: full execution hardening         |
//|   v1.00 (2026-05-20) — initial basic send order                  |
//+------------------------------------------------------------------+
#property strict
#ifndef __TRADE_EXECUTION_MANAGER_MQH__
#define __TRADE_EXECUTION_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "TradePlan.mqh"
#include <Trade/Trade.mqh>

// Retry-eligible return codes
#define EXEC_RETCODE_IS_RETRYABLE(rc) \
   ((rc)==TRADE_RETCODE_REQUOTE        || \
    (rc)==TRADE_RETCODE_PRICE_CHANGED  || \
    (rc)==TRADE_RETCODE_OFF_QUOTES     || \
    (rc)==TRADE_RETCODE_PRICE_OFF      || \
    (rc)==TRADE_RETCODE_CONNECTION     || \
    (rc)==TRADE_RETCODE_TIMEOUT)

#define EXEC_MAX_RETRIES   3
#define EXEC_BACKOFF_BASE  100   // ms

enum ENUM_EXEC_STATUS
  {
   EXEC_OK           = 0,
   EXEC_BLOCKED      = 1,   // re-entry guard or risk block
   EXEC_FAILED       = 2,   // broker rejected, non-retryable
   EXEC_PARTIAL      = 3,   // partially filled
   EXEC_RETRY_EXHAUST= 4    // all retries used
  };

struct ExecResult
  {
   ENUM_EXEC_STATUS status;
   ulong            ticket;
   double           filledLot;
   double           filledPrice;
   double           slippagePts;  // actual - requested (points)
   int              attempts;
   string           reason;

   void Clear()
     { status=EXEC_FAILED; ticket=0; filledLot=0;
       filledPrice=0; slippagePts=0; attempts=0; reason=""; }
  };

//+------------------------------------------------------------------+
//| CExecutionManager                                                |
//+------------------------------------------------------------------+
class CExecutionManager : public IManager
  {
private:
   CTrade   m_trade;
   int      m_maxRetries;
   int      m_backoffBaseMs;

   // ── Adaptive deviation: ATR × factor, clamped to [minDev, maxDev] ──
   int CalcMaxDeviation(double atrPoints) const
     {
      double raw = atrPoints * m_cfg.Execution.DeviationAtrFactor;
      int dev = (int)MathRound(raw);
      dev = (int)MathMax(m_cfg.Execution.MinDeviationPts, dev);
      dev = (int)MathMin(m_cfg.Execution.MaxDeviationPts, dev);
      return dev;
     }

   // ── Re-entry guard: true if we already have an open position ────
   bool HasOpenPosition(int direction) const
     {
      for(int i = 0; i < PositionsTotal(); i++)
        {
         if(PositionGetSymbol(i) != _Symbol) continue;
         if((int)PositionGetInteger(POSITION_MAGIC) != m_cfg.MagicNumber) continue;
         ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         // Block same-direction duplicate
         if(direction > 0 && pt == POSITION_TYPE_BUY)  return true;
         if(direction < 0 && pt == POSITION_TYPE_SELL) return true;
        }
      return false;
     }

   // ── Single send attempt ─────────────────────────────────────
   bool SendOnce(const TradePlan &plan, int deviation, ExecResult &result)
     {
      bool sent = false;
      if(plan.direction == SIGNAL_BUY)
         sent = m_trade.Buy(plan.lot, _Symbol,
                            0,             // market price
                            plan.sl,
                            plan.tp,
                            plan.comment);
      else
         sent = m_trade.Sell(plan.lot, _Symbol,
                             0,
                             plan.sl,
                             plan.tp,
                             plan.comment);

      if(!sent)
        {
         result.reason = StringFormat("Send failed retcode=%d %s",
                                      (int)m_trade.ResultRetcode(),
                                      m_trade.ResultRetcodeDescription());
         return false;
        }

      result.ticket      = m_trade.ResultOrder();
      result.filledLot   = m_trade.ResultVolume();
      result.filledPrice = m_trade.ResultPrice();

      // Slippage audit
      double reqPrice = (plan.direction==SIGNAL_BUY)
                        ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                        : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      result.slippagePts = MathAbs(result.filledPrice - reqPrice)
                           / SymbolInfoDouble(_Symbol, SYMBOL_POINT);

      if(m_debugMode || result.slippagePts > m_cfg.Execution.MaxDeviationPts)
         PrintFormat("[Exec] Slippage: req=%.5f fill=%.5f delta=%.1f pts",
                     reqPrice, result.filledPrice, result.slippagePts);
      return true;
     }

public:
   CExecutionManager()
      : IManager(), m_maxRetries(EXEC_MAX_RETRIES),
        m_backoffBaseMs(EXEC_BACKOFF_BASE)
     {}

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      m_trade.SetExpertMagicNumber(m_cfg.MagicNumber);
      m_trade.SetMarginMode();
      m_trade.SetTypeFillingBySymbol(_Symbol);
      m_trade.SetAsyncMode(false);  // synchronous for reliable retry
      return true;
     }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_POSITION_UPDATE);
     }

   //+----------------------------------------------------------------+
   //| Execute — main entry point                                     |
   //+----------------------------------------------------------------+
   ExecResult Execute(const TradePlan &plan)
     {
      ExecResult result;
      result.Clear();

      // 1) Re-entry guard
      int dir = (plan.direction==SIGNAL_BUY) ? 1 : -1;
      if(HasOpenPosition(dir))
        {
         result.status = EXEC_BLOCKED;
         result.reason = "Re-entry guard: position already open";
         if(m_debugMode) Print("[Exec] ", result.reason);
         return result;
        }

      // 2) Adaptive max deviation
      double atr = (m_data != NULL) ? m_data.GetATRPoints() : 100.0;
      int    dev = CalcMaxDeviation(atr);
      m_trade.SetDeviationInPoints(dev);

      if(m_debugMode)
         PrintFormat("[Exec] ATR=%.0f dev=%d pts lot=%.2f dir=%s",
                     atr, dev, plan.lot,
                     plan.direction==SIGNAL_BUY?"BUY":"SELL");

      // 3) Retry loop
      for(int attempt = 0; attempt <= m_maxRetries; attempt++)
        {
         result.attempts = attempt + 1;

         if(SendOnce(plan, dev, result))
           {
            // Success path
            if(result.filledLot < plan.lot - 0.001)
              {
               // Partial fill
               result.status = EXEC_PARTIAL;
               PrintFormat("[Exec] Partial fill: req=%.2f filled=%.2f ticket=%d",
                           plan.lot, result.filledLot, result.ticket);
               PASREvent ev;
               ev.id = EVENT_ID_PARTIAL_FILL; ev.priority = 8;
               ev.ticket = result.ticket;
               DispatchEvent(ev);
              }
            else
              {
               result.status = EXEC_OK;
              }

            PrintFormat("[Exec] ✓ %s ticket=%d lot=%.2f @%.5f slip=%.1f pts (try %d)",
                        plan.direction==SIGNAL_BUY?"BUY":"SELL",
                        result.ticket, result.filledLot,
                        result.filledPrice, result.slippagePts,
                        result.attempts);
            return result;
           }

         // Check if retryable
         uint rc = (uint)m_trade.ResultRetcode();
         if(!EXEC_RETCODE_IS_RETRYABLE(rc) || attempt >= m_maxRetries)
           {
            result.status = (attempt >= m_maxRetries)
                            ? EXEC_RETRY_EXHAUST : EXEC_FAILED;
            PrintFormat("[Exec] ✗ Failed retcode=%d attempt=%d: %s",
                        rc, attempt+1, result.reason);
            return result;
           }

         // Exponential backoff before next attempt
         int waitMs = m_backoffBaseMs * (1 << attempt);  // 100, 200, 400ms
         PrintFormat("[Exec] Retry %d/%d in %dms (retcode=%d)",
                     attempt+1, m_maxRetries, waitMs, rc);
         Sleep(waitMs);

         // Refresh price data before retry
         if(m_data != NULL) m_data.OnTick();
        }

      result.status = EXEC_RETRY_EXHAUST;
      return result;
     }

   // Accessors
   void SetMaxRetries(int n)      { m_maxRetries    = MathMax(0, n); }
   void SetBackoffMs(int ms)      { m_backoffBaseMs = MathMax(50, ms); }
  };

typedef CExecutionManager ExecutionManager;
#endif // __TRADE_EXECUTION_MANAGER_MQH__
