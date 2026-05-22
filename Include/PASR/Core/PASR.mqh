//+------------------------------------------------------------------+
//|                                               Core/PASR.mqh      |
//|                          Copyright 2026, Agsicentre             |
//|   PASR Framework — Master Include                                |
//|                                                                  |
//|   USAGE (from your EA):                                          |
//|     #include <PASR/Core/PASR.mqh>                                |
//|                                                                  |
//|   LOAD ORDER GUARANTEE:                                          |
//|     L0   Config     → Types, Validator, Manager (MUST be first)  |
//|     L1   Core       → IManager, EventBus, Events                 |
//|     L1.5 Globals    → extern EA inputs (one decl point)          |
//|     L1.6 Pipeline   → PipelineTypes, PipelineEngine              |
//|     L2   Infra      → DataManager                                |
//|     L3   Data       → MarketRegime, SRManager stubs,              |
//|     L3.5 Analysis   → SRManager (full swing pivot), ZoneManager  |
//|                        (full S/D impulse-base)   [Phase 3]       |
//|     L4   Pattern    → PatternManager                             |
//|     L5a  Signal     → SignalManager v3.00 (weighted-vote + veto) |
//|     L5b  AI         → CAIOrchestrator + AISignalSource (26-dim)  |
//|     L5c  RegimeFilter → CRegimeFilter + RegimeSignalSource [P4]  |
//|     L5d  SRSignalSource + PatternSignalSource     [Phase 3]      |
//|     L5e  RiskManager (full ATR lot + circuit breaker) [Phase 4]  |
//|     L5f  Sanity      → SanityManager (Circuit Breaker) [Phase 5] |
//|     L6   Trade      → TradePlan, ExecutionManager, RecoveryMgr   |
//|     L7   UI         → DashboardManager                           |
//|     L8   Orchestrator → COrchestrator (wires all managers)       |
//|     L9   QA / Tools  → (PASR_QA_BUILD define only)              |
//|                                                                  |
//|   CHANGE LOG:                                                    |
//|   v3.01 (2026-05-21) — Phase 5 Circuit Breaker:                  |
//|     + L5f Infra/SanityManager.mqh added                          |
//|     + Data validation: stale tick, wide spread, price gap        |
//|     + Auto-pause trading on anomalous market conditions          |
//|   v2.18 (2026-05-21) — Pipeline Architecture added:              |
//|     + L1.6 PipelineTypes.mqh + PipelineEngine.mqh                |
//|     + Staged execution replaces monolithic OnTimer()             |
//|     + Profiling-aware pipeline with early-exit                   |
//|   v2.17 (2026-05-21) — Phase 3+4 includes:                      |
//|     + L3.5 Analysis/SRManager.mqh + Analysis/ZoneManager.mqh    |
//|     + L5c  Signal/RegimeFilter.mqh + Signal/RegimeSignalSource   |
//|     + L5d  Signal/SRSignalSource + Signal/PatternSignalSource    |
//|     + L5e  Trade/RiskManager.mqh                                 |
//|   v2.16 (2026-05-21) — FIX #6: canonical subfolder paths        |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property strict

#ifndef __CORE_PASR_MASTER_MQH__
#define __CORE_PASR_MASTER_MQH__

// ─── L0: Config Triad — MUST load before anything else ───────────────────
// Rule: No other PASR header may include Config/* directly.
// All config access flows through CConfigManager → IManager.m_cfg.
#include "Config/Types.mqh"       // StrategyConfig + 5 domain sub-structs
#include "Config/Validator.mqh"   // 33-rule validator (zero dependencies)
#include "Config/Manager.mqh"     // CConfigManager: Init/Reload with Validate()

// ─── L1: Core Foundation ───────────────────────────────────────────
#include "IManager.mqh"
#include "EventBus.mqh"
#include "Events.mqh"

// ─── L1.5: Globals (extern consolidation — one declaration point) ─────────
// WARNING: Globals.mqh uses extern declarations.
// It MUST be included EXACTLY ONCE per compilation unit.
// Do NOT include Globals.mqh from any other header.
#include "Globals.mqh"

// ─── L1.6: Pipeline Architecture (NEW v2.18) ──────────────────────────
#include "PipelineTypes.mqh"
#include "PipelineEngine.mqh"

// ─── L2: Infra — Production DataManager ──────────────────────────────
#include "../Infra/DataManager.mqh"

// ─── L3: Data — Canonical data structures and base classes ─────────────
// MarketRegime: enum + RegimeSnapshot struct + CMarketRegime stub
#include "../Data/RegimeTypes.mqh"
// SRStruct: SRZone struct definition
#include "../Data/SRStruct.mqh"

// ─── L3.5: Analysis — Full implementations (Phase 3) ──────────────────
// CAnalysisSRManager: swing pivot fractal + zone clustering + strength scoring
// Note: Uses SRZone struct from ../Data/SRStruct.mqh
#include "../Analysis/SRManager.mqh"
// CAnalysisZoneManager: Supply/Demand impulse-base zone detection
// Note: SDZone struct is defined inline within ZoneManager.mqh
#include "../Analysis/ZoneManager.mqh"

// ─── L4: Analysis — Pattern recognition ──────────────────────────────
#include "../Analysis/Pattern/PatternManager.mqh"

// ─── L5a: Signal — Manager + ISignalSource interface ───────────────────
// ISignalSource.mqh is included by SignalManager.mqh internally
#include "../Signal/SignalManager.mqh"

// ─── L5b: AI — Neural net inference + AISignalSource plugin ──────────────
// MIGRATED v2.00 (2026-05-22): AIManager deprecated, using CAIOrchestrator (26-dim)
// AISignalSource bridges CAIOrchestrator inference score → ISignalSource interface
#include "../Signal/AI/AITypes.mqh"           // Core types & constants (AI_FEATURE_DIM=26)
#include "../Signal/AI/AIFeatureBuilder.mqh"  // 26-dim feature engineering (includes Z-score, skew, kurtosis)
#include "../Signal/AI/AIInference.mqh"       // Expert routing + forward pass
#include "../Signal/AI/AIOrchestrator.mqh"    // CAIOrchestrator: model mgmt + inference
#include "../Signal/AI/AISignalSource.mqh"    // Bridge: CAIOrchestrator → SignalManager
// AIManager.mqh REMOVED (was deprecated 8-dim legacy system)
// FeatureEngine.mqh REMOVED (dead code - functionality merged into AIFeatureBuilder)

// ─── L5c: Regime filter + source plugin (Phase 4) ──────────────────────
// CRegimeFilter: ADX + ATR percentile + Bollinger Width regime detection
#include "../Signal/RegimeFilter.mqh"
// RegimeSignalSource: VETO mode blocks trades on VOLATILE regime
#include "../Signal/RegimeSignalSource.mqh"

// ─── L5d: SR + Pattern signal source plugins (Phase 3) ─────────────────
// SRSignalSource: zone proximity → directional vote with strength-weighted confidence
#include "../Signal/SRSignalSource.mqh"
// PatternSignalSource: PatternManager result → directional vote
#include "../Signal/PatternSignalSource.mqh"

// ─── L5e: Risk Manager (Phase 4) ─────────────────────────────────────
// Full ATR fixed-fractional lot sizing + 6-gate pre-trade circuit breaker
#include "../Trade/RiskManager.mqh"

// ─── L5f: Sanity Manager (Phase 5) ──────────────────────────────────
// Data validation: stale tick, wide spread, price gap detection
// Circuit Breaker: auto-pause trading on anomalous market conditions
#include "../Infra/SanityManager.mqh"

// ─── L5g: Telemetry Recorder (Phase 3 - Metrics Export) ───────────────
// Centralized logging of pipeline latency, execution slippage, signal metrics
// Exports to CSV for post-trade analysis
#include "../Infra/TelemetryRecorder.mqh"

// ─── L5h: Adaptive Parameter Manager (Phase 5 - Dynamic Params) ────────
// Dynamic SL/TP/Risk adjustment based on market regime (ATR/ADX)
#include "../Analysis/AdaptiveParameterManager.mqh"

// ─── L6: Trade — Execution, Recovery, Trade plan ──────────────────────
#include "../Trade/TradePlan.mqh"
#include "../Trade/ExecutionManager.mqh"
#include "../Trade/RecoveryManager.mqh"

// ─── L7: UI ────────────────────────────────────────────────────────────
#include "../UI/DashboardManager.mqh"

// ─── L8: Orchestrator — wires all managers into COrchestrator ────────────
// Include AFTER all managers so Orchestrator sees all type definitions.
#include "Orchestrator.mqh"

// ─── L9: QA / Tools (dev builds only — define PASR_QA_BUILD to enable) ───
#ifdef PASR_QA_BUILD
   #include "../QA/Audit.mqh"
   #include "../QA/Test.mqh"
   #include "../QA/LatencySimulator.mqh"  // Fase 4: Latency Simulation
   #include "../Infra/Optimizations/Optimizations.mqh"
   #include "../Infra/Optimizations/BatchProcessor.mqh"
   #include "../Infra/Optimizations/MemoryPool.mqh"
   #include "../Infra/Optimizations/Branchless.mqh"
#endif

#endif // __CORE_PASR_MASTER_MQH__
