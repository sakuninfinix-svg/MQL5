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

   double PipToPoints(const double pips) const
     {
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double factor = (digits == 3 || digits == 5) ? 10.0 : 1.0;
      return MathMax(0.0, pips) * factor;
     }

   bool CheckSpread(LegacyFilterResult &r) const
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(ask <= 0.0 || bid <= 0.0)
        {
         r.passed = false;
         r.reason = "Spread:invalid";
         return false;
        }

      double spreadPts = (ask - bid) / _Point;
      double maxSpreadPts = PipToPoints(m_cfg.Market.SpreadFilterPips);
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
       int dow = dt.day_of_week;  // 0=Sun .. 6=Sat
       if(dow < 0 || dow > 6) return true;
       DaySession sess = m_cfg.Market.Sessions[dow];
      if(!sess.Active)
        {
         r.passed = false;
         r.reason = "OutOfSession";
         return false;
        }
      int nowMin = dt.hour * 60 + dt.min;
      int startMin = MathMax(0, MathMin(1439, sess.StartMinutes));
      int endMin   = MathMax(0, MathMin(1439, sess.EndMinutes));
      if(startMin <= endMin)
        {
         if(nowMin < startMin || nowMin > endMin)
           {
            r.passed = false;
            r.reason = "OutOfSession";
            return false;
           }
        }
      else
        {
         // Wrap-around (e.g., 22:00-06:00)
         if(nowMin > endMin && nowMin < startMin)
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
