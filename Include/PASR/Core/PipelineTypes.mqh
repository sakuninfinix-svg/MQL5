//+------------------------------------------------------------------+
//| Core/PipelineTypes.mqh — v1.02 (Stage Timeout)                   |
//| Shared types, enums, and PipelineContext for CPipelineEngine      |
//|                                                                   |
//| CHANGELOG:                                                        |
//|   v1.02 (2026-05-23) — Sprint 4:                                 |
//|     - Added STAGE_TIMEOUT to ENUM_STAGE_RESULT                   |
//|     - Added STAGE_TIMEOUT_US constant (50ms default)             |
//|     - Added positions_count cache field to PipelineContext        |
//|   v1.01 — PipelineContext with exec_result.ticket field          |
//|   v1.00 — Initial pipeline types                                 |
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_PIPELINE_TYPES_MQH__
#define __CORE_PIPELINE_TYPES_MQH__

#include "PASR.Types.mqh"
#include "Events.mqh"

//--- Stage timeout: abort any stage exceeding this (microseconds)
#define STAGE_TIMEOUT_US   50000   // 50ms hard limit per stage

//+------------------------------------------------------------------+
//| Stage execution result codes                                     |
//+------------------------------------------------------------------+
enum ENUM_STAGE_RESULT
  {
   STAGE_OK      = 0,   // Stage completed successfully
   STAGE_SKIP    = 1,   // Stage skipped (manager NULL or condition not met)
   STAGE_WARN    = 2,   // Stage completed with non-fatal warning
   STAGE_FAIL    = 3,   // Stage failed, pipeline should abort this cycle
   STAGE_TIMEOUT = 4    // Stage exceeded STAGE_TIMEOUT_US — watchdog abort
  };

//+------------------------------------------------------------------+
//| Execution result (filled by Stage_Execution)                     |
//+------------------------------------------------------------------+
struct SExecResult
  {
   bool              executed;      // Was an order sent?
   ulong             ticket;        // Order ticket (0 if not executed)
   double            fill_price;    // Actual fill price
   double            slippage_pts;  // Slippage in points
   int               retcode;       // MT5 return code
   string            comment;       // Debug comment

               SExecResult() : executed(false), ticket(0),
                               fill_price(0.0), slippage_pts(0.0),
                               retcode(0), comment("") {}
  };

//+------------------------------------------------------------------+
//| Risk check result (filled by Stage_RiskCheck)                    |
//+------------------------------------------------------------------+
struct SRiskResult
  {
   bool              allowed;       // Is trade allowed?
   double            lot_size;      // Computed lot size
   double            sl_price;      // Computed SL
   double            tp_price;      // Computed TP
   string            block_reason;  // If !allowed, why

               SRiskResult() : allowed(false), lot_size(0.0),
                               sl_price(0.0), tp_price(0.0), block_reason("") {}
  };

//+------------------------------------------------------------------+
//| AI inference result (filled by Stage_AIInference)                |
//+------------------------------------------------------------------+
struct SAIResult
  {
   double            score;         // AI confidence [-1.0 .. +1.0]
   double            drift_index;   // Model drift indicator [0..1]
   bool              model_healthy; // False = drift too high, skip AI
   string            model_name;    // Which model was used

               SAIResult() : score(0.0), drift_index(0.0),
                             model_healthy(true), model_name("") {}
  };

//+------------------------------------------------------------------+
//| Pipeline execution context — shared state across all stages      |
//+------------------------------------------------------------------+
struct PipelineContext
  {
   // ---- Tick data (filled by Stage_DataSync) ----
   double            bid;
   double            ask;
   double            spread_pts;
   double            atr;           // Current ATR value
   datetime          bar_time;      // Time of last closed bar
   bool              new_bar;       // True = bar boundary crossed

   // ---- Signal (filled by Stage_SignalGen) ----
   ENUM_SIGNAL_TYPE  signal;        // SIGNAL_BUY / SIGNAL_SELL / SIGNAL_NONE
   double            signal_strength; // Confluence score [0..1]

   // ---- Regime (filled by Stage_RegimeDet) ----
   ENUM_MARKET_REGIME regime;
   double            regime_confidence;

   // ---- Trade plan (filled by Stage_AdaptiveParams) ----
   struct STradePlan
     {
      ENUM_SIGNAL_TYPE direction;
      double           entryPrice;
      double           sl;
      double           tp;
      double           lot;
     } plan;

   // ---- Risk result (filled by Stage_RiskCheck) ----
   SRiskResult       risk_result;

   // ---- AI result (filled by Stage_AIInference) ----
   SAIResult         ai_result;

   // ---- Execution result (filled by Stage_Execution) ----
   SExecResult       exec_result;

   // ---- Position cache (filled by Stage_PositionMgmt) ----
   // Sprint 4: cache PositionsTotal() once per cycle to avoid
   // redundant MT5 terminal API calls across Stage_Recovery etc.
   int               positions_count; // Cached result of PositionsTotal()
   ulong             position_ticket; // First open position matching magic

   // ---- Cycle metadata ----
   datetime          cycle_start_time;
   int               stages_executed;
   int               stages_skipped;
   int               stages_failed;
   int               stages_timeout;  // Sprint 4: count watchdog triggers

               PipelineContext() :
                  bid(0), ask(0), spread_pts(0), atr(0),
                  bar_time(0), new_bar(false),
                  signal(SIGNAL_NONE), signal_strength(0),
                  regime(REGIME_UNKNOWN), regime_confidence(0),
                  positions_count(-1), position_ticket(0),
                  cycle_start_time(0),
                  stages_executed(0), stages_skipped(0),
                  stages_failed(0), stages_timeout(0)
                { ZeroMemory(plan); }
  };

//+------------------------------------------------------------------+
//| Stage profiling record (one per stage per cycle)                 |
//+------------------------------------------------------------------+
struct SStageMetric
  {
   string            name;           // Stage name
   ulong             elapsed_us;     // Execution time in microseconds
   ENUM_STAGE_RESULT result;         // Stage outcome
   bool              timed_out;      // True if watchdog triggered
  };

#endif // __CORE_PIPELINE_TYPES_MQH__
