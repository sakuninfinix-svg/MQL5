//+------------------------------------------------------------------+
//|                                                   IManager.mqh   |
//|              Base Class for Event-Driven PASR EA Modules         |
//|                                     Copyright 2026, Agsicentre   |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "1.00"
#property strict

#ifndef __I_MANAGER_MQH__
#define __I_MANAGER_MQH__

#include "2.Config.mqh"
#include "0.EventBus.mqh"
#include "1.Events.mqh"

class DataManager;

//+------------------------------------------------------------------+
//| IManager - Template Base Class                                  |
//| Provides: Lifecycle, Auto-Subscription, Config Cache, Logging   |
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
      if (CheckPointer(m_data) == POINTER_INVALID && m_name != "DataManager")
      {
         if (CheckPointer(s_dataCache) == POINTER_INVALID)
         {
            PrintFormat("[%s] CRITICAL: Global Data Cache is NULL during Init.", m_name);
            return false;
         }
         m_data = s_dataCache;
      }

      if (CheckPointer(m_bus) == POINTER_INVALID)
      {
         Log("CRITICAL: EventBus not available.");
         return false;
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

   virtual void RefreshConfigCache()
   {
      m_debugMode = CFG.system.debug;
   }

   virtual void HandleEvent(Event *e) override
   {
      if (CheckPointer(e) == POINTER_INVALID || !m_initialized)
         return;
      switch (e.ID())
      {
      case EVENT_ID_PRICE_UPDATE:
         OnPriceUpdate(CAST_EVENT(PriceUpdateEvent, e));
         break;
      case EVENT_ID_NEW_BAR:
         OnNewBar(CAST_EVENT(NewBarEvent, e));
         break;
      case EVENT_ID_HEARTBEAT:
         OnHeartbeat(CAST_EVENT(HeartbeatEvent, e));
         break;
      case EVENT_ID_CONFIG_RELOAD:
         OnConfigReload(CAST_EVENT(ConfigReloadEvent, e));
         break;
      case EVENT_ID_EMERGENCY_STOP:
         OnEmergencyStop(CAST_EVENT(EmergencyStopEvent, e));
         break;
      case EVENT_ID_SIGNAL_GENERATED:
         OnSignalGenerated(CAST_EVENT(SignalGeneratedEvent, e));
         break;
      case EVENT_ID_RECOVERY_OPPORTUNITY:
         OnRecoveryOpportunity(CAST_EVENT(RecoveryOpportunityEvent, e));
         break;
      case EVENT_ID_RECOVERY_SIGNAL:
         OnRecoverySignal(CAST_EVENT(RecoverySignalEvent, e));
         break;
      case EVENT_ID_ORDER_EXECUTION:
         OnOrderExecution(CAST_EVENT(OrderExecutionEvent, e));
         break;
      case EVENT_ID_POSITION_UPDATE:
         OnPositionUpdate(CAST_EVENT(PositionUpdateEvent, e));
         break;
      case EVENT_ID_ZONE_UPDATE:
         OnZoneUpdate(CAST_EVENT(ZoneUpdateEvent, e));
         break;
      case EVENT_ID_MARKET_GATE:
         OnMarketGate(CAST_EVENT(MarketGateEvent, e));
         break;
      case EVENT_ID_PAUSE_TOGGLE:
         OnPauseToggle(CAST_EVENT(PauseToggleEvent, e));
         break;
      case EVENT_ID_NEWS_ALERT:
         OnNewsAlert(CAST_EVENT(NewsAlertEvent, e));
         break;
      default:
         OnCustomEvent(e);
         break;
      }
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
};

DataManager *IManager::s_dataCache;

#endif