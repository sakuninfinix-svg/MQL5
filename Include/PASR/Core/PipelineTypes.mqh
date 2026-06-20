//+------------------------------------------------------------------+
//| Core/PipelineTypes.mqh — v1.08                                   |
//| Shared types, enums, and PipelineContext for CPipelineEngine      |
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_PIPELINE_TYPES_MQH__
#define __CORE_PIPELINE_TYPES_MQH__

#include "Events.mqh"
#include "../Data/RegimeTypes.mqh"
#include "../Signal/ISignalSource.mqh"
#include "../Infra/AccountSnapshot.mqh"
#include "../Trade/PositionRegistry.mqh"

#define STAGE_TIMEOUT_US   50000
#define STAGE_COUNT        15

enum ENUM_STAGE_RESULT
  {
   STAGE_OK      = 0,
   STAGE_SKIP    = 1,
   STAGE_WARN    = 2,
   STAGE_FAIL    = 3,
   STAGE_TIMEOUT = 4,
   STAGE_ABORT   = 5
  };

enum ENUM_EXEC_STATUS
  {
   EXEC_OK        = 0,
   EXEC_FAIL      = 1,
   EXEC_SKIP      = 2,
   EXEC_RETRYING  = 3
  };

enum ENUM_TRADING_SESSION
  {
   SESSION_UNKNOWN  = 0,
   SESSION_SYDNEY   = 1,
   SESSION_TOKYO    = 2,
   SESSION_LONDON   = 3,
   SESSION_NEW_YORK = 4,
   SESSION_OVERLAP  = 5,
   // Keep legacy enum spellings as aliases while canonical code uses the names above.
   SESSION_ASIAN    = SESSION_TOKYO,
   SESSION_NEWYORK  = SESSION_NEW_YORK,
   SESSION_OFF      = SESSION_UNKNOWN
  };

// Compatibility alias for legacy pipeline wording.
#ifndef PASR_ENUM_SIGNAL_TYPE_ALIAS
#define PASR_ENUM_SIGNAL_TYPE_ALIAS
#define ENUM_SIGNAL_TYPE ENUM_SIGNAL_DIR
#endif

struct SSignal
  {
   ENUM_SIGNAL_DIR direction;
   double          confidence;
   string          primarySource;
   double          entryPrice;
   double          slPoints;
   double          tpPoints;

   SSignal() : direction(SIGNAL_NONE), confidence(0.0), primarySource(""),
               entryPrice(0.0), slPoints(0.0), tpPoints(0.0) {}

   void Clear()
     {
      direction = SIGNAL_NONE;
      confidence = 0.0;
      primarySource = "";
      entryPrice = 0.0;
      slPoints = 0.0;
      tpPoints = 0.0;
     }
  };

struct SExecResult
  {
   ENUM_EXEC_STATUS  status;
   bool              executed;
   ulong             ticket;
   double            fill_price;
   double            slippage_pts;
   int               retcode;
   string            comment;

   SExecResult() : status(EXEC_SKIP), executed(false), ticket(0),
                   fill_price(0), slippage_pts(0), retcode(0), comment("") {}
  };

struct SRiskResult
  {
   bool              allowed;
   double            lot_size;
   double            suggestedLot;
   double            lotSize;
   double            sl_price;
   double            tp_price;
   double            entryPrice;
   double            stopLoss;
   double            takeProfit;
   ulong             magic;
   string            block_reason;
   string            reason;

   SRiskResult() : allowed(false), lot_size(0), suggestedLot(0), lotSize(0),
                   sl_price(0), tp_price(0), entryPrice(0), stopLoss(0),
                   takeProfit(0), magic(0), block_reason(""), reason("") {}

   void SetResult(bool ok, double lot, string msg)
     {
      allowed      = ok;
      lot_size     = lot;
      suggestedLot = lot;
      lotSize      = lot;
      block_reason = msg;
      reason       = msg;
     }

   void SetPrices(double entry, double sl, double tp, ulong orderMagic)
     {
      entryPrice = entry;
      stopLoss   = sl;
      takeProfit = tp;
      sl_price   = sl;
      tp_price   = tp;
      magic      = orderMagic;
     }
  };

struct SAIResult
  {
   double            score;
   double            drift_index;
   bool              model_healthy;
   string            model_name;
   bool              validation_valid;
   string            validation_reason;
   int               invalid_feature_index;
   SAIResult() : score(0), drift_index(0), model_healthy(true), model_name(""),
                 validation_valid(false), validation_reason(""), invalid_feature_index(-1) {}
   void Clear()
     {
      score = 0.0;
      drift_index = 0.0;
      model_healthy = true;
      model_name = "";
      validation_valid = false;
      validation_reason = "";
      invalid_feature_index = -1;
     }
  };

struct StageMetrics
  {
   int               stage_id;
   ulong             elapsed_us;
   bool              executed;
   bool              skipped;
   bool              aborted;
   bool              timed_out;

   StageMetrics() : stage_id(0), elapsed_us(0), executed(false),
                    skipped(false), aborted(false), timed_out(false) {}

   void Reset()  { stage_id=0; elapsed_us=0; executed=false; skipped=false; aborted=false; timed_out=false; }
   void Start()  { elapsed_us = GetMicrosecondCount(); }
   void Stop()   { elapsed_us = GetMicrosecondCount() - elapsed_us; executed = true; }
  };

struct PipelineReport
  {
   ulong             last_cycle_time;
   double            avg_cycle_time_ms;
   ulong             cycle_count;
   int               aborts;
   StageMetrics      stage_metrics[STAGE_COUNT];

   PipelineReport() : last_cycle_time(0), avg_cycle_time_ms(0), cycle_count(0), aborts(0) {}

   void Reset() { last_cycle_time=0; avg_cycle_time_ms=0; cycle_count=0; aborts=0; }

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

ENUM_TRADING_SESSION PASRDetectSession()
  {
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int h = dt.hour;
   if(h >= 12 && h < 16) return SESSION_OVERLAP;
   if(h >= 7  && h < 9 ) return SESSION_OVERLAP;
   if(h >= 22 || h < 7 ) return SESSION_SYDNEY;
   if(h >= 7  && h < 12) return SESSION_LONDON;
   if(h >= 12 && h < 21) return SESSION_NEW_YORK;
   return SESSION_UNKNOWN;
  }

// Allow existing pipeline code to call DetectSession(), then undefine this macro
// in PASR.mqh before control returns to the EA translation unit.
#define DetectSession PASRDetectSession

struct PipelineContext
  {
   double            bid;
   double            ask;
   double            spread_pts;
   double            atr;
   double            atr_points;
   datetime          bar_time;
   bool              new_bar;
   bool              market_open;
   SAccountSnapshot  account;
   CPositionRegistry positions;

    EMarketRegime          regime;
    double                 regime_confidence;
    ENUM_TRADING_SESSION   session;

    // SR/Zone distance for AI feature injection
    double            sr_distance;        // Normalized distance to nearest SR (0-1)
    double            zone_strength;      // Normalized zone strength (0-1)

    SSignal           signal;
    double            signal_strength;

    SAIResult         ai_result;
    float             ai_score;
    float             drift_score;
    bool              ai_veto;
    // FIX: Additional AI fields for infer stage gating
    double            ai_confidence;
    double            ai_min_confidence;
    bool              ai_valid;

     // FIX: Pattern fields for downstream stage access
     bool              pattern_detected;
     ENUM_SIGNAL_DIR   pattern_direction;
     double            pattern_score;
     // Detailed pattern features for AI feature builder
     double            pattern_buyProb;
     double            pattern_sellProb;
     double            pattern_conflict;
     double            pattern_dominanceGap;
     double            pattern_rejectionQuality;
     double            pattern_trapQuality;
     double            pattern_reclaimQuality;
     double            pattern_followThrough;

    SRiskResult       risk_result;
    bool              trading_allowed;

   struct STradePlan
     {
      ENUM_SIGNAL_DIR direction;
      double          entryPrice;
      double          sl;
      double          tp;
      double          slPoints;
      double          tpPoints;
      double          lot;
      bool            valid;
     } plan;

   bool              plan_locked;
   SExecResult       exec_result;

   int               positions_count;
   ulong             position_ticket;
   bool              has_position;
   double            position_pnl;

   int               health_status;
   double            session_dd;
   double            daily_pnl;
   double            max_session_dd;

   ENUM_STAGE_RESULT exit_reason;
   string            exit_message;
   datetime          cycle_start_time;
   int               stages_executed;
   int               stages_skipped;
   int               stages_failed;
   int               stages_timeout;

   bool              _aborted;
   bool              _skipped;
   string            _skip_reason;

   void Reset()
     {
      bid = ask = spread_pts = atr = atr_points = 0;
      bar_time = 0;
      new_bar = false;
      market_open = false;
      account.Clear();
      positions.Clear();
      regime = REGIME_UNKNOWN;
       regime_confidence = 0;
       session = SESSION_UNKNOWN;
       sr_distance = 0.5;
       zone_strength = 0.5;
       signal.Clear();
       signal_strength = 0;
       ai_result.Clear();
       ai_score = 0;
       drift_score = 0;
       ai_veto = false;
       ai_confidence = 0.0;
       ai_min_confidence = 0.0;
       ai_valid = false;
        pattern_detected = false;
        pattern_direction = SIGNAL_NONE;
        pattern_score = 0.0;
        pattern_buyProb = 0.0;
        pattern_sellProb = 0.0;
        pattern_conflict = 0.0;
        pattern_dominanceGap = 0.0;
        pattern_rejectionQuality = 0.0;
        pattern_trapQuality = 0.0;
        pattern_reclaimQuality = 0.0;
        pattern_followThrough = 0.0;
        ZeroMemory(risk_result);
       trading_allowed = false;
      ZeroMemory(plan);
      plan_locked = false;
      ZeroMemory(exec_result);
      positions_count = -1;
      position_ticket = 0;
      has_position = false;
      position_pnl = 0;
      health_status = 0;
      session_dd = 0.0;
      daily_pnl = 0.0;
      max_session_dd = 0.0;
      exit_reason = STAGE_OK;
      exit_message = "";
      cycle_start_time = TimeCurrent();
      stages_executed = stages_skipped = stages_failed = stages_timeout = 0;
      _aborted = false;
      _skipped = false;
      _skip_reason = "";
     }

   void Abort(const string msg)
     {
      _aborted = true;
      exit_reason = STAGE_ABORT;
      exit_message = msg;
     }

   void Skip(const string reason)
     {
      _skip_reason = reason;
      if(exit_message == "") exit_message = reason;
     }

   bool ShouldContinue() const { return(!_aborted); }
  };

#endif // __CORE_PIPELINE_TYPES_MQH__
