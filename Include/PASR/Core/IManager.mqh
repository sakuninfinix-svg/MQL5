//+------------------------------------------------------------------+
//| Core/IManager.mqh — CANONICAL v2.14                              |
//| Base class for all PASR managers                                 |
//|                                                                  |
//| CHANGES v2.14 (2026-05-21):                                      |
//|   - Replace `struct StrategyConfig` forward declaration with     |
//|     full #include "Config/Types.mqh"                             |
//|   - BuildGVPrefix() confirmed: uses m_cfg.MagicNumber (canonical)|
//|   - RefreshConfig() body added [BUG-004]                         |
//|   - m_debugMode + Log() added [REF-002, REF-003]                 |
//|   - DispatchEvent() helper added [REF-001]                       |
//|   - DeclareEvents() virtual + AddEvent() stubs added [REF-005]   |
//|                                                                  |
//| INVARIANTS:                                                      |
//|   - m_cfg is refreshed ONLY via RefreshConfig() / OnConfigReload |
//|   - Never call GetConfigCache() per-function — use m_cfg always  |
//|   - BuildGVPrefix() is the ONLY way to form GV key prefixes      |
//|   - DispatchEvent() is the ONLY way managers push to the bus     |
//+------------------------------------------------------------------+
#pragma once
#ifndef CORE_IMANAGER_MQH
#define CORE_IMANAGER_MQH

// Full struct definition required — m_cfg is a value-type member
#include "Config/Types.mqh"
#include "EventBus.mqh"

// Forward declarations for dependency-injected pointers only
class IDataManager;

class IManager
  {
protected:
   IDataManager     *m_data;        // injected data bus (not owned)
   CEventBus        *m_bus;         // injected event bus (not owned)
   StrategyConfig    m_cfg;         // cached config — NO per-function copies
   bool              m_cfgDirty;    // true until first RefreshConfig() call
   bool              m_debugMode;   // [REF-002] enable verbose debug prints

   // ─── [BUG-004] RefreshConfig — implementation (was declaration-only) ───
   // Pulls config snapshot from DataManager into m_cfg cache.
   // CALL ONLY in Init() and OnConfigReload() — never on every tick.
   void              RefreshConfig()
     {
      if(CheckPointer(m_data) == POINTER_INVALID) return;
      // IDataManager interface: GetConfigCache(StrategyConfig &out)
      // implemented in Infra/DataManager.mqh
      m_data.GetConfigCache(m_cfg);
      m_cfgDirty = false;
     }

   // ─── [REF-001] DispatchEvent — single path to push events onto the bus ───
   // All managers MUST use this instead of calling m_bus.Push() directly.
   // Guards against null bus pointer (e.g. during unit test stubs).
   void              DispatchEvent(const PASREvent &ev)
     {
      if(CheckPointer(m_bus) != POINTER_INVALID)
         m_bus.Push(ev);
     }

   // ─── [REF-003] Log — gated debug print ───
   void              Log(const string msg)
     {
      if(m_debugMode) Print(msg);
     }

   // ─── [REF-005] AddEvent — stub for subclass DeclareEvents() pattern ───
   // No-op in base class. Subclasses use this in DeclareEvents() to
   // register event interest; actual routing is done by the orchestrator.
   void              AddEvent(ENUM_EVENT_ID /*id*/) {}

   // ─── Build account+magic-namespaced GV prefix ───
   // Format: PASR_{account_login}_{magic_number}_
   // Example: PASR_12345678_100001_
   // INVARIANT: ALL GV keys MUST use this prefix.
   //            Prevents state corruption when two EA instances share
   //            the same magic number on different accounts.
   string            BuildGVPrefix()
     {
      long login = AccountInfoInteger(ACCOUNT_LOGIN);
      long magic = m_cfg.MagicNumber;   // [BUG-006] canonical field name
      return "PASR_" + IntegerToString(login) + "_" + IntegerToString(magic) + "_";
     }

public:
   IManager() : m_data(NULL), m_bus(NULL), m_cfgDirty(true), m_debugMode(false)
     {
      // StrategyConfig has a constructor that sets safe defaults — no ZeroMemory
      // needed. ZeroMemory would overwrite those defaults with zeros.
     }

   // ─── Primary init: inject DataManager + EventBus, then cache config ───
   // Returns false if data pointer is invalid — caller must abort.
   virtual bool      Init(IDataManager *data, CEventBus *bus)
     {
      if(CheckPointer(data) == POINTER_INVALID) return false;
      m_data = data;
      m_bus  = bus;   // bus may be NULL in unit test stubs — that is OK
      RefreshConfig();
      DeclareEvents(); // [REF-005] let subclass register its event interests
      return true;
     }

   virtual void      Deinit()        {}
   virtual void      OnNewBar()      {}
   virtual void      OnPriceUpdate() {}

   // [REF-005] Override in subclass to register event interests via AddEvent()
   virtual void      DeclareEvents() {}

   // Health check: at minimum the data bus must be valid.
   // Subclasses should override to add their own invariant checks.
   virtual bool      IsHealthy() const
     {
      return CheckPointer(m_data) != POINTER_INVALID;
     }

   // Called by orchestrator when EVENT_ID_CONFIG_RELOAD fires.
   // Subclasses with extra state may override; always call super.
   virtual void      OnConfigReload() { RefreshConfig(); }

   // Enable verbose debug output for this manager instance
   void              SetDebugMode(bool enable) { m_debugMode = enable; }
  };

#endif // CORE_IMANAGER_MQH
