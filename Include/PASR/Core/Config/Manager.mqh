//+------------------------------------------------------------------+
//|                                      Core/Config/Manager.mqh    |
//|                                      Copyright 2026, Agsicentre |
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_CONFIG_MANAGER_MQH__
#define __CORE_CONFIG_MANAGER_MQH__

#include "Types.mqh"
#include "Validator.mqh"
#include "../EventBus.mqh"
#include "../Events.mqh"

class CConfigManager
  {
private:
   StrategyConfig  m_cfg;
   bool            m_cfgValid;
   CEventBus      *m_bus;
   datetime        m_lastReload;

   void ApplyDefaults(StrategyConfig &cfg)
     {
      if(StringLen(cfg.EAName) == 0)  cfg.EAName  = "PASR";
      if(StringLen(cfg.Version) == 0) cfg.Version = "2.0.0";
      if(cfg.MagicNumber <= 0)        cfg.MagicNumber = 123456;
     }

public:
   CConfigManager()
      : m_cfgValid(false), m_bus(NULL), m_lastReload(0) {}

   void SetEventBus(CEventBus *bus) { m_bus = bus; }

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
            " EA=", m_cfg.EAName, " v", m_cfg.Version);
      return INIT_SUCCEEDED;
     }

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
        {
         PASREvent ev;
         ev.id = EVENT_ID_CONFIG_RELOAD;
         ev.priority = 20;
         ev.timestamp = TimeCurrent();
         ev.comment = "ConfigReload";
         m_bus.DispatchImmediate(ev);
        }

      Print("[CConfigManager] Reload OK and broadcast at ",
            TimeToString(m_lastReload, TIME_DATE | TIME_MINUTES));
      return true;
     }

   StrategyConfig  GetConfig()    const { return m_cfg; }
   bool            IsValid()      const { return m_cfgValid; }
   datetime        LastReload()   const { return m_lastReload; }
  };

#endif // __CORE_CONFIG_MANAGER_MQH__
