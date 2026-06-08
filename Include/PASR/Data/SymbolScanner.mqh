//+------------------------------------------------------------------+
//| Data/SymbolScanner.mqh — Multi-Symbol Scanner                    |
//| Copyright 2026, Agsicentre                                       |
//+------------------------------------------------------------------+
#property strict
#ifndef DATA_SYMBOL_SCANNER_MQH
#define DATA_SYMBOL_SCANNER_MQH

#include "../Core/IManager.mqh"
#include "../Infra/TickCache.mqh"

//+------------------------------------------------------------------+
//| Symbol info structure                                            |
//+------------------------------------------------------------------+
struct SymbolInfoEx
  {
   string            name;
   long              digits;
   double            point;
   double            spread;
   double            min_lot;
   double            max_lot;
   double            lot_step;
   bool              trade_allowed;
   datetime          last_tick_time;
   bool              is_active;

   void Reset()
     {
      name = "";
      digits = 0;
      point = 0.0;
      spread = 0.0;
      min_lot = 0.0;
      max_lot = 0.0;
      lot_step = 0.0;
      trade_allowed = false;
      last_tick_time = 0;
      is_active = false;
     }

   SymbolInfoEx()
     {
      Reset();
     }
  };

//+------------------------------------------------------------------+
//| Symbol filter criteria                                           |
//+------------------------------------------------------------------+
struct SymbolFilterCriteria
  {
   double            max_spread_pts;
   double            min_volume;
   bool              check_session;
   int               session_start_hour;
   int               session_end_hour;

   void Reset()
     {
      max_spread_pts = 30.0;
      min_volume = 0.0;
      check_session = false;
      session_start_hour = 0;
      session_end_hour = 24;
     }

   SymbolFilterCriteria()
     {
      Reset();
     }
  };

//+------------------------------------------------------------------+
//| CSymbolScanner — Multi-symbol scanning engine                    |
//+------------------------------------------------------------------+
class CSymbolScanner : public IManager
  {
private:
   SymbolInfoEx          m_symbols[];
   CTickCache            m_tick_caches[];
   int                   m_symbol_count;
   SymbolFilterCriteria  m_filter;
   int                   m_current_index;
   datetime              m_last_scan_time;
   int                   m_scans_completed;
   ulong                 m_ticks_processed;
   ulong                 m_ticks_filtered;

   bool IsWithinSession(int hour) const
     {
      if(!m_filter.check_session) return true;
      int start = m_filter.session_start_hour;
      int end   = m_filter.session_end_hour;
      if(start <= end)
         return (hour >= start && hour < end);
      return (hour >= start || hour < end);
     }

   bool RefreshSymbolInfo(int idx)
     {
      if(idx < 0 || idx >= m_symbol_count) return false;
      string sym = m_symbols[idx].name;
      if(sym == "") return false;

      m_symbols[idx].digits        = SymbolInfoInteger(sym, SYMBOL_DIGITS);
      m_symbols[idx].point         = SymbolInfoDouble(sym, SYMBOL_POINT);
      m_symbols[idx].min_lot       = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      m_symbols[idx].max_lot       = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
      m_symbols[idx].lot_step      = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
      m_symbols[idx].trade_allowed = (SymbolInfoInteger(sym, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_DISABLED);

      long spread_long = SymbolInfoInteger(sym, SYMBOL_SPREAD);
      m_symbols[idx].spread = (spread_long > 0) ? (double)spread_long : 0.0;
      m_symbols[idx].last_tick_time = TimeCurrent();

      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      m_symbols[idx].is_active = IsWithinSession(dt.hour);
      return true;
     }

public:
   CSymbolScanner()
      : IManager(), m_symbol_count(0), m_current_index(0),
        m_last_scan_time(0), m_scans_completed(0),
        m_ticks_processed(0), m_ticks_filtered(0)
     {}

   ~CSymbolScanner()
     {
      Deinit();
     }

   virtual string HandlerName() const override { return "SymbolScanner"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      return InitFromConfig();
     }

   virtual void Deinit() override
     {
      ArrayResize(m_symbols, 0);
      ArrayResize(m_tick_caches, 0);
      m_symbol_count = 0;
      IManager::Deinit();
     }

   bool InitSymbols(const string &symbols[], int count)
     {
      if(count <= 0 || count > 100)
        {
         Print("[SymbolScanner][ERROR] Invalid symbol count: ", count);
         return false;
        }

      if(ArrayResize(m_symbols, count) != count)
        {
         Print("[SymbolScanner][ERROR] Failed to allocate symbol array");
         return false;
        }

      if(ArrayResize(m_tick_caches, count) != count)
        {
         Print("[SymbolScanner][ERROR] Failed to allocate tick cache array");
         ArrayResize(m_symbols, 0);
         return false;
        }

      for(int i = 0; i < count; i++)
        {
         m_symbols[i].Reset();
         m_symbols[i].name = symbols[i];
         if(!m_tick_caches[i].Init(symbols[i]))
            Print("[SymbolScanner][WARN] TickCache init failed for ", symbols[i]);
         RefreshSymbolInfo(i);
        }

      m_symbol_count = count;
      m_current_index = 0;
      Print("[SymbolScanner][INFO] Initialized with ", m_symbol_count, " symbols");
      return true;
     }

   bool InitFromConfig()
     {
      string symbols[];
      ArrayResize(symbols, 1);
      symbols[0] = _Symbol;
      return InitSymbols(symbols, ArraySize(symbols));
     }

   void SetFilter(const SymbolFilterCriteria &criteria)
     {
      m_filter = criteria;
      Print("[SymbolScanner][INFO] Filter updated: max_spread=", criteria.max_spread_pts, " pts");
     }

   SymbolFilterCriteria GetFilter() const
     {
      return m_filter;
     }

   int ScanNext()
     {
      if(m_symbol_count <= 0) return -1;
      int start_idx = m_current_index;

      do
        {
         int idx = m_current_index;
         m_current_index = (m_current_index + 1) % m_symbol_count;

         if(m_current_index == 0)
           {
            m_last_scan_time = TimeCurrent();
            m_scans_completed++;
           }

         if(!RefreshSymbolInfo(idx)) continue;
         if(!PassesFilter(idx)) continue;

         if(!m_tick_caches[idx].Update())
           {
            m_ticks_filtered++;
            continue;
           }

         m_ticks_processed++;
         return idx;
        }
      while(m_current_index != start_idx);

      return -1;
     }

   bool PassesFilter(int idx) const
     {
      if(idx < 0 || idx >= m_symbol_count) return false;
      if(!m_symbols[idx].trade_allowed) return false;
      if(!m_symbols[idx].is_active) return false;
      if(m_filter.max_spread_pts > 0.0 && m_symbols[idx].spread > m_filter.max_spread_pts)
         return false;
      return true;
     }

   bool GetSymbolInfo(int idx, SymbolInfoEx &out) const
     {
      if(idx < 0 || idx >= m_symbol_count) return false;
      out = m_symbols[idx];
      return true;
     }

   bool GetSymbolInfoByName(const string &name, SymbolInfoEx &out) const
     {
      for(int i = 0; i < m_symbol_count; i++)
        {
         if(m_symbols[i].name == name)
           {
            out = m_symbols[i];
            return true;
           }
        }
      return false;
     }

   bool GetTickCacheStats(int idx, ulong &hits, ulong &misses, double &hitRate) const
     {
      if(idx < 0 || idx >= m_symbol_count) return false;
      hits = m_tick_caches[idx].GetHitCount();
      misses = m_tick_caches[idx].GetMissCount();
      hitRate = m_tick_caches[idx].GetHitRate();
      return true;
     }

   int GetCurrentIndex() const { return m_current_index; }
   int GetSymbolCount() const { return m_symbol_count; }
   int GetScansCompleted() const { return m_scans_completed; }
   datetime GetLastScanTime() const { return m_last_scan_time; }

   ulong GenerateMagicNumber(ulong base_magic, int idx) const
     {
      if(idx < 0 || idx >= m_symbol_count) return base_magic;
      if(StringLen(m_symbols[idx].name) <= 0) return base_magic;

      uint hash = (uint)StringGetCharacter(m_symbols[idx].name, 0);
      for(int i = 1; i < StringLen(m_symbols[idx].name); i++)
         hash = hash * 31 + (uint)StringGetCharacter(m_symbols[idx].name, i);

      return (base_magic & 0xFFFF0000) | (hash & 0x0000FFFF);
     }

   void GetStats(ulong &processed, ulong &filtered, int &scans) const
     {
      processed = m_ticks_processed;
      filtered  = m_ticks_filtered;
      scans     = m_scans_completed;
     }

   void PrintStats() const
     {
      Print("[SymbolScanner] Symbols: ", m_symbol_count,
            ", Scans: ", m_scans_completed,
            ", Ticks Processed: ", m_ticks_processed,
            ", Ticks Filtered: ", m_ticks_filtered);

      for(int i = 0; i < m_symbol_count; i++)
         Print("  [", m_symbols[i].name, "] Spread: ", m_symbols[i].spread,
               " pts, Active: ", m_symbols[i].is_active);
     }

   void ResetStats()
     {
      m_ticks_processed = 0;
      m_ticks_filtered  = 0;
      m_scans_completed = 0;
      m_last_scan_time  = 0;
     }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_TICK);
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_PRICE_UPDATE);
     }

   virtual void OnPriceUpdate() override
     {
      ScanNext();
     }

   virtual void OnNewBar() override
     {
      for(int i = 0; i < m_symbol_count; i++)
         RefreshSymbolInfo(i);
     }

   virtual void OnEvent(const PASREvent &ev) override
     {
      switch(ev.id)
        {
         case EVENT_ID_TICK:
         case EVENT_ID_PRICE_UPDATE:
            OnPriceUpdate();
            break;
         case EVENT_ID_NEW_BAR:
            OnNewBar();
            break;
         default:
            break;
        }
     }
  };

#endif // DATA_SYMBOL_SCANNER_MQH
