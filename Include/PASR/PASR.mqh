//+------------------------------------------------------------------+
//|                                                       PASR.mqh   |
//|                                       Copyright 2026, Agsicentre |
//|            MASTER INCLUDE — PASR EA Framework                    |
//|                                                                   |
//| PURPOSE:                                                         |
//| Single entry point for the entire PASR framework.               |
//| Include ONLY this file in your EA. Load order is enforced here  |
//| so numeric filename prefixes (0., 1., 2. ...) are no longer     |
//| necessary for load-order management.                             |
//|                                                                   |
//| USAGE:                                                           |
//|   #include <PASR/PASR.mqh>                                       |
//|                                                                   |
//| LAYER ORDER (dependency graph — do not reorder):                |
//|   L0: Optimizations (PASR.Optimizations.mqh)                    |
//|   L1: Core/Config/Types.mqh  (plain structs, no dependencies)   |
//|   L2: Core/EventBus.mqh      (Event, IEventHandler, EventBus)   |
//|   L3: Core/Events.mqh        (concrete event classes)           |
//|   L4: Core/IManager.mqh      (base class for all managers)      |
//|   L5: 10.DataManager.mqh     (data layer)                       |
//|   L6: 2.Config.Manager.mqh   (config management)                |
//|   L7: Manager modules        (signal, execution, recovery, ...)  |
//|   L8: 11.DashboardManager.mqh (UI — depends on all above)       |
//|                                                                   |
//| MIGRATION STATUS:                                               |
//|   [x] L0  PASR.Optimizations.mqh                               |
//|   [x] L1  Core/Config/Types.mqh  (shim → 2.Config.Types.mqh)   |
//|   [x] L2  Core/EventBus.mqh                                     |
//|   [x] L3  Core/Events.mqh                                       |
//|   [x] L4  Core/IManager.mqh                                     |
//|   [ ] L5  10.DataManager.mqh     (pending migration)            |
//|   [ ] L6  Core/Config/Manager.mqh (shim → 2.Config.Manager.mqh) |
//|   [ ] L7  Manager modules         (pending migration)           |
//|   [ ] L8  11.DashboardManager.mqh (pending migration)           |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "1.00"
#property strict

#ifndef __PASR_MQH__
#define __PASR_MQH__

// === L0: Optimizations ============================================
#include "PASR.Optimizations.mqh"

// === L1: Config types (plain structs, zero dependencies) ==========
#include "Core/Config/Types.mqh"

// === L2: Event bus core ===========================================
#include "Core/EventBus.mqh"

// === L3: Concrete event classes ===================================
#include "Core/Events.mqh"

// === L4: Base manager class =======================================
#include "Core/IManager.mqh"

// === L5-L8: Remaining managers (numeric prefix — legacy) ==========
// These will be migrated to named subfolders in future iterations.
// Until then, include via their shim or original paths.
#include "10.DataManager.mqh"
#include "Core/Config/Manager.mqh"
#include "3.ZoneManager.mqh"
#include "4.MarketManager.mqh"
#include "5.SignalManager.mqh"
#include "6.ExecutionManager.mqh"
#include "7.AIManager.mqh"
#include "8.RecoveryManager.mqh"
#include "9.PositionManager.mqh"
#include "11.DashboardManager.mqh"

#endif // __PASR_MQH__
