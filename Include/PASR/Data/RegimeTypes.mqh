//+------------------------------------------------------------------+
//|                                              RegimeTypes.mqh     |
//|                                  Copyright 2024, PASR System     |
//|                                             https://pasr.ai      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, PASR System"
#property link      "https://pasr.ai"
#property version   "1.00"
#property description "Centralized type definitions for Market Regime system"

// Prevent multiple inclusion
#ifndef REGIME_TYPES_MQH
#define REGIME_TYPES_MQH

//+------------------------------------------------------------------+
//| Market Regime Enumeration                                        |
//+------------------------------------------------------------------+
enum EMarketRegime
{
   REGIME_UNKNOWN       = 0,  // Unknown/Initializing
   REGIME_TREND_UP      = 1,  // Strong bullish trend
   REGIME_TREND_DOWN    = 2,  // Strong bearish trend
   REGIME_RANGE         = 3,  // Sideways/ranging market
   REGIME_VOLATILE      = 4,  // High volatility/noisy
   REGIME_TRANSITION    = 5,  // Changing between regimes
   REGIME_CRASH         = 6   // Extreme crash/spike event
};

//+------------------------------------------------------------------+
//| Regime Snapshot Structure                                        |
//+------------------------------------------------------------------+
struct SRegimeSnapshot
{
   EMarketRegime   regime;           // Current regime
   double          confidence;       // Confidence score (0.0-1.0)
   datetime        lastUpdate;       // Last update time
   int             durationBars;     // Duration in bars
   double          trendStrength;    // Trend strength indicator
   double          volatilityLevel;  // Normalized volatility
   double          adxValue;         // ADX value
   double          atrRatio;         // ATR ratio
   
   // Constructor
   void Init()
   {
      regime         = REGIME_UNKNOWN;
      confidence     = 0.0;
      lastUpdate     = TimeCurrent();
      durationBars   = 0;
      trendStrength  = 0.0;
      volatilityLevel = 0.0;
      adxValue       = 0.0;
      atrRatio       = 0.0;
   }
   
   // Get regime name as string
   string ToString() const
   {
      switch(regime)
      {
         case REGIME_TREND_UP:    return "TREND_UP";
         case REGIME_TREND_DOWN:  return "TREND_DOWN";
         case REGIME_RANGE:       return "RANGE";
         case REGIME_VOLATILE:    return "VOLATILE";
         case REGIME_TRANSITION:  return "TRANSITION";
         case REGIME_CRASH:       return "CRASH";
         default:                 return "UNKNOWN";
      }
   }
};

#endif // REGIME_TYPES_MQH
