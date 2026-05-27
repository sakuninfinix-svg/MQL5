//+------------------------------------------------------------------+
//| Core/OrchestratorInit.mqh — v1.04                                |
//| Out-of-class COrchestrator method implementations                 |
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_ORCHESTRATOR_INIT_MQH__
#define __CORE_ORCHESTRATOR_INIT_MQH__

int COrchestrator::Init(const StrategyConfig &cfg)
  {
   if(m_initialised)
      return INIT_SUCCEEDED;

   m_cfg = cfg;

   m_bus = new CEventBus();
   if(m_bus == NULL)
     {
      Print("[Orchestrator] EventBus allocation failed");
      return INIT_FAILED;
     }

   m_data = new CDataManager();
   if(m_data == NULL)
     {
      Print("[Orchestrator] DataManager allocation failed");
      FreeAll();
      return INIT_FAILED;
     }

   m_data.SetConfig(m_cfg);
   if(!m_data.Init(NULL, m_bus))
     {
      Print("[Orchestrator] DataManager init failed");
      FreeAll();
      return INIT_FAILED;
     }
   RegisterManager(m_data);

   m_sr = new CAnalysisSRManager();
   if(!InitManager(m_sr, "SRManager"))
     {
      FreeAll();
      return INIT_FAILED;
     }

   m_zone = new CAnalysisZoneManager();
   if(!InitManager(m_zone, "ZoneManager"))
     {
      FreeAll();
      return INIT_FAILED;
     }

   m_regime = new CRegimeFilter();
   if(!InitManager(m_regime, "RegimeFilter"))
     {
      Print("[Orchestrator] RegimeFilter init failed; continuing without regime source");
      if(m_regime != NULL)
        {
         m_regime.Deinit();
         delete m_regime;
         m_regime = NULL;
        }
     }

   // Core analysis/signal/trade managers. These are required for the pipeline
   // to do useful work instead of silently skipping most stages.
   m_pattern = new CPatternManager();
   if(!InitManager(m_pattern, "PatternManager"))
     {
      FreeAll();
      return INIT_FAILED;
     }

   m_signal = new CSignalManager();
   if(!InitManager(m_signal, "SignalManager"))
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
      m_ai_orch = new CAIOrchestrator();
      if(!InitManager(m_ai_orch, "AIOrchestrator"))
        {
         Print("[Orchestrator] AI init failed; continuing without AI source");
         if(m_ai_orch != NULL)
           {
            m_ai_orch.Deinit();
            delete m_ai_orch;
            m_ai_orch = NULL;
           }
        }
      else
        {
         m_srcAI = new AISignalSource(m_ai_orch);
         if(m_srcAI != NULL)
            m_signal.RegisterSource(m_srcAI, 0.7);
        }
     }

   m_risk = new CRiskManager();
   if(!InitManager(m_risk, "RiskManager"))
     {
      FreeAll();
      return INIT_FAILED;
     }

   m_exec = new CExecutionManager();
   if(!InitManager(m_exec, "ExecutionManager"))
     {
      FreeAll();
      return INIT_FAILED;
     }

   m_exit = new CExitEngine();
   if(m_exit == NULL)
     {
      Print("[Orchestrator] ExitEngine allocation failed");
      FreeAll();
      return INIT_FAILED;
     }
   if(!InitManager(m_exit, "ExitEngine"))
     {
      FreeAll();
      return INIT_FAILED;
     }

   m_pipeline = new CPipelineEngine();
   if(m_pipeline == NULL)
     {
      Print("[Orchestrator] PipelineEngine allocation failed");
      FreeAll();
      return INIT_FAILED;
     }

   m_pipeline.SetDebugMode(m_debugMode);
   m_pipeline.EnableProfiling(m_profiling_enabled);
   m_pipeline.InjectManagers(m_data, m_sr, m_zone, m_pattern, m_signal,
                             m_ai_orch, m_regime, m_risk, m_exec,
                             m_recovery, m_dash, m_journal, m_bus,
                             m_sanity, m_telemetry, m_adaptive,
                             m_regime_det, m_optimizer, m_async_orders,
                             m_health, m_snapshot, m_exit);

   m_lastBarTime  = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   m_new_bar_flag = false;
   m_initialised  = true;

   Print("[Orchestrator] core pipeline bootstrap OK");
   return INIT_SUCCEEDED;
  }

void COrchestrator::OnTradeTransaction(
   const MqlTradeTransaction &trans,
   const MqlTradeRequest     &request,
   const MqlTradeResult      &result)
  {
   if(!m_initialised)
      return;

   if(m_data != NULL)
      m_data.OnTrade(trans);
  }

#endif // __CORE_ORCHESTRATOR_INIT_MQH__