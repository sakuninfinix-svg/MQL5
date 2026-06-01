//+------------------------------------------------------------------+
//| Orchestration/Stages/AnalysisZoneStage.mqh - v0.10              |
//| Runtime AnalysisZone pipeline stage                              |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_ORCHESTRATION_ANALYSIS_ZONE_STAGE_MQH__
#define __PASR_ORCHESTRATION_ANALYSIS_ZONE_STAGE_MQH__

#include <PASR/Core/PipelineTypes.mqh>
#include <PASR/Core/Globals.mqh>
#include <PASR/Analysis/ZoneManager.mqh>
#include <PASR/Orchestration/PipelineStage.mqh>

class CAnalysisZoneStage : public IPipelineStage
  {
private:
   CAnalysisZoneManager *m_zone;
   bool                  m_enabled;
   bool                  m_debug;
   bool                  m_profiling;
   CPerfTimer            m_timer;

public:
   CAnalysisZoneStage()
      : m_zone(NULL), m_enabled(true), m_debug(false), m_profiling(true)
     {}

   void Bind(CAnalysisZoneManager *zone)
     {
      m_zone = zone;
     }

   void SetEnabled(const bool enabled) { m_enabled = enabled; }
   void SetDebugMode(const bool enabled) { m_debug = enabled; }
   void EnableProfiling(const bool enabled) { m_profiling = enabled; }

   virtual string Name() const override { return "AnalysisZoneStage"; }
   virtual bool IsEnabled() const override { return m_enabled; }

   virtual ENUM_STAGE_RESULT Execute(PipelineContext &ctx) override
     {
      if(!m_enabled)
         return STAGE_SKIP;
      if(m_zone == NULL)
        {
         if(m_debug) Print("[Pipeline] AnalysisZone SKIP: manager is NULL");
         return STAGE_SKIP;
        }

      m_timer.Start();
      m_zone.OnPriceUpdate();
      if(ctx.new_bar) m_zone.OnNewBar();
      if(m_profiling) m_timer.Log("Stage3_AnalysisZone");
      return STAGE_OK;
     }
  };

#endif // __PASR_ORCHESTRATION_ANALYSIS_ZONE_STAGE_MQH__
