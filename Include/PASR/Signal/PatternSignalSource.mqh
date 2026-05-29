//+------------------------------------------------------------------+
//| Signal/PatternSignalSource.mqh — v3.00                           |
//| ISignalSource plugin: normalized pattern regression fallback vote |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_PATTERN_SOURCE_MQH__
#define __SIGNAL_PATTERN_SOURCE_MQH__

#include "ISignalSource.mqh"
#include "../Analysis/Pattern/PatternManager.mqh"

class PatternSignalSource : public ISignalSource
  {
private:
   CPatternManager *m_pattern;
   double           m_minConfidence;

public:
   PatternSignalSource(CPatternManager *p, double minConfidence = 0.55)
      : m_pattern(p), m_minConfidence(MathMax(0.0, MathMin(1.0, minConfidence))) {}

   virtual string Name() override { return "PatternSignalSource"; }

   virtual bool Evaluate(SignalResult &out) override
     {
      out.Clear();
      if(m_pattern == NULL) return false;

      SPatternResult pr = m_pattern.GetLastResult();
      if(!pr.found) return false;

      double score = MathMax(0.0, MathMin(1.0, pr.confluenceScore));
      if(score < m_minConfidence) return false;

      double gapBoost = MathMax(0.0, MathMin(1.0, pr.dominanceGap));
      double conflictPenalty = MathMax(0.0, MathMin(1.0, pr.conflictScore));
      out.confidence = MathMax(0.0, MathMin(1.0, score * (0.75 + 0.25 * gapBoost) * (1.0 - 0.35 * conflictPenalty)));
      out.reason     = pr.reason;

      if(pr.direction > 0)
        {
         out.direction = SIGNAL_BUY;
         return true;
        }
      if(pr.direction < 0)
        {
         out.direction = SIGNAL_SELL;
         return true;
        }

      out.direction = SIGNAL_NONE;
      return false;
     }

   int GetTotalPatternsDetected() const { return m_pattern != NULL ? m_pattern.GetTotalDetected() : 0; }
   int GetTotalValidSignals() const { return m_pattern != NULL ? m_pattern.GetTotalValidSignals() : 0; }
  };

#endif // __SIGNAL_PATTERN_SOURCE_MQH__