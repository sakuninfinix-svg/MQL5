//+------------------------------------------------------------------+
//| Pattern/CandleUtils.mqh — v1.00                                  |
//| Candle classification helpers used by PatternManager             |
//+------------------------------------------------------------------+
#property strict
#ifndef __PATTERN_CANDLE_UTILS_MQH__
#define __PATTERN_CANDLE_UTILS_MQH__

// Candle direction
enum ENUM_CANDLE_DIR { CANDLE_BULL=1, CANDLE_BEAR=-1, CANDLE_DOJI=0 };

// Full OHLC candle snapshot
struct CandleData
  {
   datetime time;
   double   open, high, low, close;
   double   body;      // abs(close-open)
   double   range;     // high-low
   double   upperWick; // high - max(open,close)
   double   lowerWick; // min(open,close) - low
   ENUM_CANDLE_DIR dir;

   void Load(int shift, string sym=NULL, ENUM_TIMEFRAMES tf=PERIOD_CURRENT)
     {
      string s = (sym == NULL) ? _Symbol : sym;
      time       = iTime(s, tf, shift);
      open       = iOpen(s, tf, shift);
      high       = iHigh(s, tf, shift);
      low        = iLow(s, tf, shift);
      close      = iClose(s, tf, shift);
      body       = MathAbs(close - open);
      range      = high - low;
      upperWick  = high - MathMax(open, close);
      lowerWick  = MathMin(open, close) - low;
      if(body < range * 0.05) dir = CANDLE_DOJI;
      else if(close > open)   dir = CANDLE_BULL;
      else                    dir = CANDLE_BEAR;
     }

   bool IsBullish()   const { return dir == CANDLE_BULL; }
   bool IsBearish()   const { return dir == CANDLE_BEAR; }
   bool IsDoji()      const { return dir == CANDLE_DOJI; }
   bool IsLargeBody() const { return range > 0 && body / range >= 0.6; }

   // Hammer: small body at top, long lower wick >= 2x body, tiny upper wick
   bool IsHammer() const
     {
      return (range > 0 && body / range < 0.35 &&
              lowerWick >= 2.0 * body && upperWick <= body * 0.5);
     }

   // Shooting Star: small body at bottom, long upper wick >= 2x body
   bool IsShootingStar() const
     {
      return (range > 0 && body / range < 0.35 &&
              upperWick >= 2.0 * body && lowerWick <= body * 0.5);
     }

   // Engulfing: this candle engulfs |prev|
   bool Engulfs(const CandleData &prev) const
     {
      return (dir != prev.dir &&
              MathMax(open,close) > MathMax(prev.open,prev.close) &&
              MathMin(open,close) < MathMin(prev.open,prev.close));
     }
  };

// Utility: load N candles into array starting from shift
inline void LoadCandles(CandleData &arr[], int count, int startShift=1,
                        string sym=NULL, ENUM_TIMEFRAMES tf=PERIOD_CURRENT)
  {
   ArrayResize(arr, count);
   for(int i=0;i<count;i++) arr[i].Load(startShift+i,sym,tf);
  }

#endif
