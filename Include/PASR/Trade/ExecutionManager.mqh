//+------------------------------------------------------------------+
//| Trade/ExecutionManager.mqh — v3.20                               |
//| Copyright 2026, Agsicentre                                       |
//+------------------------------------------------------------------+
#property strict
#ifndef __TRADE_EXECUTION_MANAGER_MQH__
#define __TRADE_EXECUTION_MANAGER_MQH__

#include <Trade/Trade.mqh>
#include "../Core/IManager.mqh"
#include "../Core/PipelineTypes.mqh"
#include "TradePlan.mqh"

struct ExecutionSnapshot
  {
   bool             hasPending;
   int              pendingRetries;
   int              maxRetries;
   ulong            nextRetryMs;
   ENUM_EXEC_STATUS lastStatus;
   ulong            lastTicket;
   int              lastRetcode;
   double           lastFillPrice;
   double           lastLot;
   ENUM_SIGNAL_DIR  lastDirection;
   string           lastComment;
   string           lastClearReason;
   datetime         lastExecTime;

   void Clear()
     {
      hasPending = false;
      pendingRetries = 0;
      maxRetries = 0;
      nextRetryMs = 0;
      lastStatus = EXEC_SKIP;
      lastTicket = 0;
      lastRetcode = 0;
      lastFillPrice = 0.0;
      lastLot = 0.0;
      lastDirection = SIGNAL_NONE;
      lastComment = "";
      lastClearReason = "";
      lastExecTime = 0;
     }
  };

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
   ExecutionSnapshot m_snapshot;

   void RefreshSnapshotFromResult(const TradePlan &plan, const SExecResult &result)
     {
      m_snapshot.hasPending = m_has_pending;
      m_snapshot.pendingRetries = m_pending_retries;
      m_snapshot.maxRetries = m_maxRetries;
      m_snapshot.nextRetryMs = m_next_retry_ms;
      m_snapshot.lastStatus = result.status;
      m_snapshot.lastTicket = result.ticket;
      m_snapshot.lastRetcode = result.retcode;
      m_snapshot.lastFillPrice = result.fill_price;
      m_snapshot.lastLot = plan.lot;
      m_snapshot.lastDirection = plan.direction;
      m_snapshot.lastComment = result.comment;
      m_snapshot.lastExecTime = TimeCurrent();
     }

   void ClearPendingRetry(const string reason)
     {
      if(!m_has_pending)
        {
         m_snapshot.lastClearReason = reason;
         return;
        }
      m_has_pending = false;
      m_pending_retries = 0;
      m_next_retry_ms = 0;
      m_snapshot.hasPending = false;
      m_snapshot.pendingRetries = 0;
      m_snapshot.nextRetryMs = 0;
      m_snapshot.lastClearReason = reason;
      if(m_debugMode) Print("[Exec] Pending retry cleared: ", reason);
     }

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
      evUpdate.data1    = 1.0;
      evUpdate.comment  = "OrderPlaced";
      DispatchImmediate(evUpdate);
     }

public:
   CExecutionManager()
      : IManager(), m_maxRetries(3), m_retryDelayMs(500),
        m_has_pending(false), m_pending_retries(0), m_next_retry_ms(0)
     {
      m_snapshot.Clear();
      m_snapshot.maxRetries = m_maxRetries;
     }

   virtual string HandlerName() const override { return "ExecutionManager"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      m_trade.SetExpertMagicNumber(m_cfg.MagicNumber);
      m_trade.SetDeviationInPoints((int)MathMax(10.0, m_cfg.Market.SpreadFilterPips * 10.0));
      m_trade.SetTypeFilling(ORDER_FILLING_IOC);
      m_snapshot.maxRetries = m_maxRetries;
      Print("[Exec] v3.20 Init OK");
      return true;
     }

   virtual void Deinit() override
     {
      ClearPendingRetry("Deinit");
      IManager::Deinit();
     }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_EMERGENCY_STOP);
      AddEvent(EVENT_ID_POSITION_UPDATE);
      AddEvent(EVENT_ID_TRADE_OPEN);
      AddEvent(EVENT_ID_TRADE_CLOSE);
     }

   virtual void OnEvent(const PASREvent &ev) override
     {
      switch(ev.id)
        {
         case EVENT_ID_EMERGENCY_STOP:
            ClearPendingRetry("EmergencyStop");
            break;
         case EVENT_ID_TRADE_OPEN:
            ClearPendingRetry("TradeOpenEvent");
            break;
         case EVENT_ID_POSITION_UPDATE:
            if(ev.data1 == 1.0 || ev.ticket > 0)
               ClearPendingRetry("PositionUpdateEvent");
            break;
         case EVENT_ID_TRADE_CLOSE:
            if(m_debugMode) PrintFormat("[Exec] Trade close observed ticket=%I64u", ev.ticket);
            break;
         default:
            break;
        }
     }

   SExecResult Execute(const TradePlan &plan)
     {
      SExecResult result;
      if(!IsInitialized())
        {
         result.status = EXEC_FAIL;
         result.comment = "NotInitialized";
         RefreshSnapshotFromResult(plan, result);
         return result;
        }

      if(SendOnce(plan, result))
        {
         RefreshSnapshotFromResult(plan, result);
         DispatchPositionOpened(plan, result);
         return result;
        }

      if(result.retcode == TRADE_RETCODE_REQUOTE || result.retcode == TRADE_RETCODE_PRICE_CHANGED)
        {
         m_has_pending = true;
         m_pending_plan = plan;
         m_pending_retries = 0;
         m_next_retry_ms = GetTickCount64() + (ulong)m_retryDelayMs;
         result.status = EXEC_RETRYING;
         Print("[Exec] Queued for retry: ", result.retcode, " ", result.comment);
        }
      RefreshSnapshotFromResult(plan, result);
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
         RefreshSnapshotFromResult(m_pending_plan, result);
         ClearPendingRetry("RetrySuccess");
         PrintFormat("[Exec] Retry success on attempt %d ticket=%I64u", m_pending_retries + 1, result.ticket);
         DispatchPositionOpened(m_pending_plan, result);
         return;
        }

      m_pending_retries++;
      if(m_pending_retries >= m_maxRetries)
        {
         RefreshSnapshotFromResult(m_pending_plan, result);
         PrintFormat("[Exec] Retry failed permanently after %d attempts", m_pending_retries);
         ClearPendingRetry("RetryLimit");
         return;
        }
      m_next_retry_ms = GetTickCount64() + (ulong)m_retryDelayMs;
      RefreshSnapshotFromResult(m_pending_plan, result);
     }

   ExecutionSnapshot GetSnapshot() const { return m_snapshot; }
   bool HasPendingRetry() const { return m_has_pending; }

   void PrintDiagnostics() const
     {
      PrintFormat("[ExecDiag] pending=%s retry=%d/%d lastStatus=%d ticket=%I64u ret=%d price=%.5f lot=%.2f dir=%d comment=%s clear=%s",
                  m_snapshot.hasPending ? "true" : "false",
                  m_snapshot.pendingRetries,
                  m_snapshot.maxRetries,
                  (int)m_snapshot.lastStatus,
                  m_snapshot.lastTicket,
                  m_snapshot.lastRetcode,
                  m_snapshot.lastFillPrice,
                  m_snapshot.lastLot,
                  (int)m_snapshot.lastDirection,
                  m_snapshot.lastComment,
                  m_snapshot.lastClearReason);
     }
  };

#endif // __TRADE_EXECUTION_MANAGER_MQH__
