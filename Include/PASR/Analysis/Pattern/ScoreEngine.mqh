//+------------------------------------------------------------------+
//| ScoreEngine.mqh                                                  |
//| Copyright 2026, Agsicentre                                       |
//| Unified scoring engine for pattern confluence and strength       |
//+------------------------------------------------------------------+
#ifndef __SCORE_ENGINE_MQH__
#define __SCORE_ENGINE_MQH__

#property strict

#include "CandleUtils.mqh"
#include "../Data/RegimeTypes.mqh"

//+------------------------------------------------------------------+
//| Score Components Structure                                       |
//+------------------------------------------------------------------+
struct SScoreComponents
{
   double patternScore;      // Base pattern detection score
   double rejectionScore;    // Wick rejection strength
   double momentumScore;     // Follow-through momentum
   double locationScore;     // Position relative to key levels
   double regimeScore;       // Regime alignment bonus
   double volumeScore;       // Volume confirmation (if available)
   double confluenceScore;   // Multi-pattern confluence
   
   void Reset()
   {
      patternScore   = 0.0;
      rejectionScore = 0.0;
      momentumScore  = 0.0;
      locationScore  = 0.0;
      regimeScore    = 0.0;
      volumeScore    = 0.0;
      confluenceScore = 0.0;
   }
   
   double Total() const
   {
      return patternScore + rejectionScore + momentumScore + 
             locationScore + regimeScore + volumeScore + confluenceScore;
   }
};

//+------------------------------------------------------------------+
//| Final Signal Score                                               |
//+------------------------------------------------------------------+
struct SFinalScore
{
   double rawScore;          // Un-normalized total
   double normalizedScore;   // Normalized to 0-10 scale
   double confidence;        // Confidence percentage 0-100%
   string grade;             // Letter grade (A+, A, B, C, D, F)
   bool   isValid;           // Whether score meets minimum threshold
   
   void Calculate(double raw, double minThreshold)
   {
      rawScore = raw;
      
      //--- Normalize to 0-10 scale (assuming max reasonable score is ~5.0)
      normalizedScore = MathMin(10.0, MathMax(0.0, raw / 0.5));
      
      //--- Convert to confidence percentage
      confidence = MathMin(100.0, normalizedScore * 10.0);
      
      //--- Assign letter grade
      if(normalizedScore >= 9.0)      grade = "A+";
      else if(normalizedScore >= 8.0) grade = "A";
      else if(normalizedScore >= 7.0) grade = "B+";
      else if(normalizedScore >= 6.0) grade = "B";
      else if(normalizedScore >= 5.0) grade = "C+";
      else if(normalizedScore >= 4.0) grade = "C";
      else if(normalizedScore >= 3.0) grade = "D";
      else                            grade = "F";
      
      //--- Validity check
      isValid = (rawScore >= minThreshold);
   }
};

//+------------------------------------------------------------------+
//| CScoreEngine Class                                               |
//| Centralized scoring system for all pattern evaluations          |
//+------------------------------------------------------------------+
class CScoreEngine
{
private:
   double m_minValidScore;
   double m_atrPoints;
   EMarketRegime m_currentRegime;
   
   //--- Weights for each component
   double m_wPattern;
   double m_wRejection;
   double m_wMomentum;
   double m_wLocation;
   double m_wRegime;
   double m_wVolume;
   double m_wConfluence;
   
public:
                  CScoreEngine();
   virtual       ~CScoreEngine();
   
   //--- Configuration
   void SetMinValidScore(double score)  { m_minValidScore = score; }
   void SetATRPoints(double atr)        { m_atrPoints = atr; }
   void SetRegime(EMarketRegime regime) { m_currentRegime = regime; }
   
   void SetWeights(double pattern, double rejection, double momentum, 
                   double location, double regime, double volume, double confluence);
   
   //--- Main scoring method
   SFinalScore Calculate(const SScoreComponents &components);
   
   //--- Component calculators
   double CalculatePatternScore(int patternType, double baseScore);
   double CalculateRejectionScore(const MqlRates &rates[], int shift, int direction);
   double CalculateMomentumScore(const MqlRates &rates[], int shift, int direction);
   double CalculateLocationScore(double price, double support, double resistance, int direction);
   double CalculateRegimeScore(EMarketRegime regime, int patternType, int direction);
   double CalculateVolumeScore(const MqlRates &rates[], int shift, int direction);
   double CalculateConfluenceScore(const double patternScores[], int count);
   
   //--- Quick evaluation helpers
   bool IsStrongSignal(const SFinalScore &score);
   bool IsModerateSignal(const SFinalScore &score);
   bool IsWeakSignal(const SFinalScore &score);
   
   //--- Getters
   double GetMinValidScore() const { return m_minValidScore; }
   string GetScoreBreakdown(const SScoreComponents &comp);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CScoreEngine::CScoreEngine() : m_minValidScore(1.6),
                               m_atrPoints(0.0),
                               m_currentRegime(REGIME_UNKNOWN),
                               m_wPattern(1.0),
                               m_wRejection(0.3),
                               m_wMomentum(0.2),
                               m_wLocation(0.25),
                               m_wRegime(0.2),
                               m_wVolume(0.1),
                               m_wConfluence(0.35)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CScoreEngine::~CScoreEngine()
{
}

//+------------------------------------------------------------------+
//| Set Custom Weights                                               |
//+------------------------------------------------------------------+
void CScoreEngine::SetWeights(double pattern, double rejection, double momentum, 
                              double location, double regime, double volume, double confluence)
{
   m_wPattern    = pattern;
   m_wRejection  = rejection;
   m_wMomentum   = momentum;
   m_wLocation   = location;
   m_wRegime     = regime;
   m_wVolume     = volume;
   m_wConfluence = confluence;
}

//+------------------------------------------------------------------+
//| Calculate Final Score                                            |
//+------------------------------------------------------------------+
SFinalScore CScoreEngine::Calculate(const SScoreComponents &components)
{
   SFinalScore final;
   
   //--- Weighted sum
   double weighted = (components.patternScore   * m_wPattern) +
                     (components.rejectionScore * m_wRejection) +
                     (components.momentumScore  * m_wMomentum) +
                     (components.locationScore  * m_wLocation) +
                     (components.regimeScore    * m_wRegime) +
                     (components.volumeScore    * m_wVolume) +
                     (components.confluenceScore * m_wConfluence);
   
   final.Calculate(weighted, m_minValidScore);
   return final;
}

//+------------------------------------------------------------------+
//| Calculate Pattern Score                                          |
//+------------------------------------------------------------------+
double CScoreEngine::CalculatePatternScore(int patternType, double baseScore)
{
   //--- Base score already provided, can apply pattern-specific multipliers
   double multiplier = 1.0;
   
   //--- High-probability patterns get slight boost
   switch(patternType)
   {
      case 1: // PATTERN_PINBAR
         multiplier = 1.0;
         break;
      case 2: // PATTERN_ENGULFING
         multiplier = 1.1;
         break;
      case 4: // PATTERN_INSIDE_BAR_BREAKOUT
         multiplier = 1.05;
         break;
      case 5: // PATTERN_FAKEY
         multiplier = 1.15;  // Fakeys are high probability
         break;
      default:
         multiplier = 1.0;
   }
   
   return baseScore * multiplier;
}

//+------------------------------------------------------------------+
//| Calculate Rejection Score                                        |
//+------------------------------------------------------------------+
double CScoreEngine::CalculateRejectionScore(const MqlRates &rates[], int shift, int direction)
{
   if(shift < 0 || shift + 1 >= ArraySize(rates))
      return 0.0;
   
   double range = CandleRange(rates, shift);
   if(range <= 0.0)
      return 0.0;
   
   double score = 0.0;
   
   //--- Major wick in direction of trade
   double majorWick = (direction == 1) ? LowerWick(rates, shift) : UpperWick(rates, shift);
   double wickPct = majorWick / range;
   
   if(wickPct >= 0.50) score += 0.15;
   if(wickPct >= 0.60) score += 0.10;
   if(wickPct >= 0.70) score += 0.10;
   
   //--- Small body confirms rejection
   double bodyPct = BodyPercent(rates, shift);
   if(bodyPct <= 0.35) score += 0.10;
   if(bodyPct <= 0.25) score += 0.05;
   
   //--- ATR expansion adds confidence
   if(IsLargeCandle(rates, shift, m_atrPoints, 0.6)) score += 0.10;
   
   return MathMin(0.5, score); // Cap at 0.5
}

//+------------------------------------------------------------------+
//| Calculate Momentum Score                                         |
//+------------------------------------------------------------------+
double CScoreEngine::CalculateMomentumScore(const MqlRates &rates[], int shift, int direction)
{
   if(shift < 1 || shift + 1 >= ArraySize(rates))
      return 0.0;
   
   double score = 0.0;
   
   //--- Follow-through: current close better than previous close
   double prevClose = CandleClose(rates, shift + 1);
   double curClose  = CandleClose(rates, shift);
   
   if(direction == 1 && curClose > prevClose)
   {
      score += 0.10;
      //--- Extra for strong follow-through
      if((curClose - prevClose) > CandleBody(rates, shift) * 0.5)
         score += 0.05;
   }
   else if(direction == -1 && curClose < prevClose)
   {
      score += 0.10;
      //--- Extra for strong follow-through
      if((prevClose - curClose) > CandleBody(rates, shift) * 0.5)
         score += 0.05;
   }
   
   //--- Multiple candles in same direction
   int consecutive = 0;
   for(int i = shift; i <= MathMin(shift + 2, ArraySize(rates) - 1); i++)
   {
      if(direction == 1 && IsBullish(rates, i))
         consecutive++;
      else if(direction == -1 && IsBearish(rates, i))
         consecutive++;
   }
   
   if(consecutive >= 2) score += 0.10;
   if(consecutive >= 3) score += 0.10;
   
   return MathMin(0.4, score);
}

//+------------------------------------------------------------------+
//| Calculate Location Score                                         |
//+------------------------------------------------------------------+
double CScoreEngine::CalculateLocationScore(double price, double support, double resistance, int direction)
{
   if(support <= 0.0 || resistance <= 0.0 || support >= resistance)
      return 0.0;
   
   double range = resistance - support;
   double score = 0.0;
   
   //--- Long near support
   if(direction == 1)
   {
      double distFromSupport = (price - support) / range;
      
      if(distFromSupport <= 0.10) score += 0.25;  // Very close to support
      else if(distFromSupport <= 0.25) score += 0.15;
      else if(distFromSupport <= 0.40) score += 0.05;
   }
   //--- Short near resistance
   else if(direction == -1)
   {
      double distFromResistance = (resistance - price) / range;
      
      if(distFromResistance <= 0.10) score += 0.25;  // Very close to resistance
      else if(distFromResistance <= 0.25) score += 0.15;
      else if(distFromResistance <= 0.40) score += 0.05;
   }
   
   return MathMin(0.25, score);
}

//+------------------------------------------------------------------+
//| Calculate Regime Score                                           |
//+------------------------------------------------------------------+
double CScoreEngine::CalculateRegimeScore(EMarketRegime regime, int patternType, int direction)
{
   double score = 0.0;
   
   //--- Reversal patterns favored in sideways markets
   if(regime == REGIME_SIDEWAYS || regime == REGIME_CONSOLIDATION)
   {
      if(patternType == 1 || patternType == 2 || patternType == 5) // Pinbar, Engulfing, Fakey
         score += 0.20;
   }
   
   //--- Breakout patterns favored in trending markets
   if(regime == REGIME_TREND_UP || regime == REGIME_TREND_DOWN)
   {
      if(patternType == 4) // Inside bar breakout
         score += 0.20;
      
      //--- Trend alignment bonus
      if((regime == REGIME_TREND_UP && direction == 1) ||
         (regime == REGIME_TREND_DOWN && direction == -1))
         score += 0.15;
   }
   
   //--- Penalty in high volatility/crash regimes
   if(regime == REGIME_HIGH_VOLATILITY || regime == REGIME_CRASH)
   {
      score -= 0.15;
   }
   
   return MathMax(0.0, score);
}

//+------------------------------------------------------------------+
//| Calculate Volume Score                                           |
//+------------------------------------------------------------------+
double CScoreEngine::CalculateVolumeScore(const MqlRates &rates[], int shift, int direction)
{
   if(shift < 1 || shift + 1 >= ArraySize(rates))
      return 0.0;
   
   long curVol = CandleVolume(rates, shift);
   long prevVol = CandleVolume(rates, shift + 1);
   
   if(prevVol <= 0)
      return 0.05; // Default small score if no volume data
   
   double volRatio = (double)curVol / (double)prevVol;
   
   double score = 0.0;
   
   //--- Above average volume is bullish for confirmation
   if(volRatio >= 1.5) score += 0.10;
   if(volRatio >= 2.0) score += 0.05;
   
   return MathMin(0.15, score);
}

//+------------------------------------------------------------------+
//| Calculate Confluence Score                                       |
//+------------------------------------------------------------------+
double CScoreEngine::CalculateConfluenceScore(const double patternScores[], int count)
{
   if(count <= 0)
      return 0.0;
   
   //--- Count how many patterns are signaling
   int activePatterns = 0;
   double totalScore = 0.0;
   
   for(int i = 0; i < count; i++)
   {
      if(patternScores[i] > 0.0)
      {
         activePatterns++;
         totalScore += patternScores[i];
      }
   }
   
   if(activePatterns == 0)
      return 0.0;
   
   //--- Base confluence for multiple patterns agreeing
   double score = 0.0;
   
   if(activePatterns >= 2) score += 0.15;
   if(activePatterns >= 3) score += 0.15;
   if(activePatterns >= 4) score += 0.10;
   
   //--- Add average strength
   score += (totalScore / activePatterns) * 0.2;
   
   return MathMin(0.5, score);
}

//+------------------------------------------------------------------+
//| Signal Strength Classifiers                                      |
//+------------------------------------------------------------------+
bool CScoreEngine::IsStrongSignal(const SFinalScore &score)
{
   return score.normalizedScore >= 7.0 && score.isValid;
}

bool CScoreEngine::IsModerateSignal(const SFinalScore &score)
{
   return score.normalizedScore >= 5.0 && score.normalizedScore < 7.0 && score.isValid;
}

bool CScoreEngine::IsWeakSignal(const SFinalScore &score)
{
   return score.normalizedScore >= 3.0 && score.normalizedScore < 5.0;
}

//+------------------------------------------------------------------+
//| Get Score Breakdown String                                       |
//+------------------------------------------------------------------+
string CScoreEngine::GetScoreBreakdown(const SScoreComponents &comp)
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

#endif // __SCORE_ENGINE_MQH__
