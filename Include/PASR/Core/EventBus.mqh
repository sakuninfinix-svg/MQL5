//+------------------------------------------------------------------+
//| Core/EventBus.mqh — CANONICAL v2.13                              |
//| Priority-queue event bus + EventRecorder ring buffer             |
//+------------------------------------------------------------------+
#pragma once
#ifndef CORE_EVENT_BUS_MQH
#define CORE_EVENT_BUS_MQH

#include "Events.mqh"

//+------------------------------------------------------------------+
//| EventRecorder — ring buffer for recent event history             |
//+------------------------------------------------------------------+
#define PASR_EVENT_HISTORY_SIZE 256

class EventRecorder
  {
private:
   PASREvent         m_history[PASR_EVENT_HISTORY_SIZE];
   int               m_head;
   int               m_count;

public:
   EventRecorder() : m_head(0), m_count(0) { Start(); }

   void              Start()
     {
      ZeroMemory(m_history);
      m_head  = 0;
      m_count = 0;
     }

   void              Record(const PASREvent &ev)
     {
      m_history[m_head] = ev;
      m_head = (m_head + 1) % PASR_EVENT_HISTORY_SIZE;
      if(m_count < PASR_EVENT_HISTORY_SIZE) m_count++;
     }

   int               Count() const { return m_count; }

   bool              GetLast(PASREvent &out, ENUM_EVENT_ID filter = EVENT_ID_NONE) const
     {
      if(m_count == 0) return false;
      int idx = (m_head - 1 + PASR_EVENT_HISTORY_SIZE) % PASR_EVENT_HISTORY_SIZE;
      for(int i = 0; i < m_count; i++)
        {
         const PASREvent &ev = m_history[idx];
         if(filter == EVENT_ID_NONE || ev.id == filter)
           {
            out = ev;
            return true;
           }
         idx = (idx - 1 + PASR_EVENT_HISTORY_SIZE) % PASR_EVENT_HISTORY_SIZE;
        }
      return false;
     }
  };

//+------------------------------------------------------------------+
//| PASREventBus — array-backed min-heap, zero heap alloc            |
//+------------------------------------------------------------------+
#define PASR_BUS_MAX_EVENTS 64

class PASREventBus
  {
private:
   PASREvent         m_queue[PASR_BUS_MAX_EVENTS];
   int               m_size;
   EventRecorder     m_recorder;

   void              SiftUp(int idx)
     {
      while(idx > 0)
        {
         int parent = (idx - 1) / 2;
         if(m_queue[parent].priority <= m_queue[idx].priority) break;
         PASREvent tmp    = m_queue[parent];
         m_queue[parent]  = m_queue[idx];
         m_queue[idx]     = tmp;
         idx = parent;
        }
     }

   void              SiftDown(int idx)
     {
      while(true)
        {
         int smallest = idx;
         int left     = 2 * idx + 1;
         int right    = 2 * idx + 2;
         if(left  < m_size && m_queue[left].priority  < m_queue[smallest].priority) smallest = left;
         if(right < m_size && m_queue[right].priority < m_queue[smallest].priority) smallest = right;
         if(smallest == idx) break;
         PASREvent tmp        = m_queue[smallest];
         m_queue[smallest]    = m_queue[idx];
         m_queue[idx]         = tmp;
         idx = smallest;
        }
     }

public:
   PASREventBus() : m_size(0) {}

   bool              Push(const PASREvent &ev)
     {
      if(m_size >= PASR_BUS_MAX_EVENTS)
        {
         Print("[EventBus][WARN] Queue full — dropping event ", EnumToString(ev.id));
         return false;
        }
      m_queue[m_size] = ev;
      SiftUp(m_size);
      m_size++;
      m_recorder.Record(ev);
      return true;
     }

   bool              Pop(PASREvent &out)
     {
      if(m_size == 0) return false;
      out        = m_queue[0];
      m_queue[0] = m_queue[--m_size];
      SiftDown(0);
      return true;
     }

   bool              Peek(PASREvent &out) const
     {
      if(m_size == 0) return false;
      out = m_queue[0];
      return true;
     }

   // Convenience: publish a simple event by ID
   bool              Publish(ENUM_EVENT_ID id, int prio = 50,
                             double d1 = 0, double d2 = 0)
     {
      PASREvent ev(id, prio, d1, d2);
      return Push(ev);
     }

   int               Size()  const { return m_size; }
   bool              Empty() const { return m_size == 0; }
   void              Clear()       { m_size = 0; }

   EventRecorder    *GetRecorder() { return &m_recorder; }
  };

// Alias for cleaner EA code
typedef PASREventBus CEventBus;

#endif // CORE_EVENT_BUS_MQH
