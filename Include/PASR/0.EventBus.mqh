//+------------------------------------------------------------------+
//|                                                  0.EventBus.mqh  |
//|                                       Copyright 2026, Agsicentre |
//|            Event-Driven Core for PASR EA                         |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "1.30"
#property strict

#ifndef __EVENT_BUS_MQH__
#define __EVENT_BUS_MQH__

//--- Performance optimization: Pre-allocated handler pool
#define MAX_HANDLERS_PER_EVENT 16
#define MAX_EVENT_TYPES 32

//+------------------------------------------------------------------+
//| Event Priority Groups - OPTIMIZATION V1.30                       |
//+------------------------------------------------------------------+
#define EVENT_PRIORITY_CRITICAL  0      // Emergency stops
#define EVENT_PRIORITY_HIGH     50      // Price updates, new bars
#define EVENT_PRIORITY_NORMAL   100     // Heartbeats, config changes
#define EVENT_PRIORITY_LOW      150     // UI updates, logging

// Priority validation macros
#define IS_CRITICAL_PRIORITY(p)  ((p) >= 0 && (p) <= 10)
#define IS_HIGH_PRIORITY(p)      ((p) > 10 && (p) <= 50)
#define IS_NORMAL_PRIORITY(p)    ((p) > 50 && (p) <= 100)
#define IS_LOW_PRIORITY(p)       ((p) > 100 && (p) <= 200)

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
   uint m_currentIndex;     // Current write position

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
      m_currentIndex = 0; // Reset counter agar rekaman dimulai dari index 0

      // Pre-allocate once at startup
      if(ArraySize(m_history) != m_maxHistory)
         ArrayResize(m_history, m_maxHistory);

      for(int i = 0; i < ArraySize(m_history); i++)
      {
         m_history[i].timestamp = 0;
         m_history[i].eventType = 0;
         m_history[i].sourceId = 0;
      }
      Print("Event Recording Started (Max: ", m_maxHistory, " events).");
   }
   void Stop()
   {
      m_isRecording = false;
      Print("Event Recording Stopped. Captured: ", MathMin((int)m_currentIndex, m_maxHistory));
   }
   bool IsRecording() const { return m_isRecording; }

   void Record(Event *e)
   {
      if (!m_isRecording || CheckPointer(e) == POINTER_INVALID)
         return;

      // Circular buffer - zero allocation
      uint idx = m_currentIndex % (uint)m_maxHistory;
      m_history[idx].timestamp = e.Timestamp();
      m_history[idx].eventType = e.ID();
      m_history[idx].sourceId = e.SourceId();
      m_currentIndex++;
      // Skip serialization - store only essential data
   }

   int HistorySize() const { return MathMin((int)m_currentIndex, m_maxHistory); }

   // Get actual count including overflow
   uint TotalRecorded() const { return m_currentIndex; }

   // Getter for Replay with bounds checking
   // Index 0 always returns the oldest available event
   int GetHistoryType(int i)
   {
      int size = HistorySize();
      if (i < 0 || i >= size)
         return 0;
      uint startOffset = (m_currentIndex >= (uint)m_maxHistory) ? (m_currentIndex % (uint)m_maxHistory) : 0;
      uint idx = (startOffset + (uint)i) % (uint)m_maxHistory;
      return m_history[(int)idx].eventType;
   }

   int GetHistorySourceId(int i)
   {
      int size = HistorySize();
      if (i < 0 || i >= size)
         return 0;
      uint startOffset = (m_currentIndex >= (uint)m_maxHistory) ? (m_currentIndex % (uint)m_maxHistory) : 0;
      uint idx = (startOffset + (uint)i) % (uint)m_maxHistory;
      return m_history[(int)idx].sourceId;
   }

   datetime GetHistoryTimestamp(int i)
   {
      int size = HistorySize();
      if (i < 0 || i >= size)
         return 0;
      uint startOffset = (m_currentIndex >= (uint)m_maxHistory) ? (m_currentIndex % (uint)m_maxHistory) : 0;
      uint idx = (startOffset + (uint)i) % (uint)m_maxHistory;
      return m_history[(int)idx].timestamp;
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
   // OPTIMIZATION V1.30: Added priority validation and warnings
   bool Subscribe(int eventID, IEventHandler *handler, int priority = EVENT_PRIORITY_NORMAL)
   {
      if (handler == NULL || CheckPointer(handler) == POINTER_INVALID)
         return false;
      if (eventID < 0 || eventID >= MAX_EVENT_TYPES)
         return false;
      
      // Priority validation with warnings for critical events
      #ifdef __DEBUG__
      if (eventID == 5 && !IS_CRITICAL_PRIORITY(priority)) // EVENT_ID_EMERGENCY_STOP is 5
         Print("WARNING: Emergency stop event should have CRITICAL priority (0-10). Current: ", priority);
      if (eventID == 1 && !IS_HIGH_PRIORITY(priority)) // EVENT_ID_PRICE_UPDATE is 1
         Print("WARNING: Price update event should have HIGH priority (11-50). Current: ", priority);
      #endif

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
      int insertPos = total; // Default to end
      for (int i = 0; i < total; i++)
      {
         // Perbaikan: Urutkan Ascending (Nilai angka kecil/Kritis dieksekusi lebih dulu)
         if (priority < m_handlersByType[eventID][i].priority)
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
   // OPTIMIZATION V1.30: Added batch dispatch support for high-frequency events
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
   
   // 
   // Reduces overhead when firing multiple events of same type
   void DispatchBatch(int eventID, Event *&events[], int count)
   {
      if (count <= 0)
         return;
      if (eventID < 0 || eventID >= MAX_EVENT_TYPES)
         return;
      
      int total = m_handlerCount[eventID];
      if (total == 0)
      {
         // Clean up all events if no handlers
         for (int i = 0; i < count; i++)
         {
            if (events[i] != NULL && CheckPointer(events[i]) == POINTER_DYNAMIC)
            {
               delete events[i];
               events[i] = NULL;
            }
         }
         return;
      }
      
      // Process each event through all handlers
      for (int e = 0; e < count; e++)
      {
         if (events[e] == NULL || CheckPointer(events[e]) == POINTER_INVALID)
            continue;
            
         bool isHeapAllocated = (CheckPointer(events[e]) == POINTER_DYNAMIC);
         
         // Record event
         if (CheckPointer(g_recorder) != POINTER_INVALID && g_recorder.IsRecording())
         {
            g_recorder.Record(events[e]);
         }
         
         // Execute all handlers for this event
         for (int i = 0; i < total; i++)
         {
            IEventHandler *h = m_handlersByType[eventID][i].handler;
            if (h != NULL && CheckPointer(h) != POINTER_INVALID)
            {
               h.HandleEvent(events[e]);
            }
         }
         
         // Clean up if heap-allocated
         if (isHeapAllocated && CheckPointer(events[e]) == POINTER_DYNAMIC)
         {
            delete events[e];
            events[e] = NULL;
         }
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