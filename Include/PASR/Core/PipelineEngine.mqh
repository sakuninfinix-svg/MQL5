//+------------------------------------------------------------------+
//| Core/PipelineEngine.mqh — v1.01 SPRINT-11                       |
//| Full 14-stage pipeline implementation.                           |
//|                                                                  |
//| BUGS FIXED IN THIS VERSION:                                      |
//|   BUG-N01 [CRITICAL]: Stage_AnalysisSR pushed EVENT_ID_NEW_BAR  |
//|     but never dispatched it. SR OnEvent() never fired in timer  |
//|     path. Fix: m_bus.Dispatch(ev) called immediately after Push.|
//|   BUG-N04 [HIGH]: Stage_RiskCheck set ctx.exit_reason=STAGE_SKIP|
//|     on a soft rejection — poisoned exit_reason and triggered    |
//|     false-alarm debug log in Orchestrator. Fix: exit_reason not |
//|     overwritten; only exit_message written on soft skip.        |
//|   BUG-N07 [CRITICAL]: SkipIfNull() used CheckPointer(void*)     |
//|     — undefined in MQL5; could return POINTER_DYNAMIC for NULL. |
//|     All 14 stage guards were unreliable. Fix: ptr==NULL check.  |
//|                                                                  |
//| BUGS FIXED IN v1.00 (Sprint 10):                                 |
//|   BUG-003: All 7 empty stage stubs now implemented.             |
//|   BUG-006: InjectManagers() stores m_health/snapshot.           |
//|   BUG-007: Corrected 3 broken include paths.                    |
//|   BUG-011: Stage_Execution uses exec_result.ticket.             |
//|                                                                  |
//| PIPELINE STAGE MAP:                                              |
//|   Stage 1  DataSync         — m_data->OnTick()                  |
//|   Stage 2  AnalysisSR       — m_bus.Dispatch(EVENT_ID_NEW_BAR)  |
//|   Stage 3  AnalysisZone     — m_zone->Update() on new bar       |
//|   Stage 4  PatternRec       — m_pattern->OnTick()               |
//|   Stage 5  RegimeDet        — m_regime_det->Evaluate()          |
//|   Stage 6  SignalGen        — m_signal->AggregateSignals()       |
//|   Stage 7  AIInfer          — m_ai_orch->Evaluate()             |
//|   Stage 8  RiskCheck        — m_risk->CheckRisk()               |
//|   Stage 9  AdaptiveParams   — m_adaptive->OnNewBar()            |
//|   Stage 10 Execution        — m_exec->Execute() + ticket capture|
//|   Stage 11 PosMgmt          — m_exec->ManagePositions()         |
//|   Stage 12 Recovery         — m_recovery->OnTick()              |
//|   Stage 13 Dashboard        — m_dash->OnTimer()                 |
//|   Stage 14 Journal          — m_journal->LogEntry()             |
//|                                                                  |
//| CHANGELOG:                                                       |
//|   v1.01 (2026-05-23) — Sprint 11: N01/N04/N07 fixes             |
//|   v1.00 (2026-05-23) — Sprint 10: full implementation           |
//+------------------------------------------------------------------+
#property strict

#ifndef __CORE_PIPELINE_ENGINE_MQH__
#define __CORE_PIPELINE_ENGINE_MQH__

#ifdef __CORE_PASR_MASTER_MQH__
  // OK — included via PASR.mqh
#else
  #error "Include <PASR/Core/PASR.mqh> instead of PipelineEngine.mqh directly."
#endif

//+------------------------------------------------------------------+
//| CPipelineEngine — drives the 14-stage PASR pipeline              |
//+------------------------------------------------------------------+
class CPipelineEngine
  {
private:
   // ── Non-owning manager pointers (injected by Orchestrator) ──────
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
   CHealthMonitor            *m_health;    // BUG-006 FIX (Sprint 10)
   CSnapshotManager          *m_snapshot;  // BUG-006 FIX (Sprint 10)

   // ── Config ──────────────────────────────────────────────────────
   bool   m_debug_mode;
   bool   m_profiling_enabled;

   // ── Stage profiler ──────────────────────────────────────────────
   CPerfTimer m_stage_timer;

   //+----------------------------------------------------------------+
   //| BUG-N07 FIX: SkipIfNull — plain ptr==NULL, NOT CheckPointer() |
   //| CheckPointer() requires CObject*; passing void* is UB in MQL5 |
   //| and could return POINTER_DYNAMIC for an actual null pointer,   |
   //| making ALL 14 stage guards silently non-functional.            |
   //+----------------------------------------------------------------+
   ENUM_STAGE_RESULT SkipIfNull(const void *ptr, const string stageName)
     {
      if(ptr == NULL)
        {
         if(m_debug_mode)
            PrintFormat("[Pipeline] %s SKIP: manager is NULL", stageName);
         return STAGE_SKIP;
        }
      return STAGE_OK;
     }

   //+------------------------------------------------------------------+
   //| Stage 1: DataSync                                                |
   //+------------------------------------------------------------------+
   ENUM_STAGE_RESULT Stage_DataSync(PipelineContext &ctx)
     {
      if(SkipIfNull(m_data, "DataSync") == STAGE_SKIP) return STAGE_SKIP;
      m_stage_timer.Start();
      m_data.OnTick();
      if(m_profiling_enabled) m_stage_timer.Log("Stage1_DataSync");
      return STAGE_OK;
     }

   //+------------------------------------------------------------------+
   //| Stage 2: AnalysisSR                                              |
   //| BUG-N01 FIX: Push() alone does NOT call subscribers. Must call  |
   //| m_bus.Dispatch(ev) immediately so SR OnEvent() fires this cycle.|
   //+------------------------------------------------------------------+
   ENUM_STAGE_RESULT Stage_AnalysisSR(PipelineContext &ctx)
     {
      if(SkipIfNull(m_sr, "AnalysisSR") == STAGE_SKIP) return STAGE_SKIP;
      if(!ctx.new_bar) return STAGE_SKIP;
      m_stage_timer.Start();

      PASREvent ev;
      ev.id       = EVENT_ID_NEW_BAR;
      ev.priority = 10;

      if(m_bus != NULL)
        {
         // BUG-N01 FIX: Dispatch immediately to SR manager.
         // Do NOT use Push()+Drain() here — Drain() would flush ALL queued
         // events including higher-priority system events meant for OnTick().
         // Dispatch(ev) calls subscribers directly without touching the heap.
         m_bus.Dispatch(ev);
        }

      if(m_profiling_enabled) m_stage_timer.Log("Stage2_AnalysisSR");
      return STAGE_OK;
     }

   //+------------------------------------------------------------------+
   //| Stage 3: AnalysisZone                                            |
   //+------------------------------------------------------------------+
   ENUM_STAGE_RESULT Stage_AnalysisZone(PipelineContext &ctx)
     {
      if(SkipIfNull(m_zone, "AnalysisZone") == STAGE_SKIP) return STAGE_SKIP;
      if(!ctx.new_bar) return STAGE_SKIP;
      m_stage_timer.Start();
      m_zone.Update();
      if(m_profiling_enabled) m_stage_timer.Log("Stage3_AnalysisZone");
      return STAGE_OK;
     }

   //+------------------------------------------------------------------+
   //| Stage 4: PatternRecognition                                      |
   //+------------------------------------------------------------------+
   ENUM_STAGE_RESULT Stage_PatternRec(PipelineContext &ctx)
     {
      if(SkipIfNull(m_pattern, "PatternRec") == STAGE_SKIP) return STAGE_SKIP;
      m_stage_timer.Start();
      m_pattern.OnTick();
      if(m_profiling_enabled) m_stage_timer.Log("Stage4_PatternRec");
      return STAGE_OK;
     }

   //+------------------------------------------------------------------+
   //| Stage 5: RegimeDetection                                         |
   //+------------------------------------------------------------------+
   ENUM_STAGE_RESULT Stage_RegimeDet(PipelineContext &ctx)
     {
      if(SkipIfNull(m_regime_det, "RegimeDet") == STAGE_SKIP) return STAGE_SKIP;
      m_stage_timer.Start();
      m_regime_det.Evaluate();
      ctx.regime = m_regime_det.GetCurrentRegime();
      if(m_profiling_enabled) m_stage_timer.Log("Stage5_RegimeDet");
      return STAGE_OK;
     }

   //+------------------------------------------------------------------+
   //| Stage 6: SignalGeneration                                        |
   //+------------------------------------------------------------------+
   ENUM_STAGE_RESULT Stage_SignalGen(PipelineContext &ctx)
     {
      if(SkipIfNull(m_signal, "SignalGen") == STAGE_SKIP) return STAGE_SKIP;
      m_stage_timer.Start();
      ctx.signal = m_signal.AggregateSignals();
      if(m_debug_mode)
         PrintFormat("[Pipeline] SignalGen: dir=%s conf=%.3f src=%s",
                     EnumToString(ctx.signal.direction),
                     ctx.signal.confidence,
                     ctx.signal.primarySource);
      if(m_profiling_enabled) m_stage_timer.Log("Stage6_SignalGen");
      return STAGE_OK;
     }

   //+------------------------------------------------------------------+
   //| Stage 7: AIInference                                             |
   //+------------------------------------------------------------------+
   ENUM_STAGE_RESULT Stage_AIInfer(PipelineContext &ctx)
     {
      if(SkipIfNull(m_ai_orch, "AIInfer") == STAGE_SKIP) return STAGE_SKIP;
      m_stage_timer.Start();
      ctx.ai_score = m_ai_orch.Evaluate();
      if(m_debug_mode)
         PrintFormat("[Pipeline] AIInfer: score=%.4f", ctx.ai_score);
      if(m_profiling_enabled) m_stage_timer.Log("Stage7_AIInfer");
      return STAGE_OK;
     }

   //+------------------------------------------------------------------+
   //| Stage 8: RiskCheck                                               |
   //| BUG-N04 FIX: Do NOT set ctx.exit_reason on soft STAGE_SKIP.    |
   //| Overwriting exit_reason with STAGE_SKIP here caused:           |
   //|   1. Orchestrator debug branch to fire as if pipeline aborted.  |
   //|   2. exit_reason poisoned for Stage 14 Journal logging.         |
   //| Fix: only write exit_message (human log), never exit_reason.   |
   //+------------------------------------------------------------------+
   ENUM_STAGE_RESULT Stage_RiskCheck(PipelineContext &ctx)
     {
      if(SkipIfNull(m_risk, "RiskCheck") == STAGE_SKIP) return STAGE_SKIP;
      if(ctx.signal.direction == SIGNAL_NONE) return STAGE_SKIP;
      m_stage_timer.Start();

      ctx.risk_result = m_risk.CheckRisk(ctx.signal);

      if(!ctx.risk_result.allowed)
        {
         if(m_debug_mode)
            PrintFormat("[Pipeline] RiskCheck REJECTED: %s", ctx.risk_result.reason);
         // BUG-N04 FIX: removed ctx.exit_reason = STAGE_SKIP
         // Only set human-readable message; downstream stages self-skip
         // via risk_result.allowed == false guard.
         ctx.exit_message = "RiskCheck: " + ctx.risk_result.reason;
         if(m_profiling_enabled) m_stage_timer.Log("Stage8_RiskCheck");
         return STAGE_SKIP;
        }

      ctx.trading_allowed = true;
      if(m_profiling_enabled) m_stage_timer.Log("Stage8_RiskCheck");
      return STAGE_OK;
     }

   //+------------------------------------------------------------------+
   //| Stage 9: AdaptiveParameters                                      |
   //+------------------------------------------------------------------+
   ENUM_STAGE_RESULT Stage_AdaptiveParams(PipelineContext &ctx)
     {
      if(SkipIfNull(m_adaptive, "AdaptiveParams") == STAGE_SKIP) return STAGE_SKIP;
      if(!ctx.new_bar) return STAGE_SKIP;
      m_stage_timer.Start();
      m_adaptive.OnNewBar();
      if(m_profiling_enabled) m_stage_timer.Log("Stage9_AdaptiveParams");
      return STAGE_OK;
     }

   //+------------------------------------------------------------------+
   //| Stage 10: Execution                                              |
   //+------------------------------------------------------------------+
   ENUM_STAGE_RESULT Stage_Execution(PipelineContext &ctx)
     {
      if(SkipIfNull(m_exec, "Execution") == STAGE_SKIP) return STAGE_SKIP;
      if(ctx.signal.direction == SIGNAL_NONE) return STAGE_SKIP;
      if(!ctx.risk_result.allowed)            return STAGE_SKIP;
      m_stage_timer.Start();

      TradePlan plan;
      plan.direction  = ctx.signal.direction;
      plan.entryPrice = ctx.risk_result.entryPrice;
      plan.stopLoss   = ctx.risk_result.stopLoss;
      plan.takeProfit = ctx.risk_result.takeProfit;
      plan.lotSize    = ctx.risk_result.lotSize;
      plan.magic      = ctx.risk_result.magic;
      ctx.plan        = plan;

      ctx.exec_result = m_exec.Execute(plan);

      if(ctx.exec_result.status == EXEC_FAIL)
        {
         if(m_debug_mode)
            PrintFormat("[Pipeline] Execution FAILED: %s", ctx.exec_result.comment);
         ctx.exit_reason  = STAGE_ABORT;
         ctx.exit_message = "Execution error: " + ctx.exec_result.comment;
         if(m_profiling_enabled) m_stage_timer.Log("Stage10_Execution");
         return STAGE_ABORT;
        }

      if(ctx.exec_result.status == EXEC_OK && m_recovery != NULL)
        {
         int dir = (plan.direction == SIGNAL_BUY) ? 1 : -1;
         m_recovery.OnTradeOpen(ctx.exec_result.ticket, dir, plan.entryPrice);
        }

      if(m_debug_mode)
         PrintFormat("[Pipeline] Execution OK: ticket=%I64u price=%.5f lot=%.2f",
                     ctx.exec_result.ticket, plan.entryPrice, plan.lotSize);

      if(m_profiling_enabled) m_stage_timer.Log("Stage10_Execution");
      return STAGE_OK;
     }

   //+------------------------------------------------------------------+
   //| Stage 11: PositionManagement                                     |
   //+------------------------------------------------------------------+
   ENUM_STAGE_RESULT Stage_PosMgmt(PipelineContext &ctx)
     {
      if(SkipIfNull(m_exec, "PosMgmt") == STAGE_SKIP) return STAGE_SKIP;
      m_stage_timer.Start();
      m_exec.ManagePositions();
      if(m_profiling_enabled) m_stage_timer.Log("Stage11_PosMgmt");
      return STAGE_OK;
     }

   //+------------------------------------------------------------------+
   //| Stage 12: Recovery                                               |
   //+------------------------------------------------------------------+
   ENUM_STAGE_RESULT Stage_Recovery(PipelineContext &ctx)
     {
      if(SkipIfNull(m_recovery, "Recovery") == STAGE_SKIP) return STAGE_SKIP;
      m_stage_timer.Start();
      m_recovery.OnTick();
      if(m_profiling_enabled) m_stage_timer.Log("Stage12_Recovery");
      return STAGE_OK;
     }

   //+------------------------------------------------------------------+
   //| Stage 13: Dashboard                                              |
   //+------------------------------------------------------------------+
   ENUM_STAGE_RESULT Stage_Dashboard(PipelineContext &ctx)
     {
      if(SkipIfNull(m_dash, "Dashboard") == STAGE_SKIP) return STAGE_SKIP;
      m_stage_timer.Start();
      m_dash.SetPipelineSignal(ctx.signal);
      m_dash.SetAIScore(ctx.ai_score);
      m_dash.SetRegime(ctx.regime);
      m_dash.SetSessionDD(ctx.session_dd);
      m_dash.OnTimer();
      if(m_profiling_enabled) m_stage_timer.Log("Stage13_Dashboard");
      return STAGE_OK;
     }

   //+------------------------------------------------------------------+
   //| Stage 14: Journal                                                |
   //+------------------------------------------------------------------+
   ENUM_STAGE_RESULT Stage_Journal(PipelineContext &ctx)
     {
      if(SkipIfNull(m_journal, "Journal") == STAGE_SKIP) return STAGE_SKIP;
      if(!ctx.new_bar) return STAGE_SKIP;
      m_stage_timer.Start();
      m_journal.LogEntry(ctx);
      if(m_telemetry != NULL)
         m_telemetry.RecordBarEvent(ctx);
      if(m_profiling_enabled) m_stage_timer.Log("Stage14_Journal");
      return STAGE_OK;
     }

public:
   CPipelineEngine()
      : m_data(NULL), m_sr(NULL), m_zone(NULL),
        m_pattern(NULL), m_signal(NULL), m_ai_orch(NULL),
        m_regime(NULL), m_risk(NULL), m_exec(NULL),
        m_recovery(NULL), m_dash(NULL), m_journal(NULL),
        m_bus(NULL), m_sanity(NULL), m_telemetry(NULL),
        m_adaptive(NULL), m_regime_det(NULL),
        m_optimizer(NULL), m_async_orders(NULL),
        m_health(NULL), m_snapshot(NULL),
        m_debug_mode(false), m_profiling_enabled(true)
     {}

   void SetDebugMode(bool on)    { m_debug_mode        = on; }
   void EnableProfiling(bool on) { m_profiling_enabled = on; }

   //+------------------------------------------------------------------+
   //| InjectManagers — called once by Orchestrator::Init()            |
   //+------------------------------------------------------------------+
   void InjectManagers(
      CDataManager              *data,
      CAnalysisSRManager        *sr,
      CAnalysisZoneManager      *zone,
      CPatternManager           *pattern,
      CSignalManager            *signal,
      CAIOrchestrator           *ai_orch,
      CRegimeFilter             *regime,
      CRiskManager              *risk,
      CExecutionManager         *exec,
      CRecoveryManager          *recovery,
      CDashboardManager         *dash,
      CJournalManager           *journal,
      CEventBus                 *bus,
      CSanityManager            *sanity,
      CTelemetryRecorder        *telemetry,
      CAdaptiveParameterManager *adaptive,
      CMarketRegimeDetector     *regime_det,
      CLatencyOptimizer         *optimizer    = NULL,
      CAsyncOrderManager        *async_orders = NULL,
      CHealthMonitor            *health       = NULL,
      CSnapshotManager          *snapshot     = NULL
   )
     {
      m_data         = data;         m_sr           = sr;
      m_zone         = zone;         m_pattern      = pattern;
      m_signal       = signal;       m_ai_orch      = ai_orch;
      m_regime       = regime;       m_risk         = risk;
      m_exec         = exec;         m_recovery     = recovery;
      m_dash         = dash;         m_journal      = journal;
      m_bus          = bus;          m_sanity       = sanity;
      m_telemetry    = telemetry;    m_adaptive     = adaptive;
      m_regime_det   = regime_det;   m_optimizer    = optimizer;
      m_async_orders = async_orders; m_health       = health;
      m_snapshot     = snapshot;
     }

   //+------------------------------------------------------------------+
   //| ExecutePipeline — drives all 14 stages sequentially             |
   //+------------------------------------------------------------------+
   ENUM_STAGE_RESULT ExecutePipeline(PipelineContext &ctx)
     {
      ENUM_STAGE_RESULT r;

      // Health gate
      if(ctx.health_status < 0)
        {
         if(m_debug_mode)
            PrintFormat("[Pipeline] ABORT: HealthStatus=%d (critical)", ctx.health_status);
         ctx.exit_reason  = STAGE_ABORT;
         ctx.exit_message = "Health gate: critical status";
         return STAGE_ABORT;
        }

      // Session drawdown gate — threshold from ctx (injected by Orchestrator)
      // BUG-N05 already fixed in PipelineTypes.mqh v1.05
      if(ctx.session_dd > 0.0 && ctx.max_session_dd > 0.0
         && ctx.session_dd >= ctx.max_session_dd)
        {
         if(m_debug_mode)
            PrintFormat("[Pipeline] SKIP: SessionDD=%.2f%% >= limit=%.2f%%",
                        ctx.session_dd, ctx.max_session_dd);
         Stage_Dashboard(ctx);
         Stage_Journal(ctx);
         return STAGE_SKIP;
        }

      // ── 14-stage sequential execution ──────────────────────────
      if((r = Stage_DataSync(ctx))       == STAGE_ABORT) { ctx.exit_reason = r; return r; }
      if((r = Stage_AnalysisSR(ctx))     == STAGE_ABORT) { ctx.exit_reason = r; return r; }
      if((r = Stage_AnalysisZone(ctx))   == STAGE_ABORT) { ctx.exit_reason = r; return r; }
      if((r = Stage_PatternRec(ctx))     == STAGE_ABORT) { ctx.exit_reason = r; return r; }
      if((r = Stage_RegimeDet(ctx))      == STAGE_ABORT) { ctx.exit_reason = r; return r; }
      if((r = Stage_SignalGen(ctx))      == STAGE_ABORT) { ctx.exit_reason = r; return r; }
      if((r = Stage_AIInfer(ctx))        == STAGE_ABORT) { ctx.exit_reason = r; return r; }
      if((r = Stage_RiskCheck(ctx))      == STAGE_ABORT) { ctx.exit_reason = r; return r; }
      if((r = Stage_AdaptiveParams(ctx)) == STAGE_ABORT) { ctx.exit_reason = r; return r; }
      if((r = Stage_Execution(ctx))      == STAGE_ABORT) { ctx.exit_reason = r; return r; }
      if((r = Stage_PosMgmt(ctx))        == STAGE_ABORT) { ctx.exit_reason = r; return r; }
      if((r = Stage_Recovery(ctx))       == STAGE_ABORT) { ctx.exit_reason = r; return r; }
      if((r = Stage_Dashboard(ctx))      == STAGE_ABORT) { ctx.exit_reason = r; return r; }
      if((r = Stage_Journal(ctx))        == STAGE_ABORT) { ctx.exit_reason = r; return r; }

      ctx.exit_reason = STAGE_OK;
      return STAGE_OK;
     }
  };

#endif // __CORE_PIPELINE_ENGINE_MQH__
