//+------------------------------------------------------------------+
//| Core/EventBus.mqh — v3.01 (Priority Heap)                        |
//| High-performance event dispatch with binary-heap priority queue  |
//|                                                                   |
//| CHANGELOG:                                                        |
//|   v3.01 (2026-05-23) — Sprint 4 Performance Hardening:           |
//|     - REPLACED O(n) linear scan with binary min-heap             |
//|     - Push(): O(log n) sift-up                                   |
//|     - Pop() / Drain(): O(log n) sift-down per event              |
//|     - Added Stats() struct for telemetry monitoring              |
//|     - Added EVENTBUS_MAX_DEPTH guard (prevent unbounded growth)  |
//|   v3.00 — Initial EventBus with CEventBus class + IEventHandler  |
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_EVENTBUS_MQH__
#define __CORE_EVENTBUS_MQH__

#include "Events.mqh"

#define EVENTBUS_MAX_DEPTH   256   // Hard cap: discard lowest-priority if exceeded
#define EVENTBUS_MAX_SUBS     32   // Max subscribers per bus instance

//+------------------------------------------------------------------+
//| IEventHandler — interface all managers must implement            |
//+------------------------------------------------------------------+
class IEventHandler
  {
public:
   virtual void      OnEvent(const PASREvent &ev) = 0;
   virtual string    HandlerName() const           = 0;
  };

//+------------------------------------------------------------------+
//| EventBus Stats — exposed for telemetry / Stage_Journal           |
//+------------------------------------------------------------------+
struct SEventBusStats
  {
   int               queue_depth;    // Current events in queue
   int               peak_depth;     // Max depth seen this session
   ulong             total_pushed;   // Total events pushed (lifetime)
   ulong             total_dropped;  // Events dropped (queue full)
   ulong             total_drained;  // Total dispatch calls
  };

//+------------------------------------------------------------------+
//| CEventBus — Binary min-heap priority queue dispatch              |
//+------------------------------------------------------------------+
class CEventBus
  {
private:
   // ---- Heap storage (min-heap on priority DESC: lower number = higher prio) ----
   PASREvent         m_heap[];          // Heap array (1-indexed: heap[1..m_size])
   int               m_size;            // Current heap occupancy

   // ---- Subscribers ----
   IEventHandler    *m_subs[];          // Subscriber list
   int               m_sub_count;

   // ---- Stats ----
   SEventBusStats    m_stats;

   // ---- Internal heap ops ----
   void              SiftUp(int i)
     {
      while(i > 1)
        {
         int parent = i / 2;
         // min-heap: higher priority (lower number) bubbles up
         if(m_heap[parent].priority > m_heap[i].priority)
           {
            PASREvent tmp   = m_heap[parent];
            m_heap[parent]  = m_heap[i];
            m_heap[i]       = tmp;
            i               = parent;
           }
         else break;
        }
     }

   void              SiftDown(int i)
     {
      while(true)
        {
         int smallest = i;
         int l = 2 * i,
             r = 2 * i + 1;
         if(l <= m_size && m_heap[l].priority < m_heap[smallest].priority)
            smallest = l;
         if(r <= m_size && m_heap[r].priority < m_heap[smallest].priority)
            smallest = r;
         if(smallest != i)
           {
            PASREvent tmp      = m_heap[smallest];
            m_heap[smallest]   = m_heap[i];
            m_heap[i]          = tmp;
            i                  = smallest;
           }
         else break;
        }
     }

public:
              CEventBus() : m_size(0), m_sub_count(0)
     {
      ArrayResize(m_heap,    EVENTBUS_MAX_DEPTH + 2); // 1-indexed + 1 spare
      ArrayResize(m_subs,    EVENTBUS_MAX_SUBS);
      ZeroMemory(m_stats);
     }

   //--- Subscribe / Unsubscribe -------------------------------------------
   bool              Subscribe(IEventHandler *handler)
     {
      if(handler == NULL || m_sub_count >= EVENTBUS_MAX_SUBS) return false;
      // Duplicate guard
      for(int i = 0; i < m_sub_count; i++)
         if(m_subs[i] == handler) return true; // already registered
      m_subs[m_sub_count++] = handler;
      return true;
     }

   void              Unsubscribe(IEventHandler *handler)
     {
      for(int i = 0; i < m_sub_count; i++)
        {
         if(m_subs[i] == handler)
           {
            // Shift remaining left
            for(int j = i; j < m_sub_count - 1; j++)
               m_subs[j] = m_subs[j + 1];
            m_sub_count--;
            return;
           }
        }
     }

   //--- Push (O log n) ----------------------------------------------------
   bool              Push(const PASREvent &ev)
     {
      m_stats.total_pushed++;
      if(m_size >= EVENTBUS_MAX_DEPTH)
        {
         // Queue full: drop lowest-priority event (last leaf in heap)
         // Only drop if new event has higher priority than worst in queue
         if(ev.priority >= m_heap[m_size].priority)
           {
            m_stats.total_dropped++;
            return false; // new event is lower/equal priority, discard it
           }
         // Replace worst
         m_heap[m_size] = ev;
         // Sift up from m_size (it may be better than its parent now)
         SiftUp(m_size);
         return true;
        }
      // Normal path: append at end, sift up
      m_size++;
      m_heap[m_size] = ev;
      SiftUp(m_size);
      // Update stats
      if(m_size > m_stats.peak_depth) m_stats.peak_depth = m_size;
      m_stats.queue_depth = m_size;
      return true;
     }

   //--- Pop highest-priority event (O log n) ------------------------------
   bool              Pop(PASREvent &out)
     {
      if(m_size == 0) return false;
      out          = m_heap[1];          // Root = highest priority
      m_heap[1]    = m_heap[m_size];     // Move last leaf to root
      m_size--;
      if(m_size > 0) SiftDown(1);        // Restore heap property
      m_stats.queue_depth = m_size;
      return true;
     }

   //--- Drain: dispatch all queued events to subscribers (O n log n) ------
   int               Drain()
     {
      int dispatched = 0;
      PASREvent ev;
      while(Pop(ev))
        {
         for(int i = 0; i < m_sub_count; i++)
            if(CheckPointer(m_subs[i]) != POINTER_INVALID)
               m_subs[i].OnEvent(ev);
         dispatched++;
         m_stats.total_drained++;
        }
      return dispatched;
     }

   //--- Peek without removing (read-only) ---------------------------------
   bool              Peek(PASREvent &out) const
     {
      if(m_size == 0) return false;
      out = m_heap[1];
      return true;
     }

   //--- Utility -----------------------------------------------------------
   int               Depth()     const { return m_size; }
   int               SubCount()  const { return m_sub_count; }
   bool              IsEmpty()   const { return m_size == 0; }

   void              Clear()
     {
      m_size = 0;
      m_stats.queue_depth = 0;
     }

   const SEventBusStats *GetStats() const { return &m_stats; }

   void              ResetStats()
     {
      m_stats.total_pushed  = 0;
      m_stats.total_dropped = 0;
      m_stats.total_drained = 0;
      m_stats.peak_depth    = m_size;
     }
  };

#endif // __CORE_EVENTBUS_MQH__
