//+------------------------------------------------------------------+
//| Orchestration/Stages/SignalStage.mqh - v0.30                    |
//| Runtime SignalGen pipeline stage — hierarchical confluence mode  |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_ORCHESTRATION_SIGNAL_STAGE_MQH__
#define __PASR_ORCHESTRATION_SIGNAL_STAGE_MQH__

#include <PASR/Core/PipelineTypes.mqh>
#include <PASR/Core/Globals.mqh>
#include <PASR/Analysis/SRManager.mqh>
#include <PASR/Analysis/Pattern/PatternManager.mqh>
#include <PASR/AI/AIOrchestrator.mqh>
#include <PASR/Signal/SignalManager.mqh>
#include <PASR/Orchestration/PipelineStage.mqh>

class CSignalStage : public CPipelineStageBase
  {
private:
   CSignalManager     *m_signal;
   CAIOrchestrator    *m_ai_orch;
   CAnalysisSRManager *m_sr;
   CPatternManager    *m_pattern;
   bool                m_enabled;
   bool                m_debug;
   bool                m_profiling;
   CPerfTimer          m_timer;

   void InjectAIContext(PipelineContext &ctx)
     {
      if(m_ai_orch == NULL) return;
      double srDist = 0.5;
      double zoneStrength = 0.5;
      double patternScore = 0.5;

      if(m_sr != NULL && ctx.bid > 0.0)
        {
         SRZoneExtended z;
         if(m_sr.IsNearValidZone(ctx.bid, 0.5, z))
           {
            double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            double atrPrice = (ctx.atr_points > 0.0) ? ctx.atr_points : 0.0;
            double dist = MathAbs(ctx.bid - z.price);
            srDist = (atrPrice > 0.0) ? MathMax(0.0, MathMin(1.0, 1.0 - dist / MathMax(atrPrice, point))) : 0.5;
            zoneStrength = MathMax(0.0, MathMin(1.0, z.strength / 100.0));
           }
        }

      if(m_pattern != NULL)
        {
         SPatternResult pr = m_pattern.GetLastResult();
         if(pr.found)
            patternScore = MathMax(0.0, MathMin(1.0, pr.confluenceScore));

         SPatternFeatureSnapshot pf = m_pattern.GetLastFeatureSnapshot();
         CAIFeatureBuilder *fb = m_ai_orch.GetFeatureBuilder();
         if(fb != NULL)
            fb.InjectPatternFeatures(pf.buyProb, pf.sellProb, pf.conflict, pf.dominanceGap,
                                     pf.rejectionQuality, pf.trapQuality, pf.reclaimQuality,
                                     pf.followThrough);
        }

      m_ai_orch.InjectContext(srDist, zoneStrength, patternScore, ctx.regime);
     }

   void PublishAiResult(PipelineContext &ctx)
     {
      if(m_ai_orch == NULL)
        {
         ctx.ai_result.model_healthy = false;
         ctx.ai_result.validation_valid = false;
         if(ctx.ai_result.validation_reason == "")
            ctx.ai_result.validation_reason = "AI orchestrator unavailable";
         return;
        }

      SAIInferenceResult ai = m_ai_orch.GetLastResult();
      AIFeatureValidationResult validation = m_ai_orch.GetLastValidation();
      ctx.ai_score = (float)ai.score;
      ctx.ai_veto = ai.vetoed;
      ctx.drift_score = (float)ai.drift_score;
      ctx.ai_result.score = ctx.ai_score;
      ctx.ai_result.drift_index = ctx.drift_score;
      ctx.ai_result.model_healthy = (m_ai_orch.IsHealthy() && validation.modelHealthy);
      ctx.ai_result.model_name = (ai.model_id != "") ? ai.model_id : validation.modelId;
      ctx.ai_result.validation_valid = validation.valid;
      ctx.ai_result.validation_reason = validation.reason;
      ctx.ai_result.invalid_feature_index = validation.invalidIndex;
     }

   ENUM_STAGE_RESULT ResolveConfluenceSignal(PipelineContext &ctx)
     {
      if(m_signal == NULL)
        {
         if(m_debug) Print("[Pipeline] ConfluenceSignal SKIP: manager is NULL");
         if(m_profiling) m_timer.Log("Stage6_SignalGen");
         return STAGE_SKIP;
        }

      ctx.signal = m_signal.AggregateSignals();
      ctx.signal_strength = ctx.signal.confidence;
      PublishAiResult(ctx);

      SignalLayerSnapshot snap = m_signal.GetSnapshot();
      if(ctx.signal.direction == SIGNAL_NONE)
         ctx.exit_message = "Signal: " + snap.lastReason;

      if(m_debug)
        {
         if(ctx.signal.direction == SIGNAL_NONE)
            PrintFormat("[Pipeline] CONFLUENCE no trade: %s (src=%d conf=%d veto=%s)",
                        snap.lastReason, snap.sourceCount, snap.lastConfluence,
                        snap.lastVetoed ? "true" : "false");
         else
            PrintFormat("[Pipeline] CONFLUENCE Signal: dir=%d conf=%.3f src=%s confluence=%d",
                        (int)ctx.signal.direction, ctx.signal.confidence,
                        ctx.signal.primarySource, snap.lastConfluence);
        }

      if(m_profiling) m_timer.Log("Stage6_ConfluenceSignal");
      return STAGE_OK;
     }

public:
   CSignalStage()
      : m_signal(NULL), m_ai_orch(NULL), m_sr(NULL), m_pattern(NULL),
        m_enabled(true), m_debug(false), m_profiling(true)
     {}

   void Bind(CSignalManager *signal,
             CAIOrchestrator *ai_orch,
             CAnalysisSRManager *sr,
             CPatternManager *pattern)
     {
      m_signal = signal;
      m_ai_orch = ai_orch;
      m_sr = sr;
      m_pattern = pattern;
     }

   void Bind(IManager *manager)
     {
      m_manager = manager;
     }

   void SetDebugMode(const bool enabled)
     {
      m_debug = enabled;
     }

   void EnableProfiling(const bool enabled)
     {
      m_profiling = enabled;
     }

   virtual string Name() const override { return "SignalStage"; }
   virtual bool IsEnabled() const override { return m_enabled; }

   virtual ENUM_STAGE_RESULT Execute(PipelineContext &ctx) override
     {
      if(!m_enabled)
         return STAGE_SKIP;

      m_timer.Start();
      ctx.signal.Clear();
      InjectAIContext(ctx);
      return ResolveConfluenceSignal(ctx);
     }
  };

#endif // __PASR_ORCHESTRATION_SIGNAL_STAGE_MQH__