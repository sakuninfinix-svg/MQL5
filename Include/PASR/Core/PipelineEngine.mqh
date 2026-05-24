//+------------------------------------------------------------------+
//| Core/PipelineEngine.mqh — v1.03                                  |
//| Full 14-stage pipeline implementation.                           |
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_PIPELINE_ENGINE_MQH__
#define __CORE_PIPELINE_ENGINE_MQH__

#ifdef __CORE_PASR_MASTER_MQH__
#else
  #error "Include <PASR/Core/PASR.mqh> instead of PipelineEngine.mqh directly."
#endif

class CPipelineEngine
  {
private:
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
   CHealthMonitor            *m_health;
   CSnapshotManager          *m_snapshot;

   bool   m_debug_mode;
   bool   m_profiling_enabled;
   CPerfTimer m_stage_timer;

   ENUM_STAGE_RESULT SkipIfNull(const void *ptr, const string stageName)
     {
      if(ptr == NULL)
        {
         if(m_debug_mode) PrintFormat("[Pipeline] %s SKIP: manager is NULL", stageName);
         return STAGE_SKIP;
        }
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_DataSync(PipelineContext &ctx)
     {
      if(SkipIfNull(m_data, "DataSync") == STAGE_SKIP) return STAGE_SKIP;
      m_stage_timer.Start();
      m_data.OnTick();
      if(m_profiling_enabled) m_stage_timer.Log("Stage1_DataSync");
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_AnalysisSR(PipelineContext &ctx)
     {
      if(SkipIfNull(m_sr, "AnalysisSR") == STAGE_SKIP) return STAGE_SKIP;
      if(!ctx.new_bar) return STAGE_SKIP;
      m_stage_timer.Start();
      PASREvent ev;
      ev.id = EVENT_ID_NEW_BAR;
      ev.priority = 10;
      if(m_bus != NULL) m_bus.Dispatch(ev);
      if(m_profiling_enabled) m_stage_timer.Log("Stage2_AnalysisSR");
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_AnalysisZone(PipelineContext &ctx)
     {
      if(SkipIfNull(m_zone, "AnalysisZone") == STAGE_SKIP) return STAGE_SKIP;
      if(!ctx.new_bar) return STAGE_SKIP;
      m_stage_timer.Start();
      m_zone.Update();
      if(m_profiling_enabled) m_stage_timer.Log("Stage3_AnalysisZone");
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_PatternRec(PipelineContext &ctx)
     {
      if(SkipIfNull(m_pattern, "PatternRec") == STAGE_SKIP) return STAGE_SKIP;
      m_stage_timer.Start();
      m_pattern.OnTick();
      if(m_profiling_enabled) m_stage_timer.Log("Stage4_PatternRec");
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_RegimeDet(PipelineContext &ctx)
     {
      if(m_regime != NULL)
        {
         m_regime.OnNewBar();
         ctx.regime = m_regime.GetRegime();
         return STAGE_OK;
        }
      if(SkipIfNull(m_regime_det, "RegimeDet") == STAGE_SKIP) return STAGE_SKIP;
      m_stage_timer.Start();
      ctx.regime = m_regime_det.GetCurrentRegime();
      if(m_profiling_enabled) m_stage_timer.Log("Stage5_RegimeDet");
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_SignalGen(PipelineContext &ctx)
     {
      if(SkipIfNull(m_signal, "SignalGen") == STAGE_SKIP) return STAGE_SKIP;
      m_stage_timer.Start();
      ctx.signal = m_signal.AggregateSignals();
      if(m_debug_mode)
         PrintFormat("[Pipeline] SignalGen: dir=%d conf=%.3f src=%s", (int)ctx.signal.direction, ctx.signal.confidence, ctx.signal.primarySource);
      if(m_profiling_enabled) m_stage_timer.Log("Stage6_SignalGen");
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_AIInfer(PipelineContext &ctx)
     {
      if(SkipIfNull(m_ai_orch, "AIInfer") == STAGE_SKIP) return STAGE_SKIP;
      m_stage_timer.Start();
      ctx.ai_score = m_ai_orch.Evaluate();
      if(m_profiling_enabled) m_stage_timer.Log("Stage7_AIInfer");
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_RiskCheck(PipelineContext &ctx)
     {
      if(SkipIfNull(m_risk, "RiskCheck") == STAGE_SKIP) return STAGE_SKIP;
      if(ctx.signal.direction == SIGNAL_NONE) return STAGE_SKIP;
      m_stage_timer.Start();
      ctx.risk_result = m_risk.CheckRisk(ctx.signal);
      if(!ctx.risk_result.allowed)
        {
         if(m_debug_mode) PrintFormat("[Pipeline] RiskCheck REJECTED: %s", ctx.risk_result.reason);
         ctx.exit_message = "RiskCheck: " + ctx.risk_result.reason;
         if(m_profiling_enabled) m_stage_timer.Log("Stage8_RiskCheck");
         return STAGE_SKIP;
        }
      ctx.trading_allowed = true;
      if(m_profiling_enabled) m_stage_timer.Log("Stage8_RiskCheck");
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_AdaptiveParams(PipelineContext &ctx)
     {
      if(SkipIfNull(m_adaptive, "AdaptiveParams") == STAGE_SKIP) return STAGE_SKIP;
      if(!ctx.new_bar) return STAGE_SKIP;
      m_stage_timer.Start();
      m_adaptive.OnNewBar();
      if(m_profiling_enabled) m_stage_timer.Log("Stage9_AdaptiveParams");
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_Execution(PipelineContext &ctx)
     {
      if(SkipIfNull(m_exec, "Execution") == STAGE_SKIP) return STAGE_SKIP;
      if(ctx.signal.direction == SIGNAL_NONE) return STAGE_SKIP;
      if(!ctx.risk_result.allowed) return STAGE_SKIP;
      m_stage_timer.Start();

      TradePlan plan;
      plan.Clear();
      plan.direction = ctx.signal.direction;
      plan.entryPrice = ctx.risk_result.entryPrice;
      plan.sl = ctx.risk_result.stopLoss;
      plan.tp = ctx.risk_result.takeProfit;
      plan.lot = ctx.risk_result.lotSize;
      plan.slPoints = ctx.signal.slPoints;
      plan.comment = StringFormat("PASR|PIPE|%.0f", ctx.signal.confidence * 100.0);
      plan.valid = (plan.direction != SIGNAL_NONE && plan.lot > 0 && plan.sl > 0 && plan.tp > 0);
      ctx.plan.direction = plan.direction;
      ctx.plan.entryPrice = plan.entryPrice;
      ctx.plan.sl = plan.sl;
      ctx.plan.tp = plan.tp;
      ctx.plan.slPoints = plan.slPoints;
      ctx.plan.lot = plan.lot;
      ctx.plan.valid = plan.valid;

      ctx.exec_result = m_exec.Execute(plan);

      if(ctx.exec_result.status == EXEC_FAIL)
        {
         if(m_debug_mode) PrintFormat("[Pipeline] Execution FAILED: %s", ctx.exec_result.comment);
         ctx.exit_reason = STAGE_ABORT;
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
         PrintFormat("[Pipeline] Execution status=%d ticket=%I64u price=%.5f lot=%.2f", (int)ctx.exec_result.status, ctx.exec_result.ticket, plan.entryPrice, plan.lot);
      if(m_profiling_enabled) m_stage_timer.Log("Stage10_Execution");
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_PosMgmt(PipelineContext &ctx)
     {
      if(SkipIfNull(m_exec, "PosMgmt") == STAGE_SKIP) return STAGE_SKIP;
      m_stage_timer.Start();
      m_exec.ManagePositions();
      if(m_profiling_enabled) m_stage_timer.Log("Stage11_PosMgmt");
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_Recovery(PipelineContext &ctx)
     {
      if(SkipIfNull(m_recovery, "Recovery") == STAGE_SKIP) return STAGE_SKIP;
      m_stage_timer.Start();
      m_recovery.OnPriceUpdate();
      if(ctx.new_bar)
         m_recovery.OnNewBar();
      if(m_profiling_enabled) m_stage_timer.Log("Stage12_Recovery");
      return STAGE_OK;
     }

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

   ENUM_STAGE_RESULT Stage_Journal(PipelineContext &ctx)
     {
      if(SkipIfNull(m_journal, "Journal") == STAGE_SKIP) return STAGE_SKIP;
      if(!ctx.new_bar) return STAGE_SKIP;
      m_stage_timer.Start();
      m_journal.LogEntry(ctx);
      if(m_telemetry != NULL) m_telemetry.RecordBarEvent(ctx);
      if(m_profiling_enabled) m_stage_timer.Log("Stage14_Journal");
      return STAGE_OK;
     }

public:
   CPipelineEngine()
      : m_data(NULL), m_sr(NULL), m_zone(NULL), m_pattern(NULL), m_signal(NULL),
        m_ai_orch(NULL), m_regime(NULL), m_risk(NULL), m_exec(NULL),
        m_recovery(NULL), m_dash(NULL), m_journal(NULL), m_bus(NULL),
        m_sanity(NULL), m_telemetry(NULL), m_adaptive(NULL), m_regime_det(NULL),
        m_optimizer(NULL), m_async_orders(NULL), m_health(NULL), m_snapshot(NULL),
        m_debug_mode(false), m_profiling_enabled(true)
     {}

   void SetDebugMode(bool on) { m_debug_mode = on; }
   void EnableProfiling(bool on) { m_profiling_enabled = on; }

   void InjectManagers(CDataManager *data, CAnalysisSRManager *sr, CAnalysisZoneManager *zone,
      CPatternManager *pattern, CSignalManager *signal, CAIOrchestrator *ai_orch,
      CRegimeFilter *regime, CRiskManager *risk, CExecutionManager *exec,
      CRecoveryManager *recovery, CDashboardManager *dash, CJournalManager *journal,
      CEventBus *bus, CSanityManager *sanity, CTelemetryRecorder *telemetry,
      CAdaptiveParameterManager *adaptive, CMarketRegimeDetector *regime_det,
      CLatencyOptimizer *optimizer=NULL, CAsyncOrderManager *async_orders=NULL,
      CHealthMonitor *health=NULL, CSnapshotManager *snapshot=NULL)
     {
      m_data=data; m_sr=sr; m_zone=zone; m_pattern=pattern; m_signal=signal;
      m_ai_orch=ai_orch; m_regime=regime; m_risk=risk; m_exec=exec;
      m_recovery=recovery; m_dash=dash; m_journal=journal; m_bus=bus;
      m_sanity=sanity; m_telemetry=telemetry; m_adaptive=adaptive;
      m_regime_det=regime_det; m_optimizer=optimizer; m_async_orders=async_orders;
      m_health=health; m_snapshot=snapshot;
     }

   ENUM_STAGE_RESULT ExecutePipeline(PipelineContext &ctx)
     {
      ENUM_STAGE_RESULT r;
      if(ctx.health_status < 0)
        {
         ctx.exit_reason = STAGE_ABORT;
         ctx.exit_message = "Health gate: critical status";
         return STAGE_ABORT;
        }
      if(ctx.session_dd > 0.0 && ctx.max_session_dd > 0.0 && ctx.session_dd >= ctx.max_session_dd)
        {
         Stage_Dashboard(ctx);
         Stage_Journal(ctx);
         return STAGE_SKIP;
        }
      if((r=Stage_DataSync(ctx))==STAGE_ABORT) return r;
      if((r=Stage_AnalysisSR(ctx))==STAGE_ABORT) return r;
      if((r=Stage_AnalysisZone(ctx))==STAGE_ABORT) return r;
      if((r=Stage_PatternRec(ctx))==STAGE_ABORT) return r;
      if((r=Stage_RegimeDet(ctx))==STAGE_ABORT) return r;
      if((r=Stage_SignalGen(ctx))==STAGE_ABORT) return r;
      if((r=Stage_AIInfer(ctx))==STAGE_ABORT) return r;
      if((r=Stage_RiskCheck(ctx))==STAGE_ABORT) return r;
      if((r=Stage_AdaptiveParams(ctx))==STAGE_ABORT) return r;
      if((r=Stage_Execution(ctx))==STAGE_ABORT) return r;
      if((r=Stage_PosMgmt(ctx))==STAGE_ABORT) return r;
      if((r=Stage_Recovery(ctx))==STAGE_ABORT) return r;
      if((r=Stage_Dashboard(ctx))==STAGE_ABORT) return r;
      if((r=Stage_Journal(ctx))==STAGE_ABORT) return r;
      ctx.exit_reason = STAGE_OK;
      return STAGE_OK;
     }
  };

#endif // __CORE_PIPELINE_ENGINE_MQH__
