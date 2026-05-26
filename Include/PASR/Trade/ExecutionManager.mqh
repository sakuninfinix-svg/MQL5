//+------------------------------------------------------------------+
//| Trade/ExecutionManager.mqh — v3.06                               |
//| Copyright 2026, Agsicentre                                       |
//+------------------------------------------------------------------+
#property strict
#ifndef __TRADE_EXECUTION_MANAGER_MQH__
#define __TRADE_EXECUTION_MANAGER_MQH__

#include <Trade/Trade.mqh>
#include "../Core/IManager.mqh"
#include "../Core/PipelineTypes.mqh"
#include "TradePlan.mqh"

class CExecutionManager : public IManager
  {
private:
   CTrade  m_trade;
   int     m_maxRetries;
   int     m_retryDelayMs;

   bool      m_has_pending;
   TradePlan m_pending_plan;
   int       m_pending_retries;
   ulong     m_next_retry_ms;

   void ClampStopsToMinLevel(ENUM_SIGNAL_DIR dir, double &sl, double &tp)
     {
      long stopsLevelPts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      if(stopsLevelPts <= 0) return;
      double stopLevel = stopsLevelPts * _Point * 1.1;

      if(dir == SIGNAL_BUY)
        {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(sl > 0.0 && (ask - sl) < stopLevel) sl = NormalizeDouble(ask - stopLevel, _Digits);
         if(tp > 0.0 && (tp - ask) < stopLevel) tp = NormalizeDouble(ask + stopLevel, _Digits);
        }
      else if(dir == SIGNAL_SELL)
        {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(sl > 0.0 && (sl - bid) < stopLevel) sl = NormalizeDouble(bid + stopLevel, _Digits);
         if(tp > 0.0 && (bid - tp) < stopLevel) tp = NormalizeDouble(bid - stopLevel, _Digits);
        }
     }

   bool SendOnce(const TradePlan &plan, SExecResult &result)
     {
      result.status = EXEC_FAIL;
      result.executed = false;
      result.ticket = 0;
      result.retcode = 0;
      result.comment = "";

      if(!plan.valid || plan.direction == SIGNAL_NONE || plan.lot <= 0.0)
        {
         result.status = EXEC_SKIP;
         result.comment = "InvalidTradePlan";
         return false;
        }

      double sl = plan.sl;
      double tp = plan.tp;
      ClampStopsToMinLevel(plan.direction, sl, tp);

      bool sent = (plan.direction == SIGNAL_BUY)
         ? m_trade.Buy(plan.lot, _Symbol, 0, sl, tp, plan.comment)
         : m_trade.Sell(plan.lot, _Symbol, 0, sl, tp, plan.comment);

      result.retcode = (int)m_trade.ResultRetcode();
      result.comment = m_trade.ResultComment();
      result.fill_price = m_trade.ResultPrice();

      if(sent && (result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED))
        {
         result.status = EXEC_OK;
         result.executed = true;
         result.ticket = m_trade.ResultOrder();
         return true;
        }

      return false;
     }

   void DispatchPositionOpened(const TradePlan &plan, const SExecResult &result)
     {
      PASREvent evOpen;
      evOpen.id       = EVENT_ID_TRADE_OPEN;
      evOpen.ticket   = result.ticket;
      evOpen.priority = 10;
      evOpen.data1    = (double)plan.direction;
      evOpen.comment  = "OrderPlaced";
      DispatchImmediate(evOpen);

      PASREvent evUpdate;
      evUpdate.id       = EVENT_ID_POSITION_UPDATE;
      evUpdate.ticket   = result.ticket;
      evUpdate.priority = 15;
      evUpdate.data1    = 1.0; // open/refresh signal for RiskManager::SyncOpenTradesFromBroker()
      evUpdate.comment  = "OrderPlaced";
      DispatchImmediate(evUpdate);
     }

public:
   CExecutionManager()
      : IManager(), m_maxRetries(3), m_retryDelayMs(500),
        m_has_pending(false), m_pending_retries(0), m_next_retry_ms(0)
     {}

   virtual string HandlerName() const override { return "ExecutionManager"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      m_trade.SetExpertMagicNumber(m_cfg.MagicNumber);
      m_trade.SetDeviationInPoints((int)MathMax(10.0, m_cfg.Market.SpreadFilterPips * 10.0));
      m_trade.SetTypeFilling(ORDER_FILLING_IOC);
      Print("[Exec] v3.06 Init OK");
      return true;
     }

   virtual void Deinit() override
     {
      m_has_pending = false;
      IManager::Deinit();
     }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_EMERGENCY_STOP);
     }

   virtual void OnEvent(const PASREvent &ev) override
     {
      if(ev.id == EVENT_ID_EMERGENCY_STOP) m_has_pending = false;
     }

   SExecResult Execute(const TradePlan &plan)
     {
      SExecResult result;
      if(!IsInitialized())
        {
         result.status = EXEC_FAIL;
         result.comment = "NotInitialized";
         return result;
        }

      if(SendOnce(plan, result))
        {
         DispatchPositionOpened(plan, result);
         return result;
        }

      if(result.retcode == TRADE_RETCODE_REQUOTE ||
         result.retcode == TRADE_RETCODE_PRICE_CHANGED ||
         result.retcode == TRADE_RETCODE_OFF_QUOTES)
        {
         m_has_pending = true;
         m_pending_plan = plan;
         m_pending_retries = 0;
         m_next_retry_ms = GetTickCount64() + (ulong)m_retryDelayMs;
         result.status = EXEC_RETRYING;
         Print("[Exec] Queued for retry: ", result.retcode, " ", result.comment);
        }
      return result;
     }

   void ProcessRetryQueue()
     {
      if(!m_has_pending) return;
      ulong nowMs = GetTickCount64();
      if(nowMs < m_next_retry_ms) return;

      SExecResult result;
      if(SendOnce(m_pending_plan, result))
        {
         m_has_pending = false;
         PrintFormat("[Exec] Retry success on attempt %d ticket=%llu", m_pending_retries + 1, result.ticket);
         DispatchPositionOpened(m_pending_plan, result);
         return;
        }

      m_pending_retries++;
      if(m_pending_retries >= m_maxRetries)
        {
         m_has_pending = false;
         PrintFormat("[Exec] Retry exhausted after %d attempts. Last: %d %s", m_maxRetries, result.retcode, result.comment);
         return;
        }

      int delayMs = m_retryDelayMs * (1 << m_pending_retries);
      m_next_retry_ms = nowMs + (ulong)delayMs;
      PrintFormat("[Exec] Retry %d/%d in %dms. Code=%d", m_pending_retries, m_maxRetries, delayMs, result.retcode);
     }

   void ManagePositions()
     {
      // Placeholder hook for Stage 11. Full exit/position integration is tracked separately.
     }

   bool HasPendingRetry() const { return m_has_pending; }
  };

#endif // __TRADE_EXECUTION_MANAGER_MQH__
