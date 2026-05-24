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
//|  v1.00 (2026-05-24) — Sprint 21: Issue #180 resolved             |
//|    - Placeholder dihapus, menjadi master include sungguhan       |
//|    - Include ordering distabilkan                                |
//|    - Semua core types dan managers tersedia                      |
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_PASR_MASTER_MQH__
#define __CORE_PASR_MASTER_MQH__

// ── Layer 0: Config Types (no dependencies) ───────────────────────
#include "Config/Types.mqh"

// ── Layer 1: Core Infrastructure ──────────────────────────────────
#include "Globals.mqh"
#include "Events.mqh"
#include "EventBus.mqh"
#include "IManager.mqh"

// ── Layer 2: Pipeline & Orchestration ─────────────────────────────
#include "PipelineTypes.mqh"
#include "PipelineEngine.mqh"
#include "Orchestrator.mqh"

// ── Layer 3: State & Ownership ────────────────────────────────────
#include "StateOwnershipMap.mqh"
#include "PASR_SymbolManager.mqh"

// ── Layer 4: Infra Managers (Data, Health, Session, etc.) ─────────
#include "../Infra/DataManager.mqh"
#include "../Infra/HealthMonitor.mqh"
#include "../Infra/SessionState.mqh"
#include "../Infra/SnapshotManager.mqh"
#include "../Infra/JournalManager.mqh"
#include "../Infra/TelemetryRecorder.mqh"
#include "../Infra/PerformanceReport.mqh"
#include "../Infra/SanityManager.mqh"
#include "../Infra/StateManager.mqh"
#include "../Infra/AdaptiveConfig.mqh"

// ── Layer 5: Analysis Managers ────────────────────────────────────
#include "../Analysis/SRManager.mqh"
#include "../Analysis/ZoneManager.mqh"
#include "../Analysis/MarketRegimeDetector.mqh"
#include "../Analysis/AdaptiveParameterManager.mqh"
#include "../Analysis/Pattern/PatternManager.mqh"

// ── Layer 6: Signal Managers ──────────────────────────────────────
#include "../Signal/SignalManager.mqh"
#include "../Signal/SignalFilterPipeline.mqh"

// ── Layer 7: Trade Managers ───────────────────────────────────────
#include "../Trade/RiskManager.mqh"
#include "../Trade/ExecutionManager.mqh"
#include "../Trade/RecoveryManager.mqh"
#include "../Trade/PositionManager.mqh"
#include "../Trade/ExitEngine.mqh"
#include "../Trade/CorrelationManager.mqh"

// ── Layer 8: AI Managers ──────────────────────────────────────────
#include "../AI/AIOrchestrator.mqh"
#include "../AI/AIFeatureBuilder.mqh"
#include "../AI/AIInference.mqh"
#include "../AI/AIEnsemble.mqh"
#include "../AI/AITrainer.mqh"
#include "../AI/ConfidenceCalibrator.mqh"
#include "../AI/OnlineLearningGuard.mqh"
#include "../AI/AISignalSource.mqh"
#include "../AI/ModelRegistry.mqh"

// ── Layer 9: UI Managers ──────────────────────────────────────────
#include "../UI/DashboardManager.mqh"

// ── Layer 10: Low Latency & QA ────────────────────────────────────
#include "LatencyOptimizer.mqh"
#include "AsyncOrderManager.mqh"
#include "HighFreqTimer.mqh"
#include "../QA/LatencySimulator.mqh"

#endif // __CORE_PASR_MASTER_MQH__