//+------------------------------------------------------------------+
//| Trade/ExecutionManager.mqh — v3.02                               |
//| Copyright 2026, Agsicentre                                       |
//|                                                                  |
//| CHANGELOG:                                                       |
//|   v3.02 (2026-05-24) Sprint 3B:                                 |
//|     BUG-T14: SendOnce() now validates SL/TP against              |
//|              SYMBOL_TRADE_STOPS_LEVEL before sending order.      |
//|              Previously sent plan.sl / plan.tp as-is; if price   |
//|              moved between TradePlan creation and execution,     |
//|              broker rejected with TRADE_RETCODE_INVALID_STOPS.  |
//|              Fix: clamp SL/TP to minimum stopLevel*1.1 distance. |
//|   v3.01 — async retry with exponential backoff.                 |
//+------------------------------------------------------------------+
#property strict
#ifndef __TRADE_EXECUTION_MANAGER_MQH__
#define __TRADE_EXECUTION_MANAGER_MQH__

#include <Trade/Trade.mqh>
#include "../Core/IManager.mqh"
#include "TradePlan.mqh"

struct ExecResult
  {
   bool   success;
   ulong  ticket;
   int    retcode;
   string comment;
   ExecResult() : success(false), ticket(0), retcode(0), comment("") {}
  };

class CExecutionManager : public IManager
  {
private:
   CTrade  m_trade;
   int     m_maxRetries;
   int     m_retryDelayMs;
   bool    m_initialized;

   // Async retry queue (single pending plan)
   bool      m_has_pending;
   TradePlan m_pending_plan;
   int       m_pending_retries;
   datetime  m_next_retry_time;

   // BUG-T14 FIX: Clamp SL/TP to broker's minimum stop level.
   // Modifies sl/tp in-place before order submission.
   void ClampStopsToMinLevel(ENUM_SIGNAL_DIRECTION dir, double &sl, double &tp)
     {
      long stopsLevelPts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      if(stopsLevelPts <= 0) return; // Broker has no stops restriction
      double stopLevel = stopsLevelPts * _Point * 1.1; // +10% safety margin

      if(dir == SIGNAL_BUY)
        {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(sl > 0.0 && (ask - sl) < stopLevel)
            sl = NormalizeDouble(ask - stopLevel, _Digits);
         if(tp > 0.0 && (tp - ask) < stopLevel)
            tp = NormalizeDouble(ask + stopLevel, _Digits);
        }
      else // SIGNAL_SELL
        {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(sl > 0.0 && (sl - bid) < stopLevel)
            sl = NormalizeDouble(bid + stopLevel, _Digits);
         if(tp > 0.0 && (bid - tp) < stopLevel)
            tp = NormalizeDouble(bid - stopLevel, _Digits);
        }
     }

   bool SendOnce(const TradePlan &plan, ExecResult &result)
     {
      double sl = plan.sl;
      double tp = plan.tp;

      // BUG-T14 FIX: Validate stops before submission
      ClampStopsToMinLevel(plan.direction, sl, tp);

      bool sent = (plan.direction == SIGNAL_BUY)
         ? m_trade.Buy (plan.lot, _Symbol, 0, sl, tp, plan.comment)
         : m_trade.Sell(plan.lot, _Symbol, 0, sl, tp, plan.comment);

      result.retcode = (int)m_trade.ResultRetcode();
      result.comment = m_trade.ResultComment();
      if(sent && result.retcode == TRADE_RETCODE_DONE)
        {
         result.success = true;
         result.ticket  = m_trade.ResultOrder();
        }
      return result.success;
     }

public:
   CExecutionManager()
      : m_maxRetries(3), m_retryDelayMs(500), m_initialized(false),
        m_has_pending(false), m_pending_retries(0), m_next_retry_time(0)
     {}

   virtual string HandlerName() const override { return "ExecutionManager"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      m_trade.SetExpertMagicNumber(m_cfg.MagicNumber);
      m_trade.SetDeviationInPoints(m_cfg.Execution.MaxSlippagePts);
      m_trade.SetTypeFilling(ORDER_FILLING_IOC);
      m_initialized = true;
      Print("[Exec] v3.02 Init OK");
      return true;
     }

   virtual void Deinit() override
     {
      m_has_pending  = false;
      m_initialized  = false;
      IManager::Deinit();
     }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_EMERGENCY_STOP);
     }

   virtual void OnEvent(const PASREvent &ev) override
     {
      switch(ev.id)
        {
         case EVENT_ID_EMERGENCY_STOP:
            m_has_pending = false; // Cancel any pending retry
            break;
         default: break;
        }
     }

   // Execute plan — returns immediately; retries handled by OnTimer()
   ExecResult Execute(const TradePlan &plan)
     {
      ExecResult result;
      if(!m_initialized) { result.comment = "NotInitialized"; return result; }

      if(SendOnce(plan, result)) return result;

      // Retry-able errors: queue for async retry
      if(result.retcode == TRADE_RETCODE_REQUOTE ||
         result.retcode == TRADE_RETCODE_PRICE_CHANGED ||
         result.retcode == TRADE_RETCODE_OFF_QUOTES)
        {
         m_has_pending      = true;
         m_pending_plan     = plan;
         m_pending_retries  = 0;
         m_next_retry_time  = TimeCurrent(); // Retry immediately next timer
         Print("[Exec] Queued for retry: ", result.retcode, " ", result.comment);
        }
      return result;
     }

   // Called by Orchestrator::OnTimer() to drain retry queue
   void ProcessRetryQueue()
     {
      if(!m_has_pending) return;
      if(TimeCurrent() < m_next_retry_time) return;

      ExecResult result;
      if(SendOnce(m_pending_plan, result))
        {
         m_has_pending = false;
         PrintFormat("[Exec] Retry success on attempt %d ticket=%llu",
                     m_pending_retries + 1, result.ticket);
         // Notify pipeline of successful execution
         PASREvent ev;
         ev.id     = EVENT_ID_POSITION_UPDATE;
         ev.ticket = result.ticket;
         ev.priority = 15;
         DispatchEvent(ev);
         return;
        }

      m_pending_retries++;
      if(m_pending_retries >= m_maxRetries)
        {
         m_has_pending = false;
         PrintFormat("[Exec] Retry exhausted after %d attempts. Last: %d %s",
                     m_maxRetries, result.retcode, result.comment);
         return;
        }

      // Exponential backoff: 500ms, 1000ms, 2000ms
      int delayMs = m_retryDelayMs * (1 << m_pending_retries);
      m_next_retry_time = TimeCurrent() + (datetime)(delayMs / 1000) + 1;
      PrintFormat("[Exec] Retry %d/%d in %dms. Code=%d",
                  m_pending_retries, m_maxRetries, delayMs, result.retcode);
     }

   bool HasPendingRetry() const { return m_has_pending; }
  };

#endif // __TRADE_EXECUTION_MANAGER_MQH__
