# Core Module (`PASR/Core/`)

15 files — Foundation layer: EventBus, Config, IManager base, types, utilities.

## Arsitektur

```
Core/
  ├── Config/
  │   ├── Types.mqh          — StrategyConfig & sub-configs (Risk, Market, AI, Pattern, Signal, Display)
  │   ├── Validator.mqh       — 35 business rules validator
  │   └── Manager.mqh         — Config lifecycle: init, reload, validate, snapshot
  ├── Globals.mqh             — GV helpers, logging, price validation, perf timer
  ├── Events.mqh              — ENUM_EVENT_ID (70+ events), PASREvent struct
  ├── EventPool.mqh           — Zero-allocation PASREvent object pool (max 1024)
  ├── EventBus.mqh            — Priority event dispatch (binary heap, 32 subscribers, 256 depth)
  ├── IManager.mqh            — Base class for all managers
  ├── HighFreqTimer.mqh       — Polling-based microsecond timer
  ├── LatencyOptimizer.mqh    — Order buffering, latency tracking
  ├── PASR_SymbolManager.mqh  — Multi-symbol manager (100 symbols, correlation)
  ├── PipelineTypes.mqh       — Pipeline context, SSignal, SExecResult, SRiskResult, StageMetrics
  ├── StateOwnershipMap.mqh   — State ownership contracts (documentation)
  ├── AsyncOrderManager.mqh   — Non-blocking order execution
  └── PASR.mqh                — Master include (umbrella)
```

## File Reference

| # | File | Class | Fungsi |
|---|------|-------|--------|
| 1 | `Config/Types.mqh` | — | `StrategyConfig` root + `RiskConfig`, `MarketConfig`, `AIConfig` (60 fields), `PatternConfig`, `SignalTuningConfig`, `DisplayConfig` |
| 2 | `Config/Validator.mqh` | `CConfigValidator` | Validate identity, risk, market, AI, pattern, display, cross-field rules |
| 3 | `Config/Manager.mqh` | `CConfigManager` | Init/reload with validation, snapshot, event broadcast |
| 4 | `Globals.mqh` | `CPerfTimer` | GV scoped keys, 4-level logging, price/volume validation, tick freshness, spread check |
| 5 | `Events.mqh` | — | `ENUM_EVENT_ID`: NEW_BAR, PRICE_UPDATE, TRADE_OPEN/CLOSE, ORDER_REQUEST, SIGNAL_GENERATED, AI_INFERENCE, RISK_CHECK, CONFIG_RELOAD, SYSTEM_HALT/ERROR, SESSION_CHANGE, REGIME_CHANGE, etc. |
| 6 | `EventPool.mqh` | `CEventPool` | Object pool: `Acquire()`, `Release()`, peak tracking |
| 7 | `EventBus.mqh` | `CEventBus`, `IEventHandler` | Min-heap priority queue, subscribe/unsubscribe, dispatch/drain |
| 8 | `IManager.mqh` | `IManager` | Abstract base: `Init()`, `Deinit()`, `OnNewBar()`, `OnPriceUpdate()`, `OnEvent()`, `DeclareEvents()`, logging, event dispatch helpers |
| 9 | `HighFreqTimer.mqh` | `CHighFreqTimer`, `CPerformanceCounter` | 1ms polling timer, microsecond counter |
| 10 | `LatencyOptimizer.mqh` | `CLatencyOptimizer` | Circular order buffer, avg latency, async mode, inline math (`FastMin`, `FastMax`, `FastAbs`) |
| 11 | `PASR_SymbolManager.mqh` | `CSymbolManager` | 100-symbol watchlist, tick/bar tracking, correlation, round-robin, load balancing |
| 12 | `PipelineTypes.mqh` | — | `SSignal`, `SExecResult`, `SRiskResult`, `SAIResult`, `StageMetrics`, `PipelineReport`, `PipelineContext` |
| 13 | `StateOwnershipMap.mqh` | — | Ownership contracts (documentation only) |
| 14 | `AsyncOrderManager.mqh` | `CAsyncOrderManager` | FIFO async order queue, state: PENDING→SENDING→SENT→CONFIRMED/FILLED/REJECTED |
| 15 | `PASR.mqh` | — | Master include (25+ includes in layered order) |

## EventBus Architecture

```
                    ┌─────────────┐
                    │  CEventBus   │
                    │  (Min-Heap)  │
                    └──────┬──────┘
                           │
          ┌────────────────┼────────────────┐
          │                │                │
    ┌──────┴──────┐  ┌─────┴──────┐  ┌─────┴──────┐
    │ IEventHandler│  │IEventHandler│  │IEventHandler│
    │ (Subscriber) │  │ (Subscriber) │  │ (Subscriber) │
    └──────────────┘  └─────────────┘  └─────────────┘

Priority: lower number = higher priority (0 = highest)
Max subscribers: 32
Max queue depth: 256
Dispatch: Push() → Drain() / DispatchImmediate()
```

## Config Structure

```cpp
struct StrategyConfig {
    ulong MagicNumber;
    string EAName;
    string Version;
    RiskConfig Risk;              // LotSize, RiskPercent, SL/TP mult, DD limits, etc.
    MarketConfig Market;          // ATR/ADX periods, spread filter, session hours
    AIConfig AI;                  // 60+ fields for all AI components
    PatternConfig Pattern;        // Pattern detection thresholds
    SignalTuningConfig Signal;    // Signal filtering cooldowns
    DisplayConfig Display;        // Dashboard colors, arrows, fonts
};
```
