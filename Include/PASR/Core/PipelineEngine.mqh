//+------------------------------------------------------------------+
//| Core/PipelineEngine.mqh — v2.02 (Sprint 9 — Full Field Alignment)|
//| Staged pipeline execution engine with metrics                    |
//|                                                                  |
//| PURPOSE: Replace monolithic OnTimer() with pipelined stages       |
//|                                                                  |
//| CHANGELOG:                                                       |
//|   v2.02 (2026-05-23) Sprint 9:                                   |
//|     T1/T9:  ctx.exec_result.status == EXEC_OK (was STAGE_ABORT)  |
//|     T2/T11: risk_result field refs unified (.suggestedLot/.reason)|
//|     T3:     ctx.signal now SSignal struct; access .direction     |
//|     T6:     ctx.ai_score/drift_score/ai_veto (scalar fields)     |
//|     T8:     ctx.has_position / ctx.position_pnl                  |
//|     T16:    PipelineReport.RecordCycle() call in ExecutePipeline  |
//|     T18:    ctx.ShouldContinue() / ctx.Abort() / ctx.Skip()      |
//|     T19:    DetectSession() call in Stage_RegimeDet               |
//|   v2.01 (2026-05-23) — BUG-006 + BUG-007 + BUG-011              |
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_PIPELINE_ENGINE_MQH__
#define __CORE_PIPELINE_ENGINE_MQH__

#include "PipelineTypes.mqh"
#include "../Infra/DataManager.mqh"

// BUG-007 fixed paths
#include "../Analysis/SRManager.mqh"
#include "../Analysis/ZoneManager.mqh"
#include "../Analysis/PatternManager.mqh"
#include "../Signal/SignalManager.mqh"
#include "../Signal/RegimeFilter.mqh"
#include "../Trade/RiskManager.mqh"
#include "../Trade/ExecutionManager.mqh"
#include "../Trade/RecoveryManager.mqh"
#include "../UI/DashboardManager.mqh"
#include "../Infra/JournalManager.mqh"
#include "EventBus.mqh"
#include "../Infra/SanityManager.mqh"
#include "../Infra/TelemetryRecorder.mqh"
#include "../Analysis/AdaptiveParameterManager.mqh"
#include "../Analysis/MarketRegimeDetector.mqh"
#include "LatencyOptimizer.mqh"
#include "AsyncOrderManager.mqh"
#include "../Infra/HealthMonitor.mqh"
#include "../Infra/SnapshotManager.mqh"
#include "../Signal/AI/AIOrchestrator.mqh"

// Forward declarations
class CDataManager;
class CAnalysisSRManager;
class CAnalysisZoneManager;
class CPatternManager;
class CSignalManager;
class CAIOrchestrator;
class CRegimeFilter;
class CRiskManager;
class CExecutionManager;
class CRecoveryManager;
class CDashboardManager;
class CEventBus;
class CJournalManager;
class CAdaptiveParameterManager;
class CHealthMonitor;
class CSnapshotManager;

//+------------------------------------------------------------------+
//| CPipelineEngine — Staged execution with profiling                |
//+------------------------------------------------------------------+
class CPipelineEngine
  {
private:
   // Manager references (non-owning, injected by Orchestrator)
   CDataManager              *m_data;
   CAnalysisSRManager        *m_sr;
   CAnalysisZoneManager      *m_zone;
   CPatternManager           *m_pattern;
   CSignalManager            *m_signal;
   CAIOrchestrator           *m_ai_orch;
   CRegimeFilter             *m_regime;
   CRiskManager              *m_risk;
   CExecutionManager         *m_exec;
   CRecoveryManager          *m_recovery;
   CDashboardManager         *m_dash;
   CJournalManager           *m_journal;
   CEventBus                 *m_bus;
   CSanityManager            *m_sanity;
   CTelemetryRecorder        *m_telemetry;
   CAdaptiveParameterManager *m_adaptive;
   CMarketRegimeDetector     *m_regime_det;
   CLatencyOptimizer         *m_optimizer;
   CAsyncOrderManager        *m_async_orders;
   CHealthMonitor            *m_health;    // BUG-006 fixed
   CSnapshotManager          *m_snapshot;  // BUG-006 fixed

   // Profiling state
   PipelineReport  m_report;            // T16: was undefined
   StageMetrics    m_current_stage;     // T16: was undefined
   bool            m_profiling_enabled;
   bool            m_debug_mode;

   //+-----------------------------------------------------------------+
   //| Helper: push event and drain synchronously                      |
   //+-----------------------------------------------------------------+
   void PushAndDrain(int event_id, int priority)
     {
      if(CheckPointer(m_bus) == POINTER_INVALID) return;
      PASREvent ev;
      ev.id       = event_id;
      ev.priority = priority;
      m_bus->Push(ev);
      PASREvent drain_ev;
      while(m_bus->Pop(drain_ev))
         m_bus->Dispatch(drain_ev);
     }

   // ────────────────────────────────────────────────────────────
   //                    STAGE IMPLEMENTATIONS                        |
   // ────────────────────────────────────────────────────────────

   ENUM_STAGE_RESULT Stage_DataSync(PipelineContext &ctx)
     {
      m_current_stage.Start();

      MqlTick tick;
      if(!SymbolInfoTick(_Symbol, tick))
        {
         ctx.Abort("Failed to get tick data");
         m_current_stage.Stop();
         m_current_stage.aborted = true;
         return STAGE_ABORT;       // T14: STAGE_ABORT now defined
        }

      ctx.bid         = tick.bid;
      ctx.ask         = tick.ask;
      ctx.spread_pts  = (tick.ask - tick.bid) / _Point;
      ctx.bar_time    = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
      ctx.market_open = ((TimeCurrent() - tick.time) < 60); // T5

      if(CheckPointer(m_data) != POINTER_INVALID)
         m_data->OnTick();

      // T4: populate both atr and atr_points
      if(m_data != NULL)
        {
         ctx.atr        = m_data->GetATR();
         ctx.atr_points = m_data->GetATRPoints(); // T4: field now exists
        }

      m_current_stage.Stop();
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_AnalysisSR(PipelineContext &ctx)
     {
      m_current_stage.Start();

      if(CheckPointer(m_sr) == POINTER_INVALID)
        { m_current_stage.Stop(); m_current_stage.skipped = true; return STAGE_SKIP; }

      if(ctx.new_bar)
         PushAndDrain(EVENT_ID_NEW_BAR, 10);

      m_current_stage.Stop();
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_AnalysisZone(PipelineContext &ctx)
     {
      m_current_stage.Start();

      if(CheckPointer(m_zone) == POINTER_INVALID)
        { m_current_stage.Stop(); m_current_stage.skipped = true; return STAGE_SKIP; }

      if(ctx.new_bar)
         PushAndDrain(EVENT_ID_NEW_BAR, 9);

      m_current_stage.Stop();
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_PatternRec(PipelineContext &ctx)
     {
      m_current_stage.Start();

      if(CheckPointer(m_pattern) == POINTER_INVALID)
        { m_current_stage.Stop(); m_current_stage.skipped = true; return STAGE_SKIP; }

      if(ctx.new_bar)
         PushAndDrain(EVENT_ID_NEW_BAR, 8);

      m_current_stage.Stop();
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_RegimeDet(PipelineContext &ctx)
     {
      m_current_stage.Start();

      if(CheckPointer(m_regime) == POINTER_INVALID)
        { m_current_stage.Stop(); m_current_stage.skipped = true; return STAGE_SKIP; }

      ctx.regime  = m_regime->GetCurrentRegime();
      ctx.session = DetectSession();  // T19: now defined in PipelineTypes.mqh

      m_current_stage.Stop();
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_SignalGen(PipelineContext &ctx)
     {
      m_current_stage.Start();

      if(CheckPointer(m_signal) == POINTER_INVALID)
        { m_current_stage.Stop(); m_current_stage.skipped = true; return STAGE_SKIP; }

      // T3: ctx.signal is SSignal struct now
      if(m_signal->HasSignal())
        {
         ctx.signal          = m_signal->GetCurrent();   // returns SSignal
         ctx.signal_strength = ctx.signal.strength;
        }
      else
        {
         ZeroMemory(ctx.signal);
         ctx.Skip("No signal generated");
         m_current_stage.Stop();
         m_current_stage.skipped = true;
         return STAGE_SKIP;
        }

      m_current_stage.Stop();
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_AIInference(PipelineContext &ctx)
     {
      m_current_stage.Start();

      if(CheckPointer(m_ai_orch) == POINTER_INVALID)
        { m_current_stage.Stop(); m_current_stage.skipped = true; return STAGE_SKIP; }

      float features[AI_FEATURE_DIM];
      if(m_ai_orch->BuildFeaturesPublic(features))
        {
         // T6: write to scalar fields (also mirror to ai_result)
         ctx.ai_score              = m_ai_orch->Predict(features);
         ctx.drift_score           = m_ai_orch->GetDriftScore();
         ctx.ai_result.score       = (double)ctx.ai_score;
         ctx.ai_result.drift_index = (double)ctx.drift_score;

         ctx.ai_veto = (ctx.ai_score < 0.4f || ctx.drift_score > 0.6f);

         if(ctx.ai_veto)
           {
            ctx.Skip("AI veto triggered");
            m_current_stage.Stop();
            m_current_stage.skipped = true;
            return STAGE_SKIP;
           }
        }
      else
        {
         ctx.ai_score  = 0.5f;
         ctx.drift_score = 0.0f;
         ctx.ai_veto   = false;
        }

      m_current_stage.Stop();
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_RiskCheck(PipelineContext &ctx)
     {
      m_current_stage.Start();

      if(CheckPointer(m_risk) == POINTER_INVALID)
        { m_current_stage.Stop(); m_current_stage.skipped = true; return STAGE_SKIP; }

      // T2/T11: RiskManager.Check() must call risk_result.SetResult() to keep aliases in sync
      ctx.risk_result = m_risk->Check(ctx.plan.slPoints);

      if(!ctx.risk_result.allowed)
        {
         if(m_debug_mode)
            PrintFormat("[Pipeline] RiskBlock: %s", ctx.risk_result.block_reason);
         ctx.Skip(ctx.risk_result.block_reason);  // T11: use canonical field name
         m_current_stage.Stop();
         m_current_stage.skipped = true;
         return STAGE_SKIP;
        }

      ctx.plan.lot      = ctx.risk_result.lot_size;   // T11: canonical field name
      ctx.trading_allowed = true;                      // T7: field now exists

      m_current_stage.Stop();
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_AdaptiveParams(PipelineContext &ctx)
     {
      m_current_stage.Start();

      if(CheckPointer(m_adaptive) == POINTER_INVALID)
        { m_current_stage.Stop(); m_current_stage.skipped = true; return STAGE_SKIP; }

      m_adaptive->UpdateParameters();

      if(ctx.plan.valid && ctx.plan.slPoints > 0)   // T13: .valid + .slPoints now exist
        {
         double adaptiveSL = m_adaptive->GetStopLoss();
         double adaptiveTP = m_adaptive->GetTakeProfit();

         if(adaptiveSL > 0 && MathAbs(adaptiveSL - ctx.plan.slPoints) > _Point)
            ctx.plan.slPoints = adaptiveSL;

         if(adaptiveTP > 0 && MathAbs(adaptiveTP - ctx.plan.tpPoints) > _Point)
            ctx.plan.tpPoints = adaptiveTP;
        }

      ctx.plan_locked = true;   // S7-007: write-once guard
      m_current_stage.Stop();
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_Execution(PipelineContext &ctx)
     {
      m_current_stage.Start();

      if(CheckPointer(m_exec) == POINTER_INVALID || !ctx.plan.valid)  // T13
        { m_current_stage.Stop(); m_current_stage.skipped = true; return STAGE_SKIP; }

      ctx.exec_result = m_exec->Execute(ctx.plan);

      // T1/T9: status field now defined in SExecResult
      if(ctx.exec_result.status == EXEC_OK)
        {
         if(CheckPointer(m_risk) != POINTER_INVALID)
            m_risk->OnTradeOpened();

         if(CheckPointer(m_recovery) != POINTER_INVALID)
            // BUG-011 fixed: use actual ticket from exec_result
            m_recovery->OnTradeOpen(
               ctx.exec_result.ticket,
               ctx.signal.direction == SIGNAL_BUY ? 1 : -1,  // T3: ctx.signal is SSignal
               ctx.plan.entryPrice
            );
        }

      m_current_stage.Stop();
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_PositionMgmt(PipelineContext &ctx)
     {
      m_current_stage.Start();

      ctx.positions_count = PositionsTotal();
      ctx.has_position    = (ctx.positions_count > 0);  // T8
      ctx.position_pnl    = 0;                          // T8: reset before summing

      if(ctx.has_position)
        {
         for(int i = PositionsTotal() - 1; i >= 0; i--)
           {
            if(PositionGetSymbol(i) == _Symbol)
              {
               ctx.position_ticket = PositionGetTicket(i);
               ctx.position_pnl   += PositionGetDouble(POSITION_PROFIT); // T8
              }
           }
        }

      m_current_stage.Stop();
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_Recovery(PipelineContext &ctx)
     {
      m_current_stage.Start();

      if(CheckPointer(m_recovery) == POINTER_INVALID)
        { m_current_stage.Stop(); m_current_stage.skipped = true; return STAGE_SKIP; }

      PushAndDrain(EVENT_ID_PRICE_UPDATE, 5);

      m_current_stage.Stop();
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_Dashboard(PipelineContext &ctx)
     {
      m_current_stage.Start();

      if(CheckPointer(m_dash) == POINTER_INVALID)
        { m_current_stage.Stop(); m_current_stage.skipped = true; return STAGE_SKIP; }

      if(CheckPointer(m_bus) != POINTER_INVALID)
        {
         PASREvent ev;
         ev.id     = EVENT_ID_POSITION_UPDATE;
         ev.priority = 3;
         ev.profit   = ctx.position_pnl;   // T8: field now exists
         m_bus->Push(ev);
         PASREvent drain_ev;
         while(m_bus->Pop(drain_ev))
            m_bus->Dispatch(drain_ev);
        }

      m_current_stage.Stop();
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_Journal(PipelineContext &ctx)
     {
      m_current_stage.Start();

      if(m_profiling_enabled && m_debug_mode)
        {
         string msg = StringFormat("Pipeline cycle: %lluµs (avg %.2fms) stages=%d skipped=%d",
                                   m_report.last_cycle_time,
                                   m_report.avg_cycle_time_ms,
                                   ctx.stages_executed,
                                   ctx.stages_skipped);
         if(CheckPointer(m_journal) != POINTER_INVALID)
            m_journal->LogInfo(msg);
         else
            Print("[Pipeline][Journal] ", msg);
        }

      m_current_stage.Stop();
      return STAGE_OK;
     }

public:
   CPipelineEngine()
      : m_data(NULL), m_sr(NULL), m_zone(NULL), m_pattern(NULL),
        m_signal(NULL), m_ai_orch(NULL), m_regime(NULL), m_risk(NULL),
        m_exec(NULL), m_recovery(NULL), m_dash(NULL), m_journal(NULL),
        m_bus(NULL), m_sanity(NULL), m_telemetry(NULL), m_adaptive(NULL),
        m_regime_det(NULL), m_optimizer(NULL), m_async_orders(NULL),
        m_health(NULL), m_snapshot(NULL),
        m_profiling_enabled(true), m_debug_mode(false)
     {
      m_report.Reset();
     }

   ~CPipelineEngine() { /* Non-owning: do NOT delete injected refs */ }

   void SetDebugMode(bool on)    { m_debug_mode = on; }
   void EnableProfiling(bool on) { m_profiling_enabled = on; }

   //+----------------------------------------------------------------+
   //| InjectManagers                                                  |
   //+----------------------------------------------------------------+
   void InjectManagers(CDataManager *data,
                       CAnalysisSRManager *sr,
                       CAnalysisZoneManager *zone,
                       CPatternManager *pattern,
                       CSignalManager *signal,
                       CAIOrchestrator *ai_orch,
                       CRegimeFilter *regime,
                       CRiskManager *risk,
                       CExecutionManager *exec,
                       CRecoveryManager *recovery,
                       CDashboardManager *dash,
                       CJournalManager *journal,
                       CEventBus *bus,
                       CSanityManager *sanity             = NULL,
                       CTelemetryRecorder *telemetry       = NULL,
                       CAdaptiveParameterManager *adaptive = NULL,
                       CMarketRegimeDetector *regime_det   = NULL,
                       CLatencyOptimizer *optimizer        = NULL,
                       CAsyncOrderManager *async_orders    = NULL,
                       CHealthMonitor *health              = NULL,
                       CSnapshotManager *snapshot          = NULL)
     {
      m_data         = data;
      m_sr           = sr;
      m_zone         = zone;
      m_pattern      = pattern;
      m_signal       = signal;
      m_ai_orch      = ai_orch;
      m_regime       = regime;
      m_risk         = risk;
      m_exec         = exec;
      m_recovery     = recovery;
      m_dash         = dash;
      m_journal      = journal;
      m_bus          = bus;
      m_sanity       = sanity;
      m_telemetry    = telemetry;
      m_adaptive     = adaptive;
      m_regime_det   = regime_det;
      m_optimizer    = optimizer;
      m_async_orders = async_orders;
      m_health       = health;    // BUG-006 fixed
      m_snapshot     = snapshot;  // BUG-006 fixed
     }

   //+----------------------------------------------------------------+
   //| ExecutePipeline — run all 14 stages in sequence               |
   //+----------------------------------------------------------------+
   ENUM_STAGE_RESULT ExecutePipeline(PipelineContext &ctx)
     {
      ulong cycle_start = GetMicrosecondCount();
      ctx.cycle_start_time = TimeCurrent();

      // Health gate: abort if EA is critically unhealthy
      if(ctx.health_status >= 3)
        {
         ctx.Abort("EA in DEAD health state — pipeline blocked");
         return STAGE_ABORT;
        }

      typedef ENUM_STAGE_RESULT (CPipelineEngine::*StageFunc)(PipelineContext&);
      static const StageFunc stages[STAGE_COUNT] =
        {
         NULL,                                  // [0] sentinel
         &CPipelineEngine::Stage_DataSync,       // [1]
         &CPipelineEngine::Stage_AnalysisSR,     // [2]
         &CPipelineEngine::Stage_AnalysisZone,   // [3]
         &CPipelineEngine::Stage_PatternRec,     // [4]
         &CPipelineEngine::Stage_RegimeDet,      // [5]
         &CPipelineEngine::Stage_SignalGen,      // [6]
         &CPipelineEngine::Stage_AIInference,    // [7]
         &CPipelineEngine::Stage_RiskCheck,      // [8]
         &CPipelineEngine::Stage_AdaptiveParams, // [9]
         &CPipelineEngine::Stage_Execution,      // [10]
         &CPipelineEngine::Stage_PositionMgmt,   // [11]
         &CPipelineEngine::Stage_Recovery,       // [12]
         &CPipelineEngine::Stage_Dashboard,      // [13]
         &CPipelineEngine::Stage_Journal         // [14]
        };

      ENUM_STAGE_RESULT result = STAGE_OK;

      for(int i = 1; i < STAGE_COUNT && ctx.ShouldContinue(); i++)
        {
         m_current_stage.Reset();
         m_current_stage.stage_id = i;

         if(stages[i] != NULL)
            result = (this.*stages[i])(ctx);

         // Timeout guard
         if(m_current_stage.elapsed_us > STAGE_TIMEOUT_US)
           {
            m_current_stage.timed_out = true;
            ctx.stages_timeout++;
            if(m_debug_mode)
               PrintFormat("[Pipeline] Stage[%d] TIMEOUT: %lluµs", i, m_current_stage.elapsed_us);
           }

         // Update ctx stage counters
         switch(result)
           {
            case STAGE_OK:      ctx.stages_executed++; break;
            case STAGE_SKIP:    ctx.stages_skipped++;  break;
            case STAGE_FAIL:    ctx.stages_failed++;   break;
            case STAGE_TIMEOUT: ctx.stages_timeout++;  break;
            case STAGE_ABORT:   /* handled by ShouldContinue() */ break;
            default:            break;
           }

         // Record per-stage metrics
         if(m_profiling_enabled)
           {
            m_report.stage_metrics[i].elapsed_us += m_current_stage.elapsed_us;
           }
        }

      // Record cycle-level report (T16: PipelineReport.RecordCycle)
      ulong elapsed = GetMicrosecondCount() - cycle_start;
      m_report.RecordCycle(elapsed, result);

      return result;
     }

   const PipelineReport& GetReport() const { return m_report; }
  };

#endif // __CORE_PIPELINE_ENGINE_MQH__
