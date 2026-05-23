//+------------------------------------------------------------------+
//| Signal/SignalFilterPipeline.mqh — v1.02                         |
//| Modular filter pipeline for signal validation                    |
//|                                                                  |
//| FIX v1.02:                                                       |
//|  BUG-S10-001 — RunCompletePipeline() used undefined `support`   |
//|    and `resistance` variables; compile error on all builds.      |
//|    Fixed: pass explicit zonePrice + oppositeZone params.         |
//|  BUG-S10-002 — RunCustomFilters() was never called from         |
//|    RunCompletePipeline(); custom filters were silently ignored.  |
//|    Fixed: custom filter pass appended at end of pipeline.        |
//|  BUG-S10-003 — MTF filter received rates[shift].close as        |
//|    referencePrice; should use signalPrice for zone proximity.    |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_FILTER_PIPELINE_MQH__
#define __SIGNAL_FILTER_PIPELINE_MQH__

#include <Arrays\ArrayObj.mqh>
#include "../Data/SRStruct.mqh"
#include "SignalConfig.mqh"

//+------------------------------------------------------------------+
//| Filter Result Structure                                          |
//+------------------------------------------------------------------+
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

   void Reject(const string &filter, const string &msg)
     {
      passed     = false;
      filterName = filter;
      this.reason = msg;
     }
  };

//+------------------------------------------------------------------+
//| IFilter — Interface for pluggable custom filters                 |
//+------------------------------------------------------------------+
class IFilter
  {
public:
   virtual string Name() = 0;
   virtual bool   Apply(int shift, const MqlRates &rates[], double atrPoints,
                        ENUM_SIGNAL_DIR dir, FilterResult &result) = 0;
  };

//+------------------------------------------------------------------+
//| CSignalFilterPipeline — v1.02                                    |
//+------------------------------------------------------------------+
class CSignalFilterPipeline
  {
private:
   const CSignalConfig *m_config;
   CArrayObj            m_customFilters;
   string               m_currentFilterReason;

public:
   CSignalFilterPipeline() : m_config(NULL), m_currentFilterReason("") {}

   void Init(const CSignalConfig &config) { m_config = &config; }

   void AddCustomFilter(IFilter *filter)
     {
      if(filter != NULL) m_customFilters.Add(filter);
     }

   string GetCurrentReason() const { return m_currentFilterReason; }

   //--- Filter 1: Zone Touch
   bool PassZoneTouchFilter(int shift, int dir, double zonePrice,
                            double atrPoints, double dynamicMult,
                            FilterResult &result, const MqlRates &rates[])
     {
      m_currentFilterReason = "";
      if(m_config == NULL) { result.Reject("ZoneTouch","Config not initialized"); return false; }

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

   //--- Filter 2: Context / Momentum
   bool PassContextFilter(int shift, double atrPoints, FilterResult &result,
                          const MqlRates &rates[], int dir)
     {
      m_currentFilterReason = "";
      if(m_config == NULL) { result.Reject("Context","Config not initialized"); return false; }

      double o = rates[shift].open,  h = rates[shift].high;
      double l = rates[shift].low,   c = rates[shift].close;
      double range = h - l;
      double body  = MathAbs(o - c);

      if(range > m_config.GetMaxSignalATR() * atrPoints * _Point)
        {
         result.Reject("Context","Signal too large");
         m_currentFilterReason = "Signal too large";
         return false;
        }

      if(range > 0 && (body / range) > m_config.GetAntiBreakoutPct())
        {
         result.Reject("Context","Body too long");
         m_currentFilterReason = "Body too long";
         return false;
        }

      double threshold = atrPoints * m_config.GetMomentumThresholdATR() * _Point;
      int    pushCount = 0;
      int    sz        = ArraySize(rates);

      for(int i = 1; i <= 3 && (shift + i + 1) < sz; i++)
        {
         double curO  = rates[shift+i].open,  curC  = rates[shift+i].close;
         double curH  = rates[shift+i].high,  curL  = rates[shift+i].low;
         double prevH = rates[shift+i+1].high, prevL = rates[shift+i+1].low;
         double curBody = MathAbs(curO - curC);

         bool isPush = (dir == 1) ?
                       (curH < prevH || (curC < curO && curBody > threshold)) :
                       (curL > prevL || (curC > curO && curBody > threshold));
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

   //--- Filter 3: MTF Quality
   // BUG-S10-003 FIX: referencePrice = signalPrice (not rates[shift].close)
   bool PassMTFFilter(int dir, double referencePrice,
                      double htfSupport, double htfResistance,
                      double atrPoints, int &bias, FilterResult &result)
     {
      m_currentFilterReason = "";
      if(m_config == NULL) { result.Reject("MTF","Config not initialized"); return false; }

      bias = 0;
      if(m_config.GetUseMTF())
        {
         double zone          = (atrPoints * m_config.GetATRBufferMult()) * _Point;
         bool nearHtfSupport  = (referencePrice <= htfSupport    + zone);
         bool nearHtfResist   = (referencePrice >= htfResistance - zone);

         if(nearHtfSupport  && !nearHtfResist)  bias =  1;
         else if(nearHtfResist && !nearHtfSupport) bias = -1;
        }

      if(!m_config.GetUseMTF()) return true;

      int qualityScore = dir * bias;
      if(qualityScore >= 0)
        {
         result.passed = true;
         result.reason = (qualityScore == 1) ?
                         "High Quality Signal (MTF Aligned)" :
                         "Standard Quality Signal (MTF Neutral)";
         return true;
        }

      result.Reject("MTF","Low Quality (Blocked by MTF Contra-Bias)");
      m_currentFilterReason = "Low Quality (Blocked by MTF Contra-Bias)";
      return false;
     }

   //--- Filter 4: Opportunity / R:R
   // BUG-S10-001 FIX: receive explicit zonePrice + oppositeZone instead of bare
   // `support`/`resistance` symbols that were undefined in calling scope.
   bool PassOpportunityFilter(int dir, double atrPoints,
                              double zonePrice, double oppositeZone,
                              double signalPrice, FilterResult &result)
     {
      m_currentFilterReason = "";
      if(m_config == NULL) { result.Reject("Opportunity","Config not initialized"); return false; }

      // target = the zone on the opposite side of the trade
      double target     = oppositeZone;
      double profitDist = (dir == 1) ? (target - signalPrice) : (signalPrice - target);
      double minTPDist  = (atrPoints * m_config.GetMinTPDistanceATR()) * _Point;

      if(profitDist < minTPDist)
        {
         result.Reject("Opportunity","TP distance < Min ATR");
         m_currentFilterReason = "TP distance < Min ATR";
         return false;
        }
      return true;
     }

   //--- Run Complete Pipeline
   // BUG-S10-001 FIX: receive support + resistance explicitly; resolve to
   //   zonePrice / oppositeZone based on direction before calling filters.
   // BUG-S10-002 FIX: RunCustomFilters() now called as final pass.
   // BUG-S10-003 FIX: signalPrice passed to MTF filter (was rates[shift].close).
   bool RunCompletePipeline(int shift, int dir, double zonePrice,
                            double signalPrice, double atrPoints,
                            double htfSupport, double htfResistance,
                            double dynamicMult,
                            double support, double resistance,   // BUG-S10-001 FIX
                            FilterResult &result,
                            const MqlRates &rates[])
     {
      result.Clear();

      // Resolve opposite-zone for R:R check
      double oppositeZone = (dir == 1) ? resistance : support;

      // 1. Zone Touch Filter
      if(!PassZoneTouchFilter(shift, dir, zonePrice, atrPoints, dynamicMult, result, rates))
         return false;

      // 2. Context / Momentum Filter
      if(!PassContextFilter(shift, atrPoints, result, rates, dir))
         return false;

      // 3. MTF Quality Filter — BUG-S10-003: use signalPrice not rates[].close
      int bias = 0;
      if(!PassMTFFilter(dir, signalPrice, htfSupport, htfResistance, atrPoints, bias, result))
         return false;

      // 4. Opportunity / R:R Filter — BUG-S10-001: pass resolved oppositeZone
      if(!PassOpportunityFilter(dir, atrPoints, zonePrice, oppositeZone, signalPrice, result))
         return false;

      // 5. Custom Filters — BUG-S10-002: was never called before
      ENUM_SIGNAL_DIR sigDir = (dir == 1) ? SIGNAL_BUY : SIGNAL_SELL;
      if(!RunCustomFilters(shift, rates, atrPoints, sigDir, result))
         return false;

      result.passed = true;
      result.reason = "All filters passed";
      return true;
     }

   //--- Run Custom Filters
   bool RunCustomFilters(int shift, const MqlRates &rates[], double atrPoints,
                         ENUM_SIGNAL_DIR dir, FilterResult &result)
     {
      for(int i = 0; i < m_customFilters.Total(); i++)
        {
         IFilter *filter = (IFilter*)m_customFilters.At(i);
         if(filter != NULL && !filter.Apply(shift, rates, atrPoints, dir, result))
            return false;
        }
      result.passed = true;
      return true;
     }
  };

#endif // __SIGNAL_FILTER_PIPELINE_MQH__
