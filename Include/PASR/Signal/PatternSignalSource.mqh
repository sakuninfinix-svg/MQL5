//+------------------------------------------------------------------+
//| Signal/PatternSignalSource.mqh — v2.02                           |
//| ISignalSource plugin: CPatternManager result → directional vote. |
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
   PatternSignalSource(CPatternManager *p, double minConfidence = 1.60)
      : m_pattern(p), m_minConfidence(minConfidence) {}

   virtual string Name() override { return "PatternSignalSource"; }

   virtual bool Evaluate(SignalResult &out) override
     {
      out.Clear();
      if(m_pattern == NULL) return false;

      SPatternResult pr = m_pattern.GetLastResult();
      if(!pr.found) return false;

      if(pr.confluenceScore < m_minConfidence) return false;

      out.confidence = MathMin(1.0, pr.confluenceScore / MathMax(m_minConfidence, 1.0));
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