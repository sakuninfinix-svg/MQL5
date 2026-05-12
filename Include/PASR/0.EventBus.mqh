//+------------------------------------------------------------------+
//|                                                  0.EventBus.mqh  |
//|                                       Copyright 2026, Agsicentre |
//|            Event-Driven Core for PASR EA                         |
//|                 OPTIMIZED FOR HIGH PERFORMANCE                   |
//|                 VERSION 1.20 - ULTRA FAST                        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "1.20"

#ifndef __EVENT_BUS_MQH__
#define __EVENT_BUS_MQH__

#property strict

//--- Performance optimization: Pre-allocated handler pool
#define MAX_HANDLERS_PER_EVENT 16
#define MAX_EVENT_TYPES 32

//+------------------------------------------------------------------+
//| Base Event Class - OPTIMIZED V1.20                               |
//+------------------------------------------------------------------+
class Event
{
protected:
   datetime m_timestamp;
   int m_sourceId; // Use int instead of string for faster comparison

public:
   Event(const int sourceId = 0)
   {
      m_timestamp = TimeCurrent();
      m_sourceId = sourceId;
   }

   virtual ~Event() {}
   virtual int ID() const = 0;
   datetime Timestamp() const { return m_timestamp; }
   int SourceId() const { return m_sourceId; }

   virtual string Type() const = 0;
   virtual string Serialize() const { return ""; }
};

// Forward declaration for the recorder
class EventRecorder;
EventRecorder *g_recorder = NULL;

//+------------------------------------------------------------------+
//| Generic Event Handler Interface                                   |
//+------------------------------------------------------------------+
interface IEventHandler
{
public:
   virtual void HandleEvent(Event * e) = 0;
};

//+------------------------------------------------------------------+
//| Event Recorder (Debug Utility) - OPTIMIZED                       |
//+------------------------------------------------------------------+
class EventRecorder
{
private:
   struct RecordedEvent
   {
      datetime timestamp;
      int eventType; // Use int instead of string for faster comparison
      int sourceId;
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
      m_history[idx].eventType = e.ID();
      m_history[idx].sourceId = e.SourceId();
      // Skip serialization - store only essential data
   }

   int HistorySize() const { return ArraySize(m_history); }

   // Getter for Replay with bounds checking
   int GetHistoryType(int i)
   {
      if (i < 0 || i >= ArraySize(m_history))
         return 0;
      return m_history[i].eventType;
   }
   int GetHistorySourceId(int i)
   {
      if (i < 0 || i >= ArraySize(m_history))
         return 0;
      return m_history[i].sourceId;
   }
};

//+------------------------------------------------------------------+
//| Event Bus Singleton - OPTIMIZED                                  |
//| Uses direct array indexing for O(1) event lookup                 |
//+------------------------------------------------------------------+
class EventBus
{
private:
   static EventBus *m_instance;

   // Optimized: Direct array per event type instead of linear search
   struct HandlerRegistration
   {
      IEventHandler *handler;
      int priority;
   };
   
   HandlerRegistration m_handlersByType[MAX_EVENT_TYPES][];
   int m_handlerCount[MAX_EVENT_TYPES];

   EventBus() 
   {
      ArrayInitialize(m_handlerCount, 0);
   }

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

   // Register handler for specific event type - O(1) operation
   bool Subscribe(int eventID, IEventHandler *handler, int priority = 100)
   {
      if (handler == NULL || CheckPointer(handler) == POINTER_INVALID)
         return false;
      if (eventID < 0 || eventID >= MAX_EVENT_TYPES)
         return false;

      // Avoid duplicate subscriptions
      int total = m_handlerCount[eventID];
      HandlerRegistration &handlers[] = m_handlersByType[eventID];
      
      for (int i = 0; i < total; i++)
      {
         if (handlers[i].handler == handler)
            return false;
      }

      if (ArrayResize(handlers, total + 1) == -1)
         return false;

      handlers[total].handler = handler;
      handlers[total].priority = priority;
      m_handlerCount[eventID] = total + 1;

      return true;
   }

   // Unsubscribe handler - O(n) but rarely called
   void Unsubscribe(int eventID, IEventHandler *handler)
   {
      if (handler == NULL || CheckPointer(handler) == POINTER_INVALID)
         return;
      if (eventID < 0 || eventID >= MAX_EVENT_TYPES)
         return;

      int total = m_handlerCount[eventID];
      HandlerRegistration &handlers[] = m_handlersByType[eventID];
      
      for (int i = 0; i < total; i++)
      {
         if (handlers[i].handler == handler)
         {
            // Shift remaining handlers
            for (int j = i; j < total - 1; j++)
            {
               handlers[j] = handlers[j + 1];
            }
            ArrayResize(handlers, total - 1);
            m_handlerCount[eventID] = total - 1;
            return;
         }
      }
   }

   // Dispatch event - OPTIMIZED: No sorting, direct execution
   void Dispatch(Event *e)
   {
      if (e == NULL || CheckPointer(e) == POINTER_INVALID)
         return;

      bool isHeapAllocated = (CheckPointer(e) == POINTER_DYNAMIC);
      int id = e.ID();

      if (id < 0 || id >= MAX_EVENT_TYPES)
      {
         if (isHeapAllocated && CheckPointer(e) == POINTER_DYNAMIC)
            delete e;
         return;
      }

      int total = m_handlerCount[id];
      if (total == 0)
      {
         if (isHeapAllocated && CheckPointer(e) == POINTER_DYNAMIC)
            delete e;
         return;
      }

      HandlerRegistration &handlers[] = m_handlersByType[id];

      // Record event once before dispatching
      if (g_recorder != NULL && CheckPointer(g_recorder) != POINTER_INVALID && g_recorder.IsRecording())
      {
         g_recorder.Record(e);
      }

      // Execute handlers directly without sorting (priority handled by subscription order)
      for (int i = 0; i < total; i++)
      {
         IEventHandler *h = handlers[i].handler;
         if (h != NULL && CheckPointer(h) != POINTER_INVALID)
         {
            h.HandleEvent(e);
         }
      }

      // Clean up event memory only if it was heap-allocated
      if (isHeapAllocated && CheckPointer(e) == POINTER_DYNAMIC)
      {
         delete e;
      }
   }

   void Clear()
   {
      for (int i = 0; i < MAX_EVENT_TYPES; i++)
      {
         ArrayFree(m_handlersByType[i]);
         m_handlerCount[i] = 0;
      }
   }
};

inline void DispatchEvent(Event *e)
{
   EventBus::Instance().Dispatch(e);
}

// Initialize static members
EventBus *EventBus::m_instance = NULL;
Event *EventBus::m_eventPool[];
int EventBus::m_eventPoolSize = 0;
int EventBus::m_eventPoolIndex = 0;

#endif