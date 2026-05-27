//+------------------------------------------------------------------+
//|                                     EngulfingStrategy.mqh        |
//|                                 Copyright 2024, PASR Framework   |
//|                                     https://pasr-framework.com   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, PASR Framework"
#property link      "https://pasr-framework.com"
#property version   "2.0.0"
#property description "Engulfing pattern detection strategy"

#include "IPatternStrategy.mqh"
#include "../CandleUtils.mqh"

//+------------------------------------------------------------------+
//| Engulfing Strategy Implementation                                |
//+------------------------------------------------------------------+
class CEngulfingStrategy : public CBasePatternStrategy
{
private:
   SEngulfingParams  m_params;             // Engulfing-specific parameters
   double            m_engulfPercent;      // Cached engulfment percentage
   bool              m_isBullish;          // Direction flag
   int               m_priorTrendBars;     // Count of prior trend bars
   
public:
   void Init() override
   {
      CBasePatternStrategy::Init();
      m_name = "Engulfing Strategy";
      m_patternType = PATTERN_ENGULFING;
      m_params.Init();
   }
   
   void SetParameters(const SEngulfingParams &params)
   {
      m_params = params;
   }
   
   const SEngulfingParams& GetParameters() const
   {
      return m_params;
   }
   
protected:
   virtual bool CheckPatternShape(int shift) override
   {
      // Current (engulfing) candle
      double currOpen = GetOpen(_Symbol, _Period, shift);
      double currHigh = GetHigh(_Symbol, _Period, shift);
      double currLow = GetLow(_Symbol, _Period, shift);
      double currClose = GetClose(_Symbol, _Period, shift);
      
      // Previous candle
      double prevOpen = GetOpen(_Symbol, _Period, shift + 1);
      double prevHigh = GetHigh(_Symbol, _Period, shift + 1);
      double prevLow = GetLow(_Symbol, _Period, shift + 1);
      double prevClose = GetClose(_Symbol, _Period, shift + 1);
      
      double currRange = currHigh - currLow;
      double prevRange = prevHigh - prevLow;
      
      if(currRange == 0 || prevRange == 0)
         return false;
      
      double currBody = MathAbs(currClose - currOpen);
      double prevBody = MathAbs(prevClose - prevOpen);
      
      // Check if current engulfs previous
      bool engulfsHigh = currHigh >= prevHigh;
      bool engulfsLow = currLow <= prevLow;
      bool engulfsBody = (currOpen <= prevClose && currClose >= prevOpen) ||
                        (currClose <= prevOpen && currOpen >= prevClose);
      
      if(m_params.requireFullEngulf)
      {
         if(!engulfsHigh || !engulfsLow)
            return false;
      }
      
      if(!engulfsBody)
         return false;
      
      // Calculate engulfment percentage
      m_engulfPercent = currBody / prevBody;
      if(m_engulfPercent < m_params.minEngulfPercent)
         return false;
      
      // Determine direction
      m_isBullish = (currClose > currOpen);
      
      // Check prior trend
      m_priorTrendBars = CountPriorTrendBars(shift, m_isBullish ? -1 : 1);
      if(m_priorTrendBars < m_params.minPriorTrendBars)
         return false;
      
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
      
      return true;
   }
   
   virtual bool CheckPatternSize(int shift, const SPatternParams &params) override
   {
      double atr = context.GetMarketContext().atr;
      if(atr == 0)
         return true;
      
      double candleRange = GetHigh(_Symbol, _Period, shift) - GetLow(_Symbol, _Period, shift);
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
      
      // Engulfment percentage scoring (up to +30 points)
      double engulfBonus = (m_engulfPercent - m_params.minEngulfPercent) * 20.0;
      score += MathMin(engulfBonus, 30.0);
      
      // Prior trend strength scoring (up to +25 points)
      double trendBonus = m_priorTrendBars * 5.0;
      score += MathMin(trendBonus, 25.0);
      
      // Full engulf bonus
      if(m_params.requireFullEngulf)
      {
         double currHigh = GetHigh(_Symbol, _Period, shift);
         double currLow = GetLow(_Symbol, _Period, shift);
         double prevHigh = GetHigh(_Symbol, _Period, shift + 1);
         double prevLow = GetLow(_Symbol, _Period, shift + 1);
         
         if(currHigh > prevHigh && currLow < prevLow)
            score += 15.0;  // Complete engulfment
      }
      
      // Close position scoring (up to +20 points)
      double currClose = GetClose(_Symbol, _Period, shift);
      double currOpen = GetOpen(_Symbol, _Period, shift);
      double currHigh = GetHigh(_Symbol, _Period, shift);
      double currLow = GetLow(_Symbol, _Period, shift);
      
      double closePosition = 0.0;
      if(m_isBullish)
         closePosition = (currClose - currLow) / (currHigh - currLow);
      else
         closePosition = (currHigh - currClose) / (currHigh - currLow);
      
      if(closePosition > 0.8)
         score += 20.0;  // Strong close in direction
      else if(closePosition > 0.6)
         score += 10.0;
      
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
      double high = GetHigh(_Symbol, _Period, shift);
      double low = GetLow(_Symbol, _Period, shift);
      double close = GetClose(_Symbol, _Period, shift);
      double point = _Point;
      
      if(direction > 0)  // Bullish engulfing
      {
         entry = close;
         stopLoss = low - 2 * point;  // Below engulfing low
         double risk = entry - stopLoss;
         takeProfit = entry + 2 * risk;  // 1:2 RR
      }
      else  // Bearish engulfing
      {
         entry = close;
         stopLoss = high + 2 * point;  // Above engulfing high
         double risk = stopLoss - entry;
         takeProfit = entry - 2 * risk;  // 1:2 RR
      }
   }
   
   virtual string GetEvaluationNotes() const override
   {
      string notes = CBasePatternStrategy::GetEvaluationNotes();
      notes += StringFormat("Engulf: %.2fx, PriorTrend: %d bars", 
                           m_engulfPercent, m_priorTrendBars);
      return notes;
   }
   
private:
   int CountPriorTrendBars(int shift, int expectedDirection)
   {
      int count = 0;
      int lookback = m_params.minPriorTrendBars + 5;  // Extra buffer
      
      for(int i = shift + 1; i < shift + lookback && i < Bars(_Symbol, _Period); i++)
      {
         double open = GetOpen(_Symbol, _Period, i);
         double close = GetClose(_Symbol, _Period, i);
         
         int barDir = 0;
         if(close > open)
            barDir = 1;
         else if(close < open)
            barDir = -1;
         
         if(barDir == expectedDirection)
            count++;
         else
            break;
      }
      
      return count;
   }
};
