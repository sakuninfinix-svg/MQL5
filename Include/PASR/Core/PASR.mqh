//+------------------------------------------------------------------+
//|                                               Core/PASR.mqh      |
//|                          Copyright 2026, Agsicentre             |
//|   PASR Framework — Master Include                                |
//|                                                                  |
//|   USAGE (from your EA):                                          |
//|     #include <PASR/Core/PASR.mqh>                               |
//|                                                                  |
//|   LOAD ORDER GUARANTEE:                                          |
//|     L1  Core     → IManager, EventBus, Events, Config           |
//|     L2  Infra    → DataManager (production, account-safe GVs)   |
//|     L3  Data     → MarketManager, ZoneManager, SRManager,       |
//|                    MarketRegime (forward to Infra/ production)   |
//|     L4  Analysis → PatternManager                               |
//|     L5  Signal   → SignalManager, AIManager                     |
//|     L6  Trade    → TradePlan, ExecutionManager, RecoveryManager |
//|     L7  UI       → DashboardManager                             |
//|     L8  QA       → Audit/Test/Opt (PASR_QA_BUILD define only)   |
//|                                                                  |
//|   Replaces: numeric prefix include order (0.mqh … 12.mqh)       |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property strict

#ifndef __CORE_PASR_MASTER_MQH__
#define __CORE_PASR_MASTER_MQH__

// ─── L1: Core Foundation ─────────────────────────────────────────────────────
// These files live in PASR/Core/ — fully migrated
#include "IManager.mqh"
#include "EventBus.mqh"
#include "Events.mqh"

// Config is in Core/Config/ subfolder
#ifdef __MQL5__
   // MQL5 include is relative to MQL5/Include
   #include <PASR/Core/Config/Types.mqh>
   #include <PASR/Core/Config/Manager.mqh>
#else
   #include "Config/Types.mqh"
   #include "Config/Manager.mqh"
#endif

// Globals (extern consolidation — lives at PASR root, accessible by all layers)
#include "../Globals.mqh"

// ─── L2: Infra — Production implementations ──────────────────────────────────
// DataManager: account-safe GV keys, optimized scavenge, dashboard throttle
#include "../Infra/DataManager.mqh"

// ─── L3: Data — Forward stubs (→ Infra production files) ────────────────────
// These stubs exist for backward-compat and as canonical named imports.
// They all forward to the real implementation in Infra/ or root legacy files.
#include "../Data/MarketManager.mqh"
#include "../Data/ZoneManager.mqh"
#include "../Data/SRManager.mqh"
#include "../Data/MarketRegime.mqh"

// ─── L4: Analysis ────────────────────────────────────────────────────────────
#include "../9.PatternManager.mqh"

// ─── L5: Signal ──────────────────────────────────────────────────────────────
#include "../5.SignalManager.mqh"
#include "../7.AIManager.mqh"

// ─── L6: Trade ───────────────────────────────────────────────────────────────
#include "../Trade/TradePlan.mqh"
#include "../Trade/ExecutionManager.mqh"
#include "../Trade/RecoveryManager.mqh"

// ─── L7: UI ──────────────────────────────────────────────────────────────────
#include "../11.DashboardManager.mqh"

// ─── L8: QA (dev builds only — define PASR_QA_BUILD to enable) ───────────────
#ifdef PASR_QA_BUILD
   #include "../PASR.Audit.mqh"
   #include "../PASR.Test.mqh"
   #include "../PASR.Optimizations.mqh"
   #include "../PASR.BatchProcessor.mqh"
   #include "../PASR.MemoryPool.mqh"
   #include "../PASR.Branchless.mqh"
#endif

#endif // __CORE_PASR_MASTER_MQH__
