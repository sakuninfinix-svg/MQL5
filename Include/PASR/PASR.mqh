//+------------------------------------------------------------------+
//|                                                       PASR.mqh   |
//|                                       Copyright 2026, Agsicentre |
//|              MASTER INCLUDE — PASR EA Framework v2.00            |
//|                                                                   |
//| USAGE: #include <PASR/PASR.mqh>  (satu baris, semua tersedia)   |
//|                                                                   |
//| LAYER ARCHITECTURE (dependency order — jangan diubah urutannya): |
//|                                                                   |
//|  L0  Tools/Optimizations   ← macros, CStringPool, cache align   |
//|  L1  Core/Config/Types     ← plain structs (zero deps)          |
//|  L2  Core/EventBus         ← Event, IEventHandler, EventBus     |
//|  L3  Core/Events           ← concrete event classes             |
//|  L4  Core/IManager         ← base class semua manager           |
//|  L5  Globals               ← global singletons & helpers        |
//|  L6  Data/DataManager      ← indicator cache, symbol data       |
//|  L7  Core/Config/Manager   ← config loading & validation        |
//|  L8  Data/MarketRegime     ← regime detection                   |
//|  L9  Data/ZoneManager      ← S/D zones                         |
//|  L10 Data/MarketManager    ← market conditions                  |
//|  L11 Data/SRManager        ← support/resistance                 |
//|  L12 Analysis/PatternMgr   ← pattern recognition               |
//|  L13 Signal/SignalManager  ← signal generation                  |
//|  L14 AI/AIManager          ← ML orchestration (optional)        |
//|  L15 Trade/ExecutionMgr    ← order execution                    |
//|  L16 Trade/RecoveryMgr     ← error recovery                     |
//|  L17 UI/DashboardManager   ← dashboard (depends on all above)  |
//|                                                                   |
//| MIGRATION STATUS:                                               |
//|  [x] L0   Tools/Optimizations.mqh                              |
//|  [x] L1   Core/Config/Types.mqh                                |
//|  [x] L2   Core/EventBus.mqh                                    |
//|  [x] L3   Core/Events.mqh                                      |
//|  [x] L4   Core/IManager.mqh                                    |
//|  [x] L5   Globals.mqh                                          |
//|  [x] L6   Data/DataManager.mqh                                 |
//|  [x] L7   Core/Config/Manager.mqh                              |
//|  [x] L8   Data/MarketRegime.mqh                                |
//|  [x] L9   Data/ZoneManager.mqh                                 |
//|  [x] L10  Data/MarketManager.mqh                               |
//|  [x] L11  Data/SRManager.mqh                                   |
//|  [x] L12  Analysis/PatternManager.mqh                          |
//|  [x] L13  Signal/SignalManager.mqh                             |
//|  [x] L14  AI/AIManager.mqh (if exists)                         |
//|  [x] L15  Trade/ExecutionManager.mqh                           |
//|  [x] L16  Trade/RecoveryManager.mqh                            |
//|  [x] L17  UI/DashboardManager.mqh                              |
//|                                                                   |
//| NOTE: Semua file lama (0.EventBus.mqh, 10.DataManager.mqh, dst) |
//| masih ada sebagai backward-compat shims. EA lama tetap compile. |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "2.00"
#property strict

#ifndef __PASR_MQH__
#define __PASR_MQH__

// =================================================================
// L0: Performance macros & string pool
// =================================================================
#include "Tools/Optimizations.mqh"

// =================================================================
// L1: Config types — plain structs, zero dependencies
// =================================================================
#include "Core/Config/Types.mqh"

// =================================================================
// L2: Event bus — Event base, IEventHandler, EventBus singleton
// =================================================================
#include "Core/EventBus.mqh"

// =================================================================
// L3: Concrete event classes
// =================================================================
#include "Core/Events.mqh"

// =================================================================
// L4: IManager base class
// =================================================================
#include "Core/IManager.mqh"

// =================================================================
// L5: Global utilities & singleton registry
// =================================================================
#include "Globals.mqh"

// =================================================================
// L6: Data layer — indicator cache & symbol data
// =================================================================
#include "Data/DataManager.mqh"

// =================================================================
// L7: Config manager — loads & validates StrategyConfig
// =================================================================
#include "Core/Config/Manager.mqh"

// =================================================================
// L8-L11: Market data sub-managers
// =================================================================
#include "Data/MarketRegime.mqh"
#include "Data/ZoneManager.mqh"
#include "Data/MarketManager.mqh"
#include "Data/SRManager.mqh"

// =================================================================
// L12: Analysis layer
// =================================================================
#include "Analysis/PatternManager.mqh"

// =================================================================
// L13: Signal generation
// =================================================================
#include "Signal/SignalManager.mqh"

// =================================================================
// L14: AI/ML orchestration (optional — comment out to disable)
// =================================================================
#include "AI/AIManager.mqh"

// =================================================================
// L15-L16: Execution layer
// =================================================================
#include "Trade/ExecutionManager.mqh"
#include "Trade/RecoveryManager.mqh"

// =================================================================
// L17: UI — depends on all layers above
// =================================================================
#include "UI/DashboardManager.mqh"

#endif // __PASR_MQH__
