//+------------------------------------------------------------------+
//| FakeoutDetector.mqh                                              |
//| Copyright 2026, Agsicentre                                       |
//+------------------------------------------------------------------+
#ifndef __FAKEOUT_DETECTOR_MQH__
#define __FAKEOUT_DETECTOR_MQH__

#property strict

#include "CandleUtils.mqh"

//+------------------------------------------------------------------+
//| Fakeout Detection Result                                         |
//+------------------------------------------------------------------+
struct SFakeoutResult
{
   bool   isFakeout;
   int    direction;        // 1 = bullish fakeout (false breakdown), -1 = bearish fakeout (false breakout)
   double extremePrice;     // The false breakout extreme
   double reversalPrice;    // Price where reversal confirmed
   double strength;         // Confidence score 0.0-1.0
   string patternType;      // Type of fakeout detected
   ulong  barTime;          // Bar time when fakeout occurred
   
   void Clear()
   {
      isFakeout     = false;
      direction     = 0;
      extremePrice  = 0.0;
      reversalPrice = 0.0;
      strength      = 0.0;
      patternType   = "";
      barTime       = 0;
   }
};

//+------------------------------------------------------------------+
//| CFakeoutDetector Class                                           |
//| Detects various types of fakeouts/false breakouts               |
//+------------------------------------------------------------------+
class CFakeoutDetector
{
private:
   double m_atrPoints;
   double m_minStrength;
   int    m_lookbackBars;
   
public:
                  CFakeoutDetector() : m_atrPoints(0.0), m_minStrength(0.6), m_lookbackBars(20) {}
   virtual       ~CFakeoutDetector() {}
   
   void SetATRPoints(double atr)        { m_atrPoints = atr; }
   void SetMinStrength(double strength) { m_minStrength = strength; }
   void SetLookbackBars(int bars)       { m_lookbackBars = bars; }
   
   //--- Main detection method
   bool Detect(const MqlRates &rates[], int shift, SFakeoutResult &result);
   
   //--- Specific fakeout patterns
   bool DetectLiquidityGrab(const MqlRates &rates[], int shift, SFakeoutResult &result);
   bool DetectFalseBreakout(const MqlRates &rates[], int shift, double supportLevel, double resistanceLevel, SFakeoutResult &result);
   bool DetectSpringUpthrust(const MqlRates &rates[], int shift, SFakeoutResult &result);
   
private:
   //--- Helper methods
   double FindRecentHigh(const MqlRates &rates[], int startShift, int lookback);
   double FindRecentLow(const MqlRates &rates[], int startShift, int lookback);
   bool   IsSignificantBreak(double breakPrice, double level, double tolerance);
   double CalculateFakeoutStrength(const MqlRates &rates[], int shift, int dir);
};

//+------------------------------------------------------------------+
//| Find Recent High                                                 |
//+------------------------------------------------------------------+
double CFakeoutDetector::FindRecentHigh(const MqlRates &rates[], int startShift, int lookback)
{
   if(startShift < 0 || startShift + lookback >= ArraySize(rates))
      return 0.0;
   
   double highest = CandleHigh(rates, startShift);
   for(int i = 0; i < lookback && (startShift + i) < ArraySize(rates); i++)
   {
      double high = CandleHigh(rates, startShift + i);
      if(high > highest)
         highest = high;
   }
   return highest;
}

//+------------------------------------------------------------------+
//| Find Recent Low                                                  |
//+------------------------------------------------------------------+
double CFakeoutDetector::FindRecentLow(const MqlRates &rates[], int startShift, int lookback)
{
   if(startShift < 0 || startShift + lookback >= ArraySize(rates))
      return DBL_MAX;
   
   double lowest = CandleLow(rates, startShift);
   for(int i = 0; i < lookback && (startShift + i) < ArraySize(rates); i++)
   {
      double low = CandleLow(rates, startShift + i);
      if(low < lowest)
         lowest = low;
   }
   return lowest;
}

//+------------------------------------------------------------------+
//| Check if Break is Significant                                    |
//+------------------------------------------------------------------+
bool CFakeoutDetector::IsSignificantBreak(double breakPrice, double level, double tolerance)
{
   double tol = MathMax(tolerance * _Point, 3 * _Point);
   
   //--- Break above resistance
   if(breakPrice > level)
      return (breakPrice - level) >= tol;
   
   //--- Break below support
   if(breakPrice < level)
      return (level - breakPrice) >= tol;
   
   return false;
}

//+------------------------------------------------------------------+
//| Calculate Fakeout Strength                                       |
//+------------------------------------------------------------------+
double CFakeoutDetector::CalculateFakeoutStrength(const MqlRates &rates[], int shift, int dir)
{
   double strength = 0.5; // Base strength
   
   if(shift < 1 || shift + 1 >= ArraySize(rates))
      return strength;
   
   //--- Factor 1: Rejection candle body size
   double bodyPct = BodyPercent(rates, shift);
   if(bodyPct >= 0.40) strength += 0.15;
   if(bodyPct >= 0.60) strength += 0.10;
   
   //--- Factor 2: Wick rejection
   double rejectionWick = (dir == 1) ? LowerWick(rates, shift) : UpperWick(rates, shift);
   double range = CandleRange(rates, shift);
   if(range > 0.0)
   {
      double wickPct = rejectionWick / range;
      if(wickPct >= 0.50) strength += 0.15;
      if(wickPct >= 0.65) strength += 0.10;
   }
   
   //--- Factor 3: Follow-through confirmation
   double prevClose = CandleClose(rates, shift + 1);
   double curClose  = CandleClose(rates, shift);
   
   if(dir == 1 && curClose > prevClose) strength += 0.10;
   if(dir == -1 && curClose < prevClose) strength += 0.10;
   
   //--- Factor 4: ATR expansion
   if(IsLargeCandle(rates, shift, m_atrPoints, 0.7)) strength += 0.10;
   
   return MathMin(1.0, strength);
}

//+------------------------------------------------------------------+
//| Main Detection Method                                            |
//+------------------------------------------------------------------+
bool CFakeoutDetector::Detect(const MqlRates &rates[], int shift, SFakeoutResult &result)
{
   result.Clear();
   
   if(shift < 1 || shift + 2 >= ArraySize(rates))
      return false;
   
   //--- Try liquidity grab detection first
   if(DetectLiquidityGrab(rates, shift, result))
      return true;
   
   //--- Try spring/upthrust detection
   if(DetectSpringUpthrust(rates, shift, result))
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Detect Liquidity Grab Pattern                                    |
//+------------------------------------------------------------------+
bool CFakeoutDetector::DetectLiquidityGrab(const MqlRates &rates[], int shift, SFakeoutResult &result)
{
   result.Clear();
   
   if(shift < 2 || shift + 2 >= ArraySize(rates))
      return false;
   
   //--- Find recent swing high and low
   double recentHigh = FindRecentHigh(rates, shift + 1, m_lookbackBars / 2);
   double recentLow  = FindRecentLow(rates, shift + 1, m_lookbackBars / 2);
   
   if(recentHigh <= 0.0 || recentLow >= DBL_MAX)
      return false;
   
   double currentHigh = CandleHigh(rates, shift);
   double currentLow  = CandleLow(rates, shift);
   double currentClose = CandleClose(rates, shift);
   double currentOpen  = CandleOpen(rates, shift);
   
   //--- Bullish liquidity grab: break below recent low, then close back above
   if(currentLow < recentLow && currentClose > recentLow && currentClose > currentOpen)
   {
      result.isFakeout     = true;
      result.direction     = 1;  // Bullish reversal
      result.extremePrice  = currentLow;
      result.reversalPrice = recentLow;
      result.patternType   = "Liquidity Grab Bull";
      result.barTime       = rates[shift].time;
      result.strength      = CalculateFakeoutStrength(rates, shift, 1);
      
      return result.strength >= m_minStrength;
   }
   
   //--- Bearish liquidity grab: break above recent high, then close back below
   if(currentHigh > recentHigh && currentClose < recentHigh && currentClose < currentOpen)
   {
      result.isFakeout     = true;
      result.direction     = -1; // Bearish reversal
      result.extremePrice  = currentHigh;
      result.reversalPrice = recentHigh;
      result.patternType   = "Liquidity Grab Bear";
      result.barTime       = rates[shift].time;
      result.strength      = CalculateFakeoutStrength(rates, shift, -1);
      
      return result.strength >= m_minStrength;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Detect False Breakout at Support/Resistance                      |
//+------------------------------------------------------------------+
bool CFakeoutDetector::DetectFalseBreakout(const MqlRates &rates[], int shift, 
                                           double supportLevel, double resistanceLevel, 
                                           SFakeoutResult &result)
{
   result.Clear();
   
   if(shift < 1 || shift + 1 >= ArraySize(rates))
      return false;
   
   if(supportLevel <= 0.0 || resistanceLevel <= 0.0)
      return false;
   
   double currentHigh = CandleHigh(rates, shift);
   double currentLow  = CandleLow(rates, shift);
   double currentClose = CandleClose(rates, shift);
   double currentOpen  = CandleOpen(rates, shift);
   
   double tolerance = m_atrPoints * 0.20; // 20% of ATR as tolerance
   
   //--- False breakdown at support
   if(IsSignificantBreak(currentLow, supportLevel, tolerance) && 
      currentClose > supportLevel && currentClose > currentOpen)
   {
      result.isFakeout     = true;
      result.direction     = 1;  // Bullish
      result.extremePrice  = currentLow;
      result.reversalPrice = supportLevel;
      result.patternType   = "False Breakdown";
      result.barTime       = rates[shift].time;
      result.strength      = CalculateFakeoutStrength(rates, shift, 1);
      
      return result.strength >= m_minStrength;
   }
   
   //--- False breakout at resistance
   if(IsSignificantBreak(currentHigh, resistanceLevel, tolerance) && 
      currentClose < resistanceLevel && currentClose < currentOpen)
   {
      result.isFakeout     = true;
      result.direction     = -1; // Bearish
      result.extremePrice  = currentHigh;
      result.reversalPrice = resistanceLevel;
      result.patternType   = "False Breakout";
      result.barTime       = rates[shift].time;
      result.strength      = CalculateFakeoutStrength(rates, shift, -1);
      
      return result.strength >= m_minStrength;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Detect Spring / Upthrust (Wyckoff Patterns)                      |
//+------------------------------------------------------------------+
bool CFakeoutDetector::DetectSpringUpthrust(const MqlRates &rates[], int shift, SFakeoutResult &result)
{
   result.Clear();
   
   if(shift < 2 || shift + 2 >= ArraySize(rates))
      return false;
   
   //--- Identify trading range
   double rangeHigh = FindRecentHigh(rates, shift + 1, m_lookbackBars);
   double rangeLow  = FindRecentLow(rates, shift + 1, m_lookbackBars);
   
   if(rangeHigh <= 0.0 || rangeLow >= DBL_MAX)
      return false;
   
   double rangeMid = (rangeHigh + rangeLow) / 2.0;
   double currentClose = CandleClose(rates, shift);
   double currentOpen  = CandleOpen(rates, shift);
   
   //--- Spring: break below range low, strong close back in range
   if(CandleLow(rates, shift) < rangeLow && 
      currentClose > rangeLow && 
      currentClose > rangeMid &&
      currentClose > currentOpen)
   {
      result.isFakeout     = true;
      result.direction     = 1;  // Bullish spring
      result.extremePrice  = CandleLow(rates, shift);
      result.reversalPrice = rangeLow;
      result.patternType   = "Spring";
      result.barTime       = rates[shift].time;
      result.strength      = CalculateFakeoutStrength(rates, shift, 1);
      
      //--- Additional strength for closing in upper half of range
      if(currentClose > (rangeMid + (rangeHigh - rangeMid) * 0.5))
         result.strength += 0.15;
      
      return result.strength >= m_minStrength;
   }
   
   //--- Upthrust: break above range high, strong close back in range
   if(CandleHigh(rates, shift) > rangeHigh && 
      currentClose < rangeHigh && 
      currentClose < rangeMid &&
      currentClose < currentOpen)
   {
      result.isFakeout     = true;
      result.direction     = -1; // Bearish upthrust
      result.extremePrice  = CandleHigh(rates, shift);
      result.reversalPrice = rangeHigh;
      result.patternType   = "Upthrust";
      result.barTime       = rates[shift].time;
      result.strength      = CalculateFakeoutStrength(rates, shift, -1);
      
      //--- Additional strength for closing in lower half of range
      if(currentClose < (rangeMid - (rangeMid - rangeLow) * 0.5))
         result.strength += 0.15;
      
      return result.strength >= m_minStrength;
   }
   
   return false;
}

#endif // __FAKEOUT_DETECTOR_MQH__
