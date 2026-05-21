//+------------------------------------------------------------------+
//|                                               Core/PASR.mqh      |
//|                          Copyright 2026, Agsicentre             |
//|   PASR Framework — Master Include                                |
//|                                                                  |
//|   USAGE (from your EA):                                          |
//|     #include <PASR/Core/PASR.mqh>                               |
//|                                                                  |
//|   LOAD ORDER GUARANTEE:                                          |
//|     L0  Config   → Types, Validator, Manager (MUST be first)    |
//|     L1  Core     → IManager, EventBus, Events                   |
//|     L2  Infra    → DataManager (production, account-safe GVs)   |
//|     L3  Data     → MarketManager, ZoneManager, SRManager,       |
//|                    MarketRegime (forward to Infra/ production)   |
//|     L4  Analysis → PatternManager (canonical subfolder path)    |
//|     L5a Signal   → SignalManager (canonical subfolder path)     |
//|     L5b AI       → AIManager + AISignalSource plugin            |
//|     L6  Trade    → TradePlan, ExecutionManager, RecoveryManager |
//|     L7  UI       → DashboardManager (canonical subfolder path)  |
//|     L8  Orchestrator → COrchestrator (wires all managers)       |
//|     L9  QA       → QA/* + Tools/* (PASR_QA_BUILD define only)   |
//|                                                                  |
//|   CHANGE LOG:                                                    |
//|   v2.16 (2026-05-21) — FIX #6:                                  |
//|     L4 path ../9.PatternManager.mqh  → ../Pattern/PatternManager.mqh |
//|     L5 path ../5.SignalManager.mqh   → ../Signal/SignalManager.mqh   |
//|     L7 path ../11.DashboardManager.mqh → ../UI/DashboardManager.mqh  |
//|     L5b ADD ../Signal/AI/AISignalSource.mqh (FIX #7)            |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property strict

#ifndef __CORE_PASR_MASTER_MQH__
#define __CORE_PASR_MASTER_MQH__

// ─── L0: Config Triad — MUST load before anything else ─────────────────────
// Rule: No other PASR header may include Config/* directly.
// All config access flows through CConfigManager → EventBus → m_cfg in IManager.
#include "Config/Types.mqh"      // StrategyConfig + 5 domain sub-structs
#include "Config/Validator.mqh"  // 33-rule validator (zero dependencies)
#include "Config/Manager.mqh"    // CConfigManager: Init/Reload with Validate() gate

// ─── L1: Core Foundation ─────────────────────────────────────────────────
#include "IManager.mqh"
#include "EventBus.mqh"
#include "Events.mqh"

// ─── L1.5: Globals (extern consolidation — one declaration point) ─────────
// WARNING: Globals.mqh uses extern declarations.
// It MUST be included EXACTLY ONCE per compilation unit.
// Do NOT include Globals.mqh from any other header.
#include "../Globals.mqh"

// ─── L2: Infra — Production implementations ───────────────────────────────
// DataManager: account-safe GV keys, optimized scavenge, dashboard throttle
#include "../Infra/DataManager.mqh"

// ─── L3: Data — Forward stubs (→ Infra production files) ─────────────────
// These stubs exist for backward-compat and as canonical named imports.
#include "../Data/MarketManager.mqh"
#include "../Data/ZoneManager.mqh"
#include "../Data/SRManager.mqh"
#include "../Data/MarketRegime.mqh"

// ─── L4: Analysis ─────────────────────────────────────────────────────────
// FIX #6: was ../9.PatternManager.mqh (root-level numbered file)
#include "../Pattern/PatternManager.mqh"

// ─── L5: Signal ───────────────────────────────────────────────────────────
// FIX #6: was ../5.SignalManager.mqh (root-level numbered file)
#include "../Signal/SignalManager.mqh"
// FIX #7: AISignalSource plugin — bridges AIManager score → ISignalSource interface
#include "../Signal/AI/AISignalSource.mqh"
#include "../AI/AIManager.mqh"

// ─── L6: Trade ────────────────────────────────────────────────────────────
#include "../Trade/TradePlan.mqh"
#include "../Trade/ExecutionManager.mqh"
#include "../Trade/RecoveryManager.mqh"

// ─── L7: UI ───────────────────────────────────────────────────────────────
// FIX #6: was ../11.DashboardManager.mqh (root-level numbered file)
#include "../UI/DashboardManager.mqh"

// ─── L8: Orchestrator — wires all managers into COrchestrator ─────────────
// Include after all managers so Orchestrator can forward-declare them.
#include "Orchestrator.mqh"

// ─── L9: QA / Tools (dev builds only — define PASR_QA_BUILD to enable) ──────
// Phase 4: all QA and Tools files relocated from root to subfolders.
#ifdef PASR_QA_BUILD
   #include "../QA/Audit.mqh"
   #include "../QA/Test.mqh"
   #include "../Tools/Optimizations.mqh"
   #include "../Tools/BatchProcessor.mqh"
   #include "../Tools/MemoryPool.mqh"
   #include "../Tools/Branchless.mqh"
#endif

#endif // __CORE_PASR_MASTER_MQH__
