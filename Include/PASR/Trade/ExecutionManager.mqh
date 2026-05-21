//+------------------------------------------------------------------+
//| Trade/ExecutionManager.mqh — v2.00                               |
//| Order execution with retry, slippage guard, event emission.      |
//| Replaces root ../6.ExecutionManager.mqh stub.                    |
//+------------------------------------------------------------------+
#property strict
#ifndef __TRADE_EXECUTION_MANAGER_MQH__
#define __TRADE_EXECUTION_MANAGER_MQH__

#include <Trade/Trade.mqh>
#include "../Core/IManager.mqh"
#include "TradePlan.mqh"

enum ENUM_EXEC_RESULT { EXEC_OK=0, EXEC_RETRY=1, EXEC_FAIL=2 };

struct ExecResult
  {
   ENUM_EXEC_RESULT status;
   ulong            ticket;
   int              retcode;
   string           comment;

   void Ok(ulong t)       { status=EXEC_OK;    ticket=t; retcode=0; comment=""; }
   void Fail(int code, string msg) { status=EXEC_FAIL; ticket=0; retcode=code; comment=msg; }
  };

//+------------------------------------------------------------------+
//| CExecutionManager — sends orders with retry + event dispatch     |
//+------------------------------------------------------------------+
class CExecutionManager : public IManager
  {
private:
   CTrade  m_trade;
   int     m_maxRetry;
   int     m_retryDelayMs;
   double  m_maxSlippage;   // in points

public:
   CExecutionManager()
      : IManager(), m_maxRetry(3), m_retryDelayMs(200), m_maxSlippage(3.0) {}

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      m_trade.SetExpertMagicNumber((ulong)m_cfg.MagicNumber);
      m_trade.SetDeviationInPoints((ulong)m_maxSlippage);
      return true;
     }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_POSITION_UPDATE);
      AddEvent(EVENT_ID_EMERGENCY_STOP);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
     }

   void SetMaxRetry(int n)         { m_maxRetry    = MathMax(1, n); }
   void SetRetryDelayMs(int ms)    { m_retryDelayMs = MathMax(0, ms); }
   void SetMaxSlippage(double pts) { m_maxSlippage  = MathMax(0, pts); }

   // ── Execute a TradePlan ────────────────────────────────────────
   ExecResult Execute(const TradePlan &plan)
     {
      ExecResult res; res.Fail(0, "NotExecuted");

      if(!plan.valid)
        { res.Fail(-1, "InvalidPlan"); return res; }

      for(int attempt = 1; attempt <= m_maxRetry; attempt++)
        {
         bool sent = false;
         if(plan.direction == 1)   // BUY
            sent = m_trade.Buy(plan.lot, _Symbol,
                               plan.entryPrice, plan.stopLoss, plan.takeProfit,
                               StringFormat("PASR#%d", m_cfg.MagicNumber));
         else                      // SELL
            sent = m_trade.Sell(plan.lot, _Symbol,
                                plan.entryPrice, plan.stopLoss, plan.takeProfit,
                                StringFormat("PASR#%d", m_cfg.MagicNumber));

         if(sent && m_trade.ResultRetcode() == TRADE_RETCODE_DONE)
           {
            ulong ticket = m_trade.ResultOrder();
            if(m_debugMode)
               PrintFormat("[Exec] OK ticket=%d lot=%.2f dir=%s attempt=%d",
                           ticket, plan.lot, plan.direction==1?"BUY":"SELL", attempt);

            PASREvent ev;
            ev.id       = EVENT_ID_POSITION_UPDATE;
            ev.priority = 50;
            DispatchEvent(ev);

            res.Ok(ticket);
            return res;
           }

         int code = (int)m_trade.ResultRetcode();
         if(m_debugMode)
            PrintFormat("[Exec] Attempt %d/%d failed: code=%d %s",
                        attempt, m_maxRetry, code, m_trade.ResultRetcodeDescription());

         // Non-retriable errors
         if(code == TRADE_RETCODE_INVALID_PRICE ||
            code == TRADE_RETCODE_INVALID_STOPS ||
            code == TRADE_RETCODE_INVALID_VOLUME)
           { res.Fail(code, m_trade.ResultRetcodeDescription()); return res; }

         if(attempt < m_maxRetry) Sleep(m_retryDelayMs);
        }

      res.Fail((int)m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
      return res;
     }

   // Close a specific ticket
   bool CloseTicket(ulong ticket)
     {
      if(!PositionSelectByTicket(ticket)) return false;
      bool ok = m_trade.PositionClose(ticket);
      if(ok)
        {
         PASREvent ev; ev.id=EVENT_ID_POSITION_UPDATE; ev.priority=50;
         DispatchEvent(ev);
        }
      return ok;
     }

   virtual void OnConfigReload() override
     {
      IManager::OnConfigReload();
      m_trade.SetExpertMagicNumber((ulong)m_cfg.MagicNumber);
      m_trade.SetDeviationInPoints((ulong)m_maxSlippage);
     }
  };

typedef CExecutionManager ExecutionManager;
#endif
