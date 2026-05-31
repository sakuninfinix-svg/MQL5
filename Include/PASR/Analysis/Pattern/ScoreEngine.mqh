//+------------------------------------------------------------------+
//| ScoreEngine.mqh                                                  |
//| Unified scoring engine for pattern confluence and strength       |
//+------------------------------------------------------------------+
#property strict
#ifndef __SCORE_ENGINE_MQH__
#define __SCORE_ENGINE_MQH__

#include "CandleUtils.mqh"
#include <PASR/Data/RegimeTypes.mqh>

struct SScoreComponents
  {
   double patternScore;
   double rejectionScore;
   double momentumScore;
   double locationScore;
   double regimeScore;
   double volumeScore;
   double confluenceScore;

   void Reset()
     {
      patternScore = 0.0;
      rejectionScore = 0.0;
      momentumScore = 0.0;
      locationScore = 0.0;
      regimeScore = 0.0;
      volumeScore = 0.0;
      confluenceScore = 0.0;
     }

   double Total() const
     {
      return patternScore + rejectionScore + momentumScore +
             locationScore + regimeScore + volumeScore + confluenceScore;
     }
  };

struct SFinalScore
  {
   double rawScore;
   double normalizedScore;
   double confidence;
   string grade;
   bool   isValid;

   void Calculate(double raw, double minThreshold)
     {
      rawScore = raw;
      normalizedScore = MathMin(10.0, MathMax(0.0, raw / 0.5));
      confidence = MathMin(100.0, normalizedScore * 10.0);
      if(normalizedScore >= 9.0)      grade = "A+";
      else if(normalizedScore >= 8.0) grade = "A";
      else if(normalizedScore >= 7.0) grade = "B+";
      else if(normalizedScore >= 6.0) grade = "B";
      else if(normalizedScore >= 5.0) grade = "C+";
      else if(normalizedScore >= 4.0) grade = "C";
      else if(normalizedScore >= 3.0) grade = "D";
      else                            grade = "F";
      isValid = (rawScore >= minThreshold);
     }
  };

class CScoreEngine
  {
private:
   double m_minValidScore;
   double m_atrPoints;
   EMarketRegime m_currentRegime;
   double m_wPattern;
   double m_wRejection;
   double m_wMomentum;
   double m_wLocation;
   double m_wRegime;
   double m_wVolume;
   double m_wConfluence;

public:
   CScoreEngine()
      : m_minValidScore(1.6), m_atrPoints(0.0), m_currentRegime(REGIME_UNKNOWN),
        m_wPattern(1.0), m_wRejection(0.3), m_wMomentum(0.2),
        m_wLocation(0.25), m_wRegime(0.2), m_wVolume(0.1), m_wConfluence(0.35)
     {}

   void SetMinValidScore(double score)  { m_minValidScore = score; }
   void SetATRPoints(double atr)        { m_atrPoints = atr; }
   void SetRegime(EMarketRegime regime) { m_currentRegime = regime; }

   void SetWeights(double pattern, double rejection, double momentum,
                   double location, double regime, double volume, double confluence)
     {
      m_wPattern = pattern;
      m_wRejection = rejection;
      m_wMomentum = momentum;
      m_wLocation = location;
      m_wRegime = regime;
      m_wVolume = volume;
      m_wConfluence = confluence;
     }

   SFinalScore Calculate(SScoreComponents &components)
     {
      SFinalScore scoreResult;
      double weighted = (components.patternScore * m_wPattern) +
                        (components.rejectionScore * m_wRejection) +
                        (components.momentumScore * m_wMomentum) +
                        (components.locationScore * m_wLocation) +
                        (components.regimeScore * m_wRegime) +
                        (components.volumeScore * m_wVolume) +
                        (components.confluenceScore * m_wConfluence);
      scoreResult.Calculate(weighted, m_minValidScore);
      return scoreResult;
     }

   double CalculatePatternScore(int patternType, double baseScore)
     {
      double multiplier = 1.0;
      switch(patternType)
        {
         case 2: multiplier = 1.1; break;
         case 4: multiplier = 1.05; break;
         case 5: multiplier = 1.15; break;
         default: multiplier = 1.0; break;
        }
      return baseScore * multiplier;
     }

   double CalculateRejectionScore(MqlRates &rates[], int shift, int direction)
     {
      if(shift < 0 || shift + 1 >= ArraySize(rates)) return 0.0;
      double range = CandleRange(rates, shift);
      if(range <= 0.0) return 0.0;
      double score = 0.0;
      double majorWick = (direction == 1) ? LowerWick(rates, shift) : UpperWick(rates, shift);
      double wickPct = majorWick / range;
      if(wickPct >= 0.50) score += 0.15;
      if(wickPct >= 0.60) score += 0.10;
      if(wickPct >= 0.70) score += 0.10;
      double bodyPct = BodyPercent(rates, shift);
      if(bodyPct <= 0.35) score += 0.10;
      if(bodyPct <= 0.25) score += 0.05;
      if(IsLargeCandle(rates, shift, m_atrPoints, 0.6)) score += 0.10;
      return MathMin(0.5, score);
     }

   double CalculateMomentumScore(MqlRates &rates[], int shift, int direction)
     {
      if(shift < 1 || shift + 1 >= ArraySize(rates)) return 0.0;
      double score = 0.0;
      double prevClose = CandleClose(rates, shift + 1);
      double curClose  = CandleClose(rates, shift);
      if(direction == 1 && curClose > prevClose)
        {
         score += 0.10;
         if((curClose - prevClose) > CandleBody(rates, shift) * 0.5) score += 0.05;
        }
      else if(direction == -1 && curClose < prevClose)
        {
         score += 0.10;
         if((prevClose - curClose) > CandleBody(rates, shift) * 0.5) score += 0.05;
        }
      int consecutive = 0;
      int lim = MathMin(shift + 2, ArraySize(rates) - 1);
      for(int i = shift; i <= lim; i++)
        {
         if(direction == 1 && IsBullish(rates, i)) consecutive++;
         else if(direction == -1 && IsBearish(rates, i)) consecutive++;
        }
      if(consecutive >= 2) score += 0.10;
      if(consecutive >= 3) score += 0.10;
      return MathMin(0.4, score);
     }

   double CalculateLocationScore(double price, double support, double resistance, int direction)
     {
      if(support <= 0.0 || resistance <= 0.0 || support >= resistance) return 0.0;
      double range = resistance - support;
      double score = 0.0;
      if(direction == 1)
        {
         double distFromSupport = (price - support) / range;
         if(distFromSupport <= 0.10) score += 0.25;
         else if(distFromSupport <= 0.25) score += 0.15;
         else if(distFromSupport <= 0.40) score += 0.05;
        }
      else if(direction == -1)
        {
         double distFromResistance = (resistance - price) / range;
         if(distFromResistance <= 0.10) score += 0.25;
         else if(distFromResistance <= 0.25) score += 0.15;
         else if(distFromResistance <= 0.40) score += 0.05;
        }
      return MathMin(0.25, score);
     }

   double CalculateRegimeScore(EMarketRegime regime, int patternType, int direction)
     {
      double score = 0.0;
      if(regime == REGIME_RANGE || regime == REGIME_TRANSITION)
        {
         if(patternType == 1 || patternType == 2 || patternType == 5) score += 0.20;
        }
      if(regime == REGIME_TREND_UP || regime == REGIME_TREND_DOWN)
        {
         if(patternType == 4) score += 0.20;
         if((regime == REGIME_TREND_UP && direction == 1) ||
            (regime == REGIME_TREND_DOWN && direction == -1)) score += 0.15;
        }
      if(regime == REGIME_VOLATILE || regime == REGIME_CRASH) score -= 0.15;
      return MathMax(0.0, score);
     }

   double CalculateVolumeScore(MqlRates &rates[], int shift, int direction)
     {
      if(shift < 1 || shift + 1 >= ArraySize(rates)) return 0.0;
      long curVol = CandleVolume(rates, shift);
      long prevVol = CandleVolume(rates, shift + 1);
      if(prevVol <= 0) return 0.05;
      double volRatio = (double)curVol / (double)prevVol;
      double score = 0.0;
      if(volRatio >= 1.5) score += 0.10;
      if(volRatio >= 2.0) score += 0.05;
      return MathMin(0.15, score);
     }

   double CalculateConfluenceScore(double &patternScores[], int count)
     {
      if(count <= 0) return 0.0;
      int activePatterns = 0;
      double totalScore = 0.0;
      int n = MathMin(count, ArraySize(patternScores));
      for(int i = 0; i < n; i++)
        {
         if(patternScores[i] > 0.0)
           {
            activePatterns++;
            totalScore += patternScores[i];
           }
        }
      if(activePatterns == 0) return 0.0;
      double score = 0.0;
      if(activePatterns >= 2) score += 0.15;
      if(activePatterns >= 3) score += 0.15;
      if(activePatterns >= 4) score += 0.10;
      score += (totalScore / activePatterns) * 0.2;
      return MathMin(0.5, score);
     }

   bool IsStrongSignal(SFinalScore &score)
     { return score.normalizedScore >= 7.0 && score.isValid; }
   bool IsModerateSignal(SFinalScore &score)
     { return score.normalizedScore >= 5.0 && score.normalizedScore < 7.0 && score.isValid; }
   bool IsWeakSignal(SFinalScore &score)
     { return score.normalizedScore >= 3.0 && score.normalizedScore < 5.0; }

   double GetMinValidScore() const { return m_minValidScore; }

   string GetScoreBreakdown(SScoreComponents &comp)
     {
      return StringFormat("Pattern=%.2f | Rejection=%.2f | Momentum=%.2f | Location=%.2f | Regime=%.2f | Volume=%.2f | Confluence=%.2f | TOTAL=%.2f",
                          comp.patternScore,
                          comp.rejectionScore,
                          comp.momentumScore,
                          comp.locationScore,
                          comp.regimeScore,
                          comp.volumeScore,
                          comp.confluenceScore,
                          comp.Total());
     }
  };

#endif // __SCORE_ENGINE_MQH__
