//+------------------------------------------------------------------+
//| Core/PipelineTypes.mqh — CANONICAL v1.00                         |
//| Pipeline architecture types for staged processing                |
//|                                                                  |
//| PURPOSE: Define pipeline stages, context passing, profiling      |
//|                                                                  |
//| ARCHITECTURE:                                                    |
//|   • Stage enum for ordered execution                             |
//|   • PipelineContext for data flow between stages                 |
//|   • StageMetrics for per-stage performance tracking              |
//|   • PipelineResult for early-exit short-circuiting               |
//|                                                                  |
//| USAGE:                                                           |
//|   Replace monolithic OnTimer() with staged pipeline              |
//|   Each stage is independent, testable, profileable               |
//|                                                                  |
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_PIPELINE_TYPES_MQH__
#define __CORE_PIPELINE_TYPES_MQH__

#include "PASR.Types.mqh"

//+------------------------------------------------------------------+
//| Pipeline Stage Enum — Ordered execution phases                   |
//+------------------------------------------------------------------+
enum ENUM_PIPELINE_STAGE
  {
   STAGE_NONE          = 0,   // Invalid / not started
   STAGE_DATA_SYNC     = 1,   // Sync market data, update prices
   STAGE_ANALYSIS_SR   = 2,   // Update Support/Resistance zones
   STAGE_ANALYSIS_ZONE = 3,   // Update Supply/Demand zones
   STAGE_PATTERN_REC   = 4,   // Pattern recognition
   STAGE_REGIME_DET    = 5,   // Market regime detection
   STAGE_SIGNAL_GEN    = 6,   // Generate signals from all sources
   STAGE_AI_INFERENCE  = 7,   // AI scoring and veto
   STAGE_RISK_CHECK    = 8,   // Pre-trade risk gates
   STAGE_EXECUTION     = 9,   // Order execution
   STAGE_POSITION_MGMT = 10,  // Active position management (BE, trail)
   STAGE_RECOVERY      = 11,  // Recovery engine for fakeouts
   STAGE_DASHBOARD     = 12,  // UI updates
   STAGE_JOURNAL       = 13,  // Logging and metrics
   STAGE_COUNT         = 14   // Total stages (for loops)
  };

//+------------------------------------------------------------------+
//| Stage Execution Result                                           |
//+------------------------------------------------------------------+
enum ENUM_STAGE_RESULT
  {
   STAGE_OK            = 0,   // Continue to next stage
   STAGE_SKIP          = 1,   // Skip remaining stages (normal exit)
   STAGE_ABORT         = 2,   // Abort pipeline (error / circuit breaker)
   STAGE_RETRY         = 3    // Retry this stage (transient error)
  };

//+------------------------------------------------------------------+
//| Per-Stage Performance Metrics                                    |
//+------------------------------------------------------------------+
struct StageMetrics
  {
   ulong   stage_id;           // ENUM_PIPELINE_STAGE
   ulong   start_time_us;      // Start timestamp (microseconds)
   ulong   elapsed_us;         // Execution time (microseconds)
   bool    executed;           // Was stage executed this cycle?
   bool    skipped;            // Was stage skipped?
   bool    aborted;            // Did stage abort the pipeline?
   int     retry_count;        // Number of retries attempted
   
   void Reset()
     {
      stage_id = 0;
      start_time_us = 0;
      elapsed_us = 0;
      executed = false;
      skipped = false;
      aborted = false;
      retry_count = 0;
     }
     
   void Start()
     {
      start_time_us = GetMicrosecondCount();
      executed = true;
     }
     
   void Stop()
     {
      if(start_time_us > 0)
         elapsed_us = GetMicrosecondCount() - start_time_us;
     }
  };

//+------------------------------------------------------------------+
//| Pipeline-Wide Performance Report                                 |
//+------------------------------------------------------------------+
struct PipelineReport
  {
   StageMetrics  stage_metrics[STAGE_COUNT];
   ulong         total_elapsed_us;
   ulong         cycle_count;
   ulong         last_cycle_time;
   double        avg_cycle_time_ms;
   int           abort_count;
   int           skip_count;
   
   void Reset()
     {
      for(int i = 0; i < STAGE_COUNT; i++)
         stage_metrics[i].Reset();
      total_elapsed_us = 0;
      cycle_count = 0;
      last_cycle_time = 0;
      avg_cycle_time_ms = 0.0;
      abort_count = 0;
      skip_count = 0;
     }
     
   void RecordCycle(ulong elapsed_us, ENUM_STAGE_RESULT result)
     {
      cycle_count++;
      last_cycle_time = elapsed_us;
      
      // Running average (exponential moving average)
      double current_ms = elapsed_us / 1000.0;
      avg_cycle_time_ms = (avg_cycle_time_ms * 0.95) + (current_ms * 0.05);
      
      if(result == STAGE_ABORT) abort_count++;
      if(result == STAGE_SKIP)  skip_count++;
     }
     
   string ToString() const
     {
      string report = StringFormat("Pipeline Report [cycles=%d avg=%.2fms]\n",
                                   cycle_count, avg_cycle_time_ms);
      for(int i = 1; i < STAGE_COUNT; i++)
        {
         const StageMetrics &m = stage_metrics[i];
         if(m.executed || m.skipped)
           {
            string status = m.executed ? "EXEC" : (m.skipped ? "SKIP" : "----");
            report += StringFormat("  %-18s: %s %6dµs\n",
                                   EnumToString((ENUM_PIPELINE_STAGE)i),
                                   status, m.elapsed_us);
           }
        }
      return report;
     }
  };

//+------------------------------------------------------------------+
//| Pipeline Context — Data passed between stages                    |
//+------------------------------------------------------------------+
struct PipelineContext
  {
   // Input data (populated by early stages)
   datetime          bar_time;           // Current bar timestamp
   double            bid;                // Current bid price
   double            ask;                // Current ask price
   double            atr_points;         // ATR in points
   ENUM_MARKET_REGIME regime;            // Detected market regime
   ENUM_TRADING_SESSION session;         // Trading session
   
   // Signal data (populated by signal generation stage)
   FinalSignal       signal;             // Aggregated signal
   double            ai_score;           // AI confidence score
   double            drift_score;        // AI drift score
   bool              ai_veto;            // AI veto flag
   
   // Trade plan (populated by risk check stage)
   TradePlan         plan;               // Built trade plan
   RiskCheckResult   risk_result;        // Risk check result
   
   // Execution result (populated by execution stage)
   ExecResult        exec_result;        // Execution outcome
   
   // Position management state
   bool              has_position;       // Open position exists
   ulong             position_ticket;    // Active position ticket
   double            position_pnl;       // Floating P&L
   
   // Control flags
   bool              new_bar;            // New bar detected
   bool              market_open;        // Market is open
   bool              trading_allowed;    // Circuit breakers allow trading
   
   // Early-exit reason (for debugging)
   ENUM_STAGE_RESULT exit_reason;        // Why pipeline exited
   string            exit_message;       // Human-readable reason
   
   void Reset()
     {
      bar_time = 0;
      bid = 0;
      ask = 0;
      atr_points = 0;
      regime = REGIME_UNKNOWN;
      session = SESSION_OFF;
      ZeroMemory(signal);
      ai_score = 0.0;
      drift_score = 0.0;
      ai_veto = false;
      ZeroMemory(plan);
      ZeroMemory(risk_result);
      ZeroMemory(exec_result);
      has_position = false;
      position_ticket = 0;
      position_pnl = 0.0;
      new_bar = false;
      market_open = false;
      trading_allowed = true;
      exit_reason = STAGE_OK;
      exit_message = "";
     }
     
   bool ShouldContinue() const
     {
      return (exit_reason == STAGE_OK && trading_allowed);
     }
     
   void Abort(const string reason)
     {
      exit_reason = STAGE_ABORT;
      exit_message = reason;
      trading_allowed = false;
     }
     
   void Skip(const string reason)
     {
      exit_reason = STAGE_SKIP;
      exit_message = reason;
     }
  };

#endif // __CORE_PIPELINE_TYPES_MQH__
