//+------------------------------------------------------------------+
//| Central/PASRKernel.mqh — v0.23                                   |
//| Compatibility facade for Centralized Modular Pipeline migration    |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_CENTRAL_KERNEL_MQH__
#define __PASR_CENTRAL_KERNEL_MQH__

// v0.30 owns CPipelineEngine and uses CBackendAdapter as a temporary
// manager/event provider while manager ownership moves into Central.

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
   CBackendAdapter        *m_backend;
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

   bool RegisterBorrowedIfMissing(const string name, IManager *module)
     {
      if(module == NULL)
         return false;
      if(m_registry.Contains(name))
         return true;
      return m_registry.RegisterOrReplace(name, module, false);
     }

   bool InitPipeline()
     {
      if(m_backend == NULL)
        {
         m_last_error = "Cannot initialize pipeline without backend";
         return false;
        }

      m_pipeline = CModuleFactory::CreatePipelineEngine();
      if(m_pipeline == NULL)
        {
         m_last_error = "PipelineEngine allocation failed";
         Print("[PASRKernel] ", m_last_error);
         return false;
        }

      m_pipeline.SetDebugMode(m_debug);
      m_pipeline.EnableProfiling(m_profiling_enabled);

      // Phase 4 cleanup: pipeline dependencies are now sourced from the
      // central typed service locator wherever a module is registry-owned.
      // Backend direct access remains only for compatibility-only services
      // that are not yet represented as IManager registry entries.
      m_pipeline.InjectManagers(m_services.Data(),
                                m_services.SR(),
                                m_services.Zone(),
                                m_services.Pattern(),
                                m_services.Signal(),
                                m_services.AI(),
                                m_services.RegimeFilter(),
                                m_services.Risk(),
                                m_services.Execution(),
                                m_services.Recovery(),
                                m_services.Dashboard(),
                                m_services.Journal(),
                                m_backend.GetEventBus(),
                                m_services.Sanity(),
                                m_services.Telemetry(),
                                m_services.Adaptive(),
                                m_backend.GetRegimeDetector(),
                                NULL,
                                NULL,
                                m_services.Health(),
                                m_services.Snapshot(),
                                m_services.Exit());
      return true;
     }

public:
   CPASRKernel()
      : m_backend(NULL), m_pipeline(NULL), m_state(PASR_KERNEL_STOPPED), m_ready(false),
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
      if(m_pipeline != NULL)
         m_pipeline.SetDebugMode(enabled);
     }

   void SetProfilingEnabled(const bool enabled)
     {
      m_profiling_enabled = enabled;
      if(m_backend != NULL)
         m_backend.SetProfilingEnabled(enabled);
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

      m_backend = new CBackendAdapter();
      if(m_backend == NULL)
        {
         SetState(PASR_KERNEL_FAILED, "Backend orchestrator allocation failed");
         Print("[PASRKernel] Backend orchestrator allocation failed");
         return INIT_FAILED;
        }

      m_backend.SetDebugMode(m_debug);
      m_backend.SetProfilingEnabled(m_profiling_enabled);
      m_backend.BindOwnerRegistry(&m_registry, true);
      int rc = m_backend.Init(m_cfg);
      if(rc != INIT_SUCCEEDED)
        {
         SetState(PASR_KERNEL_FAILED, "Backend orchestrator init failed");
         Print("[PASRKernel] Backend orchestrator init failed");
         delete m_backend;
         m_backend = NULL;
         m_registry.Clear(true);
         return rc;
        }

      BindBackendServices();
      if(!ValidateBackendServices())
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

      if(m_backend != NULL)
        {
         m_backend.OnDeinit(reason);
         delete m_backend;
         m_backend = NULL;
        }
      m_registry.Clear(true);
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
      if(!m_ready || m_backend == NULL || m_pipeline == NULL)
         return;

      bool isNewBar = m_backend.ConsumeNewBarFlag();
      m_backend.PreparePipelineContext(m_pipeline_ctx, isNewBar);
      m_backend.DrainEventQueue();
      m_backend.ProcessExecutionRetryQueue();
      ENUM_STAGE_RESULT result = m_pipeline.ExecutePipeline(m_pipeline_ctx);
      m_backend.DrainEventQueue();
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

   CBackendAdapter* Backend() const
     {
      return m_backend;
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
      if(m_backend == NULL)
         return;

      RegisterBorrowedIfMissing(PASR_MOD_DATA_MANAGER,       m_backend.GetDataManager());
      RegisterBorrowedIfMissing(PASR_MOD_SR_MANAGER,         m_backend.GetSRManager());
      RegisterBorrowedIfMissing(PASR_MOD_ZONE_MANAGER,       m_backend.GetZoneManager());
      RegisterBorrowedIfMissing(PASR_MOD_PATTERN_MANAGER,    m_backend.GetPatternManager());
      RegisterBorrowedIfMissing(PASR_MOD_SIGNAL_MANAGER,     m_backend.GetSignalManager());
      RegisterBorrowedIfMissing(PASR_MOD_AI_ORCHESTRATOR,    m_backend.GetAIOrchestrator());
      RegisterBorrowedIfMissing(PASR_MOD_REGIME_FILTER,      m_backend.GetRegimeFilter());
      RegisterBorrowedIfMissing(PASR_MOD_RISK_MANAGER,       m_backend.GetRiskManager());
      RegisterBorrowedIfMissing(PASR_MOD_EXECUTION_MANAGER,  m_backend.GetExecManager());
      RegisterBorrowedIfMissing(PASR_MOD_EXIT_ENGINE,        m_backend.GetExitEngine());
      RegisterBorrowedIfMissing(PASR_MOD_RECOVERY_MANAGER,   m_backend.GetRecoveryManager());
      RegisterBorrowedIfMissing(PASR_MOD_JOURNAL_MANAGER,    m_backend.GetJournalManager());
      RegisterBorrowedIfMissing(PASR_MOD_DASHBOARD_MANAGER,  m_backend.GetDashboard());
      RegisterBorrowedIfMissing(PASR_MOD_SANITY_MANAGER,     m_backend.GetSanityManager());
      RegisterBorrowedIfMissing(PASR_MOD_TELEMETRY_RECORDER, m_backend.GetTelemetry());
      RegisterBorrowedIfMissing(PASR_MOD_ADAPTIVE_MANAGER,   m_backend.GetAdaptiveManager());
      RegisterBorrowedIfMissing(PASR_MOD_HEALTH_MONITOR,     m_backend.GetHealthMonitor());
      RegisterBorrowedIfMissing(PASR_MOD_SNAPSHOT_MANAGER,   m_backend.GetSnapshotManager());
      RegisterBorrowedIfMissing(PASR_MOD_SESSION_STATE,      m_backend.GetSessionState());
     }
  };

#endif // __PASR_CENTRAL_KERNEL_MQH__