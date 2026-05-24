//+------------------------------------------------------------------+
//|                                       Core/PASR.mqh              |
//|                          Copyright 2026, Agsicentre              |
//|                                                                  |
//|  PURPOSE: Master include untuk PASR Modular EA                   |
//|    User hanya perlu include file ini untuk menggunakan PASR.     |
//|    Semua dependency di-include secara terurut dan stabil.        |
//|                                                                  |
//|  USAGE:                                                          |
//|    #include <PASR/Core/PASR.mqh>                                 |
//|                                                                  |
//|  CHANGELOG:                                                      |
//|  v1.01 (2026-05-24):                                            |
//|    - Include order corrected: Orchestrator/PipelineEngine now    |
//|      load AFTER manager classes they reference.                  |
//|  v1.00 (2026-05-24) — Sprint 21: Issue #180 resolved             |
//|    - Placeholder dihapus, menjadi master include sungguhan       |
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_PASR_MASTER_MQH__
#define __CORE_PASR_MASTER_MQH__

// ── Layer 0: Config + core primitives ─────────────────────────────
#include "Config/Types.mqh"
#include "Globals.mqh"
#include "Events.mqh"
#include "EventBus.mqh"
#include "IManager.mqh"
#include "PipelineTypes.mqh"

// ── Layer 1: State & utility core ─────────────────────────────────
#include "StateOwnershipMap.mqh"
#include "PASR_SymbolManager.mqh"
#include "LatencyOptimizer.mqh"
#include "AsyncOrderManager.mqh"
#include "HighFreqTimer.mqh"

// ── Layer 2: Infra managers ───────────────────────────────────────
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

// ── Layer 3: Analysis managers ────────────────────────────────────
#include "../Analysis/SRManager.mqh"
#include "../Analysis/ZoneManager.mqh"
#include "../Analysis/MarketRegimeDetector.mqh"
#include "../Analysis/AdaptiveParameterManager.mqh"
#include "../Analysis/Pattern/PatternManager.mqh"

// ── Layer 4: AI managers and signal sources ───────────────────────
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

// ── Layer 5: Signal managers ──────────────────────────────────────
#include "../Signal/SignalFilterPipeline.mqh"
#include "../Signal/SignalManager.mqh"

// ── Layer 6: Trade managers ───────────────────────────────────────
#include "../Trade/TradePlan.mqh"
#include "../Trade/PositionManager.mqh"
#include "../Trade/ExitEngine.mqh"
#include "../Trade/RiskManager.mqh"
#include "../Trade/ExecutionManager.mqh"
#include "../Trade/RecoveryEngine.mqh"
#include "../Trade/RecoveryManager.mqh"
#include "../Trade/CorrelationManager.mqh"

// ── Layer 7: UI + QA helpers ──────────────────────────────────────
#include "../UI/DashboardManager.mqh"
#include "../QA/LatencySimulator.mqh"

// ── Layer 8: Pipeline and orchestration — after all manager types ─
#include "PipelineEngine.mqh"
#include "Orchestrator.mqh"

#endif // __CORE_PASR_MASTER_MQH__
