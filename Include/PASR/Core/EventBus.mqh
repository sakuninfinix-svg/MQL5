//+------------------------------------------------------------------+
//| Core/EventBus.mqh — v3.04                                       |
//| High-performance event dispatch with binary-heap priority queue  |
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_EVENTBUS_MQH__
#define __CORE_EVENTBUS_MQH__

#include "Events.mqh"

#define EVENTBUS_MAX_DEPTH   256
#define EVENTBUS_MAX_SUBS     32

class IEventHandler
  {
public:
   virtual void      OnEvent(const PASREvent &ev) = 0;
   virtual string    HandlerName() const           = 0;
   virtual bool      IsListening(ENUM_EVENT_ID id) const { return true; }
  };

struct SEventBusStats
  {
   int               queue_depth;
   int               peak_depth;
   ulong             total_pushed;
   ulong             total_dropped;
   ulong             total_drained;
  };

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

   int FindWorstPriorityIndex() const
     {
      if(m_size <= 0) return -1;
      int worst = 1;
      int firstLeaf = MathMax(1, m_size / 2 + 1);
      for(int i = firstLeaf; i <= m_size; i++)
        {
         if(m_heap[i].priority > m_heap[worst].priority)
            worst = i;
        }
      return worst;
     }

   void RestoreHeapAt(int idx)
     {
      if(idx <= 0 || idx > m_size) return;
      SiftUp(idx);
      SiftDown(idx);
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
         int worstIdx = FindWorstPriorityIndex();
         if(worstIdx < 1 || ev.priority >= m_heap[worstIdx].priority)
           {
            m_stats.total_dropped++;
            return false;
           }
         m_heap[worstIdx] = ev;
         RestoreHeapAt(worstIdx);
         m_stats.queue_depth = m_size;
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
