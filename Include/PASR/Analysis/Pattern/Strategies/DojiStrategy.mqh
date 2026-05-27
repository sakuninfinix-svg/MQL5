//+------------------------------------------------------------------+
//|                                           DojiStrategy.mqh       |
//|                                 Copyright 2024, PASR Framework   |
//|                                     https://pasr-framework.com   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, PASR Framework"
#property link      "https://pasr-framework.com"
#property version   "2.0.0"
#property description "Doji pattern detection strategy"

#include "IPatternStrategy.mqh"
#include "../CandleUtils.mqh"

//+------------------------------------------------------------------+
//| Doji Strategy Implementation                                     |
//+------------------------------------------------------------------+
class CDojiStrategy : public CBasePatternStrategy
{
private:
   double m_maxBodyToRangeRatio;
   double m_minRangeRatio;
   
public:
   CDojiStrategy()
   {
      m_name = "Doji";
      m_patternType = PATTERN_DOJI;
      m_maxBodyToRangeRatio = 0.15;  // Body is < 15% of total range
      m_minRangeRatio = 0.7;         // Range should be reasonable vs ATR
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
      
      double open = GetOpen(_Symbol, _Period, shift);
      double close = GetClose(_Symbol, _Period, shift);
      double high = GetHigh(_Symbol, _Period, shift);
      double low = GetLow(_Symbol, _Period, shift);
      
      double body = MathAbs(close - open);
      double range = high - low;
      double upperWick = high - MathMax(open, close);
      double lowerWick = MathMin(open, close) - low;
      
      if(range == 0)
         return 0.0;
      
      double score = 0.0;
      
      // Base score for doji formation
      double bodyRatio = body / range;
      if(bodyRatio <= m_maxBodyToRangeRatio)
      {
         score = 60.0;
         
         // Bonus for very small body (perfect doji)
         if(bodyRatio < 0.05)
            score += 20.0;
         else if(bodyRatio < 0.10)
            score += 10.0;
      }
      
      // Analyze wick symmetry for different doji types
      double wickRatio = 0.0;
      if(MathMax(upperWick, lowerWick) > 0)
         wickRatio = MathMin(upperWick, lowerWick) / MathMax(upperWick, lowerWick);
      
      // Standard doji: balanced wicks
      if(wickRatio > 0.7)
         score += 10.0;
      
      // Dragonfly doji: long lower wick, short/no upper wick
      if(lowerWick > upperWick * 2.0 && upperWick < range * 0.1)
         score += 15.0;
      
      // Gravestone doji: long upper wick, short/no lower wick
      if(upperWick > lowerWick * 2.0 && lowerWick < range * 0.1)
         score += 15.0;
      
      // Check location context
      const SLocationContext &loc = context.GetLocationContext();
      if(loc.isNearSupport || loc.isNearResistance)
         score += 10.0;  // Doji at key levels more significant
      
      return MathMin(score, 100.0);
   }
   
   virtual bool CheckPatternShape(int shift) override
   {
      double open = GetOpen(_Symbol, _Period, shift);
      double close = GetClose(_Symbol, _Period, shift);
      double high = GetHigh(_Symbol, _Period, shift);
      double low = GetLow(_Symbol, _Period, shift);
      
      double body = MathAbs(close - open);
      double range = high - low;
      
      if(range == 0)
         return false;
      
      double bodyRatio = body / range;
      
      // Must have very small body relative to range
      if(bodyRatio > m_maxBodyToRangeRatio)
         return false;
      
      // Range should be reasonable (not a flat line)
      double atr = CCandleUtils::GetATR(14, shift);
      if(atr > 0)
      {
         double rangeRatio = range / atr;
         if(rangeRatio < m_minRangeRatio * 0.5)
            return false;
      }
      
      return true;
   }
   
   virtual bool CheckPatternLocation(int shift, const CPatternContext &context) override
   {
      // Doji can form anywhere, but more significant at key levels
      return true;
   }
   
   virtual bool CheckPatternSize(int shift, const SPatternParams &params) override
   {
      double range = GetHigh(_Symbol, _Period, shift) - GetLow(_Symbol, _Period, shift);
      double atr = CCandleUtils::GetATR(14, shift);
      
      if(atr == 0)
         return true;
      
      double rangeRatio = range / atr;
      
      // Doji range should be at least reasonable
      return (rangeRatio >= params.minBarSizeRatio * 0.3);
   }
   
   virtual double EvaluatePatternStrength(int shift) override
   {
      return CalculateRawScore(shift, m_currentContext);
   }
   
protected:
   virtual int DetermineDirection(int shift) override
   {
      // Doji itself is neutral - direction determined by context
      // Check previous trend for potential reversal
      
      if(shift < 1)
         return 0;
      
      double prevClose = GetClose(_Symbol, _Period, shift + 1);
      double prevOpen = GetOpen(_Symbol, _Period, shift + 1);
      double currentClose = GetClose(_Symbol, _Period, shift);
      
      // If previous was bullish and doji forms, potential bearish reversal
      if(prevClose > prevOpen)
         return -1;
      
      // If previous was bearish and doji forms, potential bullish reversal
      if(prevClose < prevOpen)
         return 1;
      
      return 0;
   }
};

//+------------------------------------------------------------------+
//| Long-Legged Doji Strategy                                        |
//+------------------------------------------------------------------+
class CLongLeggedDojiStrategy : public CDojiStrategy
{
public:
   CLongLeggedDojiStrategy()
   {
      m_name = "LongLeggedDoji";
      m_patternType = PATTERN_DOJI;
   }
   
   virtual bool CheckPatternShape(int shift) override
   {
      if(!CDojiStrategy::CheckPatternShape(shift))
         return false;
      
      double open = GetOpen(_Symbol, _Period, shift);
      double close = GetClose(_Symbol, _Period, shift);
      double high = GetHigh(_Symbol, _Period, shift);
      double low = GetLow(_Symbol, _Period, shift);
      
      double body = MathAbs(close - open);
      double range = high - low;
      double upperWick = high - MathMax(open, close);
      double lowerWick = MathMin(open, close) - low;
      
      if(range == 0)
         return false;
      
      // Both wicks must be long (> 40% of range each)
      return (upperWick > range * 0.4 && lowerWick > range * 0.4);
   }
   
   virtual double CalculateRawScore(int shift, 
                                   const CPatternContext &context) override
   {
      double baseScore = CDojiStrategy::CalculateRawScore(shift, context);
      
      if(baseScore > 0)
      {
         // Bonus for long-legged formation
         baseScore += 15.0;
      }
      
      return MathMin(baseScore, 100.0);
   }
};
