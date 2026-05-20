//+------------------------------------------------------------------+
//|                                                        PASR.mqh  |
//|                                       Copyright 2026, Agsicentre |
//|            PASR EA — Master Include File v4.00                  |
//|                   Refactored Folder Structure                   |
//+------------------------------------------------------------------+
//| PURPOSE                                                          |
//| Replaces the numeric-prefix file-ordering convention.            |
//| Include this single file in your EA .mq5 entry point.           |
//| Correct dependency order is enforced here — developers no        |
//| longer need to know or maintain the right include sequence.      |
//|                                                                  |
//| BEFORE (fragile):                                                |
//|   #include <PASR/0.EventBus.mqh>                                 |
//|   #include <PASR/1.Events.mqh>                                   |
//|   #include <PASR/2.Config.Types.mqh>                             |
//|   ... (14 files, order must be manually maintained)              |
//|                                                                  |
//| AFTER (safe):                                                    |
//|   #include <PASR/Core/PASR.mqh>   // one line, always correct    |
//|                                                                  |
//| DEPENDENCY LAYERS                                                |
//|   Layer 0: Core infrastructure (no deps)                         |
//|   Layer 1: Base classes                                          |
//|   Layer 2: Data & Market                                         |
//|   Layer 3: Analysis                                              |
//|   Layer 4: Signal & AI                                           |
//|   Layer 5: Execution & Recovery                                  |
//|   Layer 6: UI (lowest priority)                                  |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "4.00"
#property strict

#ifndef __PASR_MQH__
#define __PASR_MQH__

// ── Layer 0: Core infrastructure (no dependencies) ────────────────
#include "0.EventBus.mqh"
#include "1.Events.mqh"
#include "2.Config.Types.mqh"
#include "Globals.mqh"

// ── Layer 1: Base classes ─────────────────────────────────────────
#include "IManager.mqh"
#include "2.Config.Manager.mqh"

// ── Layer 2: Data & Market ────────────────────────────────────────
#include "../Data/3.MarketManager.mqh"
#include "../Data/3.ZoneManager.mqh"
#include "../Infrastructure/10.DataManager.mqh"
#include "../Infrastructure/12.MarketRegime.mqh"

// ── Layer 3: Analysis ─────────────────────────────────────────────
#include "../Data/4.SRManager.mqh"
#include "../Infrastructure/9.PatternManager.mqh"

// ── Layer 4: Signal & AI ──────────────────────────────────────────
#include "../Strategy/5.SignalManager.mqh"
#include "../Strategy/AI/7.AIManager.mqh"

// ── Layer 5: Execution & Recovery ────────────────────────────────
#include "../Strategy/6.ExecutionManager.mqh"
#include "../Infrastructure/8.RecoveryManager.mqh"

// ── Layer 6: UI (no business logic deps required) ─────────────────
#include "../Infrastructure/11.DashboardManager.mqh"

#endif // __PASR_MQH__
