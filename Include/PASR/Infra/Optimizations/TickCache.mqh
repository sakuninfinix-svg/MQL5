//+------------------------------------------------------------------+
//| Infra/Optimizations/TickCache.mqh — High-Performance Tick Filter |
//+------------------------------------------------------------------+
#property strict
#ifndef TOOLS_TICK_CACHE_MQH
#define TOOLS_TICK_CACHE_MQH

class CTickCache
  {
private:
   MqlTick  m_last_tick;
   string   m_symbol;
   bool     m_initialized;
   ulong    m_hit_count;
   ulong    m_miss_count;
   datetime m_last_bar_time;
   double   m_prev_bid;
   double   m_prev_ask;
   ulong    m_prev_volume;
   datetime m_prev_time;

public:
   CTickCache()
      : m_symbol(""), m_initialized(false), m_hit_count(0), m_miss_count(0),
        m_last_bar_time(0), m_prev_bid(0.0), m_prev_ask(0.0),
        m_prev_volume(0), m_prev_time(0)
     {
      ZeroMemory(m_last_tick);
     }

   bool Init(const string symbol = "")
     {
      if(m_initialized) return true;
      m_symbol = (symbol == "") ? _Symbol : symbol;
      if(!SymbolInfoTick(m_symbol, m_last_tick))
        {
         Print("[TickCache][ERROR] Failed to get initial tick for ", m_symbol);
         return false;
        }
      m_prev_bid = m_last_tick.bid;
      m_prev_ask = m_last_tick.ask;
      m_prev_volume = m_last_tick.volume;
      m_prev_time = m_last_tick.time;
      m_last_bar_time = 0;
      m_initialized = true;
      return true;
     }

   bool Update()
     {
      if(!m_initialized)
        {
         if(!Init()) return true;
        }

      MqlTick current_tick;
      if(!SymbolInfoTick(m_symbol, current_tick))
         return true;

      bool is_duplicate = (current_tick.time == m_prev_time &&
                           MathAbs(current_tick.bid - m_prev_bid) < _Point / 10.0 &&
                           MathAbs(current_tick.ask - m_prev_ask) < _Point / 10.0 &&
                           current_tick.volume == m_prev_volume);
      if(is_duplicate)
        {
         m_hit_count++;
         return false;
        }

      m_miss_count++;
      m_last_tick = current_tick;
      m_prev_bid = current_tick.bid;
      m_prev_ask = current_tick.ask;
      m_prev_volume = current_tick.volume;
      m_prev_time = current_tick.time;
      return true;
     }

   void GetLastTick(MqlTick &out) const
     {
      out = m_last_tick;
     }

   bool HasPriceChange(double threshold = 1.0) const
     {
      if(!m_initialized) return false;
      double price_change = MathAbs(m_last_tick.bid - m_prev_bid);
      return (price_change >= threshold * _Point);
     }

   bool HasVolumeChange() const
     {
      if(!m_initialized) return false;
      return (m_last_tick.volume != m_prev_volume);
     }

   bool IsNewBar(ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT) const
     {
      if(!m_initialized) return false;
      datetime times[];
      ArraySetAsSeries(times, true);
      if(CopyTime(m_symbol, timeframe, 0, 2, times) <= 0)
         return false;
      return (times[0] != m_last_bar_time);
     }

   void MarkBarSeen()
     {
      datetime times[];
      ArraySetAsSeries(times, true);
      if(CopyTime(m_symbol, PERIOD_CURRENT, 0, 1, times) > 0)
         m_last_bar_time = times[0];
     }

   ulong GetHitCount() const { return m_hit_count; }
   ulong GetMissCount() const { return m_miss_count; }

   double GetHitRate() const
     {
      ulong total = m_hit_count + m_miss_count;
      if(total == 0) return 0.0;
      return (double)m_hit_count / (double)total * 100.0;
     }

   void ResetStats()
     {
      m_hit_count = 0;
      m_miss_count = 0;
      m_last_bar_time = 0;
     }

   bool IsInitialized() const { return m_initialized; }
   string GetSymbol() const { return m_symbol; }

   void PrintStats() const
     {
      Print("[TickCache] Symbol: ", m_symbol,
            ", Hits: ", m_hit_count,
            ", Misses: ", m_miss_count,
            ", Hit Rate: ", DoubleToString(GetHitRate(), 2), "%");
     }
  };

#endif // TOOLS_TICK_CACHE_MQH
