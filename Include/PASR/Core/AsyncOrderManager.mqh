//+------------------------------------------------------------------+
//| Core/AsyncOrderManager.mqh                                       |
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_ASYNC_ORDER_MANAGER_MQH__
#define __CORE_ASYNC_ORDER_MANAGER_MQH__

#include "LatencyOptimizer.mqh"
#include "../Trade/ExecutionManager.mqh"

enum EAsyncOrderState
  {
   AOS_PENDING,
   AOS_SENDING,
   AOS_SENT,
   AOS_CONFIRMED,
   AOS_FILLED,
   AOS_REJECTED,
   AOS_CANCELLED
  };

struct SAsyncOrder
  {
   ulong            order_id;
   ulong            ticket;
   MqlTradeRequest  request;
   EAsyncOrderState state;
   datetime         timestamp_created;
   datetime         timestamp_sent;
   datetime         timestamp_confirmed;
   int              retry_count;
   string           error_message;

   void Reset()
     {
      order_id = 0;
      ticket = 0;
      ZeroMemory(request);
      state = AOS_PENDING;
      timestamp_created = 0;
      timestamp_sent = 0;
      timestamp_confirmed = 0;
      retry_count = 0;
      error_message = "";
     }
  };

class CAsyncOrderManager
  {
private:
   SAsyncOrder       m_orders[];
   int               m_max_orders;
   int               m_active_count;
   CLatencyOptimizer *m_optimizer;
   CExecutionManager *m_executor;
   int               m_queue_head;
   int               m_queue_tail;

   void ResetOrders()
     {
      for(int i = 0; i < ArraySize(m_orders); i++)
         m_orders[i].Reset();
     }

public:
   CAsyncOrderManager()
      : m_max_orders(50), m_active_count(0), m_optimizer(NULL), m_executor(NULL),
        m_queue_head(0), m_queue_tail(0)
     {
      ArrayResize(m_orders, m_max_orders);
      ResetOrders();
     }

   bool Initialize(CLatencyOptimizer *optimizer, CExecutionManager *executor)
     {
      if(optimizer == NULL || executor == NULL)
         return false;
      m_optimizer = optimizer;
      m_executor = executor;
      m_optimizer.EnableAsyncMode();
      Print("[AsyncOrderManager] Initialized for non-blocking execution");
      return true;
     }

   ulong QueueOrder(const MqlTradeRequest &request)
     {
      if(m_active_count >= m_max_orders)
        {
         Print("[AsyncOrderManager] Order queue full!");
         return 0;
        }

      ulong order_id = GetUniqueOrderId();
      SAsyncOrder order;
      order.Reset();
      order.order_id = order_id;
      order.request = request;
      order.state = AOS_PENDING;
      order.timestamp_created = TimeCurrent();
      m_orders[m_queue_tail] = order;
      m_queue_tail = (m_queue_tail + 1) % m_max_orders;
      m_active_count++;
      return order_id;
     }

   void ProcessQueue()
     {
      if(m_active_count == 0) return;
      SAsyncOrder order = m_orders[m_queue_head];

      if(order.state == AOS_PENDING)
        {
         if(SendOrderAsync(order))
           {
            order.state = AOS_SENDING;
            order.timestamp_sent = TimeCurrent();
           }
        }
      else if(order.state == AOS_SENDING)
        {
         order.state = AOS_SENT;
        }

      m_orders[m_queue_head] = order;
     }

   void OnTradeTransaction(const MqlTradeTransaction &trans)
     {
      for(int i = 0; i < m_max_orders; i++)
        {
         if(m_orders[i].order_id == trans.order && m_orders[i].state == AOS_SENT)
           {
            if(trans.type == TRADE_TRANSACTION_ORDER_ADD)
               m_orders[i].state = AOS_CONFIRMED;
            else if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
               m_orders[i].state = AOS_FILLED;
            else if(trans.type == TRADE_TRANSACTION_ORDER_DELETE)
               m_orders[i].state = AOS_CANCELLED;
            m_orders[i].timestamp_confirmed = TimeCurrent();
            break;
           }
        }
     }

   EAsyncOrderState GetOrderState(ulong order_id) const
     {
      for(int i = 0; i < m_max_orders; i++)
        {
         if(m_orders[i].order_id == order_id)
            return m_orders[i].state;
        }
      return AOS_REJECTED;
     }

   int GetActiveCount() const { return m_active_count; }

private:
   ulong GetUniqueOrderId()
     {
      static ulong counter = 0;
      return ++counter;
     }

   bool SendOrderAsync(SAsyncOrder &order)
     {
      if(m_executor == NULL) return false;
      MqlTradeResult result;
      bool success = m_executor.ExecuteOrder(order.request, result);
      if(success)
        {
         order.ticket = result.order;
         return true;
        }
      order.state = AOS_REJECTED;
      order.error_message = "Execution failed: " + EnumToString((ENUM_TRADE_RETURN_CODE)result.retcode);
      return false;
     }
  };

#endif // __CORE_ASYNC_ORDER_MANAGER_MQH__
