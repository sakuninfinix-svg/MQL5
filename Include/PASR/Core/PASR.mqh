//+------------------------------------------------------------------+
//|                                       Core/PASR.mqh              |
//|                          Copyright 2026, Agsicentre              |
//|                                                                  |
//|  PURPOSE: Master include untuk PASR Modular EA                   |
//|    User hanya perlu include file ini untuk menggunakan PASR.     |
//|    Semua dependency di-include secara terurut dan stabil.        |
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_PASR_MASTER_MQH__
#define __CORE_PASR_MASTER_MQH__

// Layer 0: Config + core primitives
#include "Config/Types.mqh"
#include "Globals.mqh"
#include "Events.mqh"
#include "EventBus.mqh"
#include "IManager.mqh"
#include "PipelineTypes.mqh"

// Layer 0b: Data types (used by multiple layers)
#include <PASR/Data/RegimeTypes.mqh>
#include <PASR/Data/SRStruct.mqh>
#include <PASR/Data/SymbolScanner.mqh>

// Layer 1: State & utility core
#include "StateOwnershipMap.mqh"
#include "PASR_SymbolManager.mqh"
#include "LatencyOptimizer.mqh"
#include "AsyncOrderManager.mqh"
#include "HighFreqTimer.mqh"

// Layer 2: Infra managers
#include <PASR/Infra/AdaptiveConfig.mqh>
#include <PASR/Infra/DataManager.mqh>
#include <PASR/Infra/HealthMonitor.mqh>
#include <PASR/Infra/SessionState.mqh>
#include <PASR/Infra/SnapshotManager.mqh>
#include <PASR/Infra/JournalManager.mqh>
#include <PASR/Infra/TelemetryRecorder.mqh>
#include <PASR/Infra/PerformanceReport.mqh>
#include <PASR/Infra/SanityManager.mqh>
#include <PASR/Infra/StateManager.mqh>

// Layer 3: Analysis managers
#include <PASR/Analysis/SRManager.mqh>
#include <PASR/Analysis/ZoneManager.mqh>
#include <PASR/Analysis/MarketRegimeDetector.mqh>
#include <PASR/Analysis/AdaptiveParameterManager.mqh>
#include <PASR/Analysis/Pattern/PatternManager.mqh>
#include <PASR/Analysis/Pattern/CandleUtils.mqh>
#include <PASR/Analysis/Pattern/FakeoutDetector.mqh>
#include <PASR/Analysis/Pattern/PatternTypes.mqh>
#include <PASR/Analysis/Pattern/ScoreEngine.mqh>
#include <PASR/Analysis/SRDetector.mqh>

// Layer 4: AI managers and signal sources
#include <PASR/AI/AITypes.mqh>
#include <PASR/AI/AIFeatureBuilder.mqh>
#include <PASR/AI/AIInference.mqh>
#include <PASR/AI/AIEnsemble.mqh>
#include <PASR/AI/AITrainer.mqh>
#include <PASR/AI/ConfidenceCalibrator.mqh>
#include <PASR/AI/OnlineLearningGuard.mqh>
#include <PASR/AI/AICalibrationBridge.mqh>
#include <PASR/AI/ModelRegistry.mqh>
#include <PASR/AI/ONNXBridge.mqh>
#include <PASR/AI/AIOrchestrator.mqh>
#include <PASR/AI/AISignalSource.mqh>

// Layer 5: Signal managers
#include <PASR/Signal/SignalFilterPipeline.mqh>
#include <PASR/Signal/RegimeFilter.mqh>
#include <PASR/Signal/RegimeSignalSource.mqh>
#include <PASR/Signal/SignalManager.mqh>
#include <PASR/Signal/ISignalSource.mqh>
#include <PASR/Signal/PatternSignalSource.mqh>
#include <PASR/Signal/SignalAggregator.mqh>
#include <PASR/Signal/SignalConfig.mqh>
#include <PASR/Signal/SignalCooldownManager.mqh>
#include <PASR/Signal/SignalFilter.mqh>
#include <PASR/Signal/SignalScorer.mqh>
#include <PASR/Signal/SRSignalSource.mqh>

// Layer 6: Trade managers
#include "../Trade/TradePlan.mqh"
#include "../Trade/PositionManager.mqh"
#include "../Trade/ExitEngine.mqh"
#include "../Trade/RiskManager.mqh"
#include "../Trade/ExecutionManager.mqh"
#include "../Trade/RecoveryEngine.mqh"
#include "../Trade/RecoveryManager.mqh"
#include "../Trade/CorrelationManager.mqh"

// Layer 7: UI + QA helpers
#include "../UI/DashboardManager.mqh"
#include "../QA/LatencySimulator.mqh"

// Layer 8: Orchestration interfaces + legacy pipeline backend
// PipelineStage is the forward-compatible split-stage interface.
// CPipelineEngine remains in Core during the compatibility phase.
#include "../Orchestration/PipelineStage.mqh"
#include "PipelineEngine.mqh"

// PipelineTypes temporarily maps DetectSession -> PASRDetectSession so included
// core pipeline code binds to the canonical helper. Undefine it before returning
// to the EA translation unit so PASR_MODULAR.mq5 can keep its own helper name.
#ifdef DetectSession
#undef DetectSession
#endif

#include "Orchestrator.mqh"
#include "OrchestratorInit.mqh"

// Layer 9: Centralized Modular Pipeline facade
// These files are included after the legacy orchestrator so CPASRKernel can
// delegate to COrchestrator during the non-breaking migration phase.
#include "../Central/ModuleNames.mqh"
#include "../Central/ModuleRegistry.mqh"
#include "../Central/ServiceLocator.mqh"
#include "../Central/LifecycleManager.mqh"
#include "../Central/PASRKernel.mqh"

#endif // __CORE_PASR_MASTER_MQH__
