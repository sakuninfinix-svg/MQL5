//+------------------------------------------------------------------+
//| Orchestration/PipelineStage.mqh — v0.20                           |
//| Base interface for split pipeline stages                           |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_ORCHESTRATION_PIPELINE_STAGE_MQH__
#define __PASR_ORCHESTRATION_PIPELINE_STAGE_MQH__

class IPipelineStage
  {
public:
   virtual string Name() const = 0;
   virtual ENUM_STAGE_RESULT Execute(PipelineContext &ctx) = 0;

   // Phase 5 compatibility hooks. Default implementations keep existing
   // stage contracts source-compatible while allowing extracted stages to
   // receive runtime toggles from CPipelineEngine later.
   virtual bool IsEnabled() const { return true; }
   virtual void SetEnabled(const bool enabled) {}
   virtual void SetDebugMode(const bool enabled) {}
   virtual void SetProfilingEnabled(const bool enabled) {}
  };

#endif // __PASR_ORCHESTRATION_PIPELINE_STAGE_MQH__