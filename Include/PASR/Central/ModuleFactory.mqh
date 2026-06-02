//+------------------------------------------------------------------+
//| Central/ModuleFactory.mqh - v1.00                                |
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

   static CMarketRegimeDetector* CreateMarketRegimeDetector()
     { return new CMarketRegimeDetector(); }

   static CAdaptiveParameterManager* CreateAdaptiveParameterManager()
     { return new CAdaptiveParameterManager(); }

   static CPatternManager* CreatePatternManager()
     { return new CPatternManager(); }

   static CSignalManager* CreateSignalManager()
     { return new CSignalManager(); }

   static PatternSignalSource* CreatePatternSignalSource(CPatternManager *pattern)
     { return new PatternSignalSource(pattern); }

   static SRSignalSource* CreateSRSignalSource(CAnalysisSRManager *sr, IDataManager *data, const double proximityATR = 0.5)
     { return new SRSignalSource(sr, data, proximityATR); }

   static CRegimeSignalSource* CreateRegimeSignalSource(CRegimeFilter *regime, const ENUM_REGIME_SOURCE_MODE mode = REGIME_MODE_VETO)
     { return new CRegimeSignalSource(regime, mode); }

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

   static CSanityManager* CreateSanityManager()
     { return new CSanityManager(); }

   static CTelemetryRecorder* CreateTelemetryRecorder()
     { return new CTelemetryRecorder(); }

   static CHealthMonitor* CreateHealthMonitor()
     { return new CHealthMonitor(); }

   static CSessionState* CreateSessionState()
     { return new CSessionState(); }

   static CJournalManager* CreateJournalManager()
     { return new CJournalManager(); }

   static CDashboardManager* CreateDashboardManager()
     { return new CDashboardManager(); }

   static CPipelineEngine* CreatePipelineEngine()
     { return new CPipelineEngine(); }
  };

#endif // __PASR_CENTRAL_MODULE_FACTORY_MQH__
