//+------------------------------------------------------------------+
//| CandleUtils.mqh                                                  |
//| Copyright 2026, Agsicentre                                       |
//| Utility functions for candlestick analysis                       |
//+------------------------------------------------------------------+
#ifndef __CANDLE_UTILS_MQH__
#define __CANDLE_UTILS_MQH__

#property strict

//+------------------------------------------------------------------+
//| Basic Candle Properties                                          |
//+------------------------------------------------------------------+

//--- Get candle open price
inline double CandleOpen(const MqlRates &rates[], int shift)
{
   if(shift < 0 || shift >= ArraySize(rates))
      return 0.0;
   return rates[shift].open;
}

//--- Get candle high price
inline double CandleHigh(const MqlRates &rates[], int shift)
{
   if(shift < 0 || shift >= ArraySize(rates))
      return 0.0;
   return rates[shift].high;
}

//--- Get candle low price
inline double CandleLow(const MqlRates &rates[], int shift)
{
   if(shift < 0 || shift >= ArraySize(rates))
      return 0.0;
   return rates[shift].low;
}

//--- Get candle close price
inline double CandleClose(const MqlRates &rates[], int shift)
{
   if(shift < 0 || shift >= ArraySize(rates))
      return 0.0;
   return rates[shift].close;
}

//--- Get candle volume
inline long CandleVolume(const MqlRates &rates[], int shift)
{
   if(shift < 0 || shift >= ArraySize(rates))
      return 0;
   return rates[shift].tick_volume;
}

//+------------------------------------------------------------------+
//| Derived Candle Metrics                                           |
//+------------------------------------------------------------------+

//--- Calculate full candle range (high - low)
inline double CandleRange(const MqlRates &rates[], int shift)
{
   return CandleHigh(rates, shift) - CandleLow(rates, shift);
}

//--- Calculate candle body size (absolute value of close - open)
inline double CandleBody(const MqlRates &rates[], int shift)
{
   return MathAbs(CandleClose(rates, shift) - CandleOpen(rates, shift));
}

//--- Calculate upper wick size
inline double UpperWick(const MqlRates &rates[], int shift)
{
   double high = CandleHigh(rates, shift);
   double bodyTop = MathMax(CandleOpen(rates, shift), CandleClose(rates, shift));
   return high - bodyTop;
}

//--- Calculate lower wick size
inline double LowerWick(const MqlRates &rates[], int shift)
{
   double low = CandleLow(rates, shift);
   double bodyBottom = MathMin(CandleOpen(rates, shift), CandleClose(rates, shift));
   return bodyBottom - low;
}

//--- Calculate candle body midpoint
inline double CandleMidpoint(const MqlRates &rates[], int shift)
{
   return (CandleOpen(rates, shift) + CandleClose(rates, shift)) / 2.0;
}

//--- Calculate upper body (top of body)
inline double CandleBodyTop(const MqlRates &rates[], int shift)
{
   return MathMax(CandleOpen(rates, shift), CandleClose(rates, shift));
}

//--- Calculate lower body (bottom of body)
inline double CandleBodyBottom(const MqlRates &rates[], int shift)
{
   return MathMin(CandleOpen(rates, shift), CandleClose(rates, shift));
}

//+------------------------------------------------------------------+
//| Candle Direction Tests                                           |
//+------------------------------------------------------------------+

//--- Check if candle is bullish (close > open)
inline bool IsBullish(const MqlRates &rates[], int shift)
{
   return CandleClose(rates, shift) > CandleOpen(rates, shift);
}

//--- Check if candle is bearish (close < open)
inline bool IsBearish(const MqlRates &rates[], int shift)
{
   return CandleClose(rates, shift) < CandleOpen(rates, shift);
}

//--- Check if candle is neutral/doji (close ≈ open)
inline bool IsNeutral(const MqlRates &rates[], int shift, double tolerance = 0.00001)
{
   return MathAbs(CandleClose(rates, shift) - CandleOpen(rates, shift)) <= tolerance;
}

//--- Check if candle is an inside bar relative to previous bar
inline bool IsInsideBar(const MqlRates &rates[], int shift)
{
   if(shift < 1 || shift + 1 >= ArraySize(rates))
      return false;
      
   return CandleHigh(rates, shift) < CandleHigh(rates, shift + 1) &&
          CandleLow(rates, shift)  > CandleLow(rates, shift + 1);
}

//--- Check if candle is an outside bar (engulfing high and low)
inline bool IsOutsideBar(const MqlRates &rates[], int shift)
{
   if(shift < 1 || shift + 1 >= ArraySize(rates))
      return false;
      
   return CandleHigh(rates, shift) > CandleHigh(rates, shift + 1) &&
          CandleLow(rates, shift)  < CandleLow(rates, shift + 1);
}

//+------------------------------------------------------------------+
//| Wick Analysis                                                    |
//+------------------------------------------------------------------+

//--- Calculate upper wick as percentage of total range
inline double UpperWickPercent(const MqlRates &rates[], int shift)
{
   double range = CandleRange(rates, shift);
   if(range <= 0.0)
      return 0.0;
   return UpperWick(rates, shift) / range;
}

//--- Calculate lower wick as percentage of total range
inline double LowerWickPercent(const MqlRates &rates[], int shift)
{
   double range = CandleRange(rates, shift);
   if(range <= 0.0)
      return 0.0;
   return LowerWick(rates, shift) / range;
}

//--- Calculate body as percentage of total range
inline double BodyPercent(const MqlRates &rates[], int shift)
{
   double range = CandleRange(rates, shift);
   if(range <= 0.0)
      return 0.0;
   return CandleBody(rates, shift) / range;
}

//--- Check if candle has a significant upper wick (rejection at top)
inline bool HasSignificantUpperWick(const MqlRates &rates[], int shift, double threshold = 0.5)
{
   return UpperWickPercent(rates, shift) >= threshold;
}

//--- Check if candle has a significant lower wick (rejection at bottom)
inline bool HasSignificantLowerWick(const MqlRates &rates[], int shift, double threshold = 0.5)
{
   return LowerWickPercent(rates, shift) >= threshold;
}

//--- Check if candle is a doji (very small body relative to range)
inline bool IsDoji(const MqlRates &rates[], int shift, double bodyThreshold = 0.1)
{
   return BodyPercent(rates, shift) <= bodyThreshold;
}

//+------------------------------------------------------------------+
//| ATR Normalization                                                |
//+------------------------------------------------------------------+

//--- Normalize a price value by ATR (convert to ATR units)
inline double NormalizeByATR(double priceValue, double atrPoints)
{
   if(atrPoints <= 0.0)
      return 0.0;
   return priceValue / (atrPoints * _Point);
}

//--- Normalize candle range by ATR
inline double NormalizeRangeByATR(const MqlRates &rates[], int shift, double atrPoints)
{
   double range = CandleRange(rates, shift);
   return NormalizeByATR(range, atrPoints);
}

//--- Normalize candle body by ATR
inline double NormalizeBodyByATR(const MqlRates &rates[], int shift, double atrPoints)
{
   double body = CandleBody(rates, shift);
   return NormalizeByATR(body, atrPoints);
}

//--- Check if candle range is significant relative to ATR
inline bool IsLargeCandle(const MqlRates &rates[], int shift, double atrPoints, double threshold = 0.7)
{
   return NormalizeRangeByATR(rates, shift, atrPoints) >= threshold;
}

//--- Check if candle range is small relative to ATR
inline bool IsSmallCandle(const MqlRates &rates[], int shift, double atrPoints, double threshold = 0.3)
{
   return NormalizeRangeByATR(rates, shift, atrPoints) <= threshold;
}

//+------------------------------------------------------------------+
//| Multi-Candle Comparisons                                         |
//+------------------------------------------------------------------+

//--- Check if current candle engulfs the previous candle's body
inline bool IsBodyEngulfing(const MqlRates &rates[], int shift)
{
   if(shift < 1 || shift + 1 >= ArraySize(rates))
      return false;
   
   double curBody = CandleBody(rates, shift);
   double prevBody = CandleBody(rates, shift + 1);
   
   if(prevBody <= 0.0)
      return false;
   
   bool bullishEngulf = IsBullish(rates, shift) && IsBearish(rates, shift + 1) &&
                        CandleClose(rates, shift) > CandleOpen(rates, shift + 1) &&
                        CandleOpen(rates, shift) < CandleClose(rates, shift + 1);
   
   bool bearishEngulf = IsBearish(rates, shift) && IsBullish(rates, shift + 1) &&
                        CandleClose(rates, shift) < CandleOpen(rates, shift + 1) &&
                        CandleOpen(rates, shift) > CandleClose(rates, shift + 1);
   
   return (bullishEngulf || bearishEngulf) && curBody >= prevBody * 1.2;
}

//--- Compare two candles' ranges
inline double RangeRatio(const MqlRates &rates[], int shift1, int shift2)
{
   double range1 = CandleRange(rates, shift1);
   double range2 = CandleRange(rates, shift2);
   
   if(range2 <= 0.0)
      return 0.0;
   
   return range1 / range2;
}

//--- Check if a series of candles have similar highs (within tolerance)
inline bool AreSimilarHighs(const MqlRates &rates[], int shift1, int shift2, double tolerancePoints)
{
   double high1 = CandleHigh(rates, shift1);
   double high2 = CandleHigh(rates, shift2);
   double tol = MathMax(tolerancePoints * _Point, 3 * _Point);
   
   return MathAbs(high1 - high2) <= tol;
}

//--- Check if a series of candles have similar lows (within tolerance)
inline bool AreSimilarLows(const MqlRates &rates[], int shift1, int shift2, double tolerancePoints)
{
   double low1 = CandleLow(rates, shift1);
   double low2 = CandleLow(rates, shift2);
   double tol = MathMax(tolerancePoints * _Point, 3 * _Point);
   
   return MathAbs(low1 - low2) <= tol;
}

#endif // __CANDLE_UTILS_MQH__
