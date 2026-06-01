//+------------------------------------------------------------------+
//| Central/BackendAdapter.mqh - v3.11                               |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#property strict

#ifndef __PASR_CENTRAL_BACKEND_ADAPTER_MQH__
#define __PASR_CENTRAL_BACKEND_ADAPTER_MQH__

#ifdef __CORE_PASR_MASTER_MQH__
#else
  // When not building via the master PASR include, provide minimal
  // dependencies here to avoid forcing a full include and creating
  // circular includes.
  #include <PASR/Core/Config/Types.mqh>
  #include <PASR/Core/PipelineTypes.mqh>
  class IManager;
  class CDataManager;
  class CAnalysisSRManager;
  class CAnalysisZoneManager;
  class CPatternManager;
  class CSignalManager;
  class CAIOrchestrator;
  class CMarketRegimeDetector;
  class CRegimeFilter;
  class CRiskManager;
  class CExecutionManager;
  class CExitEngine;
  class CRecoveryManager;
  class CDashboardManager;
  class CSanityManager;
  class CTelemetryRecorder;
  class CJournalManager;
  class CAdaptiveParameterManager;
  class CLatencyOptimizer;
  class CAsyncOrderManager;
  class CHighFreqTimer;
  class CHealthMonitor;
  class CSnapshotManager;
  class CSessionState;
  class CLatencySimulator;
  class PatternSignalSource;
  class SRSignalSource;
  class AISignalSource;
  class CRegimeSignalSource;
  class CEventBus;
  class CPipelineEngine;
  class CConfigManager;
#endif

#include <PASR/Central/ModuleNames.mqh>
#include <PASR/Central/ModuleRegistry.mqh>
#include <PASR/Central/LifecycleManager.mqh>

class CBackendAdapter
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
   CExitEngine               *m_exit;
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
   CModuleRegistry          *m_owner_registry;
   StrategyConfig             m_cfg;
   CConfigManager            *m_cfgMgr;
   CLifecycleManager          m_lifecycle;
   datetime                   m_lastBarTime;
   bool                       m_debugMode;
   bool                       m_initialised;
   bool                       m_profiling_enabled;
   bool                       m_registry_owns_managers;
   bool                       m_new_bar_flag;
   ulong                      m_last_price_dispatch_ms;
   int                        m_price_dispatch_throttle_ms;

   bool BarChanged()
     {
      datetime t = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
      if(t != m_lastBarTime) { m_lastBarTime = t; return true; }
      return false;
     }

   void RegisterManager(IManager *mgr)
     {
      if(mgr == NULL || m_bus == NULL) return;
      if(!m_bus.Register(mgr))
         PrintFormat("[BackendAdapter] Register failed for %s", mgr.HandlerName());
     }

   bool InitManager(IManager *mgr, const string name)
     {
      if(mgr == NULL)
        { PrintFormat("[BackendAdapter] %s alloc failed", name); return false; }
      if(!m_lifecycle.InitCritical(mgr, name))
         return false;
      if(m_registry_owns_managers && m_owner_registry != NULL)
        {
         if(!m_owner_registry.RegisterOrReplace(name, mgr, true, false))
           {
            PrintFormat("[BackendAdapter] Registry ownership bind failed for %s", name);
            return false;
           }
        }
      return true;
     }

   bool BindOwnedManager(IManager *mgr, const string name)
     {
      if(!m_registry_owns_managers || m_owner_registry == NULL || mgr == NULL)
         return true;
      if(!m_owner_registry.RegisterOrReplace(name, mgr, true, false))
        {
         PrintFormat("[BackendAdapter] Registry ownership bind failed for %s", name);
         return false;
        }
      return true;
     }

   void DrainQueue()
     {
      if(m_bus != NULL) m_bus.Drain();
     }

   void FreeAll();

public:
   CBackendAdapter()
      : m_data(NULL), m_sr(NULL), m_zone(NULL), m_pattern(NULL),
        m_signal(NULL), m_ai_orch(NULL), m_regime_det(NULL),
        m_regime(NULL), m_risk(NULL), m_exec(NULL), m_exit(NULL), m_recovery(NULL),
        m_dash(NULL), m_sanity(NULL), m_telemetry(NULL), m_journal(NULL),
        m_adaptive(NULL), m_optimizer(NULL), m_async_orders(NULL),
        m_hf_timer(NULL), m_health(NULL), m_snapshot(NULL), m_session(NULL),
        m_latency_sim(NULL), m_srcPattern(NULL), m_srcSR(NULL),
        m_srcAI(NULL), m_srcRegime(NULL), m_bus(NULL), m_owner_registry(NULL), m_cfgMgr(NULL),
        m_lastBarTime(0), m_debugMode(false),
        m_initialised(false), m_profiling_enabled(true), m_registry_owns_managers(false), m_new_bar_flag(false),
        m_last_price_dispatch_ms(0), m_price_dispatch_throttle_ms(50)
     {}

   ~CBackendAdapter() { FreeAll(); }

   int Init()
     {
      StrategyConfig cfg;
      return Init(cfg);
     }

   int Init(const StrategyConfig &cfg);

   void SetDebugMode(bool enable) { m_debugMode = enable; m_lifecycle.SetDebugMode(enable); }
   void SetProfilingEnabled(bool enable) { m_profiling_enabled = enable; }
   bool IsProfilingEnabled() const { return m_profiling_enabled; }
   void SetPriceDispatchThrottleMs(int ms) { if(ms >= 0) m_price_dispatch_throttle_ms = ms; }
   bool IsInitialized() const { return m_initialised; }

   void BindOwnerRegistry(CModuleRegistry *registry, const bool registryOwnsManagers)
     {
      m_owner_registry = registry;
      m_registry_owns_managers = (registry != NULL && registryOwnsManagers);
     }

   bool RegistryOwnsManagers() const
     {
      return m_registry_owns_managers;
     }

   bool ConsumeNewBarFlag()
     {
      bool isNewBar = m_new_bar_flag;
      m_new_bar_flag = false;
      return isNewBar;
     }

   void PreparePipelineContext(PipelineContext &ctx, const bool isNewBar)
     {
      ctx.Reset();
      ctx.new_bar = isNewBar;
      if(m_health  != NULL) ctx.health_status = m_health.GetStatus();
      if(m_session != NULL)
        {
         ctx.session_dd = m_session.GetDrawdownPct();
         ctx.daily_pnl  = m_session.GetDailyPnL();
        }
      ctx.max_session_dd = m_cfg.Risk.MaxDailyLossPct;
     }

   void DrainEventQueue()
     {
      DrainQueue();
     }

   void ProcessExecutionRetryQueue()
     {
      if(m_exec != NULL) m_exec.ProcessRetryQueue();
     }

   void OnTick()
     {
      if(!m_initialised) return;
      MqlTick latestTick;
      if(!SymbolInfoTick(_Symbol, latestTick)) return;
      if(m_sanity != NULL && !m_sanity.ValidateTick(latestTick)) return;
      if(BarChanged()) m_new_bar_flag = true;
      if(m_bus != NULL)
        {
         ulong nowMs = GetTickCount64();
         if(m_price_dispatch_throttle_ms == 0 || nowMs - m_last_price_dispatch_ms >= (ulong)m_price_dispatch_throttle_ms)
           {
            PASREvent evTick;
            evTick.id       = EVENT_ID_PRICE_UPDATE;
            evTick.priority = 90;
            evTick.timestamp= TimeCurrent();
            m_bus.Dispatch(evTick);
            m_last_price_dispatch_ms = nowMs;
           }
        }
     }

   void OnTimer()
     {
      // Compatibility no-op: CPASRKernel owns and executes CPipelineEngine.
     }

   void OnDeinit(const int reason)
     {
      EventKillTimer();
      m_initialised = false;
      if(m_debugMode) PrintFormat("[BackendAdapter] OnDeinit reason=%d", reason);
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
   CExitEngine*        GetExitEngine()     const { return m_exit; }
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
   CPipelineEngine*    GetPipelineEngine() const { return NULL; }
  };

void CBackendAdapter::FreeAll()
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
   if(m_adaptive != NULL) { if(!m_registry_owns_managers) { m_lifecycle.DeinitOne(m_adaptive, PASR_MOD_ADAPTIVE_MANAGER); delete m_adaptive; } m_adaptive = NULL; }
   if(m_journal != NULL) { if(!m_registry_owns_managers) { m_lifecycle.DeinitOne(m_journal, PASR_MOD_JOURNAL_MANAGER); delete m_journal; } m_journal = NULL; }
   if(m_telemetry != NULL) { if(!m_registry_owns_managers) { m_lifecycle.DeinitOne(m_telemetry, PASR_MOD_TELEMETRY_RECORDER); delete m_telemetry; } m_telemetry = NULL; }
   if(m_dash != NULL) { if(!m_registry_owns_managers) { m_lifecycle.DeinitOne(m_dash, PASR_MOD_DASHBOARD_MANAGER); delete m_dash; } m_dash = NULL; }
   if(m_recovery != NULL) { if(!m_registry_owns_managers) { m_lifecycle.DeinitOne(m_recovery, PASR_MOD_RECOVERY_MANAGER); delete m_recovery; } m_recovery = NULL; }
   if(m_exit != NULL) { if(!m_registry_owns_managers) { m_lifecycle.DeinitOne(m_exit, PASR_MOD_EXIT_ENGINE); delete m_exit; } m_exit = NULL; }
   if(m_exec != NULL) { if(!m_registry_owns_managers) { m_lifecycle.DeinitOne(m_exec, PASR_MOD_EXECUTION_MANAGER); delete m_exec; } m_exec = NULL; }
   if(m_risk != NULL) { if(!m_registry_owns_managers) { m_lifecycle.DeinitOne(m_risk, PASR_MOD_RISK_MANAGER); delete m_risk; } m_risk = NULL; }
   if(m_ai_orch != NULL) { if(!m_registry_owns_managers) { m_lifecycle.DeinitOne(m_ai_orch, PASR_MOD_AI_ORCHESTRATOR); delete m_ai_orch; } m_ai_orch = NULL; }
   if(m_signal != NULL) { if(!m_registry_owns_managers) { m_lifecycle.DeinitOne(m_signal, PASR_MOD_SIGNAL_MANAGER); delete m_signal; } m_signal = NULL; }
   if(m_pattern != NULL) { if(!m_registry_owns_managers) { m_lifecycle.DeinitOne(m_pattern, PASR_MOD_PATTERN_MANAGER); delete m_pattern; } m_pattern = NULL; }
   if(m_regime != NULL) { if(!m_registry_owns_managers) { m_lifecycle.DeinitOne(m_regime, PASR_MOD_REGIME_FILTER); delete m_regime; } m_regime = NULL; }
   if(m_regime_det != NULL) { m_regime_det.Deinit(); delete m_regime_det; m_regime_det = NULL; }
   if(m_zone != NULL) { if(!m_registry_owns_managers) { m_lifecycle.DeinitOne(m_zone, PASR_MOD_ZONE_MANAGER); delete m_zone; } m_zone = NULL; }
   if(m_sr != NULL) { if(!m_registry_owns_managers) { m_lifecycle.DeinitOne(m_sr, PASR_MOD_SR_MANAGER); delete m_sr; } m_sr = NULL; }
   if(m_sanity != NULL) { if(!m_registry_owns_managers) { m_lifecycle.DeinitOne(m_sanity, PASR_MOD_SANITY_MANAGER); delete m_sanity; } m_sanity = NULL; }
   if(m_latency_sim != NULL) { delete m_latency_sim; m_latency_sim = NULL; }
   if(m_cfgMgr != NULL) { delete m_cfgMgr; m_cfgMgr = NULL; }
   if(m_data != NULL) { if(!m_registry_owns_managers) { m_lifecycle.DeinitOne(m_data, PASR_MOD_DATA_MANAGER); delete m_data; } m_data = NULL; }
   if(m_bus != NULL) { delete m_bus; m_bus = NULL; }
  }

#endif // __PASR_CENTRAL_BACKEND_ADAPTER_MQH__
