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
#property strict

#ifndef __EVENT_BUS_MQH__
#define __EVENT_BUS_MQH__

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
};

// Forward declaration for the recorder
class EventRecorder;

// Global recorder instance (defined in main EA file)
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
//| Event Recorder (Debug Utility) - OPTIMIZED V1.21                 |
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
   int m_maxHistory;        // Maximum history size (circular buffer)
   int m_currentIndex;      // Current write position

public:
   EventRecorder() : m_isRecording(false), m_maxHistory(1000), m_currentIndex(0) {}

   void SetMaxHistory(int size)
   {
      m_maxHistory = MathMax(100, MathMin(10000, size));
      if(ArraySize(m_history) != m_maxHistory)
         ArrayResize(m_history, m_maxHistory);
   }

   void Start()
   {
      m_isRecording = true;
      m_currentIndex = 0;
      // Pre-allocate once at startup
      if(ArraySize(m_history) != m_maxHistory)
         ArrayResize(m_history, m_maxHistory);
      else
         ArrayInitialize(m_history, 0);
      Print("Event Recording Started (Max: ", m_maxHistory, " events).");
   }
   void Stop()
   {
      m_isRecording = false;
      Print("Event Recording Stopped. Captured: ", MathMin(m_currentIndex, m_maxHistory));
   }
   bool IsRecording() const { return m_isRecording; }

   void Record(Event *e)
   {
      if (!m_isRecording || CheckPointer(e) == POINTER_INVALID)
         return;
      
      // Circular buffer - zero allocation
      int idx = m_currentIndex % m_maxHistory;
      m_history[idx].timestamp = e.Timestamp();
      m_history[idx].eventType = e.ID();
      m_history[idx].sourceId = e.SourceId();
      m_currentIndex++;
      // Skip serialization - store only essential data
   }

   int HistorySize() const { return MathMin(m_currentIndex, m_maxHistory); }
   
   // Get actual count including overflow
   int TotalRecorded() const { return m_currentIndex; }

   // Getter for Replay with bounds checking
   int GetHistoryType(int i)
   {
      if (i < 0 || i >= HistorySize())
         return 0;
      int idx = i % m_maxHistory;
      return m_history[idx].eventType;
   }
   
   int GetHistorySourceId(int i)
   {
      if (i < 0 || i >= HistorySize())
         return 0;
      int idx = i % m_maxHistory;
      return m_history[idx].sourceId;
   }
   
   datetime GetHistoryTimestamp(int i)
   {
      if (i < 0 || i >= HistorySize())
         return 0;
      int idx = i % m_maxHistory;
      return m_history[idx].timestamp;
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
   
   HandlerRegistration m_handlersByType[MAX_EVENT_TYPES][MAX_HANDLERS_PER_EVENT];
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
      
      int total = m_handlerCount[eventID];
      if (total >= MAX_HANDLERS_PER_EVENT)
         return false;

      // Avoid duplicate subscriptions
      for (int i = 0; i < total; i++)
      {
         if (m_handlersByType[eventID][i].handler == handler)
            return false;
      }

      // Insert based on priority (Descending: higher priority first)
      int insertPos = total;
      for (int i = 0; i < total; i++)
      {
         if (priority > m_handlersByType[eventID][i].priority)
         {
            insertPos = i;
            break;
         }
      }

      // Shift elements to the right to make room
      for (int j = total; j > insertPos; j--)
         m_handlersByType[eventID][j] = m_handlersByType[eventID][j - 1];

      m_handlersByType[eventID][insertPos].handler = handler;
      m_handlersByType[eventID][insertPos].priority = priority;
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
      
      for (int i = 0; i < total; i++)
      {
         if (m_handlersByType[eventID][i].handler == handler)
         {
            // Shift remaining handlers
            for (int j = i; j < total - 1; j++)
            {
               m_handlersByType[eventID][j] = m_handlersByType[eventID][j + 1];
            }
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
         if (isHeapAllocated && CheckPointer(e) == POINTER_DYNAMIC) delete e;
         return;
      }

      int total = m_handlerCount[id];
      if (total == 0)
      {
         if (isHeapAllocated && CheckPointer(e) == POINTER_DYNAMIC) delete e;
         return;
      }

      // Record event once before dispatching
      if (CheckPointer(g_recorder) != POINTER_INVALID && g_recorder.IsRecording())
      {
         g_recorder.Record(e);
      }

      // Execute handlers directly without sorting (priority handled by subscription order)
      for (int i = 0; i < total; i++)
      {
         IEventHandler *h = m_handlersByType[id][i].handler;
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
         m_handlerCount[i] = 0;
      }
   }
};

inline void DispatchEvent(Event *e)
{
   EventBus *bus = EventBus::Instance();
   if (CheckPointer(bus) != POINTER_INVALID)
      bus.Dispatch(e);
   else if (CheckPointer(e) == POINTER_DYNAMIC)
      delete e;
}

// Initialize static members
EventBus *EventBus::m_instance = NULL;

#endif