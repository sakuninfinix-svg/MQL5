//+------------------------------------------------------------------+
//| Orchestration/Stages/AIInferStage.mqh                            |
//| Pipeline stage: AI inference and confidence gating               |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_ORCHESTRATION_AI_INFER_STAGE_MQH__
#define __PASR_ORCHESTRATION_AI_INFER_STAGE_MQH__

#include "PipelineStageBase.mqh"
#include "../../AI/AIOrchestrator.mqh"
#include "../../Analysis/SRManager.mqh"
#include "../../Analysis/SRZoneStore.mqh"
#include "../../Analysis/ZoneManager.mqh"

class CAIInferStage : public CPipelineStageBase
  {
private:
    CAIOrchestrator       *m_ai_orch;
    CAnalysisSRManager    *m_sr;
    CAnalysisZoneManager  *m_zone;

public:
    CAIInferStage() : CPipelineStageBase("AIInfer"), m_ai_orch(NULL), m_sr(NULL), m_zone(NULL) {}
    void SetAIOrchestrator(CAIOrchestrator *orch) { m_ai_orch = orch; }
    void Bind(CAIOrchestrator *orch, CAnalysisSRManager *sr, CAnalysisZoneManager *zone)
      {
       m_ai_orch = orch;
       m_sr = sr;
       m_zone = zone;
      }

    double GetSRDistance() const
      {
       if(m_sr == NULL) return 0.5;
       double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
       double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
       double price = (bid + ask) / 2.0;
       
       SRZoneExtended sup, res;
       bool hasSup = m_sr.GetNearestSupport(price, sup);
       bool hasRes = m_sr.GetNearestResistance(price, res);
       
       double dist = 0.5;
       if(hasSup && hasRes)
         {
          double range = res.price - sup.price;
          if(range > 0) dist = (price - sup.price) / range;
         }
       else if(hasSup)
         dist = 0.25;
       else if(hasRes)
         dist = 0.75;
       
       return MathMax(0.0, MathMin(1.0, dist));
      }

    double GetZoneStrength() const
      {
       if(m_zone == NULL) return 0.5;
       // ZoneManager doesn't expose strength directly, use 0.5 as default
       return 0.5;
      }

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

        // Calculate SR distance and zone strength
        double sr_dist = GetSRDistance();
        double zone_str = GetZoneStrength();

        // Inject regime context from pipeline (HMM/RegimeFilter) into AI for gating
        // RegimeStage runs before AIInferStage, so ctx.regime and ctx.regime_confidence are available
        if(m_ai_orch.GetFeatureBuilder() != NULL)
          {
           m_ai_orch.InjectContext(
               sr_dist,                 // SR distance (normalized)
               zone_str,                // Zone strength (normalized)
               ctx.pattern_score,       // Pattern score
               ctx.regime,              // Regime from RegimeStage (HMM preferred)
               ctx.regime_confidence    // Regime confidence from HMM
           );
          }

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
       // Store model info for observability
       ctx.ai_result.model_name = ai_result.model_id;
       ctx.ai_result.model_healthy = ai_result.valid;
       ctx.ai_result.validation_valid = ai_result.valid && !ai_result.vetoed;
       ctx.ai_result.validation_reason = ai_result.vetoed ? ai_result.veto_reason : "OK";

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
