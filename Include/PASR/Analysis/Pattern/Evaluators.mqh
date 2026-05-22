//+------------------------------------------------------------------+
//| Evaluators.mqh                                                   |
//| Copyright 2026, Agsicentre                                       |
//| Pattern evaluation utilities for scoring and validation          |
//+------------------------------------------------------------------+
#ifndef __EVALUATORS_MQH__
#define __EVALUATORS_MQH__

#property strict

#include "CandleUtils.mqh"
#include "../Data/RegimeTypes.mqh"

//+------------------------------------------------------------------+
//| Evaluation Result Structure                                      |
//+------------------------------------------------------------------+
struct SEvaluationResult
{
   bool   isValid;
   double baseScore;
   double regimeWeight;
   double finalScore;
   string patternName;
   int    direction;        // 1 = bullish, -1 = bearish, 0 = neutral
   double extremePrice;     // Key level (high for bearish, low for bullish)
   string notes;
   
   void Reset()
   {
      isValid       = false;
      baseScore     = 0.0;
      regimeWeight  = 1.0;
      finalScore    = 0.0;
      patternName   = "";
      direction     = 0;
      extremePrice  = 0.0;
      notes         = "";
   }
   
   void CalculateFinal()
   {
      if(isValid)
         finalScore = baseScore * regimeWeight;
      else
         finalScore = 0.0;
   }
};

//+------------------------------------------------------------------+
//| Base Evaluator Class                                             |
//+------------------------------------------------------------------+
class CPatternEvaluator
{
protected:
   double m_minScore;
   double m_atrPoints;
   
public:
                  CPatternEvaluator() : m_minScore(1.0), m_atrPoints(0.0) {}
   virtual       ~CPatternEvaluator() {}
   
   void SetMinScore(double score) { m_minScore = score; }
   void SetATRPoints(double atr)  { m_atrPoints = atr; }
   
   virtual bool Evaluate(const MqlRates &rates[], int shift, SEvaluationResult &result) = 0;
   
protected:
   //--- Scoring helpers
   void AddRejectionStrength(const MqlRates &rates[], int shift, int dir, double &score)
   {
      double range = CandleRange(rates, shift);
      if(range <= 0.0) return;
      
      double majorWick = (dir == 1) ? LowerWick(rates, shift) : UpperWick(rates, shift);
      double wickPct = majorWick / range;
      double bodyPct = BodyPercent(rates, shift);
      double atrFactor = NormalizeRangeByATR(rates, shift, m_atrPoints);
      
      if(wickPct >= 0.50) score += 0.20;
      if(wickPct >= 0.60) score += 0.10;
      if(bodyPct <= 0.35) score += 0.10;
      if(atrFactor >= 0.60) score += 0.10;
   }
   
   void AddFollowThroughStrength(const MqlRates &rates[], int shift, int dir, double &score)
   {
      if(shift < 1 || shift + 1 >= ArraySize(rates)) return;
      
      double prevClose = CandleClose(rates, shift + 1);
      double curClose  = CandleClose(rates, shift);
      
      if(dir == 1 && curClose > prevClose) score += 0.10;
      if(dir == -1 && curClose < prevClose) score += 0.10;
   }
   
   double CalculateRegimeWeight(EMarketRegime regime, int direction) const
   {
      double weight = 1.0;
      
      //--- Boost reversal patterns in ranging markets
      if(regime == REGIME_SIDEWAYS || regime == REGIME_CONSOLIDATION)
      {
         weight += 0.20;
      }
      
      //--- Boost trend-following in trending markets
      if(regime == REGIME_TREND_UP || regime == REGIME_TREND_DOWN)
      {
         if((regime == REGIME_TREND_UP && direction == 1) ||
            (regime == REGIME_TREND_DOWN && direction == -1))
            weight += 0.15;
      }
      
      //--- Reduce confidence in high volatility
      if(regime == REGIME_HIGH_VOLATILITY || regime == REGIME_CRASH)
      {
         weight -= 0.15;
      }
      
      return MathMax(0.5, weight);
   }
};

//+------------------------------------------------------------------+
//| Pinbar Evaluator                                                 |
//+------------------------------------------------------------------+
class CPinbarEvaluator : public CPatternEvaluator
{
public:
   virtual bool Evaluate(const MqlRates &rates[], int shift, SEvaluationResult &result) override
   {
      result.Reset();
      
      if(shift < 0 || shift + 1 >= ArraySize(rates))
         return false;
      
      double range = CandleRange(rates, shift);
      if(range <= 0.0)
         return false;
      
      double bodyMid = CandleMidpoint(rates, shift);
      double upper = UpperWick(rates, shift);
      double lower = LowerWick(rates, shift);
      
      int dir = 0;
      double extreme = 0.0;
      
      //--- Bullish pinbar: close in upper half, long lower wick
      if(CandleClose(rates, shift) > bodyMid && lower > (upper > 0 ? upper * 2.0 : _Point))
      {
         dir = 1;
         extreme = CandleLow(rates, shift);
      }
      //--- Bearish pinbar: close in lower half, long upper wick
      else if(CandleClose(rates, shift) < bodyMid && upper > (lower > 0 ? lower * 2.0 : _Point))
      {
         dir = -1;
         extreme = CandleHigh(rates, shift);
      }
      else
         return false;
      
      result.isValid      = true;
      result.patternName  = (dir == 1) ? "Pinbar Bull" : "Pinbar Bear";
      result.direction    = dir;
      result.extremePrice = extreme;
      result.baseScore    = 1.00;
      
      //--- Add strength modifiers
      AddRejectionStrength(rates, shift, dir, result.baseScore);
      AddFollowThroughStrength(rates, shift, dir, result.baseScore);
      
      result.CalculateFinal();
      return result.isValid;
   }
};

//+------------------------------------------------------------------+
//| Engulfing Pattern Evaluator                                      |
//+------------------------------------------------------------------+
class CEngulfingEvaluator : public CPatternEvaluator
{
public:
   virtual bool Evaluate(const MqlRates &rates[], int shift, SEvaluationResult &result) override
   {
      result.Reset();
      
      if(shift < 1 || shift + 1 >= ArraySize(rates))
         return false;
      
      double o1 = CandleOpen(rates, shift),     c1 = CandleClose(rates, shift);
      double o2 = CandleOpen(rates, shift + 1), c2 = CandleClose(rates, shift + 1);
      
      bool prevBearish = c2 < o2;
      bool prevBullish = c2 > o2;
      
      int dir = 0;
      double extreme = 0.0;
      double score = 1.00;
      
      //--- Bullish engulfing
      if(prevBearish && c1 > o1 && c1 > o2 && o1 < c2)
      {
         dir = 1;
         extreme = CandleLow(rates, shift);
      }
      //--- Bearish engulfing
      else if(prevBullish && c1 < o1 && c1 < o2 && o1 > c2)
      {
         dir = -1;
         extreme = CandleHigh(rates, shift);
      }
      else
         return false;
      
      //--- Score enhancement for strong engulfing
      double body1 = CandleBody(rates, shift);
      double body2 = CandleBody(rates, shift + 1);
      if(body2 > 0.0 && body1 >= body2 * 1.20) score += 0.20;
      if(IsLargeCandle(rates, shift, m_atrPoints, 0.7)) score += 0.15;
      
      result.isValid      = true;
      result.patternName  = (dir == 1) ? "Engulf Bull" : "Engulf Bear";
      result.direction    = dir;
      result.extremePrice = extreme;
      result.baseScore    = score;
      
      AddFollowThroughStrength(rates, shift, dir, result.baseScore);
      result.CalculateFinal();
      
      return result.isValid;
   }
};

//+------------------------------------------------------------------+
//| Tweezer Pattern Evaluator                                        |
//+------------------------------------------------------------------+
class CTweezerEvaluator : public CPatternEvaluator
{
public:
   virtual bool Evaluate(const MqlRates &rates[], int shift, SEvaluationResult &result) override
   {
      result.Reset();
      
      if(shift < 1 || shift + 1 >= ArraySize(rates))
         return false;
      
      double h1 = CandleHigh(rates, shift);
      double l1 = CandleLow(rates, shift);
      double h2 = CandleHigh(rates, shift + 1);
      double l2 = CandleLow(rates, shift + 1);
      
      //--- Tolerance for matching highs/lows
      double tol = MathMax(m_atrPoints * 0.10 * _Point, 3 * _Point);
      
      int dir = 0;
      double extreme = 0.0;
      double score = 1.00;
      
      //--- Tweezer Bottom: similar lows with bullish close
      if(MathAbs(l1 - l2) <= tol && IsBullish(rates, shift))
      {
         dir = 1;
         extreme = MathMin(l1, l2);
      }
      //--- Tweezer Top: similar highs with bearish close
      else if(MathAbs(h1 - h2) <= tol && IsBearish(rates, shift))
      {
         dir = -1;
         extreme = MathMax(h1, h2);
      }
      else
         return false;
      
      //--- Score enhancements
      if(IsLargeCandle(rates, shift, m_atrPoints, 0.5)) score += 0.10;
      if(BodyPercent(rates, shift) >= 0.35) score += 0.10;
      
      result.isValid      = true;
      result.patternName  = (dir == 1) ? "Tweezer Bottom" : "Tweezer Top";
      result.direction    = dir;
      result.extremePrice = extreme;
      result.baseScore    = score;
      
      result.CalculateFinal();
      return result.isValid;
   }
};

//+------------------------------------------------------------------+
//| Fakey Pattern Evaluator                                          |
//+------------------------------------------------------------------+
class CFakeyEvaluator : public CPatternEvaluator
{
public:
   virtual bool Evaluate(const MqlRates &rates[], int shift, SEvaluationResult &result) override
   {
      result.Reset();
      
      if(shift < 2 || shift + 2 >= ArraySize(rates))
         return false;
      
      //--- Check for inside bar structure (mother bar -> inside bar -> fakeout)
      double h1 = CandleHigh(rates, shift + 1);
      double l1 = CandleLow(rates, shift + 1);
      double h2 = CandleHigh(rates, shift + 2);
      double l2 = CandleLow(rates, shift + 2);
      
      bool insideStructure = (h1 < h2 && l1 > l2);
      if(!insideStructure)
         return false;
      
      //--- Current bar fakeout
      double h0 = CandleHigh(rates, shift);
      double l0 = CandleLow(rates, shift);
      double c0 = CandleClose(rates, shift);
      double o0 = CandleOpen(rates, shift);
      
      int dir = 0;
      double extreme = 0.0;
      double score = 1.00;
      
      //--- Bullish fakey: break below inside bar low, then close back inside
      if(l0 < l1 && c0 > l1 && c0 > o0)
      {
         dir = 1;
         extreme = l0;
      }
      //--- Bearish fakey: break above inside bar high, then close back inside
      else if(h0 > h1 && c0 < h1 && c0 < o0)
      {
         dir = -1;
         extreme = h0;
      }
      else
         return false;
      
      //--- Score enhancements
      if(IsLargeCandle(rates, shift, m_atrPoints, 0.6)) score += 0.15;
      if(BodyPercent(rates, shift) >= 0.40) score += 0.10;
      
      result.isValid      = true;
      result.patternName  = (dir == 1) ? "Fakey Bull" : "Fakey Bear";
      result.direction    = dir;
      result.extremePrice = extreme;
      result.baseScore    = score;
      
      result.CalculateFinal();
      return result.isValid;
   }
};

//+------------------------------------------------------------------+
//| Inside Bar Breakout Evaluator                                    |
//+------------------------------------------------------------------+
class CInsideBarEvaluator : public CPatternEvaluator
{
public:
   virtual bool Evaluate(const MqlRates &rates[], int shift, SEvaluationResult &result) override
   {
      result.Reset();
      
      if(shift < 1 || shift + 1 >= ArraySize(rates))
         return false;
      
      if(!IsInsideBar(rates, shift))
         return false;
      
      double motherHigh = CandleHigh(rates, shift + 1);
      double motherLow  = CandleLow(rates, shift + 1);
      double motherMid  = (motherHigh + motherLow) / 2.0;
      double childClose = CandleClose(rates, shift);
      
      int dir = 0;
      double extreme = 0.0;
      double score = 1.00;
      
      //--- Determine bias based on close position within mother bar
      if(childClose > motherMid)
      {
         dir = 1;
         extreme = CandleLow(rates, shift);
      }
      else if(childClose < motherMid)
      {
         dir = -1;
         extreme = CandleHigh(rates, shift);
      }
      else
         return false;
      
      //--- Score enhancements
      double motherRange = CandleRange(rates, shift + 1);
      double childRange  = CandleRange(rates, shift);
      
      if(motherRange > 0.0 && childRange / motherRange <= 0.65) score += 0.15;
      if(NormalizeRangeByATR(rates, shift + 1, m_atrPoints) >= 0.70) score += 0.10;
      
      result.isValid      = true;
      result.patternName  = (dir == 1) ? "Inside Bull" : "Inside Bear";
      result.direction    = dir;
      result.extremePrice = extreme;
      result.baseScore    = score;
      
      result.CalculateFinal();
      return result.isValid;
   }
};

#endif // __EVALUATORS_MQH__
