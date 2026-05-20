//+------------------------------------------------------------------+
//| Core/IManager.mqh — CANONICAL v2.13                              |
//| Base class for all PASR managers                                 |
//| - m_cfg cached config (refresh on ConfigReloadEvent only)        |
//| - m_bus EventBus wiring                                          |
//| - BuildGVPrefix: account-safe GlobalVariable key prefix          |
//+------------------------------------------------------------------+
#pragma once
#ifndef CORE_IMANAGER_MQH
#define CORE_IMANAGER_MQH

#include "EventBus.mqh"

// Forward declarations
struct StrategyConfig;
class  IDataManager;

class IManager
  {
protected:
   IDataManager     *m_data;       // injected data bus
   CEventBus        *m_bus;        // injected event bus
   StrategyConfig    m_cfg;        // cached config — NO per-function copies
   bool              m_cfgDirty;

   //--- Refresh cached config from DataManager
   //--- Call once on Init(), then only on EVENT_ID_CONFIG_RELOAD
   void              RefreshConfig();

   //--- Account+magic namespaced GV prefix
   //--- Format: PASR_{login}_{magic}_
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

   //--- Primary init: receives both DataManager and EventBus
   virtual bool      Init(IDataManager *data, CEventBus *bus)
     {
      if(CheckPointer(data) == POINTER_INVALID) return false;
      m_data = data;
      m_bus  = bus;
      RefreshConfig();
      return true;
     }

   virtual void      Deinit()       {}
   virtual void      OnNewBar()     {}
   virtual void      OnPriceUpdate(){}
   virtual bool      IsHealthy() const { return CheckPointer(m_data) != POINTER_INVALID; }

   //--- Called by orchestrator when EVENT_ID_CONFIG_RELOAD fires
   virtual void      OnConfigReload() { RefreshConfig(); }
  };

#endif // CORE_IMANAGER_MQH
