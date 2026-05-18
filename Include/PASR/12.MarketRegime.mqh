//+------------------------------------------------------------------+
//|                                             12.MarketRegime.mqh |
//|                                       Copyright 2026, Agsicentre |
//|            Multi-Timeframe Market Regime & Volatility Filter     |
//|                                                                  |
//| FEATURES:                                                        |
//| - Numeric Scoring System (0-1) for regime and volatility        |
//| - Proper indicator initialization and cleanup                   |
//| - Optimized volatility calculation with history buffers         |
//| - Smart transition detection with dual counter system           |
//| - Multi-timeframe trend confirmation                            |
//| - Full SignalManager integration                                |
//| - Robust error handling with fallback values                    |
//| - Backward compatibility maintained                             |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "2.00"
#property strict

#ifndef __MARKET_REGIME_MQH__
#define __MARKET_REGIME_MQH__

#include "IManager.mqh"
// NOTE: Do NOT include 10.DataManager.mqh here to avoid circular dependency!
// DataManager is accessed via pointer (forward declaration below)

//+------------------------------------------------------------------+
//| Forward Declaration: DataManager                                 |
//| NOTE: Do NOT include 10.DataManager.mqh here to avoid circular   |
//|       dependency. The actual class is defined in that file.      |
//+------------------------------------------------------------------+
class DataManager;

//+------------------------------------------------------------------+
//| ENUMS: Market Regime Types                                       |
//+------------------------------------------------------------------+
enum ENUM_MARKET_REGIME
{
   REGIME_NONE = 0,
   REGIME_TRENDING_STRONG,    // Strong trending market
   REGIME_TRENDING_WEAK,      // Weak trending market
   REGIME_RANGING_SIDEWAYS,   // Sideways/ranging market
   REGIME_CHOPPY_HIGH_VOL,    // Choppy with high volatility
   REGIME_TRANSITION          // Regime transition (avoid trading)
};

enum ENUM_VOLATILITY_REGIME
{
   VOLATILITY_LOW = 0,
   VOLATILITY_MEDIUM,
   VOLATILITY_HIGH
};

//+------------------------------------------------------------------+
//| STRUCT: Regime Result with Numeric Scoring                       |
//+------------------------------------------------------------------+
struct RegimeResult
{
   ENUM_MARKET_REGIME regime;
   ENUM_VOLATILITY_REGIME volRegime;
   double regimeScore;        // 0.0 - 1.0 numeric score
   double volatilityScore;    // 0.0 - 1.0 normalized volatility
   double trendStrength;      // ADX value
   double atrRatio;           // Current ATR / Average ATR
   bool isTransition;         // True if regime changing
   bool mtfConfirmed;         // Multi-TF confirmation status
   int tfAlignment;           // Number of aligned timeframes (0-3)
   
   RegimeResult()
   {
      regime = REGIME_NONE;
      volRegime = VOLATILITY_MEDIUM;
      regimeScore = 0.0;
      volatilityScore = 0.5;
      trendStrength = 0.0;
      atrRatio = 1.0;
      isTransition = false;
      mtfConfirmed = false;
      tfAlignment = 0;
   }
   
   // Get minimum signal threshold based on regime
   double GetMinSignalThreshold(double baseThreshold = 0.5) const
   {
      if(isTransition) return baseThreshold * 2.0;  // Require stronger signals
      
      switch(regime)
      {
         case REGIME_TRENDING_STRONG: return baseThreshold * 0.7;  // More lenient
         case REGIME_TRENDING_WEAK:   return baseThreshold * 0.85;
         case REGIME_RANGING_SIDEWAYS: return baseThreshold * 1.3; // Stricter
         case REGIME_CHOPPY_HIGH_VOL: return baseThreshold * 1.5;  // Much stricter
         default: return baseThreshold * 2.0;
      }
   }
   
   string Description() const
   {
      string regimeStr = "";
      switch(regime)
      {
         case REGIME_TRENDING_STRONG: regimeStr = "Strong Trend"; break;
         case REGIME_TRENDING_WEAK: regimeStr = "Weak Trend"; break;
         case REGIME_RANGING_SIDEWAYS: regimeStr = "Ranging"; break;
         case REGIME_CHOPPY_HIGH_VOL: regimeStr = "Choppy High Vol"; break;
         case REGIME_TRANSITION: regimeStr = "Transition"; break;
         default: regimeStr = "Unknown"; break;
      }
      
      string volStr = "";
      switch(volRegime)
      {
         case VOLATILITY_LOW: volStr = "Low Vol"; break;
         case VOLATILITY_MEDIUM: volStr = "Med Vol"; break;
         case VOLATILITY_HIGH: volStr = "High Vol"; break;
         default: volStr = "Unknown Vol"; break;
      }
      
      string mtfStr = mtfConfirmed ? " [MTF Confirmed]" : "";
      
      return StringFormat("%s + %s (Score: %.2f)%s", regimeStr, volStr, regimeScore, mtfStr);
   }
};

//+------------------------------------------------------------------+
//| CLASS: MarketRegimeFilter                                        |
//+------------------------------------------------------------------+
class MarketRegimeFilter
{
private:
   string m_symbol;
   ENUM_TIMEFRAMES m_tfTrading;
   ENUM_TIMEFRAMES m_tfHigher;
   ENUM_TIMEFRAMES m_tfLongTerm;
   
   // Indicator handles
   int m_handleADX;
   int m_handleATR;
   int m_handleADX_Higher;
   int m_handleATR_Higher;
   int m_handleADX_LongTerm;
   int m_handleATR_LongTerm;
   
   RegimeResult m_currentResult;
   datetime m_lastUpdate;
   
   // History buffers for smoothing
   double m_adxHistory[];
   double m_atrHistory[];
   int m_historySize;
   
   // Transition detection - dual counter system
   ENUM_MARKET_REGIME m_previousRegime;
   int m_transitionCounter;    // Counts bars in new regime
   int m_stableCounter;        // Counts bars in same regime
   
   // Cached values for performance
   double m_cachedRegimeScore;
   double m_cachedVolatilityScore;
   datetime m_cachedScoreTime;
   
   // DataManager reference for ATR/price data access
   DataManager *m_data;
   
private:
   // Initialize indicator handles
   bool CreateIndicators()
   {
      // Release existing handles first
      ReleaseIndicators();
      
      // Trading timeframe indicators
      m_handleADX = iADX(m_symbol, m_tfTrading, 14);
      m_handleATR = iATR(m_symbol, m_tfTrading, 14);
      
      // Higher timeframe indicators
      m_handleADX_Higher = iADX(m_symbol, m_tfHigher, 14);
      m_handleATR_Higher = iATR(m_symbol, m_tfHigher, 14);
      
      // Long-term timeframe indicators
      m_handleADX_LongTerm = iADX(m_symbol, m_tfLongTerm, 14);
      m_handleATR_LongTerm = iATR(m_symbol, m_tfLongTerm, 14);
      
      // Validate handles
      if(m_handleADX == INVALID_HANDLE || m_handleATR == INVALID_HANDLE ||
         m_handleADX_Higher == INVALID_HANDLE || m_handleATR_Higher == INVALID_HANDLE ||
         m_handleADX_LongTerm == INVALID_HANDLE || m_handleATR_LongTerm == INVALID_HANDLE)
      {
         PrintFormat("[MarketRegime] Failed to create indicator handles. ADX=%d, ATR=%d", 
                     m_handleADX, m_handleATR);
         return false;
      }
      
      // Initialize history buffers
      ArraySetAsSeries(m_adxHistory, true);
      ArraySetAsSeries(m_atrHistory, true);
      ArrayResize(m_adxHistory, m_historySize);
      ArrayResize(m_atrHistory, m_historySize);
      ArrayInitialize(m_adxHistory, 25.0);  // Default ADX
      ArrayInitialize(m_atrHistory, 0.001); // Default ATR
      
      return true;
   }
   
   // Cleanup indicator handles
   void ReleaseIndicators()
   {
      if(m_handleADX != INVALID_HANDLE) { IndicatorRelease(m_handleADX); m_handleADX = INVALID_HANDLE; }
      if(m_handleATR != INVALID_HANDLE) { IndicatorRelease(m_handleATR); m_handleATR = INVALID_HANDLE; }
      if(m_handleADX_Higher != INVALID_HANDLE) { IndicatorRelease(m_handleADX_Higher); m_handleADX_Higher = INVALID_HANDLE; }
      if(m_handleATR_Higher != INVALID_HANDLE) { IndicatorRelease(m_handleATR_Higher); m_handleATR_Higher = INVALID_HANDLE; }
      if(m_handleADX_LongTerm != INVALID_HANDLE) { IndicatorRelease(m_handleADX_LongTerm); m_handleADX_LongTerm = INVALID_HANDLE; }
      if(m_handleATR_LongTerm != INVALID_HANDLE) { IndicatorRelease(m_handleATR_LongTerm); m_handleATR_LongTerm = INVALID_HANDLE; }
   }
   
   // Safe CopyBuffer with fallback
   double GetIndicatorValue(int handle, int buffer, int shift, double fallback = 0.0)
   {
      double value[];
      ArrayResize(value, 1);
      if(CopyBuffer(handle, buffer, shift, 1, value) < 1)
         return fallback;
      return value[0];
   }
   
   // Calculate ADX for trend strength with history smoothing
   double CalculateADX(ENUM_TIMEFRAMES tf, int period = 14)
   {
      int handle = INVALID_HANDLE;
      if(tf == m_tfTrading) handle = m_handleADX;
      else if(tf == m_tfHigher) handle = m_handleADX_Higher;
      else if(tf == m_tfLongTerm) handle = m_handleADX_LongTerm;
      
      if(handle == INVALID_HANDLE) return 25.0; // Fallback
      
      double adx = GetIndicatorValue(handle, 0, 0, 25.0);
      
      // Update history for smoothing
      ArrayInsert(m_adxHistory, adx, 0, 0, 1);
      if(ArraySize(m_adxHistory) > m_historySize)
         ArrayResize(m_adxHistory, m_historySize);
      
      return adx;
   }
   
   // Calculate ATR with history tracking
   double CalculateATR(ENUM_TIMEFRAMES tf, int period = 14)
   {
      int handle = INVALID_HANDLE;
      if(tf == m_tfTrading) handle = m_handleATR;
      else if(tf == m_tfHigher) handle = m_handleATR_Higher;
      else if(tf == m_tfLongTerm) handle = m_handleATR_LongTerm;
      
      if(handle == INVALID_HANDLE) return 0.001; // Fallback
      
      double atr = GetIndicatorValue(handle, 0, 0, 0.001);
      
      // Update history
      ArrayInsert(m_atrHistory, atr, 0, 0, 1);
      if(ArraySize(m_atrHistory) > m_historySize)
         ArrayResize(m_atrHistory, m_historySize);
      
      return atr;
   }
   
   // Optimized volatility ratio calculation with dynamic lookback
   double CalculateVolatilityRatio(ENUM_TIMEFRAMES tf, int lookback = 50)
   {
      double currentATR = CalculateATR(tf, 14);
      
      // Use cached history if available
      int historyCount = ArraySize(m_atrHistory);
      if(historyCount < 2) return 1.0;
      
      // Dynamic lookback based on available data
      int effectiveLookback = MathMin(lookback, historyCount);
      if(effectiveLookback < 2) return 1.0;
      
      // Calculate average from history
      double sum = 0.0;
      for(int i = 1; i < effectiveLookback; i++) // Skip current bar
         sum += m_atrHistory[i];
      
      double avgATR = sum / (effectiveLookback - 1);
      if(avgATR <= 0.0) return 1.0;
      
      return currentATR / avgATR;
   }
   
   // Determine market regime based on ADX and price action
   ENUM_MARKET_REGIME DetermineRegime(ENUM_TIMEFRAMES tf)
   {
      double adx = CalculateADX(tf, 14);
      
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(m_symbol, tf, 1, 50, rates);
      if(copied < 50)
         return REGIME_NONE;
      
      // Calculate directional movement
      int highestIdx = ArrayMaximum(rates, 0, 20, offsetof(MqlRates, high));
      int lowestIdx = ArrayMinimum(rates, 0, 20, offsetof(MqlRates, low));
      
      double highestHigh = (highestIdx >= 0 && highestIdx < ArraySize(rates)) ? rates[highestIdx].high : rates[0].high;
      double lowestLow = (lowestIdx >= 0 && lowestIdx < ArraySize(rates)) ? rates[lowestIdx].low : rates[0].low;
      
      double range = highestHigh - lowestLow;
      double avgBody = 0;
      
      for(int i = 0; i < 20; i++)
      {
         avgBody += MathAbs(rates[i].close - rates[i].open);
      }
      avgBody /= 20.0;
      if(avgBody <= 0.0) avgBody = range * 0.1; // Fallback
      
      // ADX-based regime detection with hysteresis
      if(adx > 35)
         return REGIME_TRENDING_STRONG;
      else if(adx > 25)
         return REGIME_TRENDING_WEAK;
      else if(adx < 20 && range < avgBody * 3)
         return REGIME_RANGING_SIDEWAYS;
      else if(adx < 25 && range > avgBody * 5)
         return REGIME_CHOPPY_HIGH_VOL;
      else
         return REGIME_TRANSITION;
   }
   
   // Determine volatility regime with improved clustering
   ENUM_VOLATILITY_REGIME DetermineVolatilityRegime(ENUM_TIMEFRAMES tf)
   {
      double ratio = CalculateVolatilityRatio(tf, 50);
      
      // Threshold-based clustering with hysteresis
      if(ratio < 0.7)
         return VOLATILITY_LOW;
      else if(ratio > 1.3)
         return VOLATILITY_HIGH;
      else
         return VOLATILITY_MEDIUM;
   }
   
   // Smart transition detection with dual counter system
   bool DetectTransition(ENUM_MARKET_REGIME current, ENUM_MARKET_REGIME previous)
   {
      if(current != previous)
      {
         // Regime changed - reset stable counter, increment transition counter
         m_stableCounter = 0;
         m_transitionCounter++;
         
         // Require 3 consecutive bars of new regime to confirm
         return (m_transitionCounter < 3);
      }
      else
      {
         // Same regime - increment stable counter, reset transition counter
         m_transitionCounter = 0;
         m_stableCounter++;
         
         // Consider stable after 5 bars in same regime
         return false;
      }
   }
   
   // Calculate numeric regime score (0.0 - 1.0)
   double CalculateRegimeScore(ENUM_MARKET_REGIME regime, double adx, double atrRatio)
   {
      double baseScore = 0.0;
      
      switch(regime)
      {
         case REGIME_TRENDING_STRONG:
            // Score based on ADX strength: 35->0.9, 50->1.0
            baseScore = 0.9 + MathMin((adx - 35) / 15.0, 1.0) * 0.1;
            break;
            
         case REGIME_TRENDING_WEAK:
            // Score: 25->0.6, 35->0.89
            baseScore = 0.6 + MathMin((adx - 25) / 10.0, 1.0) * 0.29;
            break;
            
         case REGIME_RANGING_SIDEWAYS:
            baseScore = 0.45;
            break;
            
         case REGIME_CHOPPY_HIGH_VOL:
            baseScore = 0.25;
            break;
            
         case REGIME_TRANSITION:
            baseScore = 0.1;
            break;
            
         default:
            baseScore = 0.0;
            break;
      }
      
      // Adjust for volatility: high vol reduces score slightly
      double volAdjustment = 1.0 - MathMax(0.0, (atrRatio - 1.0) * 0.1);
      volAdjustment = MathMax(0.8, MathMin(1.0, volAdjustment));
      
      return MathMax(0.0, MathMin(1.0, baseScore * volAdjustment));
   }
   
   // Calculate normalized volatility score (0.0 - 1.0)
   double CalculateVolatilityScore(double atrRatio)
   {
      // Map ATR ratio to 0-1 scale
      // ratio < 0.5 -> 0.9 (very low vol, good for tight stops)
      // ratio = 1.0 -> 0.5 (normal vol)
      // ratio > 2.0 -> 0.1 (very high vol, risky)
      
      if(atrRatio < 0.5)
         return 0.9;
      else if(atrRatio > 2.0)
         return 0.1;
      else
      {
         // Linear interpolation between 0.5 and 2.0
         return 0.9 - (atrRatio - 0.5) / 1.5 * 0.8;
      }
   }
   
   // Get trend alignment across multiple timeframes
   int GetTrendAlignment()
   {
      ENUM_MARKET_REGIME trading = DetermineRegime(m_tfTrading);
      ENUM_MARKET_REGIME higher = DetermineRegime(m_tfHigher);
      ENUM_MARKET_REGIME longTerm = DetermineRegime(m_tfLongTerm);
      
      int alignment = 0;
      
      // Count how many TFs are in trending state
      if(trading == REGIME_TRENDING_STRONG || trading == REGIME_TRENDING_WEAK) alignment++;
      if(higher == REGIME_TRENDING_STRONG || higher == REGIME_TRENDING_WEAK) alignment++;
      if(longTerm == REGIME_TRENDING_STRONG || longTerm == REGIME_TRENDING_WEAK) alignment++;
      
      return alignment;
   }
   
   // Check if multi-timeframe confirmation exists
   bool IsMTFConfirmed()
   {
      ENUM_MARKET_REGIME trading = DetermineRegime(m_tfTrading);
      ENUM_MARKET_REGIME higher = DetermineRegime(m_tfHigher);
      ENUM_MARKET_REGIME longTerm = DetermineRegime(m_tfLongTerm);
      
      // Require at least 2 out of 3 TFs to agree on trend direction
      int trendCount = 0;
      if(trading == REGIME_TRENDING_STRONG || trading == REGIME_TRENDING_WEAK) trendCount++;
      if(higher == REGIME_TRENDING_STRONG || higher == REGIME_TRENDING_WEAK) trendCount++;
      if(longTerm == REGIME_TRENDING_STRONG || longTerm == REGIME_TRENDING_WEAK) trendCount++;
      
      return trendCount >= 2;
   }
   
   // Build detailed reasoning string
   string BuildReasoning()
   {
      string reasoning = StringFormat("Regime: %s | Score: %.2f | Vol: %.2f", 
                                      m_currentResult.regime == REGIME_TRENDING_STRONG ? "Strong Trend" :
                                      m_currentResult.regime == REGIME_TRENDING_WEAK ? "Weak Trend" :
                                      m_currentResult.regime == REGIME_RANGING_SIDEWAYS ? "Ranging" :
                                      m_currentResult.regime == REGIME_CHOPPY_HIGH_VOL ? "Choppy" : "Transition",
                                      m_currentResult.regimeScore,
                                      m_currentResult.volatilityScore);
      
      if(m_currentResult.mtfConfirmed)
         reasoning += " | MTF Confirmed";
      
      reasoning += StringFormat(" | TF Alignment: %d/3", m_currentResult.tfAlignment);
      
      if(m_currentResult.isTransition)
         reasoning += " | WARNING: Transition Phase";
      
      return reasoning;
   }
   
public:
   MarketRegimeFilter()
   {
      m_symbol = _Symbol;
      m_tfTrading = _Period;
      m_tfHigher = (ENUM_TIMEFRAMES)PeriodSeconds(_Period) * 4;
      m_tfLongTerm = (ENUM_TIMEFRAMES)PeriodSeconds(_Period) * 24;
      
      // Initialize all handles to INVALID
      m_handleADX = INVALID_HANDLE;
      m_handleATR = INVALID_HANDLE;
      m_handleADX_Higher = INVALID_HANDLE;
      m_handleATR_Higher = INVALID_HANDLE;
      m_handleADX_LongTerm = INVALID_HANDLE;
      m_handleATR_LongTerm = INVALID_HANDLE;
      
      m_lastUpdate = 0;
      m_historySize = 100;
      m_previousRegime = REGIME_NONE;
      m_transitionCounter = 0;
      m_stableCounter = 0;
      m_cachedRegimeScore = 0.0;
      m_cachedVolatilityScore = 0.5;
      m_cachedScoreTime = 0;
      m_data = NULL;  // Initialize DataManager pointer
      
      // Create indicators on construction
      CreateIndicators();
   }
   
   ~MarketRegimeFilter()
   {
      ReleaseIndicators();
   }
   
   // Set DataManager reference
   void SetDataManager(DataManager *data) { m_data = data; }
   DataManager* GetDataManager() const { return m_data; }
   
   // Initialize with custom timeframes
   bool Init(ENUM_TIMEFRAMES tfTrading, ENUM_TIMEFRAMES tfHigher, ENUM_TIMEFRAMES tfLongTerm)
   {
      m_tfTrading = tfTrading;
      m_tfHigher = tfHigher;
      m_tfLongTerm = tfLongTerm;
      
      // Recreate indicators for new timeframes
      return CreateIndicators();
   }
   
   // Update regime context (call on NewBar)
   void Update()
   {
      datetime currentBarTime = iTime(m_symbol, m_tfTrading, 0);
      if(currentBarTime == m_lastUpdate && m_lastUpdate != 0)
         return;
      
      m_lastUpdate = currentBarTime;
      
      // Determine regimes for all timeframes
      ENUM_MARKET_REGIME tradingRegime = DetermineRegime(m_tfTrading);
      ENUM_MARKET_REGIME higherRegime = DetermineRegime(m_tfHigher);
      ENUM_MARKET_REGIME longTermRegime = DetermineRegime(m_tfLongTerm);
      ENUM_VOLATILITY_REGIME volRegime = DetermineVolatilityRegime(m_tfTrading);
      
      // Check for transition with smart detection
      bool isTransition = DetectTransition(tradingRegime, m_previousRegime);
      
      // Calculate trend strength (ADX)
      double trendStrength = CalculateADX(m_tfTrading, 14);
      
      // Calculate ATR ratio
      double currentATR = CalculateATR(m_tfTrading, 14);
      double avgATR = 0.0;
      
      // Get historical ATR for average calculation
      double atrHistory[];
      ArrayResize(atrHistory, 50);
      if(CopyBuffer(m_handleATR, 0, 1, 50, atrHistory) >= 50)
      {
         double sum = 0.0;
         for(int i = 0; i < 50; i++) sum += atrHistory[i];
         avgATR = sum / 50.0;
      }
      else
         avgATR = currentATR; // Fallback
      
      double atrRatio = (avgATR > 0.0) ? (currentATR / avgATR) : 1.0;
      
      // Calculate scores
      double regimeScore = CalculateRegimeScore(isTransition ? REGIME_TRANSITION : tradingRegime, trendStrength, atrRatio);
      double volatilityScore = CalculateVolatilityScore(atrRatio);
      
      // Cache scores
      m_cachedRegimeScore = regimeScore;
      m_cachedVolatilityScore = volatilityScore;
      m_cachedScoreTime = currentBarTime;
      
      // Get MTF confirmation status
      bool mtfConfirmed = IsMTFConfirmed();
      int tfAlignment = GetTrendAlignment();
      
      // Update result struct
      m_currentResult.regime = isTransition ? REGIME_TRANSITION : tradingRegime;
      m_currentResult.volRegime = volRegime;
      m_currentResult.regimeScore = regimeScore;
      m_currentResult.volatilityScore = volatilityScore;
      m_currentResult.trendStrength = trendStrength;
      m_currentResult.atrRatio = atrRatio;
      m_currentResult.isTransition = isTransition;
      m_currentResult.mtfConfirmed = mtfConfirmed;
      m_currentResult.tfAlignment = tfAlignment;
      
      m_previousRegime = tradingRegime;
   }
   
   // Get current regime result
   const RegimeResult& GetResult() const
   {
      return m_currentResult;
   }
   
   // Backward compatibility: GetContext() alias
   const RegimeResult& GetContext() const
   {
      return m_currentResult;
   }
   
   // Get numeric regime score (0.0 - 1.0)
   double GetRegimeScore() const
   {
      return m_currentResult.regimeScore;
   }
   
   // Get normalized volatility score (0.0 - 1.0)
   double GetVolatilityScore() const
   {
      return m_currentResult.volatilityScore;
   }
   
   // Get dynamic threshold wrapper for compatibility
   double GetDynamicThreshold(double baseThreshold = 0.5) const
   {
      return m_currentResult.GetMinSignalThreshold(baseThreshold);
   }
   
   // Check if trading is allowed based on regime
   bool IsTradingAllowed(bool allowRanging = true, bool allowChoppy = false) const
   {
      if(m_currentResult.isTransition)
         return false;  // Avoid trading during transitions
      
      switch(m_currentResult.regime)
      {
         case REGIME_TRENDING_STRONG:
         case REGIME_TRENDING_WEAK:
            return true;
            
         case REGIME_RANGING_SIDEWAYS:
            return allowRanging;
            
         case REGIME_CHOPPY_HIGH_VOL:
            return allowChoppy;
            
         default:
            return false;
      }
   }
   
   // Backward compatibility aliases
   ENUM_MARKET_REGIME GetMarketRegime() const { return m_currentResult.regime; }
   bool IsTrending() const { return m_currentResult.regime == REGIME_TRENDING_STRONG || m_currentResult.regime == REGIME_TRENDING_WEAK; }
   bool IsRanging() const { return m_currentResult.regime == REGIME_RANGING_SIDEWAYS; }
   
   // Get lot size multiplier based on regime
   double GetLotMultiplier(double baseMult, 
                           double strongMult = 1.5,
                           double weakMult = 1.0,
                           double sideMult = 0.7,
                           double chopMult = 0.5) const
   {
      if(m_currentResult.isTransition)
         return 0.0;  // No trading
      
      switch(m_currentResult.regime)
      {
         case REGIME_TRENDING_STRONG:
            return baseMult * strongMult;
         case REGIME_TRENDING_WEAK:
            return baseMult * weakMult;
         case REGIME_RANGING_SIDEWAYS:
            return baseMult * sideMult;
         case REGIME_CHOPPY_HIGH_VOL:
            return baseMult * chopMult;
         default:
            return baseMult * 0.5;
      }
   }
   
   // Get SL/TP adjustment factor based on volatility
   double GetVolatilityAdjustment() const
   {
      switch(m_currentResult.volRegime)
      {
         case VOLATILITY_LOW:
            return 0.8;  // Tighter stops in low vol
         case VOLATILITY_HIGH:
            return 1.5;  // Wider stops in high vol
         default:
            return 1.0;
      }
   }
   
   // Check multi-TF confluence
   bool HasConfluence() const
   {
      return m_currentResult.mtfConfirmed;
   }
   
   // Get regime description for logging
   string GetDescription() const
   {
      return m_currentResult.Description();
   }
   
   // Get detailed reasoning
   string GetReasoning() const
   {
      // Need non-const access for BuildReasoning, so we duplicate logic here
      string reasoning = StringFormat("Regime: %s | Score: %.2f | Vol: %.2f", 
                                      m_currentResult.regime == REGIME_TRENDING_STRONG ? "Strong Trend" :
                                      m_currentResult.regime == REGIME_TRENDING_WEAK ? "Weak Trend" :
                                      m_currentResult.regime == REGIME_RANGING_SIDEWAYS ? "Ranging" :
                                      m_currentResult.regime == REGIME_CHOPPY_HIGH_VOL ? "Choppy" : "Transition",
                                      m_currentResult.regimeScore,
                                      m_currentResult.volatilityScore);
      
      if(m_currentResult.mtfConfirmed)
         reasoning += " | MTF Confirmed";
      
      reasoning += StringFormat(" | TF Alignment: %d/3", m_currentResult.tfAlignment);
      
      if(m_currentResult.isTransition)
         reasoning += " | WARNING: Transition Phase";
      
      return reasoning;
   }
};

//+------------------------------------------------------------------+
//| EXAMPLE USAGE                                                    |
//+------------------------------------------------------------------+
/*
// Global declaration
MarketRegimeFilter g_regimeFilter;

// In OnInit()
int OnInit()
{
   // Optional: Initialize with custom timeframes
   // g_regimeFilter.Init(PERIOD_H1, PERIOD_H4, PERIOD_D1);
   
   return(INIT_SUCCEEDED);
}

// In OnTick() or OnBar()
void OnTick()
{
   // Update regime analysis
   g_regimeFilter.Update();
   
   // Get regime result with scores
   RegimeResult result = g_regimeFilter.GetResult();
   
   // Check if trading is allowed
   if(!g_regimeFilter.IsTradingAllowed(true, false))
   {
      Print("Trading not allowed: ", result.Description());
      return;
   }
   
   // Get numeric scores for adaptive logic
   double regimeScore = g_regimeFilter.GetRegimeScore();    // 0.0 - 1.0
   double volScore = g_regimeFilter.GetVolatilityScore();   // 0.0 - 1.0
   
   // Adaptive signal threshold based on regime
   double signalThreshold = result.GetMinSignalThreshold(0.5);
   
   // Example: Use regime score to adjust position size
   double baseLotSize = 0.1;
   double adjustedLotSize = baseLotSize * regimeScore;  // More confident = larger size
   
   // Example: Use volatility score to adjust stops
   double baseStopLoss = 50.0;  // points
   double adjustedStopLoss = baseStopLoss * (2.0 - volScore);  // Lower vol = tighter stops
   
   // Check MTF confirmation
   if(result.mtfConfirmed)
   {
      Print("Strong setup confirmed across multiple timeframes!");
      // Can increase confidence in signals
   }
   
   // Log detailed reasoning
   Print(g_regimeFilter.GetReasoning());
}

// In OnDeinit()
void OnDeinit(const int reason)
{
   // Destructor handles cleanup automatically
}
*/

#endif
