//+------------------------------------------------------------------+
//| Orchestration/PipelineStage.mqh — v0.10                           |
//| Base interface for future split pipeline stages                    |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_ORCHESTRATION_PIPELINE_STAGE_MQH__
#define __PASR_ORCHESTRATION_PIPELINE_STAGE_MQH__

class IPipelineStage
  {
public:
   virtual string Name() const = 0;
   virtual ENUM_STAGE_RESULT Execute(PipelineContext &ctx) = 0;
   virtual bool IsEnabled() const { return true; }
  };

#endif // __PASR_ORCHESTRATION_PIPELINE_STAGE_MQH__
