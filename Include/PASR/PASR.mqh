//+------------------------------------------------------------------+
//|                                                     PASR.mqh     |
//|                             Copyright 2026, Agsicentre           |
//|                       agsicentre.wordpress.com                   |
//|                                                                  |
//| PASR MASTER INCLUDE — single entry point for EA files            |
//|                                                                  |
//| Usage in Expert Advisor:                                         |
//|   #include <PASR/PASR.mqh>                                       |
//|                                                                  |
//| Include order guarantees correct dependency resolution.          |
//| Do NOT include individual PASR files directly in EA code;        |
//| always use this master include.                                  |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "2.05"
#property strict

#ifndef __PASR_MQH__
#define __PASR_MQH__

// ── Layer 0: Core ─────────────────────────────────────────────────
// Zero external PASR dependencies. Must be first.
#include "Core/EventBus.mqh"      // CEventBus, IEvent
#include "Core/Events.mqh"        // All event type definitions
#include "Core/ConfigTypes.mqh"   // StrategyConfig + sub-structs
#include "Core/IManager.mqh"      // IManager base class
#include "Core/Globals.mqh"       // Global singleton declarations

// ── Layer 2: Infra ────────────────────────────────────────────────
// Broker API wrappers. Depends on Core only.
#include "Infra/ConfigManager.mqh" // Config load, validate, hot-reload
#include "Infra/DataManager.mqh"   // ATR, rates, volume, spread

// ── Layer 3: Analysis ─────────────────────────────────────────────
// Market analysis. Depends on Core + Infra.
#include "Analysis/MarketManager.mqh"  // Session, spread, trading hours
#include "Analysis/ZoneManager.mqh"    // Supply/demand zones
#include "Analysis/SRManager.mqh"      // S/R levels
#include "Analysis/MarketRegime.mqh"   // Trend/range/chop classification

// ── Layer 3b: Pattern ─────────────────────────────────────────────
// Candlestick pattern analysis. Depends on Core + Infra.
#include "Pattern/PatternManager.mqh"  // Fakeout detection, pattern eval

// ── Layer 5a: AI ──────────────────────────────────────────────────
// Neural network inference. Depends on Core + Infra + Analysis.
#include "AI/AIManager.mqh"            // NN inference + training dispatch

// ── Layer 4: Signal ───────────────────────────────────────────────
// Signal generation. Depends on Core + Infra + Analysis + AI.
#include "Signal/SignalManager.mqh"    // Entry/exit signal generation

// ── Layer 6: Trade ────────────────────────────────────────────────
// Order execution + recovery. Depends on Core + Infra + Signal.
#include "Trade/ExecutionManager.mqh" // Order placement, sizing, retry
#include "Trade/RecoveryManager.mqh"  // Position recovery, trailing, partial

// ── Layer 7: UI ───────────────────────────────────────────────────
// Presentation only. Depends on Core events (read-only).
#include "UI/DashboardManager.mqh"     // On-chart status panel

#endif // __PASR_MQH__
