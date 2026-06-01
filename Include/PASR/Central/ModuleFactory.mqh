//+------------------------------------------------------------------+
//| Central/ModuleFactory.mqh - v0.10                                |
//| Central allocation factory for PASR runtime modules               |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_CENTRAL_MODULE_FACTORY_MQH__
#define __PASR_CENTRAL_MODULE_FACTORY_MQH__

class CModuleFactory
  {
public:
   static CEventBus* CreateEventBus()
     { return new CEventBus(); }

   static CDataManager* CreateDataManager()
     { return new CDataManager(); }

   static CAnalysisSRManager* CreateSRManager()
     { return new CAnalysisSRManager(); }

   static CAnalysisZoneManager* CreateZoneManager()
     { return new CAnalysisZoneManager(); }

   static CRegimeFilter* CreateRegimeFilter()
     { return new CRegimeFilter(); }

   static CPatternManager* CreatePatternManager()
     { return new CPatternManager(); }

   static CSignalManager* CreateSignalManager()
     { return new CSignalManager(); }

   static CAIOrchestrator* CreateAIOrchestrator()
     { return new CAIOrchestrator(); }

   static CRiskManager* CreateRiskManager()
     { return new CRiskManager(); }

   static CExecutionManager* CreateExecutionManager()
     { return new CExecutionManager(); }

   static CExitEngine* CreateExitEngine()
     { return new CExitEngine(); }

   static CRecoveryManager* CreateRecoveryManager()
     { return new CRecoveryManager(); }

   static CJournalManager* CreateJournalManager()
     { return new CJournalManager(); }

   static CDashboardManager* CreateDashboardManager()
     { return new CDashboardManager(); }

   static CPipelineEngine* CreatePipelineEngine()
     { return new CPipelineEngine(); }
  };

#endif // __PASR_CENTRAL_MODULE_FACTORY_MQH__
