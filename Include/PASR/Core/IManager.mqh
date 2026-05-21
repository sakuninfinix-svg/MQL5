//+------------------------------------------------------------------+
//| Core/IManager.mqh — CANONICAL v2.15                              |
//| Base class for all PASR managers                                 |
//|                                                                  |
//| CHANGES v2.15 (2026-05-21):                                      |
//|   FIX #8  — m_eventMask (uint) added for declared-event filter  |
//|   FIX #8  — AddEvent() now sets bit in m_eventMask              |
//|   FIX #8  — IsListening(ENUM_EVENT_ID) added for EventBus query |
//|                                                                  |
//| INVARIANTS:                                                      |
//|   - m_cfg is refreshed ONLY via RefreshConfig() / OnConfigReload|
//|   - Never call GetConfigCache() per-function — use m_cfg always  |
//|   - BuildGVPrefix() is the ONLY way to form GV key prefixes     |
//|   - DispatchEvent() is the ONLY way managers push to the bus    |
//|   - AddEvent() in DeclareEvents() sets the filter mask           |
//|   - IsListening() is queried by PASREventBus::Dispatch()        |
//+------------------------------------------------------------------+
#pragma once
#ifndef CORE_IMANAGER_MQH
#define CORE_IMANAGER_MQH

#include "Config/Types.mqh"
#include "EventBus.mqh"

class IDataManager;

class IManager
  {
protected:
   IDataManager     *m_data;        // injected data bus (not owned)
   CEventBus        *m_bus;         // injected event bus (not owned)
   StrategyConfig    m_cfg;         // cached config
   bool              m_cfgDirty;
   bool              m_debugMode;
   uint              m_eventMask;   // FIX #8: bitmask of declared event ids

   void              RefreshConfig()
     {
      if(CheckPointer(m_data) == POINTER_INVALID) return;
      m_data.GetConfigCache(m_cfg);
      m_cfgDirty = false;
     }

   void              DispatchEvent(const PASREvent &ev)
     {
      if(CheckPointer(m_bus) != POINTER_INVALID)
         m_bus.Push(ev);
     }

   void              Log(const string msg)
     {
      if(m_debugMode) Print(msg);
     }

   // FIX #8: AddEvent sets bit in m_eventMask.
   // EVENT_ID values are assumed to fit in bits 0..30.
   // Called by subclass DeclareEvents() only.
   void              AddEvent(ENUM_EVENT_ID id)
     {
      if((int)id >= 0 && (int)id < 32)
         m_eventMask |= (1u << (uint)id);
     }

   string            BuildGVPrefix()
     {
      long login = AccountInfoInteger(ACCOUNT_LOGIN);
      long magic = m_cfg.MagicNumber;
      return "PASR_" + IntegerToString(login) + "_" + IntegerToString(magic) + "_";
     }

public:
   IManager() : m_data(NULL), m_bus(NULL), m_cfgDirty(true),
                m_debugMode(false), m_eventMask(0)
     {}

   virtual bool      Init(IDataManager *data, CEventBus *bus)
     {
      if(CheckPointer(data) == POINTER_INVALID) return false;
      m_data = data;
      m_bus  = bus;
      RefreshConfig();
      DeclareEvents();
      return true;
     }

   virtual void      Deinit()        {}
   virtual void      OnNewBar()      {}
   virtual void      OnPriceUpdate() {}
   virtual void      DeclareEvents() {}

   // FIX #8: queried by PASREventBus::Dispatch() before routing event.
   // If DeclareEvents() was never called / AddEvent() never set this id,
   // returns false and the subscriber is skipped for this event.
   // If m_eventMask == 0 (legacy: DeclareEvents not overridden), returns
   // true for ALL events so existing managers keep working.
   bool              IsListening(ENUM_EVENT_ID id) const
     {
      if(m_eventMask == 0) return true;  // legacy compat: receive all
      if((int)id < 0 || (int)id >= 32)   return false;
      return (m_eventMask & (1u << (uint)id)) != 0;
     }

   virtual bool      IsHealthy() const
     {
      return CheckPointer(m_data) != POINTER_INVALID;
     }

   virtual void      OnConfigReload() { RefreshConfig(); }

   void              SetDebugMode(bool enable) { m_debugMode = enable; }
  };

#endif // CORE_IMANAGER_MQH
