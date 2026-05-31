//+------------------------------------------------------------------+
//| Signal/SignalFilterPipeline.mqh — v1.05                         |
//| Modular filter pipeline for signal validation                    |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_FILTER_PIPELINE_MQH__
#define __SIGNAL_FILTER_PIPELINE_MQH__

#include "../Data/SRStruct.mqh"
#include "SignalConfig.mqh"

#define PASR_MAX_CUSTOM_FILTERS 32

struct FilterResult
  {
   bool   passed;
   string reason;
   string filterName;

   void Clear()
     {
      passed     = true;
      reason     = "OK";
      filterName = "";
     }

   void Reject(const string filter, const string msg)
     {
      passed     = false;
      filterName = filter;
      reason     = msg;
     }
  };

class IFilter
  {
public:
   virtual string Name() = 0;
   virtual bool   Apply(int shift, const MqlRates &rates[], double atrPoints,
                        ENUM_SIGNAL_DIR dir, FilterResult &result) = 0;
  };

class CSignalFilterPipeline
  {
private:
   const CSignalConfig *m_config;
   IFilter             *m_customFilters[PASR_MAX_CUSTOM_FILTERS];
   int                  m_customFilterCount;
   string               m_currentFilterReason;

   bool HasRateIndex(const MqlRates &rates[], int index) const
     { return (index >= 0 && index < ArraySize(rates)); }

public:
   CSignalFilterPipeline() : m_config(NULL), m_customFilterCount(0), m_currentFilterReason("")
     {
      for(int i=0; i<PASR_MAX_CUSTOM_FILTERS; i++) m_customFilters[i] = NULL;
     }

   void Init(const CSignalConfig &config) { m_config = &config; }

   void AddCustomFilter(IFilter *filter)
     {
      if(filter == NULL) return;
      if(m_customFilterCount >= PASR_MAX_CUSTOM_FILTERS) return;
      m_customFilters[m_customFilterCount++] = filter;
     }

   string GetCurrentReason() const { return m_currentFilterReason; }

   bool PassZoneTouchFilter(int shift, int dir, double zonePrice,
                            double atrPoints, double dynamicMult,
                            FilterResult &result, const MqlRates &rates[])
     {
      m_currentFilterReason = "";
      if(m_config == NULL) { result.Reject("ZoneTouch","Config not initialized"); return false; }
      if(!HasRateIndex(rates, shift)) { result.Reject("ZoneTouch","Insufficient candle data"); return false; }
      double extreme   = (dir == 1) ? rates[shift].low : rates[shift].high;
      double zoneWidth = (atrPoints * dynamicMult) * _Point;
      double mult      = (m_config.GetEntryMode() == MODE_SAFE) ? 0.5 : 1.0;
      bool ok = (dir == 1) ? (extreme <= zonePrice + (zoneWidth * mult))
                            : (extreme >= zonePrice - (zoneWidth * mult));
      if(!ok)
        {
         result.Reject("ZoneTouch","Not touching zone");
         m_currentFilterReason = "Not touching zone";
         return false;
        }
      return true;
     }

   bool PassContextFilter(int shift, double atrPoints, FilterResult &result,
                          const MqlRates &rates[], int dir)
     {
      m_currentFilterReason = "";
      if(m_config == NULL) { result.Reject("Context","Config not initialized"); return false; }
      int sz = ArraySize(rates);
      if(shift < 0 || shift >= sz)
        {
         result.Reject("Context","Insufficient candle data");
         m_currentFilterReason = "Insufficient candle data";
         return false;
        }
      double o = rates[shift].open, h = rates[shift].high;
      double l = rates[shift].low, c = rates[shift].close;
      double range = h - l;
      double body = MathAbs(o - c);
      if(range > m_config.GetMaxSignalATR() * atrPoints * _Point)
        {
         result.Reject("Context","Signal too large");
         m_currentFilterReason = "Signal too large";
         return false;
        }
      bool rejectionClose = (dir == 1) ? (c > o) : (c < o);
      if(range > 0 && (body / range) > m_config.GetAntiBreakoutPct() && !rejectionClose)
        {
         result.Reject("Context","Breakout candle: large body without rejection close");
         m_currentFilterReason = "Breakout candle: large body without rejection close";
         return false;
        }
      double threshold = atrPoints * m_config.GetMomentumThresholdATR() * _Point;
      int pushCount = 0;
      for(int i = 1; i <= 3; i++)
        {
         int curIdx = shift + i;
         int prevIdx = curIdx + 1;
         if(prevIdx >= sz) break;
         double curO = rates[curIdx].open, curC = rates[curIdx].close;
         double curH = rates[curIdx].high, curL = rates[curIdx].low;
         double prevH = rates[prevIdx].high, prevL = rates[prevIdx].low;
         double curBody = MathAbs(curO - curC);
         bool isPush = (dir == 1)
                       ? (curH < prevH || (curC < curO && curBody > threshold))
                       : (curL > prevL || (curC > curO && curBody > threshold));
         if(isPush) pushCount++; else break;
        }
      if(pushCount < 1)
        {
         result.Reject("Context","No momentum push to zone");
         m_currentFilterReason = "No momentum push to zone";
         return false;
        }
      return true;
     }

   bool PassMTFFilter(int dir, double referencePrice,
                      double htfSupport, double htfResistance,
                      double atrPoints, int &bias, FilterResult &result)
     {
      m_currentFilterReason = "";
      if(m_config == NULL) { result.Reject("MTF","Config not initialized"); return false; }
      bias = 0;
      if(m_config.GetUseMTF())
        {
         double zone = (atrPoints * m_config.GetATRBufferMult()) * _Point;
         bool nearHtfSupport = (htfSupport > 0.0 && referencePrice <= htfSupport + zone);
         bool nearHtfResist = (htfResistance > 0.0 && referencePrice >= htfResistance - zone);
         if(nearHtfSupport && !nearHtfResist) bias = 1;
         else if(nearHtfResist && !nearHtfSupport) bias = -1;
        }
      if(!m_config.GetUseMTF()) return true;
      int qualityScore = dir * bias;
      if(qualityScore >= 0)
        {
         result.passed = true;
         result.reason = (qualityScore == 1) ? "High Quality Signal (MTF Aligned)" : "Standard Quality Signal (MTF Neutral)";
         return true;
        }
      result.Reject("MTF","Low Quality (Blocked by MTF Contra-Bias)");
      m_currentFilterReason = "Low Quality (Blocked by MTF Contra-Bias)";
      return false;
     }

   bool PassOpportunityFilter(int dir, double atrPoints,
                              double zonePrice, double oppositeZone,
                              double signalPrice, FilterResult &result)
     {
      m_currentFilterReason = "";
      if(m_config == NULL) { result.Reject("Opportunity","Config not initialized"); return false; }
      if(oppositeZone <= 0.0)
        {
         result.passed = true;
         result.reason = "No opposite zone; opportunity neutral";
         return true;
        }
      double target = oppositeZone;
      double profitDist = (dir == 1) ? (target - signalPrice) : (signalPrice - target);
      double slDist = MathAbs(signalPrice - zonePrice);
      double minTPDist = (atrPoints * m_config.GetMinTPDistanceATR()) * _Point;
      if(profitDist <= 0.0)
        {
         result.Reject("Opportunity","Target is behind entry");
         m_currentFilterReason = "Target is behind entry";
         return false;
        }
      if(profitDist < minTPDist)
        {
         result.Reject("Opportunity","TP distance < Min ATR");
         m_currentFilterReason = "TP distance < Min ATR";
         return false;
        }
      if(slDist > 0.0)
        {
         double rr = profitDist / slDist;
         double minRR = m_config.GetMinRRRatio();
         if(rr < minRR)
           {
            string msg = StringFormat("R:R %.2f < min %.2f", rr, minRR);
            result.Reject("Opportunity", msg);
            m_currentFilterReason = msg;
            return false;
           }
        }
      return true;
     }

   bool RunCompletePipeline(int shift, int dir, double zonePrice,
                            double signalPrice, double atrPoints,
                            double htfSupport, double htfResistance,
                            double dynamicMult,
                            double support, double resistance,
                            FilterResult &result,
                            const MqlRates &rates[])
     {
      result.Clear();
      if(!HasRateIndex(rates, shift))
        {
         result.Reject("Pipeline", "Insufficient candle data");
         return false;
        }
      double oppositeZone = (dir == 1) ? resistance : support;
      if(!PassZoneTouchFilter(shift, dir, zonePrice, atrPoints, dynamicMult, result, rates)) return false;
      if(!PassContextFilter(shift, atrPoints, result, rates, dir)) return false;
      int bias = 0;
      if(!PassMTFFilter(dir, signalPrice, htfSupport, htfResistance, atrPoints, bias, result)) return false;
      if(!PassOpportunityFilter(dir, atrPoints, zonePrice, oppositeZone, signalPrice, result)) return false;
      ENUM_SIGNAL_DIR sigDir = (dir == 1) ? SIGNAL_BUY : SIGNAL_SELL;
      if(!RunCustomFilters(shift, rates, atrPoints, sigDir, result)) return false;
      result.passed = true;
      result.reason = "All filters passed";
      return true;
     }

   bool RunCustomFilters(int shift, const MqlRates &rates[], double atrPoints,
                         ENUM_SIGNAL_DIR dir, FilterResult &result)
     {
      for(int i = 0; i < m_customFilterCount; i++)
        {
         IFilter *filter = m_customFilters[i];
         if(filter != NULL && !filter.Apply(shift, rates, atrPoints, dir, result)) return false;
        }
      result.passed = true;
      return true;
     }
  };

#endif // __SIGNAL_FILTER_PIPELINE_MQH__
