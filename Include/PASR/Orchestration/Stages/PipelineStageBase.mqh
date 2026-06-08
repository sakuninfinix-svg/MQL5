//+------------------------------------------------------------------+
//| Orchestration/Stages/PipelineStageBase.mqh — v0.10                |
//| Reusable base for Phase 5 split pipeline stage extraction          |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_ORCHESTRATION_STAGES_PIPELINE_STAGE_BASE_MQH__
#define __PASR_ORCHESTRATION_STAGES_PIPELINE_STAGE_BASE_MQH__

#include <PASR/Orchestration/PipelineStage.mqh>

class CPipelineStageBase : public IPipelineStage
  {
protected:
   string m_name;
   bool   m_enabled;
   bool   m_debug;
   bool   m_profiling_enabled;

public:
   CPipelineStageBase(const string name = "PipelineStage")
      : m_name(name), m_enabled(true), m_debug(false), m_profiling_enabled(true)
     {}

   virtual string Name() const
     {
      return m_name;
     }

   virtual bool IsEnabled() const
     {
      return m_enabled;
     }

   virtual void SetEnabled(const bool enabled)
     {
      m_enabled = enabled;
     }

   virtual void SetDebugMode(const bool enabled)
     {
      m_debug = enabled;
     }

   virtual void SetProfilingEnabled(const bool enabled)
     {
      m_profiling_enabled = enabled;
     }

   ENUM_STAGE_RESULT Skip(const string reason = "") const
     {
      if(m_debug && reason != "")
         PrintFormat("[PipelineStage:%s] SKIP: %s", m_name, reason);
      return STAGE_SKIP;
     }

   ENUM_STAGE_RESULT Abort(PipelineContext &ctx, const string reason) const
     {
      ctx.exit_reason = STAGE_ABORT;
      ctx.exit_message = reason;
      if(m_debug)
         PrintFormat("[PipelineStage:%s] ABORT: %s", m_name, reason);
      return STAGE_ABORT;
     }
  };

#endif // __PASR_ORCHESTRATION_STAGES_PIPELINE_STAGE_BASE_MQH__