//+------------------------------------------------------------------+
//|                                           HaramiStrategy.mqh     |
//|                                 Copyright 2024, PASR Framework   |
//|                                     https://pasr-framework.com   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, PASR Framework"
#property link      "https://pasr-framework.com"
#property version   "2.0.0"
#property description "Harami pattern detection strategy"

#include "IPatternStrategy.mqh"
#include "../CandleUtils.mqh"

//+------------------------------------------------------------------+
//| Harami Strategy Implementation                                   |
//+------------------------------------------------------------------+
class CHaramiStrategy : public CBasePatternStrategy
{
private:
   double m_minBodyRatio;
   double m_maxBodyRatio;
   
public:
   CHaramiStrategy()
   {
      m_name = "Harami";
      m_patternType = PATTERN_HARAMI;
      m_minBodyRatio = 0.1;
      m_maxBodyRatio = 0.7;
   }
   
   virtual void Init() override
   {
      CBasePatternStrategy::Init();
   }
   
   virtual double CalculateRawScore(int shift, 
                                   const CPatternContext &context) override
   {
      if(shift < 1)
         return 0.0;
      
      double motherOpen = iOpen(_Symbol, _Period, shift + 1);
      double motherClose = iClose(_Symbol, _Period, shift + 1);
      double babyOpen = iOpen(_Symbol, _Period, shift);
      double babyClose = iClose(_Symbol, _Period, shift);
      
      double motherBody = MathAbs(motherClose - motherOpen);
      double babyBody = MathAbs(babyClose - babyOpen);
      
      if(motherBody == 0)
         return 0.0;
      
      double bodyRatio = babyBody / motherBody;
      
      double score = 0.0;
      
      // Check if baby body is within mother body range
      double motherHigh = MathMax(motherOpen, motherClose);
      double motherLow = MathMin(motherOpen, motherClose);
      double babyHigh = MathMax(babyOpen, babyClose);
      double babyLow = MathMin(babyOpen, babyClose);
      
      if(babyHigh <= motherHigh && babyLow >= motherLow)
      {
         score = 65.0;
         
         // Bonus for smaller baby body
         if(bodyRatio < m_maxBodyRatio)
            score += 15.0;
         
         // Bonus if baby is doji (very small body)
         if(bodyRatio < 0.2)
            score += 10.0;
         
         // Bonus for opposite colors (reversal signal)
         bool motherBullish = (motherClose > motherOpen);
         bool babyBullish = (babyClose > babyOpen);
         
         if(motherBullish != babyBullish)
            score += 10.0;  // Color contrast bonus
      }
      
      return score;
   }
   
   virtual bool CheckPatternShape(int shift) override
   {
      if(shift < 1)
         return false;
      
      double motherOpen = iOpen(_Symbol, _Period, shift + 1);
      double motherClose = iClose(_Symbol, _Period, shift + 1);
      double babyOpen = iOpen(_Symbol, _Period, shift);
      double babyClose = iClose(_Symbol, _Period, shift);
      
      double motherHigh = MathMax(motherOpen, motherClose);
      double motherLow = MathMin(motherOpen, motherClose);
      double babyHigh = MathMax(babyOpen, babyClose);
      double babyLow = MathMin(babyOpen, babyClose);
      
      // Baby body must be completely inside mother body
      if(babyHigh > motherHigh || babyLow < motherLow)
         return false;
      
      double motherBody = motherHigh - motherLow;
      double babyBody = babyHigh - babyLow;
      
      if(motherBody == 0)
         return false;
      
      double bodyRatio = babyBody / motherBody;
      
      return (bodyRatio >= m_minBodyRatio && bodyRatio <= m_maxBodyRatio);
   }
   
   virtual bool CheckPatternLocation(int shift, const CPatternContext &context) override
   {
      // Harami is more significant after strong moves
      const SLocationContext &loc = context.GetLocationContext();
      
      // Good at support/resistance
      if(loc.isNearSupport || loc.isNearResistance)
         return true;
      
      // Also good after extended moves
      if(MathAbs(loc.trendStrength) > 60.0)
         return true;
      
      return true;
   }
   
   virtual bool CheckPatternSize(int shift, const SPatternParams &params) override
   {
      double motherBody = MathAbs(iClose(_Symbol, _Period, shift + 1) - iOpen(_Symbol, _Period, shift + 1));
      double atr = CCandleUtils::GetATR(14, shift + 1);
      
      if(atr == 0)
         return true;
      
      double bodyRatio = motherBody / atr;
      
      // Mother bar should have reasonable body size
      return (bodyRatio >= params.minBarSizeRatio * 0.5);
   }
   
   virtual double EvaluatePatternStrength(int shift) override
   {
      return CalculateRawScore(shift, m_currentContext);
   }
   
protected:
   virtual int DetermineDirection(int shift) override
   {
      double motherOpen = iOpen(_Symbol, _Period, shift + 1);
      double motherClose = iClose(_Symbol, _Period, shift + 1);
      double babyClose = iClose(_Symbol, _Period, shift);
      
      // Bullish harami: mother bearish, baby closes higher
      if(motherClose < motherOpen && babyClose > motherClose)
         return 1;
      
      // Bearish harami: mother bullish, baby closes lower
      if(motherClose > motherOpen && babyClose < motherClose)
         return -1;
      
      // Default based on baby close position
      double motherMid = (MathMax(motherOpen, motherClose) + MathMin(motherOpen, motherClose)) / 2.0;
      if(babyClose > motherMid)
         return 1;
      else if(babyClose < motherMid)
         return -1;
      
      return 0;
   }
};

//+------------------------------------------------------------------+
//| Harami Cross Strategy (Baby is Doji)                             |
//+------------------------------------------------------------------+
class CHaramiCrossStrategy : public CHaramiStrategy
{
public:
   CHaramiCrossStrategy()
   {
      m_name = "HaramiCross";
      m_patternType = PATTERN_HARAMI;  // Same type, stricter criteria
      m_maxBodyRatio = 0.2;  // Very small baby body (doji-like)
   }
   
   virtual bool CheckPatternShape(int shift) override
   {
      if(!CHaramiStrategy::CheckPatternShape(shift))
         return false;
      
      // Additional check: baby must be doji-like
      double babyOpen = iOpen(_Symbol, _Period, shift);
      double babyClose = iClose(_Symbol, _Period, shift);
      double babyHigh = iHigh(_Symbol, _Period, shift);
      double babyLow = iLow(_Symbol, _Period, shift);
      
      double babyBody = MathAbs(babyClose - babyOpen);
      double babyRange = babyHigh - babyLow;
      
      if(babyRange == 0)
         return false;
      
      double bodyToRangeRatio = babyBody / babyRange;
      
      // Doji: body is very small compared to range
      return (bodyToRangeRatio < 0.3);
   }
   
   virtual double CalculateRawScore(int shift, 
                                   const CPatternContext &context) override
   {
      double baseScore = CHaramiStrategy::CalculateRawScore(shift, context);
      
      if(baseScore > 0)
      {
         // Bonus for being a true cross (doji baby)
         baseScore += 15.0;
      }
      
      return MathMin(baseScore, 100.0);
   }
};
