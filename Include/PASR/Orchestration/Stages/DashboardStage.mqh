//+------------------------------------------------------------------+
//| Orchestration/Stages/DashboardStage.mqh - v0.10                 |
//| Runtime Dashboard pipeline stage                                 |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_ORCHESTRATION_DASHBOARD_STAGE_MQH__
#define __PASR_ORCHESTRATION_DASHBOARD_STAGE_MQH__

#include <PASR/Core/PipelineTypes.mqh>
#include <PASR/Core/Globals.mqh>
#include <PASR/UI/DashboardManager.mqh>
#include <PASR/Orchestration/PipelineStage.mqh>

class CDashboardStage : public IPipelineStage
  {
private:
   CDashboardManager *m_dashboard;
   bool               m_enabled;
   bool               m_debug;
   bool               m_profiling;
   string             m_observability;
   CPerfTimer         m_timer;

public:
   CDashboardStage()
      : m_dashboard(NULL), m_enabled(true), m_debug(false), m_profiling(true),
        m_observability("")
     {}

   void Bind(CDashboardManager *dashboard)
     {
      m_dashboard = dashboard;
     }

   void SetEnabled(const bool enabled)
     {
      m_enabled = enabled;
     }

   void SetDebugMode(const bool enabled)
     {
      m_debug = enabled;
     }

   void EnableProfiling(const bool enabled)
     {
      m_profiling = enabled;
     }

   void SetObservabilityText(const string text)
     {
      m_observability = text;
     }

   virtual string Name() const override { return "DashboardStage"; }
   virtual bool IsEnabled() const override { return m_enabled; }

   virtual ENUM_STAGE_RESULT Execute(PipelineContext &ctx) override
     {
      if(!m_enabled)
         return STAGE_SKIP;
      if(m_dashboard == NULL)
        {
         if(m_debug) Print("[Pipeline] Dashboard SKIP: manager is NULL");
         return STAGE_SKIP;
        }

      m_timer.Start();
      m_dashboard.SetPipelineSignal(ctx.signal);
      m_dashboard.SetAIScore(ctx.ai_score);
      m_dashboard.SetRegime(ctx.regime);
      m_dashboard.SetSessionDD(ctx.session_dd);
      m_dashboard.SetObservabilityText(m_observability);
      m_dashboard.OnTimer();
      if(m_profiling) m_timer.Log("Stage13_Dashboard");
      return STAGE_OK;
     }
  };

#endif // __PASR_ORCHESTRATION_DASHBOARD_STAGE_MQH__
