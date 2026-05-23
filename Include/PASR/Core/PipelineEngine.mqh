//+------------------------------------------------------------------+
//| Core/PipelineEngine.mqh — v2.01 (Profiling-Aware)                |
//| Staged pipeline execution engine with metrics                    |
//|                                                                   |
//| PURPOSE: Replace monolithic OnTimer() with pipelined stages       |
//|                                                                   |
//| CHANGELOG:                                                        |
//|   v2.01 (2026-05-23) — BUG-006 + BUG-007 + BUG-011:             |
//|     BUG-007: Fixed wrong include paths (RegimeFilter, RiskManager,|
//|              AdaptiveParameterManager all had wrong subfolders)   |
//|     BUG-006: Added m_health + m_snapshot member fields            |
//|              InjectManagers() now stores them correctly            |
//|     BUG-011: Stage_Execution() hardcoded ticket=0 fixed           |
//|              Now uses ctx.exec_result.ticket                      |
//|                                                                   |
//| STAGES (14 total):                                                |
//|   1. Data Sync  -> 2. Analysis SR  -> 3. Analysis Zone           |
//|   4. Pattern Rec -> 5. Regime Det  -> 6. Signal Gen              |
//|   7. AI Inference -> 8. Risk Check -> 9. Adaptive Params         |
//|   10. Execution -> 11. Position Mgmt -> 12. Recovery             |
//|   13. Dashboard -> 14. Journal                                   |
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_PIPELINE_ENGINE_MQH__
#define __CORE_PIPELINE_ENGINE_MQH__

#include "PipelineTypes.mqh"
#include "../Infra/DataManager.mqh"

// BUG-007 FIX: Corrected include paths
// ZoneManager defines SDZone struct inline
#include "../Analysis/SRManager.mqh"
#include "../Analysis/ZoneManager.mqh"
#include "../Analysis/PatternManager.mqh"
#include "../Signal/SignalManager.mqh"
#include "../Signal/RegimeFilter.mqh"              // BUG-007: was ../Analysis/RegimeFilter.mqh
#include "../Trade/RiskManager.mqh"               // BUG-007: was ../Risk/RiskManager.mqh
#include "../Trade/ExecutionManager.mqh"
#include "../Trade/RecoveryManager.mqh"
#include "../UI/DashboardManager.mqh"
#include "../Infra/JournalManager.mqh"
#include "EventBus.mqh"
#include "../Infra/SanityManager.mqh"              // Phase 1
#include "../Infra/TelemetryRecorder.mqh"          // Phase 3
#include "../Analysis/AdaptiveParameterManager.mqh" // BUG-007: was ../Risk/AdaptiveParameterManager.mqh
#include "../Analysis/MarketRegimeDetector.mqh"    // Phase 5
#include "LatencyOptimizer.mqh"                   // Phase 6
#include "AsyncOrderManager.mqh"                  // Phase 6
#include "../Infra/HealthMonitor.mqh"              // Phase 7: Self-Healing
#include "../Infra/SnapshotManager.mqh"            // Phase 7: State Persistence
#include "../Signal/AI/AIOrchestrator.mqh"         // Phase 7: 26-dim AI System

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
class CHealthMonitor;    // Phase 7
class CSnapshotManager;  // Phase 7

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
   // BUG-006 FIX: Added missing Phase 7 member fields
   CHealthMonitor            *m_health;    // Phase 7: Self-Healing
   CSnapshotManager          *m_snapshot;  // Phase 7: State Persistence

   // Profiling state
   PipelineReport  m_report;
   StageMetrics    m_current_stage;
   bool            m_profiling_enabled;
   bool            m_debug_mode;

   // ── Individual Stage Implementations ───────────────────────────

   ENUM_STAGE_RESULT Stage_DataSync(PipelineContext &ctx)
     {
      m_current_stage.Start();

      MqlTick tick;
      if(!SymbolInfoTick(_Symbol, tick))
        {
         ctx.Abort("Failed to get tick data");
         m_current_stage.Stop();
         m_current_stage.aborted = true;
         return STAGE_ABORT;
        }

      ctx.bid         = tick.bid;
      ctx.ask         = tick.ask;
      ctx.bar_time    = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
      ctx.market_open = ((TimeCurrent() - tick.time) < 60);

      if(CheckPointer(m_data) != POINTER_INVALID)
         m_data->OnTick();

      ctx.atr_points = (m_data != NULL) ? m_data->GetATRPoints() : 0;

      m_current_stage.Stop();
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_AnalysisSR(PipelineContext &ctx)
     {
      m_current_stage.Start();

      if(CheckPointer(m_sr) == POINTER_INVALID)
        { m_current_stage.Stop(); m_current_stage.skipped = true; return STAGE_SKIP; }

      if(ctx.new_bar && CheckPointer(m_bus) != POINTER_INVALID)
        {
         PASREvent ev;
         ev.id = EVENT_ID_NEW_BAR;
         ev.priority = 10;
         m_bus->Push(ev);

         // Drain to process SR update immediately
         PASREvent drain_ev;
         while(m_bus->Pop(drain_ev))
            m_bus->Dispatch(drain_ev);
        }

      m_current_stage.Stop();
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_AnalysisZone(PipelineContext &ctx)
     {
      m_current_stage.Start();

      if(CheckPointer(m_zone) == POINTER_INVALID)
        { m_current_stage.Stop(); m_current_stage.skipped = true; return STAGE_SKIP; }

      // Zone updates happen via event bus (drained in SR stage)
      // If new bar, push zone refresh event
      if(ctx.new_bar && CheckPointer(m_bus) != POINTER_INVALID)
        {
         PASREvent ev;
         ev.id = EVENT_ID_NEW_BAR;
         ev.priority = 9;
         m_bus->Push(ev);
         PASREvent drain_ev;
         while(m_bus->Pop(drain_ev))
            m_bus->Dispatch(drain_ev);
        }

      m_current_stage.Stop();
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_PatternRec(PipelineContext &ctx)
     {
      m_current_stage.Start();

      if(CheckPointer(m_pattern) == POINTER_INVALID)
        { m_current_stage.Stop(); m_current_stage.skipped = true; return STAGE_SKIP; }

      // Pattern recognition triggered via EVENT_ID_NEW_BAR dispatch
      // PatternManager.OnEvent() handles the update internally
      if(ctx.new_bar && CheckPointer(m_bus) != POINTER_INVALID)
        {
         PASREvent ev;
         ev.id = EVENT_ID_NEW_BAR;
         ev.priority = 8;
         m_bus->Push(ev);
         PASREvent drain_ev;
         while(m_bus->Pop(drain_ev))
            m_bus->Dispatch(drain_ev);
        }

      m_current_stage.Stop();
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_RegimeDet(PipelineContext &ctx)
     {
      m_current_stage.Start();

      if(CheckPointer(m_regime) == POINTER_INVALID)
        { m_current_stage.Stop(); m_current_stage.skipped = true; return STAGE_SKIP; }

      ctx.regime  = m_regime->GetCurrentRegime();
      ctx.session = DetectSession();

      m_current_stage.Stop();
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_SignalGen(PipelineContext &ctx)
     {
      m_current_stage.Start();

      if(CheckPointer(m_signal) == POINTER_INVALID)
        { m_current_stage.Stop(); m_current_stage.skipped = true; return STAGE_SKIP; }

      if(m_signal->HasSignal())
        {
         ctx.signal = m_signal->GetCurrent();
        }
      else
        {
         ctx.signal.direction = SIGNAL_NONE;
         ctx.Skip("No signal generated");
         m_current_stage.Stop();
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
         ctx.ai_score    = m_ai_orch->Predict(features);
         ctx.drift_score = m_ai_orch->GetDriftScore();
         ctx.ai_veto     = (ctx.ai_score < 0.4f || ctx.drift_score > 0.6f);

         if(ctx.ai_veto)
           {
            ctx.Skip("AI veto triggered");
            m_current_stage.Stop();
            return STAGE_SKIP;
           }
        }
      else
        {
         ctx.ai_score    = 0.5f;
         ctx.drift_score = 0.0f;
         ctx.ai_veto     = false;
        }

      m_current_stage.Stop();
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_RiskCheck(PipelineContext &ctx)
     {
      m_current_stage.Start();

      if(CheckPointer(m_risk) == POINTER_INVALID)
        { m_current_stage.Stop(); m_current_stage.skipped = true; return STAGE_SKIP; }

      ctx.risk_result = m_risk->Check(ctx.plan.slPoints);

      if(!ctx.risk_result.allowed)
        {
         if(m_debug_mode)
            PrintFormat("[Pipeline] RiskBlock: %s", ctx.risk_result.reason);
         ctx.Skip(ctx.risk_result.reason);
         m_current_stage.Stop();
         return STAGE_SKIP;
        }

      ctx.plan.lot      = ctx.risk_result.suggestedLot;
      ctx.trading_allowed = true;

      m_current_stage.Stop();
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_AdaptiveParams(PipelineContext &ctx)
     {
      m_current_stage.Start();

      if(CheckPointer(m_adaptive) == POINTER_INVALID)
        { m_current_stage.Stop(); m_current_stage.skipped = true; return STAGE_SKIP; }

      m_adaptive->UpdateParameters();

      if(ctx.plan.valid && ctx.plan.slPoints > 0)
        {
         double adaptiveSL = m_adaptive->GetStopLoss();
         double adaptiveTP = m_adaptive->GetTakeProfit();

         if(adaptiveSL > 0 && MathAbs(adaptiveSL - ctx.plan.slPoints) > _Point)
            ctx.plan.slPoints = adaptiveSL;

         if(adaptiveTP > 0 && MathAbs(adaptiveTP - ctx.plan.tpPoints) > _Point)
            ctx.plan.tpPoints = adaptiveTP;
        }

      m_current_stage.Stop();
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_Execution(PipelineContext &ctx)
     {
      m_current_stage.Start();

      if(CheckPointer(m_exec) == POINTER_INVALID || !ctx.plan.valid)
        { m_current_stage.Stop(); m_current_stage.skipped = true; return STAGE_SKIP; }

      ctx.exec_result = m_exec->Execute(ctx.plan);

      if(ctx.exec_result.status == EXEC_OK)
        {
         if(CheckPointer(m_risk) != POINTER_INVALID)
            m_risk->OnTradeOpened();

         if(CheckPointer(m_recovery) != POINTER_INVALID)
            // BUG-011 FIX: Use actual ticket from exec_result, not hardcoded 0
            m_recovery->OnTradeOpen(
               ctx.exec_result.ticket,
               ctx.plan.direction == SIGNAL_BUY ? 1 : -1,
               ctx.plan.entryPrice
            );
        }

      m_current_stage.Stop();
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_PositionMgmt(PipelineContext &ctx)
     {
      m_current_stage.Start();

      ctx.has_position = (PositionsTotal() > 0);
      if(ctx.has_position)
        {
         for(int i = PositionsTotal() - 1; i >= 0; i--)
           {
            if(PositionGetSymbol(i) == _Symbol)
              {
               ctx.position_ticket = PositionGetTicket(i);
               ctx.position_pnl    = PositionGetDouble(POSITION_PROFIT);
               break;
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

      // RecoveryManager.OnTick() handles trailing stop, BE, partial close
      // It is called via the EventBus EVENT_ID_PRICE_UPDATE dispatch
      // Explicit tick event push for recovery processing
      if(CheckPointer(m_bus) != POINTER_INVALID)
        {
         PASREvent ev;
         ev.id = EVENT_ID_PRICE_UPDATE;
         ev.priority = 5;
         m_bus->Push(ev);
         PASREvent drain_ev;
         while(m_bus->Pop(drain_ev))
            m_bus->Dispatch(drain_ev);
        }

      m_current_stage.Stop();
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_Dashboard(PipelineContext &ctx)
     {
      m_current_stage.Start();

      if(CheckPointer(m_dash) == POINTER_INVALID)
        { m_current_stage.Stop(); m_current_stage.skipped = true; return STAGE_SKIP; }

      // Dashboard update via EVENT_ID_POSITION_UPDATE event
      if(CheckPointer(m_bus) != POINTER_INVALID)
        {
         PASREvent ev;
         ev.id = EVENT_ID_POSITION_UPDATE;
         ev.priority = 3;
         ev.profit   = ctx.position_pnl;
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
         string msg = StringFormat("Pipeline cycle: %dµs (avg %.2fms)",
                                   m_report.last_cycle_time,
                                   m_report.avg_cycle_time_ms);
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
        m_health(NULL), m_snapshot(NULL),   // BUG-006 FIX
        m_profiling_enabled(true), m_debug_mode(false)
     {
      m_report.Reset();
     }

   ~CPipelineEngine() { /* Non-owning: do NOT delete injected refs */ }

   void SetDebugMode(bool on)   { m_debug_mode = on; }
   void EnableProfiling(bool on) { m_profiling_enabled = on; }

   //+----------------------------------------------------------------+
   //| InjectManagers — called once by COrchestrator after alloc       |
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
                       CHealthMonitor *health              = NULL,  // BUG-006 FIX
                       CSnapshotManager *snapshot          = NULL)  // BUG-006 FIX
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
      m_health       = health;    // BUG-006 FIX: now stored
      m_snapshot     = snapshot;  // BUG-006 FIX: now stored
     }

   //+----------------------------------------------------------------+
   //| ExecutePipeline — run all 14 stages in order                   |
   //+----------------------------------------------------------------+
   ENUM_STAGE_RESULT ExecutePipeline(PipelineContext &ctx)
     {
      ulong cycle_start = GetMicrosecondCount();

      typedef ENUM_STAGE_RESULT (CPipelineEngine::*StageFunc)(PipelineContext&);
      static const StageFunc stages[STAGE_COUNT] =
        {
         NULL,
         &CPipelineEngine::Stage_DataSync,
         &CPipelineEngine::Stage_AnalysisSR,
         &CPipelineEngine::Stage_AnalysisZone,
         &CPipelineEngine::Stage_PatternRec,
         &CPipelineEngine::Stage_RegimeDet,
         &CPipelineEngine::Stage_SignalGen,
         &CPipelineEngine::Stage_AIInference,
         &CPipelineEngine::Stage_RiskCheck,
         &CPipelineEngine::Stage_AdaptiveParams,
         &CPipelineEngine::Stage_Execution,
         &CPipelineEngine::Stage_PositionMgmt,
         &CPipelineEngine::Stage_Recovery,
         &CPipelineEngine::Stage_Dashboard,
         &CPipelineEngine::Stage_Journal
        };

      ENUM_STAGE_RESULT result = STAGE_OK;

      for(int i = 1; i < STAGE_COUNT && ctx.ShouldContinue(); i++)
        {
         m_current_stage.Reset();
         m_current_stage.stage_id = i;

         if(stages[i] != NULL)
            result = (this.*stages[i])(ctx);

         if(m_profiling_enabled)
           {
            m_report.stage_metrics[i].elapsed_us += m_current_stage.elapsed_us;
            if(m_current_stage.executed) m_report.stage_metrics[i].executed = true;
            if(m_current_stage.skipped)  m_report.stage_metrics[i].skipped  = true;
            if(m_current_stage.aborted)  m_report.stage_metrics[i].aborted  = true;
           }

         if(result == STAGE_ABORT) break;
        }

      ulong elapsed = GetMicrosecondCount() - cycle_start;
      if(m_profiling_enabled)
         m_report.RecordCycle(elapsed, result);

      ctx.exit_reason = result;
      return result;
     }

   const PipelineReport& GetReport() const { return m_report; }

   void PrintProfile() const
     {
      if(!m_profiling_enabled) return;
      Print(m_report.ToString());
     }
  };

#endif // __CORE_PIPELINE_ENGINE_MQH__
