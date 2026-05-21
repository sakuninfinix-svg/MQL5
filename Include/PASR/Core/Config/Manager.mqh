//+------------------------------------------------------------------+
//|                                      Core/Config/Manager.mqh    |
//|                                      Copyright 2026, Agsicentre |
//|                                                                  |
//|  PURPOSE: CConfigManager — load, validate, distribute config.   |
//|    - Reads StrategyConfig built by EA OnInit()                   |
//|    - Calls CConfigValidator::Validate() before every dispatch   |
//|    - Publishes EVENT_CONFIG_RELOAD via EventBus                  |
//|    - All managers update their m_cfg in response to that event  |
//|    - ConfigReload is the ONLY channel config reaches managers    |
//|    - GetConfig() returns by value — no raw pointer leaks        |
//|                                                                  |
//|  INVARIANT: m_cfgValid == true  <==>  m_cfg passed Validate()   |
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_CONFIG_MANAGER_MQH__
#define __CORE_CONFIG_MANAGER_MQH__

#include "Types.mqh"
#include "Validator.mqh"
#include "../EventBus.mqh"
#include "../Events.mqh"

//+------------------------------------------------------------------+
//| CConfigManager                                                   |
//+------------------------------------------------------------------+
class CConfigManager
  {
private:
   StrategyConfig  m_cfg;         // single canonical config instance
   bool            m_cfgValid;    // true only after successful Validate()
   CEventBus      *m_bus;         // injected EventBus (not owned)
   datetime        m_lastReload;  // timestamp of last successful reload

   //--- Patch fields that can never come from EA input parameters
   void ApplyDefaults(StrategyConfig &cfg)
     {
      if(StringLen(cfg.EAName) == 0)  cfg.EAName  = "PASR";
      if(StringLen(cfg.Version) == 0) cfg.Version = "2.0.0";
      if(cfg.MagicNumber <= 0)        cfg.MagicNumber = 123456;
     }

public:
   CConfigManager()
      : m_cfgValid(false), m_bus(NULL), m_lastReload(0) {}

   //--- Inject EventBus before calling Init()
   void SetEventBus(CEventBus *bus) { m_bus = bus; }

   //--- One-time initialisation called from EA OnInit().
   //--- inputCfg is built by the EA from sinput parameters.
   //--- Returns INIT_SUCCEEDED or INIT_PARAMETERS_INCORRECT.
   int Init(StrategyConfig &inputCfg)
     {
      m_cfg = inputCfg;
      ApplyDefaults(m_cfg);

      string errors[];
      if(!CConfigValidator::Validate(m_cfg, errors))
        {
         CConfigValidator::PrintErrors(errors);
         m_cfgValid = false;
         return INIT_PARAMETERS_INCORRECT;
        }

      m_cfgValid   = true;
      m_lastReload = TimeCurrent();

      Print("[CConfigManager] Init OK — magic=", m_cfg.MagicNumber,
            "  EA=", m_cfg.EAName, "  v", m_cfg.Version);
      return INIT_SUCCEEDED;
     }

   //--- Hot-reload: validate new config then broadcast to all managers.
   //--- On validation failure: logs errors, KEEPS existing config,
   //--- does NOT publish event (atomic — no partial state visible).
   bool Reload(StrategyConfig &newCfg)
     {
      ApplyDefaults(newCfg);

      string errors[];
      if(!CConfigValidator::Validate(newCfg, errors))
        {
         Print("[CConfigManager] Reload rejected — keeping previous config:");
         CConfigValidator::PrintErrors(errors);
         return false;
        }

      m_cfg        = newCfg;
      m_cfgValid   = true;
      m_lastReload = TimeCurrent();

      if(m_bus != NULL)
         m_bus.Publish(EVENT_CONFIG_RELOAD);

      Print("[CConfigManager] Reload OK and broadcast at ",
            TimeToString(m_lastReload, TIME_DATE | TIME_MINUTES));
      return true;
     }

   //--- Read-only config access — always by value, never by pointer
   StrategyConfig  GetConfig()    const { return m_cfg; }
   bool            IsValid()      const { return m_cfgValid; }
   datetime        LastReload()   const { return m_lastReload; }
  };

#endif // __CORE_CONFIG_MANAGER_MQH__
