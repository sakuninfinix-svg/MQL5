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
//|     L2   Infra      → DataManager                                |
//|     L3   Data       → MarketManager, ZoneManager stubs,          |
//|                        SRManager stub, MarketRegime              |
//|     L3.5 Analysis   → SRManager (full swing pivot), ZoneManager  |
//|                        (full S/D impulse-base)   [Phase 3]       |
//|     L4   Pattern    → PatternManager                             |
//|     L5a  Signal     → SignalManager v3.00 (weighted-vote + veto) |
//|     L5b  AI         → AIManager + AISignalSource                 |
//|     L5c  RegimeFilter → CRegimeFilter + RegimeSignalSource [P4]  |
//|     L5d  SRSignalSource + PatternSignalSource     [Phase 3]      |
//|     L5e  RiskManager (full ATR lot + circuit breaker) [Phase 4]  |
//|     L6   Trade      → TradePlan, ExecutionManager, RecoveryMgr   |
//|     L7   UI         → DashboardManager                           |
//|     L8   Orchestrator → COrchestrator (wires all managers)       |
//|     L9   QA / Tools  → (PASR_QA_BUILD define only)              |
//|                                                                  |
//|   CHANGE LOG:                                                    |
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
#include "../Globals.mqh"

// ─── L2: Infra — Production DataManager ──────────────────────────────
#include "../Infra/DataManager.mqh"

// ─── L3: Data — Forward stubs (backward-compat canonical named imports) ───
#include "../Data/MarketManager.mqh"
#include "../Data/ZoneManager.mqh"
#include "../Data/SRManager.mqh"
#include "../Data/MarketRegime.mqh"

// ─── L3.5: Analysis — Full implementations (Phase 3) ──────────────────
// CAnalysisSRManager: swing pivot fractal + zone clustering + strength scoring
#include "../Analysis/SRManager.mqh"
// CAnalysisZoneManager: Supply/Demand impulse-base zone detection
#include "../Analysis/ZoneManager.mqh"

// ─── L4: Analysis — Pattern recognition ──────────────────────────────
#include "../Analysis/Pattern/PatternManager.mqh"

// ─── L5a: Signal — Manager + ISignalSource interface ───────────────────
// ISignalSource.mqh is included by SignalManager.mqh internally
#include "../Signal/SignalManager.mqh"

// ─── L5b: AI — Neural net inference + AISignalSource plugin ──────────────
// AISignalSource bridges AIManager confidence score → ISignalSource interface
#include "../Signal/AI/AISignalSource.mqh"
#include "../AI/AIManager.mqh"

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
   #include "../Tools/Optimizations.mqh"
   #include "../Tools/BatchProcessor.mqh"
   #include "../Tools/MemoryPool.mqh"
   #include "../Tools/Branchless.mqh"
#endif

#endif // __CORE_PASR_MASTER_MQH__
