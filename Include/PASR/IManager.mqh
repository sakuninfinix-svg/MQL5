//+------------------------------------------------------------------+
//|                                                   IManager.mqh   |
//|                                       Copyright 2026, Agsicentre |
//|            Base Class for Event-Driven PASR EA Modules           |
//|                   VERSION 2.01 - Fixed SessionChangeEvent        |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "2.01"
#property strict

#ifndef __I_MANAGER_MQH__
#define __I_MANAGER_MQH__

#include "0.EventBus.mqh"
#include "1.Events.mqh"
#include "2.Config.Types.mqh"
#include "2.Config.Manager.mqh"

class DataManager;

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
   
   EventHandlerMetrics()
   {
      totalEvents = 0;
      errorCount = 0;
      lastEventTime = 0;
      avgLatencyMs = 0.0;
      maxLatencyMs = 0.0;
   }
};

//+------------------------------------------------------------------+
//| IManager - Template Base Class V2.0                              |
//| Provides: Lifecycle, Auto-Subscription, Config Cache, Logging    |
//|          Memory Safety, Re-entrancy Protection, Metrics          |
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
      m_debugMode = CFG.system.debug;
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
      m_debugMode = CFG.system.debug;
   }

   virtual void HandleEvent(Event *e) override
   {
      // Null check
      if (CheckPointer(e) == POINTER_INVALID || !m_initialized)
         return;
      
      // Re-entrancy protection
      if (m_isDispatching)
      {
         m_reentrancyGuard++;
         if (m_debugMode && m_reentrancyGuard > 1)
         {
            Log("⚠️ Re-entrancy detected! Guard count: " + IntegerToString(m_reentrancyGuard));
         }
         return;
      }
      
      m_isDispatching = true;
      ulong startTime = GetMicrosecondCount();
      
      bool success = true;
      string eventName = e.Name();
      int eventID = e.ID();
      
      // Type-safe casting with validation
      PriceUpdateEvent *priceEvt = NULL;
      NewBarEvent *barEvt = NULL;
      HeartbeatEvent *hbEvt = NULL;
      ConfigReloadEvent *cfgEvt = NULL;
      EmergencyStopEvent *emergEvt = NULL;
      SignalGeneratedEvent *sigEvt = NULL;
      RecoveryOpportunityEvent *recOppEvt = NULL;
      RecoverySignalEvent *recSigEvt = NULL;
      OrderExecutionEvent *ordEvt = NULL;
      PositionUpdateEvent *posEvt = NULL;
      ZoneUpdateEvent *zoneEvt = NULL;
      MarketGateEvent *gateEvt = NULL;
      PauseToggleEvent *pauseEvt = NULL;
      NewsAlertEvent *newsEvt = NULL;
      SessionChangeEvent *sessEvt = NULL;
      
      // MQL5 native error handling: use GetLastError() pattern instead of try-catch
      ResetLastError();
      int preErrorCount = GetLastError();
      
      switch (eventID)
      {
      case EVENT_ID_PRICE_UPDATE:
         priceEvt = CAST_EVENT(PriceUpdateEvent, e);
         if (CheckPointer(priceEvt) != POINTER_INVALID)
            OnPriceUpdate(priceEvt);
         else
            success = false;
         break;
         
      case EVENT_ID_NEW_BAR:
         barEvt = CAST_EVENT(NewBarEvent, e);
         if (CheckPointer(barEvt) != POINTER_INVALID)
            OnNewBar(barEvt);
         else
            success = false;
         break;
         
      case EVENT_ID_HEARTBEAT:
         hbEvt = CAST_EVENT(HeartbeatEvent, e);
         if (CheckPointer(hbEvt) != POINTER_INVALID)
            OnHeartbeat(hbEvt);
         else
            success = false;
         break;
         
      case EVENT_ID_CONFIG_RELOAD:
         cfgEvt = CAST_EVENT(ConfigReloadEvent, e);
         if (CheckPointer(cfgEvt) != POINTER_INVALID)
            OnConfigReload(cfgEvt);
         else
            success = false;
         break;
         
      case EVENT_ID_EMERGENCY_STOP:
         emergEvt = CAST_EVENT(EmergencyStopEvent, e);
         if (CheckPointer(emergEvt) != POINTER_INVALID)
            OnEmergencyStop(emergEvt);
         else
            success = false;
         break;
         
      case EVENT_ID_SIGNAL_GENERATED:
         sigEvt = CAST_EVENT(SignalGeneratedEvent, e);
         if (CheckPointer(sigEvt) != POINTER_INVALID)
            OnSignalGenerated(sigEvt);
         else
            success = false;
         break;
         
      case EVENT_ID_RECOVERY_OPPORTUNITY:
         recOppEvt = CAST_EVENT(RecoveryOpportunityEvent, e);
         if (CheckPointer(recOppEvt) != POINTER_INVALID)
            OnRecoveryOpportunity(recOppEvt);
         else
            success = false;
         break;
         
      case EVENT_ID_RECOVERY_SIGNAL:
         recSigEvt = CAST_EVENT(RecoverySignalEvent, e);
         if (CheckPointer(recSigEvt) != POINTER_INVALID)
            OnRecoverySignal(recSigEvt);
         else
            success = false;
         break;
         
      case EVENT_ID_ORDER_EXECUTION:
         ordEvt = CAST_EVENT(OrderExecutionEvent, e);
         if (CheckPointer(ordEvt) != POINTER_INVALID)
            OnOrderExecution(ordEvt);
         else
            success = false;
         break;
         
      case EVENT_ID_POSITION_UPDATE:
         posEvt = CAST_EVENT(PositionUpdateEvent, e);
         if (CheckPointer(posEvt) != POINTER_INVALID)
            OnPositionUpdate(posEvt);
         else
            success = false;
         break;
         
      case EVENT_ID_ZONE_UPDATE:
         zoneEvt = CAST_EVENT(ZoneUpdateEvent, e);
         if (CheckPointer(zoneEvt) != POINTER_INVALID)
            OnZoneUpdate(zoneEvt);
         else
            success = false;
         break;
         
      case EVENT_ID_MARKET_GATE:
         gateEvt = CAST_EVENT(MarketGateEvent, e);
         if (CheckPointer(gateEvt) != POINTER_INVALID)
            OnMarketGate(gateEvt);
         else
            success = false;
         break;
         
      case EVENT_ID_PAUSE_TOGGLE:
         pauseEvt = CAST_EVENT(PauseToggleEvent, e);
         if (CheckPointer(pauseEvt) != POINTER_INVALID)
            OnPauseToggle(pauseEvt);
         else
            success = false;
         break;
         
      case EVENT_ID_SESSION_CHANGE:
         sessEvt = CAST_EVENT(SessionChangeEvent, e);
         if (CheckPointer(sessEvt) != POINTER_INVALID)
            OnSessionChange(sessEvt);
         else
            success = false;
         break;
         
      case EVENT_ID_NEWS_ALERT:
         newsEvt = CAST_EVENT(NewsAlertEvent, e);
         if (CheckPointer(newsEvt) != POINTER_INVALID)
            OnNewsAlert(newsEvt);
         else
            success = false;
         break;
         
      default:
         OnCustomEvent(e);
         break;
      }
      
      // Check for errors after handler execution
      int postErrorCount = GetLastError();
      if (postErrorCount != preErrorCount && postErrorCount != 0)
      {
         success = false;
         PrintFormat("[%s] ERROR: Handler error for %s: Error %d", m_name, eventName, postErrorCount);
         ResetLastError();
      }
      
      // Calculate latency
      ulong endTime = GetMicrosecondCount();
      double latencyMs = (endTime - startTime) / 1000.0;
      
      // Update metrics
      m_metrics.totalEvents++;
      m_metrics.lastEventTime = TimeCurrent();
      
      if (!success)
         m_metrics.errorCount++;
      
      // Update average latency
      double totalLatency = m_metrics.avgLatencyMs * (m_metrics.totalEvents - 1);
      m_metrics.avgLatencyMs = (totalLatency + latencyMs) / m_metrics.totalEvents;
      
      if (latencyMs > m_metrics.maxLatencyMs)
         m_metrics.maxLatencyMs = latencyMs;
      
      // Error logging
      if (!success && m_debugMode)
      {
         Log("❌ Error processing event: " + eventName + " (ID: " + IntegerToString(eventID) + ")");
      }
      
      // High latency warning
      if (latencyMs > 10.0 && m_debugMode)
      {
         Log("⚠️ High latency detected: " + DoubleToString(latencyMs, 3) + "ms for " + eventName);
      }
      
      m_isDispatching = false;
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