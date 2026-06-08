//+------------------------------------------------------------------+
//| Orchestration/Stages/AnalysisSRStage.mqh - v0.10                |
//| Runtime AnalysisSR pipeline stage                                |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_ORCHESTRATION_ANALYSIS_SR_STAGE_MQH__
#define __PASR_ORCHESTRATION_ANALYSIS_SR_STAGE_MQH__

#include <PASR/Core/PipelineTypes.mqh>
#include <PASR/Core/Globals.mqh>
#include <PASR/Core/Events.mqh>
#include <PASR/Core/EventBus.mqh>
#include <PASR/Analysis/SRManager.mqh>
#include <PASR/Orchestration/PipelineStage.mqh>

class CAnalysisSRStage : public IPipelineStage
  {
private:
   CAnalysisSRManager *m_sr;
   CEventBus          *m_bus;
   bool                m_enabled;
   bool                m_debug;
   bool                m_profiling;
   CPerfTimer          m_timer;

public:
   CAnalysisSRStage()
      : m_sr(NULL), m_bus(NULL), m_enabled(true), m_debug(false), m_profiling(true)
     {}

   void Bind(CAnalysisSRManager *sr, CEventBus *bus)
     {
      m_sr = sr;
      m_bus = bus;
     }

   void SetEnabled(const bool enabled) { m_enabled = enabled; }
   void SetDebugMode(const bool enabled) { m_debug = enabled; }
   void EnableProfiling(const bool enabled) { m_profiling = enabled; }

   virtual string Name() const override { return "AnalysisSRStage"; }
   virtual bool IsEnabled() const override { return m_enabled; }

   virtual ENUM_STAGE_RESULT Execute(PipelineContext &ctx) override
     {
      if(!m_enabled)
         return STAGE_SKIP;
      if(m_sr == NULL)
        {
         if(m_debug) Print("[Pipeline] AnalysisSR SKIP: manager is NULL");
         return STAGE_SKIP;
        }
      if(!ctx.new_bar)
         return STAGE_SKIP;

      m_timer.Start();
      PASREvent ev;
      ev.id = EVENT_ID_NEW_BAR;
      ev.priority = 10;
      if(m_bus != NULL) m_bus.DispatchImmediate(ev);
      if(m_profiling) m_timer.Log("Stage2_AnalysisSR");
      return STAGE_OK;
     }
  };

#endif // __PASR_ORCHESTRATION_ANALYSIS_SR_STAGE_MQH__
