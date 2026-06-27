//+------------------------------------------------------------------+
//| Signal/PatternSignalSource.mqh — v3.11                           |
//| ATR cross-check: weak range / ATR ratio penalty guard             |
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
   double           m_minRangeATR;   // min candle range/ATR ratio to allow full confidence
   double           m_maxRangeATR;   // max ratio above which we cap too-wide noise
   bool             m_useATRScaling;
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
   PatternSignalSource(CPatternManager *p, double minConfidence = 0.40,
                       bool useATRScaling = true,
                       double minRangeATR = 0.30,
                       double maxRangeATR = 4.00)
      : m_pattern(p), m_minConfidence(MathMax(0.0, MathMin(1.0, minConfidence))),
        m_minRangeATR(MathMax(0.05, minRangeATR)),
        m_maxRangeATR(MathMax(m_minRangeATR + 0.5, maxRangeATR)),
        m_useATRScaling(useATRScaling),
        m_lastEvaluated(0), m_lastDirection(SIGNAL_NONE),
        m_lastConfidence(0.0), m_lastReason("") {}

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

      double gapBoost       = MathMax(0.0, MathMin(1.0, pr.dominanceGap));
      double conflictPenalty= MathMax(0.0, MathMin(1.0, pr.conflictScore));
      double baseConf       = MathMax(0.0, MathMin(1.0,
                                score * (0.75 + 0.25 * gapBoost) * (1.0 - 0.35 * conflictPenalty)));

      // ATR cross-check guard: scale confidence by range/ATR ratio quality
      double atrMult = 1.0;
      string atrReason = "ATR-ok";
      if(m_useATRScaling && pr.rangePoints > 0.0)
        {
         if(pr.rangePoints < m_minRangeATR)
           {
            // weak signal: range too small relative to current volatility = thin bar noise
            atrMult = MathMax(0.4, pr.rangePoints / m_minRangeATR);
            atrReason = StringFormat("thinspace r/ATR=%.2f", pr.rangePoints);
           }
         else if(pr.rangePoints > m_maxRangeATR)
           {
            // runaway candle: extreme expansion = low-quality rejection signal
            atrMult = MathMax(0.4, m_maxRangeATR / pr.rangePoints);
            atrReason = StringFormat("hugecape r/ATR=%.2f", pr.rangePoints);
           }
        }
      out.confidence = MathMax(0.0, MathMin(1.0, baseConf * atrMult));
      out.reason     = pr.reason + (atrMult < 0.999 ? "|" + atrReason : "");

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
