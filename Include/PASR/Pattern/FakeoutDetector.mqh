//+------------------------------------------------------------------+
//|  Pattern/FakeoutDetector.mqh                                     |
//|  PASR Framework — Fakeout / SL-Hunt Detection Layer              |
//|  Detects fake stop-out events and provides re-entry signals.     |
//|  Depends: PatternTypes only (no evaluator or scorer deps)        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property strict

#ifndef __FAKEOUT_DETECTOR_MQH__
#define __FAKEOUT_DETECTOR_MQH__

#include "PatternTypes.mqh"

class FakeoutDetector
{
public:
   //--- Input context passed by caller --------------------------------
   struct Context
   {
      ulong     originalTicket;
      int       direction;
      double    slHitPrice;
      double    entryPrice;
      double    atrPoints;
      double    slMultiplier;
      MqlTick   currentTick;
      MqlRates  rates[];      // rates[0] = latest closed bar
   };

   //-------------------------------------------------------------------
   //  Detect — returns true when the stop-out looks like a fakeout    |
   //                                                                   |
   //  Severity levels:                                                 |
   //    1 = shallow penetration only                                   |
   //    2 = shallow + body reversal on the same candle                 |
   //-------------------------------------------------------------------
   static bool Detect(const Context &ctx, FakeoutResult &result)
   {
      result.detected   = false;
      result.level      = 0;
      result.confidence = 0.0;
      result.reason     = "";

      double maxOvershoot = ctx.atrPoints * ctx.slMultiplier * _Point;
      double penetration  = (ctx.direction == 1)
                            ? (ctx.slHitPrice - ctx.currentTick.bid)
                            : (ctx.currentTick.ask - ctx.slHitPrice);

      // Penetration deeper than 1×SL_mult×ATR → genuine momentum break
      if (penetration > maxOvershoot)
      {
         result.reason = StringFormat(
            "Momentum Breakout | penetration %.1f pts > max %.1f pts",
            penetration / _Point, maxOvershoot / _Point);
         return false;
      }

      // Body reversal check on the candle that breached SL
      bool bodyReversal = (ctx.direction == 1)
                          ? (ctx.rates[0].close > ctx.rates[0].open)
                          : (ctx.rates[0].close < ctx.rates[0].open);

      if (bodyReversal) result.level = 2;

      result.detected   = (penetration > 0 && bodyReversal);
      result.confidence = 0.5 + (bodyReversal ? 0.3 : 0.0);
      result.reason = StringFormat(
         "Fakeout Level %d | Penetration: %.1f pts | BodyReversal: %s",
         result.level, penetration / _Point, bodyReversal ? "YES" : "NO");

      return result.detected;
   }
};

#endif // __FAKEOUT_DETECTOR_MQH__
