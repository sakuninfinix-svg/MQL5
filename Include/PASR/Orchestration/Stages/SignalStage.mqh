//+------------------------------------------------------------------+
//| Orchestration/Stages/SignalStage.mqh - v0.20                    |
//| Runtime SignalGen pipeline stage                                 |
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

class CSignalStage : public IPipelineStage
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

   ENUM_STAGE_RESULT RuleFallbackSignal(PipelineContext &ctx)
     {
      if(m_signal == NULL)
        {
         if(m_debug) Print("[Pipeline] RuleFallbackSignal SKIP: manager is NULL");
         if(m_profiling) m_timer.Log("Stage6_SignalGen");
         return STAGE_SKIP;
        }
      ctx.signal = m_signal.AggregateSignals();
      ctx.signal_strength = ctx.signal.confidence;
      if(m_debug)
         PrintFormat("[Pipeline] RULE_FALLBACK Signal: dir=%d conf=%.3f src=%s", (int)ctx.signal.direction, ctx.signal.confidence, ctx.signal.primarySource);
      if(m_profiling) m_timer.Log("Stage6_RuleFallbackSignal");
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

   virtual string Name() const override { return "SignalStage"; }
   virtual bool IsEnabled() const override { return m_enabled; }

   virtual ENUM_STAGE_RESULT Execute(PipelineContext &ctx) override
     {
      if(!m_enabled)
         return STAGE_SKIP;

      m_timer.Start();
      ctx.signal.Clear();
      InjectAIContext(ctx);

      bool aiAvailable = (m_ai_orch != NULL && m_ai_orch.IsReady() && m_ai_orch.IsHealthy());
      if(!aiAvailable)
        {
         ctx.ai_result.model_healthy = false;
         ctx.exit_message = "AI unavailable; using rule fallback";
         return RuleFallbackSignal(ctx);
        }

      if(m_ai_orch.PredictSignal(ctx.signal))
        {
         SAIInferenceResult ai = m_ai_orch.GetLastResult();
         ctx.ai_score = (float)ai.score;
         ctx.ai_veto = ai.vetoed;
         ctx.drift_score = (float)ai.drift_score;
         ctx.ai_result.score = ctx.ai_score;
         ctx.ai_result.drift_index = ctx.drift_score;
         ctx.ai_result.model_healthy = true;
         ctx.signal_strength = ctx.signal.confidence;
         if(m_debug)
            PrintFormat("[Pipeline] AI_PRIMARY Signal: dir=%d conf=%.3f src=%s", (int)ctx.signal.direction, ctx.signal.confidence, ctx.signal.primarySource);
         if(m_profiling) m_timer.Log("Stage6_AIPrimarySignal");
         return STAGE_OK;
        }

      SAIInferenceResult last = m_ai_orch.GetLastResult();
      ctx.ai_score = (float)last.score;
      ctx.ai_veto = last.vetoed;
      ctx.drift_score = (float)last.drift_score;
      ctx.ai_result.score = ctx.ai_score;
      ctx.ai_result.drift_index = ctx.drift_score;
      ctx.ai_result.model_healthy = true;
      ctx.exit_message = last.vetoed ? last.veto_reason : "AI primary chose no trade";
      if(m_debug)
         PrintFormat("[Pipeline] AI_PRIMARY no trade: %s", ctx.exit_message);
      if(m_profiling) m_timer.Log("Stage6_AIPrimarySignal");
      return STAGE_OK;
     }
  };

#endif // __PASR_ORCHESTRATION_SIGNAL_STAGE_MQH__
