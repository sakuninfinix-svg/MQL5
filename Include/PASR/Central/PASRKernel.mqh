//+------------------------------------------------------------------+
//| Central/PASRKernel.mqh — v0.11                                    |
//| Compatibility facade for Centralized Modular Pipeline migration    |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_CENTRAL_KERNEL_MQH__
#define __PASR_CENTRAL_KERNEL_MQH__

// v0.11 intentionally delegates to the existing COrchestrator backend.
// This allows EAs to migrate from COrchestrator to CPASRKernel without
// changing runtime behavior while responsibilities are extracted gradually.

class CPASRKernel
  {
private:
   COrchestrator     *m_backend;
   CModuleRegistry    m_registry;
   CServiceLocator    m_services;
   CLifecycleManager  m_lifecycle;
   StrategyConfig     m_cfg;
   bool               m_ready;
   bool               m_debug;
   bool               m_profiling_enabled;

public:
   CPASRKernel()
      : m_backend(NULL), m_ready(false), m_debug(false), m_profiling_enabled(true)
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

      m_cfg = cfg;
      m_backend = new COrchestrator();
      if(m_backend == NULL)
        {
         Print("[PASRKernel] Backend orchestrator allocation failed");
         return INIT_FAILED;
        }

      m_backend.SetDebugMode(m_debug);
      m_backend.SetProfilingEnabled(m_profiling_enabled);
      int rc = m_backend.Init(m_cfg);
      if(rc != INIT_SUCCEEDED)
        {
         Print("[PASRKernel] Backend orchestrator init failed");
         delete m_backend;
         m_backend = NULL;
         return rc;
        }

      BindBackendServices();
      m_ready = true;
      Print("[PASRKernel] Centralized Modular Pipeline facade initialized");
      return INIT_SUCCEEDED;
     }

   void Shutdown(const int reason)
     {
      if(m_backend != NULL)
        {
         m_backend.OnDeinit(reason);
         delete m_backend;
         m_backend = NULL;
        }
      m_registry.Clear(false);
      m_ready = false;
     }

   void OnTick()
     {
      if(m_backend != NULL)
         m_backend.OnTick();
     }

   void OnTimer()
     {
      if(m_backend != NULL)
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
      if(m_backend != NULL)
         m_backend.OnTradeTransaction(trans, request, result);
     }

   bool IsReady() const
     {
      return m_ready;
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
      m_registry.Register("DataManager",      m_backend.GetDataManager(),      false);
      m_registry.Register("SRManager",        m_backend.GetSRManager(),        false);
      m_registry.Register("ZoneManager",      m_backend.GetZoneManager(),      false);
      m_registry.Register("PatternManager",   m_backend.GetPatternManager(),   false);
      m_registry.Register("SignalManager",    m_backend.GetSignalManager(),    false);
      m_registry.Register("AIOrchestrator",   m_backend.GetAIOrchestrator(),   false);
      m_registry.Register("RegimeFilter",     m_backend.GetRegimeFilter(),     false);
      m_registry.Register("RiskManager",      m_backend.GetRiskManager(),      false);
      m_registry.Register("ExecutionManager", m_backend.GetExecManager(),      false);
      m_registry.Register("ExitEngine",       m_backend.GetExitEngine(),       false);
      m_registry.Register("RecoveryManager",  m_backend.GetRecoveryManager(),  false);
      m_registry.Register("JournalManager",   m_backend.GetJournalManager(),   false);
      m_registry.Register("DashboardManager", m_backend.GetDashboard(),        false);
     }
  };

#endif // __PASR_CENTRAL_KERNEL_MQH__
