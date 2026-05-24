//+------------------------------------------------------------------+
//| Analysis/SRDetector.mqh — v1.0.2                                 |
//| Responsibility: PIVOT DETECTION ONLY                             |
//+------------------------------------------------------------------+
#property strict
#ifndef __ANALYSIS_SR_DETECTOR_MQH__
#define __ANALYSIS_SR_DETECTOR_MQH__

#include "../Data/SRStruct.mqh"

#define SR_LEFT_BARS    5
#define SR_RIGHT_BARS   5

struct SRPivotResult
  {
   double   price;
   bool     isHigh;
   int      barsAgo;
   void Init() { price=0.0; isHigh=false; barsAgo=0; }
  };

class CSRDetector
  {
private:
   int   m_leftBars;
   int   m_rightBars;

   bool IsPivotHigh(int shift, int totalBars) const
     {
      if(shift < m_rightBars || shift >= totalBars - m_leftBars) return false;
      double h = iHigh(_Symbol, _Period, shift);
      for(int i=1;i<=m_leftBars;i++)  if(iHigh(_Symbol,_Period,shift+i) >= h) return false;
      for(int i=1;i<=m_rightBars;i++) if(iHigh(_Symbol,_Period,shift-i) >= h) return false;
      return true;
     }

   bool IsPivotLow(int shift, int totalBars) const
     {
      if(shift < m_rightBars || shift >= totalBars - m_leftBars) return false;
      double l = iLow(_Symbol, _Period, shift);
      for(int i=1;i<=m_leftBars;i++)  if(iLow(_Symbol,_Period,shift+i) <= l) return false;
      for(int i=1;i<=m_rightBars;i++) if(iLow(_Symbol,_Period,shift-i) <= l) return false;
      return true;
     }

   bool IsConfirmedPivotInBuffer(const double &buf[], int i, bool findHigh) const
     {
      double val = buf[i];
      bool ok = true;
      for(int j=1;j<=m_leftBars && ok;j++)
         ok = findHigh ? buf[i-j] < val : buf[i-j] > val;
      for(int j=1;j<=m_rightBars && ok;j++)
         ok = findHigh ? buf[i+j] < val : buf[i+j] > val;
      return ok;
     }

public:
   CSRDetector() : m_leftBars(SR_LEFT_BARS), m_rightBars(SR_RIGHT_BARS) {}

   void SetPivotBars(int leftBars, int rightBars)
     {
      m_leftBars  = MathMax(1, leftBars);
      m_rightBars = MathMax(1, rightBars);
     }

   void SetPivotBarsForPeriod(ENUM_TIMEFRAMES tf=PERIOD_CURRENT)
     {
      ENUM_TIMEFRAMES p = (tf == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : tf;
      switch(p)
        {
         case PERIOD_M15: SetPivotBars(3,3); break;
         case PERIOD_M30: SetPivotBars(4,4); break;
         case PERIOD_H1:  SetPivotBars(5,5); break;
         case PERIOD_H4:  SetPivotBars(6,6); break;
         case PERIOD_D1:  SetPivotBars(8,8); break;
         default:         SetPivotBars(5,5); break;
        }
     }

   int Scan(int lookback, SRPivotResult &out[])
     {
      int totalBars = (int)Bars(_Symbol, _Period);
      int scanEnd = MathMin(lookback, totalBars - m_rightBars - 1);
      int found = 0;
      int startSize = ArraySize(out);
      for(int shift=m_rightBars+1; shift<scanEnd; shift++)
        {
         bool isHigh = IsPivotHigh(shift,totalBars);
         bool isLow  = IsPivotLow(shift,totalBars);
         if(!isHigh && !isLow) continue;
         int newIdx = startSize + found;
         ArrayResize(out,newIdx+1);
         out[newIdx].barsAgo = shift;
         out[newIdx].isHigh  = isHigh;
         out[newIdx].price   = isHigh ? iHigh(_Symbol,_Period,shift) : iLow(_Symbol,_Period,shift);
         found++;
        }
      return found;
     }

   int FindNearestSwing(bool findHigh, int startBar, int maxBars) const
     {
      if(startBar < 0 || maxBars <= 0) return -1;
      int totalBars=(int)Bars(_Symbol,_Period);
      if(startBar >= totalBars) return -1;
      int scanLimit=MathMin(maxBars,totalBars-startBar-1);
      if(scanLimit <= m_leftBars + m_rightBars) return -1;
      double buf[]; ArraySetAsSeries(buf,true);
      int copied = findHigh ? CopyHigh(_Symbol,_Period,startBar,scanLimit,buf) : CopyLow(_Symbol,_Period,startBar,scanLimit,buf);
      if(copied != scanLimit) return -1;
      for(int i=m_rightBars; i<scanLimit-m_leftBars; i++)
         if(IsConfirmedPivotInBuffer(buf,i,findHigh)) return startBar+i;
      return -1;
     }

   int FindBestSwing(bool findHigh, int startBar, int maxBars) const
     {
      if(startBar < 0 || maxBars <= 0) return -1;
      int totalBars=(int)Bars(_Symbol,_Period);
      if(startBar >= totalBars) return -1;
      int scanLimit=MathMin(maxBars,totalBars-startBar-1);
      if(scanLimit <= m_leftBars + m_rightBars) return -1;
      double buf[]; ArraySetAsSeries(buf,true);
      int copied = findHigh ? CopyHigh(_Symbol,_Period,startBar,scanLimit,buf) : CopyLow(_Symbol,_Period,startBar,scanLimit,buf);
      if(copied != scanLimit) return -1;
      int swingBar=-1;
      double bestValue = findHigh ? -DBL_MAX : DBL_MAX;
      for(int i=m_rightBars; i<scanLimit-m_leftBars; i++)
        {
         if(!IsConfirmedPivotInBuffer(buf,i,findHigh)) continue;
         double val=buf[i];
         if((findHigh && val>bestValue) || (!findHigh && val<bestValue))
           { bestValue=val; swingBar=startBar+i; }
        }
      return swingBar;
     }
  };

#endif
