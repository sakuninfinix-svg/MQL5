//+------------------------------------------------------------------+
//| Data/RegimeTypes.mqh — v1.01                                     |
//| Canonical type definitions for PASR Market Regime system          |
//+------------------------------------------------------------------+
#property strict
#ifndef REGIME_TYPES_MQH
#define REGIME_TYPES_MQH

enum EMarketRegime
  {
   REGIME_UNKNOWN       = 0,
   REGIME_TREND_UP      = 1,
   REGIME_TREND_DOWN    = 2,
   REGIME_RANGE         = 3,
   REGIME_VOLATILE      = 4,
   REGIME_TRANSITION    = 5,
   REGIME_CRASH         = 6,
   REGIME_SQUEEZE       = 7
  };

string MarketRegimeName(EMarketRegime regime)
  {
   switch(regime)
     {
      case REGIME_TREND_UP:    return "TREND_UP";
      case REGIME_TREND_DOWN:  return "TREND_DOWN";
      case REGIME_RANGE:       return "RANGE";
      case REGIME_VOLATILE:    return "VOLATILE";
      case REGIME_TRANSITION:  return "TRANSITION";
      case REGIME_CRASH:       return "CRASH";
      case REGIME_SQUEEZE:     return "SQUEEZE";
      default:                 return "UNKNOWN";
     }
  }

struct SRegimeSnapshot
  {
   EMarketRegime   regime;
   double          confidence;
   datetime        lastUpdate;
   int             durationBars;
   double          trendStrength;
   double          volatilityLevel;
   double          adxValue;
   double          atrRatio;

   void Init()
     {
      regime          = REGIME_UNKNOWN;
      confidence      = 0.0;
      lastUpdate      = TimeCurrent();
      durationBars    = 0;
      trendStrength   = 0.0;
      volatilityLevel = 0.0;
      adxValue        = 0.0;
      atrRatio        = 0.0;
     }

   string ToString() const
     {
      return MarketRegimeName(regime);
     }
  };

#endif // REGIME_TYPES_MQH
