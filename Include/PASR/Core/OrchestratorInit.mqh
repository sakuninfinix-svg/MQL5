//+------------------------------------------------------------------+
//| Core/OrchestratorInit.mqh — v1.00                                |
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
                             m_health, m_snapshot);

   m_lastBarTime  = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   m_new_bar_flag = false;
   m_initialised  = true;

   Print("[Orchestrator] minimal bootstrap OK");
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
