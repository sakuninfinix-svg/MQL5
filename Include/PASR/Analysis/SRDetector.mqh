//+------------------------------------------------------------------+
//| Analysis/SRDetector.mqh — v1.0.1                                 |
//| Responsibility: PIVOT DETECTION ONLY                             |
//|                                                                   |
//| Pure calculation layer — no IManager, no EventBus, no side       |
//| effects. Detects swing pivot highs/lows from OHLC arrays and      |
//| returns them as SRPivotResult structs for SRZoneStore to consume. |
//|                                                                   |
//| Owned by:  CAnalysisSRManager (SRManager.mqh)                    |
//| Feeds:     CSRZoneStore via SRManager.OnNewBar()                  |
//|                                                                   |
//| CHANGELOG:                                                       |
//|   v1.0.1 (2026-05-24):                                           |
//|     BUG-I07: FindNearestSwing() previously returned the best      |
//|              price extremum in the scan window, not the nearest   |
//|              confirmed pivot from startBar. Fixed to return the   |
//|              first confirmed pivot. Old extremum behavior kept as |
//|              FindBestSwing().                                    |
//+------------------------------------------------------------------+
#property strict
#ifndef __ANALYSIS_SR_DETECTOR_MQH__
#define __ANALYSIS_SR_DETECTOR_MQH__

#include "../Data/SRStruct.mqh"

//--- Pivot detection constants
#define SR_LEFT_BARS    3   // Confirmation bars — left side
#define SR_RIGHT_BARS   3   // Confirmation bars — right side

//+------------------------------------------------------------------+
//| Single pivot scan result                                         |
//+------------------------------------------------------------------+
struct SRPivotResult
  {
   double   price;      // Pivot price level
   bool     isHigh;     // true=resistance pivot, false=support pivot
   int      barsAgo;    // How many bars ago this pivot formed

   void Init()
     {
      price   = 0.0;
      isHigh  = false;
      barsAgo = 0;
     }
  };

//+------------------------------------------------------------------+
//| CSRDetector — stateless pivot scanner                            |
//|                                                                   |
//| DESIGN CONTRACT:                                                  |
//|   - No member state that persists between calls                   |
//|   - All inputs passed explicitly (no global reads)                |
//|   - Returns results via output array — no side effects            |
//|   - All iHigh/iLow/CopyHigh/CopyLow calls ISOLATED HERE          |
//+------------------------------------------------------------------+
class CSRDetector
  {
private:
   //-- Configuration (set once at construction/config)
   int   m_leftBars;    // Pivot left-side confirmation bars
   int   m_rightBars;   // Pivot right-side confirmation bars

   //-- Checks if bar[shift] is a confirmed pivot HIGH
   bool IsPivotHigh(int shift, int totalBars) const
     {
      if(shift < m_rightBars || shift >= totalBars - m_leftBars)
         return false;

      double h = iHigh(_Symbol, _Period, shift);

      for(int i = 1; i <= m_leftBars; i++)
         if(iHigh(_Symbol, _Period, shift + i) >= h) return false;

      for(int i = 1; i <= m_rightBars; i++)
         if(iHigh(_Symbol, _Period, shift - i) >= h) return false;

      return true;
     }

   //-- Checks if bar[shift] is a confirmed pivot LOW
   bool IsPivotLow(int shift, int totalBars) const
     {
      if(shift < m_rightBars || shift >= totalBars - m_leftBars)
         return false;

      double l = iLow(_Symbol, _Period, shift);

      for(int i = 1; i <= m_leftBars; i++)
         if(iLow(_Symbol, _Period, shift + i) <= l) return false;

      for(int i = 1; i <= m_rightBars; i++)
         if(iLow(_Symbol, _Period, shift - i) <= l) return false;

      return true;
     }

   bool IsConfirmedPivotInBuffer(const double &buf[], int i, bool findHigh) const
     {
      double val = buf[i];
      bool   ok  = true;

      // Bars closer to the current bar side
      for(int j = 1; j <= m_leftBars && ok; j++)
         ok = findHigh ? buf[i - j] < val : buf[i - j] > val;

      // Bars farther to the history side
      for(int j = 1; j <= m_rightBars && ok; j++)
         ok = findHigh ? buf[i + j] < val : buf[i + j] > val;

      return ok;
     }

public:
   CSRDetector()
      : m_leftBars(SR_LEFT_BARS),
        m_rightBars(SR_RIGHT_BARS)
     {}

   //-- Override pivot confirmation window
   void SetPivotBars(int leftBars, int rightBars)
     {
      m_leftBars  = MathMax(1, leftBars);
      m_rightBars = MathMax(1, rightBars);
     }

   //+---------------------------------------------------------------+
   //| Scan() — main entry point                                     |
   //|                                                               |
   //| Scans [lookback] bars back for pivot highs/lows.              |
   //| Appends results to [out] — caller manages the array.          |
   //| Returns number of pivots found this call.                     |
   //+---------------------------------------------------------------+
   int Scan(int lookback, SRPivotResult &out[])
     {
      int totalBars = (int)Bars(_Symbol, _Period);
      int scanEnd   = MathMin(lookback, totalBars - m_rightBars - 1);
      int found     = 0;
      int startSize = ArraySize(out);

      for(int shift = m_rightBars + 1; shift < scanEnd; shift++)
        {
         bool isHigh = IsPivotHigh(shift, totalBars);
         bool isLow  = IsPivotLow(shift, totalBars);

         if(!isHigh && !isLow) continue;

         // Append to output array
         int newIdx = startSize + found;
         ArrayResize(out, newIdx + 1);
         out[newIdx].barsAgo = shift;
         out[newIdx].isHigh  = isHigh;
         out[newIdx].price   = isHigh
                               ? iHigh(_Symbol, _Period, shift)
                               : iLow(_Symbol, _Period, shift);
         found++;
        }

      return found;
     }

   //+---------------------------------------------------------------+
   //| FindNearestSwing() — locate nearest confirmed pivot           |
   //|                                                               |
   //| Returns the first confirmed pivot found from startBar toward  |
   //| older bars, or -1 if none found. This matches the method name |
   //| and is suitable for nearest swing SL/reference placement.     |
   //+---------------------------------------------------------------+
   int FindNearestSwing(bool findHigh, int startBar, int maxBars) const
     {
      if(startBar < 0 || maxBars <= 0) return -1;

      int totalBars = (int)Bars(_Symbol, _Period);
      if(startBar >= totalBars) return -1;

      int scanLimit = MathMin(maxBars, totalBars - startBar - 1);
      if(scanLimit <= m_leftBars + m_rightBars) return -1;

      double buf[];
      ArraySetAsSeries(buf, true);

      int copied = findHigh
                   ? CopyHigh(_Symbol, _Period, startBar, scanLimit, buf)
                   : CopyLow(_Symbol, _Period, startBar, scanLimit, buf);

      if(copied != scanLimit) return -1;

      for(int i = m_rightBars; i < scanLimit - m_leftBars; i++)
        {
         if(IsConfirmedPivotInBuffer(buf, i, findHigh))
            return startBar + i;
        }

      return -1;
     }

   //+---------------------------------------------------------------+
   //| FindBestSwing() — locate strongest price extremum pivot       |
   //|                                                               |
   //| Keeps the old FindNearestSwing() behavior intentionally:      |
   //| highest confirmed swing high or lowest confirmed swing low in |
   //| the scan window. Use this when the desired intent is extremum |
   //| selection, not nearest pivot selection.                       |
   //+---------------------------------------------------------------+
   int FindBestSwing(bool findHigh, int startBar, int maxBars) const
     {
      if(startBar < 0 || maxBars <= 0) return -1;

      int totalBars = (int)Bars(_Symbol, _Period);
      if(startBar >= totalBars) return -1;

      int scanLimit = MathMin(maxBars, totalBars - startBar - 1);
      if(scanLimit <= m_leftBars + m_rightBars) return -1;

      double buf[];
      ArraySetAsSeries(buf, true);

      int copied = findHigh
                   ? CopyHigh(_Symbol, _Period, startBar, scanLimit, buf)
                   : CopyLow(_Symbol, _Period, startBar, scanLimit, buf);

      if(copied != scanLimit) return -1;

      int    swingBar  = -1;
      double bestValue = findHigh ? -DBL_MAX : DBL_MAX;

      for(int i = m_rightBars; i < scanLimit - m_leftBars; i++)
        {
         if(!IsConfirmedPivotInBuffer(buf, i, findHigh))
            continue;

         double val = buf[i];
         if((findHigh && val > bestValue) || (!findHigh && val < bestValue))
           {
            bestValue = val;
            swingBar  = startBar + i;
           }
        }

      return swingBar;
     }
  };

#endif // __ANALYSIS_SR_DETECTOR_MQH__
