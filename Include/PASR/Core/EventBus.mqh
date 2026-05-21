//+------------------------------------------------------------------+
//| Core/EventBus.mqh — CANONICAL v2.15                              |
//| Priority-queue event bus + subscriber registry + dispatch        |
//|                                                                  |
//| CHANGES v2.15 (2026-05-21):                                      |
//|   FIX #1  — Add Register(IManager*) + subscriber registry       |
//|   FIX #1  — Add Dispatch(PASREvent&) routed to subscribers       |
//|   FIX #8  — Dispatch() honours each subscriber's event mask     |
//|             (set via IManager::AddEvent in DeclareEvents())      |
//|                                                                  |
//| INVARIANTS:                                                      |
//|   - Push()     : enqueue into min-heap (priority order)         |
//|   - Pop()      : dequeue from min-heap (for DrainQueue pattern) |
//|   - Dispatch() : broadcast to all registered subscribers whose  |
//|                  event mask includes the event id               |
//|   - Register() : add subscriber once (idempotent on same ptr)   |
//+------------------------------------------------------------------+
#pragma once
#ifndef CORE_EVENT_BUS_MQH
#define CORE_EVENT_BUS_MQH

#include "Events.mqh"

// Forward declaration — full definition in IManager.mqh
class IManager;

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
//| PASREventBus — array-backed min-heap + subscriber registry       |
//+------------------------------------------------------------------+
#define PASR_BUS_MAX_EVENTS      64
#define PASR_BUS_MAX_SUBSCRIBERS 16

class PASREventBus
  {
private:
   // ── Min-heap queue ────────────────────────────────────────────
   PASREvent         m_queue[PASR_BUS_MAX_EVENTS];
   int               m_size;
   EventRecorder     m_recorder;

   // ── Subscriber registry (FIX #1) ─────────────────────────────
   IManager         *m_subscribers[PASR_BUS_MAX_SUBSCRIBERS];
   int               m_subCount;

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
   PASREventBus() : m_size(0), m_subCount(0)
     {
      ArrayInitialize(m_subscribers, 0);
     }

   // ── Min-heap operations (unchanged) ──────────────────────────

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

   // ── Subscriber registry (FIX #1 + FIX #8) ────────────────────
   // Register a manager as subscriber. Idempotent — duplicate ptrs ignored.
   // Called by Orchestrator::RegisterManager() for every manager.
   bool              Register(IManager *mgr)
     {
      if(mgr == NULL) return false;
      // Idempotent: skip if already registered
      for(int i = 0; i < m_subCount; i++)
         if(m_subscribers[i] == mgr) return true;
      if(m_subCount >= PASR_BUS_MAX_SUBSCRIBERS)
        {
         Print("[EventBus][WARN] Subscriber limit reached — dropping ", (ulong)mgr);
         return false;
        }
      m_subscribers[m_subCount++] = mgr;
      return true;
     }

   // Dispatch an event directly to all subscribers whose event mask
   // includes this event id (FIX #1 + FIX #8).
   // This is the BROADCAST path used by DrainQueue() in Orchestrator.
   void              Dispatch(const PASREvent &ev)
     {
      for(int i = 0; i < m_subCount; i++)
        {
         IManager *mgr = m_subscribers[i];
         if(mgr == NULL) continue;
         // FIX #8: honour declared-event mask filter
         if(!mgr.IsListening(ev.id)) continue;

         switch(ev.id)
           {
            case EVENT_ID_NEW_BAR:              mgr.OnNewBar();      break;
            case EVENT_ID_PRICE_UPDATE:         mgr.OnPriceUpdate(); break;
            case EVENT_ID_TRADE_CLOSED:         /* handled by specific managers */ break;
            case EVENT_ID_TIMER:                /* handled by specific managers */ break;
            case EVENT_ID_CONFIG_RELOAD:        mgr.OnConfigReload(); break;
            case EVENT_ID_RECOVERY_OPPORTUNITY: /* handled by RecoveryManager */  break;
            case EVENT_ID_EMERGENCY_STOP:       /* handled by ExecutionManager */ break;
            case EVENT_ID_AI_TRAIN:             /* handled by AIManager */        break;
            default:                            break;
           }
        }
     }
  };

// Alias for cleaner EA code
typedef PASREventBus CEventBus;

//+------------------------------------------------------------------+
//| ProcessDeferredEvents — Process queued events from timer         |
//+------------------------------------------------------------------+
// This method is called from OnTimer() to process deferred events
// that were queued during tick processing. It drains the priority
// queue and dispatches each event to registered subscribers.
void ProcessDeferredEvents()
  {
   CEventBus *bus = CEventBus::Instance();
   if(CheckPointer(bus) == POINTER_INVALID) return;
   
   // Drain the queue by popping and dispatching each event
   PASREvent ev;
   while(bus.Pop(ev))
     {
      bus.Dispatch(ev);
     }
  }

#endif // CORE_EVENT_BUS_MQH
