# Infrastructure Module (`PASR/Infra/`)

13 files — Data management, persistence, monitoring, logging.

## File Reference

| # | File | Class | Fungsi |
|---|------|-------|--------|
| 1 | `TickCache.mqh` | `CTickCache` | Tick duplicate filter, new-bar detection, hit/miss stats |
| 2 | `AccountSnapshot.mqh` | `SAccountSnapshot` | Per-cycle account state: balance, equity, margin, profit, drawdown |
| 3 | `DataManager.mqh` | `CDataManager` | **Central data hub**: ATR cache, daily profit, position registry access, GV scavenging |
| 4 | `SessionState.mqh` | `CSessionState` | Equity peak, daily/weekly PnL, drawdown, trades today, GV persistence |
| 5 | `StateManager.mqh` | `CStateManager` | Binary file persistence: equity peak, daily balance, consec losses, circuit breaker |
| 6 | `SnapshotManager.mqh` | `CSnapshotManager` | Auto snapshot rotation (max 5), integrity checksum, event-driven save |
| 7 | `SanityManager.mqh` | `CSanityManager` | Tick freshness, spread width, price gap validation, circuit breaker |
| 8 | `HealthMonitor.mqh` | `CHealthMonitor` | Memory/heartbeat/error/latency monitoring, soft/hard recovery escalation |
| 9 | `AdaptiveConfig.mqh` | `CAdaptiveConfig` | Multi-dimensional config: regime × session × volatility tiers, AI confidence threshold |
| 10 | `TelemetryRecorder.mqh` | `CTelemetryRecorder` | CSV metric recording, buffer/flush, file rotation, auto optimizer detection |
| 11 | `JournalManager.mqh` | `CJournalManager` | Per-trade CSV journal, 500-entry ring buffer, stats by regime/session/day |
| 12 | `AuditLogSystem.mqh` | `CAuditLogSystem` | Structured audit log, circular buffer, file rotation (5MB), retention |
| 13 | `PerformanceReport.mqh` | `CPerformanceReport` | Minimal HTML report generator from journal data |

## Key Managers

### CDataManager
```
- OnInit: create ATR(14) handle
- OnTick: update tick cache
- OnNewBar: refresh ATR, update daily profit, scavenge GVs
- OnTrade: track profit/loss, update consecutive losses
```

### CSessionState
```
- Tracks: peak equity, daily/weekly PnL, drawdown, open positions
- Persists via GlobalVariables (cross-restart)
- Daily reset at broker midnight
```

### CSanityManager
```
Validation checks:
- Tick freshness (≤ 5 seconds)
- Spread (≤ configured max)
- Price gap (> 10 × current spread)
Circuit breaker: trips after 3 consecutive failures
Auto half-open reset after cooldown
```

### CJournalManager
```
Recording: ticket, direction, lots, entry/exit price, SL/TP, profit, R:R
Context: AI score, regime, session, pattern, confidence
Stats: by regime, by session, daily PnL, max drawdown (500-entry buffer)
Export: CSV file with daily rotation
```

### CHealthMonitor
```
Health states: OK → WARNING → CRITICAL → DEAD
Monitors: memory usage growth, heartbeat gaps, error rate, latency
Recovery: SOFT (reset) or HARD (full reinit)
```
