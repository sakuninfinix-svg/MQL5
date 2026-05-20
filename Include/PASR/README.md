# PASR EA Framework

> **Price Action Support & Resistance** — production-grade MQL5 EA framework  
> with event-driven architecture, AI inference layer, and account-safe state management.

[![Version](https://img.shields.io/badge/version-v2.12-blue)](#changelog)
[![Status](https://img.shields.io/badge/migration-✅%2013%2F14%20canonical-green)](#migration-status)
[![MQL5](https://img.shields.io/badge/platform-MetaTrader%205-orange)](#requirements)

---

## Quick Start

```cpp
// In your EA .mq5 file — single include, all modules loaded:
#include <PASR/Core/PASR.mqh>

// Instantiate the orchestrator
CPASREngine engine;

int OnInit()   { return engine.Init() ? INIT_SUCCEEDED : INIT_FAILED; }
void OnDeinit(const int reason) { engine.Deinit(); }
void OnTick()  { engine.OnTick(); }
void OnTimer() { engine.OnTimer(); }  // required for deferred AI training
```

> **Legacy path still works:** `#include <PASR/PASR.mqh>` forwards to `Core/PASR.mqh`.

---

## Architecture

```
Include/PASR/
├── Core/                   ← Foundation layer (always include first)
│   ├── PASR.mqh            ← TRUE master include (EA entry point)
│   ├── EventBus.mqh        ← Priority queue event bus + ENUM_EVENT_ID
│   ├── Events.mqh          ← All event type definitions
│   ├── IManager.mqh        ← Base class: m_cfg cache, BuildGVPrefix, bus wiring
│   ├── Globals.mqh         ← Singleton extern declarations (ONE definition)
│   └── Config/
│       ├── Types.mqh       ← StrategyConfig struct (100+ validated fields)
│       └── Manager.mqh     ← Config load/save/reload + ConfigReloadEvent
│
├── Infra/
│   └── DataManager.mqh     ← Account-safe GV, OHLCV cache, tick buffer
│
├── Data/                   ← Named canonical modules
│   ├── MarketManager.mqh   ← Session, spread, tick quality detection
│   ├── ZoneManager.mqh     ← Supply/demand zone detection
│   ├── SRManager.mqh       ← Multi-timeframe S/R level tracking
│   └── MarketRegime.mqh    ← Trend/range/volatile regime classifier
│
├── Pattern/
│   └── PatternManager.mqh  ← Candlestick + price action pattern scanner
│
├── Signal/
│   └── SignalManager.mqh   ← Pluggable ISignalSource aggregator (OnNewBar only)
│
├── Trade/
│   ├── ExecutionManager.mqh ← O(1) GV key cache, account-isolated prefix
│   └── RecoveryManager.mqh  ← Drawdown recovery logic + state machine
│
├── AI/
│   └── AIManager.mqh       ← CAIInference (tick-safe) + CAITrainer (timer-only)
│
├── UI/
│   └── DashboardManager.mqh ← 1Hz throttled chart objects, account-namespaced
│
├── Tools/                  ← Utility helpers
├── QA/                     ← PASR.Test.mqh unit test runner
├── docs/                   ← Architecture deep-dives and ADRs
│
└── [N.Xxx.mqh legacy shims] ← Thin #include forwarders, DO NOT edit
```

### Event Flow

```
OnTick()
  └─ engine.OnTick()
        ├─ DataManager.OnPriceUpdate()       ← tick buffer, spread check
        ├─ DashboardManager.OnPriceUpdate()  ← throttled 1Hz render
        └─ [if new bar detected]
              ├─ MarketManager.OnNewBar()
              ├─ MarketRegime.OnNewBar()
              ├─ ZoneManager.OnNewBar()
              ├─ SRManager.OnNewBar()
              ├─ PatternManager.OnNewBar()
              ├─ SignalManager.OnNewBar()     ← aggregates ISignalSource plugins
              ├─ AIOrchestrator.OnNewBar()    ← inference only, no backprop
              └─ ExecutionManager.OnNewBar()

OnTimer()
  └─ AIOrchestrator.OnTimer()               ← deferred minibatch training

OnTradeTransaction()
  └─ ExecutionManager.OnTradeOpen/Close()   ← O(1) GV cache update
```

---

## Key Design Decisions

### Account-Isolated GlobalVariables

All `GlobalVariableSet/Get` calls use an account-prefixed key:
```
PASR_{AccountLogin}_{MagicNumber}_T{Ticket}_SL
PASR_{AccountLogin}_{MagicNumber}_T{Ticket}_TP
```
This prevents state corruption when running live + demo instances with the same magic number on the same terminal.

### Event-Driven, Not Poll-Driven

Modules do **not** scan on every tick. `OnPriceUpdate()` is reserved for lightweight tick-safe operations only (e.g. spread monitoring, dashboard throttle). All analysis runs on `OnNewBar()` via the EventBus.

### AI Thread Safety

`CAIInference::Predict()` is tick-safe (no allocation, read-only weights).  
`CAITrainer::TrainStep()` is called from `OnTimer()` **only** — never from `OnTick()`.  
Backprop never blocks the price feed.

### Config Caching

`IManager` caches a `StrategyConfig m_cfg` copy refreshed only on `ConfigReloadEvent`.  
This eliminates ~400 struct copies/second that occurred when each function called `GetConfigCache()` independently.

---

## Migration Status

| Module | Canonical Path | Status | Since |
|---|---|---|---|
| EventBus | `Core/EventBus.mqh` | ✅ CANONICAL | v2.05 |
| Events | `Core/Events.mqh` | ✅ CANONICAL | v2.05 |
| IManager | `Core/IManager.mqh` | ✅ CANONICAL | v2.05 |
| Config Types | `Core/Config/Types.mqh` | ✅ CANONICAL | v2.05 |
| Config Manager | `Core/Config/Manager.mqh` | ✅ CANONICAL | v2.05 |
| DataManager | `Infra/DataManager.mqh` | ✅ CANONICAL | v2.05 |
| MarketManager | `Data/MarketManager.mqh` | ✅ CANONICAL | v2.05 |
| ZoneManager | `Data/ZoneManager.mqh` | ✅ CANONICAL | v2.05 |
| SRManager | `Data/SRManager.mqh` | ✅ CANONICAL | v2.05 |
| MarketRegime | `Data/MarketRegime.mqh` | ✅ CANONICAL | v2.05 |
| PatternManager | `Pattern/PatternManager.mqh` | ✅ CANONICAL | v2.04 |
| RecoveryManager | `Trade/RecoveryManager.mqh` | ✅ CANONICAL | v2.05 |
| ExecutionManager | `Trade/ExecutionManager.mqh` | ✅ CANONICAL | **v2.12** |
| SignalManager | `Signal/SignalManager.mqh` | ✅ CANONICAL | **v2.12** |
| DashboardManager | `UI/DashboardManager.mqh` | ✅ CANONICAL | **v2.12** |
| AIManager | `AI/AIManager.mqh` | 🔶 SCAFFOLD | **v2.12** |

**13/14 modules fully canonical.** Only AI needs real weight loading + backprop implementation.

---

## Requirements

- MetaTrader 5 build **3600+**
- MQL5 compiler with `#pragma once` support
- No external DLL dependencies
- `OnTimer()` must be enabled in EA (`EventSetTimer(1)`) for AI training

---

## Running Tests

```cpp
#include <PASR/PASR.Test.mqh>
// Attach PASR.Test.mq5 script to any chart
// Results printed to Experts log
```

See `QA/` folder and `PASR.Test.mqh` for unit test coverage.

---

## Changelog

| Version | Date | Changes |
|---|---|---|
| **v2.12** | 2026-05-20 | ExecutionManager, SignalManager, DashboardManager → CANONICAL; AI scaffold with deferred training |
| v2.11 | 2026-05-20 | EventBus enum, IManager m_cfg cache, GV account prefix, dashboard 1Hz throttle |
| v2.10 | 2026-05-19 | RecoveryManager crash fix (cfg scope bug), ZeroMemory init |
| v2.05 | 2026-05-18 | Major canonical migration: Core, Infra, Data, Pattern, Trade/Recovery |
| v2.04 | 2026-05-17 | Pattern folder canonical, PatternManager decomposition |
| v2.00 | 2026-05-15 | EventBus priority queue, IManager base class, Config split |

---

## Contributing

1. **Never edit** `N.Xxx.mqh` numbered files — they are read-only shims
2. All new code goes into the canonical folder structure
3. Follow the `IManager` interface contract: `Init()`, `OnNewBar()`, `OnPriceUpdate()`, `IsHealthy()`
4. AI training logic must only run from `OnTimer()` — never from `OnTick()`
5. All GlobalVariable keys must use `BuildGVPrefix()` from `Core/IManager.mqh`
