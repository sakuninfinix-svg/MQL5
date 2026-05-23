//+------------------------------------------------------------------+
//| Core/IManager.mqh — CANONICAL v2.16                              |
//| Base class for all PASR managers                                 |
//|                                                                  |
//| CHANGES v2.16 (2026-05-24):                                      |
//|   BUG-013 — RefreshConfig(): NULL guard before CheckPointer       |
//|             IDataManager* may not be CObject-derived; plain NULL  |
//|             check is safe for any pointer type.                   |
//|   BUG-014 — Init(): assign m_bus BEFORE calling DeclareEvents()   |
//|             Some subclasses call DispatchEvent() in DeclareEvents |
//|             to broadcast readiness. Without m_bus assigned first  |
//|             that event is silently dropped.                        |
//|   BUG-015 — IsListening(): legacy compat (mask==0) now EXCLUDES   |
//|             PASR_MASK_NOISY_EVENTS to prevent flooding managers    |
//|             that never overrode DeclareEvents() with tick events.  |
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

// BUG-015: Bitmask of high-frequency events that should NOT be
// delivered to legacy managers (mask==0) that never declared events.
// These events fire on every tick/bar-end and would flood any manager
// that simply forgot to override DeclareEvents().
// Values correspond to bit positions: (1u << (uint)EVENT_ID_xxx)
// EVENT_ID_PRICE_UPDATE = 1, EVENT_ID_TICK_DONE = 2
// Update this mask if new noisy event IDs are added.
static const uint PASR_MASK_NOISY_EVENTS = (1u << 1) | (1u << 2); // ids 1,2

class IManager
  {
protected:
   IDataManager     *m_data;        // injected data bus (not owned)
   CEventBus        *m_bus;         // injected event bus (not owned)
   StrategyConfig    m_cfg;         // cached config
   bool              m_cfgDirty;
   bool              m_debugMode;
   uint              m_eventMask;   // bitmask of declared event ids

   void              RefreshConfig()
     {
      // BUG-013 FIX: IDataManager* may not be CObject-derived.
      // Plain NULL check is safe for any pointer type.
      // Keep CheckPointer as secondary guard for CObject-derived impls.
      if(m_data == NULL) return;
      if(CheckPointer(m_data) == POINTER_INVALID) return;
      m_data.GetConfigCache(m_cfg);
      m_cfgDirty = false;
     }

   void              DispatchEvent(const PASREvent &ev)
     {
      if(m_bus == NULL) return;
      if(CheckPointer(m_bus) == POINTER_INVALID) return;
      m_bus.Push(ev);
     }

   void              Log(const string msg)
     {
      if(m_debugMode) Print(msg);
     }

   // AddEvent sets bit in m_eventMask.
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
      if(data == NULL) return false;
      if(CheckPointer(data) == POINTER_INVALID) return false;

      m_data = data;

      // BUG-014 FIX: Assign m_bus BEFORE calling DeclareEvents().
      // Subclasses that call DispatchEvent() inside DeclareEvents()
      // (e.g. to announce manager readiness) need m_bus valid.
      m_bus = bus;

      RefreshConfig();
      DeclareEvents();
      return true;
     }

   virtual void      Deinit()        {}
   virtual void      OnNewBar()      {}
   virtual void      OnPriceUpdate() {}
   virtual void      DeclareEvents() {}

   // IsListening() is queried by PASREventBus::Dispatch() before routing.
   //
   // BUG-015 FIX: Legacy compat (m_eventMask == 0) now EXCLUDES noisy
   // events (PRICE_UPDATE, TICK_DONE) to prevent flooding managers that
   // never overrode DeclareEvents(). All other events pass through as
   // before — backward compat is preserved for non-tick events.
   //
   // A manager that explicitly wants tick events MUST call:
   //   AddEvent(EVENT_ID_PRICE_UPDATE);
   // in its DeclareEvents() override. Then m_eventMask != 0 and the
   // normal bitmask path applies (no legacy compat).
   bool              IsListening(ENUM_EVENT_ID id) const
     {
      if(m_eventMask == 0)
        {
         // Legacy compat: receive all EXCEPT noisy high-frequency events
         if((int)id >= 0 && (int)id < 32)
            return (PASR_MASK_NOISY_EVENTS & (1u << (uint)id)) == 0;
         return true;
        }
      if((int)id < 0 || (int)id >= 32) return false;
      return (m_eventMask & (1u << (uint)id)) != 0;
     }

   virtual bool      IsHealthy() const
     {
      return (m_data != NULL && CheckPointer(m_data) != POINTER_INVALID);
     }

   virtual void      OnConfigReload() { RefreshConfig(); }

   void              SetDebugMode(bool enable) { m_debugMode = enable; }
  };

#endif // CORE_IMANAGER_MQH
