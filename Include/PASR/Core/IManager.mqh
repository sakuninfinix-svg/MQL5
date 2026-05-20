//+------------------------------------------------------------------+
//|                                             Core/IManager.mqh    |
//|                                       Copyright 2026, Agsicentre |
//|            Base Class for Event-Driven PASR EA Modules           |
//|                   VERSION 2.11 - m_cfg cached field added        |
//+------------------------------------------------------------------+
//| Migrated from IManager.mqh as part of Core layer refactoring.   |
//| The root IManager.mqh is now a shim that re-includes this file. |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "2.11"
#property strict

#ifndef __CORE_I_MANAGER_MQH__
#define __CORE_I_MANAGER_MQH__

#include "EventBus.mqh"
#include "Config/Types.mqh"

// Forward declarations
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
   ulong  totalEvents;
   ulong  errorCount;
   ulong  lastEventTime;
   double avgLatencyMs;
   double maxLatencyMs;

   EventHandlerMetrics()
      : totalEvents(0), errorCount(0), lastEventTime(0),
        avgLatencyMs(0.0), maxLatencyMs(0.0) {}
};

//+------------------------------------------------------------------+
//| IManager - Template Base Class V2.11                             |
//| Provides: Lifecycle, Auto-Subscription, Config Cache, Logging    |
//|          Memory Safety, Re-entrancy Protection, Metrics          |
//+------------------------------------------------------------------+
class IManager : public IEventHandler
{
protected:
   string           m_name;
   bool             m_initialized;
   int              m_subscribedIDs[];
   int              m_priority;
   EventBus        *m_bus;
   DataManager     *m_data;
   bool             m_debugMode;

   string           m_symbol;
   ENUM_TIMEFRAMES  m_period;
   static DataManager *s_dataCache;

   bool             m_isDispatching;
   EventHandlerMetrics m_metrics;
   int              m_reentrancyGuard;

   // IM-OPT-1: Cached config — refreshed only on ConfigReloadEvent
   StrategyConfig   m_cfg;
   bool             m_cfgLoaded;

public:
   IManager(const string name, int priority = 50)
   {
      m_name            = name;
      m_initialized     = false;
      m_priority        = priority;
      m_debugMode       = false;
      m_bus             = EventBus::Instance();
      m_symbol          = _Symbol;
      m_period          = _Period;
      m_isDispatching   = false;
      m_reentrancyGuard = 0;
      m_cfgLoaded       = false;
      ZeroMemory(m_cfg);
   }

   static void SetGlobalDataManager(DataManager *d) { s_dataCache = d; }
   static DataManager *GetGlobalDataManager()       { return s_dataCache; }

   virtual ~IManager()
   {
      if(m_initialized) Deinit();
      ArrayFree(m_subscribedIDs);
   }

   virtual bool Init()
   {
      if(m_initialized) return true;

      if(CheckPointer(m_bus) == POINTER_INVALID)
      {
         PrintFormat("[%s] CRITICAL: EventBus not available during Init.", m_name);
         return false;
      }

      if(CheckPointer(m_data) == POINTER_INVALID && m_name != "DataManager")
      {
         if(CheckPointer(s_dataCache) == POINTER_INVALID)
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
      if(!m_initialized) return;
      UnsubscribeFromEvents();
      m_initialized = false;
      Log("🛑 Deinitialized.");
   }

   void SetDataManager(DataManager *manager) { m_data = manager; }
   DataManager *GetDataManager() const       { return m_data; }

   virtual string GetHandlerName() const override { return m_name; }

   virtual void RefreshConfigCache()
   {
      if(CheckPointer(m_data) != POINTER_INVALID)
      {
         m_data.GetConfigCache(m_cfg);
         m_cfgLoaded = true;
         m_debugMode = m_cfg.system.debug;
      }
      else
      {
         #if defined(__MQL5__) && !defined(__TESTER__)
         extern const StrategyConfig& GetConfig();
         m_debugMode = GetConfig().system.debug;
         #else
         m_debugMode = false;
         #endif
      }
   }

   const StrategyConfig& Config() const { return m_cfg; }

   virtual void HandleEvent(Event *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID || !m_initialized) return;

      if(m_isDispatching)
      {
         m_reentrancyGuard++;
         if(m_debugMode && m_reentrancyGuard > 1)
            Log("⚠️ Re-entrancy detected! Guard: " + IntegerToString(m_reentrancyGuard));
         return;
      }

      m_isDispatching = true;
      const ulong startTime = GetMicrosecondCount();

      DispatchToHandlers(e);

      const ulong elapsed = GetMicrosecondCount() - startTime;
      UpdateMetrics(elapsed);

      m_isDispatching   = false;
      m_reentrancyGuard = 0;
   }

protected:
   // ---- Lifecycle hooks (override in subclass) --------------------
   virtual void DeclareBaseEvents()  {}
   virtual void SubscribeToEvents()  {}
   virtual void UnsubscribeFromEvents() {}
   virtual void DispatchToHandlers(Event *e) {}

   // ---- Subscription helpers -------------------------------------
   void Subscribe(int eventId, int priority = -1)
   {
      if(CheckPointer(m_bus) == POINTER_INVALID) return;
      int p = (priority < 0) ? m_priority : priority;
      if(m_bus.Subscribe(eventId, this, p))
      {
         int size = ArraySize(m_subscribedIDs);
         ArrayResize(m_subscribedIDs, size + 1);
         m_subscribedIDs[size] = eventId;
      }
   }

   void UnsubscribeAll()
   {
      if(CheckPointer(m_bus) == POINTER_INVALID) return;
      for(int i = 0; i < ArraySize(m_subscribedIDs); i++)
         m_bus.Unsubscribe(m_subscribedIDs[i], this);
      ArrayResize(m_subscribedIDs, 0);
   }

   // ---- Logging --------------------------------------------------
   void Log(const string msg) const
   {
      if(m_debugMode)
         PrintFormat("[%s] %s", m_name, msg);
   }

   void LogError(const string msg) const
   {
      PrintFormat("[%s] ERROR: %s", m_name, msg);
   }

   // ---- Metrics --------------------------------------------------
   void UpdateMetrics(ulong elapsedUs)
   {
      m_metrics.totalEvents++;
      m_metrics.lastEventTime = TimeCurrent();
      double ms = (double)elapsedUs / 1000.0;
      m_metrics.avgLatencyMs = (m_metrics.avgLatencyMs * (m_metrics.totalEvents - 1) + ms)
                               / m_metrics.totalEvents;
      if(ms > m_metrics.maxLatencyMs) m_metrics.maxLatencyMs = ms;
   }

public:
   const EventHandlerMetrics& GetMetrics() const { return m_metrics; }

   bool IsInitialized()   const { return m_initialized; }
   int  GetPriority()     const { return m_priority; }
   string GetName()       const { return m_name; }
};

// Static member definition
DataManager *IManager::s_dataCache = NULL;

#endif // __CORE_I_MANAGER_MQH__
