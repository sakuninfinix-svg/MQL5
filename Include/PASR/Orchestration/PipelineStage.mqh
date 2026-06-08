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

   virtual bool IsEnabled() const
     {
      return true;
     }

   virtual void SetEnabled(const bool enabled)
     {
      // Optional for concrete stages that expose runtime toggles.
     }

   virtual void SetDebugMode(const bool enabled)
     {
      // Optional for concrete stages that emit diagnostics.
     }

   virtual void EnableProfiling(const bool enabled)
     {
      // Optional for concrete stages that measure elapsed time.
     }

   virtual bool IsReady() const
     {
      return true;
     }

   virtual string LastError() const
     {
      return "";
     }

   virtual ulong LastElapsedUs() const
     {
      return 0;
     }

   virtual void Reset()
     {
      // Optional for stages that keep transient state.
     }
  };

#endif // __PASR_ORCHESTRATION_PIPELINE_STAGE_MQH__