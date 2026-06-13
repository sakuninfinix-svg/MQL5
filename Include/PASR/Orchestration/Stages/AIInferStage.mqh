//+------------------------------------------------------------------+
//| Orchestration/Stages/AIInferStage.mqh                            |
//| Pipeline stage: AI inference and confidence gating               |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_ORCHESTRATION_AI_INFER_STAGE_MQH__
#define __PASR_ORCHESTRATION_AI_INFER_STAGE_MQH__

#include "PipelineStageBase.mqh"
#include "../../AI/AIOrchestrator.mqh"

class CAIInferStage : public CPipelineStageBase
  {
private:
   CAIOrchestrator *m_ai_orch;

public:
   CAIInferStage() : CPipelineStageBase("AIInfer"), m_ai_orch(NULL) {}
   void SetAIOrchestrator(CAIOrchestrator *orch) { m_ai_orch = orch; }
   void Bind(CAIOrchestrator *orch) { m_ai_orch = orch; }

   // FIX: Use correct CAIOrchestrator.Predict() signature — takes SAIInferenceResult&, no args
   virtual ENUM_STAGE_RESULT Execute(PipelineContext &ctx) override
     {
      if(!m_enabled) return STAGE_SKIP;
      if(m_ai_orch == NULL)
        {
         if(m_debug) Print("[AIInferStage] AIOrchestrator is NULL");
         return STAGE_SKIP;
        }

      // Only run inference when signal is valid
      if(ctx.signal.direction == SIGNAL_NONE)
         return STAGE_SKIP;

      // Run AI inference — CAIOrchestrator.Predict() builds features internally
      SAIInferenceResult ai_result;
      ai_result.Reset();
      if(!m_ai_orch.Predict(ai_result))
        {
         if(m_debug) Print("[AIInferStage] AI Predict failed or unavailable");
         ctx.ai_valid = false;
         return STAGE_SKIP;
        }

      // Store AI result in context
      ctx.ai_valid = ai_result.valid;
      ctx.ai_confidence = ai_result.confidence;
      ctx.ai_score = (float)ai_result.score;
      ctx.drift_score = (float)ai_result.drift_score;
      ctx.ai_veto = ai_result.vetoed;

      // Apply confidence gate using context threshold
      double minConf = ctx.ai_min_confidence;
      if(minConf <= 0.0) minConf = 0.55; // default fallback

      if(ai_result.confidence < minConf)
        {
         if(m_debug)
            PrintFormat("[AIInferStage] AI confidence %.3f below threshold %.3f — veto",
                        ai_result.confidence, minConf);
         return STAGE_SKIP;
        }

      // Apply drift veto
      if(ai_result.vetoed)
        {
         if(m_debug)
            PrintFormat("[AIInferStage] AI vetoed: %s (drift=%.3f)",
                        ai_result.veto_reason, ai_result.drift_score);
         return STAGE_SKIP;
        }

      if(m_debug)
         PrintFormat("[AIInferStage] AI: dir=%d conf=%.3f score=%.3f drift=%.3f model=%s",
                     ai_result.direction,
                     ai_result.confidence,
                     ai_result.score,
                     ai_result.drift_score,
                     ai_result.model_id);

      return STAGE_OK;
     }

   virtual string Name() const override { return "AIInfer"; }
  };

#endif // __PASR_ORCHESTRATION_AI_INFER_STAGE_MQH__
