//+------------------------------------------------------------------+
//| Core/PipelineTypes.mqh — v1.05 (Sprint 11 — BUG-N05 fix)       |
//| Shared types, enums, and PipelineContext for CPipelineEngine     |
//|                                                                  |
//| CHANGELOG:                                                       |
//|   v1.05 (2026-05-23) Sprint 11:                                  |
//|    BUG-N05: Added max_session_dd field to PipelineContext.       |
//|             ExecutePipeline SessionDD gate was hardcoded 5.0.    |
//|             Orchestrator::OnTimer() injects cfg value each cycle.|
//|             Reset() preserves max_session_dd (like health_status)|
//|   v1.04 (2026-05-23) Sprint 9 — 19 compile/runtime fixes:       |
//|    T1/T9:  SExecResult: added status (ENUM_EXEC_STATUS) field    |
//|    T2/T11: SRiskResult: added suggestedLot+reason aliases        |
//|    T3:     PipelineContext.signal changed to SSignal struct       |
//|    T4:     Added atr_points field (alias for atr in DataSync)     |
//|    T5:     Added market_open field                                |
//|    T6:     Added ai_score, drift_score, ai_veto scalars           |
//|    T7:     Added trading_allowed field                            |
//|    T8:     Added has_position, position_pnl fields               |
//|    T10:    Added exit_reason, exit_message fields                 |
//|    T12:    Added session (ENUM_TRADING_SESSION) field             |
//|    T13:    STradePlan: added slPoints, tpPoints, valid fields     |
//|    T14:    STAGE_ABORT added to ENUM_STAGE_RESULT                 |
//|    T15:    STAGE_COUNT defined as 15 (14 stages + NULL[0])       |
//|    T16:    StageMetrics + PipelineReport structs added            |
//|    T17:    PipelineContext.Reset() method added                   |
//|    T18:    PipelineContext.Abort()/Skip()/ShouldContinue() added  |
//|    T19:    DetectSession() free function added                    |
//|   v1.03 (2026-05-23) Sprint 7: health_status, plan_locked,       |
//|           session_dd, daily_pnl                                   |
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_PIPELINE_TYPES_MQH__
#define __CORE_PIPELINE_TYPES_MQH__

#include "PASR.Types.mqh"
#include "Events.mqh"

//+------------------------------------------------------------------+
//| Constants                                                        |
//+------------------------------------------------------------------+
#define STAGE_TIMEOUT_US   50000
#define STAGE_COUNT        15    // T15: indices 0..14 (0=NULL sentinel, 1..14=stages)

//+------------------------------------------------------------------+
//| Stage result enum                                                |
//+------------------------------------------------------------------+
enum ENUM_STAGE_RESULT
  {
   STAGE_OK      = 0,
   STAGE_SKIP    = 1,
   STAGE_WARN    = 2,
   STAGE_FAIL    = 3,
   STAGE_TIMEOUT = 4,
   STAGE_ABORT   = 5    // T14: hard abort — stop entire pipeline cycle
  };

//+------------------------------------------------------------------+
//| T9: Execution status enum (was missing — EXEC_OK was undefined)  |
//+------------------------------------------------------------------+
enum ENUM_EXEC_STATUS
  {
   EXEC_OK        = 0,
   EXEC_FAIL      = 1,
   EXEC_SKIP      = 2,
   EXEC_RETRYING  = 3
  };

//+------------------------------------------------------------------+
//| T12: Trading session enum                                        |
//+------------------------------------------------------------------+
enum ENUM_TRADING_SESSION
  {
   SESSION_UNKNOWN  = 0,
   SESSION_SYDNEY   = 1,
   SESSION_TOKYO    = 2,
   SESSION_LONDON   = 3,
   SESSION_NEW_YORK = 4,
   SESSION_OVERLAP  = 5
  };

//+------------------------------------------------------------------+
//| T1/T9: SExecResult — added ENUM_EXEC_STATUS status field         |
//+------------------------------------------------------------------+
struct SExecResult
  {
   ENUM_EXEC_STATUS  status;       // T9: was missing; Stage_Execution checks == EXEC_OK
   bool              executed;
   ulong             ticket;
   double            fill_price;
   double            slippage_pts;
   int               retcode;
   string            comment;

                     SExecResult() :
                        status(EXEC_SKIP), executed(false), ticket(0),
                        fill_price(0), slippage_pts(0), retcode(0), comment("") {}
  };

//+------------------------------------------------------------------+
//| T2/T11: SRiskResult — field names unified                        |
//| Stage_RiskCheck uses .suggestedLot + .reason                     |
//| Fields stored under canonical names; aliases via inline methods  |
//+------------------------------------------------------------------+
struct SRiskResult
  {
   bool              allowed;
   double            lot_size;        // canonical
   double            suggestedLot;    // T11: alias — same value as lot_size
   double            sl_price;
   double            tp_price;
   string            block_reason;    // canonical
   string            reason;          // T11: alias — same value as block_reason

                     SRiskResult() :
                        allowed(false), lot_size(0), suggestedLot(0),
                        sl_price(0), tp_price(0),
                        block_reason(""), reason("") {}

   void SetResult(bool ok, double lot, string msg)
     {
      allowed      = ok;
      lot_size     = lot;
      suggestedLot = lot;       // keep aliases in sync
      block_reason = msg;
      reason       = msg;
     }
  };

//+------------------------------------------------------------------+
//| SAIResult (unchanged)                                            |
//+------------------------------------------------------------------+
struct SAIResult
  {
   double            score;
   double            drift_index;
   bool              model_healthy;
   string            model_name;
                     SAIResult() : score(0), drift_index(0), model_healthy(true), model_name("") {}
  };

//+------------------------------------------------------------------+
//| T16: StageMetrics — per-stage timing + status (was missing)      |
//+------------------------------------------------------------------+
struct StageMetrics
  {
   int               stage_id;
   ulong             elapsed_us;
   bool              executed;
   bool              skipped;
   bool              aborted;
   bool              timed_out;

                     StageMetrics() : stage_id(0), elapsed_us(0),
                        executed(false), skipped(false), aborted(false), timed_out(false) {}

   void              Reset()  { stage_id=0; elapsed_us=0; executed=false; skipped=false; aborted=false; timed_out=false; }
   void              Start()  { elapsed_us = GetMicrosecondCount(); }
   void              Stop()   { elapsed_us = GetMicrosecondCount() - elapsed_us; executed = true; }
  };

//+------------------------------------------------------------------+
//| T16: PipelineReport — cycle-level aggregate metrics (was missing) |
//+------------------------------------------------------------------+
struct PipelineReport
  {
   ulong             last_cycle_time;   // microseconds
   double            avg_cycle_time_ms;
   ulong             cycle_count;
   int               aborts;
   StageMetrics      stage_metrics[STAGE_COUNT];

                     PipelineReport() : last_cycle_time(0), avg_cycle_time_ms(0),
                        cycle_count(0), aborts(0) {}

   void              Reset() { last_cycle_time=0; avg_cycle_time_ms=0; cycle_count=0; aborts=0; }

   void RecordCycle(ulong elapsed, ENUM_STAGE_RESULT result)
     {
      last_cycle_time   = elapsed;
      cycle_count++;
      double ms         = (double)elapsed / 1000.0;
      avg_cycle_time_ms = (avg_cycle_time_ms * (cycle_count-1) + ms) / cycle_count;
      if(result == STAGE_ABORT) aborts++;
     }

   string ToString() const
     {
      return StringFormat("[PipelineReport] cycles=%llu last=%lluµs avg=%.3fms aborts=%d",
                          cycle_count, last_cycle_time, avg_cycle_time_ms, aborts);
     }
  };

//+------------------------------------------------------------------+
//| T19: DetectSession() — free function (was undefined)             |
//| Called by Stage_RegimeDet to populate ctx.session               |
//+------------------------------------------------------------------+
ENUM_TRADING_SESSION DetectSession()
  {
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int h = dt.hour;
   // Overlap windows take priority
   if(h >= 12 && h < 16) return SESSION_OVERLAP;   // London/NY
   if(h >= 7  && h < 9 ) return SESSION_OVERLAP;   // Tokyo/London
   if(h >= 22 || h < 7 ) return SESSION_SYDNEY;    // Sydney + Tokyo pre-open
   if(h >= 7  && h < 12) return SESSION_LONDON;
   if(h >= 12 && h < 21) return SESSION_NEW_YORK;
   return SESSION_UNKNOWN;
  }

//+------------------------------------------------------------------+
//| PipelineContext                                                  |
//|                                                                  |
//| WRITE RULES (Sprint 7 ownership contract):                       |
//|   bid/ask/atr/atr_points/new_bar → Stage_DataSync ONLY          |
//|   signal (SSignal)               → Stage_SignalGen ONLY         |
//|   regime/confidence              → Stage_RegimeDet ONLY         |
//|   session                        → Stage_RegimeDet ONLY         |
//|   plan.*                         → Stage_AdaptiveParams         |
//|                                    then plan_locked = true      |
//|   risk_result.*                  → Stage_RiskCheck ONLY         |
//|   ai_score/drift_score/ai_veto   → Stage_AIInference ONLY       |
//|   exec_result.*                  → Stage_Execution ONLY         |
//|   has_position/position_pnl      → Stage_PositionMgmt ONLY      |
//|   health_status                  → Orchestrator pre-loop         |
//|   session_dd/daily_pnl           → Orchestrator pre-loop         |
//|   max_session_dd                 → Orchestrator pre-loop (cfg)   |
//+------------------------------------------------------------------+
struct PipelineContext
  {
   // ── Stage 1: DataSync ─────────────────────────────────────────
   double            bid;
   double            ask;
   double            spread_pts;
   double            atr;          // raw ATR value
   double            atr_points;   // T4: ATR expressed in points (DataSync alias)
   datetime          bar_time;
   bool              new_bar;
   bool              market_open;  // T5: true if tick is fresh (< 60s old)

   // ── Stage 5: Regime ───────────────────────────────────────────
   ENUM_MARKET_REGIME       regime;
   double                   regime_confidence;
   ENUM_TRADING_SESSION     session;          // T12: current trading session

   // ── Stage 6: Signal ───────────────────────────────────────────
   // T3: was scalar ENUM_SIGNAL_TYPE — changed to SSignal struct
   SSignal           signal;
   double            signal_strength;

   // ── Stage 7: AI Inference ─────────────────────────────────────
   SAIResult         ai_result;
   float             ai_score;     // T6: scalar shorthand for ai_result.score
   float             drift_score;  // T6: scalar shorthand for ai_result.drift_index
   bool              ai_veto;      // T6: true if AI vetoed entry

   // ── Stage 8: Risk Check ───────────────────────────────────────
   SRiskResult       risk_result;
   bool              trading_allowed;  // T7: set true by Stage_RiskCheck on pass

   // ── Stage 9: Trade Plan (written by AdaptiveParams) ───────────
   struct STradePlan
     {
      ENUM_SIGNAL_TYPE direction;
      double           entryPrice;
      double           sl;          // absolute SL price
      double           tp;          // absolute TP price
      double           slPoints;    // T13: SL in points  (AdaptiveParams reads/writes)
      double           tpPoints;    // T13: TP in points  (AdaptiveParams reads/writes)
      double           lot;
      bool             valid;        // T13: true when plan is complete and executable
     } plan;

   bool              plan_locked;   // S7-007: true after Stage_AdaptiveParams writes

   // ── Stage 10: Execution ───────────────────────────────────────
   SExecResult       exec_result;

   // ── Stage 11: Position Management ────────────────────────────
   int               positions_count;
   ulong             position_ticket;
   bool              has_position;  // T8: true if any matching position open
   double            position_pnl;  // T8: floating PnL of current position

   // ── Runtime State (injected by Orchestrator pre-loop) ─────────
   int               health_status;    // S7-004: 0=OK 1=WARN 2=CRIT 3=DEAD
   double            session_dd;       // current drawdown % from CSessionState
   double            daily_pnl;        // daily PnL from CSessionState
   // BUG-N05 FIX: was hardcoded 5.0 in ExecutePipeline().
   // Orchestrator injects cfg value (Risk.MaxDailyDrawdownPct) each cycle.
   // Default 5.0 retained for safety if Orchestrator omits the inject.
   double            max_session_dd;   // max allowed DD% — injected from StrategyConfig

   // ── Pipeline meta ─────────────────────────────────────────────
   ENUM_STAGE_RESULT exit_reason;    // T10: result of last stage that caused exit
   string            exit_message;   // T10: human-readable exit message
   datetime          cycle_start_time;
   int               stages_executed;
   int               stages_skipped;
   int               stages_failed;
   int               stages_timeout;

   // ── Internal abort/skip flags ─────────────────────────────────
   bool              _aborted;
   bool              _skipped;
   string            _skip_reason;

   //+---------------------------------------------------------------+
   //| T17: Reset — called by Orchestrator at start of each cycle   |
   //| NOTE: health_status, session_dd, daily_pnl, max_session_dd   |
   //|       are NOT reset here — they are injected by Orchestrator  |
   //|       in OnTimer() before ExecutePipeline() is called.        |
   //+---------------------------------------------------------------+
   void Reset()
     {
      bid = ask = spread_pts = atr = atr_points = 0;
      bar_time  = 0; new_bar = false; market_open = false;
      regime    = REGIME_UNKNOWN; regime_confidence = 0;
      session   = SESSION_UNKNOWN;
      ZeroMemory(signal); signal_strength = 0;
      ZeroMemory(ai_result);
      ai_score  = 0; drift_score = 0; ai_veto = false;
      ZeroMemory(risk_result);
      trading_allowed = false;
      ZeroMemory(plan); plan_locked = false;
      ZeroMemory(exec_result);
      positions_count = -1; position_ticket = 0;
      has_position    = false; position_pnl = 0;
      // health_status / session_dd / daily_pnl / max_session_dd
      // preserved — injected by Orchestrator::OnTimer() pre-loop
      exit_reason     = STAGE_OK; exit_message = "";
      cycle_start_time = TimeCurrent();
      stages_executed = stages_skipped = stages_failed = stages_timeout = 0;
      _aborted = false; _skipped = false; _skip_reason = "";
     }

   //+---------------------------------------------------------------+
   //| T18: Abort — hard stop, pipeline halts immediately           |
   //+---------------------------------------------------------------+
   void Abort(const string msg)
     {
      _aborted     = true;
      exit_reason  = STAGE_ABORT;
      exit_message = msg;
     }

   //+---------------------------------------------------------------+
   //| T18: Skip — soft skip, pipeline continues next stage         |
   //+---------------------------------------------------------------+
   void Skip(const string reason)
     {
      _skip_reason = reason;
      if(exit_message == "") exit_message = reason;
     }

   //+---------------------------------------------------------------+
   //| T18: ShouldContinue — checked by stage loop each iteration   |
   //+---------------------------------------------------------------+
   bool ShouldContinue() const
     {
      return(!_aborted);
     }
  };

#endif // __CORE_PIPELINE_TYPES_MQH__
