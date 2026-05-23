//+------------------------------------------------------------------+
//| Signal/SignalFilterPipeline.mqh — v1.00                          |
//| Modular filter pipeline for signal validation                    |
//|                                                                  |
//| PURPOSE:                                                         |
//|   - Execute sequential filter checks on potential signals        |
//|   - Each filter can reject a signal with a specific reason       |
//|   - Supports custom filters via IFilter interface                |
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
      passed = true; 
      reason = "OK"; 
      filterName = "";
     }
     
   void Reject(const string &filter, const string &reason)
     {
      passed = false;
      filterName = filter;
      this.reason = reason;
     }
  };

//+------------------------------------------------------------------+
//| IFilter - Interface for custom filters                           |
//+------------------------------------------------------------------+
class IFilter
  {
public:
   virtual string Name() = 0;
   virtual bool   Apply(int shift, const MqlRates &rates, double atrPoints,
                        ENUM_SIGNAL_DIR dir, FilterResult &result) = 0;
  };

//+------------------------------------------------------------------+
//| CSignalFilterPipeline - Main filter pipeline                     |
//+------------------------------------------------------------------+
class CSignalFilterPipeline
  {
private:
   const CSignalConfig *m_config;
   CArrayObj m_customFilters;
   
   // Filter state
   string m_currentFilterReason;
   
public:
   //+------------------------------------------------------------------+
   //| Constructor                                                      |
   //+------------------------------------------------------------------+
   CSignalFilterPipeline() : m_config(NULL), m_currentFilterReason("")
     {
     }
   
   //+------------------------------------------------------------------+
   //| Initialize with config                                           |
   //+------------------------------------------------------------------+
   void Init(const CSignalConfig &config)
     {
      m_config = &config;
     }
   
   //+------------------------------------------------------------------+
   //| Add custom filter                                                |
   //+------------------------------------------------------------------+
   void AddCustomFilter(IFilter *filter)
     {
      if(filter != NULL)
        {
         m_customFilters.Add(filter);
        }
     }
   
   //+------------------------------------------------------------------+
   //| Get current filter reason                                        |
   //+------------------------------------------------------------------+
   string GetCurrentReason() const
     {
      return m_currentFilterReason;
     }
   
   //+------------------------------------------------------------------+
   //| Filter 1: Zone Touch Filter                                      |
   //| Checks if price touched the zone within tolerance                |
   //+------------------------------------------------------------------+
   bool PassZoneTouchFilter(int shift, int dir, double zonePrice,
                           double atrPoints, double dynamicMult,
                           FilterResult &result, const MqlRates &rates)
     {
      m_currentFilterReason = "";
      
      if(m_config == NULL)
        {
         result.Reject("ZoneTouch", "Config not initialized");
         return false;
        }
      
      double extreme = (dir == 1) ? rates[shift].low : rates[shift].high;
      double zoneWidth = (atrPoints * dynamicMult) * _Point;
      double multiplier = (m_config->GetEntryMode() == MODE_SAFE) ? 0.5 : 1.0;
      
      bool ok = (dir == 1) ?
                (extreme <= zonePrice + (zoneWidth * multiplier)) :
                (extreme >= zonePrice - (zoneWidth * multiplier));
      
      if(!ok)
        {
         result.Reject("ZoneTouch", "Not touching zone");
         m_currentFilterReason = "Not touching zone";
         return false;
        }
      
      return true;
     }
   
   //+------------------------------------------------------------------+
   //| Filter 2: Context/Momentum Filter                                |
   //| Validates candle context and momentum into zone                  |
   //+------------------------------------------------------------------+
   bool PassContextFilter(int shift, double atrPoints, FilterResult &result,
                         const MqlRates &rates, int dir)
     {
      m_currentFilterReason = "";
      
      if(m_config == NULL)
        {
         result.Reject("Context", "Config not initialized");
         return false;
        }
      
      double o = rates[shift].open, h = rates[shift].high;
      double l = rates[shift].low, c = rates[shift].close;
      double range = h - l;
      double body = MathAbs(o - c);
      
      // Check max candle size
      if(range > m_config->GetMaxSignalATR() * atrPoints * _Point)
        {
         result.Reject("Context", "Signal too large");
         m_currentFilterReason = "Signal too large";
         return false;
        }
      
      // Check anti-breakout ratio
      if(range > 0 && (body / range) > m_config->GetAntiBreakoutPct())
        {
         result.Reject("Context", "Body too long");
         m_currentFilterReason = "Body too long";
         return false;
        }
      
      // Filter Momentum: Check 1-3 previous candles
      double threshold = atrPoints * m_config->GetMomentumThresholdATR() * _Point;
      int pushCount = 0;
      
      for(int i = 1; i <= 3 && (shift + i) < ArraySize(rates); i++)
        {
         double curO = rates[shift + i].open, curC = rates[shift + i].close;
         double curH = rates[shift + i].high, curL = rates[shift + i].low;
         double prevH = rates[shift + i + 1].high, prevL = rates[shift + i + 1].low;
         double curBody = MathAbs(curO - curC);
         
         bool isPush = (dir == 1) ?
                      (curH < prevH || (curC < curO && curBody > threshold)) :
                      (curL > prevL || (curC > curO && curBody > threshold));
         
         if(isPush) 
           pushCount++;
         else 
           break;
        }
      
      if(pushCount < 1)
        {
         result.Reject("Context", "No momentum push to zone");
         m_currentFilterReason = "No momentum push to zone";
         return false;
        }
      
      return true;
     }
   
   //+------------------------------------------------------------------+
   //| Filter 3: MTF Quality Filter                                     |
   //| Checks Higher Timeframe alignment                                |
   //+------------------------------------------------------------------+
   bool PassMTFFilter(int dir, double referencePrice,
                     double htfSupport, double htfResistance,
                     double atrPoints, int &bias, FilterResult &result)
     {
      m_currentFilterReason = "";
      
      if(m_config == NULL)
        {
         result.Reject("MTF", "Config not initialized");
         return false;
        }
      
      // Calculate MTF bias
      bias = 0;
      if(m_config->GetUseMTF())
        {
         double zone = (atrPoints * m_config->GetATRBufferMult()) * _Point;
         bool nearHtfSupport = (referencePrice <= htfSupport + zone);
         bool nearHtfResistance = (referencePrice >= htfResistance - zone);
         
         if(nearHtfSupport && !nearHtfResistance) 
           bias = 1;
         else if(nearHtfResistance && !nearHtfSupport) 
           bias = -1;
        }
      
      if(!m_config->GetUseMTF()) 
        {
         return true; // MTF disabled, always pass
        }
      
      int qualityScore = dir * bias;
      
      if(qualityScore == 1)
        {
         result.passed = true;
         result.reason = "High Quality Signal (MTF Aligned)";
         return true;
        }
      
      if(qualityScore == 0)
        {
         result.passed = true;
         result.reason = "Standard Quality Signal (MTF Neutral)";
         return true;
        }
      
      result.Reject("MTF", "Low Quality (Blocked by MTF Contra-Bias)");
      m_currentFilterReason = "Low Quality (Blocked by MTF Contra-Bias)";
      return false;
     }
   
   //+------------------------------------------------------------------+
   //| Filter 4: Opportunity/R:R Filter                                 |
   //| Validates minimum profit distance                                |
   //+------------------------------------------------------------------+
   bool PassOpportunityFilter(int dir, int shift, double atrPoints,
                             double support, double resistance,
                             double signalPrice, FilterResult &result,
                             const MqlRates &rates)
     {
      m_currentFilterReason = "";
      
      if(m_config == NULL)
        {
         result.Reject("Opportunity", "Config not initialized");
         return false;
        }
      
      double target = (dir == 1) ? resistance : support;
      double profitDist = (dir == 1) ? (target - signalPrice) : (signalPrice - target);
      
      double minTPDist = (atrPoints * m_config->GetMinTPDistanceATR()) * _Point;
      
      if(profitDist < minTPDist)
        {
         result.Reject("Opportunity", "TP distance < Min ATR");
         m_currentFilterReason = "TP distance < Min ATR";
         return false;
        }
      
      return true;
     }
   
   //+------------------------------------------------------------------+
   //| Run Complete Filter Pipeline                                     |
   //| Executes all filters in sequence                                 |
   //+------------------------------------------------------------------+
   bool RunCompletePipeline(int shift, int dir, double zonePrice,
                           double signalPrice, double atrPoints,
                           double htfSupport, double htfResistance,
                           double dynamicMult, FilterResult &result,
                           const MqlRates &rates)
     {
      result.Clear();
      
      // 1. Zone Touch Filter
      if(!PassZoneTouchFilter(shift, dir, zonePrice, atrPoints, 
                              dynamicMult, result, rates))
        return false;
      
      // 2. Context/Momentum Filter
      if(!PassContextFilter(shift, atrPoints, result, rates, dir))
        return false;
      
      // 3. MTF Quality Filter
      int bias = 0;
      if(!PassMTFFilter(dir, rates[shift].close, htfSupport, htfResistance,
                       atrPoints, bias, result))
        return false;
      
      // 4. Opportunity/R:R Filter
      if(!PassOpportunityFilter(dir, shift, atrPoints, support, resistance,
                               signalPrice, result, rates))
        return false;
      
      // All filters passed
      result.passed = true;
      result.reason = "All filters passed";
      return true;
     }
   
   //+------------------------------------------------------------------+
   //| Run Custom Filters                                               |
   //| Executes any registered custom filters                           |
   //+------------------------------------------------------------------+
   bool RunCustomFilters(int shift, const MqlRates &rates, double atrPoints,
                        ENUM_SIGNAL_DIR dir, FilterResult &result)
     {
      for(int i = 0; i < m_customFilters.Total(); i++)
        {
         IFilter *filter = (IFilter*)m_customFilters.At(i);
         if(filter != NULL)
           {
            if(!filter.Apply(shift, rates, atrPoints, dir, result))
              {
               return false;
              }
           }
        }
      
      result.passed = true;
      return true;
     }
  };

#endif // __SIGNAL_FILTER_PIPELINE_MQH__
