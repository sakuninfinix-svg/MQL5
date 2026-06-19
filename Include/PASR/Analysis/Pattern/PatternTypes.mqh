//+------------------------------------------------------------------+
//| Analysis/Pattern/PatternTypes.mqh — v1.00                        |
//| Canonical pattern type definitions for PASR                      |
//| Copyright @2026                                                  |
//| agsicentre.wordpress.com                                         |
//+------------------------------------------------------------------+
#property strict
#ifndef PATTERN_TYPES_MQH
#define PATTERN_TYPES_MQH

#include <PASR/Data/RegimeTypes.mqh>

enum ENUM_PATTERN_TYPE
  {
   PATTERN_NONE                = 0,
   PATTERN_PINBAR              = 1,
   PATTERN_ENGULFING           = 2,
   PATTERN_INSIDE_BAR          = 3,
   PATTERN_INSIDE_BAR_BREAKOUT = 4,
   PATTERN_FAKEY               = 5,
   PATTERN_BOTTOM              = 6,
   PATTERN_DOJI                = 7,
   PATTERN_HARAMI              = 8,
   PATTERN_OUTSIDE_BAR         = 9,
   PATTERN_MORNING_STAR        = 10,
   PATTERN_EVENING_STAR        = 11
  };

// MQL5 typedef aliasing of enum can be brittle in includes.
// Keep legacy name as macro alias for old code.
#define EPatternType ENUM_PATTERN_TYPE

#define PATTERN_PINBAR_BULL   PATTERN_PINBAR
#define PATTERN_PINBAR_BEAR   PATTERN_PINBAR
#define PATTERN_ENGULF_BULL   PATTERN_ENGULFING
#define PATTERN_ENGULF_BEAR   PATTERN_ENGULFING
#define PATTERN_HARAMI_BULL   PATTERN_HARAMI
#define PATTERN_HARAMI_BEAR   PATTERN_HARAMI

string PatternTypeName(const ENUM_PATTERN_TYPE type)
  {
   switch(type)
     {
      case PATTERN_PINBAR:              return "Pinbar";
      case PATTERN_ENGULFING:           return "Engulfing";
      case PATTERN_INSIDE_BAR:          return "Inside Bar";
      case PATTERN_INSIDE_BAR_BREAKOUT: return "Inside Bar Breakout";
      case PATTERN_FAKEY:               return "Fakey";
      case PATTERN_BOTTOM:              return "Tweezer";
      case PATTERN_DOJI:                return "Doji";
      case PATTERN_HARAMI:              return "Harami";
      case PATTERN_OUTSIDE_BAR:         return "Outside Bar";
      case PATTERN_MORNING_STAR:        return "Morning Star";
      case PATTERN_EVENING_STAR:        return "Evening Star";
      default:                          return "None";
     }
  }

#endif // PATTERN_TYPES_MQH
