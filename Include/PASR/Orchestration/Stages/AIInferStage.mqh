//+------------------------------------------------------------------+
//| Orchestration/Stages/AIInferStage.mqh - v0.10                   |
//| Runtime AIInfer pipeline stage                                   |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_ORCHESTRATION_AI_INFER_STAGE_MQH__
#define __PASR_ORCHESTRATION_AI_INFER_STAGE_MQH__

#include <PASR/Core/PipelineTypes.mqh>
#include <PASR/AI/AIOrchestrator.mqh>
#include <PASR/Orchestration/PipelineStage.mqh>

class CAIInferStage : public IPipelineStage
  {
private:
   CAIOrchestrator *m_ai_orch;
   bool             m_enabled;

public:
   CAIInferStage() : m_ai_orch(NULL), m_enabled(true) {}

   void Bind(CAIOrchestrator *ai_orch)
     {
      m_ai_orch = ai_orch;
     }

   void SetEnabled(const bool enabled)
     {
      m_enabled = enabled;
     }

   virtual string Name() const override { return "AIInferStage"; }
   virtual bool IsEnabled() const override { return m_enabled; }

   virtual ENUM_STAGE_RESULT Execute(PipelineContext &ctx) override
     {
      if(!m_enabled)
         return STAGE_SKIP;
      if(m_ai_orch == NULL)
         return STAGE_SKIP;
      SAIInferenceResult last = m_ai_orch.GetLastResult();
      AIFeatureValidationResult validation = m_ai_orch.GetLastValidation();
      ctx.ai_result.model_healthy = (m_ai_orch.IsHealthy() && validation.modelHealthy);
      ctx.ai_result.score = last.score;
      ctx.ai_result.drift_index = last.drift_score;
      ctx.ai_result.model_name = (last.model_id != "") ? last.model_id : validation.modelId;
      ctx.ai_result.validation_valid = validation.valid;
      ctx.ai_result.validation_reason = validation.reason;
      ctx.ai_result.invalid_feature_index = validation.invalidIndex;
      if(!validation.valid && validation.reason != "")
         ctx.ai_veto = true;
      return STAGE_OK;
     }
  };

#endif // __PASR_ORCHESTRATION_AI_INFER_STAGE_MQH__
