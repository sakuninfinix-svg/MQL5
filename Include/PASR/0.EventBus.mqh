//+------------------------------------------------------------------+
//|                                                  0.EventBus.mqh  |
//|                                       Copyright 2026, Agsicentre |
//|            Event-Driven Core for PASR EA - V1.31 (PATCHED)        |
//|                                                                  |
//| FEATURES:                                                        |
//| - Safe memory management with auto-cleanup                       |
//| - Re-entrancy protection (dispatch guard)                        |
//| - Priority-based event execution                                 |
//| - Optional deferred processing via OnTimer                       |
//| - Event groups for wildcard subscriptions                        |
//| - Structured debug logging with performance metrics              |
//| - Error handling per handler                                     |
//| - Hybrid ID system (int for perf, string for debug)              |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "1.31"
#property strict

#ifndef __EVENT_BUS_MQH__
#define __EVENT_BUS_MQH__

//--- Performance optimization: Pre-allocated handler pool
#define MAX_HANDLERS_PER_EVENT 16
#define MAX_EVENT_TYPES 32
#define MAX_EVENT_GROUPS 8
#define MAX_DEFERRED_EVENTS 100

//--- Event Priority Groups - OPTIMIZATION V1.30
#define EVENT_PRIORITY_CRITICAL  0      // Emergency stops
#define EVENT_PRIORITY_HIGH     50      // Price updates, new bars
#define EVENT_PRIORITY_NORMAL   100     // Heartbeats, config changes
#define EVENT_PRIORITY_LOW      150     // UI updates, logging

// Priority validation macros
#define IS_CRITICAL_PRIORITY(p)  ((p) >= 0 && (p) <= 10)
#define IS_HIGH_PRIORITY(p)      ((p) > 10 && (p) <= 50)
#define IS_NORMAL_PRIORITY(p)    ((p) > 50 && (p) <= 100)
#define IS_LOW_PRIORITY(p)       ((p) > 100 && (p) <= 200)

//--- Event Group Flags for Wildcard Subscriptions
#define EVENT_GROUP_NONE        0
#define EVENT_GROUP_MARKET      1      // Price, bar, tick events
#define EVENT_GROUP_SIGNAL      2      // Signal generation events
#define EVENT_GROUP_ORDER       4      // Order/position events
#define EVENT_GROUP_SYSTEM      8      // Config, heartbeat, emergency
#define EVENT_GROUP_ALL         0xFFFF // Subscribe to all events

//--- Debug Logging Control
#ifdef __DEBUG__
   #define EVENT_LOG_LEVEL_VERBOSE  0
   #define EVENT_LOG_LEVEL_INFO     1
   #define EVENT_LOG_LEVEL_WARNING  2
   #define EVENT_LOG_LEVEL_ERROR    3
   #define EVENT_LOG_CURRENT_LEVEL  EVENT_LOG_LEVEL_VERBOSE
#else
   #define EVENT_LOG_CURRENT_LEVEL  EVENT_LOG_LEVEL_ERROR
#endif

#define LOG_EVENT(level, msg) \
   if(level >= EVENT_LOG_CURRENT_LEVEL) Print("[EventBus] ", msg)

//+------------------------------------------------------------------+
//| Base Event Class - OPTIMIZED V1.31                               |
//| Added: group flags, event name for debug, cancellation support   |
//+------------------------------------------------------------------+
class Event
{
protected:
   datetime m_timestamp;
   int m_sourceId;
   int m_group;              // Event group for wildcard subscriptions
   string m_name;            // Event name for debug logging
   bool m_cancelled;         // Cancellation flag for emergency scenarios

public:
   Event(const int sourceId = 0, const int group = EVENT_GROUP_NONE, const string name = "")
   {
      m_timestamp = TimeCurrent();
      m_sourceId = sourceId;
      m_group = group;
      m_name = name;
      m_cancelled = false;
   }

   virtual ~Event() {}
   virtual int ID() const = 0;
   datetime Timestamp() const { return m_timestamp; }
   int SourceId() const { return m_sourceId; }
   int Group() const { return m_group; }
   string Name() const { return m_name; }
   
   void Cancel() { m_cancelled = true; }
   bool IsCancelled() const { return m_cancelled; }
};

// Forward declaration for the recorder
class EventRecorder;

// Global recorder instance (defined in main EA file)
extern EventRecorder *g_recorder;

//+------------------------------------------------------------------+
//| Generic Event Handler Base Class - V1.31 (PATCHED)               |
//| PATCH: Converted from 'interface' to 'class'.                    |
//| MQL5 'interface' keyword does NOT allow method bodies.            |
//| Using abstract class with pure virtual + default implementations. |
//+------------------------------------------------------------------+
class IEventHandler
{
public:
   virtual void HandleEvent(Event *e) = 0;
   
   virtual void OnHandlerError(int eventId, string errorMsg)
   {
      LOG_EVENT(EVENT_LOG_LEVEL_ERROR, "Handler error on event " + IntegerToString(eventId) + ": " + errorMsg);
   }
   
   virtual string GetHandlerName() const
   {
      return "UnknownHandler";
   }
   
   virtual ~IEventHandler() {}
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
//| Event Bus Singleton - OPTIMIZED V1.31                            |
//| Uses direct array indexing for O(1) event lookup                 |
//| Added: Re-entrancy guard, wildcard subscriptions, debug logging  |
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
      int groupFlags;  // Event groups this handler subscribes to
   };

   HandlerRegistration m_handlersByType[MAX_EVENT_TYPES][MAX_HANDLERS_PER_EVENT];
   int m_handlerCount[MAX_EVENT_TYPES];
   
   // Re-entrancy protection
   bool m_isDispatching;
   int m_dispatchDepth;
   
   // Deferred event queue (for OnTimer processing)
   struct DeferredEvent
   {
      int eventID;
      Event *eventPtr;
      bool isPending;
   };
   DeferredEvent m_deferredQueue[MAX_DEFERRED_EVENTS];
   int m_deferredCount;
   bool m_deferredEnabled;
   
   // Performance metrics
   ulong m_totalDispatches;
   ulong m_totalHandlersCalled;
   datetime m_lastResetTime;

   EventBus()
   {
      ArrayInitialize(m_handlerCount, 0);
      m_isDispatching = false;
      m_dispatchDepth = 0;
      m_deferredCount = 0;
      m_deferredEnabled = false;
      m_totalDispatches = 0;
      m_totalHandlersCalled = 0;
      m_lastResetTime = TimeCurrent();
      
      // Initialize deferred queue
      for(int i = 0; i < MAX_DEFERRED_EVENTS; i++)
         m_deferredQueue[i].isPending = false;
   }

public:
   ~EventBus() 
   { 
      Clear(); 
      LOG_EVENT(EVENT_LOG_LEVEL_INFO, "EventBus destroyed");
   }

   static EventBus *Instance()
   {
      if (m_instance == NULL)
         m_instance = new EventBus();
      return m_instance;
   }

   static void Destroy()
   {
      if (m_instance != NULL)
      {
         delete m_instance;
         m_instance = NULL;
      }
   }

   // Subscribe handler to specific event type
   // Returns false if slot is full or handler already registered
   bool Subscribe(int eventID, IEventHandler *handler, int priority = EVENT_PRIORITY_NORMAL, int groupFlags = EVENT_GROUP_NONE)
   {
      if (handler == NULL || CheckPointer(handler) == POINTER_INVALID)
         return false;
      if (eventID < 0 || eventID >= MAX_EVENT_TYPES)
         return false;

      int total = m_handlerCount[eventID];
      if (total >= MAX_HANDLERS_PER_EVENT)
         return false;

      // Check for duplicate registration
      for (int i = 0; i < total; i++)
      {
         if (m_handlersByType[eventID][i].handler == handler)
            return false;
      }

      // Insert based on priority (Ascending: lower value = higher priority = executed first)
      int insertPos = total; // Default to end
      for (int i = 0; i < total; i++)
      {
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
      m_handlersByType[eventID][insertPos].groupFlags = groupFlags;
      m_handlerCount[eventID] = total + 1;
      
      LOG_EVENT(EVENT_LOG_LEVEL_VERBOSE, "Subscribed handler to event " + IntegerToString(eventID) + 
                " (priority=" + IntegerToString(priority) + ", groups=" + IntegerToString(groupFlags) + ")");
      
      return true;
   }
   
   // Wildcard subscription: subscribe to all events in a group
   // PATCH: Added per-slot capacity guard to prevent overflow
   bool SubscribeToGroup(int groupFlag, IEventHandler *handler, int priority = EVENT_PRIORITY_NORMAL)
   {
      if (handler == NULL || CheckPointer(handler) == POINTER_INVALID)
         return false;
      if (groupFlag == EVENT_GROUP_NONE)
         return false;
         
      // WARNING: Subscribes handler to ALL MAX_EVENT_TYPES slots.
      // Each consumes one entry from MAX_HANDLERS_PER_EVENT (16 max per slot).
      int subscribed = 0;
      for (int i = 0; i < MAX_EVENT_TYPES; i++)
      {
         if (m_handlerCount[i] < MAX_HANDLERS_PER_EVENT)
         {
            if (Subscribe(i, handler, priority, groupFlag))
               subscribed++;
         }
      }
      
      LOG_EVENT(EVENT_LOG_LEVEL_INFO, "Wildcard subscription to group " + IntegerToString(groupFlag) + 
                " completed (" + IntegerToString(subscribed) + " events)");
      return subscribed > 0;
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

   // Dispatch event - OPTIMIZED V1.31
   // Added: Re-entrancy guard, error handling per handler, cancellation check
   void Dispatch(Event *e)
   {
      if (e == NULL || CheckPointer(e) == POINTER_INVALID)
         return;

      bool isHeapAllocated = (CheckPointer(e) == POINTER_DYNAMIC);
      int id = e.ID();

      if (id < 0 || id >= MAX_EVENT_TYPES)
      {
         LOG_EVENT(EVENT_LOG_LEVEL_ERROR, "Invalid event ID: " + IntegerToString(id));
         if (isHeapAllocated && CheckPointer(e) == POINTER_DYNAMIC) delete e;
         return;
      }
      
      // Check if event was cancelled before dispatching
      if (e.IsCancelled())
      {
         LOG_EVENT(EVENT_LOG_LEVEL_VERBOSE, "Event " + IntegerToString(id) + " cancelled, skipping dispatch");
         if (isHeapAllocated && CheckPointer(e) == POINTER_DYNAMIC) delete e;
         return;
      }

      int total = m_handlerCount[id];
      if (total == 0)
      {
         if (isHeapAllocated && CheckPointer(e) == POINTER_DYNAMIC) delete e;
         return;
      }
      
      // Re-entrancy protection
      m_isDispatching = true;
      m_dispatchDepth++;
      
      ulong startTime = GetMicrosecondCount();
      int handlersCalled = 0;
      int errorsHandled = 0;

      // Record event once before dispatching
      if (CheckPointer(g_recorder) != POINTER_INVALID && g_recorder.IsRecording())
      {
         g_recorder.Record(e);
      }

      // Execute handlers with error handling and cancellation check
      for (int i = 0; i < total; i++)
      {
         // Check if event was cancelled during dispatch
         if (e.IsCancelled())
         {
            LOG_EVENT(EVENT_LOG_LEVEL_WARNING, "Event " + IntegerToString(id) + 
                      " cancelled during dispatch after " + IntegerToString(handlersCalled) + " handlers");
            break;
         }
         
         IEventHandler *h = m_handlersByType[id][i].handler;
         if (h != NULL && CheckPointer(h) != POINTER_INVALID)
         {
            // PATCH: ResetLastError() sets error to 0, so preErrorCount was always 0 - useless.
            // Correct pattern: reset, call, then check postError directly.
            ResetLastError();
            h.HandleEvent(e);
            int postErrorCount = GetLastError();
            if (postErrorCount != 0)
            {
               errorsHandled++;
               string handlerName = (CheckPointer(h) != POINTER_INVALID) ? h.GetHandlerName() : "Unknown";
               LOG_EVENT(EVENT_LOG_LEVEL_ERROR, "Error in handler [" + handlerName + "] for event " + IntegerToString(id) + ": Error " + IntegerToString(postErrorCount));
               h.OnHandlerError(id, "Error " + IntegerToString(postErrorCount));
               ResetLastError();
            }
            handlersCalled++;
         }
      }
      
      // Update metrics
      m_totalDispatches++;
      m_totalHandlersCalled += (ulong)handlersCalled;
      
      // Log performance for slow dispatches (>1ms)
      #ifdef __DEBUG__
      ulong elapsed = GetMicrosecondCount() - startTime;
      if (elapsed > 1000)
      {
         LOG_EVENT(EVENT_LOG_LEVEL_WARNING, "Slow dispatch: event " + IntegerToString(id) + 
                   " took " + DoubleToString(elapsed / 1000.0, 2) + "ms (" + 
                   IntegerToString(handlersCalled) + " handlers, " + 
                   IntegerToString(errorsHandled) + " errors)");
      }
      #endif
      
      m_dispatchDepth--;
      if (m_dispatchDepth == 0)
         m_isDispatching = false;

      // Clean up event memory only if it was heap-allocated
      if (isHeapAllocated && CheckPointer(e) == POINTER_DYNAMIC)
      {
         delete e;
      }
   }
   
   // Batch dispatch - PATCHED V1.31: added re-entrancy guard + metrics update + error handling
   // Reduces overhead when firing multiple events of same type
   void DispatchBatch(int eventID, Event *&events[], int count)
   {
      if (count <= 0)
         return;
      if (eventID < 0 || eventID >= MAX_EVENT_TYPES)
      {
         // Clean up all events on invalid ID
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
      
      m_isDispatching = true;
      m_dispatchDepth++;
      
      ulong startTime = GetMicrosecondCount();
      int handlersCalled = 0;
      int errorsHandled = 0;
      
      // Process each event through all handlers
      for (int e = 0; e < count; e++)
      {
         if (events[e] == NULL || CheckPointer(events[e]) == POINTER_INVALID)
            continue;
            
         bool isHeapAllocated = (CheckPointer(events[e]) == POINTER_DYNAMIC);
         bool eventCancelled = false;
         
         // Record event once before dispatching
         if (CheckPointer(g_recorder) != POINTER_INVALID && g_recorder.IsRecording())
         {
            g_recorder.Record(events[e]);
         }
         
         // Execute all handlers for this event with error handling
         for (int i = 0; i < total; i++)
         {
            // Check cancellation flag (if event supports it)
            if (events[e].IsCancelled())
            {
               eventCancelled = true;
               LOG_EVENT(EVENT_LOG_LEVEL_WARNING, "Event " + IntegerToString(eventID) + 
                         " cancelled during batch dispatch after " + IntegerToString(i) + " handlers");
               break;
            }
            
            IEventHandler *h = m_handlersByType[eventID][i].handler;
            if (h != NULL && CheckPointer(h) != POINTER_INVALID)
            {
               ResetLastError();
               h.HandleEvent(events[e]);
               int postErrorCount = GetLastError();
               if (postErrorCount != 0)
               {
                  errorsHandled++;
                  string handlerName = (CheckPointer(h) != POINTER_INVALID) ? h.GetHandlerName() : "Unknown";
                  LOG_EVENT(EVENT_LOG_LEVEL_ERROR, "Error in handler [" + handlerName + "] for batch event " + IntegerToString(eventID) + ": Error " + IntegerToString(postErrorCount));
                  h.OnHandlerError(eventID, "Error " + IntegerToString(postErrorCount));
                  ResetLastError();
               }
               handlersCalled++;
            }
         }
         
         // Clean up if heap-allocated (always, regardless of cancellation)
         if (isHeapAllocated && CheckPointer(events[e]) == POINTER_DYNAMIC)
         {
            delete events[e];
            events[e] = NULL;
         }
      }
      
      // Update metrics
      m_totalDispatches += (ulong)count;
      m_totalHandlersCalled += (ulong)handlersCalled;
      
      // Log performance for slow batch dispatches (>2ms)
      #ifdef __DEBUG__
      ulong elapsed = GetMicrosecondCount() - startTime;
      if (elapsed > 2000)
      {
         LOG_EVENT(EVENT_LOG_LEVEL_WARNING, "Slow batch dispatch: event " + IntegerToString(eventID) + 
                   " took " + DoubleToString(elapsed / 1000.0, 2) + "ms (" + 
                   IntegerToString(count) + " events, " + IntegerToString(handlersCalled) + " handlers, " + 
                   IntegerToString(errorsHandled) + " errors)");
      }
      #endif
      
      m_dispatchDepth--;
      if(m_dispatchDepth == 0) m_isDispatching = false;
   }

   // Deferred event processing - V1.31
   // Queue events for processing in OnTimer (avoids re-entrancy issues)
   // PATCH: Added memory cleanup on queue-full drop
   bool QueueEventDeferred(Event *e)
   {
      if (e == NULL || CheckPointer(e) == POINTER_INVALID)
         return false;
      if (!m_deferredEnabled)
         return false;
      if (m_deferredCount >= MAX_DEFERRED_EVENTS)
      {
         LOG_EVENT(EVENT_LOG_LEVEL_WARNING, "Deferred queue full, dropping event " + IntegerToString(e.ID()));
         // Prevent memory leak: delete dynamic event that cannot be queued
         if (CheckPointer(e) == POINTER_DYNAMIC)
            delete e;
         return false;
      }
      
      int idx = m_deferredCount;
      m_deferredQueue[idx].eventID = e.ID();
      m_deferredQueue[idx].eventPtr = e;
      m_deferredQueue[idx].isPending = true;
      m_deferredCount++;
      
      LOG_EVENT(EVENT_LOG_LEVEL_VERBOSE, "Event " + IntegerToString(e.ID()) + " queued for deferred processing");
      return true;
   }
   
   // Process deferred events (call from OnTimer)
   void ProcessDeferredEvents()
   {
      if (m_deferredCount == 0 || m_isDispatching)
         return;
         
      int processed = 0;
      for (int i = 0; i < m_deferredCount; i++)
      {
         if (m_deferredQueue[i].isPending && m_deferredQueue[i].eventPtr != NULL)
         {
            Event *e = m_deferredQueue[i].eventPtr;
            m_deferredQueue[i].isPending = false;
            m_deferredQueue[i].eventPtr = NULL;
            
            Dispatch(e);  // Dispatch will handle memory cleanup
            processed++;
         }
      }
      
      // Compact the queue
      int writeIdx = 0;
      for (int i = 0; i < m_deferredCount; i++)
      {
         if (m_deferredQueue[i].isPending)
         {
            if (writeIdx != i)
               m_deferredQueue[writeIdx] = m_deferredQueue[i];
            writeIdx++;
         }
      }
      m_deferredCount = writeIdx;
      
      LOG_EVENT(EVENT_LOG_LEVEL_VERBOSE, "Processed " + IntegerToString(processed) + " deferred events");
   }
   
   // Enable/disable deferred processing
   void EnableDeferredProcessing(bool enable)
   {
      m_deferredEnabled = enable;
      LOG_EVENT(EVENT_LOG_LEVEL_INFO, "Deferred processing " + (enable ? "enabled" : "disabled"));
   }
   
   // Get performance metrics
   void GetMetrics(ulong &totalDispatches, ulong &totalHandlersCalled, datetime &lastReset)
   {
      totalDispatches = m_totalDispatches;
      totalHandlersCalled = m_totalHandlersCalled;
      lastReset = m_lastResetTime;
   }
   
   // Reset metrics
   void ResetMetrics()
   {
      m_totalDispatches = 0;
      m_totalHandlersCalled = 0;
      m_lastResetTime = TimeCurrent();
      LOG_EVENT(EVENT_LOG_LEVEL_INFO, "EventBus metrics reset");
   }
   
   // Check if currently dispatching (for re-entrancy detection)
   bool IsDispatching() const { return m_isDispatching; }
   int GetDispatchDepth() const { return m_dispatchDepth; }

   void Clear()
   {
      // Clean up any pending deferred events
      for (int i = 0; i < m_deferredCount; i++)
      {
         if (m_deferredQueue[i].isPending && m_deferredQueue[i].eventPtr != NULL)
         {
            if (CheckPointer(m_deferredQueue[i].eventPtr) == POINTER_DYNAMIC)
            {
               delete m_deferredQueue[i].eventPtr;
               m_deferredQueue[i].eventPtr = NULL;
            }
            m_deferredQueue[i].isPending = false;
         }
      }
      m_deferredCount = 0;
      
      // Unsubscribe all handlers (no deletion - handlers are owned by managers)
      for (int i = 0; i < MAX_EVENT_TYPES; i++)
      {
         m_handlerCount[i] = 0;
         // Explicitly clear handler pointers to prevent dangling references
         for (int j = 0; j < MAX_HANDLERS_PER_EVENT; j++)
         {
            m_handlersByType[i][j].handler = NULL;
            m_handlersByType[i][j].priority = 0;
            m_handlersByType[i][j].groupFlags = EVENT_GROUP_NONE;
         }
      }
      
      // Reset metrics
      m_totalDispatches = 0;
      m_totalHandlersCalled = 0;
      m_lastResetTime = TimeCurrent();
      
      LOG_EVENT(EVENT_LOG_LEVEL_INFO, "EventBus cleared and reset");
   }
};

//+------------------------------------------------------------------+
//| Safe Event Dispatch with Null Check                              |
//| Prevents memory leaks when EventBus is unavailable               |
//+------------------------------------------------------------------+
inline void DispatchEvent(Event *e)
{
   if (CheckPointer(e) == POINTER_INVALID)
      return;
      
   EventBus *bus = EventBus::Instance();
   if (CheckPointer(bus) != POINTER_INVALID)
   {
      bus.Dispatch(e);  // Dispatch takes ownership and deletes heap events
   }
   else
   {
      // EventBus not available - clean up to prevent memory leak
      if (CheckPointer(e) == POINTER_DYNAMIC)
      {
         #ifdef __DEBUG__
         Print("[WARN] EventBus unavailable, deleting event ", e.ID(), " to prevent memory leak");
         #endif
         delete e;
      }
   }
}

// Initialize static members
EventBus *EventBus::m_instance = NULL;

#endif
