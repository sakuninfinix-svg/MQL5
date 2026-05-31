//+------------------------------------------------------------------+
//| Central/ServiceLocator.mqh — v0.20                               |
//| Typed lookup facade for central PASR services/managers             |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_CENTRAL_SERVICE_LOCATOR_MQH__
#define __PASR_CENTRAL_SERVICE_LOCATOR_MQH__

class CServiceLocator
  {
private:
   CModuleRegistry *m_registry;

   IManager* Lookup(const string name) const
     {
      if(m_registry == NULL) return NULL;
      return m_registry.Get(name);
     }

public:
   CServiceLocator()
      : m_registry(NULL)
     {}

   void Bind(CModuleRegistry *registry)
     {
      m_registry = registry;
     }

   bool IsBound() const
     {
      return (m_registry != NULL);
     }

   bool Has(const string name) const
     {
      return (m_registry != NULL && m_registry.Contains(name));
     }

   bool IsReady(const string name) const
     {
      return (m_registry != NULL && m_registry.IsReady(name));
     }

   IManager* GetManager(const string name) const
     {
      return Lookup(name);
     }

   CDataManager* Data() const
     { return (CDataManager*)Lookup(PASR_MOD_DATA_MANAGER); }

   CAnalysisSRManager* SR() const
     { return (CAnalysisSRManager*)Lookup(PASR_MOD_SR_MANAGER); }

   CAnalysisZoneManager* Zone() const
     { return (CAnalysisZoneManager*)Lookup(PASR_MOD_ZONE_MANAGER); }

   CPatternManager* Pattern() const
     { return (CPatternManager*)Lookup(PASR_MOD_PATTERN_MANAGER); }

   CSignalManager* Signal() const
     { return (CSignalManager*)Lookup(PASR_MOD_SIGNAL_MANAGER); }

   CAIOrchestrator* AI() const
     { return (CAIOrchestrator*)Lookup(PASR_MOD_AI_ORCHESTRATOR); }

   CRegimeFilter* RegimeFilter() const
     { return (CRegimeFilter*)Lookup(PASR_MOD_REGIME_FILTER); }

   CRiskManager* Risk() const
     { return (CRiskManager*)Lookup(PASR_MOD_RISK_MANAGER); }

   CExecutionManager* Execution() const
     { return (CExecutionManager*)Lookup(PASR_MOD_EXECUTION_MANAGER); }

   CExitEngine* Exit() const
     { return (CExitEngine*)Lookup(PASR_MOD_EXIT_ENGINE); }

   CRecoveryManager* Recovery() const
     { return (CRecoveryManager*)Lookup(PASR_MOD_RECOVERY_MANAGER); }

   CJournalManager* Journal() const
     { return (CJournalManager*)Lookup(PASR_MOD_JOURNAL_MANAGER); }

   CDashboardManager* Dashboard() const
     { return (CDashboardManager*)Lookup(PASR_MOD_DASHBOARD_MANAGER); }

   CSanityManager* Sanity() const
     { return (CSanityManager*)Lookup("SanityManager"); }

   CTelemetryRecorder* Telemetry() const
     { return (CTelemetryRecorder*)Lookup("TelemetryRecorder"); }

   CAdaptiveParameterManager* Adaptive() const
     { return (CAdaptiveParameterManager*)Lookup("AdaptiveParameterManager"); }

   CHealthMonitor* Health() const
     { return (CHealthMonitor*)Lookup("HealthMonitor"); }

   CSnapshotManager* Snapshot() const
     { return (CSnapshotManager*)Lookup("SnapshotManager"); }

   CSessionState* Session() const
     { return (CSessionState*)Lookup("SessionState"); }
  };

#endif // __PASR_CENTRAL_SERVICE_LOCATOR_MQH__
