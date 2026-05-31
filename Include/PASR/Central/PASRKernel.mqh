//+------------------------------------------------------------------+
//| Central/PASRKernel.mqh — v0.21                                   |
//| Compatibility facade for Centralized Modular Pipeline migration    |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_CENTRAL_KERNEL_MQH__
#define __PASR_CENTRAL_KERNEL_MQH__

// v0.21 still delegates runtime to COrchestrator, but binds more backend
// services into the central registry so Phase 2 modules can resolve them
// through CServiceLocator without taking ownership yet.

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
   COrchestrator          *m_backend;
   CModuleRegistry         m_registry;
   CServiceLocator         m_services;
   CLifecycleManager       m_lifecycle;
   StrategyConfig          m_cfg;
   ENUM_PASR_KERNEL_STATE  m_state;
   bool                    m_ready;
   bool                    m_debug;
   bool                    m_profiling_enabled;
   string                  m_last_error;

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

   bool ValidateBackendServices()
     {
      if(m_backend == NULL)
        {
         m_last_error = "Backend is NULL";
         return false;
        }

      bool ok = true;
      ok = RequireService(PASR_MOD_DATA_MANAGER)      && ok;
      ok = RequireService(PASR_MOD_SIGNAL_MANAGER)    && ok;
      ok = RequireService(PASR_MOD_RISK_MANAGER)      && ok;
      ok = RequireService(PASR_MOD_EXECUTION_MANAGER) && ok;
      ok = RequireService(PASR_MOD_EXIT_ENGINE)       && ok;
      return ok;
     }

public:
   CPASRKernel()
      : m_backend(NULL), m_state(PASR_KERNEL_STOPPED), m_ready(false),
        m_debug(false), m_profiling_enabled(true), m_last_error("")
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
      if(m_backend != NULL)
         m_backend.SetDebugMode(enabled);
     }

   void SetProfilingEnabled(const bool enabled)
     {
      m_profiling_enabled = enabled;
      if(m_backend != NULL)
         m_backend.SetProfilingEnabled(enabled);
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

      m_backend = new COrchestrator();
      if(m_backend == NULL)
        {
         SetState(PASR_KERNEL_FAILED, "Backend orchestrator allocation failed");
         Print("[PASRKernel] Backend orchestrator allocation failed");
         return INIT_FAILED;
        }

      m_backend.SetDebugMode(m_debug);
      m_backend.SetProfilingEnabled(m_profiling_enabled);
      int rc = m_backend.Init(m_cfg);
      if(rc != INIT_SUCCEEDED)
        {
         SetState(PASR_KERNEL_FAILED, "Backend orchestrator init failed");
         Print("[PASRKernel] Backend orchestrator init failed");
         delete m_backend;
         m_backend = NULL;
         return rc;
        }

      BindBackendServices();
      if(!ValidateBackendServices())
        {
         SetState(PASR_KERNEL_FAILED, m_last_error);
         Shutdown(REASON_INITFAILED);
         return INIT_FAILED;
        }

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

      if(m_backend != NULL)
        {
         m_backend.OnDeinit(reason);
         delete m_backend;
         m_backend = NULL;
        }
      m_registry.Clear(false);
      m_ready = false;
      SetState(PASR_KERNEL_STOPPED);
     }

   void OnTick()
     {
      if(m_ready && m_backend != NULL)
         m_backend.OnTick();
     }

   void OnTimer()
     {
      if(m_ready && m_backend != NULL)
         m_backend.OnTimer();
     }

   void OnDeinit(const int reason)
     {
      Shutdown(reason);
     }

   void OnTradeTransaction(const MqlTradeTransaction &trans,
                           const MqlTradeRequest &request,
                           const MqlTradeResult &result)
     {
      if(m_ready && m_backend != NULL)
         m_backend.OnTradeTransaction(trans, request, result);
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

   COrchestrator* Backend() const
     {
      return m_backend;
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
      return (m_backend != NULL) ? m_backend.GetEventBus() : NULL;
     }

   CDataManager* GetDataManager() const
     {
      return (m_backend != NULL) ? m_backend.GetDataManager() : NULL;
     }

   CRiskManager* GetRiskManager() const
     {
      return (m_backend != NULL) ? m_backend.GetRiskManager() : NULL;
     }

   CDashboardManager* GetDashboard() const
     {
      return (m_backend != NULL) ? m_backend.GetDashboard() : NULL;
     }

   void BindBackendServices()
     {
      m_registry.Clear(false);
      if(m_backend == NULL)
         return;

      // owned=false because the legacy orchestrator still owns these objects.
      m_registry.RegisterOrReplace(PASR_MOD_DATA_MANAGER,      m_backend.GetDataManager(),      false);
      m_registry.RegisterOrReplace(PASR_MOD_SR_MANAGER,        m_backend.GetSRManager(),        false);
      m_registry.RegisterOrReplace(PASR_MOD_ZONE_MANAGER,      m_backend.GetZoneManager(),      false);
      m_registry.RegisterOrReplace(PASR_MOD_PATTERN_MANAGER,   m_backend.GetPatternManager(),   false);
      m_registry.RegisterOrReplace(PASR_MOD_SIGNAL_MANAGER,    m_backend.GetSignalManager(),    false);
      m_registry.RegisterOrReplace(PASR_MOD_AI_ORCHESTRATOR,   m_backend.GetAIOrchestrator(),   false);
      m_registry.RegisterOrReplace(PASR_MOD_REGIME_FILTER,     m_backend.GetRegimeFilter(),     false);
      m_registry.RegisterOrReplace(PASR_MOD_RISK_MANAGER,      m_backend.GetRiskManager(),      false);
      m_registry.RegisterOrReplace(PASR_MOD_EXECUTION_MANAGER, m_backend.GetExecManager(),      false);
      m_registry.RegisterOrReplace(PASR_MOD_EXIT_ENGINE,       m_backend.GetExitEngine(),       false);
      m_registry.RegisterOrReplace(PASR_MOD_RECOVERY_MANAGER,  m_backend.GetRecoveryManager(),  false);
      m_registry.RegisterOrReplace(PASR_MOD_JOURNAL_MANAGER,   m_backend.GetJournalManager(),   false);
      m_registry.RegisterOrReplace(PASR_MOD_DASHBOARD_MANAGER, m_backend.GetDashboard(),        false);

      // Phase 2 optional infra services. Literal names are used to avoid
      // changing public ModuleNames macros during the compatibility phase.
      m_registry.RegisterOrReplace("SanityManager",            m_backend.GetSanityManager(),    false);
      m_registry.RegisterOrReplace("TelemetryRecorder",        m_backend.GetTelemetry(),        false);
      m_registry.RegisterOrReplace("AdaptiveParameterManager", m_backend.GetAdaptiveManager(),  false);
      m_registry.RegisterOrReplace("HealthMonitor",            m_backend.GetHealthMonitor(),    false);
      m_registry.RegisterOrReplace("SnapshotManager",          m_backend.GetSnapshotManager(),  false);
      m_registry.RegisterOrReplace("SessionState",             m_backend.GetSessionState(),     false);
     }
  };

#endif // __PASR_CENTRAL_KERNEL_MQH__
