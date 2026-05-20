//+------------------------------------------------------------------+
//|  Pattern/CandleUtils.mqh                                         |
//|  PASR Framework — Candle Mathematics Layer                       |
//|  Pure static helpers — zero side-effects, zero global state.     |
//|  All functions inline-able by the MQL5 compiler.                 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property strict

#ifndef __CANDLE_UTILS_MQH__
#define __CANDLE_UTILS_MQH__

// No includes needed — operates only on MqlRates and primitive types.

class CandleUtils
{
public:
   //--- Basic OHLC accessors (named for readability at call sites) ----
   static double Open (const MqlRates &r[], int s) { return r[s].open;  }
   static double High (const MqlRates &r[], int s) { return r[s].high;  }
   static double Low  (const MqlRates &r[], int s) { return r[s].low;   }
   static double Close(const MqlRates &r[], int s) { return r[s].close; }

   //--- Derived measurements -----------------------------------------
   static double Range(const MqlRates &r[], int s)
   { return r[s].high - r[s].low; }

   static double Body(const MqlRates &r[], int s)
   { return MathAbs(r[s].close - r[s].open); }

   static double UpperWick(const MqlRates &r[], int s)
   { return r[s].high - MathMax(r[s].open, r[s].close); }

   static double LowerWick(const MqlRates &r[], int s)
   { return MathMin(r[s].open, r[s].close) - r[s].low; }

   //--- Direction predicates -----------------------------------------
   static bool IsBullish(const MqlRates &r[], int s)
   { return r[s].close > r[s].open; }

   static bool IsBearish(const MqlRates &r[], int s)
   { return r[s].close < r[s].open; }

   //--- Structural patterns ------------------------------------------
   // IsInsideBar: child (s) is fully inside mother (s+1)
   static bool IsInsideBar(const MqlRates &r[], int s)
   { return r[s].high < r[s+1].high && r[s].low > r[s+1].low; }

   //--- ATR normalisation --------------------------------------------
   // Returns range expressed as a multiple of ATR price value.
   // Returns 0.0 when atrvalue <= 0 to prevent division-by-zero.
   static double ATRFactor(double rangePrice, double atrvalue)
   {
      double p = atrvalue * _Point;
      return (p <= 0.0) ? 0.0 : rangePrice / p;
   }
};

#endif // __CANDLE_UTILS_MQH__
