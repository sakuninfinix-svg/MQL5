//+------------------------------------------------------------------+
//|                               Core/Orchestrator.mqh             |
//|                          Copyright 2026, Agsicentre             |
//|                                                                  |
//|  PURPOSE: Owns and wires all PASR managers.                      |
//|    EA's OnInit/OnTick/OnDeinit/OnTradeTransaction → delegate    |
//|    to COrchestrator with one call each.                         |
//|                                                                  |
//|  CHANGELOG:                                                      |
//|  v3.04 (2026-05-23) — Sprint 8: Runtime State Ownership wiring   |
//|    S8-002: Added CSessionState *m_session (single owner of DD)  |
//|    S8-003: PipelineContext injected with health/session state    |
//|    S8-004: Added OnEvent() — SYSTEM_RECOVER/HALT/CRITICAL        |
//|    S8-005: Fixed evHealth.data_i[0] → evHealth.data1            |
//|    S8-006: PrintSummary() updated with SessionState line        |
//|    S8-007: OnTradeTransaction calls m_session->RecordTrade()    |
//|    S8-008: FreeAll() deletes m_session in reverse init order    |
//|  v3.03 (2026-05-23) — Sprint 2 Bug Fixes:                       |
//|    BUG-002: Removed monolith ProcessNewBar() fallback in OnTick  |
//|    BUG-004: Health+Snapshot registered via InitManager() properly|
//|    BUG-005: FreeAll() fixed to strict reverse init order         |
//|    BUG-009: Constructor init list completed (health, snapshot)    |
//|    BUG-010: Eliminated redundant double DrainQueue() in OnTick() |
//|  v3.02 (2026-05-22) — Phase 3+4 Telemetry + Latency Sim         |
//|  v3.01 (2026-05-21) — Phase 5 Circuit Breaker                   |
//|  v3.00 (2026-05-21) — Phase 4 wiring                            |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property strict

#ifndef __CORE_ORCHESTRATOR_MQH__
#define __CORE_ORCHESTRATOR_MQH__

#ifdef __CORE_PASR_MASTER_MQH__
  // OK — included via PASR.mqh
#else
  #error "Include <PASR/Core/PASR.mqh> instead of Orchestrator.mqh directly."
#endif

//+------------------------------------------------------------------+
//| COrchestrator — owns all managers, wires them together           |
//+------------------------------------------------------------------+
class COrchestrator
  {
private:
   // ── Managers (owned, heap-allocated) ───────────────────────
   CDataManager           *m_data;
   CAnalysisSRManager     *m_sr;
   CAnalysisZoneManager   *m_zone;
   CPatternManager        *m_pattern;
   CSignalManager         *m_signal;
   CAIOrchestrator        *m_ai_orch;
   CMarketRegimeDetector  *m_regime_det;
   CRegimeFilter          *m_regime;
   CRiskManager           *m_risk;
   CExecutionManager      *m_exec;
   CRecoveryManager       *m_recovery;
   CDashboardManager      *m_dash;
   CSanityManager         *m_sanity;
   CTelemetryRecorder     *m_telemetry;
   CAdaptiveParameterManager *m_adaptive;

   // ── Phase 6: Low Latency ────────────────────────────────
   CLatencyOptimizer      *m_optimizer;
   CAsyncOrderManager     *m_async_orders;
   CHighFreqTimer         *m_hf_timer;

   // ── Phase 7: Self-Healing + Runtime State Ownership ──────────
   CHealthMonitor         *m_health;
   CSnapshotManager       *m_snapshot;
   CSessionState          *m_session;    // S8-002: single owner of daily DD / session PnL

   // ── QA (testing only) ──────────────────────────────────
   CLatencySimulator      *m_latency_sim;

   // ── Signal source plugins (owned) ───────────────────────
   PatternSignalSource    *m_srcPattern;
   SRSignalSource         *m_srcSR;
   AISignalSource         *m_srcAI;
   CRegimeSignalSource    *m_srcRegime;

   // ── Infrastructure ───────────────────────────────────
   CEventBus              *m_bus;
   StrategyConfig          m_cfg;
   CConfigManager         *m_cfgMgr;

   // ── Pipeline Engine ──────────────────────────────────
   CPipelineEngine        *m_pipeline;
   PipelineContext         m_pipeline_ctx;

   datetime   m_lastBarTime;
   bool       m_debugMode;
   bool       m_initialised;
   bool       m_profiling_enabled;

   // ── Bar detection ────────────────────────────────────
   bool BarChanged()
     {
      datetime t = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
      if(t != m_lastBarTime) { m_lastBarTime = t; return true; }
      return false;
     }

   // ── Manager registration helpers ─────────────────────────
   void RegisterManager(IManager *mgr)
     {
      if(mgr == NULL) return;
      mgr.DeclareEvents();
      m_bus.Register(mgr);
     }

   bool InitManager(IManager *mgr, const string name)
     {
      if(mgr == NULL)
        { PrintFormat("[Orchestrator] %s: alloc failed", name); return false; }
      if(m_debugMode) mgr.SetDebugMode(true);
      if(!mgr.Init(m_data, m_bus))
        { PrintFormat("[Orchestrator] %s.Init() FAILED", name); return false; }
      RegisterManager(mgr);
      return true;
     }

   // ── Event queue drain ─────────────────────────────────
   void DrainQueue()
     {
      PASREvent ev;
      while(m_bus.Pop(ev))
        {
         m_bus.Dispatch(ev);
         OnEvent(ev);   // S8-004: orchestrator handles SYSTEM_RECOVER/HALT/CRITICAL
        }
     }

   // ── Init summary log ──────────────────────────────────
   void PrintSummary()
     {
      Print("╔══════════════════════════════════════════════════╗");
      PrintFormat("║  PASR EA v3.04 — %s  %s", _Symbol,
                  EnumToString((ENUM_TIMEFRAMES)_Period));
      Print("╠══════════════════════════════════════════════════╣");
      Print("║  Managers:");
      PrintFormat("║    DataManager        : OK");
      PrintFormat("║    SRManager(Analysis): OK  zones=%d",
                  m_sr != NULL ? m_sr.ZoneCount() : 0);
      PrintFormat("║    ZoneManager(S/D)   : OK");
      PrintFormat("║    PatternManager     : OK");
      PrintFormat("║    SignalManager v3   : OK  sources=%d",
                  m_signal != NULL ? m_signal.SourceCount() : 0);
      PrintFormat("║      PatternSignalSource w=1.2 VOTER");
      PrintFormat("║      SRSignalSource      w=1.5 VOTER");
      PrintFormat("║      AISignalSource      w=0.8 VOTER");
      PrintFormat("║      RegimeSignalSource  w=0.0 MULT");
      PrintFormat("║    CAIOrchestrator [P7]: OK  (26-dim AI)");
      PrintFormat("║    RegimeFilter    [P4]: OK");
      PrintFormat("║    RiskManager     [P4]: OK  magic=%d", m_cfg.MagicNumber);
      PrintFormat("║    ExecutionManager    : OK");
      PrintFormat("║    RecoveryManager     : OK");
      PrintFormat("║    DashboardManager v3 : OK");
      PrintFormat("║    SanityManager  [P5] : OK  CircuitBreaker=ACTIVE");
      PrintFormat("║    TelemetryRec   [P3] : OK  CSV=ENABLED");
      PrintFormat("║    AdaptiveParams [P5] : OK  DynamicSL/TP=ACTIVE");
      PrintFormat("║    HealthMonitor  [P7] : OK  Self-Healing=ACTIVE");
      PrintFormat("║    SnapshotMgr    [P7] : OK  StatePersistence=ACTIVE");
      PrintFormat("║    SessionState   [P7] : OK  SingleOwner=ACTIVE");  // S8-006
      #ifdef PASR_QA_BUILD
      PrintFormat("║    LatencySim [P4/QA]  : OK  Backtest=ACTIVE");
      #endif
      Print("╚══════════════════════════════════════════════════╝");
     }

   //+----------------------------------------------------------------+
   //| FreeAll — strict REVERSE init order                           |
   //| Rule: Phase N deleted FIRST, Phase 0 (EventBus) deleted LAST  |
   //| Violating this causes use-after-free on shutdown               |
   //+----------------------------------------------------------------+
   void FreeAll()
     {
      // ── Pipeline engine (non-owning refs, safe to delete first) ──
      if(m_pipeline) { delete m_pipeline; m_pipeline = NULL; }

      // ── Phase 7: Self-Healing (last inited → first freed) ─────
      // S8-008: m_session added in correct reverse-init order
      if(m_session)     { delete m_session;     m_session = NULL;     }
      if(m_snapshot)    { delete m_snapshot;    m_snapshot = NULL;    }
      if(m_health)      { delete m_health;      m_health = NULL;      }

      // ── QA (only if QA_BUILD) ─────────────────────────────
      #ifdef PASR_QA_BUILD
      if(m_latency_sim) { delete m_latency_sim; m_latency_sim = NULL; }
      #endif

      // ── Phase 6: Low Latency ─────────────────────────────
      if(m_hf_timer)     { delete m_hf_timer;     m_hf_timer = NULL;     }
      if(m_async_orders) { delete m_async_orders; m_async_orders = NULL; }
      if(m_optimizer)    { delete m_optimizer;    m_optimizer = NULL;    }

      // ── Phase 5: Adaptive + Regime Det ────────────────────
      if(m_adaptive)    { delete m_adaptive;    m_adaptive = NULL;    }
      if(m_regime_det)  { delete m_regime_det;  m_regime_det = NULL;  }

      // ── Phase 3: Telemetry ───────────────────────────────
      if(m_telemetry)   { delete m_telemetry;   m_telemetry = NULL;   }

      // ── Phase 1: Sanity ───────────────────────────────────
      if(m_sanity)      { delete m_sanity;      m_sanity = NULL;      }

      // ── Signal source plugins (before managers they reference) ──
      if(m_srcRegime)   { delete m_srcRegime;   m_srcRegime = NULL;   }
      if(m_srcPattern)  { delete m_srcPattern;  m_srcPattern = NULL;  }
      if(m_srcSR)       { delete m_srcSR;       m_srcSR = NULL;       }
      if(m_srcAI)       { delete m_srcAI;       m_srcAI = NULL;       }

      // ── L7: Dashboard ────────────────────────────────────
      if(m_dash)        { delete m_dash;        m_dash = NULL;        }

      // ── L6b: Recovery ──────────────────────────────────
      if(m_recovery)    { delete m_recovery;    m_recovery = NULL;    }

      // ── L6a: Execution ─────────────────────────────────
      if(m_exec)        { delete m_exec;        m_exec = NULL;        }

      // ── L5d: Risk ─────────────────────────────────────
      if(m_risk)        { delete m_risk;        m_risk = NULL;        }

      // ── L5c: Regime ───────────────────────────────────
      if(m_regime)      { delete m_regime;      m_regime = NULL;      }

      // ── L5b: AI Orchestrator ─────────────────────────────
      if(m_ai_orch)     { delete m_ai_orch;     m_ai_orch = NULL;     }

      // ── L5a: Signal ────────────────────────────────────
      if(m_signal)      { delete m_signal;      m_signal = NULL;      }

      // ── L4: Pattern ────────────────────────────────────
      if(m_pattern)     { delete m_pattern;     m_pattern = NULL;     }

      // ── L3: Zone + SR ──────────────────────────────────
      if(m_zone)        { delete m_zone;        m_zone = NULL;        }
      if(m_sr)          { delete m_sr;          m_sr = NULL;          }

      // ── L2: DataManager ─────────────────────────────────
      if(m_data)        { delete m_data;        m_data = NULL;        }

      // ── Config ─────────────────────────────────────────
      if(m_cfgMgr)      { delete m_cfgMgr;      m_cfgMgr = NULL;      }

      // ── EventBus LAST — everything above depends on it ────────
      if(m_bus)         { delete m_bus;         m_bus = NULL;         }
     }

public:
   // S8-002 FIX: m_session added to constructor init list
   COrchestrator()
      : m_data(NULL), m_sr(NULL), m_zone(NULL),
        m_pattern(NULL), m_signal(NULL), m_ai_orch(NULL),
        m_regime_det(NULL), m_regime(NULL), m_risk(NULL),
        m_exec(NULL), m_recovery(NULL), m_dash(NULL),
        m_sanity(NULL), m_telemetry(NULL), m_adaptive(NULL),
        m_optimizer(NULL), m_async_orders(NULL), m_hf_timer(NULL),
        m_health(NULL), m_snapshot(NULL), m_session(NULL),
        m_latency_sim(NULL),
        m_srcPattern(NULL), m_srcSR(NULL),
        m_srcAI(NULL), m_srcRegime(NULL),
        m_bus(NULL), m_cfgMgr(NULL),
        m_pipeline(NULL),
        m_lastBarTime(0), m_debugMode(false),
        m_initialised(false), m_profiling_enabled(true)
     {
      m_pipeline_ctx.Reset();
     }

   ~COrchestrator() { FreeAll(); }

   void SetDebugMode(bool on)
     {
      m_debugMode = on;
      if(m_pipeline != NULL) m_pipeline->SetDebugMode(on);
     }

   void SetProfilingEnabled(bool on)
     {
      m_profiling_enabled = on;
      if(m_pipeline != NULL) m_pipeline->EnableProfiling(on);
     }

   //+----------------------------------------------------------------+
   //| Init                                                           |
   //+----------------------------------------------------------------+
   int Init()
     {
      // ── L0: Config ────────────────────────────────────────
      m_cfgMgr = new CConfigManager();
      if(m_cfgMgr==NULL || !m_cfgMgr.Init(m_cfg))
        { Print("[Orchestrator] Config FAILED"); return INIT_PARAMETERS_INCORRECT; }

      m_bus = new CEventBus();
      if(m_bus==NULL)
        { Print("[Orchestrator] EventBus alloc FAILED"); return INIT_FAILED; }

      // ── L2: DataManager ────────────────────────────────
      m_data = new CDataManager();
      if(m_data==NULL || !m_data.Init(m_cfg))
        { Print("[Orchestrator] DataManager FAILED"); FreeAll(); return INIT_FAILED; }

      // ── L3: Analysis — SR + Zone ────────────────────────
      m_sr = new CAnalysisSRManager();
      if(!InitManager(m_sr, "CAnalysisSRManager")) { FreeAll(); return INIT_FAILED; }

      m_zone = new CAnalysisZoneManager();
      if(!InitManager(m_zone, "CAnalysisZoneManager")) { FreeAll(); return INIT_FAILED; }

      // ── L4: Pattern ────────────────────────────────────
      m_pattern = new CPatternManager();
      if(!InitManager(m_pattern, "CPatternManager")) { FreeAll(); return INIT_FAILED; }

      // ── L5a: SignalManager ──────────────────────────────
      m_signal = new CSignalManager();
      if(!InitManager(m_signal, "CSignalManager")) { FreeAll(); return INIT_FAILED; }
      m_signal.SetPatternManager(m_pattern);
      m_signal.SetSRManager((CSRManager*)m_sr);

      m_srcPattern = new PatternSignalSource(m_pattern);
      m_srcSR      = new SRSignalSource(m_sr, m_data, 0.5);
      m_signal.RegisterSource(m_srcPattern, 1.2);
      m_signal.RegisterSource(m_srcSR,      1.5);

      // ── L5b: CAIOrchestrator + AISignalSource ────────────────
      m_ai_orch = new CAIOrchestrator();
      if(!InitManager(m_ai_orch, "CAIOrchestrator")) { FreeAll(); return INIT_FAILED; }
      m_srcAI = new AISignalSource(m_ai_orch, 0.6, 0.8);
      m_signal.RegisterSource(m_srcAI, 0.8);

      // ── L5c: RegimeFilter + RegimeSignalSource ───────────────
      m_regime = new CRegimeFilter();
      if(!InitManager(m_regime, "CRegimeFilter")) { FreeAll(); return INIT_FAILED; }
      m_signal.SetRegimeManager((CMarketRegime*)m_regime);
      m_srcRegime = new CRegimeSignalSource(m_regime);
      m_signal.RegisterSource(m_srcRegime, 0.0);

      // ── L5d: RiskManager ───────────────────────────────
      m_risk = new CRiskManager();
      if(!InitManager(m_risk, "CRiskManager")) { FreeAll(); return INIT_FAILED; }

      // ── L6a: ExecutionManager ────────────────────────────
      m_exec = new CExecutionManager();
      if(!InitManager(m_exec, "CExecutionManager")) { FreeAll(); return INIT_FAILED; }

      // ── L6b: RecoveryManager ────────────────────────────
      m_recovery = new CRecoveryManager();
      if(!InitManager(m_recovery, "CRecoveryManager")) { FreeAll(); return INIT_FAILED; }

      // ── L7: DashboardManager ────────────────────────────
      m_dash = new CDashboardManager();
      if(!InitManager(m_dash, "CDashboardManager")) { FreeAll(); return INIT_FAILED; }
      m_dash.SetRiskManager(m_risk);
      m_dash.SetSignalManager(m_signal);
      m_dash.SetRegimeFilter(m_regime);

      // ── L7b: SanityManager ─────────────────────────────
      m_sanity = new CSanityManager();
      if(!InitManager(m_sanity, "CSanityManager")) { FreeAll(); return INIT_FAILED; }
      SSanityConfig sanityCfg;
      sanityCfg.max_stale_ticks   = 5;
      sanityCfg.max_spread_points = 20;
      sanityCfg.max_price_gap_pct = 0.5;
      sanityCfg.trip_threshold    = 3;
      sanityCfg.reset_timeout_sec = 60;
      m_sanity->Initialize(sanityCfg);

      // ── L7c: TelemetryRecorder ───────────────────────────
      m_telemetry = new CTelemetryRecorder();
      if(!InitManager(m_telemetry, "CTelemetryRecorder")) { FreeAll(); return INIT_FAILED; }

      // ── L7d: AdaptiveParameterManager ────────────────────
      m_adaptive = new CAdaptiveParameterManager();
      if(!InitManager(m_adaptive, "CAdaptiveParameterManager")) { FreeAll(); return INIT_FAILED; }
      m_adaptive->Initialize(m_data, m_bus,
                             m_cfg.Risk.StopLossPoints,
                             m_cfg.Risk.TakeProfitPoints,
                             m_cfg.Risk.MaxRiskPercent);

      // ── L7e: MarketRegimeDetector ────────────────────────
      m_regime_det = new CMarketRegimeDetector();
      if(!InitManager(m_regime_det, "CMarketRegimeDetector")) { FreeAll(); return INIT_FAILED; }
      m_regime_det->Initialize(_Symbol, _Period);

      // ── L7f: Phase 6 Low Latency ────────────────────────
      m_optimizer = new CLatencyOptimizer();
      if(!InitManager(m_optimizer, "CLatencyOptimizer")) { FreeAll(); return INIT_FAILED; }
      m_optimizer->Initialize(100);

      m_async_orders = new CAsyncOrderManager();
      if(!InitManager(m_async_orders, "CAsyncOrderManager")) { FreeAll(); return INIT_FAILED; }
      m_async_orders->Initialize(m_optimizer, m_exec);

      m_hf_timer = new CHighFreqTimer();
      if(!InitManager(m_hf_timer, "CHighFreqTimer")) { FreeAll(); return INIT_FAILED; }
      m_hf_timer->Start(10);

      // ── L7g: Phase 7 Self-Healing ────────────────────────
      m_health = new CHealthMonitor();
      if(!InitManager(m_health, "CHealthMonitor")) { FreeAll(); return INIT_FAILED; }
      m_health->PostInit(m_bus);

      m_snapshot = new CSnapshotManager();
      if(!InitManager(m_snapshot, "CSnapshotManager")) { FreeAll(); return INIT_FAILED; }
      string snapshotPath = "PASR\\Snapshots";
      m_snapshot->PostInit(snapshotPath);

      SystemStateSnapshot savedState;
      if(m_snapshot->LoadLatestSnapshot(savedState))
         PrintFormat("[Orchestrator] Recovered from snapshot. Uptime was: %ds",
                     savedState.uptime_seconds);

      // ── L7h: SessionState — S8-002 NEW ─────────────────────
      // Single owner of daily DD, session PnL, and equity baseline.
      // All other managers must read via GetSnapshot() only — no direct writes.
      m_session = new CSessionState();
      if(!InitManager(m_session, "CSessionState")) { FreeAll(); return INIT_FAILED; }
      m_session->SetMagic(m_cfg.MagicNumber);
      m_session->SyncEquity();   // baseline equity for the session

      // ── QA: LatencySimulator (QA Build Only) ───────────────
      #ifdef PASR_QA_BUILD
      m_latency_sim = new CLatencySimulator();
      if(!InitManager(m_latency_sim, "CLatencySimulator")) { FreeAll(); return INIT_FAILED; }
      #endif

      // ── L8: Pipeline Engine ─────────────────────────────
      m_pipeline = new CPipelineEngine();
      if(m_pipeline == NULL)
        { Print("[Orchestrator] Pipeline engine alloc FAILED"); FreeAll(); return INIT_FAILED; }

      CJournalManager *journal = NULL;
      m_pipeline->InjectManagers(
         m_data, m_sr, m_zone, m_pattern, m_signal,
         m_ai_orch, m_regime, m_risk, m_exec, m_recovery,
         m_dash, journal, m_bus, m_sanity, m_telemetry, m_adaptive,
         m_regime_det, m_optimizer, m_async_orders,
         m_health, m_snapshot
      );
      m_pipeline->SetDebugMode(m_debugMode);
      m_pipeline->EnableProfiling(m_profiling_enabled);

      m_initialised = true;
      PrintSummary();
      return INIT_SUCCEEDED;
     }

   //+----------------------------------------------------------------+
   //| OnEvent — S8-004: Orchestrator-level system event handler     |
   //| Called from DrainQueue() after m_bus.Dispatch(ev).            |
   //| Handles events that require Orchestrator-owned state changes.  |
   //| RULE: Only handle SYSTEM_* events here. Business logic belongs |
   //|       inside the respective manager's OnEvent() method.       |
   //+----------------------------------------------------------------+
   void OnEvent(const PASREvent &ev)
     {
      switch(ev.id)
        {
         //-----------------------------------------------------------
         // S8-004: Health has completed self-recovery sequence.
         // Orchestrator must clear the flag so health check resumes.
         case EVENT_ID_SYSTEM_RECOVER:
            if(m_health != NULL)
              {
               m_health->ResetRecoveryFlag();
               if(m_debugMode)
                  Print("[Orchestrator] Recovery complete: health flag reset.");
              }
            break;

         //-----------------------------------------------------------
         // Critical warning: log with full context but keep running.
         case EVENT_ID_SYSTEM_CRITICAL:
            PrintFormat("[Orchestrator] !! SYSTEM_CRITICAL: tag=%s d1=%.4f d2=%.4f",
                        ev.tag, ev.data1, ev.data2);
            break;

         //-----------------------------------------------------------
         // Hard halt: stops all pipeline execution immediately.
         // FreeAll() not called here — OnDeinit() will do it cleanly.
         case EVENT_ID_SYSTEM_HALT:
            Print("[Orchestrator] SYSTEM_HALT received — orchestration stopped.");
            m_initialised = false;
            break;

         default:
            break;
        }
     }

   //+----------------------------------------------------------------+
   //| OnTick — BUG-002 + BUG-010 FIX (unchanged from v3.03)        |
   //| RULE: OnTick() is PURE EVENT-PUSH ONLY.                       |
   //+----------------------------------------------------------------+
   void OnTick()
     {
      if(!m_initialised) return;

      MqlTick latestTick;
      if(!SymbolInfoTick(_Symbol, latestTick)) return;
      if(m_sanity != NULL && !m_sanity->ValidateTick(latestTick))
        {
         if(m_debugMode)
            Print("[OnTick] BLOCKED by Circuit Breaker: ", m_sanity->GetStateString());
         return;
        }

      PASREvent evTick;
      evTick.id       = EVENT_ID_PRICE_UPDATE;   // now defined in Events v2.14
      evTick.priority = 5;
      m_bus.Push(evTick);

      if(BarChanged())
        {
         PASREvent evBar;
         evBar.id       = EVENT_ID_NEW_BAR;
         evBar.priority = 10;
         m_bus.Push(evBar);
        }

      DrainQueue();
     }

   //+----------------------------------------------------------------+
   //| OnTimer — Pipeline staged execution                           |
   //+----------------------------------------------------------------+
   void OnTimer()
     {
      if(!m_initialised) return;

      // Phase 7: Health Check
      if(m_health != NULL)
        {
         m_health->OnTick_HealthCheck();
         PASREvent evHealth;
         evHealth.id       = EVENT_ID_HEALTH_CHECK;
         evHealth.priority = 1;
         evHealth.data1    = (double)m_health->Status();  // S8-005: was data_i[0]
         m_bus->Push(evHealth);
        }

      // Phase 7: Periodic Snapshot (every 60s)
      static datetime s_last_snapshot = 0;
      datetime now = TimeCurrent();
      if(now - s_last_snapshot >= 60 && m_snapshot != NULL)
        {
         m_snapshot->UpdateState(true, 0.0, 0, PositionsTotal(), 0.0, 0);
         m_snapshot->SaveSnapshot();
         s_last_snapshot = now;
        }

      // Pipeline execution
      if(m_pipeline != NULL && m_profiling_enabled)
        {
         m_pipeline_ctx.Reset();
         m_pipeline_ctx.new_bar = BarChanged();

         // S8-003: Inject runtime state into context BEFORE entering stage loop.
         // Stage_RiskCheck reads these fields — they must be fresh each timer tick.
         m_pipeline_ctx.health_status = (m_health != NULL) ? m_health->Status() : 0;
         m_pipeline_ctx.plan_locked   = false;
         if(m_session != NULL)
           {
            m_session->SyncEquity();
            const SSessionSnapshot *snap = m_session->GetSnapshot();
            if(snap != NULL)
              {
               m_pipeline_ctx.session_dd = snap.current_drawdown;
               m_pipeline_ctx.daily_pnl  = snap.daily_pnl;
              }
           }

         ENUM_STAGE_RESULT result = m_pipeline->ExecutePipeline(m_pipeline_ctx);
         if(m_debugMode && result != STAGE_OK)
            PrintFormat("[Orchestrator] Pipeline exit: %s — %s",
                        EnumToString((ENUM_PIPELINE_STAGE)m_pipeline_ctx.exit_reason),
                        m_pipeline_ctx.exit_message);
        }
      else
        {
         // Fallback: legacy event push (profiling disabled)
         PASREvent ev; ev.id = EVENT_ID_TIMER; ev.priority = 1;  // now defined in Events v2.14
         m_bus.Push(ev);
         DrainQueue();
        }
     }

   //+----------------------------------------------------------------+
   //| OnTradeTransaction                                             |
   //+----------------------------------------------------------------+
   void OnTradeTransaction(const MqlTradeTransaction &trans,
                            const MqlTradeRequest    &request,
                            const MqlTradeResult     &result)
     {
      if(!m_initialised) return;
      if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
      if(trans.deal  == 0) return;
      if(!HistoryDealSelect(trans.deal)) return;
      if((int)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != m_cfg.MagicNumber) return;

      ENUM_DEAL_ENTRY entry  = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      double          profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
      ulong           pos    = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);

      if(entry == DEAL_ENTRY_IN)
        {
         int    dir   = (int)HistoryDealGetInteger(trans.deal, DEAL_TYPE)==DEAL_TYPE_BUY ? 1 : -1;
         double price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
         m_recovery.OnTradeOpen((ulong)pos, dir, price);
        }

      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
        {
         m_recovery.OnTradeClose((ulong)pos);
         m_risk.OnTradeClosed();

         // S8-007: Record closed trade into SessionState so daily_pnl is accurate.
         // Stage_RiskCheck reads daily_pnl from PipelineContext which is populated
         // from m_session->GetSnapshot() in OnTimer(). Without this call the
         // drawdown check always sees 0 and never trips the daily loss limit.
         if(m_session != NULL)
            m_session->RecordTrade(profit);

         if(m_ai_orch != NULL)
           {
            float label = (profit >= 0.0) ? 1.0f : 0.0f;
            float features[AI_FEATURE_DIM];
            if(m_ai_orch->BuildFeaturesPublic(features))
               m_ai_orch->OnTradeResult(features, label);
            else
              {
               ArrayInitialize(features, 0.0f);
               m_ai_orch->OnTradeResult(features, label, 0.1f);
              }
           }

         PASREvent ev;
         ev.id     = EVENT_ID_POSITION_UPDATE;  // now defined in Events v2.14
         ev.priority = 8;
         ev.ticket = pos;
         ev.profit = profit;
         m_bus.Push(ev);
         DrainQueue();
        }
     }

   //+----------------------------------------------------------------+
   //| OnDeinit                                                       |
   //+----------------------------------------------------------------+
   void OnDeinit(const int reason)
     {
      if(!m_initialised) return;
      m_initialised = false;

      if(m_snapshot != NULL)
        {
         m_snapshot->UpdateState(true, 0.0, 0, PositionsTotal(), 0.0, 0);
         m_snapshot->SaveSnapshot();
        }

      if(m_health != NULL)  m_health->Shutdown();
      if(m_ai_orch != NULL) m_ai_orch->Deinit();
      if(m_dash != NULL)    m_dash.Destroy();
      FreeAll();
      PrintFormat("[Orchestrator] Deinit reason=%d", reason);
     }

   // ── Accessors ─────────────────────────────────────────────
   CDataManager         *GetDataManager()     const { return m_data;     }
   CAnalysisSRManager   *GetSRManager()       const { return m_sr;       }
   CAnalysisZoneManager *GetZoneManager()     const { return m_zone;     }
   CSignalManager       *GetSignalManager()   const { return m_signal;   }
   CAIOrchestrator      *GetAIOrchestrator()  const { return m_ai_orch;  }
   CRegimeFilter        *GetRegimeFilter()    const { return m_regime;   }
   CRiskManager         *GetRiskManager()     const { return m_risk;     }
   CExecutionManager    *GetExecManager()     const { return m_exec;     }
   CRecoveryManager     *GetRecoveryManager() const { return m_recovery; }
   CDashboardManager    *GetDashboard()       const { return m_dash;     }
   CSessionState        *GetSessionState()    const { return m_session;  }  // S8-002
   const StrategyConfig &GetConfig()          const { return m_cfg;      }
  };

#endif // __CORE_ORCHESTRATOR_MQH__
