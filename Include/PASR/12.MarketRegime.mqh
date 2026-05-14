//+------------------------------------------------------------------+
//|                                             12.MarketRegime.mqh |
//|                                       Copyright 2026, Agsicentre |
//|            Multi-Timeframe Market Regime & Volatility Filter     |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "1.00"
#property strict

#ifndef __MARKET_REGIME_MQH__
#define __MARKET_REGIME_MQH__

#include "IManager.mqh"
#include "10.DataManager.mqh"

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
//| STRUCT: Multi-TF Regime Context                                  |
//+------------------------------------------------------------------+
struct MultiTFRegimeContext
{
   ENUM_MARKET_REGIME tradingTF;    // TF Trading (e.g., 1H)
   ENUM_MARKET_REGIME higherTF;     // TF Tinggi (e.g., 4H)
   ENUM_MARKET_REGIME longTermTF;   // TF Panjang (e.g., D1)
   ENUM_VOLATILITY_REGIME volRegime;
   
   double trendStrength;            // ADX or similar
   double atrRatio;                 // Current ATR / Average ATR
   bool isTransition;               // True if regime changing
   
   string Description() const
   {
      string regimeStr = "";
      switch(tradingTF)
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
      
      return StringFormat("%s + %s", regimeStr, volStr);
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
   
   MultiTFRegimeContext m_currentContext;
   datetime m_lastUpdate;
   int m_updateIntervalBars;
   
   // ADX calculation buffers
   double m_adxBuffer[];
   double m_plusDIBuffer[];
   double m_minusDIBuffer[];
   
   // ATR history for volatility clustering
   double m_atrHistory[];
   int m_atrHistorySize;
   
   // Transition detection
   ENUM_MARKET_REGIME m_previousRegime;
   int m_transitionCounter;
   
private:
   // Calculate ADX for trend strength
   double CalculateADX(ENUM_TIMEFRAMES tf, int period = 14)
   {
      ArrayResize(m_adxBuffer, 0);
      if (CopyIndicator(handleADX, 0, 0, period, m_adxBuffer) < period)
         return 0.0;
      return m_adxBuffer[0];
   }
   
   // Determine market regime based on ADX and price action
   ENUM_MARKET_REGIME DetermineRegime(ENUM_TIMEFRAMES tf)
   {
      double adx = CalculateADX(tf, 14);
      
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if (CopyRates(m_symbol, tf, 1, 50, rates) < 50)
         return REGIME_NONE;
      
      // Calculate directional movement
      double highestHigh = rates[ArrayMaximum(rates, 0, 20, offsetof(MqlRates, high))].high;
      double lowestLow = rates[ArrayMinimum(rates, 0, 20, offsetof(MqlRates, low))].low;
      double range = highestHigh - lowestLow;
      double avgBody = 0;
      
      for (int i = 0; i < 20; i++)
      {
         avgBody += MathAbs(rates[i].close - rates[i].open);
      }
      avgBody /= 20.0;
      
      // ADX-based regime detection
      if (adx > 35)
         return REGIME_TRENDING_STRONG;
      else if (adx > 25)
         return REGIME_TRENDING_WEAK;
      else if (adx < 20 && range < avgBody * 3)
         return REGIME_RANGING_SIDEWAYS;
      else if (adx < 25 && range > avgBody * 5)
         return REGIME_CHOPPY_HIGH_VOL;
      else
         return REGIME_TRANSITION;
   }
   
   // Determine volatility regime using K-Means-like clustering on ATR
   ENUM_VOLATILITY_REGIME DetermineVolatilityRegime(ENUM_TIMEFRAMES tf)
   {
      double atrValues[];
      ArraySetAsSeries(atrValues, true);
      
      // Get 100 ATR values for statistical analysis
      if (CopyATR(tf, 100, atrValues) < 100)
         return VOLATILITY_MEDIUM;
      
      // Calculate mean and standard deviation
      double sum = 0.0;
      for (int i = 0; i < 100; i++)
         sum += atrValues[i];
      double mean = sum / 100.0;
      
      double variance = 0.0;
      for (int i = 0; i < 100; i++)
      {
         double diff = atrValues[i] - mean;
         variance += diff * diff;
      }
      variance /= 100.0;
      double stdDev = MathSqrt(variance);
      
      // Current ATR ratio
      double currentATR = atrValues[0];
      double ratio = currentATR / mean;
      
      // Simple threshold-based clustering (can be enhanced with K-Means)
      if (ratio < 0.7)
         return VOLATILITY_LOW;
      else if (ratio > 1.3)
         return VOLATILITY_HIGH;
      else
         return VOLATILITY_MEDIUM;
   }
   
   // Detect regime transition
   bool DetectTransition(ENUM_MARKET_REGIME current, ENUM_MARKET_REGIME previous)
   {
      if (current != previous)
      {
         m_transitionCounter++;
         // Require 2-3 consecutive bars of new regime to confirm
         return (m_transitionCounter < 3);
      }
      else
      {
         m_transitionCounter = 0;
         return false;
      }
   }
   
public:
   MarketRegimeFilter() : m_lastUpdate(0),
                          m_updateIntervalBars(1),
                          m_atrHistorySize(100),
                          m_previousRegime(REGIME_NONE),
                          m_transitionCounter(0)
   {
      m_symbol = _Symbol;
      m_tfTrading = _Period;
      m_tfHigher = (ENUM_TIMEFRAMES)PeriodSeconds(_Period) * 4;
      m_tfLongTerm = (ENUM_TIMEFRAMES)PeriodSeconds(_Period) * 24;
      
      ArraySetAsSeries(m_adxBuffer, true);
      ArraySetAsSeries(m_atrHistory, true);
   }
   
   // Initialize with custom timeframes
   void Init(ENUM_TIMEFRAMES tfTrading, ENUM_TIMEFRAMES tfHigher, ENUM_TIMEFRAMES tfLongTerm)
   {
      m_tfTrading = tfTrading;
      m_tfHigher = tfHigher;
      m_tfLongTerm = tfLongTerm;
   }
   
   // Update regime context (call on NewBar)
   void Update()
   {
      datetime currentBarTime = iTime(m_symbol, m_tfTrading, 0);
      if (currentBarTime == m_lastUpdate)
         return;
      
      m_lastUpdate = currentBarTime;
      
      // Determine regimes for all timeframes
      ENUM_MARKET_REGIME tradingRegime = DetermineRegime(m_tfTrading);
      ENUM_MARKET_REGIME higherRegime = DetermineRegime(m_tfHigher);
      ENUM_MARKET_REGIME longTermRegime = DetermineRegime(m_tfLongTerm);
      ENUM_VOLATILITY_REGIME volRegime = DetermineVolatilityRegime(m_tfTrading);
      
      // Check for transition
      bool isTransition = DetectTransition(tradingRegime, m_previousRegime);
      
      // Calculate trend strength (ADX)
      double trendStrength = CalculateADX(m_tfTrading, 14);
      
      // Calculate ATR ratio
      double currentATR = iATR(m_symbol, m_tfTrading, 14, 0);
      double avgATR = iATR(m_symbol, m_tfTrading, 14, 50);
      double atrRatio = (avgATR > 0) ? (currentATR / avgATR) : 1.0;
      
      // Update context
      m_currentContext.tradingTF = isTransition ? REGIME_TRANSITION : tradingRegime;
      m_currentContext.higherTF = higherRegime;
      m_currentContext.longTermTF = longTermRegime;
      m_currentContext.volRegime = volRegime;
      m_currentContext.trendStrength = trendStrength;
      m_currentContext.atrRatio = atrRatio;
      m_currentContext.isTransition = isTransition;
      
      m_previousRegime = tradingRegime;
   }
   
   // Get current regime context
   const MultiTFRegimeContext& GetContext() const
   {
      return m_currentContext;
   }
   
   // Check if trading is allowed based on regime
   bool IsTradingAllowed(bool allowRanging = true, bool allowChoppy = false) const
   {
      if (m_currentContext.isTransition)
         return false;  // Avoid trading during transitions
      
      switch (m_currentContext.tradingTF)
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
   
   // Get lot size multiplier based on regime
   double GetLotMultiplier(double baseMult, 
                           double strongMult = 1.5,
                           double weakMult = 1.0,
                           double sideMult = 0.7,
                           double chopMult = 0.5) const
   {
      if (m_currentContext.isTransition)
         return 0.0;  // No trading
      
      switch (m_currentContext.tradingTF)
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
      switch (m_currentContext.volRegime)
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
      // Strong confluence: all TFs agree
      if (m_currentContext.tradingTF == m_currentContext.higherTF &&
          m_currentContext.higherTF == m_currentContext.longTermTF)
         return true;
      
      // Moderate confluence: trading TF aligns with at least one higher TF
      if (m_currentContext.tradingTF == m_currentContext.higherTF ||
          m_currentContext.tradingTF == m_currentContext.longTermTF)
         return true;
      
      return false;
   }
   
   // Get regime description for logging
   string GetDescription() const
   {
      return m_currentContext.Description();
   }
};

#endif
