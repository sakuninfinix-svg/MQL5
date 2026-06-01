//+------------------------------------------------------------------+
//| Central/BackendAdapterInit.mqh - v2.01                           |
//| Compatibility backend manager bootstrap                          |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_CENTRAL_BACKEND_ADAPTER_INIT_MQH__
#define __PASR_CENTRAL_BACKEND_ADAPTER_INIT_MQH__

#include <PASR/Central/BackendAdapter.mqh>
#include <PASR/Central/ModuleFactory.mqh>

int CBackendAdapter::Init(const StrategyConfig &cfg)
  {
   if(m_initialised)
      return INIT_SUCCEEDED;

   m_cfg = cfg;

   m_bus = CModuleFactory::CreateEventBus();
   if(m_bus == NULL)
     {
      Print("[Orchestrator] EventBus allocation failed");
      return INIT_FAILED;
     }

   m_data = CModuleFactory::CreateDataManager();
   if(m_data == NULL)
     {
      Print("[Orchestrator] DataManager allocation failed");
      FreeAll();
      return INIT_FAILED;
     }

   m_data.SetConfig(m_cfg);
   m_lifecycle.Bind(NULL, m_data, m_bus);
   m_lifecycle.SetDebugMode(m_debugMode);
   if(!m_lifecycle.InitCritical(m_data, PASR_MOD_DATA_MANAGER))
     {
      Print("[Orchestrator] DataManager init failed");
      FreeAll();
      return INIT_FAILED;
     }
   if(!BindOwnedManager(m_data, PASR_MOD_DATA_MANAGER))
     {
      FreeAll();
      return INIT_FAILED;
     }

   m_sr = CModuleFactory::CreateSRManager();
   if(!InitManager(m_sr, PASR_MOD_SR_MANAGER))
     {
      FreeAll();
      return INIT_FAILED;
     }

   m_zone = CModuleFactory::CreateZoneManager();
   if(!InitManager(m_zone, PASR_MOD_ZONE_MANAGER))
     {
      FreeAll();
      return INIT_FAILED;
     }

   m_regime = CModuleFactory::CreateRegimeFilter();
   if(!m_lifecycle.InitOptional(m_regime, PASR_MOD_REGIME_FILTER))
     {
      Print("[Orchestrator] RegimeFilter init failed; continuing without regime context");
      if(m_regime != NULL)
        {
         m_regime.Deinit();
         delete m_regime;
         m_regime = NULL;
        }
     }
   else if(!BindOwnedManager(m_regime, PASR_MOD_REGIME_FILTER))
     {
      FreeAll();
      return INIT_FAILED;
     }

   m_pattern = CModuleFactory::CreatePatternManager();
   if(!InitManager(m_pattern, PASR_MOD_PATTERN_MANAGER))
     {
      FreeAll();
      return INIT_FAILED;
     }

   m_signal = CModuleFactory::CreateSignalManager();
   if(!InitManager(m_signal, PASR_MOD_SIGNAL_MANAGER))
     {
      FreeAll();
      return INIT_FAILED;
     }
   m_signal.SetPatternManager(m_pattern);
   m_signal.SetSRManager(m_sr);
   if(m_regime != NULL)
      m_signal.SetRegimeManager(NULL);

   m_srcPattern = new PatternSignalSource(m_pattern);
   if(m_srcPattern != NULL)
      m_signal.RegisterSource(m_srcPattern, 1.0);

   m_srcSR = new SRSignalSource(m_sr, m_data, 0.5);
   if(m_srcSR != NULL)
      m_signal.RegisterSource(m_srcSR, 0.8);

   if(m_regime != NULL)
     {
      m_srcRegime = new CRegimeSignalSource(m_regime, REGIME_MODE_VETO);
      if(m_srcRegime != NULL)
         m_signal.RegisterSource(m_srcRegime, 0.6);
     }

   if(m_cfg.AI.EnableAI)
     {
      m_ai_orch = CModuleFactory::CreateAIOrchestrator();
      if(!m_lifecycle.InitOptional(m_ai_orch, PASR_MOD_AI_ORCHESTRATOR))
        {
         Print("[Orchestrator] AI init failed; rule fallback remains available");
         if(m_ai_orch != NULL)
           {
            m_ai_orch.Deinit();
            delete m_ai_orch;
            m_ai_orch = NULL;
           }
        }
      else
        {
         if(!BindOwnedManager(m_ai_orch, PASR_MOD_AI_ORCHESTRATOR))
           {
            FreeAll();
            return INIT_FAILED;
           }
         double vetoThreshold = m_cfg.AI.MinConfidence;
         double driftVetoThreshold = 0.60;
         double highConfidenceThreshold = MathMax(0.75, m_cfg.AI.MinConfidence + 0.15);
         m_ai_orch.ConfigureParameters(m_cfg.AI.EnableAI,
                                       vetoThreshold,
                                       driftVetoThreshold,
                                       highConfidenceThreshold);
        }
     }

   m_risk = CModuleFactory::CreateRiskManager();
   if(!InitManager(m_risk, PASR_MOD_RISK_MANAGER))
     {
      FreeAll();
      return INIT_FAILED;
     }

   m_exec = CModuleFactory::CreateExecutionManager();
   if(!InitManager(m_exec, PASR_MOD_EXECUTION_MANAGER))
     {
      FreeAll();
      return INIT_FAILED;
     }

   m_exit = CModuleFactory::CreateExitEngine();
   if(m_exit == NULL)
     {
      Print("[Orchestrator] ExitEngine allocation failed");
      FreeAll();
      return INIT_FAILED;
     }
   if(!InitManager(m_exit, PASR_MOD_EXIT_ENGINE))
     {
      FreeAll();
      return INIT_FAILED;
     }

   m_journal = CModuleFactory::CreateJournalManager();
   if(!m_lifecycle.InitOptional(m_journal, PASR_MOD_JOURNAL_MANAGER))
     {
      Print("[Orchestrator] Journal init failed; continuing without journal");
      if(m_journal != NULL)
        {
         m_journal.Deinit();
         delete m_journal;
         m_journal = NULL;
        }
     }
   else if(!BindOwnedManager(m_journal, PASR_MOD_JOURNAL_MANAGER))
     {
      FreeAll();
      return INIT_FAILED;
     }

   if(m_cfg.Display.ShowDashboard)
     {
      m_dash = CModuleFactory::CreateDashboardManager();
      if(!m_lifecycle.InitOptional(m_dash, PASR_MOD_DASHBOARD_MANAGER))
        {
         Print("[Orchestrator] Dashboard init failed; continuing without dashboard");
         if(m_dash != NULL)
           {
            m_dash.Deinit();
            delete m_dash;
            m_dash = NULL;
           }
        }
      else
        {
         if(!BindOwnedManager(m_dash, PASR_MOD_DASHBOARD_MANAGER))
           {
            FreeAll();
            return INIT_FAILED;
           }
         m_dash.SetJournal(m_journal);
        }
     }

   m_lastBarTime  = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   m_new_bar_flag = false;
   m_initialised  = true;

   Print("[Orchestrator] Backend managers bootstrap OK");
   return INIT_SUCCEEDED;
  }

void CBackendAdapter::OnTradeTransaction(
   const MqlTradeTransaction &trans,
   const MqlTradeRequest     &request,
   const MqlTradeResult      &result)
  {
   if(!m_initialised)
      return;

   if(m_data != NULL)
      m_data.OnTrade(trans);
  }

#endif // __PASR_CENTRAL_BACKEND_ADAPTER_INIT_MQH__
