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
#include "Config/Validator.mqh"
#include "Globals.mqh"
#include "Events.mqh"
#include "EventBus.mqh"
#include "Config/Manager.mqh"
#include "IManager.mqh"
#include "PipelineTypes.mqh"

// Layer 0b: Cross-layer data-only types
// Keep this layer free from manager classes to avoid early IManager/DataManager cycles.
#include <PASR/Data/RegimeTypes.mqh>
#include <PASR/Data/SRStruct.mqh>

// Layer 1: Core utilities that do not pull Trade/Analysis managers
#include "StateOwnershipMap.mqh"
#include "PASR_SymbolManager.mqh"
#include "LatencyOptimizer.mqh"
#include "HighFreqTimer.mqh"

// Layer 2: Infra managers and data providers
#include <PASR/Infra/AdaptiveConfig.mqh>
#include <PASR/Infra/AccountSnapshot.mqh>
#include <PASR/Infra/DataManager.mqh>
#include <PASR/Infra/HealthMonitor.mqh>
#include <PASR/Infra/SessionState.mqh>
#include <PASR/Infra/SnapshotManager.mqh>
#include <PASR/Infra/JournalManager.mqh>
#include <PASR/Infra/TelemetryRecorder.mqh>
#include <PASR/Infra/PerformanceReport.mqh>
#include <PASR/Infra/SanityManager.mqh>
#include <PASR/Infra/StateManager.mqh>

// SymbolScanner is a manager-like component, not a pure data type.
// Include it after DataManager/IManager contracts are available.
#include <PASR/Data/SymbolScanner.mqh>

// Layer 3: Analysis base modules and helpers
#include <PASR/Analysis/Pattern/PatternTypes.mqh>
#include <PASR/Analysis/Pattern/PatternManager.mqh>
#include <PASR/Analysis/SRDetector.mqh>
#include <PASR/Analysis/SRManager.mqh>
#include <PASR/Analysis/ZoneManager.mqh>
#include <PASR/Analysis/MarketRegimeDetector.mqh>
#include <PASR/Analysis/AdaptiveParameterManager.mqh>

// Layer 4: Trade primitive types required by Signal scoring/aggregation
#include <PASR/Trade/TradePlan.mqh>

// Layer 5: AI managers and AI signal source
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

// Layer 6: Signal base/config/pipeline before concrete managers/sources
#include <PASR/Signal/ISignalSource.mqh>
#include <PASR/Signal/SignalConfig.mqh>
#include <PASR/Signal/SignalFilterPipeline.mqh>
#include <PASR/Signal/SignalCooldownManager.mqh>
#include <PASR/Signal/SignalScorer.mqh>
#include <PASR/Signal/SignalAggregator.mqh>
#include <PASR/Signal/SignalFilter.mqh>
#include <PASR/Signal/RegimeFilter.mqh>
#include <PASR/Signal/RegimeSignalSource.mqh>
#include <PASR/Signal/PatternSignalSource.mqh>
#include <PASR/Signal/SRSignalSource.mqh>
#include <PASR/Signal/SignalManager.mqh>

// Layer 7: Trade managers
#include <PASR/Trade/PositionRegistry.mqh>
#include <PASR/Trade/PositionManager.mqh>
#include <PASR/Trade/ExitEngine.mqh>
#include <PASR/Trade/RiskManager.mqh>
#include <PASR/Trade/ExecutionManager.mqh>
#include <PASR/Trade/RecoveryEngine.mqh>
#include <PASR/Trade/RecoveryManager.mqh>
#include <PASR/Trade/CorrelationManager.mqh>

// AsyncOrderManager depends on ExecutionManager, so it must stay after Trade managers.
#include "AsyncOrderManager.mqh"

// Layer 8: UI + QA helpers
#include <PASR/UI/DashboardManager.mqh>
#include <PASR/QA/LatencySimulator.mqh>

// Layer 9: Orchestration interfaces + legacy pipeline backend
// PipelineStage is the forward-compatible split-stage interface.
// CPipelineEngine is canonical in Orchestration; Core/PipelineEngine.mqh is a compatibility wrapper.
#include <PASR/Orchestration/PipelineStage.mqh>
#include <PASR/Orchestration/Stages/DataSyncStage.mqh>
#include <PASR/Orchestration/Stages/AnalysisSRStage.mqh>
#include <PASR/Orchestration/Stages/AnalysisZoneStage.mqh>
#include <PASR/Orchestration/Stages/PatternStage.mqh>
#include <PASR/Orchestration/Stages/RegimeStage.mqh>
#include <PASR/Orchestration/Stages/SignalStage.mqh>
#include <PASR/Orchestration/Stages/AIInferStage.mqh>
#include <PASR/Orchestration/Stages/RiskStage.mqh>
#include <PASR/Orchestration/Stages/AdaptiveParamsStage.mqh>
#include <PASR/Orchestration/Stages/ExecutionStage.mqh>
#include <PASR/Orchestration/Stages/PositionStage.mqh>
#include <PASR/Orchestration/Stages/RecoveryStage.mqh>
#include <PASR/Orchestration/Stages/DashboardStage.mqh>
#include <PASR/Orchestration/Stages/JournalStage.mqh>
#include <PASR/Orchestration/PipelineEngine.mqh>

// PipelineTypes temporarily maps DetectSession -> PASRDetectSession so included
// core pipeline code binds to the canonical helper. Undefine it before returning
// to the EA translation unit so PASR_MODULAR.mq5 can keep its own helper name.
#ifdef DetectSession
#undef DetectSession
#endif

// Layer 10: Centralized Modular Pipeline facade
#include <PASR/Central/ModuleNames.mqh>
#include <PASR/Central/ModuleRegistry.mqh>
#include <PASR/Central/ServiceLocator.mqh>
#include <PASR/Central/LifecycleManager.mqh>
#include <PASR/Central/ModuleFactory.mqh>
#include <PASR/Central/PASRKernel.mqh>

#endif // __CORE_PASR_MASTER_MQH__
