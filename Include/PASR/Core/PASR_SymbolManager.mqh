//+------------------------------------------------------------------+
//| Core/PASR_SymbolManager.mqh — v8.01                              |
//| Multi-Symbol Manager with Correlation Control & Load Balancing    |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_SYMBOL_MANAGER_MQH__
#define __PASR_SYMBOL_MANAGER_MQH__

// <Collections/List.mqh> is not required for this implementation.

struct CSymbolData
  {
   string                  symbol;
   bool                    active;
   bool                    enabled;
   datetime                last_tick_time;
   datetime                last_bar_time;
   double                  current_price;
   double                  spread;
   double                  point;
   int                     digits;
   double                  volume_min;
   double                  volume_max;
   double                  volume_step;
   ENUM_ORDER_TYPE_FILLING filling_mode;
   long                    tick_count;
   long                    bar_count;
   double                  avg_tick_latency;
   double                  max_tick_latency;
   double                  correlation_matrix[];

   CSymbolData()
     {
      symbol = "";
      active = false;
      enabled = true;
      last_tick_time = 0;
      last_bar_time = 0;
      current_price = 0.0;
      spread = 0.0;
      point = 0.0;
      digits = 0;
      volume_min = 0.0;
      volume_max = 0.0;
      volume_step = 0.0;
      filling_mode = ORDER_FILLING_FOK;
      tick_count = 0;
      bar_count = 0;
      avg_tick_latency = 0.0;
      max_tick_latency = 0.0;
      ArrayResize(correlation_matrix, 0);
     }
  };

class CSymbolManager
  {
private:
   CSymbolData       m_symbols[];
   int               m_symbol_count;
   int               m_active_count;
   string            m_base_currency;
   int               m_current_index;
   datetime          m_last_rebalance;
   int               m_rebalance_interval;
   double            m_max_correlation;
   bool              m_correlation_enabled;
   long              m_total_ticks;
   long              m_total_bars;

public:
   CSymbolManager()
      : m_symbol_count(0), m_active_count(0), m_base_currency("USD"),
        m_current_index(0), m_last_rebalance(TimeCurrent()),
        m_rebalance_interval(60), m_max_correlation(0.85),
        m_correlation_enabled(true), m_total_ticks(0), m_total_bars(0)
     {
      ArrayResize(m_symbols, 100);
     }

   ~CSymbolManager()
     {
      for(int i = 0; i < m_symbol_count; i++) ArrayFree(m_symbols[i].correlation_matrix);
     }

   bool Initialize(const string &symbols_list[], const int count,
                   const double max_corr = 0.85, const bool enable_corr = true)
     {
      if(count <= 0 || count > 100)
        {
         Print("ERROR: Invalid symbol count: ", count);
         return false;
        }

      m_max_correlation = MathMax(0.1, MathMin(1.0, max_corr));
      m_correlation_enabled = enable_corr;
      m_symbol_count = 0;

      for(int i = 0; i < count; i++)
        {
         string sym = symbols_list[i];
         if(!SymbolSelect(sym, true))
           {
            Print("WARNING: Cannot select symbol: ", sym);
            continue;
           }

         CSymbolData &sd = m_symbols[m_symbol_count];
         sd = CSymbolData();
         sd.symbol = sym;
         sd.enabled = true;
         sd.active = true;
         sd.point = SymbolInfoDouble(sym, SYMBOL_POINT);
         sd.digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
         sd.volume_min = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
         sd.volume_max = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
         sd.volume_step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);

         long fill_flags = SymbolInfoInteger(sym, SYMBOL_FILLING_MODE);
         if((fill_flags & SYMBOL_FILLING_FOK) != 0) sd.filling_mode = ORDER_FILLING_FOK;
         else if((fill_flags & SYMBOL_FILLING_IOC) != 0) sd.filling_mode = ORDER_FILLING_IOC;
         else sd.filling_mode = ORDER_FILLING_RETURN;

         ArrayResize(sd.correlation_matrix, count);
         ArrayInitialize(sd.correlation_matrix, 0.0);
         m_symbol_count++;
        }

      m_active_count = m_symbol_count;
      Print("SymbolManager initialized with ", m_symbol_count, " symbols");
      return (m_symbol_count > 0);
     }

   bool UpdateTick(const string symbol, const double bid, const double ask, const datetime tick_time)
     {
      int idx = FindSymbol(symbol);
      if(idx < 0) return false;

      CSymbolData &sd = m_symbols[idx];
      datetime now = TimeCurrent();
      double latency = (sd.last_tick_time > 0) ? (double)(now - sd.last_tick_time) : 0.0;

      sd.tick_count++;
      m_total_ticks++;
      if(sd.avg_tick_latency == 0.0) sd.avg_tick_latency = latency;
      else sd.avg_tick_latency = (sd.avg_tick_latency * (sd.tick_count - 1) + latency) / sd.tick_count;
      sd.max_tick_latency = MathMax(sd.max_tick_latency, latency);
      sd.current_price = (ask > 0.0) ? ask : bid;
      sd.spread = (ask > 0.0 && bid > 0.0 && sd.point > 0.0) ? (ask - bid) / sd.point : 0.0;
      sd.last_tick_time = tick_time;
      return true;
     }

   bool UpdateBar(const string symbol, const datetime bar_time)
     {
      int idx = FindSymbol(symbol);
      if(idx < 0) return false;
      CSymbolData &sd = m_symbols[idx];
      if(bar_time > sd.last_bar_time)
        {
         sd.bar_count++;
         m_total_bars++;
         sd.last_bar_time = bar_time;
         return true;
        }
      return false;
     }

   bool IsNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe)
     {
      datetime current_bar = iTime(symbol, timeframe, 0);
      int idx = FindSymbol(symbol);
      if(idx < 0 || current_bar <= 0) return false;
      CSymbolData &sd = m_symbols[idx];
      if(current_bar > sd.last_bar_time)
        {
         sd.last_bar_time = current_bar;
         return true;
        }
      return false;
     }

   string GetNextSymbol()
     {
      if(m_active_count == 0) return "";
      int attempts = 0;
      while(attempts < m_symbol_count)
        {
         m_current_index = (m_current_index + 1) % m_symbol_count;
         CSymbolData &sd = m_symbols[m_current_index];
         if(sd.active && sd.enabled) return sd.symbol;
         attempts++;
        }
      return "";
     }

   bool CanOpenPosition(const string symbol)
     {
      if(!m_correlation_enabled) return true;
      int idx = FindSymbol(symbol);
      if(idx < 0) return false;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
         string pos_symbol = PositionGetString(POSITION_SYMBOL);
         if(pos_symbol == symbol) continue;

         double corr = GetCorrelation(symbol, pos_symbol);
         if(MathAbs(corr) > m_max_correlation)
           {
            Print("CORRELATION BLOCK: ", symbol, " vs ", pos_symbol, " (", corr, ")");
            return false;
           }
        }
      return true;
     }

   double GetCorrelation(const string symbol1, const string symbol2)
     {
      int idx1 = FindSymbol(symbol1);
      int idx2 = FindSymbol(symbol2);
      if(idx1 < 0 || idx2 < 0) return 0.0;
      return m_symbols[idx1].correlation_matrix[idx2];
     }

   void UpdateCorrelations(const int lookback_bars = 100)
     {
      if(!m_correlation_enabled) return;
      for(int i = 0; i < m_symbol_count; i++)
        {
         for(int j = 0; j < m_symbol_count; j++)
           {
            if(i == j) m_symbols[i].correlation_matrix[j] = 1.0;
            else m_symbols[i].correlation_matrix[j] = CalculateSymbolCorrelation(m_symbols[i].symbol, m_symbols[j].symbol, lookback_bars);
           }
        }
     }

   void Rebalance()
     {
      datetime now = TimeCurrent();
      if(now - m_last_rebalance < m_rebalance_interval) return;
      m_last_rebalance = now;
      m_active_count = 0;

      for(int i = 0; i < m_symbol_count; i++)
        {
         CSymbolData &sd = m_symbols[i];
         if(!SymbolSelect(sd.symbol, true))
           {
            sd.active = false;
            continue;
           }

         long tradeMode = SymbolInfoInteger(sd.symbol, SYMBOL_TRADE_MODE);
         if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
           {
            sd.active = false;
            continue;
           }

         if(sd.avg_tick_latency > 1.0)
            Print("WARNING: High latency for ", sd.symbol, ": ", sd.avg_tick_latency, "s");

         if(sd.active && sd.enabled) m_active_count++;
        }

      Print("Rebalanced: ", m_active_count, "/", m_symbol_count, " symbols active");
     }

   void GetStatistics(const string symbol, long &ticks, long &bars,
                      double &avg_lat, double &max_lat)
     {
      int idx = FindSymbol(symbol);
      if(idx < 0)
        {
         ticks = 0; bars = 0; avg_lat = 0.0; max_lat = 0.0;
         return;
        }
      CSymbolData &sd = m_symbols[idx];
      ticks = sd.tick_count;
      bars = sd.bar_count;
      avg_lat = sd.avg_tick_latency;
      max_lat = sd.max_tick_latency;
     }

   void GetTotalStatistics(long &total_ticks, long &total_bars, int &active_symbols)
     {
      total_ticks = m_total_ticks;
      total_bars = m_total_bars;
      active_symbols = m_active_count;
     }

   bool GetSymbolData(const string symbol, CSymbolData &out)
     {
      int idx = FindSymbol(symbol);
      if(idx < 0) return false;
      out = m_symbols[idx];
      return true;
     }

   int GetActiveCount() const { return m_active_count; }
   int GetTotalCount() const { return m_symbol_count; }

   bool SetSymbolEnabled(const string symbol, const bool enabled)
     {
      int idx = FindSymbol(symbol);
      if(idx < 0) return false;
      m_symbols[idx].enabled = enabled;
      if(!enabled) m_symbols[idx].active = false;
      return true;
     }

private:
   int FindSymbol(const string symbol)
     {
      for(int i = 0; i < m_symbol_count; i++)
         if(m_symbols[i].symbol == symbol) return i;
      return -1;
     }

   double CalculateSymbolCorrelation(const string sym1, const string sym2, const int bars)
     {
      // Placeholder: real correlation should use CopyClose() returns.
      return 0.0;
     }
  };

#endif // __PASR_SYMBOL_MANAGER_MQH__
