//+------------------------------------------------------------------+
//|                                              Core/EventBus.mqh   |
//|                                       Copyright 2026, Agsicentre |
//|            Event-Driven Core for PASR EA - V3.00                 |
//|                                                                   |
//| Migrated from 0.EventBus.mqh as part of Core layer refactoring.  |
//| 0.EventBus.mqh is now a shim that re-includes this file.         |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "3.00"
#property strict

#ifndef __CORE_EVENT_BUS_MQH__
#define __CORE_EVENT_BUS_MQH__

#include "../PASR.Optimizations.mqh"  // Include semua optimizations

#define MAX_HANDLERS_PER_EVENT  16
#define MAX_EVENT_TYPES         32
#define MAX_EVENT_GROUPS         8
#define MAX_DEFERRED_EVENTS     100

#define EVENT_PRIORITY_CRITICAL   0
#define EVENT_PRIORITY_HIGH      50
#define EVENT_PRIORITY_NORMAL   100
#define EVENT_PRIORITY_LOW      150

#define IS_CRITICAL_PRIORITY(p)  ((p) >= 0   && (p) <= 10)
#define IS_HIGH_PRIORITY(p)      ((p) > 10   && (p) <= 50)
#define IS_NORMAL_PRIORITY(p)    ((p) > 50   && (p) <= 100)
#define IS_LOW_PRIORITY(p)       ((p) > 100  && (p) <= 200)

#define EVENT_GROUP_NONE    0
#define EVENT_GROUP_MARKET  1
#define EVENT_GROUP_SIGNAL  2
#define EVENT_GROUP_ORDER   4
#define EVENT_GROUP_SYSTEM  8
#define EVENT_GROUP_ALL     0xFFFF

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
   #define LOG_EVENT(level, msg)
#endif

//+------------------------------------------------------------------+
//| ENUM: type-safe event identifiers                                |
//+------------------------------------------------------------------+
enum ENUM_EVENT_ID
{
   EVENT_ID_NONE = 0,
   EVENT_ID_PRICE_UPDATE,
   EVENT_ID_NEW_BAR,
   EVENT_ID_HEARTBEAT,
   EVENT_ID_CONFIG_RELOAD,
   EVENT_ID_EMERGENCY_STOP,
   EVENT_ID_ZONE_UPDATE,
   EVENT_ID_SIGNAL_GENERATED,
   EVENT_ID_ORDER_EXECUTION,
   EVENT_ID_POSITION_UPDATE,
   EVENT_ID_RECOVERY_OPPORTUNITY,
   EVENT_ID_RECOVERY_SIGNAL,
   EVENT_ID_MARKET_GATE,
   EVENT_ID_PAUSE_TOGGLE,
   EVENT_ID_SESSION_CHANGE,
   EVENT_ID_NEWS_ALERT
};

//+------------------------------------------------------------------+
//| Base Event Class - OPTIMIZED V3.00                               |
//| Uses string pooling for zero-allocation event names              |
//+------------------------------------------------------------------+
class Event
{
protected:
   datetime m_timestamp;
   int      m_sourceId;
   int      m_group;
   uint     m_nameHash;
   int      m_nameIndex;
   bool     m_cancelled;

public:
   CRITICAL_FUNCTION Event(const int sourceId = 0, const int group = EVENT_GROUP_NONE, const string name = "")
      : m_timestamp(TimeCurrent()),
        m_sourceId(sourceId),
        m_group(group),
        m_cancelled(false)
   {
      m_nameIndex = CStringPool::GetIndexByName(name);
      m_nameHash  = CStringPool::GetHashByIndex(m_nameIndex);
   }

   virtual ~Event() {}
   virtual int ID() const = 0;

   datetime Timestamp()    const { return m_timestamp; }
   int      SourceId()     const { return m_sourceId; }
   int      Group()        const { return m_group; }

   CRITICAL_FUNCTION const string& Name() const
   {
      return CStringPool::GetNameByIndex(m_nameIndex);
   }

   CRITICAL_FUNCTION uint NameHash() const { return m_nameHash; }

   void     Cancel()             { m_cancelled = true; }
   bool     IsCancelled()  const { return m_cancelled; }
};

class EventRecorder;
extern EventRecorder *g_recorder;

//+------------------------------------------------------------------+
//| IEventHandler                                                    |
//+------------------------------------------------------------------+
class IEventHandler
{
public:
   virtual void HandleEvent(Event *e) = 0;

   virtual void OnHandlerError(int eventId, string errorMsg)
   {
      LOG_EVENT(EVENT_LOG_LEVEL_ERROR, "Handler error on event " + IntegerToString(eventId) + ": " + errorMsg);
   }

   virtual string GetHandlerName() const { return "UnknownHandler"; }
   virtual ~IEventHandler() {}
};

//+------------------------------------------------------------------+
//| EventRecorder - OPTIMIZED V3.00                                  |
//+------------------------------------------------------------------+
class EventRecorder
{
private:
   struct RecordedEvent
   {
      datetime timestamp;
      int      eventType;
      int      sourceId;
   };

   RecordedEvent m_history[];
   bool          m_isRecording;
   int           m_maxHistory;
   uint          m_currentIndex;
   int           m_capacity;

public:
   EventRecorder()
      : m_isRecording(false), m_maxHistory(1000), m_currentIndex(0), m_capacity(1000)
   {
      ArrayResize(m_history, m_capacity);
   }

   void SetMaxHistory(int size)
   {
      m_maxHistory = MathMax(100, MathMin(10000, size));
      if(m_maxHistory > m_capacity)
      {
         m_capacity = m_maxHistory;
         ArrayResize(m_history, m_capacity);
      }
      else
         m_maxHistory = m_capacity;
   }

   void Start()
   {
      m_isRecording = true;
      if(ArraySize(m_history) < m_maxHistory)
         ArrayResize(m_history, m_maxHistory);
      m_currentIndex = 0;
      ZeroMemory(m_history);
      LOG_EVENT(EVENT_LOG_LEVEL_INFO, "Event Recording Started (Max: " + IntegerToString(m_maxHistory) + ").");
   }

   void Stop()
   {
      m_isRecording = false;
      LOG_EVENT(EVENT_LOG_LEVEL_INFO, "Event Recording Stopped. Captured: " +
                IntegerToString(MathMin((int)m_currentIndex, m_maxHistory)));
   }

   bool IsRecording() const { return m_isRecording; }

   CRITICAL_FUNCTION void Record(Event *e)
   {
      if(!m_isRecording || CheckPointer(e) == POINTER_INVALID) return;
      uint idx = m_currentIndex & (uint)(m_maxHistory - 1);
      m_history[idx].timestamp = e.Timestamp();
      m_history[idx].eventType = e.ID();
      m_history[idx].sourceId  = e.SourceId();
      m_currentIndex++;
   }

   int  HistorySize()    const { return MathMin((int)m_currentIndex, m_maxHistory); }
   uint TotalRecorded()  const { return m_currentIndex; }

   int GetHistoryType(int i)
   {
      int size = HistorySize();
      if(i < 0 || i >= size) return 0;
      uint start = (m_currentIndex >= (uint)m_maxHistory) ? (m_currentIndex & (uint)(m_maxHistory - 1)) : 0;
      return m_history[(start + (uint)i) & (uint)(m_maxHistory - 1)].eventType;
   }

   int GetHistorySourceId(int i)
   {
      int size = HistorySize();
      if(i < 0 || i >= size) return 0;
      uint start = (m_currentIndex >= (uint)m_maxHistory) ? (m_currentIndex & (uint)(m_maxHistory - 1)) : 0;
      return m_history[(start + (uint)i) & (uint)(m_maxHistory - 1)].sourceId;
   }

   datetime GetHistoryTimestamp(int i)
   {
      int size = HistorySize();
      if(i < 0 || i >= size) return 0;
      uint start = (m_currentIndex >= (uint)m_maxHistory) ? (m_currentIndex & (uint)(m_maxHistory - 1)) : 0;
      return m_history[(start + (uint)i) & (uint)(m_maxHistory - 1)].timestamp;
   }
};

//+------------------------------------------------------------------+
//| EventBus Singleton - OPTIMIZED V3.00                             |
//+------------------------------------------------------------------+
class EventBus
{
private:
   struct ALIGN_CACHE HandlerSlot
   {
      IEventHandler *handler;
      int            priority;
      bool           active;
      char           _pad[7];
   };

   struct ALIGN_CACHE EventChannel
   {
      HandlerSlot slots[MAX_HANDLERS_PER_EVENT];
      int         count;
      bool        sorted;
      char        _pad[3];
   };

   EventChannel m_channels[MAX_EVENT_TYPES];
   Event       *m_deferredQueue[MAX_DEFERRED_EVENTS];
   int          m_deferredCount;
   int          m_deferredCapacity;
   bool         m_dispatching;
   bool         m_processingDeferred;
   int          m_totalDispatched;
   int          m_totalErrors;

   static EventBus *s_instance;

   EventBus()
      : m_deferredCount(0), m_dispatching(false),
        m_processingDeferred(false), m_totalDispatched(0), m_totalErrors(0),
        m_deferredCapacity(MAX_DEFERRED_EVENTS)
   {
      ZeroMemory(m_channels);
      ZeroMemory(m_deferredQueue);
      CStringPool::Initialize();
      LOG_EVENT(EVENT_LOG_LEVEL_INFO, "EventBus initialized (V3.00)");
   }

   CRITICAL_FUNCTION void SortChannelByPriority(int eventId)
   {
      if(eventId < 0 || eventId >= MAX_EVENT_TYPES) return;
      EventChannel *ch = &m_channels[eventId];
      if(ch.sorted || ch.count <= 1) { ch.sorted = true; return; }
      for(int i = 0; i < ch.count - 1; i++)
         for(int j = 0; j < ch.count - i - 1; j++)
            if(ch.slots[j].priority > ch.slots[j + 1].priority)
            {
               HandlerSlot tmp  = ch.slots[j];
               ch.slots[j]      = ch.slots[j + 1];
               ch.slots[j + 1]  = tmp;
            }
      ch.sorted = true;
   }

public:
   static EventBus *Instance()
   {
      if(s_instance == NULL)
         s_instance = new EventBus();
      return s_instance;
   }

   static void Destroy()
   {
      if(s_instance != NULL) { delete s_instance; s_instance = NULL; }
   }

   bool Subscribe(int eventId, IEventHandler *handler, int priority = EVENT_PRIORITY_NORMAL)
   {
      if(eventId <= 0 || eventId >= MAX_EVENT_TYPES) return false;
      if(CheckPointer(handler) == POINTER_INVALID)   return false;
      EventChannel *ch = &m_channels[eventId];
      if(ch.count >= MAX_HANDLERS_PER_EVENT)
      {
         LOG_EVENT(EVENT_LOG_LEVEL_WARNING, "Max handlers reached for event " + IntegerToString(eventId));
         return false;
      }
      ch.slots[ch.count].handler  = handler;
      ch.slots[ch.count].priority = priority;
      ch.slots[ch.count].active   = true;
      ch.count++;
      ch.sorted = false;
      SortChannelByPriority(eventId);
      return true;
   }

   bool Unsubscribe(int eventId, IEventHandler *handler)
   {
      if(eventId <= 0 || eventId >= MAX_EVENT_TYPES) return false;
      EventChannel *ch = &m_channels[eventId];
      for(int i = 0; i < ch.count; i++)
         if(ch.slots[i].handler == handler) { ch.slots[i].active = false; return true; }
      return false;
   }

   CRITICAL_FUNCTION int Dispatch(Event *e)
   {
      if(CheckPointer(e) == POINTER_INVALID) return 0;
      int eventId = e.ID();
      if(eventId <= 0 || eventId >= MAX_EVENT_TYPES) { delete e; return 0; }
      if(m_dispatching)
      {
         if(m_deferredCount < m_deferredCapacity)
            m_deferredQueue[m_deferredCount++] = e;
         else
         {
            LOG_EVENT(EVENT_LOG_LEVEL_WARNING, "Deferred queue full, dropping event " + IntegerToString(eventId));
            delete e;
         }
         return 0;
      }
      if(g_recorder != NULL && CheckPointer(g_recorder) != POINTER_INVALID)
         g_recorder.Record(e);
      m_dispatching = true;
      EventChannel *ch = &m_channels[eventId];
      int handled = 0;
      for(int i = 0; i < ch.count; i++)
      {
         if(!ch.slots[i].active) continue;
         IEventHandler *h = ch.slots[i].handler;
         if(CheckPointer(h) == POINTER_INVALID) { ch.slots[i].active = false; continue; }
         h.HandleEvent(e);
         if(!e.IsCancelled()) handled++;
         if(e.IsCancelled()) break;
      }
      m_dispatching = false;
      m_totalDispatched++;
      delete e;
      ProcessDeferredEvents();
      return handled;
   }

   void DispatchBatch(Event *events[], int count)
   {
      int errorsHandled = 0;
      for(int i = 0; i < count; i++)
      {
         if(CheckPointer(events[i]) != POINTER_INVALID) Dispatch(events[i]);
         else errorsHandled++;
      }
      if(errorsHandled > 0)
         LOG_EVENT(EVENT_LOG_LEVEL_WARNING, "DispatchBatch: " + IntegerToString(errorsHandled) + " null events skipped");
   }

   void ProcessDeferredEvents()
   {
      if(m_processingDeferred || m_deferredCount == 0) return;
      m_processingDeferred = true;
      int toProcess = m_deferredCount;
      m_deferredCount = 0;
      for(int i = 0; i < toProcess; i++)
      {
         if(CheckPointer(m_deferredQueue[i]) != POINTER_INVALID)
         {
            Dispatch(m_deferredQueue[i]);
            m_deferredQueue[i] = NULL;
         }
      }
      m_processingDeferred = false;
   }

   int  GetTotalDispatched() const { return m_totalDispatched; }
   int  GetTotalErrors()     const { return m_totalErrors; }
   int  GetDeferredCount()   const { return m_deferredCount; }
   bool IsDispatching()      const { return m_dispatching; }
};

EventBus *EventBus::s_instance = NULL;

//+------------------------------------------------------------------+
//| Global Dispatch Helper                                           |
//+------------------------------------------------------------------+
void DispatchEvent(Event *e)
{
   EventBus *bus = EventBus::Instance();
   if(bus != NULL) bus.Dispatch(e);
   else if(CheckPointer(e) != POINTER_INVALID) delete e;
}

#endif // __CORE_EVENT_BUS_MQH__
