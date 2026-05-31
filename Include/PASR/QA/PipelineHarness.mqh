//+------------------------------------------------------------------+
//| QA/PipelineHarness.mqh — v1.00                                   |
//| Sprint 6 — S6-003: Full pipeline cycle runner for MQL5 Scripts  |
//|                                                                   |
//| PURPOSE:                                                          |
//|   Run a complete PASR pipeline cycle (all 14 stages) from        |
//|   an MQL5 Script without needing a live EA/terminal connection.  |
//|   Uses MockEventBus + MockDataManager for isolation.             |
//|                                                                   |
//| TYPICAL SCRIPT USAGE:                                            |
//|   #include <PASR/QA/PipelineHarness.mqh>                        |
//|                                                                   |
//|   void OnStart()                                                 |
//|   {                                                               |
//|     CPipelineHarness h;                                          |
//|     h.LoadScenario_Trending();   // inject synthetic bullish bars |
//|     h.RunCycles(50);             // simulate 50 bar events        |
//|     h.PrintReport();             // Experts tab summary           |
//|     ASSERT_TRUE(h.PassRate() > 0.95, "95%% stage pass rate");    |
//|   }                                                               |
//|                                                                   |
//| RESULT ACCESSORS:                                                 |
//|   h.PassRate()         — 0.0..1.0                                |
//|   h.TimeoutCount()     — stages that exceeded 50ms               |
//|   h.CycleCount()       — total pipeline cycles run               |
//|   h.GetStageStats(i)   — per-stage pass/fail/timeout counts      |
//+------------------------------------------------------------------+
#property strict
#ifndef __QA_PIPELINE_HARNESS_MQH__
#define __QA_PIPELINE_HARNESS_MQH__

#include "MockEventBus.mqh"
#include "MockDataManager.mqh"
#include "AssertHelpers.mqh"
#include "../Core/PipelineTypes.mqh"
#include "../Core/PipelineEngine.mqh"

#define HARNESS_MAX_STAGES   16
#define HARNESS_MAX_CYCLES  512

//--- Per-stage statistics
struct SStageStats
  {
   string   name;
   int      pass_count;
   int      fail_count;
   int      skip_count;
   int      timeout_count;
   ulong    total_us;       // Total microseconds
   ulong    max_us;         // Worst case
  };

//--- Harness-level result
struct SHarnessResult
  {
   int      cycles_run;
   int      cycles_ok;      // All 14 stages STAGE_OK
   int      cycles_partial; // Some stages STAGE_SKIP
   int      cycles_failed;  // Any stage STAGE_FAIL
   int      total_timeouts;
   double   pass_rate;      // cycles_ok / cycles_run
   ulong    avg_cycle_us;   // Average cycle time
   ulong    max_cycle_us;   // Worst cycle
  };

//+------------------------------------------------------------------+
//| CPipelineHarness — Isolated pipeline test driver                 |
//+------------------------------------------------------------------+
class CPipelineHarness
  {
private:
   CMockEventBus     *m_bus;
   CMockDataManager  *m_data;
   CPipelineEngine   *m_engine;

   SStageStats        m_stage_stats[HARNESS_MAX_STAGES];
   SHarnessResult     m_result;
   int                m_stage_count;
   bool               m_initialized;

   //--- Accumulate stage result into stats
   void RecordStageResult(int stage_idx, ENUM_STAGE_RESULT res, ulong us)
     {
      if(stage_idx < 0 || stage_idx >= HARNESS_MAX_STAGES) return;
      SStageStats &s = m_stage_stats[stage_idx];
      s.total_us += us;
      if(us > s.max_us) s.max_us = us;
      switch(res)
        {
         case STAGE_OK:      s.pass_count++;    break;
         case STAGE_SKIP:    s.skip_count++;    break;
         case STAGE_FAIL:    s.fail_count++;    break;
         case STAGE_TIMEOUT: s.timeout_count++; m_result.total_timeouts++; break;
        }
     }

public:
              CPipelineHarness()
     : m_bus(NULL), m_data(NULL), m_engine(NULL),
       m_stage_count(0), m_initialized(false)
     {
      ZeroMemory(m_result);
      ZeroMemory(m_stage_stats);
     }

              ~CPipelineHarness()
     {
      if(m_engine) { delete m_engine; m_engine = NULL; }
      if(m_data)   { delete m_data;   m_data   = NULL; }
      if(m_bus)    { delete m_bus;    m_bus    = NULL; }
     }

   //--- Setup -------------------------------------------------------
   bool Initialize()
     {
      m_bus    = new CMockEventBus(false); // record-only mode
      m_data   = new CMockDataManager();
      m_engine = new CPipelineEngine();

      if(!m_engine.InitializeWithMocks(m_bus, m_data))
        {
         Print("[Harness] ERROR: CPipelineEngine.InitializeWithMocks() failed");
         return false;
        }

      m_initialized = true;
      m_stage_count = m_engine.GetStageCount();

      // Label stages
      for(int i = 0; i < m_stage_count && i < HARNESS_MAX_STAGES; i++)
         m_stage_stats[i].name = m_engine.GetStageName(i);

      return true;
     }

   //--- Built-in Scenarios ------------------------------------------

   //--- 50-bar bullish trending scenario
   void LoadScenario_Trending()
     {
      if(!m_initialized && !Initialize()) return;
      m_data.Reset();
      double base = 1.08500;
      for(int i = 0; i < 50; i++)
        {
         double o = base + i * 0.00010;
         double c = o + 0.00008;
         MqlRates bar = CMockDataManager::BuildBar(
                          o, c + 0.00005, o - 0.00003, c,
                          (datetime)(1700000000 + i * 3600));
         m_data.InjectBars(bar, 1);
         // Corresponding tick for each bar
         MqlTick t = CMockDataManager::BuildTick(
                       c - _Point, c + _Point,
                       (datetime)(1700000000 + i * 3600 + 3500));
         m_data.InjectTick(t);
        }
     }

   //--- 50-bar ranging scenario
   void LoadScenario_Ranging()
     {
      if(!m_initialized && !Initialize()) return;
      m_data.Reset();
      double mid = 1.08500;
      for(int i = 0; i < 50; i++)
        {
         double noise = (i % 2 == 0) ? 0.00015 : -0.00015;
         double o = mid + noise;
         double c = mid - noise * 0.5;
         MqlRates bar = CMockDataManager::BuildBar(
                          o, o + 0.00020, c - 0.00020, c,
                          (datetime)(1700000000 + i * 3600));
         m_data.InjectBars(bar, 1);
         MqlTick t = CMockDataManager::BuildTick(
                       c - _Point, c + _Point,
                       (datetime)(1700000000 + i * 3600 + 3500));
         m_data.InjectTick(t);
        }
     }

   //--- Run n pipeline cycles (one cycle = one bar event)
   bool RunCycles(int n_cycles)
     {
      if(!m_initialized && !Initialize()) return false;

      int cycles = MathMin(n_cycles, m_data.BarsInjected());
      m_result.cycles_run = 0;

      for(int c = 0; c < cycles; c++)
        {
         if(!m_data.PlayNextBar()) break;

         PipelineContext ctx;
         ZeroMemory(ctx);
         ctx.new_bar   = true;
         ctx.bar_time  = m_data.m_current_bar.time;
         ctx.bid       = m_data.m_current_bar.close - _Point;
         ctx.ask       = m_data.m_current_bar.close + _Point;
         ctx.atr       = 0.00080; // synthetic ATR

         ulong t_start = GetMicrosecondCount();
         bool all_ok   = true;
         bool any_fail = false;

         for(int s = 0; s < m_engine.GetStageCount(); s++)
           {
            ulong ts = GetMicrosecondCount();
            ENUM_STAGE_RESULT res = m_engine.RunStage(s, ctx);
            ulong elapsed = GetMicrosecondCount() - ts;

            RecordStageResult(s, res, elapsed);
            if(res == STAGE_FAIL)    any_fail = true;
            if(res != STAGE_OK)      all_ok   = false;
           }

         ulong cycle_us = GetMicrosecondCount() - t_start;
         if(cycle_us > m_result.max_cycle_us) m_result.max_cycle_us = cycle_us;
         m_result.avg_cycle_us += cycle_us;
         m_result.cycles_run++;

         if(any_fail)   m_result.cycles_failed++;
         else if(all_ok) m_result.cycles_ok++;
         else            m_result.cycles_partial++;

         m_bus.Reset(); // clear event history after each cycle
        }

      if(m_result.cycles_run > 0)
         m_result.avg_cycle_us /= m_result.cycles_run;

      m_result.pass_rate = (m_result.cycles_run > 0)
                           ? (double)m_result.cycles_ok / m_result.cycles_run
                           : 0.0;
      return true;
     }

   //--- Print detailed report to Experts tab
   void PrintReport()
     {
      Print("===== PipelineHarness Report =====");
      PrintFormat("  Cycles run  : %d", m_result.cycles_run);
      PrintFormat("  All OK      : %d (%.1f%%)",
                  m_result.cycles_ok, m_result.pass_rate * 100);
      PrintFormat("  Partial     : %d", m_result.cycles_partial);
      PrintFormat("  Failed      : %d", m_result.cycles_failed);
      PrintFormat("  Timeouts    : %d", m_result.total_timeouts);
      PrintFormat("  Avg cycle   : %I64u us", m_result.avg_cycle_us);
      PrintFormat("  Worst cycle : %I64u us", m_result.max_cycle_us);
      Print("--- Stage Breakdown ---");
      for(int i = 0; i < m_stage_count && i < HARNESS_MAX_STAGES; i++)
        {
         SStageStats &s = m_stage_stats[i];
         ulong avg_us = s.pass_count + s.skip_count > 0
                        ? s.total_us / (s.pass_count + s.skip_count) : 0;
         PrintFormat("  [%02d] %-24s  OK:%d  SKIP:%d  FAIL:%d  TIMEOUT:%d  avg:%I64uus",
                     i, s.name, s.pass_count, s.skip_count,
                     s.fail_count, s.timeout_count, avg_us);
        }
      Print("=================================");
     }

   //--- Result accessors
   double   PassRate()     const { return m_result.pass_rate;      }
   int      TimeoutCount() const { return m_result.total_timeouts; }
   int      CycleCount()   const { return m_result.cycles_run;     }
   int      FailedCycles() const { return m_result.cycles_failed;  }

   bool     GetStageStats(int i, SStageStats &out) const
     {
      if(i < 0 || i >= m_stage_count) return false;
      out = m_stage_stats[i];
      return true;
     }

   CMockEventBus    *GetBus()  { return m_bus;  }
   CMockDataManager *GetData() { return m_data; }
  };

#endif // __QA_PIPELINE_HARNESS_MQH__
