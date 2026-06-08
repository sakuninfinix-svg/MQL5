//+------------------------------------------------------------------+
//| Central/PASRKernel.mqh - v0.30                                   |
//| Central facade and pipeline owner for modular migration            |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_CENTRAL_KERNEL_MQH__
#define __PASR_CENTRAL_KERNEL_MQH__

// v0.31 owns CPipelineEngine, runtime event loop, and manager bootstrap.

enum ENUM_PASR_KERNEL_STATE
  {
   PASR_KERNEL_STOPPED = 0,
   PASR_KERNEL_STARTING = 1,
   PASR_KERNEL_READY = 2,
   PASR_KERNEL_FAILED = 3,
   PASR_KERNEL_SHUTTING_DOWN = 4
  };

class CPASRKernel
  {
private:
   CEventBus              *m_event_bus;
   CMarketRegimeDetector  *m_regime_detector;
   CAdaptiveParameterManager *m_adaptive_manager;
   PatternSignalSource    *m_src_pattern;
   SRSignalSource         *m_src_sr;
   CRegimeSignalSource    *m_src_regime;
   CModuleRegistry         m_registry;
   CServiceLocator         m_services;
   CLifecycleManager       m_lifecycle;
   CPipelineEngine        *m_pipeline;
   PipelineContext         m_pipeline_ctx;
   StrategyConfig          m_cfg;
   ENUM_PASR_KERNEL_STATE  m_state;
   bool                    m_ready;
   bool                    m_debug;
   bool                    m_profiling_enabled;
   string                  m_last_error;
   datetime                m_last_bar_time;
   bool                    m_new_bar_flag;
   ulong                   m_last_price_dispatch_ms;
   int                     m_price_dispatch_throttle_ms;

   double ConfigDigest() const
     {
      double digest = 17.0;
      digest = digest * 31.0 + (double)m_cfg.MagicNumber;
      digest = digest * 31.0 + m_cfg.Risk.RiskPercent * 100.0;
      digest = digest * 31.0 + m_cfg.Risk.LotSize * 1000.0;
      digest = digest * 31.0 + m_cfg.Risk.SLMultiplier * 100.0;
      digest = digest * 31.0 + m_cfg.Risk.TPMultiplier * 100.0;
      digest = digest * 31.0 + m_cfg.Risk.MaxDailyLossPct * 100.0;
      digest = digest * 31.0 + m_cfg.Risk.MaxDrawdownPct * 100.0;
      digest = digest * 31.0 + (double)m_cfg.Risk.MaxOpenPositions;
      digest = digest * 31.0 + (m_cfg.AI.EnableAI ? 1.0 : 0.0);
      digest = digest * 31.0 + m_cfg.AI.MinConfidence * 1000.0;
      digest = digest * 31.0 + m_cfg.Pattern.MinPatternScore;
      digest = digest * 31.0 + (double)m_cfg.Pattern.LookbackBars;
      digest = digest * 31.0 + m_cfg.Market.SpreadFilterPips * 100.0;
      digest = digest * 31.0 + (double)m_cfg.Market.SessionStartHour;
      digest = digest * 31.0 + (double)m_cfg.Market.SessionEndHour;
      return MathMod(MathAbs(digest), 1000000007.0);
     }

   void PublishConfigTelemetry()
     {
      CTelemetryRecorder *telemetry = m_services.Telemetry();
      if(telemetry == NULL)
         return;
      telemetry.RecordObservabilityMetric("ConfigDigest", ConfigDigest(), "hash");
      telemetry.RecordObservabilityMetric("ConfigRiskPercent", m_cfg.Risk.RiskPercent, "percent");
      telemetry.RecordObservabilityMetric("ConfigMaxOpenPositions", (double)m_cfg.Risk.MaxOpenPositions, "count");
      telemetry.RecordObservabilityMetric("ConfigAIEnabled", m_cfg.AI.EnableAI ? 1.0 : 0.0, "bool");
      telemetry.RecordObservabilityMetric("ConfigAIMinConfidence", m_cfg.AI.MinConfidence, "normalized");
     }

   void SetState(ENUM_PASR_KERNEL_STATE state, const string message = "")
     {
      m_state = state;
      if(message != "") m_last_error = message;
      if(m_debug)
         PrintFormat("[PASRKernel] state=%d %s", (int)m_state, message);
     }

   bool RequireService(const string name)
     {
      if(!m_registry.Contains(name))
        {
         m_last_error = "Missing service: " + name;
         Print("[PASRKernel] ", m_last_error);
         return false;
        }
      return true;
     }

   bool ValidateKernelServices()
     {
      bool ok = true;
      ok = RequireService(PASR_MOD_DATA_MANAGER)      && ok;
      ok = RequireService(PASR_MOD_SIGNAL_MANAGER)    && ok;
      ok = RequireService(PASR_MOD_RISK_MANAGER)      && ok;
      ok = RequireService(PASR_MOD_EXECUTION_MANAGER) && ok;
      ok = RequireService(PASR_MOD_EXIT_ENGINE)       && ok;
      return ok;
     }

   bool RegisterOwnedManager(const string name, IManager *module)
     {
      if(module == NULL)
         return false;
      if(!m_registry.RegisterOrReplace(name, module, true, false))
        {
         PrintFormat("[PASRKernel] Registry ownership bind failed for %s", name);
         return false;
        }
      return true;
     }

   bool InitCriticalManager(const string name, IManager *module)
     {
      if(module == NULL)
        {
         PrintFormat("[PASRKernel] %s allocation failed", name);
         return false;
        }
      if(!m_lifecycle.InitCritical(module, name))
        {
         module.Deinit();
         delete module;
         return false;
        }
      if(!RegisterOwnedManager(name, module))
        {
         module.Deinit();
         delete module;
         return false;
        }
      return true;
     }

   bool InitOptionalManager(const string name, IManager *module, const string warning, bool &hardFail)
     {
      hardFail = false;
      if(!m_lifecycle.InitOptional(module, name))
        {
         Print("[PASRKernel] ", warning);
         if(module != NULL)
           {
            module.Deinit();
            delete module;
           }
         return false;
        }

      if(!RegisterOwnedManager(name, module))
        {
         hardFail = true;
         if(module != NULL)
           {
            module.Deinit();
            delete module;
           }
         return false;
        }
      return true;
     }

   void ReleaseSignalSources()
     {
      if(m_src_regime != NULL) { delete m_src_regime; m_src_regime = NULL; }
      if(m_src_sr != NULL) { delete m_src_sr; m_src_sr = NULL; }
      if(m_src_pattern != NULL) { delete m_src_pattern; m_src_pattern = NULL; }
     }

   bool BarChanged()
     {
      datetime t = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
      if(t != m_last_bar_time)
        {
         m_last_bar_time = t;
         return true;
        }
      return false;
     }

   bool ConsumeNewBarFlag()
     {
      bool isNewBar = m_new_bar_flag;
      m_new_bar_flag = false;
      return isNewBar;
     }

   void ResetRuntimeState()
     {
      m_last_bar_time = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
      m_new_bar_flag = false;
      m_last_price_dispatch_ms = 0;
     }

   void PreparePipelineContext(PipelineContext &ctx, const bool isNewBar)
     {
      ctx.Reset();
      ctx.new_bar = isNewBar;

      CHealthMonitor *health = m_services.Health();
      if(health != NULL)
         ctx.health_status = health.GetStatus();

      CSessionState *session = m_services.Session();
      if(session != NULL)
        {
         ctx.session_dd = session.GetDrawdownPct();
         ctx.daily_pnl = session.GetDailyPnL();
        }

      ctx.max_session_dd = m_cfg.Risk.MaxDailyLossPct;
     }

   void DrainEventQueue()
     {
      if(m_event_bus != NULL)
         m_event_bus.Drain();
     }

   void ProcessExecutionRetryQueue()
     {
      CExecutionManager *exec = m_services.Execution();
      if(exec != NULL)
         exec.ProcessRetryQueue();
     }

   void PublishPriceUpdate()
     {
      if(m_event_bus == NULL)
         return;

      ulong nowMs = GetTickCount64();
      if(m_price_dispatch_throttle_ms > 0 &&
         nowMs - m_last_price_dispatch_ms < (ulong)m_price_dispatch_throttle_ms)
         return;

      PASREvent evTick;
      evTick.id = EVENT_ID_PRICE_UPDATE;
      evTick.priority = 90;
      evTick.timestamp = TimeCurrent();
      m_event_bus.Dispatch(evTick);
      m_last_price_dispatch_ms = nowMs;
     }

   void PublishTradeTransactionEvent(const MqlTradeTransaction &trans)
     {
      if(m_event_bus == NULL)
         return;
      if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0)
         return;
      if(!HistoryDealSelect(trans.deal))
         return;

      string dealSymbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
      if(dealSymbol != _Symbol)
         return;

      long dealMagic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
      if(m_cfg.MagicNumber != 0 && dealMagic != m_cfg.MagicNumber)
         return;

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
      double direction = (dealType == DEAL_TYPE_SELL) ? -1.0 : 1.0;
      ulong positionTicket = (trans.position > 0) ? trans.position : trans.deal;
      double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) +
                      HistoryDealGetDouble(trans.deal, DEAL_SWAP) +
                      HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

      PASREvent ev;
      ev.timestamp = TimeCurrent();
      ev.ticket = trans.deal;
      ev.profit = profit;
      ev.priority = 5;

      if(entry == DEAL_ENTRY_IN)
        {
         ev.id = EVENT_ID_TRADE_OPEN;
         ev.ticket = positionTicket;
         ev.data1 = direction;
         ev.data2 = (double)trans.deal;
         ev.comment = "BrokerDealIn";
         m_event_bus.DispatchImmediate(ev);
        }
      else if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
        {
         ev.id = EVENT_ID_TRADE_CLOSE;
         ev.data1 = -1.0;
         ev.data2 = (double)positionTicket;
         ev.comment = "BrokerDealOut";
         m_event_bus.DispatchImmediate(ev);
        }

      PASREvent update;
      update.id = EVENT_ID_POSITION_UPDATE;
      update.priority = 10;
      update.timestamp = TimeCurrent();
      update.ticket = positionTicket;
      update.profit = 0.0;
      update.data1 = (entry == DEAL_ENTRY_IN) ? 1.0 : -1.0;
      update.comment = "BrokerDealUpdate";
      m_event_bus.DispatchImmediate(update);
     }

   bool InitPipeline()
     {
      m_pipeline = CModuleFactory::CreatePipelineEngine();
      if(m_pipeline == NULL)
        {
         m_last_error = "PipelineEngine allocation failed";
         Print("[PASRKernel] ", m_last_error);
         return false;
        }

      m_pipeline.SetDebugMode(m_debug);
      m_pipeline.EnableProfiling(m_profiling_enabled);
      SPipelineDependencies deps;
      deps.data = m_services.Data();
      deps.sr = m_services.SR();
      deps.zone = m_services.Zone();
      deps.pattern = m_services.Pattern();
      deps.signal = m_services.Signal();
      deps.ai_orch = m_services.AI();
      deps.regime = m_services.RegimeFilter();
      deps.risk = m_services.Risk();
      deps.exec = m_services.Execution();
      deps.exit_engine = m_services.Exit();
      deps.recovery = m_services.Recovery();
      deps.dash = m_services.Dashboard();
      deps.journal = m_services.Journal();
      deps.bus = m_event_bus;
      deps.sanity = m_services.Sanity();
      deps.telemetry = m_services.Telemetry();
      deps.adaptive = m_services.Adaptive();
      deps.regime_det = m_regime_detector;
      m_pipeline.InjectDependencies(deps);
      return true;
     }

   bool InitCoreServices()
     {
      CDataManager *data = CModuleFactory::CreateDataManager();
      if(data == NULL)
        {
         Print("[PASRKernel] DataManager allocation failed");
         return false;
        }

      data.SetConfig(m_cfg);
      m_lifecycle.Bind(&m_registry, data, m_event_bus);
      m_lifecycle.SetDebugMode(m_debug);
      if(!m_lifecycle.InitCritical(data, PASR_MOD_DATA_MANAGER))
        {
         Print("[PASRKernel] DataManager init failed");
         data.Deinit();
         delete data;
         return false;
        }
      if(!RegisterOwnedManager(PASR_MOD_DATA_MANAGER, data))
        {
         data.Deinit();
         delete data;
         return false;
        }

      bool hardFail = false;

      CSanityManager *sanity = CModuleFactory::CreateSanityManager();
      if(!InitOptionalManager(PASR_MOD_SANITY_MANAGER, sanity,
                              "SanityManager init failed; continuing without tick sanity gate", hardFail))
        {
         if(hardFail) return false;
        }

      CHealthMonitor *health = CModuleFactory::CreateHealthMonitor();
      if(!InitOptionalManager(PASR_MOD_HEALTH_MONITOR, health,
                              "HealthMonitor init failed; continuing without health gate", hardFail))
        {
         if(hardFail) return false;
        }

      CSessionState *session = CModuleFactory::CreateSessionState();
      if(session != NULL)
         session.SetMagic(m_cfg.MagicNumber);
      if(!InitOptionalManager(PASR_MOD_SESSION_STATE, session,
                              "SessionState init failed; continuing without session state", hardFail))
        {
         if(hardFail) return false;
        }

      return true;
     }

   bool InitAnalysisAndSignalStack()
     {
      bool hardFail = false;

      CAnalysisSRManager *sr = CModuleFactory::CreateSRManager();
      if(!InitCriticalManager(PASR_MOD_SR_MANAGER, sr))
         return false;

      CAnalysisZoneManager *zone = CModuleFactory::CreateZoneManager();
      if(!InitCriticalManager(PASR_MOD_ZONE_MANAGER, zone))
         return false;

      CRegimeFilter *regime = CModuleFactory::CreateRegimeFilter();
      if(!InitOptionalManager(PASR_MOD_REGIME_FILTER, regime,
                              "RegimeFilter init failed; continuing without regime context", hardFail))
        {
         regime = NULL;
         if(hardFail) return false;
        }

      CPatternManager *pattern = CModuleFactory::CreatePatternManager();
      if(!InitCriticalManager(PASR_MOD_PATTERN_MANAGER, pattern))
         return false;

      CSignalManager *signal = CModuleFactory::CreateSignalManager();
      if(!InitCriticalManager(PASR_MOD_SIGNAL_MANAGER, signal))
         return false;

      CDataManager *data = m_services.Data();
      signal.SetPatternManager(pattern);
      signal.SetSRManager(sr);
      if(regime != NULL)
         signal.SetRegimeManager(regime);

      m_src_pattern = CModuleFactory::CreatePatternSignalSource(pattern);
      if(m_src_pattern != NULL)
         signal.RegisterSource(m_src_pattern, 1.0);

      m_src_sr = CModuleFactory::CreateSRSignalSource(sr, data, 0.5);
      if(m_src_sr != NULL)
         signal.RegisterSource(m_src_sr, 0.8);

      if(regime != NULL)
        {
         m_src_regime = CModuleFactory::CreateRegimeSignalSource(regime, REGIME_MODE_VETO);
         if(m_src_regime != NULL)
            signal.RegisterSource(m_src_regime, 0.6);
        }

      return true;
     }

   bool InitAIStack()
     {
      if(!m_cfg.AI.EnableAI)
         return true;

      CAIOrchestrator *ai = CModuleFactory::CreateAIOrchestrator();
      if(!m_lifecycle.InitOptional(ai, PASR_MOD_AI_ORCHESTRATOR))
        {
         Print("[PASRKernel] AI init failed; rule fallback remains available");
         if(ai != NULL)
           {
            ai.Deinit();
            delete ai;
           }
         return true;
        }

      if(!RegisterOwnedManager(PASR_MOD_AI_ORCHESTRATOR, ai))
         return false;

      double vetoThreshold = m_cfg.AI.MinConfidence;
      double driftVetoThreshold = 0.60;
      double highConfidenceThreshold = MathMax(0.75, m_cfg.AI.MinConfidence + 0.15);
      ai.ConfigureParameters(m_cfg.AI.EnableAI,
                             vetoThreshold,
                             driftVetoThreshold,
                             highConfidenceThreshold);
      return true;
     }

   bool InitTradingStack()
     {
      bool hardFail = false;

      CRiskManager *risk = CModuleFactory::CreateRiskManager();
      if(!InitCriticalManager(PASR_MOD_RISK_MANAGER, risk))
         return false;

      CExecutionManager *exec = CModuleFactory::CreateExecutionManager();
      if(!InitCriticalManager(PASR_MOD_EXECUTION_MANAGER, exec))
         return false;

      CExitEngine *exitEngine = CModuleFactory::CreateExitEngine();
      if(!InitCriticalManager(PASR_MOD_EXIT_ENGINE, exitEngine))
         return false;

      CRecoveryManager *recovery = CModuleFactory::CreateRecoveryManager();
      if(!InitOptionalManager(PASR_MOD_RECOVERY_MANAGER, recovery,
                              "Recovery init failed; continuing without recovery tracking", hardFail))
        {
         if(hardFail) return false;
        }

      return true;
     }

   bool InitObservabilityStack()
     {
      bool hardFail = false;

      CTelemetryRecorder *telemetry = CModuleFactory::CreateTelemetryRecorder();
      if(!InitOptionalManager(PASR_MOD_TELEMETRY_RECORDER, telemetry,
                              "Telemetry init failed; continuing without telemetry", hardFail))
        {
         if(hardFail) return false;
        }

      CJournalManager *journal = CModuleFactory::CreateJournalManager();
      if(!InitOptionalManager(PASR_MOD_JOURNAL_MANAGER, journal,
                              "Journal init failed; continuing without journal", hardFail))
        {
         journal = NULL;
         if(hardFail) return false;
        }

      if(m_cfg.Display.ShowDashboard)
        {
         CDashboardManager *dash = CModuleFactory::CreateDashboardManager();
         if(!InitOptionalManager(PASR_MOD_DASHBOARD_MANAGER, dash,
                                 "Dashboard init failed; continuing without dashboard", hardFail))
           {
            if(hardFail) return false;
           }
         else if(dash != NULL)
           {
            dash.SetJournal(journal);
           }
        }

      return true;
     }

   bool InitManagerBootstrap()
     {
      return InitCoreServices() &&
             InitAnalysisAndSignalStack() &&
             InitAIStack() &&
             InitTradingStack() &&
             InitObservabilityStack();
     }

   bool InitAdaptiveManager()
     {
      if(m_regime_detector == NULL)
        {
         Print("[PASRKernel] AdaptiveParameterManager disabled: MarketRegimeDetector unavailable");
         return true;
        }

      CDataManager *data = m_services.Data();
      if(data == NULL)
        {
         m_last_error = "AdaptiveParameterManager requires DataManager";
         return false;
        }

      m_adaptive_manager = CModuleFactory::CreateAdaptiveParameterManager();
      if(m_adaptive_manager == NULL)
        {
         Print("[PASRKernel] AdaptiveParameterManager allocation failed; stage will skip");
         return true;
        }

      m_adaptive_manager.SetDebugMode(m_debug);
      if(!m_adaptive_manager.Init(data, m_event_bus))
        {
         Print("[PASRKernel] AdaptiveParameterManager Init failed; stage will skip");
         m_adaptive_manager.Deinit();
         delete m_adaptive_manager;
         m_adaptive_manager = NULL;
         return true;
        }

      double baseRisk = (m_cfg.Risk.RiskPercent > 0.0) ? m_cfg.Risk.RiskPercent : 1.0;
      if(!m_adaptive_manager.Initialize(m_regime_detector, 20.0, 40.0, baseRisk))
        {
         Print("[PASRKernel] AdaptiveParameterManager regime binding failed; stage will skip");
         m_adaptive_manager.Deinit();
         delete m_adaptive_manager;
         m_adaptive_manager = NULL;
         return true;
        }

      if(m_event_bus != NULL && !m_event_bus.Register(m_adaptive_manager))
         Print("[PASRKernel] EventBus register failed for AdaptiveParameterManager");

      if(!m_registry.RegisterOrReplace(PASR_MOD_ADAPTIVE_MANAGER, m_adaptive_manager, true, false))
        {
         m_last_error = "AdaptiveParameterManager registry bind failed";
         m_adaptive_manager.Deinit();
         delete m_adaptive_manager;
         m_adaptive_manager = NULL;
         return false;
        }

      return true;
     }

public:
   CPASRKernel()
      : m_event_bus(NULL), m_regime_detector(NULL), m_adaptive_manager(NULL),
        m_src_pattern(NULL), m_src_sr(NULL), m_src_regime(NULL),
        m_pipeline(NULL), m_state(PASR_KERNEL_STOPPED), m_ready(false),
        m_debug(false), m_profiling_enabled(true), m_last_error(""),
        m_last_bar_time(0), m_new_bar_flag(false), m_last_price_dispatch_ms(0),
        m_price_dispatch_throttle_ms(50)
     {
      m_services.Bind(&m_registry);
     }

   ~CPASRKernel()
     {
      Shutdown(REASON_REMOVE);
     }

   void SetDebugMode(const bool enabled)
     {
      m_debug = enabled;
      m_registry.SetDebugMode(enabled);
      m_lifecycle.SetDebugMode(enabled);
      if(m_pipeline != NULL)
         m_pipeline.SetDebugMode(enabled);
     }

   void SetProfilingEnabled(const bool enabled)
     {
      m_profiling_enabled = enabled;
      if(m_pipeline != NULL)
         m_pipeline.EnableProfiling(enabled);
     }

   bool IsProfilingEnabled() const
     {
      return m_profiling_enabled;
     }

   int Init()
     {
      StrategyConfig cfg;
      return Init(cfg);
     }

   int Init(const StrategyConfig &cfg)
     {
      if(m_ready)
         return INIT_SUCCEEDED;

      SetState(PASR_KERNEL_STARTING);
      m_cfg = cfg;
      m_last_error = "";

      m_event_bus = CModuleFactory::CreateEventBus();
      if(m_event_bus == NULL)
        {
         SetState(PASR_KERNEL_FAILED, "EventBus allocation failed");
         Print("[PASRKernel] EventBus allocation failed");
         return INIT_FAILED;
        }

      m_regime_detector = CModuleFactory::CreateMarketRegimeDetector();
      if(m_regime_detector == NULL)
         Print("[PASRKernel] MarketRegimeDetector allocation failed; RegimeFilter remains primary");

      if(!InitManagerBootstrap())
        {
         SetState(PASR_KERNEL_FAILED, "Manager bootstrap failed");
         Shutdown(REASON_INITFAILED);
         return INIT_FAILED;
        }

      if(!InitAdaptiveManager())
        {
         SetState(PASR_KERNEL_FAILED, m_last_error);
         Shutdown(REASON_INITFAILED);
         return INIT_FAILED;
        }

      if(!ValidateKernelServices())
        {
         SetState(PASR_KERNEL_FAILED, m_last_error);
         Shutdown(REASON_INITFAILED);
         return INIT_FAILED;
        }

      if(!InitPipeline())
        {
         SetState(PASR_KERNEL_FAILED, m_last_error);
         Shutdown(REASON_INITFAILED);
         return INIT_FAILED;
        }

      PublishConfigTelemetry();
      ResetRuntimeState();
      m_ready = true;
      SetState(PASR_KERNEL_READY);
      if(m_debug) m_registry.PrintSummary();
      Print("[PASRKernel] Centralized Modular Pipeline facade initialized");
      return INIT_SUCCEEDED;
     }

   void Shutdown(const int reason)
     {
      if(m_state == PASR_KERNEL_SHUTTING_DOWN) return;
      SetState(PASR_KERNEL_SHUTTING_DOWN);

      if(m_pipeline != NULL)
        {
         delete m_pipeline;
         m_pipeline = NULL;
        }

      ReleaseSignalSources();
      m_registry.Clear(true);
      m_adaptive_manager = NULL;
      if(m_regime_detector != NULL)
        {
         m_regime_detector.Deinit();
         delete m_regime_detector;
         m_regime_detector = NULL;
        }
      if(m_event_bus != NULL)
        {
         delete m_event_bus;
         m_event_bus = NULL;
        }
      m_ready = false;
      ResetRuntimeState();
      SetState(PASR_KERNEL_STOPPED);
     }

   void OnTick()
     {
      if(!m_ready)
         return;

      MqlTick latestTick;
      if(!SymbolInfoTick(_Symbol, latestTick))
         return;

      CSanityManager *sanity = m_services.Sanity();
      if(sanity != NULL && !sanity.ValidateTick(latestTick))
         return;

      if(BarChanged())
         m_new_bar_flag = true;

      PublishPriceUpdate();
     }

   void OnTimer()
     {
      if(!m_ready || m_pipeline == NULL)
         return;

      bool isNewBar = ConsumeNewBarFlag();
      PreparePipelineContext(m_pipeline_ctx, isNewBar);
      DrainEventQueue();
      ProcessExecutionRetryQueue();
      ENUM_STAGE_RESULT result = m_pipeline.ExecutePipeline(m_pipeline_ctx);
      DrainEventQueue();
      if(m_debug && result == STAGE_ABORT)
         PrintFormat("[PASRKernel] Pipeline ABORT: %s", m_pipeline_ctx.exit_message);
     }

   void OnDeinit(const int reason)
     {
      Shutdown(reason);
     }

   void OnTradeTransaction(const MqlTradeTransaction &trans,
                           const MqlTradeRequest &request,
                           const MqlTradeResult &result)
     {
      if(!m_ready)
         return;

      CDataManager *data = m_services.Data();
      if(data != NULL)
         data.OnTrade(trans);
      PublishTradeTransactionEvent(trans);
     }

   bool IsReady() const
     {
      return m_ready;
     }

   ENUM_PASR_KERNEL_STATE State() const
     {
      return m_state;
     }

   string LastError() const
     {
      return m_last_error;
     }

   CPipelineEngine* Pipeline() const
     {
      return m_pipeline;
     }

   CModuleRegistry* Registry()
     {
      return &m_registry;
     }

   CServiceLocator* Services()
     {
      return &m_services;
     }

   CEventBus* GetEventBus() const
     {
      return m_event_bus;
     }

   CDataManager* GetDataManager() const
     {
      return m_services.Data();
     }

   CRiskManager* GetRiskManager() const
     {
      return m_services.Risk();
     }

   CDashboardManager* GetDashboard() const
     {
      return m_services.Dashboard();
     }

  };

#endif // __PASR_CENTRAL_KERNEL_MQH__
