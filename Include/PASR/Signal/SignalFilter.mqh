//+------------------------------------------------------------------+
//| Signal/SignalFilter.mqh — v1.02                                  |
//| Legacy pre-signal filter chain, compile-safe adapter              |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_FILTER_MQH__
#define __SIGNAL_FILTER_MQH__

#include "../Core/IManager.mqh"

struct LegacyFilterResult
  {
   bool   passed;
   string reason;
   void Clear() { passed = true; reason = "OK"; }
  };

class CSignalFilter
  {
private:
   StrategyConfig  m_cfg;
   IDataManager   *m_data;

   bool CheckSpread(LegacyFilterResult &r) const
     {
      double spreadPts = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      double maxSpreadPts = m_cfg.Market.SpreadFilterPips * 10.0;
      if(maxSpreadPts > 0.0 && spreadPts > maxSpreadPts)
        {
         r.passed = false;
         r.reason = "Spread:" + DoubleToString(spreadPts, 1);
         return false;
        }
      return true;
     }

   bool CheckATR(LegacyFilterResult &r) const
     {
      double atr = (m_data != NULL) ? m_data.GetATRPoints() : 0.0;
      if(atr <= 0.0)
        {
         r.passed = true;
         r.reason = "ATR neutral";
         return true;
        }
      return true;
     }

   bool CheckSession(LegacyFilterResult &r) const
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int startHour = m_cfg.Market.SessionStartHour;
      int endHour = m_cfg.Market.SessionEndHour;
      if(startHour <= endHour)
        {
         if(dt.hour < startHour || dt.hour > endHour)
           {
            r.passed = false;
            r.reason = "OutOfSession";
            return false;
           }
        }
      else
        {
         if(dt.hour < startHour && dt.hour > endHour)
           {
            r.passed = false;
            r.reason = "OutOfSession";
            return false;
           }
        }
      return true;
     }

public:
   CSignalFilter(const StrategyConfig &cfg, IDataManager *data)
      : m_cfg(cfg), m_data(data) {}

   LegacyFilterResult Run() const
     {
      LegacyFilterResult r;
      r.Clear();
      if(!CheckSpread(r))  return r;
      if(!CheckATR(r))     return r;
      if(!CheckSession(r)) return r;
      return r;
     }
  };

#endif
