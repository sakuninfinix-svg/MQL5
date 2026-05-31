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
#include "../Data/RegimeTypes.mqh"
#include "../Data/SRStruct.mqh"

// Layer 1: State & utility core
#include "StateOwnershipMap.mqh"
#include "PASR_SymbolManager.mqh"
#include "LatencyOptimizer.mqh"
#include "AsyncOrderManager.mqh"
#include "HighFreqTimer.mqh"

// Layer 2: Infra managers
#include "../Infra/AdaptiveConfig.mqh"
#include "../Infra/DataManager.mqh"
#include "../Infra/HealthMonitor.mqh"
#include "../Infra/SessionState.mqh"
#include "../Infra/SnapshotManager.mqh"
#include "../Infra/JournalManager.mqh"
#include "../Infra/TelemetryRecorder.mqh"
#include "../Infra/PerformanceReport.mqh"
#include "../Infra/SanityManager.mqh"
#include "../Infra/StateManager.mqh"

// Layer 3: Analysis managers
#include "../Analysis/SRManager.mqh"
#include "../Analysis/ZoneManager.mqh"
#include "../Analysis/MarketRegimeDetector.mqh"
#include "../Analysis/AdaptiveParameterManager.mqh"
#include "../Analysis/Pattern/PatternManager.mqh"

// Layer 4: AI managers and signal sources
#include "../AI/AITypes.mqh"
#include "../AI/AIFeatureBuilder.mqh"
#include "../AI/AIInference.mqh"
#include "../AI/AIEnsemble.mqh"
#include "../AI/AITrainer.mqh"
#include "../AI/ConfidenceCalibrator.mqh"
#include "../AI/OnlineLearningGuard.mqh"
#include "../AI/AICalibrationBridge.mqh"
#include "../AI/ModelRegistry.mqh"
#include "../AI/ONNXBridge.mqh"
#include "../AI/AIOrchestrator.mqh"
#include "../AI/AISignalSource.mqh"

// Layer 5: Signal managers
#include "../Signal/SignalFilterPipeline.mqh"
#include "../Signal/RegimeFilter.mqh"
#include "../Signal/RegimeSignalSource.mqh"
#include "../Signal/SignalManager.mqh"

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
