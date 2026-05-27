//+------------------------------------------------------------------+
//| Analysis/Pattern/PatternTypes.mqh — v2.02                        |
//| Canonical pattern type definitions for PASR                       |
//+------------------------------------------------------------------+
#property strict
#ifndef PATTERN_TYPES_MQH
#define PATTERN_TYPES_MQH

#include <Arrays/ArrayObj.mqh>
#include "../../Data/RegimeTypes.mqh"

// Enum Jenis Pola Candlestick Utama (Unified untuk PatternManager)
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

typedef ENUM_PATTERN_TYPE EPatternType;

#define PATTERN_PINBAR_BULL   PATTERN_PINBAR
#define PATTERN_PINBAR_BEAR   PATTERN_PINBAR
#define PATTERN_ENGULF_BULL   PATTERN_ENGULFING
#define PATTERN_ENGULF_BEAR   PATTERN_ENGULFING
#define PATTERN_HARAMI_BULL   PATTERN_HARAMI
#define PATTERN_HARAMI_BEAR   PATTERN_HARAMI

class SPatternSignal : public CObject
  {
public:
   EPatternType     type;
   int              barIndex;
   datetime         time;
   double           open;
   double           high;
   double           low;
   double           close;
   double           bodySize;
   double           upperWick;
   double           lowerWick;
   double           totalRange;
   double           strength;
   double           confidence;
   EMarketRegime    detectedRegime;

   SPatternSignal()
     {
      Clear();
     }

   SPatternSignal(const SPatternSignal &src)
     {
      Assign(src);
     }

   void Clear()
     {
      type = PATTERN_NONE;
      barIndex = 0;
      time = 0;
      open = high = low = close = 0.0;
      bodySize = upperWick = lowerWick = totalRange = 0.0;
      strength = 0.0;
      confidence = 0.0;
      detectedRegime = REGIME_UNKNOWN;
     }

   void Assign(const SPatternSignal &src)
     {
      type = src.type;
      barIndex = src.barIndex;
      time = src.time;
      open = src.open;
      high = src.high;
      low = src.low;
      close = src.close;
      bodySize = src.bodySize;
      upperWick = src.upperWick;
      lowerWick = src.lowerWick;
      totalRange = src.totalRange;
      strength = src.strength;
      confidence = src.confidence;
      detectedRegime = src.detectedRegime;
     }

   bool IsValid() const { return type != PATTERN_NONE && strength > 0.0; }

   string TypeName() const
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

   string Direction() const
     {
      if(type == PATTERN_MORNING_STAR) return "BULLISH";
      if(type == PATTERN_EVENING_STAR) return "BEARISH";
      return "NEUTRAL";
     }
  };

class CPatternSignalArray : public CArrayObj
  {
public:
   CPatternSignalArray() { }

   bool Add(const SPatternSignal &signal)
     {
      SPatternSignal *ptr = new SPatternSignal(signal);
      if(ptr == NULL) return false;
      return CArrayObj::Add(ptr);
     }

   SPatternSignal *At(int index) const
     {
      return (SPatternSignal*)CArrayObj::At(index);
     }

   CPatternSignalArray *FilterByType(EPatternType type) const
     {
      CPatternSignalArray *result = new CPatternSignalArray();
      if(result == NULL) return NULL;

      for(int i = 0; i < Total(); i++)
        {
         SPatternSignal *sig = At(i);
         if(sig != NULL && sig.type == type)
            result.Add(*sig);
        }
      return result;
     }

   CPatternSignalArray *FilterByStrength(double minStrength) const
     {
      CPatternSignalArray *result = new CPatternSignalArray();
      if(result == NULL) return NULL;

      for(int i = 0; i < Total(); i++)
        {
         SPatternSignal *sig = At(i);
         if(sig != NULL && sig.strength >= minStrength)
            result.Add(*sig);
        }
      return result;
     }
  };

#endif // PATTERN_TYPES_MQH