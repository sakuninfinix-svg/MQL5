//+------------------------------------------------------------------+
//| Signal/SignalScorer.mqh — v2.00                                  |
//| Pure signal scoring: normalization, quality tiers, confluence    |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_SCORER_MQH__
#define __SIGNAL_SCORER_MQH__

enum ENUM_SIGNAL_QUALITY
  {
   SIGNAL_QUALITY_HIGH   = 0,
   SIGNAL_QUALITY_MEDIUM = 1,
   SIGNAL_QUALITY_LOW    = 2
  };

class CSignalScorer
  {
private:
   double Clamp01(double v) const { return MathMax(0.0, MathMin(1.0, v)); }

public:
   CSignalScorer() {}

   double NormalizeScore(double rawScore, double totalWeight) const
     {
      if(totalWeight <= 0.0) return 0.0;
      return Clamp01(rawScore / totalWeight);
     }

   ENUM_SIGNAL_QUALITY GetQualityTier(double normalizedScore) const
     {
      if(normalizedScore >= 0.75) return SIGNAL_QUALITY_HIGH;
      if(normalizedScore >= 0.50) return SIGNAL_QUALITY_MEDIUM;
      return SIGNAL_QUALITY_LOW;
     }

   double ScoreConfluence(int confluenceCount) const
     {
      if(confluenceCount <= 0) return 0.0;
      if(confluenceCount >= 4) return 1.0;
      return (double)confluenceCount / 4.0;
     }

   double ScoreDominance(double winnerScore, double loserScore) const
     {
      if(winnerScore <= 0.0) return 0.0;
      double gap = winnerScore - loserScore;
      return Clamp01(gap / winnerScore);
     }

   double ApplyConfluenceBonus(double normalizedScore, int confluenceCount) const
     {
      double bonus = ScoreConfluence(confluenceCount);
      return Clamp01(normalizedScore * (0.7 + 0.3 * bonus));
     }
  };

#endif // __SIGNAL_SCORER_MQH__
