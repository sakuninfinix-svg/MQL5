//+------------------------------------------------------------------+
//| Signal/PatternSignalSource.mqh — v3.10                           |
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
   datetime         m_lastEvaluated;
   ENUM_SIGNAL_DIR  m_lastDirection;
   double           m_lastConfidence;
   string           m_lastReason;

   void StoreLast(SignalResult &out, const string reason)
     {
      m_lastEvaluated  = TimeCurrent();
      out.evaluatedAt  = m_lastEvaluated;
      m_lastDirection  = out.direction;
      m_lastConfidence = out.confidence;
      m_lastReason     = reason;
     }

public:
   PatternSignalSource(CPatternManager *p, double minConfidence = 0.40)
      : m_pattern(p), m_minConfidence(MathMax(0.0, MathMin(1.0, minConfidence))),
        m_lastEvaluated(0), m_lastDirection(SIGNAL_NONE), m_lastConfidence(0.0), m_lastReason("") {}

   virtual string Name() override { return "PatternSignalSource"; }

   virtual bool Evaluate(SignalResult &out) override
     {
      out.Clear();
      if(m_pattern == NULL)
        {
         StoreLast(out, "Pattern manager NULL");
         return false;
        }

      SPatternResult pr = m_pattern.GetLastResult();
      if(!pr.found)
        {
         StoreLast(out, "No pattern found");
         return false;
        }

      double score = MathMax(0.0, MathMin(1.0, pr.confluenceScore));
      if(score < m_minConfidence)
        {
         out.confidence = score;
         StoreLast(out, StringFormat("Pattern score %.3f < min %.3f", score, m_minConfidence));
         return false;
        }

      double gapBoost = MathMax(0.0, MathMin(1.0, pr.dominanceGap));
      double conflictPenalty = MathMax(0.0, MathMin(1.0, pr.conflictScore));
      out.confidence = MathMax(0.0, MathMin(1.0, score * (0.75 + 0.25 * gapBoost) * (1.0 - 0.35 * conflictPenalty)));
      out.reason     = pr.reason;

      if(pr.direction > 0)
        {
         out.direction = SIGNAL_BUY;
         StoreLast(out, out.reason);
         return true;
        }
      if(pr.direction < 0)
        {
         out.direction = SIGNAL_SELL;
         StoreLast(out, out.reason);
         return true;
        }

      out.direction = SIGNAL_NONE;
      StoreLast(out, "Pattern direction neutral");
      return false;
     }

   int GetTotalPatternsDetected() const { return m_pattern != NULL ? m_pattern.GetTotalDetected() : 0; }
   int GetTotalValidSignals() const { return m_pattern != NULL ? m_pattern.GetTotalValidSignals() : 0; }
   datetime GetLastEvaluated() const { return m_lastEvaluated; }
   ENUM_SIGNAL_DIR GetLastDirection() const { return m_lastDirection; }
   double GetLastConfidence() const { return m_lastConfidence; }
   string GetLastReason() const { return m_lastReason; }
  };

#endif // __SIGNAL_PATTERN_SOURCE_MQH__
