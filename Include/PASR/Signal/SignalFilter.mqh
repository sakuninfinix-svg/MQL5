//+------------------------------------------------------------------+
//| Signal/SignalFilter.mqh — v1.01                                  |
//| Legacy pre-signal filter chain                                    |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_FILTER_MQH__
#define __SIGNAL_FILTER_MQH__

#include "../Core/IManager.mqh"

struct LegacyFilterResult
  {
   bool   passed;
   string reason;
   void Clear() { passed=true; reason="OK"; }
  };

class CSignalFilter
  {
private:
   StrategyConfig  m_cfg;
   IDataManager   *m_data;

   bool CheckSpread(LegacyFilterResult &r) const
     {
      double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
      double maxSpread = m_cfg.Signal.MaxSpreadPoints * _Point;
      if(maxSpread > 0 && spread > maxSpread)
        { r.passed=false; r.reason="Spread:"+DoubleToString(spread/_Point,1); return false; }
      return true;
     }

   bool CheckATR(LegacyFilterResult &r) const
     {
      double atr = (m_data != NULL) ? m_data.GetATRPoints() : 0.0;
      if(m_cfg.Signal.MinATRPoints > 0 && atr < m_cfg.Signal.MinATRPoints)
        { r.passed=false; r.reason="LowATR:"+DoubleToString(atr,1); return false; }
      return true;
     }

   bool CheckSession(LegacyFilterResult &r) const
     {
      if(!m_cfg.Signal.UseSessionFilter) return true;
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int hm = dt.hour * 100 + dt.min;
      if(hm < 700 || hm > 2200)
        { r.passed=false; r.reason="OutOfSession"; return false; }
      return true;
     }

public:
   CSignalFilter(const StrategyConfig &cfg, IDataManager *data)
      : m_cfg(cfg), m_data(data) {}

   LegacyFilterResult Run() const
     {
      LegacyFilterResult r; r.Clear();
      if(!CheckSpread(r))  return r;
      if(!CheckATR(r))     return r;
      if(!CheckSession(r)) return r;
      return r;
     }
  };

#endif
