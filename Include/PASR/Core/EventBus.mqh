//+------------------------------------------------------------------+
//| Core/EventBus.mqh — v3.03                                       |
//| High-performance event dispatch with binary-heap priority queue  |
//|                                                                  |
//| CHANGELOG:                                                       |
//|   v3.03 (2026-05-24):                                           |
//|     BUG-C04: Dispatch() and Drain() now respect handler          |
//|              IsListening(event_id) filters. IEventHandler adds   |
//|              default IsListening() returning true.               |
//|   v3.02 (2026-05-23) — Sprint 11 API Unification:               |
//|     BUG-N06: Register() alias added (= Subscribe()) so          |
//|              Orchestrator::RegisterManager() compiles cleanly.  |
//|     BUG-N01: Dispatch(ev) single-event helper added for         |
//|              intra-pipeline drain (Stage_AnalysisSR).           |
//|     Drain() now returns count of dispatched events.             |
//|   v3.01 (2026-05-23) — Sprint 4 Performance Hardening:          |
//|     - REPLACED O(n) linear scan with binary min-heap            |
//|     - Push(): O(log n) sift-up                                  |
//|     - Pop() / Drain(): O(log n) sift-down per event             |
//|     - Added Stats() struct for telemetry monitoring             |
//|     - Added EVENTBUS_MAX_DEPTH guard                            |
//|   v3.00 — Initial EventBus with CEventBus class + IEventHandler |
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_EVENTBUS_MQH__
#define __CORE_EVENTBUS_MQH__

#include "Events.mqh"

#define EVENTBUS_MAX_DEPTH   256
#define EVENTBUS_MAX_SUBS     32

//+------------------------------------------------------------------+
//| IEventHandler — interface all managers must implement            |
//+------------------------------------------------------------------+
class IEventHandler
  {
public:
   virtual void      OnEvent(const PASREvent &ev) = 0;
   virtual string    HandlerName() const           = 0;
   virtual bool      IsListening(ENUM_EVENT_ID id) const { return true; }
  };

//+------------------------------------------------------------------+
//| EventBus Stats                                                   |
//+------------------------------------------------------------------+
struct SEventBusStats
  {
   int               queue_depth;
   int               peak_depth;
   ulong             total_pushed;
   ulong             total_dropped;
   ulong             total_drained;
  };

//+------------------------------------------------------------------+
//| CEventBus — Binary min-heap priority queue + subscriber dispatch |
//+------------------------------------------------------------------+
class CEventBus
  {
private:
   PASREvent         m_heap[];
   int               m_size;
   IEventHandler    *m_subs[];
   int               m_sub_count;
   SEventBusStats    m_stats;

   void SiftUp(int i)
     {
      while(i > 1)
        {
         int parent = i / 2;
         if(m_heap[parent].priority > m_heap[i].priority)
           {
            PASREvent tmp  = m_heap[parent];
            m_heap[parent] = m_heap[i];
            m_heap[i]      = tmp;
            i              = parent;
           }
         else break;
        }
     }

   void SiftDown(int i)
     {
      while(true)
        {
         int smallest = i;
         int l = 2*i, r = 2*i+1;
         if(l <= m_size && m_heap[l].priority < m_heap[smallest].priority) smallest = l;
         if(r <= m_size && m_heap[r].priority < m_heap[smallest].priority) smallest = r;
         if(smallest != i)
           {
            PASREvent tmp     = m_heap[smallest];
            m_heap[smallest]  = m_heap[i];
            m_heap[i]         = tmp;
            i                 = smallest;
           }
         else break;
        }
     }

   void RouteEvent(const PASREvent &ev)
     {
      for(int i = 0; i < m_sub_count; i++)
        {
         if(m_subs[i] == NULL) continue;
         if(!m_subs[i].IsListening(ev.id)) continue;
         m_subs[i].OnEvent(ev);
        }
     }

public:
   CEventBus() : m_size(0), m_sub_count(0)
     {
      ArrayResize(m_heap, EVENTBUS_MAX_DEPTH + 2);
      ArrayResize(m_subs, EVENTBUS_MAX_SUBS);
      ZeroMemory(m_stats);
     }

   bool Subscribe(IEventHandler *handler)
     {
      if(handler == NULL || m_sub_count >= EVENTBUS_MAX_SUBS) return false;
      for(int i = 0; i < m_sub_count; i++)
         if(m_subs[i] == handler) return true;
      m_subs[m_sub_count++] = handler;
      return true;
     }

   bool Register(IEventHandler *handler) { return Subscribe(handler); }

   void Unsubscribe(IEventHandler *handler)
     {
      for(int i = 0; i < m_sub_count; i++)
         if(m_subs[i] == handler)
           {
            for(int j = i; j < m_sub_count-1; j++) m_subs[j] = m_subs[j+1];
            m_sub_count--;
            return;
           }
     }

   bool Push(const PASREvent &ev)
     {
      m_stats.total_pushed++;
      if(m_size >= EVENTBUS_MAX_DEPTH)
        {
         if(ev.priority >= m_heap[m_size].priority)
           { m_stats.total_dropped++; return false; }
         m_heap[m_size] = ev;
         SiftUp(m_size);
         return true;
        }
      m_size++;
      m_heap[m_size] = ev;
      SiftUp(m_size);
      if(m_size > m_stats.peak_depth) m_stats.peak_depth = m_size;
      m_stats.queue_depth = m_size;
      return true;
     }

   bool Pop(PASREvent &out)
     {
      if(m_size == 0) return false;
      out        = m_heap[1];
      m_heap[1]  = m_heap[m_size];
      m_size--;
      if(m_size > 0) SiftDown(1);
      m_stats.queue_depth = m_size;
      return true;
     }

   void Dispatch(const PASREvent &ev)
     {
      RouteEvent(ev);
      m_stats.total_drained++;
     }

   int Drain()
     {
      int dispatched = 0;
      PASREvent ev;
      while(Pop(ev))
        {
         RouteEvent(ev);
         dispatched++;
         m_stats.total_drained++;
        }
      return dispatched;
     }

   bool Peek(PASREvent &out) const
     {
      if(m_size == 0) return false;
      out = m_heap[1];
      return true;
     }

   int  Depth()    const { return m_size; }
   int  SubCount() const { return m_sub_count; }
   bool IsEmpty()  const { return m_size == 0; }
   void Clear()          { m_size = 0; m_stats.queue_depth = 0; }

   const SEventBusStats *GetStats() const { return &m_stats; }
   void ResetStats()
     {
      m_stats.total_pushed = m_stats.total_dropped = m_stats.total_drained = 0;
      m_stats.peak_depth   = m_size;
     }
  };

#endif // __CORE_EVENTBUS_MQH__
