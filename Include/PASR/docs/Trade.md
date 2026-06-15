# Trade Module (`PASR/Trade/`)

13 files — Trade execution, risk management, position management, exit logic, recovery.

## File Reference

| # | File | Class | Fungsi |
|---|------|-------|--------|
| 1 | `TradePlan.mqh` | `CTradePlan` | Build `TradePlan` from `SSignal`: lot, entry, SL, TP, TP2, BE, partial close |
| 2 | `RiskManager.mqh` | `CRiskManager` | Position sizing (fixed fraction), daily loss/drawdown/consec loss limits, circuit breaker, spread/session/margin checks |
| 3 | `PositionRegistry.mqh` | `CPositionRegistry` | Per-cycle position scan (64 max), lookup by ticket, floating PnL |
| 4 | `PositionManager.mqh` | `CPositionManager` | Pipeline-aware position cache, cached accessors, fill `PipelineContext` |
| 5 | `ExecutionManager.mqh` | `CExecutionManager` | Order send with retry (max 3, 500ms), requote handling, stop clamping, event dispatch |
| 6 | `ExecutionLedger.mqh` | `CExecutionLedger` | Request lifecycle: IDLE→REQUESTED→SENT→RETRYING→FILLED/REJECTED/TIMEOUT |
| 7 | `ExitEngine.mqh` | `CExitEngine` | 4 exit methods: Chandelier (3×ATR), Time (10 bars), Structure Break, Profit Fade (RSI>70) |
| 8 | `ExitConfirmationQueue.mqh` | `CExitConfirmationQueue` | 16-slot close confirmation tracker, retries (max 2), timeout detection |
| 9 | `ExitPressureScorer.mqh` | `CExitPressureScorer` | Stub → returns 0.5 |
| 10 | `RecoveryEngine.mqh` | `RecoveryEngine` | Lightweight recovery state: active, ticket, direction, attempts, GV persistence |
| 11 | `RecoveryManager.mqh` | `CRecoveryManager` | Orchestrate recovery: track losing positions, reconcile, stats |
| 12 | `RecoveryScorer.mqh` | `CRecoveryScorer` | Stub → returns false |
| 13 | `CorrelationManager.mqh` | `CCorrelationManager` | Pearson correlation matrix (100 pairs, 20 bars), block if correlation > 0.80 |

## Trade Execution Flow

```
SignalManager → SignalDecisionResult
     ↓
CRiskManager.Check()
  - Daily loss limit check
  - Max drawdown check
  - Max open positions check
  - Max consecutive losses check
  - Spread check
  - Session filter
  - Margin check
  - Circuit breaker check
  → CalcLot() → suggested lot size
     ↓
CTradePlan.Build()
  - Convert SSignal + lot → TradePlan (entry, SL, TP)
  - ATR-based SL/TP distances
     ↓
CExecutionManager.Execute()
  - Market or Limit order (TradePlan)
  - Retry loop (max 3, 500ms)
  - Stop clamping to broker min
  - Event dispatch (open, update)
```

## Exit Methods (ExitEngine)

| Method | Trigger | Parameter |
|--------|---------|-----------|
| Chandelier | ATR-based trailing stop | 3×ATR(22) |
| Time-based | Bars held exceed limit | 10 bars |
| Structure Break | Close beyond swing + 0.3×ATR | 5-bar lookback |
| Profit Fade | RSI ≥ 70 (long) / ≤ 30 (short) | RSI threshold |

## Risk Manager Limits

| Limit | Default Config |
|-------|---------------|
| Max Daily Loss | -5% |
| Max Drawdown | -15% |
| Max Open Positions | 3 |
| Max Consecutive Losses | 5 |
| Circuit Breaker Types | DAILY_LOSS, MAX_DRAWDOWN, SPREAD |

## Correlation Manager

```
- Update: on new bar + periodic (60s interval)
- Window: 20 bars
- Method: Pearson coefficient
- Max pairs: 100 (10 symbols → 45 pairs)
- Threshold: 0.80 (block new trade if exceeded)
```

## Recovery System

```
RecoveryEngine → tracks 1 losing position
RecoveryManager → orchestrates max 16 engines
  - OnTradeOpen: create engine
  - OnPriceUpdate: reconcile (check if position recovered)
  - OnNewBar: manage cooldown, attempts
  - GV persistence for restart resilience
```
