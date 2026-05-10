//+------------------------------------------------------------------+
//|                                                  0.EventBus.mqh  |
//|                                       Copyright 2026, Agsicentre |
//|            Event-Driven Core for PASR EA                         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "1.00"

#ifndef __EVENT_BUS_MQH__
#define __EVENT_BUS_MQH__

#property strict

//+------------------------------------------------------------------+
//| Base Event Class                                                 |
//+------------------------------------------------------------------+
class Event
{
protected:
   datetime m_timestamp;
   string m_source;

public:
   Event(const string source = "UNKNOWN")
   {
      m_timestamp = TimeCurrent();
      m_source = source;
   }

   virtual ~Event() {}
   virtual int ID() const = 0; // Required for static dispatch
   datetime Timestamp() const { return m_timestamp; }
   string Source() const { return m_source; }

   // Pure virtual: must be implemented by child classes
   virtual string Type() const = 0;

   // Virtual serialization for recording
   virtual string Serialize() const { return ""; }
};

// Forward declaration for the recorder
class EventRecorder;
extern EventRecorder *g_recorder;

//+------------------------------------------------------------------+
//| Generic Event Handler Interface                                   |
//+------------------------------------------------------------------+
interface IEventHandler
{
public:
   virtual void HandleEvent(Event * e) = 0;
};

//+------------------------------------------------------------------+
//| Event Recorder (Debug Utility)                                   |
//+------------------------------------------------------------------+
class EventRecorder
{
private:
   struct RecordedEvent
   {
      datetime timestamp;
      string type;
      string data;
   };

   RecordedEvent m_history[];
   bool m_isRecording;

public:
   EventRecorder() : m_isRecording(false) {}

   void Start()
   {
      m_isRecording = true;
      ArrayFree(m_history);
      Print("Event Recording Started.");
   }
   void Stop()
   {
      m_isRecording = false;
      Print("Event Recording Stopped. Total: ", ArraySize(m_history));
   }
   bool IsRecording() const { return m_isRecording; }

   void Record(Event *e)
   {
      if (!m_isRecording || CheckPointer(e) == POINTER_INVALID)
         return;
      int idx = ArraySize(m_history);
      ArrayResize(m_history, idx + 1);
      m_history[idx].timestamp = e.Timestamp();
      m_history[idx].type = e.Type();
      m_history[idx].data = e.Serialize();
   }

   int HistorySize() const { return ArraySize(m_history); }

   // Getter for Replay (implemented where events are defined)
   string GetHistoryType(int i) { return m_history[i].type; }
   string GetHistoryData(int i) { return m_history[i].data; }
};

//+------------------------------------------------------------------+
//| Event Bus Singleton                                              |
//+------------------------------------------------------------------+
class EventBus
{
private:
   static EventBus *m_instance;

   struct HandlerRegistration
   {
      int eventID;
      IEventHandler *handler;
      int priority;
   };

   HandlerRegistration m_registrations[];

   EventBus() {}

public:
   ~EventBus() { Clear(); }

   static EventBus *Instance()
   {
      if (m_instance == NULL)
         m_instance = new EventBus();
      return m_instance;
   }

   static void Release()
   {
      if (m_instance != NULL)
      {
         delete m_instance;
         m_instance = NULL;
      }
   }

   // Register handler for specific event type
   bool Subscribe(int eventID, IEventHandler *handler, int priority = 100)
   {
      if (CheckPointer(handler) == POINTER_INVALID)
         return false;

      // Avoid duplicate subscriptions
      int total = ArraySize(m_registrations);
      for (int i = 0; i < total; i++)
      {
         if (m_registrations[i].eventID == eventID && m_registrations[i].handler == handler)
            return false;
      }

      ArrayResize(m_registrations, total + 1);
      m_registrations[total].eventID = eventID;
      m_registrations[total].handler = handler;
      m_registrations[total].priority = priority;

      return true;
   }

   // Unsubscribe handler
   void Unsubscribe(int eventID, IEventHandler *handler)
   {
      int total = ArraySize(m_registrations);
      for (int i = 0; i < total; i++)
      {
         if (m_registrations[i].eventID == eventID && m_registrations[i].handler == handler)
         {
            for (int j = i; j < total - 1; j++)
            {
               m_registrations[j] = m_registrations[j + 1];
            }
            ArrayResize(m_registrations, total - 1);
            return;
         }
      }
   }

   // Dispatch event to all subscribed handlers
   void Dispatch(Event *e)
   {
      if (CheckPointer(e) == POINTER_INVALID)
         return;

      int id = e.ID();
      int total = ArraySize(m_registrations);

      // Collect and sort matches by priority
      int matches[];
      for (int i = 0; i < total; i++)
      {
         if (m_registrations[i].eventID == id)
         {
            int mSize = ArraySize(matches);
            ArrayResize(matches, mSize + 1);
            matches[mSize] = i;
         }
      }

      // Simple priority sort (Bubble Sort)
      int matchCount = ArraySize(matches);
      for (int i = 0; i < matchCount - 1; i++)
      {
         for (int j = 0; j < matchCount - i - 1; j++)
         {
            if (m_registrations[matches[j]].priority > m_registrations[matches[j + 1]].priority)
            {
               int temp = matches[j];
               matches[j] = matches[j + 1];
               matches[j + 1] = temp;
            }
         }
      }

      // Record event once before dispatching to subscribers
      if (matchCount > 0 && CheckPointer(g_recorder) != POINTER_INVALID && g_recorder.IsRecording())
      {
         g_recorder.Record(e);
      }

      // Execute handlers
      for (int i = 0; i < matchCount; i++)
      {
         IEventHandler *h = m_registrations[matches[i]].handler;
         if (CheckPointer(h) != POINTER_INVALID)
         {
            h.HandleEvent(e);
         }
      }

      // Clean up event memory after dispatch
      if (CheckPointer(e) == POINTER_DYNAMIC)
         delete e;
   }

   void Clear()
   {
      ArrayFree(m_registrations);
   }
};

inline void DispatchEvent(Event *e)
{
   EventBus::Instance().Dispatch(e);
}

// Initialize static member
EventBus *EventBus::m_instance = NULL;

#endif