//+------------------------------------------------------------------+
//| QA/MockDataManager.mqh — v1.00                                   |
//| Sprint 6 — S6-002: Tick replay injector for deterministic tests  |
//|                                                                   |
//| PURPOSE:                                                          |
//|   Feed synthetic MqlTick[] and MqlRates[] into the pipeline      |
//|   without requiring a live MT5 terminal connection.              |
//|   Enables fully deterministic, reproducible pipeline tests.      |
//|                                                                   |
//| USAGE:                                                            |
//|   CMockDataManager dm;                                           |
//|   dm.InjectTick(tick1);                                          |
//|   dm.InjectTick(tick2);                                          |
//|   while(dm.PlayNext())   // advance through injected ticks       |
//|     { ... pipeline.RunCycle() ... }                              |
//|                                                                   |
//| TICK BUILDER helper:                                             |
//|   MqlTick t = CMockDataManager::BuildTick(bid, ask, time);      |
//+------------------------------------------------------------------+
#property strict
#ifndef __QA_MOCK_DATA_MANAGER_MQH__
#define __QA_MOCK_DATA_MANAGER_MQH__

#include "../Infra/DataManager.mqh"

#define MOCK_DM_MAX_TICKS   4096
#define MOCK_DM_MAX_BARS    1024

//+------------------------------------------------------------------+
//| CMockDataManager — Synthetic tick/bar replay                     |
//+------------------------------------------------------------------+
class CMockDataManager : public CDataManager
  {
private:
   MqlTick       m_ticks[MOCK_DM_MAX_TICKS];
   int           m_tick_count;
   int           m_tick_cursor;

   MqlRates      m_bars[MOCK_DM_MAX_BARS];
   int           m_bar_count;
   int           m_bar_cursor;

   bool          m_replay_done;

public:
              CMockDataManager()
     : m_tick_count(0), m_tick_cursor(0),
       m_bar_count(0),  m_bar_cursor(0),
       m_replay_done(false)
     {}

   //--- Inject API --------------------------------------------------

   //--- Push single tick into replay buffer
   bool InjectTick(const MqlTick &tick)
     {
      if(m_tick_count >= MOCK_DM_MAX_TICKS) return false;
      m_ticks[m_tick_count++] = tick;
      return true;
     }

   //--- Push array of ticks (bulk)
   int  InjectTicks(const MqlTick &ticks[], int count)
     {
      int injected = 0;
      for(int i = 0; i < count && m_tick_count < MOCK_DM_MAX_TICKS; i++)
        {
         m_ticks[m_tick_count++] = ticks[i];
         injected++;
        }
      return injected;
     }

   //--- Push OHLCV bar array
   int  InjectBars(const MqlRates &bars[], int count)
     {
      int injected = 0;
      for(int i = 0; i < count && m_bar_count < MOCK_DM_MAX_BARS; i++)
        {
         m_bars[m_bar_count++] = bars[i];
         injected++;
        }
      return injected;
     }

   //--- Static helpers: build synthetic ticks / bars ---------------

   static MqlTick BuildTick(double bid, double ask, datetime t = 0,
                             double last = 0.0, ulong volume = 1)
     {
      MqlTick tick  = {};
      tick.bid      = bid;
      tick.ask      = ask;
      tick.last     = last > 0 ? last : (bid + ask) * 0.5;
      tick.volume   = volume;
      tick.time     = t > 0 ? t : TimeCurrent();
      return tick;
     }

   static MqlRates BuildBar(double o, double h, double l, double c,
                             datetime t = 0, long volume = 1000)
     {
      MqlRates r  = {};
      r.open      = o;
      r.high      = h;
      r.low       = l;
      r.close     = c;
      r.tick_volume = volume;
      r.time      = t > 0 ? t : TimeCurrent();
      return r;
     }

   //--- Replay control ----------------------------------------------

   //--- Advance to next injected tick.
   //    Returns false when all ticks consumed.
   bool PlayNext()
     {
      if(m_tick_cursor >= m_tick_count)
        {
         m_replay_done = true;
         return false;
        }
      // Expose current tick as "live" data for pipeline
      m_current_tick  = m_ticks[m_tick_cursor];
      m_tick_cursor++;
      return true;
     }

   //--- Advance to next bar (for new bar event simulation)
   bool PlayNextBar()
     {
      if(m_bar_cursor >= m_bar_count) return false;
      m_current_bar = m_bars[m_bar_cursor];
      m_bar_cursor++;
      return true;
     }

   //--- Reset replay to beginning (keep injected data)
   void Rewind()
     {
      m_tick_cursor = 0;
      m_bar_cursor  = 0;
      m_replay_done = false;
     }

   //--- Full reset: clear all injected data
   void Reset()
     {
      m_tick_count  = 0;
      m_tick_cursor = 0;
      m_bar_count   = 0;
      m_bar_cursor  = 0;
      m_replay_done = false;
     }

   //--- Accessors
   int  TicksInjected()  const { return m_tick_count;  }
   int  BarsInjected()   const { return m_bar_count;   }
   int  TicksCursor()    const { return m_tick_cursor; }
   bool IsReplayDone()   const { return m_replay_done; }
   int  TicksRemaining() const { return m_tick_count - m_tick_cursor; }

   //--- Current tick/bar exposed to pipeline (set by PlayNext)
   MqlTick   m_current_tick;
   MqlRates  m_current_bar;
  };

#endif // __QA_MOCK_DATA_MANAGER_MQH__
