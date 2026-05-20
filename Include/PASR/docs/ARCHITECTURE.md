# PASR Framework — Architecture Reference

> **Version**: 3.0 (Layered Architecture)
> **Date**: 2026-05-20
> **Author**: Agsicentre

---

## Overview

PASR (Price Action Support/Resistance) is an MQL5 Expert Advisor framework built on a strict 7-layer clean architecture. Each layer has a clear responsibility boundary and may only depend on layers below it.

---

## Layer Map

```
┌─────────────────────────────────────────────────────────┐
│  LAYER 0 — ENTRY POINT                                  │
│  PASR.mqh (master include)  │  Globals.mqh              │
├─────────────────────────────────────────────────────────┤
│  LAYER 1 — CORE / FOUNDATION                            │
│  Core/IManager.mqh          │  Core/EventBus.mqh        │
│  Core/Events.mqh            │  Core/Config/Types.mqh    │
│                             │  Core/Config/Manager.mqh  │
├─────────────────────────────────────────────────────────┤
│  LAYER 2 — INFRASTRUCTURE                               │
│  Infra/DataManager.mqh      │  Infra/MarketManager.mqh  │
│  Infra/ZoneManager.mqh                                  │
├─────────────────────────────────────────────────────────┤
│  LAYER 3 — ANALYSIS                                     │
│  Analysis/SRManager.mqh     │  Analysis/MarketRegime.mqh│
│  Analysis/Pattern/PatternManager.mqh  (+ Evaluators,   │
│                              ScoreEngine)               │
├─────────────────────────────────────────────────────────┤
│  LAYER 4 — SIGNAL / INTELLIGENCE                        │
│  Signal/SignalManager.mqh   │  Signal/AI/AIOrchestrator │
│  Signal/AI/AIInference.mqh  │  Signal/AI/AITrainer.mqh  │
├─────────────────────────────────────────────────────────┤
│  LAYER 5 — TRADE / EXECUTION                            │
│  Trade/ExecutionManager.mqh │  Trade/RecoveryManager.mqh│
├─────────────────────────────────────────────────────────┤
│  LAYER 6 — UI / PRESENTATION (read-only)                │
│  UI/DashboardManager.mqh                                │
├─────────────────────────────────────────────────────────┤
│  LAYER 7 — QA / DEVTOOLS (never in production)          │
│  QA/Audit.mqh  │  QA/Test.mqh  │  QA/Optimizations.mqh │
└─────────────────────────────────────────────────────────┘
```

---

## Dependency Rules (Enforcement)

| Layer | MAY include | MUST NOT include |
|-------|-------------|------------------|
| Core | Core/ only | anything else |
| Infra | Core/ | Analysis+, Signal+, Trade+, UI |
| Analysis | Core/, Infra/ | Signal+, Trade+, UI |
| Signal | Core/, Infra/, Analysis/ | Trade+, UI |
| Trade | Core/, Infra/ | Signal/, UI |
| UI | Core/, Infra/ (read) | Trade/, Signal/ (direct include) |
| QA | ALL | (never included by prod) |

---

## Migration Progress

Old numbered files at root (`0.EventBus.mqh` → `12.MarketRegime.mqh`) remain
during transition. Each is migrated to its new layer path, tested, then
the old file becomes a 1-line shim:

```cpp
// DEPRECATED — use Core/EventBus.mqh
#include "Core/EventBus.mqh"
```

### Status Table

| Old File | New Path | Status |
|----------|----------|--------|
| IManager.mqh | Core/IManager.mqh | ⏳ Pending |
| 0.EventBus.mqh | Core/EventBus.mqh | ⏳ Pending |
| 1.Events.mqh | Core/Events.mqh | ⏳ Pending |
| 2.Config.Types.mqh | Core/Config/Types.mqh | ⏳ Pending |
| 2.Config.Manager.mqh | Core/Config/Manager.mqh | ⏳ Pending |
| 3.MarketManager.mqh | Infra/MarketManager.mqh | ⏳ Pending |
| 3.ZoneManager.mqh | Infra/ZoneManager.mqh | ⏳ Pending |
| 10.DataManager.mqh | Infra/DataManager.mqh | ⏳ Pending |
| 4.SRManager.mqh | Analysis/SRManager.mqh | ⏳ Pending |
| 12.MarketRegime.mqh | Analysis/MarketRegime.mqh | ⏳ Pending |
| 9.PatternManager.mqh | Analysis/Pattern/ | ✅ Done |
| 5.SignalManager.mqh | Signal/SignalManager.mqh | ⏳ Pending |
| 7.AIManager.mqh | Signal/AI/ (3 files) | ⏳ Pending |
| 6.ExecutionManager.mqh | Trade/ExecutionManager.mqh | ⏳ Pending |
| 8.RecoveryManager.mqh | Trade/RecoveryManager.mqh | ⏳ Pending |
| 11.DashboardManager.mqh | UI/DashboardManager.mqh | ✅ Done |
| PASR.Audit.mqh | QA/Audit.mqh | ⏳ Pending |
| PASR.Test.mqh | QA/Test.mqh | ⏳ Pending |
| PASR.Optimizations.mqh | QA/Optimizations.mqh | ⏳ Pending |

---

## Key Design Decisions

### 1. Config Injection (not pull)
DataManager does NOT include ConfigManager. Config is injected:
```cpp
dataManager.InitConfigCache(cfg); // called by EA OnInit
```

### 2. GlobalVariable Key Safety
All GV keys prefixed with account login:
```cpp
string key = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))
           + "_PASR_" + symbol + "_" + (string)magic;
```

### 3. AI Thread Safety
AIInference runs on tick thread (O(layers), zero alloc).
AITrainer runs on deferred NewBar event only.
Backpropagation never blocks OnTick().

### 4. Dashboard Throttle
Dashboard renders at maximum 1 Hz:
```cpp
if(GetMicrosecondCount() - m_lastRenderUs < 1000000UL) return;
```

---

## Event Flow

```
OnTick()
  └─► EventBus.Dispatch(PriceUpdateEvent)
        ├─► DataManager.OnPriceUpdate()   [cache check only]
        ├─► MarketRegime.OnPriceUpdate()  [regime read only]
        ├─► SignalManager.OnPriceUpdate() [AI inference only]
        └─► DashboardManager.OnPriceUpdate() [throttled 1Hz]

OnNewBar()
  └─► EventBus.Dispatch(NewBarEvent)
        ├─► DataManager.OnNewBar()        [update indicators]
        ├─► SRManager.OnNewBar()          [recalc S/R levels]
        ├─► PatternManager.OnNewBar()     [scan patterns]
        ├─► MarketRegime.OnNewBar()       [full regime update]
        ├─► SignalManager.OnNewBar()      [generate signal]
        ├─► AITrainer.OnNewBar()          [deferred backprop]
        └─► ExecutionManager.OnNewBar()   [trail/BE/partial]
```
