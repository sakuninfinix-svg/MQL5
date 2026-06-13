//+------------------------------------------------------------------+
//| Orchestration/Stages/AdaptiveParamsStage.mqh - v0.10            |
//| Runtime AdaptiveParams pipeline stage                            |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_ORCHESTRATION_ADAPTIVE_PARAMS_STAGE_MQH__
#define __PASR_ORCHESTRATION_ADAPTIVE_PARAMS_STAGE_MQH__

#include <PASR/Core/PipelineTypes.mqh>
#include <PASR/Core/Globals.mqh>
#include <PASR/Analysis/AdaptiveParameterManager.mqh>
#include <PASR/Orchestration/PipelineStage.mqh>

class CAdaptiveParamsStage : public IPipelineStage
  {
private:
   CAdaptiveParameterManager *m_adaptive;
   bool                       m_enabled;
   bool                       m_debug;
   bool                       m_profiling;
   CPerfTimer                 m_timer;

public:
   CAdaptiveParamsStage()
      : m_adaptive(NULL), m_enabled(true), m_debug(false), m_profiling(true)
     {}

   void Bind(CAdaptiveParameterManager *adaptive)
     {
      m_adaptive = adaptive;
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

   virtual string Name() const override { return "AdaptiveParamsStage"; }
   virtual bool IsEnabled() const override { return m_enabled; }

   virtual ENUM_STAGE_RESULT Execute(PipelineContext &ctx) override
     {
      if(!m_enabled)
         return STAGE_SKIP;
      if(m_adaptive == NULL)
        {
         if(m_debug) Print("[Pipeline] AdaptiveParams SKIP: manager is NULL");
         return STAGE_SKIP;
        }
      if(!ctx.new_bar)
        {
         // FIX: Do NOT invalidate the plan on intra-bar ticks.
         // The plan was established on the new-bar tick; intra-bar ticks should
         // still allow downstream stages (Execution, Position) to see it.
         return STAGE_SKIP;
        }

      m_timer.Start();
      m_adaptive.OnNewBar();
      if(m_profiling) m_timer.Log("Stage9_AdaptiveParams");
      return STAGE_OK;
     }
  };

#endif // __PASR_ORCHESTRATION_ADAPTIVE_PARAMS_STAGE_MQH__
