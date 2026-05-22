//+------------------------------------------------------------------+
//|                                        PinbarStrategy.mqh        |
//|                                 Copyright 2024, PASR Framework   |
//|                                     https://pasr-framework.com   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, PASR Framework"
#property link      "https://pasr-framework.com"
#property version   "2.0.0"
#property description "Pinbar pattern detection strategy"

#include "IPatternStrategy.mqh"
#include "../CandleUtils.mqh"

//+------------------------------------------------------------------+
//| Pinbar Strategy Implementation                                   |
//+------------------------------------------------------------------+
class CPinbarStrategy : public CBasePatternStrategy
{
private:
   SPinbarParams     m_params;             // Pinbar-specific parameters
   double            m_tailRatio;          // Cached tail ratio
   double            m_bodyRatio;          // Cached body ratio
   double            m_noseRatio;          // Cached nose ratio
   bool              m_isBullish;          // Direction flag
   
public:
   void Init() override
   {
      CBasePatternStrategy::Init();
      m_name = "Pinbar Strategy";
      m_patternType = PATTERN_PINBAR;
      m_params.Init();
   }
   
   void SetParameters(const SPinbarParams &params)
   {
      m_params = params;
   }
   
   const SPinbarParams& GetParameters() const
   {
      return m_params;
   }
   
protected:
   virtual bool CheckPatternShape(int shift) override
   {
      double open = iOpen(_Symbol, _Period, shift);
      double high = iHigh(_Symbol, _Period, shift);
      double low = iLow(_Symbol, _Period, shift);
      double close = iClose(_Symbol, _Period, shift);
      
      double candleRange = high - low;
      if(candleRange == 0)
         return false;
      
      double bodySize = MathAbs(close - open);
      double upperWick = high - MathMax(open, close);
      double lowerWick = MathMin(open, close) - low;
      
      m_bodyRatio = bodySize / candleRange;
      m_tailRatio = MathMax(upperWick, lowerWick) / candleRange;
      m_noseRatio = MathMin(upperWick, lowerWick) / candleRange;
      
      // Check tail ratio (must be significant)
      if(m_tailRatio < m_params.minTailRatio)
         return false;
      
      // Check nose ratio (must be small)
      if(m_noseRatio > m_params.minNoseRatio)
         return false;
      
      // Check body ratio (should be small for pinbar)
      if(m_bodyRatio > (1.0 - m_params.minTailRatio))
         return false;
      
      m_isBullish = (lowerWick > upperWick);
      
      return true;
   }
   
   virtual bool CheckPatternLocation(int shift, const CPatternContext &context) override
   {
      const SLocationContext &locCtx = context.GetLocationContext();
      
      // If requireSRConfluence is set, must be near S/R
      if(m_params.requireSRConfluence)
      {
         if(!locCtx.nearSupport && !locCtx.nearResistance)
            return false;
         
         if(locCtx.distanceToSR > m_params.maxDistanceFromSR)
            return false;
      }
      
      // Additional location checks can be added here
      
      return true;
   }
   
   virtual bool CheckPatternSize(int shift, const SPatternParams &params) override
   {
      double atr = context.GetMarketContext().atr;
      if(atr == 0)
         return true;  // Skip ATR check if not available
      
      double candleRange = iHigh(_Symbol, _Period, shift) - iLow(_Symbol, _Period, shift);
      double candleATR = candleRange / atr;
      
      if(candleATR < params.minCandleSizeATR)
         return false;
      
      if(candleATR > params.maxCandleSizeATR)
         return false;
      
      return true;
   }
   
   virtual double EvaluatePatternStrength(int shift) override
   {
      double score = 50.0;  // Base score
      
      // Tail ratio scoring (up to +30 points)
      double tailBonus = (m_tailRatio - m_params.minTailRatio) * 50.0;
      score += MathMin(tailBonus, 30.0);
      
      // Nose ratio scoring (up to +20 points)
      double noseBonus = (m_params.minNoseRatio - m_noseRatio) * 40.0;
      score += MathMin(noseBonus, 20.0);
      
      // Body ratio scoring (up to +15 points)
      double bodyBonus = (1.0 - m_bodyRatio - m_params.minBodyRatio) * 30.0;
      score += MathMin(bodyBonus, 15.0);
      
      // Break of previous high/low bonus (up to +15 points)
      if(m_params.requireBreakOfPrev)
      {
         double prevHigh = iHigh(_Symbol, _Period, shift + 1);
         double prevLow = iLow(_Symbol, _Period, shift + 1);
         double currHigh = iHigh(_Symbol, _Period, shift);
         double currLow = iLow(_Symbol, _Period, shift);
         
         if(m_isBullish && currLow < prevLow)
            score += 15.0;  // Swept lows before reversing
         else if(!m_isBullish && currHigh > prevHigh)
            score += 15.0;  // Swept highs before reversing
      }
      
      return MathMax(0.0, MathMin(score, 100.0));
   }
   
   virtual int DetermineDirection(int shift) override
   {
      if(m_isBullish)
         return 1;
      else
         return -1;
   }
   
   virtual void GetRiskLevels(int shift, 
                             int direction,
                             double &entry,
                             double &stopLoss,
                             double &takeProfit) override
   {
      double high = iHigh(_Symbol, _Period, shift);
      double low = iLow(_Symbol, _Period, shift);
      double close = iClose(_Symbol, _Period, shift);
      double point = _Point;
      
      if(direction > 0)  // Bullish pinbar
      {
         entry = close;
         stopLoss = low - 2 * point;  // Below tail
         double risk = entry - stopLoss;
         takeProfit = entry + 2 * risk;  // 1:2 RR
      }
      else  // Bearish pinbar
      {
         entry = close;
         stopLoss = high + 2 * point;  // Above tail
         double risk = stopLoss - entry;
         takeProfit = entry - 2 * risk;  // 1:2 RR
      }
   }
   
   virtual string GetEvaluationNotes() const override
   {
      string notes = CBasePatternStrategy::GetEvaluationNotes();
      notes += StringFormat("Tail: %.2f, Body: %.2f, Nose: %.2f", 
                           m_tailRatio, m_bodyRatio, m_noseRatio);
      return notes;
   }
};
