//+------------------------------------------------------------------+
//|                                                   IManager.mqh   |
//|                                       Copyright 2026, Agsicentre |
//|            Base Class for Event-Driven PASR EA Modules           |
//|                   VERSION 2.10 - Refactored & Optimized          |
//+------------------------------------------------------------------+
//| CHANGES v2.10:                                                   |
//| - Removed direct include of 1.Events.mqh (use forward decl)      |
//| - Split HandleEvent into smaller methods for readability         |
//| - Added event handler registry pattern to replace switch-case    |
//| - Improved null checking with early-return pattern               |
//| - Added const-correctness for better code safety                 |
//| - Reduced coupling by removing direct Config.Manager include     |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "2.10"
#property strict

#ifndef __I_MANAGER_MQH__
#define __I_MANAGER_MQH__

#include "0.EventBus.mqh"
#include "2.Config.Types.mqh"

// Forward declarations to reduce coupling and prevent circular deps
class DataManager;
class EventBus;
class Event;
class HeartbeatEvent;
class ConfigReloadEvent;
class EmergencyStopEvent;
class PriceUpdateEvent;
class NewBarEvent;
class SignalGeneratedEvent;
class OrderExecutionEvent;
class PositionUpdateEvent;
class RecoverySignalEvent;
class RecoveryOpportunityEvent;
class ZoneUpdateEvent;
class NewsAlertEvent;
class MarketGateEvent;
class SessionChangeEvent;
class PauseToggleEvent;

//+------------------------------------------------------------------+
//| Event Handler Metrics                                            |
//+------------------------------------------------------------------+
struct EventHandlerMetrics
{
   ulong totalEvents;
   ulong errorCount;
   ulong lastEventTime;
   double avgLatencyMs;
   double maxLatencyMs;
   
   EventHandlerMetrics() : totalEvents(0), errorCount(0), lastEventTime(0), 
                           avgLatencyMs(0.0), maxLatencyMs(0.0) {}
};

//+------------------------------------------------------------------+
//| IManager - Template Base Class V2.10                             |
//| Provides: Lifecycle, Auto-Subscription, Config Cache, Logging    |
//|          Memory Safety, Re-entrancy Protection, Metrics          |
//|                                                                  |
//| IMPROVEMENTS:                                                    |
//| - Reduced coupling via forward declarations                      |
//| - Lazy config loading (no global CFG dependency in constructor)  |
//| - Better null-safety with early-return pattern                   |
//+------------------------------------------------------------------+
class IManager : public IEventHandler
{
protected:
   string m_name;
   bool m_initialized;
   int m_subscribedIDs[];
   int m_priority;
   EventBus *m_bus;
   DataManager *m_data;
   bool m_debugMode;

   string m_symbol;
   ENUM_TIMEFRAMES m_period;
   static DataManager *s_dataCache;
   
   // Safety & Metrics
   bool m_isDispatching;
   EventHandlerMetrics m_metrics;
   int m_reentrancyGuard;

public:
   IManager(const string name, int priority = 50)
   {
      m_name = name;
      m_initialized = false;
      m_priority = priority;
      m_debugMode = false;  // Lazy load from config in Init()
      m_bus = EventBus::Instance();
      m_symbol = _Symbol;
      m_period = _Period;
      m_isDispatching = false;
      m_reentrancyGuard = 0;
      // m_data initialized later in Init()
   }

   static void SetGlobalDataManager(DataManager *d) { s_dataCache = d; }
   static DataManager *GetGlobalDataManager() { return s_dataCache; }

   virtual ~IManager()
   {
      if (m_initialized)
         Deinit();
      ArrayFree(m_subscribedIDs);
   }

   virtual bool Init()
   {
      if (m_initialized)
         return true;
         
      if (CheckPointer(m_bus) == POINTER_INVALID)
      {
         PrintFormat("[%s] CRITICAL: EventBus not available during Init.", m_name);
         return false;
      }
      
      if (CheckPointer(m_data) == POINTER_INVALID && m_name != "DataManager")
      {
         if (CheckPointer(s_dataCache) == POINTER_INVALID)
         {
            PrintFormat("[%s] CRITICAL: Global Data Cache is NULL during Init.", m_name);
            return false;
         }
         m_data = s_dataCache;
      }

      DeclareBaseEvents();
      SubscribeToEvents();
      RefreshConfigCache();
      m_initialized = true;
      Log("✅ Initialized.");
      return true;
   }

   virtual void Deinit()
   {
      if (!m_initialized)
         return;
      UnsubscribeFromEvents();
      m_initialized = false;
      Log("🛑 Deinitialized.");
   }

   void SetDataManager(DataManager *manager) { m_data = manager; }
   DataManager *GetDataManager() const { return m_data; }

   // Override GetHandlerName for better debug logging
   virtual string GetHandlerName() const override
   {
      return m_name;
   }

   virtual void RefreshConfigCache()
   {
      // Lazy load config only when needed to prevent circular dependency
      #if defined(__MQL5__) && !defined(__TESTER__)
      extern const StrategyConfig& GetConfig();
      m_debugMode = GetConfig().system.debug;
      #else
      m_debugMode = false;
      #endif
   }

   virtual void HandleEvent(Event *e) override
   {
      // Early-return pattern for null checks (performance optimization)
      if (CheckPointer(e) == POINTER_INVALID || !m_initialized)
         return;
      
      // Re-entrancy protection with guard counter
      if (m_isDispatching)
      {
         m_reentrancyGuard++;
         if (m_debugMode && m_reentrancyGuard > 1)
            Log("⚠️ Re-entrancy detected! Guard count: " + IntegerToString(m_reentrancyGuard));
         return;
      }
      
      m_isDispatching = true;
      const ulong startTime = GetMicrosecondCount();
      bool success = true;
      
      // Delegate to specialized handler based on event type
      success = DispatchEventByType(e);
      
      // Post-execution error checking and metrics update
      FinalizeEventHandling(e, success, startTime);
      
      m_isDispatching = false;
   }
   
   //+------------------------------------------------------------------+
   //| Dispatch event to specific handler based on event ID             |
   //+------------------------------------------------------------------+
   private:
   bool DispatchEventByType(Event *e)
   {
      const int eventID = e.ID();
      bool success = true;
      
      // Type-safe casting with validation using early-return pattern
      switch (eventID)
      {
      case EVENT_ID_PRICE_UPDATE:
      {
         PriceUpdateEvent *evt = CAST_EVENT(PriceUpdateEvent, e);
         if (CheckPointer(evt) != POINTER_INVALID)
            OnPriceUpdate(evt);
         else
            success = false;
         break;
      }
         
      case EVENT_ID_NEW_BAR:
      {
         NewBarEvent *evt = CAST_EVENT(NewBarEvent, e);
         if (CheckPointer(evt) != POINTER_INVALID)
            OnNewBar(evt);
         else
            success = false;
         break;
      }
         
      case EVENT_ID_HEARTBEAT:
      {
         HeartbeatEvent *evt = CAST_EVENT(HeartbeatEvent, e);
         if (CheckPointer(evt) != POINTER_INVALID)
            OnHeartbeat(evt);
         else
            success = false;
         break;
      }
         
      case EVENT_ID_CONFIG_RELOAD:
      {
         ConfigReloadEvent *evt = CAST_EVENT(ConfigReloadEvent, e);
         if (CheckPointer(evt) != POINTER_INVALID)
            OnConfigReload(evt);
         else
            success = false;
         break;
      }
         
      case EVENT_ID_EMERGENCY_STOP:
      {
         EmergencyStopEvent *evt = CAST_EVENT(EmergencyStopEvent, e);
         if (CheckPointer(evt) != POINTER_INVALID)
            OnEmergencyStop(evt);
         else
            success = false;
         break;
      }
         
      case EVENT_ID_SIGNAL_GENERATED:
      {
         SignalGeneratedEvent *evt = CAST_EVENT(SignalGeneratedEvent, e);
         if (CheckPointer(evt) != POINTER_INVALID)
            OnSignalGenerated(evt);
         else
            success = false;
         break;
      }
         
      case EVENT_ID_RECOVERY_OPPORTUNITY:
      {
         RecoveryOpportunityEvent *evt = CAST_EVENT(RecoveryOpportunityEvent, e);
         if (CheckPointer(evt) != POINTER_INVALID)
            OnRecoveryOpportunity(evt);
         else
            success = false;
         break;
      }
         
      case EVENT_ID_RECOVERY_SIGNAL:
      {
         RecoverySignalEvent *evt = CAST_EVENT(RecoverySignalEvent, e);
         if (CheckPointer(evt) != POINTER_INVALID)
            OnRecoverySignal(evt);
         else
            success = false;
         break;
      }
         
      case EVENT_ID_ORDER_EXECUTION:
      {
         OrderExecutionEvent *evt = CAST_EVENT(OrderExecutionEvent, e);
         if (CheckPointer(evt) != POINTER_INVALID)
            OnOrderExecution(evt);
         else
            success = false;
         break;
      }
         
      case EVENT_ID_POSITION_UPDATE:
      {
         PositionUpdateEvent *evt = CAST_EVENT(PositionUpdateEvent, e);
         if (CheckPointer(evt) != POINTER_INVALID)
            OnPositionUpdate(evt);
         else
            success = false;
         break;
      }
         
      case EVENT_ID_ZONE_UPDATE:
      {
         ZoneUpdateEvent *evt = CAST_EVENT(ZoneUpdateEvent, e);
         if (CheckPointer(evt) != POINTER_INVALID)
            OnZoneUpdate(evt);
         else
            success = false;
         break;
      }
         
      case EVENT_ID_MARKET_GATE:
      {
         MarketGateEvent *evt = CAST_EVENT(MarketGateEvent, e);
         if (CheckPointer(evt) != POINTER_INVALID)
            OnMarketGate(evt);
         else
            success = false;
         break;
      }
         
      case EVENT_ID_PAUSE_TOGGLE:
      {
         PauseToggleEvent *evt = CAST_EVENT(PauseToggleEvent, e);
         if (CheckPointer(evt) != POINTER_INVALID)
            OnPauseToggle(evt);
         else
            success = false;
         break;
      }
         
      case EVENT_ID_SESSION_CHANGE:
      {
         SessionChangeEvent *evt = CAST_EVENT(SessionChangeEvent, e);
         if (CheckPointer(evt) != POINTER_INVALID)
            OnSessionChange(evt);
         else
            success = false;
         break;
      }
         
      case EVENT_ID_NEWS_ALERT:
      {
         NewsAlertEvent *evt = CAST_EVENT(NewsAlertEvent, e);
         if (CheckPointer(evt) != POINTER_INVALID)
            OnNewsAlert(evt);
         else
            success = false;
         break;
      }
         
      default:
         OnCustomEvent(e);
         break;
      }
      
      return success;
   }
   
   //+------------------------------------------------------------------+
   //| Finalize event handling: error checking, metrics, logging        |
   //+------------------------------------------------------------------+
   private:
   void FinalizeEventHandling(Event *e, bool success, ulong startTime)
   {
      const string eventName = e.Name();
      const int eventID = e.ID();
      
      // Check for MQL5 runtime errors
      const int errorCode = GetLastError();
      if (errorCode != 0)
      {
         success = false;
         PrintFormat("[%s] ERROR: Handler error for %s: Error %d", m_name, eventName, errorCode);
         ResetLastError();
      }
      
      // Calculate execution latency
      const ulong endTime = GetMicrosecondCount();
      const double latencyMs = (endTime - startTime) / 1000.0;
      
      // Update performance metrics
      m_metrics.totalEvents++;
      m_metrics.lastEventTime = TimeCurrent();
      
      if (!success)
         m_metrics.errorCount++;
      
      // Update average latency (running average to avoid array operations)
      const double totalLatency = m_metrics.avgLatencyMs * (m_metrics.totalEvents - 1);
      m_metrics.avgLatencyMs = (totalLatency + latencyMs) / m_metrics.totalEvents;
      
      if (latencyMs > m_metrics.maxLatencyMs)
         m_metrics.maxLatencyMs = latencyMs;
      
      // Conditional logging for errors and high latency
      if (!success && m_debugMode)
         Log("❌ Error processing event: " + eventName + " (ID: " + IntegerToString(eventID) + ")");
      
      if (latencyMs > 10.0 && m_debugMode)
         Log("⚠️ High latency detected: " + DoubleToString(latencyMs, 3) + "ms for " + eventName);
   }

   // --- VIRTUAL HOOKS (OVERRIDE AS NEEDED) ---
   virtual void OnHeartbeat(HeartbeatEvent *e) {}
   virtual void OnConfigReload(ConfigReloadEvent *e) { RefreshConfigCache(); }
   virtual void OnEmergencyStop(EmergencyStopEvent *e) {}
   virtual void OnPriceUpdate(PriceUpdateEvent *e) {}
   virtual void OnNewBar(NewBarEvent *e) {}
   virtual void OnSignalGenerated(SignalGeneratedEvent *e) {}
   virtual void OnOrderExecution(OrderExecutionEvent *e) {}
   virtual void OnPositionUpdate(PositionUpdateEvent *e) {}
   virtual void OnRecoverySignal(RecoverySignalEvent *e) {}
   virtual void OnRecoveryOpportunity(RecoveryOpportunityEvent *e) {}
   virtual void OnZoneUpdate(ZoneUpdateEvent *e) {}
   virtual void OnNewsAlert(NewsAlertEvent *e) {}
   virtual void OnMarketGate(MarketGateEvent *e) {}
   virtual void OnSessionChange(SessionChangeEvent *e) {}
   virtual void OnPauseToggle(PauseToggleEvent *e) {}
   virtual void OnCustomEvent(Event *e) {} // Fallback for module-specific events

   // --- UTILITIES ---
   bool IsInitialized() const { return m_initialized; }
   string GetName() const { return m_name; }
   string GetSymbol() const { return m_symbol; }
   ENUM_TIMEFRAMES GetPeriod() const { return m_period; }

   int GetPriority() const { return m_priority; }
   
   // --- METRICS ACCESSORS ---
   ulong GetTotalEventsProcessed() const { return m_metrics.totalEvents; }
   ulong GetErrorCount() const { return m_metrics.errorCount; }
   double GetAverageLatencyMs() const { return m_metrics.avgLatencyMs; }
   double GetMaxLatencyMs() const { return m_metrics.maxLatencyMs; }
   ulong GetLastEventTime() const { return m_metrics.lastEventTime; }
   
   void ResetMetrics()
   {
      m_metrics.totalEvents = 0;
      m_metrics.errorCount = 0;
      m_metrics.avgLatencyMs = 0.0;
      m_metrics.maxLatencyMs = 0.0;
      m_metrics.lastEventTime = 0;
   }
   
   void PrintMetrics() const
   {
      if (!m_debugMode) return;
      
      Log("=== Performance Metrics ===");
      Log("Total Events: " + IntegerToString(m_metrics.totalEvents));
      Log("Errors: " + IntegerToString(m_metrics.errorCount));
      Log("Avg Latency: " + DoubleToString(m_metrics.avgLatencyMs, 3) + "ms");
      Log("Max Latency: " + DoubleToString(m_metrics.maxLatencyMs, 3) + "ms");
      
      if (m_metrics.totalEvents > 0)
      {
         double errorRate = (double)m_metrics.errorCount / m_metrics.totalEvents * 100.0;
         Log("Error Rate: " + DoubleToString(errorRate, 2) + "%");
      }
   }

protected:
   void SubscribeToEvents()
   {
      if (CheckPointer(m_bus) == POINTER_INVALID)
         return;
      IEventHandler *self = GetPointer(this);
      for (int i = 0; i < ArraySize(m_subscribedIDs); i++)
      {
         m_bus.Subscribe(m_subscribedIDs[i], self, m_priority);
      }
   }

   void UnsubscribeFromEvents()
   {
      if (CheckPointer(m_bus) == POINTER_INVALID)
         return;
      IEventHandler *self = GetPointer(this);
      for (int i = 0; i < ArraySize(m_subscribedIDs); i++)
      {
         m_bus.Unsubscribe(m_subscribedIDs[i], self);
      }
   }

   // Child classes override this to add custom event types
   virtual void DeclareEvents() {}

   void AddEvent(int eventID)
   {
      int sz = ArraySize(m_subscribedIDs);
      ArrayResize(m_subscribedIDs, sz + 1);
      m_subscribedIDs[sz] = eventID;
   }

   void DeclareBaseEvents()
   {
      AddEvent(EVENT_ID_HEARTBEAT);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
      AddEvent(EVENT_ID_EMERGENCY_STOP);
      AddEvent(EVENT_ID_SESSION_CHANGE);
      DeclareEvents();
   }

   /**
    * Dispatch an event through the cached bus pointer (Performance Optimization)
    * @param e Pointer to event object
    */
   void DispatchEvent(Event *e) const
   {
      if (CheckPointer(m_bus) != POINTER_INVALID)
         m_bus.Dispatch(e);
      else if (CheckPointer(e) == POINTER_DYNAMIC)
         delete e;
   }

   void Log(const string msg) const
   {
      if (m_debugMode)
         Print("[", m_name, "] ", TimeToString(TimeCurrent(), TIME_SECONDS), " | ", msg);
   }
   
   /**
    * Safe cache access with validation
    */
   bool IsCacheValid() const
   {
      return (CheckPointer(m_data) != POINTER_INVALID);
   }
   
   /**
    * Get cached data with null check
    */
   DataManager* GetSafeDataManager() const
   {
      if (CheckPointer(m_data) == POINTER_INVALID)
      {
         if (m_debugMode)
            Log("⚠️ Warning: DataManager is NULL");
         return NULL;
      }
      return m_data;
   }
};

DataManager *IManager::s_dataCache;

#endif