//+------------------------------------------------------------------+
//| Signal/SignalFilter.mqh — v1.00                                  |
//| Pre-signal filter chain: spread, ATR, session, regime            |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_FILTER_MQH__
#define __SIGNAL_FILTER_MQH__

#include "../Core/IManager.mqh"

struct FilterResult
  {
   bool   passed;
   string reason; // which filter rejected or "OK"
   void Clear() { passed=true; reason="OK"; }
  };

class CSignalFilter
  {
private:
   const StrategyConfig *m_cfg;
   IDataManager         *m_data;

   bool CheckSpread(FilterResult &r) const
     {
      double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
      double maxSpread = m_cfg.Signal.MaxSpreadPoints * _Point;
      if(maxSpread > 0 && spread > maxSpread)
        { r.passed=false; r.reason="Spread:"+DoubleToString(spread/_Point,1); return false; }
      return true;
     }

   bool CheckATR(FilterResult &r) const
     {
      double atr = m_data.GetATRPoints();
      if(m_cfg.Signal.MinATRPoints > 0 && atr < m_cfg.Signal.MinATRPoints)
        { r.passed=false; r.reason="LowATR:"+DoubleToString(atr,1); return false; }
      return true;
     }

   bool CheckSession(FilterResult &r) const
     {
      if(!m_cfg.Signal.UseSessionFilter) return true;
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int hm = dt.hour * 100 + dt.min;
      // Default: allow London (0700-1600) + NY (1300-2200) overlap
      if(hm < 700 || hm > 2200)
        { r.passed=false; r.reason="OutOfSession"; return false; }
      return true;
     }

public:
   CSignalFilter(const StrategyConfig *cfg, IDataManager *data)
      : m_cfg(cfg), m_data(data) {}

   FilterResult Run() const
     {
      FilterResult r; r.Clear();
      if(!CheckSpread(r))  return r;
      if(!CheckATR(r))     return r;
      if(!CheckSession(r)) return r;
      return r;
     }
  };

#endif
