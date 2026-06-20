//+------------------------------------------------------------------+
//| Orchestration/Stages/PatternStage.mqh - v0.10                   |
//| Runtime PatternRec pipeline stage                                |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_ORCHESTRATION_PATTERN_STAGE_MQH__
#define __PASR_ORCHESTRATION_PATTERN_STAGE_MQH__

#include <PASR/Core/PipelineTypes.mqh>
#include <PASR/Core/Globals.mqh>
#include <PASR/Analysis/Pattern/PatternManager.mqh>
#include <PASR/AI/AIOrchestrator.mqh>
#include <PASR/Orchestration/PipelineStage.mqh>

class CPatternStage : public IPipelineStage
  {
private:
   CPatternManager  *m_pattern;
   CAIOrchestrator  *m_ai_orch;
   bool             m_enabled;
   bool             m_debug;
   bool             m_profiling;
   CPerfTimer       m_timer;

public:
   CPatternStage()
      : m_pattern(NULL), m_ai_orch(NULL), m_enabled(true), m_debug(false), m_profiling(true)
     {}

   void Bind(CPatternManager *pattern, CAIOrchestrator *ai_orch = NULL)
     {
      m_pattern = pattern;
      m_ai_orch = ai_orch;
     }

   void SetEnabled(const bool enabled) { m_enabled = enabled; }
   void SetDebugMode(const bool enabled) { m_debug = enabled; }
   void EnableProfiling(const bool enabled) { m_profiling = enabled; }

    virtual string Name() const override { return "PatternStage"; }
    virtual bool IsEnabled() const override { return m_enabled; }

    virtual ENUM_STAGE_RESULT Execute(PipelineContext &ctx) override
      {
       if(!m_enabled)
          return STAGE_SKIP;
       if(m_pattern == NULL)
         {
          if(m_debug) Print("[Pipeline] PatternRec SKIP: manager is NULL");
          return STAGE_SKIP;
         }
       if(!ctx.new_bar)
          return STAGE_SKIP;

       m_timer.Start();
       MqlRates rates[];
       ArraySetAsSeries(rates, true);
       int copied = CopyRates(_Symbol, _Period, 0, 8, rates);
       if(copied < 4)
         {
          if(m_debug) Print("[Pipeline] PatternRec SKIP: insufficient rates");
          if(m_profiling) m_timer.Log("Stage4_PatternRec");
          return STAGE_SKIP;
         }

       double atrPoints = ctx.atr_points;
       if(atrPoints <= 0.0)
          atrPoints = 1.0;

       EMarketRegime regime = (ctx.regime == REGIME_UNKNOWN) ? REGIME_RANGE : ctx.regime;
       SPatternResult result;
       bool found = m_pattern.Detect(rates, 1, atrPoints, regime, result);

       // FIX: Store pattern result in context for downstream stages
       ctx.pattern_detected = found;
       ctx.pattern_direction = (ENUM_SIGNAL_DIR)result.direction;
       ctx.pattern_score = result.confluenceScore;

       // Get detailed pattern features for AI feature builder
       SPatternFeatureSnapshot features = m_pattern.GetLastFeatureSnapshot();
       ctx.pattern_buyProb = features.buyProb;
       ctx.pattern_sellProb = features.sellProb;
       ctx.pattern_conflict = features.conflict;
       ctx.pattern_dominanceGap = features.dominanceGap;
       ctx.pattern_rejectionQuality = features.rejectionQuality;
       ctx.pattern_trapQuality = features.trapQuality;
       ctx.pattern_reclaimQuality = features.reclaimQuality;
       ctx.pattern_followThrough = features.followThrough;

       // Inject pattern features into AI orchestrator for feature building
       if(m_ai_orch != NULL && m_ai_orch.GetFeatureBuilder() != NULL)
         {
          m_ai_orch.GetFeatureBuilder().InjectPatternFeatures(
              features.buyProb,
              features.sellProb,
              features.conflict,
              features.dominanceGap,
              features.rejectionQuality,
              features.trapQuality,
              features.reclaimQuality,
              features.followThrough
          );
          // Also inject SR/zone and regime context
          m_ai_orch.InjectContext(0.5, 0.5, result.confluenceScore, regime);
         }

       if(m_debug)
         {
          if(found)
             PrintFormat("[Pipeline] PatternRec OK: type=%d dir=%d score=%.3f reason=%s",
                         (int)result.type, result.direction, result.confluenceScore, result.reason);
          else
             Print("[Pipeline] PatternRec SKIP: ", result.reason);
         }

       if(m_profiling) m_timer.Log("Stage4_PatternRec");
       return STAGE_OK;
      }
  };

#endif // __PASR_ORCHESTRATION_PATTERN_STAGE_MQH__
