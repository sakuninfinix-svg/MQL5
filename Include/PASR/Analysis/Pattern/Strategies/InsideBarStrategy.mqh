//+------------------------------------------------------------------+
//|                                         InsideBarStrategy.mqh    |
//|                                 Copyright 2024, PASR Framework   |
//|                                     https://pasr-framework.com   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, PASR Framework"
#property link      "https://pasr-framework.com"
#property version   "2.0.0"
#property description "Inside Bar and Inside Bar Breakout detection strategy"

#include "IPatternStrategy.mqh"
#include "../CandleUtils.mqh"

//+------------------------------------------------------------------+
//| Inside Bar Strategy Implementation                               |
//+------------------------------------------------------------------+
class CInsideBarStrategy : public CBasePatternStrategy
{
private:
   double m_minInsideRatio;     // Minimum inside bar ratio
   double m_maxInsideRatio;     // Maximum inside bar ratio
   
public:
   CInsideBarStrategy()
   {
      m_name = "InsideBar";
      m_patternType = PATTERN_INSIDE_BAR;
      m_minInsideRatio = 0.5;
      m_maxInsideRatio = 0.9;
   }
   
   virtual void Init() override
   {
      CBasePatternStrategy::Init();
   }
   
   virtual double CalculateRawScore(int shift, 
                                   const CPatternContext &context) override
   {
      if(!CheckPatternShape(shift))
         return 0.0;
      
      double motherHigh = iHigh(_Symbol, _Period, shift + 1);
      double motherLow = iLow(_Symbol, _Period, shift + 1);
      double insideHigh = iHigh(_Symbol, _Period, shift);
      double insideLow = iLow(_Symbol, _Period, shift);
      
      double motherRange = motherHigh - motherLow;
      double insideRange = insideHigh - insideLow;
      
      if(motherRange == 0)
         return 0.0;
      
      double ratio = insideRange / motherRange;
      
      // Score based on how well it fits the inside bar criteria
      double score = 0.0;
      if(ratio >= m_minInsideRatio && ratio <= m_maxInsideRatio)
      {
         score = 70.0;
         
         // Bonus for tighter inside bars
         if(ratio < 0.7)
            score += 15.0;
         
         // Bonus if inside bar is in upper/lower half of mother bar
         double motherMid = (motherHigh + motherLow) / 2.0;
         double insideMid = (insideHigh + insideLow) / 2.0;
         
         if(MathAbs(insideMid - motherMid) > motherRange * 0.2)
            score += 15.0;  // Offset inside bar gets bonus
      }
      
      return score;
   }
   
   virtual bool CheckPatternShape(int shift) override
   {
      if(shift < 1)
         return false;
      
      double motherHigh = iHigh(_Symbol, _Period, shift + 1);
      double motherLow = iLow(_Symbol, _Period, shift + 1);
      double insideHigh = iHigh(_Symbol, _Period, shift);
      double insideLow = iLow(_Symbol, _Period, shift);
      
      // Inside bar must be completely within mother bar's range
      if(insideHigh >= motherHigh || insideLow <= motherLow)
         return false;
      
      double motherRange = motherHigh - motherLow;
      double insideRange = insideHigh - insideLow;
      
      if(motherRange == 0)
         return false;
      
      double ratio = insideRange / motherRange;
      
      return (ratio >= m_minInsideRatio && ratio <= m_maxInsideRatio);
   }
   
   virtual bool CheckPatternLocation(int shift, const CPatternContext &context) override
   {
      // Inside bars are more significant near key levels
      const SLocationContext &loc = context.GetLocationContext();
      
      // Bonus if near support/resistance
      if(loc.isNearSupport || loc.isNearResistance)
         return true;
      
      // Also valid in consolidation areas
      if(loc.consolidationScore > 50.0)
         return true;
      
      return true;  // Inside bars can form anywhere
   }
   
   virtual bool CheckPatternSize(int shift, const SPatternParams &params) override
   {
      double motherRange = iHigh(_Symbol, _Period, shift + 1) - iLow(_Symbol, _Period, shift + 1);
      double atr = CCandleUtils::GetATR(14, shift);
      
      if(atr == 0)
         return true;
      
      double rangeRatio = motherRange / atr;
      
      // Mother bar should be at least reasonable size
      return (rangeRatio >= params.minBarSizeRatio * 0.5);
   }
   
   virtual double EvaluatePatternStrength(int shift) override
   {
      return CalculateRawScore(shift, m_currentContext);
   }
   
protected:
   virtual int DetermineDirection(int shift) override
   {
      // Inside bar itself is neutral - direction determined by breakout
      // For now, check previous trend
      double prevClose = iClose(_Symbol, _Period, shift + 1);
      double prevOpen = iOpen(_Symbol, _Period, shift + 1);
      
      if(prevClose > prevOpen)
         return 1;   // Bullish bias
      else if(prevClose < prevOpen)
         return -1;  // Bearish bias
      
      return 0;
   }
};

//+------------------------------------------------------------------+
//| Inside Bar Breakout Strategy                                     |
//+------------------------------------------------------------------+
class CInsideBarBreakoutStrategy : public CBasePatternStrategy
{
private:
   CInsideBarStrategy m_insideBarChecker;
   
public:
   CInsideBarBreakoutStrategy()
   {
      m_name = "InsideBarBreakout";
      m_patternType = PATTERN_INSIDE_BAR_BREAKOUT;
   }
   
   virtual void Init() override
   {
      CBasePatternStrategy::Init();
      m_insideBarChecker.Init();
   }
   
   virtual double CalculateRawScore(int shift, 
                                   const CPatternContext &context) override
   {
      if(shift < 1)
         return 0.0;
      
      // Check if previous bar was inside bar
      if(!m_insideBarChecker.CheckPatternShape(shift - 1))
         return 0.0;
      
      double motherHigh = iHigh(_Symbol, _Period, shift);
      double motherLow = iLow(_Symbol, _Period, shift);
      double currentClose = iClose(_Symbol, _Period, shift);
      double currentOpen = iOpen(_Symbol, _Period, shift);
      
      double score = 0.0;
      
      // Bullish breakout: close above mother high
      if(currentClose > motherHigh)
      {
         score = 75.0;
         
         // Stronger if close is well above high
         double breakoutStrength = (currentClose - motherHigh) / (motherHigh - motherLow);
         if(breakoutStrength > 0.3)
            score += 15.0;
         
         // Bonus if strong bullish candle
         if(CCandleUtils::IsStrongBullish(shift, 1.5))
            score += 10.0;
      }
      // Bearish breakout: close below mother low
      else if(currentClose < motherLow)
      {
         score = 75.0;
         
         // Stronger if close is well below low
         double breakoutStrength = (motherLow - currentClose) / (motherHigh - motherLow);
         if(breakoutStrength > 0.3)
            score += 15.0;
         
         // Bonus if strong bearish candle
         if(CCandleUtils::IsStrongBearish(shift, 1.5))
            score += 10.0;
      }
      
      return score;
   }
   
   virtual bool CheckPatternShape(int shift) override
   {
      if(shift < 1)
         return false;
      
      // Previous bar must be inside bar
      if(!m_insideBarChecker.CheckPatternShape(shift - 1))
         return false;
      
      double motherHigh = iHigh(_Symbol, _Period, shift);
      double motherLow = iLow(_Symbol, _Period, shift);
      double currentClose = iClose(_Symbol, _Period, shift);
      
      // Must have breakout (close outside mother range)
      return (currentClose > motherHigh || currentClose < motherLow);
   }
   
   virtual bool CheckPatternLocation(int shift, const CPatternContext &context) override
   {
      return true;  // Breakouts can happen anywhere
   }
   
   virtual bool CheckPatternSize(int shift, const SPatternParams &params) override
   {
      return true;  // Size check done by inside bar checker
   }
   
   virtual double EvaluatePatternStrength(int shift) override
   {
      return CalculateRawScore(shift, m_currentContext);
   }
   
protected:
   virtual int DetermineDirection(int shift) override
   {
      double motherHigh = iHigh(_Symbol, _Period, shift);
      double currentClose = iClose(_Symbol, _Period, shift);
      
      if(currentClose > motherHigh)
         return 1;   // Bullish breakout
      else if(currentClose < iLow(_Symbol, _Period, shift))
         return -1;  // Bearish breakout
      
      return 0;
   }
};
