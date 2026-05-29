//+------------------------------------------------------------------+
//| Core/PipelineEngine.mqh — v2.03                                  |
//| AI-primary pipeline with rule-based fallback/context stages       |
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
   CExitEngine               *m_exit;
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

   void FillPriceContext(PipelineContext &ctx)
     {
      MqlTick tick;
      if(SymbolInfoTick(_Symbol, tick))
        {
         ctx.bid = tick.bid;
         ctx.ask = tick.ask;
        }
      else
        {
         ctx.bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         ctx.ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        }
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      ctx.spread_pts = (point > 0.0 && ctx.ask > ctx.bid) ? (ctx.ask - ctx.bid) / point : 0.0;
      ctx.atr_points = (m_data != NULL) ? m_data.GetATRPoints() : 0.0;
      ctx.atr = ctx.atr_points;
      ctx.bar_time = iTime(_Symbol, _Period, 0);
      ctx.market_open = (ctx.bid > 0.0 && ctx.ask > 0.0);
      ctx.session = DetectSession();
     }

   void InjectAIContext(PipelineContext &ctx)
     {
      if(m_ai_orch == NULL) return;
      double srDist = 0.5;
      double zoneStrength = 0.5;
      double patternScore = 0.5;

      if(m_sr != NULL && ctx.bid > 0.0)
        {
         SRZoneExtended z;
         if(m_sr.IsNearValidZone(ctx.bid, 0.5, z))
           {
            double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            double atrPrice = (ctx.atr_points > 0.0) ? ctx.atr_points : 0.0;
            double dist = MathAbs(ctx.bid - z.price);
            srDist = (atrPrice > 0.0) ? MathMax(0.0, MathMin(1.0, 1.0 - dist / MathMax(atrPrice, point))) : 0.5;
            zoneStrength = MathMax(0.0, MathMin(1.0, z.strength / 100.0));
           }
        }

      if(m_pattern != NULL)
        {
         SPatternResult pr = m_pattern.GetLastResult();
         if(pr.found)
            patternScore = MathMax(0.0, MathMin(1.0, pr.confluenceScore));

         SPatternFeatureSnapshot pf = m_pattern.GetLastFeatureSnapshot();
         CAIFeatureBuilder *fb = m_ai_orch.GetFeatureBuilder();
         if(fb != NULL)
            fb.InjectPatternFeatures(pf.buyProb, pf.sellProb, pf.conflict, pf.dominanceGap,
                                     pf.rejectionQuality, pf.trapQuality, pf.reclaimQuality,
                                     pf.followThrough);
        }

      m_ai_orch.InjectContext(srDist, zoneStrength, patternScore, ctx.regime);
     }

   ENUM_STAGE_RESULT Stage_DataSync(PipelineContext &ctx)
     {
      if(SkipIfNull(m_data, "DataSync") == STAGE_SKIP) return STAGE_SKIP;
      m_stage_timer.Start();
      m_data.OnTick();
      FillPriceContext(ctx);
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
      if(m_bus != NULL) m_bus.DispatchImmediate(ev);
      if(m_profiling_enabled) m_stage_timer.Log("Stage2_AnalysisSR");
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_AnalysisZone(PipelineContext &ctx)
     {
      if(SkipIfNull(m_zone, "AnalysisZone") == STAGE_SKIP) return STAGE_SKIP;
      m_stage_timer.Start();
      m_zone.OnPriceUpdate();
      if(ctx.new_bar) m_zone.OnNewBar();
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
         m_stage_timer.Start();
         if(ctx.new_bar) m_regime.OnNewBar();
         ctx.regime = m_regime.GetRegime();
         ctx.regime_confidence = m_regime.IsReady() ? 1.0 : 0.0;
         if(m_profiling_enabled) m_stage_timer.Log("Stage5_RegimeDet");
         return STAGE_OK;
        }
      if(SkipIfNull(m_regime_det, "RegimeDet") == STAGE_SKIP) return STAGE_SKIP;
      m_stage_timer.Start();
      ctx.regime = m_regime_det.GetCurrentRegime();
      const SDynamicParams &params = m_regime_det.GetParams();
      ctx.regime_confidence = MathMin(1.0, MathMax(0.0, params.trend_strength / 100.0));
      if(m_profiling_enabled) m_stage_timer.Log("Stage5_RegimeDet");
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_RuleFallbackSignal(PipelineContext &ctx)
     {
      if(SkipIfNull(m_signal, "RuleFallbackSignal") == STAGE_SKIP)
        {
         if(m_profiling_enabled) m_stage_timer.Log("Stage6_SignalGen");
         return STAGE_SKIP;
        }
      ctx.signal = m_signal.AggregateSignals();
      ctx.signal_strength = ctx.signal.confidence;
      if(m_debug_mode)
         PrintFormat("[Pipeline] RULE_FALLBACK Signal: dir=%d conf=%.3f src=%s", (int)ctx.signal.direction, ctx.signal.confidence, ctx.signal.primarySource);
      if(m_profiling_enabled) m_stage_timer.Log("Stage6_RuleFallbackSignal");
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_SignalGen(PipelineContext &ctx)
     {
      m_stage_timer.Start();
      ctx.signal.Clear();
      InjectAIContext(ctx);

      bool aiAvailable = (m_ai_orch != NULL && m_ai_orch.IsReady() && m_ai_orch.IsHealthy());
      if(!aiAvailable)
        {
         ctx.ai_result.model_healthy = false;
         ctx.exit_message = "AI unavailable; using rule fallback";
         return Stage_RuleFallbackSignal(ctx);
        }

      if(m_ai_orch.PredictSignal(ctx.signal))
        {
         const SAIInferenceResult &ai = m_ai_orch.GetLastResult();
         ctx.ai_score = (float)ai.score;
         ctx.ai_veto = ai.vetoed;
         ctx.drift_score = (float)ai.drift_score;
         ctx.ai_result.score = ctx.ai_score;
         ctx.ai_result.drift_index = ctx.drift_score;
         ctx.ai_result.model_healthy = true;
         ctx.signal_strength = ctx.signal.confidence;
         if(m_debug_mode)
            PrintFormat("[Pipeline] AI_PRIMARY Signal: dir=%d conf=%.3f src=%s", (int)ctx.signal.direction, ctx.signal.confidence, ctx.signal.primarySource);
         if(m_profiling_enabled) m_stage_timer.Log("Stage6_AIPrimarySignal");
         return STAGE_OK;
        }

      const SAIInferenceResult &last = m_ai_orch.GetLastResult();
      ctx.ai_score = (float)last.score;
      ctx.ai_veto = last.vetoed;
      ctx.drift_score = (float)last.drift_score;
      ctx.ai_result.score = ctx.ai_score;
      ctx.ai_result.drift_index = ctx.drift_score;
      ctx.ai_result.model_healthy = true;
      ctx.exit_message = last.vetoed ? last.veto_reason : "AI primary chose no trade";
      if(m_debug_mode)
         PrintFormat("[Pipeline] AI_PRIMARY no trade: %s", ctx.exit_message);
      if(m_profiling_enabled) m_stage_timer.Log("Stage6_AIPrimarySignal");
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_AIInfer(PipelineContext &ctx)
     {
      if(m_ai_orch == NULL) return STAGE_SKIP;
      ctx.ai_result.model_healthy = m_ai_orch.IsHealthy();
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
      if(!ctx.new_bar)
        {
         ctx.plan.valid = false;
         return STAGE_SKIP;
        }
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
      plan.comment = StringFormat("PASR|AI_PRIMARY|%.0f", ctx.signal.confidence * 100.0);
      plan.valid = (plan.direction != SIGNAL_NONE && plan.lot > 0 && plan.sl > 0 && plan.tp > 0);

      ctx.plan.direction = plan.direction;
      ctx.plan.entryPrice = plan.entryPrice;
      ctx.plan.sl = plan.sl;
      ctx.plan.tp = plan.tp;
      ctx.plan.slPoints = plan.slPoints;
      ctx.plan.tpPoints = ctx.signal.tpPoints;
      ctx.plan.lot = plan.lot;
      ctx.plan.valid = plan.valid;

      if(!plan.valid)
        {
         ctx.exit_message = "Execution skipped: invalid trade plan";
         if(m_profiling_enabled) m_stage_timer.Log("Stage10_Execution");
         return STAGE_SKIP;
        }

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
      if(SkipIfNull(m_exit, "PosMgmt") == STAGE_SKIP) return STAGE_SKIP;
      m_stage_timer.Start();

      CTrade trade;
      long cfgMagic = (m_data != NULL && m_data.GetConfig() != NULL) ? m_data.GetConfig().MagicNumber : 0;
      if(cfgMagic > 0) trade.SetExpertMagicNumber(cfgMagic);

      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;

         long magic = PositionGetInteger(POSITION_MAGIC);
         if(cfgMagic > 0 && magic != cfgMagic) continue;

         string sym = PositionGetString(POSITION_SYMBOL);
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         ENUM_ORDER_TYPE orderType = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         datetime entryTime = (datetime)PositionGetInteger(POSITION_TIME);
         double curPrice = (orderType == ORDER_TYPE_BUY)
                           ? SymbolInfoDouble(sym, SYMBOL_BID)
                           : SymbolInfoDouble(sym, SYMBOL_ASK);

         ExitSignal sig = m_exit.CheckExit(sym, orderType, entryPrice, curPrice, entryTime);
         if(sig.reason == EXIT_NONE) continue;

         bool closed = trade.PositionClose(ticket);
         if(m_debug_mode)
            PrintFormat("[PosMgmt] Exit %I64u reason=%d closed=%s desc=%s",
                        ticket, (int)sig.reason, closed ? "true" : "false", sig.description);
        }

      if(m_profiling_enabled) m_stage_timer.Log("Stage11_PosMgmt");
      return STAGE_OK;
     }

   ENUM_STAGE_RESULT Stage_Recovery(PipelineContext &ctx)
     {
      if(SkipIfNull(m_recovery, "Recovery") == STAGE_SKIP) return STAGE_SKIP;
      m_stage_timer.Start();
      m_recovery.OnPriceUpdate();
      if(ctx.new_bar) m_recovery.OnNewBar();
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
      if(m_profiling_enabled) m_stage_timer.Log("Stage14_Journal");
      return STAGE_OK;
     }

public:
   CPipelineEngine()
      : m_data(NULL), m_sr(NULL), m_zone(NULL), m_pattern(NULL), m_signal(NULL),
        m_ai_orch(NULL), m_regime(NULL), m_risk(NULL), m_exec(NULL), m_exit(NULL),
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
      CHealthMonitor *health=NULL, CSnapshotManager *snapshot=NULL,
      CExitEngine *exit_engine=NULL)
     {
      m_data=data; m_sr=sr; m_zone=zone; m_pattern=pattern; m_signal=signal;
      m_ai_orch=ai_orch; m_regime=regime; m_risk=risk; m_exec=exec;
      m_exit=exit_engine; m_recovery=recovery; m_dash=dash; m_journal=journal; m_bus=bus;
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