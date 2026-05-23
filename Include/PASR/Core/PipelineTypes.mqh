//+------------------------------------------------------------------+
//| Core/PipelineTypes.mqh — v1.03 (Sprint 7 — State Ownership)     |
//| Shared types, enums, and PipelineContext for CPipelineEngine     |
//|                                                                  |
//| CHANGELOG:                                                       |
//|   v1.03 (2026-05-23) Sprint 7:                                  |
//|     - S7-004: Added health_status to PipelineContext             |
//|       Pipeline can now abort/skip stages if EA is unhealthy      |
//|     - S7-007: Added plan_locked flag — write-once guard for plan |
//|       Stage_AdaptiveParams sets true; Stage_RiskCheck reads only |
//|     - Added session_dd + daily_pnl fields (from SessionState)    |
//|   v1.02 (2026-05-23) Sprint 4:                                  |
//|     - Added STAGE_TIMEOUT, positions_count                       |
//|   v1.01 — exec_result.ticket                                    |
//|   v1.00 — Initial                                                |
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_PIPELINE_TYPES_MQH__
#define __CORE_PIPELINE_TYPES_MQH__

#include "PASR.Types.mqh"
#include "Events.mqh"

#define STAGE_TIMEOUT_US   50000

enum ENUM_STAGE_RESULT
  {
   STAGE_OK      = 0,
   STAGE_SKIP    = 1,
   STAGE_WARN    = 2,
   STAGE_FAIL    = 3,
   STAGE_TIMEOUT = 4
  };

struct SExecResult
  {
   bool              executed;
   ulong             ticket;
   double            fill_price;
   double            slippage_pts;
   int               retcode;
   string            comment;
                     SExecResult() : executed(false), ticket(0), fill_price(0), slippage_pts(0), retcode(0), comment("") {}
  };

struct SRiskResult
  {
   bool              allowed;
   double            lot_size;
   double            sl_price;
   double            tp_price;
   string            block_reason;
                     SRiskResult() : allowed(false), lot_size(0), sl_price(0), tp_price(0), block_reason("") {}
  };

struct SAIResult
  {
   double            score;
   double            drift_index;
   bool              model_healthy;
   string            model_name;
                     SAIResult() : score(0), drift_index(0), model_healthy(true), model_name("") {}
  };

//+------------------------------------------------------------------+
//| PipelineContext — WRITE RULES (Sprint 7 ownership contract):     |
//|   bid/ask/atr/new_bar  → Stage_DataSync ONLY                     |
//|   signal/strength      → Stage_SignalGen ONLY                    |
//|   regime/confidence    → Stage_RegimeDet ONLY                    |
//|   plan.*               → Stage_AdaptiveParams → sets plan_locked |
//|   risk_result.*        → Stage_RiskCheck ONLY (reads plan)       |
//|   ai_result.*          → Stage_AIInference ONLY                  |
//|   exec_result.*        → Stage_Execution ONLY                    |
//|   positions_count      → Stage_PositionMgmt ONLY                 |
//|   health_status        → Orchestrator BEFORE stage loop starts   |
//|   session_dd/daily_pnl → Orchestrator BEFORE stage loop starts   |
//+------------------------------------------------------------------+
struct PipelineContext
  {
   double            bid;
   double            ask;
   double            spread_pts;
   double            atr;
   datetime          bar_time;
   bool              new_bar;

   ENUM_SIGNAL_TYPE  signal;
   double            signal_strength;

   ENUM_MARKET_REGIME regime;
   double            regime_confidence;

   struct STradePlan
     {
      ENUM_SIGNAL_TYPE direction;
      double           entryPrice;
      double           sl;
      double           tp;
      double           lot;
     } plan;

   bool              plan_locked;     // S7-007: true after Stage_AdaptiveParams writes

   SRiskResult       risk_result;
   SAIResult         ai_result;
   SExecResult       exec_result;

   int               positions_count;
   ulong             position_ticket;

   int               health_status;   // S7-004: 0=OK,1=WARN,2=CRIT,3=DEAD
   double            session_dd;      // Current DD % from CSessionState
   double            daily_pnl;       // Daily PnL from CSessionState

   datetime          cycle_start_time;
   int               stages_executed;
   int               stages_skipped;
   int               stages_failed;
   int               stages_timeout;

                     PipelineContext() :
                        bid(0), ask(0), spread_pts(0), atr(0),
                        bar_time(0), new_bar(false),
                        signal(SIGNAL_NONE), signal_strength(0),
                        regime(REGIME_UNKNOWN), regime_confidence(0),
                        plan_locked(false),
                        positions_count(-1), position_ticket(0),
                        health_status(0), session_dd(0), daily_pnl(0),
                        cycle_start_time(0),
                        stages_executed(0), stages_skipped(0),
                        stages_failed(0), stages_timeout(0)
                      { ZeroMemory(plan); }
  };

struct SStageMetric
  {
   string            name;
   ulong             elapsed_us;
   ENUM_STAGE_RESULT result;
   bool              timed_out;
  };

#endif // __CORE_PIPELINE_TYPES_MQH__
