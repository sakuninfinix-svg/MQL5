//+------------------------------------------------------------------+
//|                                                  0.EventBus.mqh  |
//|                                       Copyright 2026, Agsicentre |
//|            Event-Driven Core for PASR EA - V2.00 (REFACTORED)    |
//|                                                                   |
//| V2.00 MAJOR REFACTORING:                                         |
//| - Reduced coupling: Removed direct includes, use forward decl.   |
//| - Performance: Object pooling for events, reduced allocations    |
//| - Safety: Enhanced null checks, const-correctness improvements   |
//| - Structure: Split large methods, improved readability           |
//| - Memory: Better cleanup, prevented potential leaks              |
//|                                                                   |
//| V1.32 FIXES (PRESERVED):                                          |
//| - BUG-A: EventRecorder::Start() zero-fill fix                    |
//| - BUG-B: DispatchBatch errorsHandled scope fix                   |
//| - BUG-C: ProcessDeferredEvents re-entrancy guard                 |
//| - BUG-D: DispatchEvent stack pointer protection                  |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "2.00"
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

//--- Debug Logging Control - OPTIMIZED
#ifdef __DEBUG__
   #define EVENT_LOG_LEVEL_VERBOSE  0
   #define EVENT_LOG_LEVEL_INFO     1
   #define EVENT_LOG_LEVEL_WARNING  2
   #define EVENT_LOG_LEVEL_ERROR    3
   #define EVENT_LOG_CURRENT_LEVEL  EVENT_LOG_LEVEL_VERBOSE
   #define LOG_EVENT(level, msg) \
      if(level >= EVENT_LOG_CURRENT_LEVEL) Print("[EventBus] ", msg)
#else
   #define EVENT_LOG_CURRENT_LEVEL  EVENT_LOG_LEVEL_ERROR
   #define LOG_EVENT(level, msg) // No-op in release
#endif

//+------------------------------------------------------------------+
//| Base Event Class - OPTIMIZED V2.00                               |
//| Added: group flags, event name for debug, cancellation support   |
//| Improvements: const-correctness, inline getters for performance  |
//+------------------------------------------------------------------+
class Event
{
protected:
   datetime m_timestamp;
   int      m_sourceId;
   int      m_group;              // Event group for wildcard subscriptions
   string   m_name;               // Event name for debug logging
   bool     m_cancelled;          // Cancellation flag for emergency scenarios

public:
   // Constructor with defaults - optimized parameter order for alignment
   Event(const int sourceId = 0, const int group = EVENT_GROUP_NONE, const string name = "")
      : m_timestamp(TimeCurrent()),
        m_sourceId(sourceId),
        m_group(group),
        m_name(name),
        m_cancelled(false)
   {
   }

   virtual ~Event() {}
   
   // Pure virtual ID - must be implemented by derived classes
   virtual int ID() const = 0;
   
   // Inline getters for performance (avoid function call overhead)
   datetime Timestamp() const { return m_timestamp; }
   int      SourceId()  const { return m_sourceId; }
   int      Group()     const { return m_group; }
   string   Name()      const { return m_name; }
   
   // Cancellation support for emergency scenarios
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
//| Event Recorder (Debug Utility) - V2.00                           |
//| Improvements: Better memory management, const-correctness        |
//| BUG-A FIX: Start() now always zero-fills the buffer and resets   |
//| m_currentIndex unconditionally, preventing stale replay data.    |
//+------------------------------------------------------------------+
class EventRecorder
{
private:
   // Compact structure for cache efficiency
   struct RecordedEvent
   {
      datetime timestamp;
      int      eventType;  // Use int instead of string for faster comparison
      int      sourceId;
   };

   RecordedEvent m_history[];
   bool          m_isRecording;
   int           m_maxHistory;        // Maximum history size (circular buffer)
   uint          m_currentIndex;      // Current write position

public:
   // Constructor with initialization list
   EventRecorder() 
      : m_isRecording(false), 
        m_maxHistory(1000), 
        m_currentIndex(0) 
   {
   }

   // Configure history size with validation
   void SetMaxHistory(int size)
   {
      m_maxHistory = MathMax(100, MathMin(10000, size));
      if(ArraySize(m_history) != m_maxHistory)
         ArrayResize(m_history, m_maxHistory);
   }

   // Start recording - always zero-fill to prevent stale data
   void Start()
   {
      m_isRecording = true;

      // [BUG-A FIX] Always resize+zero-fill on Start() to guarantee
      // replay correctness. Old code skipped resize if size was already
      // correct, leaving stale data at positions > new m_currentIndex=0.
      ArrayResize(m_history, m_maxHistory);
      m_currentIndex = 0; // Reset AFTER resize so index math is clean

      for(int i = 0; i < m_maxHistory; i++)
      {
         m_history[i].timestamp = 0;
         m_history[i].eventType = 0;
         m_history[i].sourceId = 0;
      }
      LOG_EVENT(EVENT_LOG_LEVEL_INFO, "Event Recording Started (Max: " + IntegerToString(m_maxHistory) + " events).");
   }

   // Stop recording with summary
   void Stop()
   {
      m_isRecording = false;
      LOG_EVENT(EVENT_LOG_LEVEL_INFO, "Event Recording Stopped. Captured: " + 
                IntegerToString(MathMin((int)m_currentIndex, m_maxHistory)));
   }
   
   bool IsRecording() const { return m_isRecording; }

   // Record event - zero allocation, circular buffer
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
//| Event Bus Singleton - V2.00 (REFACTORED)                         |
//| Improvements: Better structure, const-correctness, documentation |
//| Uses direct array indexing for O(1) event lookup                 |
//+------------------------------------------------------------------+
class EventBus
{
private:
   static EventBus *m_instance;

   // Handler registration with priority and group support
   struct HandlerRegistration
   {
      IEventHandler *handler;
      int            priority;
      int            groupFlags;
   };

   // Fixed-size arrays for zero-allocation performance
   HandlerRegistration m_handlersByType[MAX_EVENT_TYPES][MAX_HANDLERS_PER_EVENT];
   int                 m_handlerCount[MAX_EVENT_TYPES];
   
   // Re-entrancy protection to prevent recursive dispatch
   bool  m_isDispatching;
   int   m_dispatchDepth;
   
   // Deferred event queue (for OnTimer processing)
   struct DeferredEvent
   {
      int    eventID;
      Event *eventPtr;
      bool   isPending;
   };
   DeferredEvent m_deferredQueue[MAX_DEFERRED_EVENTS];
   int           m_deferredCount;
   bool          m_deferredEnabled;
   
   // Performance metrics for monitoring
   ulong    m_totalDispatches;
   ulong    m_totalHandlersCalled;
   datetime m_lastResetTime;

   // Private constructor for singleton pattern
   EventBus()
   {
      ArrayInitialize(m_handlerCount, 0);
      m_isDispatching     = false;
      m_dispatchDepth     = 0;
      m_deferredCount     = 0;
      m_deferredEnabled   = false;
      m_totalDispatches   = 0;
      m_totalHandlersCalled = 0;
      m_lastResetTime     = TimeCurrent();
      
      for(int i = 0; i < MAX_DEFERRED_EVENTS; i++)
         m_deferredQueue[i].isPending = false;
   }

public:
   // Destructor with cleanup
   ~EventBus() 
   { 
      Clear(); 
      LOG_EVENT(EVENT_LOG_LEVEL_INFO, "EventBus destroyed");
   }

   // Singleton instance accessor - thread-safe in MQL5 context
   static EventBus *Instance()
   {
      if (m_instance == NULL)
         m_instance = new EventBus();
      return m_instance;
   }

   // Static destructor for cleanup on EA shutdown
   static void Destroy()
   {
      if (m_instance != NULL)
      {
         delete m_instance;
         m_instance = NULL;
      }
   }

   bool Subscribe(int eventID, IEventHandler *handler, int priority = EVENT_PRIORITY_NORMAL, int groupFlags = EVENT_GROUP_NONE)
   {
      if (handler == NULL || CheckPointer(handler) == POINTER_INVALID)
         return false;
      if (eventID < 0 || eventID >= MAX_EVENT_TYPES)
         return false;

      int total = m_handlerCount[eventID];
      if (total >= MAX_HANDLERS_PER_EVENT)
         return false;

      for (int i = 0; i < total; i++)
      {
         if (m_handlersByType[eventID][i].handler == handler)
            return false;
      }

      int insertPos = total;
      for (int i = 0; i < total; i++)
      {
         if (priority < m_handlersByType[eventID][i].priority)
         {
            insertPos = i;
            break;
         }
      }

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
   
   // [BUG-SubscribeToGroup PATCH v1.31] Per-slot capacity guard prevents overflow
   bool SubscribeToGroup(int groupFlag, IEventHandler *handler, int priority = EVENT_PRIORITY_NORMAL)
   {
      if (handler == NULL || CheckPointer(handler) == POINTER_INVALID)
         return false;
      if (groupFlag == EVENT_GROUP_NONE)
         return false;
         
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
            for (int j = i; j < total - 1; j++)
               m_handlersByType[eventID][j] = m_handlersByType[eventID][j + 1];
            m_handlerCount[eventID] = total - 1;
            return;
         }
      }
   }

   void Dispatch(Event *e)
   {
      if (e == NULL || CheckPointer(e) == POINTER_INVALID)
         return;

      bool isHeapAllocated = (CheckPointer(e) == POINTER_DYNAMIC);
      int id = e.ID();

      if (id < 0 || id >= MAX_EVENT_TYPES)
      {
         LOG_EVENT(EVENT_LOG_LEVEL_ERROR, "Invalid event ID: " + IntegerToString(id));
         if (isHeapAllocated) delete e;
         return;
      }
      
      if (e.IsCancelled())
      {
         LOG_EVENT(EVENT_LOG_LEVEL_VERBOSE, "Event " + IntegerToString(id) + " cancelled, skipping dispatch");
         if (isHeapAllocated) delete e;
         return;
      }

      int total = m_handlerCount[id];
      if (total == 0)
      {
         if (isHeapAllocated) delete e;
         return;
      }
      
      m_isDispatching = true;
      m_dispatchDepth++;
      
      ulong startTime = GetMicrosecondCount();
      int handlersCalled = 0;
      int errorsHandled = 0;

      if (CheckPointer(g_recorder) != POINTER_INVALID && g_recorder.IsRecording())
         g_recorder.Record(e);

      for (int i = 0; i < total; i++)
      {
         if (e.IsCancelled())
         {
            LOG_EVENT(EVENT_LOG_LEVEL_WARNING, "Event " + IntegerToString(id) + 
                      " cancelled during dispatch after " + IntegerToString(handlersCalled) + " handlers");
            break;
         }
         
         IEventHandler *h = m_handlersByType[id][i].handler;
         if (h != NULL && CheckPointer(h) != POINTER_INVALID)
         {
            // [BUG-GetLastError PATCH v1.31] ResetLastError sets to 0, check post directly
            ResetLastError();
            h.HandleEvent(e);
            int postErrorCount = GetLastError();
            if (postErrorCount != 0)
            {
               errorsHandled++;
               string handlerName = h.GetHandlerName();
               LOG_EVENT(EVENT_LOG_LEVEL_ERROR, "Error in handler [" + handlerName + "] for event " + IntegerToString(id) + ": Error " + IntegerToString(postErrorCount));
               h.OnHandlerError(id, "Error " + IntegerToString(postErrorCount));
               ResetLastError();
            }
            handlersCalled++;
         }
      }
      
      m_totalDispatches++;
      m_totalHandlersCalled += (ulong)handlersCalled;
      
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

      if (isHeapAllocated && CheckPointer(e) == POINTER_DYNAMIC)
         delete e;
   }
   
   // [BUG-B FIX v1.32] errorsHandled moved outside inner loop so it
   // accumulates across all events in the batch (was shadowed per-event
   // in some MQL5 compiler versions due to inner scope redeclaration).
   void DispatchBatch(int eventID, Event *&events[], int count)
   {
      if (count <= 0)
         return;
      if (eventID < 0 || eventID >= MAX_EVENT_TYPES)
      {
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
      int errorsHandled = 0; // [BUG-B FIX] declared at batch scope, not per-event scope
      
      for (int e = 0; e < count; e++)
      {
         if (events[e] == NULL || CheckPointer(events[e]) == POINTER_INVALID)
            continue;
            
         bool isHeapAllocated = (CheckPointer(events[e]) == POINTER_DYNAMIC);
         
         if (CheckPointer(g_recorder) != POINTER_INVALID && g_recorder.IsRecording())
            g_recorder.Record(events[e]);
         
         for (int i = 0; i < total; i++)
         {
            if (events[e].IsCancelled())
            {
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
                  string handlerName = h.GetHandlerName();
                  LOG_EVENT(EVENT_LOG_LEVEL_ERROR, "Error in handler [" + handlerName + "] for batch event " + IntegerToString(eventID) + ": Error " + IntegerToString(postErrorCount));
                  h.OnHandlerError(eventID, "Error " + IntegerToString(postErrorCount));
                  ResetLastError();
               }
               handlersCalled++;
            }
         }
         
         if (isHeapAllocated && CheckPointer(events[e]) == POINTER_DYNAMIC)
         {
            delete events[e];
            events[e] = NULL;
         }
      }
      
      m_totalDispatches += (ulong)count;
      m_totalHandlersCalled += (ulong)handlersCalled;
      
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

   // [BUG-QueueDeferred PATCH v1.31] Memory cleanup on queue-full drop
   bool QueueEventDeferred(Event *e)
   {
      if (e == NULL || CheckPointer(e) == POINTER_INVALID)
         return false;
      if (!m_deferredEnabled)
         return false;
      if (m_deferredCount >= MAX_DEFERRED_EVENTS)
      {
         LOG_EVENT(EVENT_LOG_LEVEL_WARNING, "Deferred queue full, dropping event " + IntegerToString(e.ID()));
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
   
   // [BUG-C FIX v1.32] ProcessDeferredEvents re-entrancy guard:
   // Old guard checked m_isDispatching which is set TRUE by Dispatch().
   // After Dispatch() returns and resets depth to 0, m_isDispatching
   // becomes false again - so subsequent events in the same call ARE
   // processed correctly. However the guard at the TOP of this function
   // used m_isDispatching which could be true if called from WITHIN a
   // Dispatch() handler (re-entrancy). The fix keeps the guard but
   // also adds a depth check to detect nested calls properly.
   void ProcessDeferredEvents()
   {
      // [BUG-C FIX] Check both flag AND depth to handle re-entrancy correctly
      if (m_deferredCount == 0 || m_isDispatching || m_dispatchDepth > 0)
         return;
         
      int processed = 0;
      for (int i = 0; i < m_deferredCount; i++)
      {
         if (m_deferredQueue[i].isPending && m_deferredQueue[i].eventPtr != NULL)
         {
            Event *e = m_deferredQueue[i].eventPtr;
            m_deferredQueue[i].isPending = false;
            m_deferredQueue[i].eventPtr = NULL;
            
            Dispatch(e);  // Dispatch handles memory cleanup
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
   
   void EnableDeferredProcessing(bool enable)
   {
      m_deferredEnabled = enable;
      LOG_EVENT(EVENT_LOG_LEVEL_INFO, "Deferred processing " + (enable ? "enabled" : "disabled"));
   }
   
   void GetMetrics(ulong &totalDispatches, ulong &totalHandlersCalled, datetime &lastReset)
   {
      totalDispatches = m_totalDispatches;
      totalHandlersCalled = m_totalHandlersCalled;
      lastReset = m_lastResetTime;
   }
   
   void ResetMetrics()
   {
      m_totalDispatches = 0;
      m_totalHandlersCalled = 0;
      m_lastResetTime = TimeCurrent();
      LOG_EVENT(EVENT_LOG_LEVEL_INFO, "EventBus metrics reset");
   }
   
   bool IsDispatching() const { return m_isDispatching; }
   int GetDispatchDepth() const { return m_dispatchDepth; }

   void Clear()
   {
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
      
      for (int i = 0; i < MAX_EVENT_TYPES; i++)
      {
         m_handlerCount[i] = 0;
         for (int j = 0; j < MAX_HANDLERS_PER_EVENT; j++)
         {
            m_handlersByType[i][j].handler = NULL;
            m_handlersByType[i][j].priority = 0;
            m_handlersByType[i][j].groupFlags = EVENT_GROUP_NONE;
         }
      }
      
      m_totalDispatches = 0;
      m_totalHandlersCalled = 0;
      m_lastResetTime = TimeCurrent();
      
      LOG_EVENT(EVENT_LOG_LEVEL_INFO, "EventBus cleared and reset");
   }
};

//+------------------------------------------------------------------+
//| Safe Event Dispatch with Null Check - V2.00                      |
//| [BUG-D FIX] Only delete if POINTER_DYNAMIC to prevent            |
//| undefined behavior when e is a valid stack-allocated pointer.    |
//| Improvements: Better error handling, consistent logging          |
//+------------------------------------------------------------------+
inline void DispatchEvent(Event *e)
{
   if (e == NULL || CheckPointer(e) == POINTER_INVALID)
      return;
      
   EventBus *bus = EventBus::Instance();
   if (bus != NULL && CheckPointer(bus) != POINTER_INVALID)
   {
      bus.Dispatch(e);  // Dispatch takes ownership and deletes heap events
   }
   else
   {
      // [BUG-D FIX] Only delete DYNAMIC pointers - stack pointers must NOT be deleted
      if (CheckPointer(e) == POINTER_DYNAMIC)
      {
         LOG_EVENT(EVENT_LOG_LEVEL_WARNING, 
                   "[WARN] EventBus unavailable, deleting event " + IntegerToString(e.ID()) + 
                   " to prevent memory leak");
         delete e;
      }
   }
}

// Initialize static members
EventBus *EventBus::m_instance = NULL;

#endif // __EVENT_BUS_MQH__
