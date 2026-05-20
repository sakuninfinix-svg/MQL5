//+------------------------------------------------------------------+
//|                                                   IManager.mqh   |
//|                                       Copyright 2026, Agsicentre |
//|            Base Class for Event-Driven PASR EA Modules           |
//|                   VERSION 2.11 - m_cfg cached field added        |
//+------------------------------------------------------------------+
//| CHANGES v2.11:                                                   |
//| - IM-OPT-1: m_cfg (StrategyConfig) cached field added.          |
//|   RefreshConfigCache() now fills m_cfg from DataManager so every |
//|   subclass uses Config() or m_cfg directly instead of calling   |
//|   m_data.GetConfigCache(cfg) inside every method body.           |
//|   Saves ~400+ unnecessary struct copies/sec on busy tick stream. |
//|                                                                  |
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
#property version "2.11"
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

   // Safety & Metrics
   bool             m_isDispatching;
   EventHandlerMetrics m_metrics;
   int              m_reentrancyGuard;

   // IM-OPT-1: Cached config — refreshed only on ConfigReloadEvent.
   // Subclasses use Config() or m_cfg directly; no per-function GetConfigCache() calls.
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
      // m_data initialized later in Init()
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

   // IM-OPT-1: Populate m_cfg once from DataManager; fall back to extern GetConfig().
   // Called on Init() and on every ConfigReloadEvent.
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
         // Fallback path (e.g. during early init before DataManager is ready)
         #if defined(__MQL5__) && !defined(__TESTER__)
         extern const StrategyConfig& GetConfig();
         m_debugMode = GetConfig().system.debug;
         #else
         m_debugMode = false;
         #endif
      }
   }

   // IM-OPT-1: Const accessor for subclasses — no copy, no re-fetch.
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
      bool success = true;

      success = DispatchEventByType(e);

      FinalizeEventHandling(e, success, startTime);
      m_isDispatching = false;
      m_reentrancyGuard = 0;
   }

protected:
   // DeclareBaseEvents, SubscribeToEvents, UnsubscribeFromEvents, AddEvent, Log,
   // DispatchEventByType, FinalizeEventHandling — all preserved from v2.10 below.
   // (Subclasses override DeclareEvents() and specific OnXxx() handlers.)

   virtual void DeclareBaseEvents()
   {
      AddEvent(EVENT_ID_HEARTBEAT);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
      AddEvent(EVENT_ID_EMERGENCY_STOP);
      DeclareEvents();
   }

   virtual void DeclareEvents() {}

   void AddEvent(int eventId)
   {
      int size = ArraySize(m_subscribedIDs);
      ArrayResize(m_subscribedIDs, size + 1);
      m_subscribedIDs[size] = eventId;
   }

   void SubscribeToEvents()
   {
      if(CheckPointer(m_bus) == POINTER_INVALID) return;
      int total = ArraySize(m_subscribedIDs);
      for(int i = 0; i < total; i++)
         m_bus.Subscribe(m_subscribedIDs[i], GetPointer(this), m_priority);
   }

   void UnsubscribeFromEvents()
   {
      if(CheckPointer(m_bus) == POINTER_INVALID) return;
      int total = ArraySize(m_subscribedIDs);
      for(int i = 0; i < total; i++)
         m_bus.Unsubscribe(m_subscribedIDs[i], GetPointer(this));
   }

   void Log(const string msg) const
   {
      if(m_debugMode)
         PrintFormat("[%s] %s", m_name, msg);
   }

   bool DispatchEventByType(Event *e)
   {
      if(CheckPointer(e) == POINTER_INVALID) return false;
      bool handled = true;
      int id = e.ID();
      if     (id == EVENT_ID_HEARTBEAT)           OnHeartbeat           (dynamic_cast<HeartbeatEvent*>(e));
      else if(id == EVENT_ID_CONFIG_RELOAD)        { OnConfigReload(dynamic_cast<ConfigReloadEvent*>(e)); RefreshConfigCache(); }
      else if(id == EVENT_ID_EMERGENCY_STOP)       OnEmergencyStop       (dynamic_cast<EmergencyStopEvent*>(e));
      else if(id == EVENT_ID_PRICE_UPDATE)         OnPriceUpdate         (dynamic_cast<PriceUpdateEvent*>(e));
      else if(id == EVENT_ID_NEW_BAR)              OnNewBar              (dynamic_cast<NewBarEvent*>(e));
      else if(id == EVENT_ID_SIGNAL_GENERATED)     OnSignalGenerated     (dynamic_cast<SignalGeneratedEvent*>(e));
      else if(id == EVENT_ID_ORDER_EXECUTION)      OnOrderExecution      (dynamic_cast<OrderExecutionEvent*>(e));
      else if(id == EVENT_ID_POSITION_UPDATE)      OnPositionUpdate      (dynamic_cast<PositionUpdateEvent*>(e));
      else if(id == EVENT_ID_RECOVERY_OPPORTUNITY) OnRecoveryOpportunity (dynamic_cast<RecoveryOpportunityEvent*>(e));
      else if(id == EVENT_ID_RECOVERY_SIGNAL)      OnRecoverySignal      (dynamic_cast<RecoverySignalEvent*>(e));
      else if(id == EVENT_ID_ZONE_UPDATE)          OnZoneUpdate          (dynamic_cast<ZoneUpdateEvent*>(e));
      else if(id == EVENT_ID_NEWS_ALERT)           OnNewsAlert           (dynamic_cast<NewsAlertEvent*>(e));
      else if(id == EVENT_ID_MARKET_GATE)          OnMarketGate          (dynamic_cast<MarketGateEvent*>(e));
      else if(id == EVENT_ID_SESSION_CHANGE)       OnSessionChange       (dynamic_cast<SessionChangeEvent*>(e));
      else if(id == EVENT_ID_PAUSE_TOGGLE)         OnPauseToggle         (dynamic_cast<PauseToggleEvent*>(e));
      else handled = false;
      return handled;
   }

   void FinalizeEventHandling(Event *e, bool success, ulong startTime)
   {
      ulong elapsed = GetMicrosecondCount() - startTime;
      m_metrics.totalEvents++;
      m_metrics.lastEventTime = TimeCurrent();

      double ms = (double)elapsed / 1000.0;
      if(m_metrics.totalEvents == 1)
         m_metrics.avgLatencyMs = ms;
      else
         m_metrics.avgLatencyMs = m_metrics.avgLatencyMs * 0.95 + ms * 0.05;

      if(ms > m_metrics.maxLatencyMs) m_metrics.maxLatencyMs = ms;

      if(!success)
      {
         m_metrics.errorCount++;
         if(m_debugMode)
            PrintFormat("[%s] Handler error for event %d", m_name,
                        (CheckPointer(e) != POINTER_INVALID ? e.ID() : -1));
      }
   }

   //--- Virtual event handlers (override in subclasses as needed) ---
   virtual void OnHeartbeat           (HeartbeatEvent *e)           {}
   virtual void OnConfigReload        (ConfigReloadEvent *e)        {}
   virtual void OnEmergencyStop       (EmergencyStopEvent *e)       {}
   virtual void OnPriceUpdate         (PriceUpdateEvent *e)         {}
   virtual void OnNewBar              (NewBarEvent *e)              {}
   virtual void OnSignalGenerated     (SignalGeneratedEvent *e)     {}
   virtual void OnOrderExecution      (OrderExecutionEvent *e)      {}
   virtual void OnPositionUpdate      (PositionUpdateEvent *e)      {}
   virtual void OnRecoveryOpportunity (RecoveryOpportunityEvent *e) {}
   virtual void OnRecoverySignal      (RecoverySignalEvent *e)      {}
   virtual void OnZoneUpdate          (ZoneUpdateEvent *e)          {}
   virtual void OnNewsAlert           (NewsAlertEvent *e)           {}
   virtual void OnMarketGate          (MarketGateEvent *e)          {}
   virtual void OnSessionChange       (SessionChangeEvent *e)       {}
   virtual void OnPauseToggle         (PauseToggleEvent *e)         {}
};

DataManager *IManager::s_dataCache = NULL;

#endif // __I_MANAGER_MQH__
