//+------------------------------------------------------------------+
//|                                               Core/PASR.mqh     |
//|                          Copyright 2026, Agsicentre             |
//|   PASR Framework — Master Include                                |
//|   Usage: #include "../PASR/Core/PASR.mqh"                        |
//|          (or use root PASR.mqh which forwards here)             |
//|                                                                  |
//|   LOAD ORDER GUARANTEE:                                          |
//|     L1  Core  → IManager, EventBus, Events, Config              |
//|     L2  Infra → DataManager, MarketManager, ZoneManager         |
//|     L3  Analysis → SRManager, MarketRegime, PatternManager      |
//|     L4  Signal → SignalManager (+ AI/ sublayer)                 |
//|     L5  Trade  → TradePlan, ExecutionManager, RecoveryManager   |
//|     L6  UI     → DashboardManager                               |
//|     L7  QA     → Audit, Test, Optimizations (PASR_QA_BUILD only)|
//|                                                                  |
//|   Replaces: numeric prefix include order (0.mqh, 1.mqh, ...)    |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property strict

#ifndef __CORE_PASR_MASTER_MQH__
#define __CORE_PASR_MASTER_MQH__

// ─── L1: Core ────────────────────────────────────────────────────────────────
#include "../IManager.mqh"
#include "../0.EventBus.mqh"
#include "../1.Events.mqh"
#include "../2.Config.Types.mqh"
#include "../2.Config.Manager.mqh"
#include "../Globals.mqh"

// ─── L2: Infra ───────────────────────────────────────────────────────────────
#include "../Infra/DataManager.mqh"
#include "../3.MarketManager.mqh"
#include "../3.ZoneManager.mqh"

// ─── L3: Analysis ────────────────────────────────────────────────────────────
#include "../4.SRManager.mqh"
#include "../12.MarketRegime.mqh"
#include "../9.PatternManager.mqh"

// ─── L4: Signal ──────────────────────────────────────────────────────────────
#include "../5.SignalManager.mqh"
#include "../7.AIManager.mqh"

// ─── L5: Trade ───────────────────────────────────────────────────────────────
#include "../Trade/TradePlan.mqh"
#include "../Trade/ExecutionManager.mqh"
#include "../8.RecoveryManager.mqh"

// ─── L6: UI ──────────────────────────────────────────────────────────────────
#include "../11.DashboardManager.mqh"

// ─── L7: QA (dev builds only) ────────────────────────────────────────────────
#ifdef PASR_QA_BUILD
   #include "../PASR.Audit.mqh"
   #include "../PASR.Test.mqh"
   #include "../PASR.Optimizations.mqh"
   #include "../PASR.BatchProcessor.mqh"
   #include "../PASR.MemoryPool.mqh"
   #include "../PASR.Branchless.mqh"
#endif

#endif // __CORE_PASR_MASTER_MQH__
