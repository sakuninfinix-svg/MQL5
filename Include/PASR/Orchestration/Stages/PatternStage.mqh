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
#include <PASR/Orchestration/PipelineStage.mqh>

class CPatternStage : public IPipelineStage
  {
private:
   CPatternManager *m_pattern;
   bool             m_enabled;
   bool             m_debug;
   bool             m_profiling;
   CPerfTimer       m_timer;

public:
   CPatternStage()
      : m_pattern(NULL), m_enabled(true), m_debug(false), m_profiling(true)
     {}

   void Bind(CPatternManager *pattern)
     {
      m_pattern = pattern;
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
