//+------------------------------------------------------------------+
//| Core/Orchestrator.mqh — v3.08                                    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#property strict

#ifndef __CORE_ORCHESTRATOR_MQH__
#define __CORE_ORCHESTRATOR_MQH__

#ifdef __CORE_PASR_MASTER_MQH__
#else
  #error "Include <PASR/Core/PASR.mqh> instead of Orchestrator.mqh directly."
#endif

class CConfigManager;

class COrchestrator
  {
private:
   CDataManager              *m_data;
   CAnalysisSRManager        *m_sr;
   CAnalysisZoneManager      *m_zone;
   CPatternManager           *m_pattern;
   CSignalManager            *m_signal;
   CAIOrchestrator           *m_ai_orch;
   CMarketRegimeDetector     *m_regime_det;
   CRegimeFilter             *m_regime;
   CRiskManager              *m_risk;
   CExecutionManager         *m_exec;
   CRecoveryManager          *m_recovery;
   CDashboardManager         *m_dash;
   CSanityManager            *m_sanity;
   CTelemetryRecorder        *m_telemetry;
   CJournalManager           *m_journal;
   CAdaptiveParameterManager *m_adaptive;
   CLatencyOptimizer         *m_optimizer;
   CAsyncOrderManager        *m_async_orders;
   CHighFreqTimer            *m_hf_timer;
   CHealthMonitor            *m_health;
   CSnapshotManager          *m_snapshot;
   CSessionState             *m_session;
   CLatencySimulator         *m_latency_sim;
   PatternSignalSource       *m_srcPattern;
   SRSignalSource            *m_srcSR;
   AISignalSource            *m_srcAI;
   CRegimeSignalSource       *m_srcRegime;
   CEventBus                 *m_bus;
   StrategyConfig             m_cfg;
   CConfigManager            *m_cfgMgr;
   CPipelineEngine           *m_pipeline;
   PipelineContext            m_pipeline_ctx;
   datetime                   m_lastBarTime;
   bool                       m_debugMode;
   bool                       m_initialised;
   bool                       m_profiling_enabled;
   bool                       m_new_bar_flag;

   bool BarChanged()
     {
      datetime t = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
      if(t != m_lastBarTime) { m_lastBarTime = t; return true; }
      return false;
     }

   void RegisterManager(IManager *mgr)
     {
      if(mgr == NULL || m_bus == NULL) return;
      mgr.DeclareEvents();
      if(!m_bus.Register(mgr))
         PrintFormat("[Orchestrator] Register failed for %s", mgr.HandlerName());
     }

   bool InitManager(IManager *mgr, const string name)
     {
      if(mgr == NULL)
        { PrintFormat("[Orchestrator] %s alloc failed", name); return false; }
      if(m_debugMode) mgr.SetDebugMode(true);
      if(!mgr.Init(m_data, m_bus))
        { PrintFormat("[Orchestrator] %s.Init failed", name); return false; }
      RegisterManager(mgr);
      return true;
     }

   void DrainQueue()
     {
      if(m_bus != NULL) m_bus.Drain();
     }

   void FreeAll();

public:
   COrchestrator()
      : m_data(NULL), m_sr(NULL), m_zone(NULL), m_pattern(NULL),
        m_signal(NULL), m_ai_orch(NULL), m_regime_det(NULL),
        m_regime(NULL), m_risk(NULL), m_exec(NULL), m_recovery(NULL),
        m_dash(NULL), m_sanity(NULL), m_telemetry(NULL), m_journal(NULL),
        m_adaptive(NULL), m_optimizer(NULL), m_async_orders(NULL),
        m_hf_timer(NULL), m_health(NULL), m_snapshot(NULL), m_session(NULL),
        m_latency_sim(NULL), m_srcPattern(NULL), m_srcSR(NULL),
        m_srcAI(NULL), m_srcRegime(NULL), m_bus(NULL), m_cfgMgr(NULL),
        m_pipeline(NULL), m_lastBarTime(0), m_debugMode(false),
        m_initialised(false), m_profiling_enabled(true), m_new_bar_flag(false)
     {}

   ~COrchestrator() { FreeAll(); }

   int Init()
     {
      StrategyConfig cfg;
      return Init(cfg);
     }

   int Init(const StrategyConfig &cfg);

   void SetDebugMode(bool enable) { m_debugMode = enable; }
   void SetProfilingEnabled(bool enable) { m_profiling_enabled = enable; }
   bool IsProfilingEnabled() const { return m_profiling_enabled; }

   void OnTick()
     {
      if(!m_initialised) return;
      MqlTick latestTick;
      if(!SymbolInfoTick(_Symbol, latestTick)) return;
      if(m_sanity != NULL && !m_sanity.ValidateTick(latestTick)) return;
      if(BarChanged()) m_new_bar_flag = true;
      if(m_bus != NULL)
        {
         PASREvent evTick;
         evTick.id       = EVENT_ID_PRICE_UPDATE;
         evTick.priority = 5;
         m_bus.Push(evTick);
        }
     }

   void OnTimer()
     {
      if(!m_initialised || m_pipeline == NULL) return;
      bool isNewBar  = m_new_bar_flag;
      m_new_bar_flag = false;
      m_pipeline_ctx.Reset();
      m_pipeline_ctx.new_bar = isNewBar;
      if(m_health  != NULL) m_pipeline_ctx.health_status = m_health.GetStatus();
      if(m_session != NULL)
        {
         m_pipeline_ctx.session_dd = m_session.GetDrawdownPct();
         m_pipeline_ctx.daily_pnl  = m_session.GetDailyPnL();
        }
      m_pipeline_ctx.max_session_dd = m_cfg.Risk.MaxDailyLossPct;
      DrainQueue();
      if(m_exec != NULL) m_exec.ProcessRetryQueue();
      ENUM_STAGE_RESULT result = m_pipeline.ExecutePipeline(m_pipeline_ctx);
      DrainQueue();
      if(m_debugMode && result == STAGE_ABORT)
         PrintFormat("[Orchestrator] Pipeline ABORT: %s", m_pipeline_ctx.exit_message);
     }

   void OnDeinit(const int reason)
     {
      EventKillTimer();
      m_initialised = false;
      if(m_debugMode) PrintFormat("[Orchestrator] OnDeinit reason=%d", reason);
     }

   void OnTradeTransaction(const MqlTradeTransaction &trans,
                           const MqlTradeRequest &request,
                           const MqlTradeResult &result);

   CDataManager*       GetDataManager()    const { return m_data; }
   CAnalysisSRManager* GetSRManager()      const { return m_sr; }
   CAnalysisZoneManager* GetZoneManager()  const { return m_zone; }
   CPatternManager*    GetPatternManager() const { return m_pattern; }
   CSignalManager*     GetSignalManager()  const { return m_signal; }
   CAIOrchestrator*    GetAIOrchestrator() const { return m_ai_orch; }
   CMarketRegimeDetector* GetRegimeDetector() const { return m_regime_det; }
   CRegimeFilter*      GetRegimeFilter()   const { return m_regime; }
   CRiskManager*       GetRiskManager()    const { return m_risk; }
   CExecutionManager*  GetExecManager()    const { return m_exec; }
   CRecoveryManager*   GetRecoveryManager()const { return m_recovery; }
   CDashboardManager*  GetDashboard()      const { return m_dash; }
   CSanityManager*     GetSanityManager()  const { return m_sanity; }
   CTelemetryRecorder* GetTelemetry()      const { return m_telemetry; }
   CJournalManager*    GetJournalManager() const { return m_journal; }
   CAdaptiveParameterManager* GetAdaptiveManager() const { return m_adaptive; }
   CHealthMonitor*     GetHealthMonitor()  const { return m_health; }
   CSnapshotManager*   GetSnapshotManager()const { return m_snapshot; }
   CSessionState*      GetSessionState()   const { return m_session; }
   CLatencySimulator*  GetLatencySimulator() const { return m_latency_sim; }
   CEventBus*          GetEventBus()       const { return m_bus; }
   CPipelineEngine*    GetPipelineEngine() const { return m_pipeline; }
  };

void COrchestrator::FreeAll()
  {
   if(m_snapshot != NULL) { m_snapshot.Shutdown(); delete m_snapshot; m_snapshot = NULL; }
   if(m_health   != NULL) { m_health.Shutdown();   delete m_health;   m_health   = NULL; }
   if(m_session  != NULL) { delete m_session;  m_session  = NULL; }
   if(m_hf_timer != NULL) { delete m_hf_timer; m_hf_timer = NULL; }
   if(m_async_orders != NULL) { delete m_async_orders; m_async_orders = NULL; }
   if(m_optimizer != NULL) { delete m_optimizer; m_optimizer = NULL; }
   if(m_srcRegime != NULL) { delete m_srcRegime; m_srcRegime = NULL; }
   if(m_srcAI != NULL) { delete m_srcAI; m_srcAI = NULL; }
   if(m_srcSR != NULL) { delete m_srcSR; m_srcSR = NULL; }
   if(m_srcPattern != NULL) { delete m_srcPattern; m_srcPattern = NULL; }
   if(m_pipeline != NULL) { delete m_pipeline; m_pipeline = NULL; }
   if(m_adaptive != NULL) { delete m_adaptive; m_adaptive = NULL; }
   if(m_journal != NULL) { delete m_journal; m_journal = NULL; }
   if(m_telemetry != NULL) { delete m_telemetry; m_telemetry = NULL; }
   if(m_dash != NULL) { m_dash.Destroy(); delete m_dash; m_dash = NULL; }
   if(m_recovery != NULL) { delete m_recovery; m_recovery = NULL; }
   if(m_exec != NULL) { delete m_exec; m_exec = NULL; }
   if(m_risk != NULL) { delete m_risk; m_risk = NULL; }
   if(m_ai_orch != NULL) { m_ai_orch.Deinit(); delete m_ai_orch; m_ai_orch = NULL; }
   if(m_signal != NULL) { delete m_signal; m_signal = NULL; }
   if(m_pattern != NULL) { delete m_pattern; m_pattern = NULL; }
   if(m_regime != NULL) { delete m_regime; m_regime = NULL; }
   if(m_regime_det != NULL) { delete m_regime_det; m_regime_det = NULL; }
   if(m_zone != NULL) { delete m_zone; m_zone = NULL; }
   if(m_sr != NULL) { delete m_sr; m_sr = NULL; }
   if(m_sanity != NULL) { delete m_sanity; m_sanity = NULL; }
   if(m_latency_sim != NULL) { delete m_latency_sim; m_latency_sim = NULL; }
   if(m_cfgMgr != NULL) { delete m_cfgMgr; m_cfgMgr = NULL; }
   if(m_data != NULL) { delete m_data; m_data = NULL; }
   if(m_bus != NULL) { delete m_bus; m_bus = NULL; }
  }

#endif // __CORE_ORCHESTRATOR_MQH__
