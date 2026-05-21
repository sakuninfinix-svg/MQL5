//+------------------------------------------------------------------+
//| Core/IManager.mqh — CANONICAL v2.14                              |
//| Base class for all PASR managers                                 |
//|                                                                  |
//| CHANGES v2.14 (2026-05-21):                                      |
//|   - Replace `struct StrategyConfig` forward declaration with     |
//|     full #include "Config/Types.mqh"                             |
//|     Forward decl is insufficient for value-type member m_cfg     |
//|     (compiler needs full struct layout to size the class)        |
//|   - BuildGVPrefix() confirmed correct: account+magic prefix      |
//|   - No functional changes — wiring fix only                      |
//|                                                                  |
//| INVARIANTS:                                                      |
//|   - m_cfg is refreshed ONLY via RefreshConfig() / OnConfigReload |
//|   - Never call GetConfigCache() per-function — use m_cfg always  |
//|   - BuildGVPrefix() is the ONLY way to form GV key prefixes      |
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
   IDataManager     *m_data;       // injected data bus (not owned)
   CEventBus        *m_bus;        // injected event bus (not owned)
   StrategyConfig    m_cfg;        // cached config — NO per-function copies
   bool              m_cfgDirty;   // true until first RefreshConfig() call

   //--- Refresh cached config from DataManager.
   //--- Call once on Init(), then ONLY on EVENT_ID_CONFIG_RELOAD.
   //--- Never call on every tick — struct copy is expensive.
   void              RefreshConfig();

   //--- Build an account+magic namespaced GlobalVariable key prefix.
   //--- Format: PASR_{account_login}_{magic_number}_
   //--- Example: PASR_12345678_100001_
   //--- INVARIANT: ALL GV keys in the framework MUST use this prefix.
   //---            This prevents state corruption when two EA instances
   //---            share the same magic number on different accounts.
   string            BuildGVPrefix()
     {
      long login = AccountInfoInteger(ACCOUNT_LOGIN);
      long magic = (long)m_cfg.MagicNumber;
      return "PASR_" + IntegerToString(login) + "_" + IntegerToString(magic) + "_";
     }

public:
   IManager() : m_data(NULL), m_bus(NULL), m_cfgDirty(true)
     {
      ZeroMemory(m_cfg);
     }

   //--- Primary init: inject DataManager + EventBus, then cache config.
   //--- Returns false if data pointer is invalid — caller must abort.
   virtual bool      Init(IDataManager *data, CEventBus *bus)
     {
      if(CheckPointer(data) == POINTER_INVALID) return false;
      m_data = data;
      m_bus  = bus;
      RefreshConfig();
      return true;
     }

   virtual void      Deinit()        {}
   virtual void      OnNewBar()      {}
   virtual void      OnPriceUpdate() {}

   //--- Health check: at minimum the data bus must be valid.
   //--- Subclasses should override to add their own invariant checks.
   virtual bool      IsHealthy() const
     {
      return CheckPointer(m_data) != POINTER_INVALID;
     }

   //--- Called by orchestrator when EVENT_ID_CONFIG_RELOAD fires.
   //--- Subclasses with extra state may override; always call super.
   virtual void      OnConfigReload() { RefreshConfig(); }
  };

#endif // CORE_IMANAGER_MQH
