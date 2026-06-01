//+------------------------------------------------------------------+
//| QA/MockEventBus.mqh — v1.00                                      |
//| Sprint 6 — S6-001: Stub EventBus for unit tests                 |
//|                                                                   |
//| PURPOSE:                                                          |
//|   Drop-in replacement for CEventBus that records all Push()      |
//|   calls instead of delivering them. Lets PipelineHarness fire    |
//|   synthetic events and verify which handlers were called,        |
//|   what events were dispatched, and in what order.                |
//|                                                                   |
//| USAGE:                                                            |
//|   CMockEventBus *bus = new CMockEventBus();                       |
//|   myManager.Initialize(bus);                                      |
//|   bus.InjectEvent(ev);          // fire directly to subscribers   |
//|   int n = bus.PushedCount();    // how many events were pushed     |
//|   PASREvent last = bus.LastEvent(); // last dispatched event       |
//|   bus.Reset();                  // clear history for next test     |
//+------------------------------------------------------------------+
#property strict
#ifndef __QA_MOCK_EVENT_BUS_MQH__
#define __QA_MOCK_EVENT_BUS_MQH__

#include "../Core/EventBus.mqh"
#include "../Core/Events.mqh"

#define MOCK_BUS_MAX_HISTORY  256

//+------------------------------------------------------------------+
//| CMockEventBus — Records events instead of delivering them        |
//+------------------------------------------------------------------+
class CMockEventBus : public CEventBus
  {
private:
   PASREvent     m_history[MOCK_BUS_MAX_HISTORY]; // Full push history
   int           m_history_head;                  // Next write index
   int           m_pushed_total;                  // Total pushed (no cap)
   bool          m_passthrough;                   // If true: also real-deliver

public:
              CMockEventBus(bool passthrough = false)
     : m_history_head(0), m_pushed_total(0), m_passthrough(passthrough)
     {
      Reset();
     }

   bool Push(const PASREvent &ev)
     {
      m_history[m_history_head % MOCK_BUS_MAX_HISTORY] = ev;
      m_history_head++;
      m_pushed_total++;

      if(m_passthrough)
         return CEventBus::Push(ev);
      return true;
     }

   void DispatchImmediate(const PASREvent &ev)
     {
      Push(ev);
      if(m_passthrough)
         CEventBus::DispatchImmediate(ev);
     }

   //--- Inject event directly to all subscribers (bypass history)
   //    Use this to simulate incoming events FROM external system
   void InjectEvent(const PASREvent &ev)
     {
      CEventBus::DispatchImmediate(ev);
     }

   //--- Accessors ---------------------------------------------------
   int           PushedCount()    const { return m_pushed_total; }
   bool          HasEvents()      const { return m_pushed_total > 0; }

   PASREvent     LastEvent() const
     {
      if(m_pushed_total == 0) { PASREvent empty; return empty; }
      int idx = (m_history_head - 1 + MOCK_BUS_MAX_HISTORY)
                % MOCK_BUS_MAX_HISTORY;
      return m_history[idx];
     }

   bool          GetHistory(int i, PASREvent &ev) const
     {
      if(i < 0 || i >= MathMin(m_pushed_total, MOCK_BUS_MAX_HISTORY))
         return false;
      ev = m_history[i % MOCK_BUS_MAX_HISTORY];
      return true;
     }

   //--- Find first event with given id in history
   bool          FindEvent(ENUM_EVENT_ID ev_id, PASREvent &ev) const
     {
      int cap = MathMin(m_pushed_total, MOCK_BUS_MAX_HISTORY);
      for(int i = 0; i < cap; i++)
        {
         if(m_history[i].id == ev_id) { ev = m_history[i]; return true; }
        }
      return false;
     }

   //--- Count events with specific id
   int           CountEvents(ENUM_EVENT_ID ev_id) const
     {
      int cap   = MathMin(m_pushed_total, MOCK_BUS_MAX_HISTORY);
      int count = 0;
      for(int i = 0; i < cap; i++)
         if(m_history[i].id == ev_id) count++;
      return count;
     }

   //--- Reset: clear history for next test case
   void Reset()
     {
      m_history_head = 0;
      m_pushed_total = 0;
      for(int i = 0; i < MOCK_BUS_MAX_HISTORY; i++)
        {
         PASREvent empty;
         m_history[i] = empty;
        }
      // DO NOT reset subscribers — keep manager registrations intact
     }
  };

#endif // __QA_MOCK_EVENT_BUS_MQH__
