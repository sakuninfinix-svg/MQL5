//+------------------------------------------------------------------+
//| Central/ServiceLocator.mqh — v0.10                                |
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

   IManager* GetManager(const string name) const
     {
      return Lookup(name);
     }

   CDataManager* Data() const
     {
      return (CDataManager*)Lookup("DataManager");
     }

   CAnalysisSRManager* SR() const
     {
      return (CAnalysisSRManager*)Lookup("SRManager");
     }

   CAnalysisZoneManager* Zone() const
     {
      return (CAnalysisZoneManager*)Lookup("ZoneManager");
     }

   CPatternManager* Pattern() const
     {
      return (CPatternManager*)Lookup("PatternManager");
     }

   CSignalManager* Signal() const
     {
      return (CSignalManager*)Lookup("SignalManager");
     }

   CAIOrchestrator* AI() const
     {
      return (CAIOrchestrator*)Lookup("AIOrchestrator");
     }

   CRegimeFilter* RegimeFilter() const
     {
      return (CRegimeFilter*)Lookup("RegimeFilter");
     }

   CRiskManager* Risk() const
     {
      return (CRiskManager*)Lookup("RiskManager");
     }

   CExecutionManager* Execution() const
     {
      return (CExecutionManager*)Lookup("ExecutionManager");
     }

   CExitEngine* Exit() const
     {
      return (CExitEngine*)Lookup("ExitEngine");
     }

   CRecoveryManager* Recovery() const
     {
      return (CRecoveryManager*)Lookup("RecoveryManager");
     }

   CJournalManager* Journal() const
     {
      return (CJournalManager*)Lookup("JournalManager");
     }

   CDashboardManager* Dashboard() const
     {
      return (CDashboardManager*)Lookup("DashboardManager");
     }
  };

#endif // __PASR_CENTRAL_SERVICE_LOCATOR_MQH__
