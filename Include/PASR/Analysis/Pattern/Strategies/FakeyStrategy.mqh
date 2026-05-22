//+------------------------------------------------------------------+
//|                                            FakeyStrategy.mqh     |
//|                                 Copyright 2024, PASR Framework   |
//|                                     https://pasr-framework.com   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, PASR Framework"
#property link      "https://pasr-framework.com"
#property version   "2.0.0"
#property description "Fakey (False Breakout) pattern detection strategy"

#include "IPatternStrategy.mqh"
#include "InsideBarStrategy.mqh"
#include "../CandleUtils.mqh"
#include "../FakeoutDetector.mqh"

//+------------------------------------------------------------------+
//| Fakey Strategy Implementation                                    |
//+------------------------------------------------------------------+
class CFakeyStrategy : public CBasePatternStrategy
{
private:
   CInsideBarStrategy m_insideBarChecker;
   CFakeoutDetector m_fakeoutDetector;
   double m_minFakeoutStrength;
   
public:
   CFakeyStrategy()
   {
      m_name = "Fakey";
      m_patternType = PATTERN_FAKEY;
      m_minFakeoutStrength = 60.0;
   }
   
   virtual void Init() override
   {
      CBasePatternStrategy::Init();
      m_insideBarChecker.Init();
      m_fakeoutDetector.Init();
   }
   
   virtual double CalculateRawScore(int shift, 
                                   const CPatternContext &context) override
   {
      if(shift < 2)
         return 0.0;
      
      // Check if bar-1 was inside bar
      if(!m_insideBarChecker.CheckPatternShape(shift - 1))
         return 0.0;
      
      double motherHigh = iHigh(_Symbol, _Period, shift);
      double motherLow = iLow(_Symbol, _Period, shift);
      double currentHigh = iHigh(_Symbol, _Period, shift);
      double currentLow = iLow(_Symbol, _Period, shift);
      double currentClose = iClose(_Symbol, _Period, shift);
      double currentOpen = iOpen(_Symbol, _Period, shift);
      
      double score = 0.0;
      
      // Bullish Fakey: False breakdown below mother low, then close back inside/above
      if(currentLow < motherLow && currentClose > motherLow)
      {
         score = 80.0;
         
         // Stronger if long lower wick (rejection)
         double lowerWick = currentClose - currentLow;
         double candleRange = currentHigh - currentLow;
         
         if(candleRange > 0)
         {
            double wickRatio = lowerWick / candleRange;
            if(wickRatio > 0.6)
               score += 15.0;  // Long rejection wick
         }
         
         // Bonus if close is in upper half
         if(currentClose > (currentHigh + currentLow) / 2.0)
            score += 5.0;
      }
      // Bearish Fakey: False breakout above mother high, then close back inside/below
      else if(currentHigh > motherHigh && currentClose < motherHigh)
      {
         score = 80.0;
         
         // Stronger if long upper wick (rejection)
         double upperWick = currentHigh - currentClose;
         double candleRange = currentHigh - currentLow;
         
         if(candleRange > 0)
         {
            double wickRatio = upperWick / candleRange;
            if(wickRatio > 0.6)
               score += 15.0;  // Long rejection wick
         }
         
         // Bonus if close is in lower half
         if(currentClose < (currentHigh + currentLow) / 2.0)
            score += 5.0;
      }
      
      // Apply fakeout detector analysis
      SFakeoutResult fakeoutResult = m_fakeoutDetector.AnalyzeFakeout(shift);
      if(fakeoutResult.isFakeout && fakeoutResult.confidence >= m_minFakeoutStrength)
      {
         score += fakeoutResult.confidence * 0.2;  // Up to +20 points
      }
      
      return MathMin(score, 100.0);
   }
   
   virtual bool CheckPatternShape(int shift) override
   {
      if(shift < 2)
         return false;
      
      // Previous bar must be inside bar
      if(!m_insideBarChecker.CheckPatternShape(shift - 1))
         return false;
      
      double motherHigh = iHigh(_Symbol, _Period, shift);
      double motherLow = iLow(_Symbol, _Period, shift);
      double currentHigh = iHigh(_Symbol, _Period, shift);
      double currentLow = iLow(_Symbol, _Period, shift);
      double currentClose = iClose(_Symbol, _Period, shift);
      
      // Must have false breakout (wick outside, close inside)
      bool bullishFakey = (currentLow < motherLow && currentClose > motherLow);
      bool bearishFakey = (currentHigh > motherHigh && currentClose < motherHigh);
      
      return (bullishFakey || bearishFakey);
   }
   
   virtual bool CheckPatternLocation(int shift, const CPatternContext &context) override
   {
      // Fakeys are most powerful at key levels
      const SLocationContext &loc = context.GetLocationContext();
      
      if(loc.isNearSupport || loc.isNearResistance)
         return true;
      
      // Also good at round numbers
      double price = iClose(_Symbol, _Period, shift);
      double roundNumber = MathRound(price / 100.0) * 100.0;
      if(MathAbs(price - roundNumber) < 10 * _Point)
         return true;
      
      return true;  // Can form anywhere but better at key levels
   }
   
   virtual bool CheckPatternSize(int shift, const SPatternParams &params) override
   {
      double motherRange = iHigh(_Symbol, _Period, shift) - iLow(_Symbol, _Period, shift);
      double atr = CCandleUtils::GetATR(14, shift);
      
      if(atr == 0)
         return true;
      
      double rangeRatio = motherRange / atr;
      
      // Mother bar should be reasonable size
      return (rangeRatio >= params.minBarSizeRatio * 0.5);
   }
   
   virtual double EvaluatePatternStrength(int shift) override
   {
      return CalculateRawScore(shift, m_currentContext);
   }
   
protected:
   virtual int DetermineDirection(int shift) override
   {
      double motherLow = iLow(_Symbol, _Period, shift);
      double currentClose = iClose(_Symbol, _Period, shift);
      
      // Bullish fakey: rejected lows
      if(currentClose > motherLow && iLow(_Symbol, _Period, shift) < motherLow)
         return 1;
      
      // Bearish fakey: rejected highs
      if(currentClose < iHigh(_Symbol, _Period, shift) && iHigh(_Symbol, _Period, shift) > iHigh(_Symbol, _Period, shift))
         return -1;
      
      // Default: check close position
      double motherMid = (iHigh(_Symbol, _Period, shift) + iLow(_Symbol, _Period, shift)) / 2.0;
      if(currentClose > motherMid)
         return 1;
      else if(currentClose < motherMid)
         return -1;
      
      return 0;
   }
};
