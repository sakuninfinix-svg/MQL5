# Signal Module (`PASR/Signal/`)

17 files — Signal generation, filtering, aggregation, and decision engine.

## Arsitektur

```
Signal/
  ├── ISignalSource.mqh          — Abstract signal source interface
  ├── SignalConfig.mqh           — Configuration cache
  ├── SignalFilter.mqh           — Legacy filter chain (spread, ATR, session)
  ├── SignalFilterPipeline.mqh   — Modular filter pipeline (zone, context, MTF, opportunity)
  ├── SignalScorer.mqh           — Signal scoring, quality tiers, normalization
  ├── SignalCooldownManager.mqh  — Cooldown + failed zone tracking
  ├── SignalAggregator.mqh       — Vote/Modulate/Veto aggregation (32 sources)
  ├── SignalDecisionEngine.mqh   — Final signal decision (accept/reject)
  ├── SignalManager.mqh          — Top-level signal orchestration
  ├── SignalManagerIntegration.mqh — Integration guide (docs)
  ├── DynamicWeightManager.mqh   — Bayesian signal weight adaptation
  ├── PatternSignalSource.mqh    — Pattern → signal adapter
  ├── SRSignalSource.mqh         — S/R proximity → signal adapter
  ├── RegimeSignalSource.mqh     — Regime → signal (veto/modulate)
  ├── RegimeFilter.mqh           — ADX/ATR/BB regime detection
  ├── SessionQualityScorer.mqh   — Session quality scoring (stub)
  └── EntryQualityScorer.mqh     — Entry quality scoring (stub)
```

## File Reference

| # | File | Class | Fungsi |
|---|------|-------|--------|
| 1 | `ISignalSource.mqh` | `ISignalSource` | Interface: `Name()`, `Evaluate(SignalResult&)`. Struct `SignalResult`: direction, confidence, reason |
| 2 | `SignalConfig.mqh` | `CSignalConfig` | Cache: lookback, min score, confluence, cooldown, MTF, ATR, spread, urgency |
| 3 | `SignalFilter.mqh` | `CSignalFilter` | Legacy: spread check, ATR filter, session time filter |
| 4 | `SignalFilterPipeline.mqh` | `CSignalFilterPipeline` | Modular: zone touch → context (candle/momentum) → MTF bias → opportunity (R:R) → custom filters |
| 5 | `SignalScorer.mqh` | `CSignalScorer` | Normalize, MTF bias, quality tier (HIGH/MEDIUM/LOW), urgency |
| 6 | `SignalCooldownManager.mqh` | `CSignalCooldownManager` | Per-zone cooldown, pattern failure blocking, cleanup |
| 7 | `SignalAggregator.mqh` | `CSignalAggregator` | 32-source aggregation: veto → multiplier → voter, dominance gap, confluence |
| 8 | `SignalDecisionEngine.mqh` | `CSignalDecisionEngine` | Final: `Decide()`, reason: ACCEPTED, NO_SOURCES, VETOED, CONFLICT, NO_CONSENSUS, STALE |
| 9 | `SignalManager.mqh` | `CSignalManager` | **Orchestrator**: init sources, aggregate, filter, cooldown, decision, event handling |
| 10 | `SignalManagerIntegration.mqh` | — | Documentation only |
| 11 | `DynamicWeightManager.mqh` | `CDynamicWeightManager` | 10-source performance tracking, Bayesian weight updates (LR=0.01, 0.1-2.0 range) |
| 12 | `PatternSignalSource.mqh` | `PatternSignalSource` | GPA = gap boost, conflict penalty, confidence threshold |
| 13 | `SRSignalSource.mqh` | `SRSignalSource` | BUY near support, SELL near resistance, confidence from distance + strength |
| 14 | `RegimeSignalSource.mqh` | `RegimeSignalSource` | VETO/MODULATE mode: range=1.1x, trend=0.7x, volatile=0.2x, squeeze/crash=0.0x |
| 15 | `RegimeFilter.mqh` | `CRegimeFilter` | ADX(14) + ATR(14) + BB(20,2) → regime detection |
| 16 | `SessionQualityScorer.mqh` | `CSessionQualityScorer` | Stub → returns 0.5 |
| 17 | `EntryQualityScorer.mqh` | `CEntryQualityScorer` | Stub → returns 0.5 |

## Signal Flow

```
                   ┌──────────────┐
                   │ SignalManager │
                   └──────┬───────┘
                          │
        ┌─────────────────┼──────────────────┐
        │                 │                   │
   ┌────┴────┐      ┌────┴────┐        ┌────┴────┐
   │Pattern  │      │SR       │        │Regime   │
   │SignalSrc│      │SignalSrc│        │SignalSrc│
   └────┬────┘      └────┬────┘        └────┬────┘
        │                 │                   │
        └─────────────────┼──────────────────┘
                          │
                    ┌─────┴──────┐
                    │ Aggregator │ (veto → multiplier → voter)
                    └─────┬──────┘
                          │
                    ┌─────┴──────┐
                    │  Decision  │
                    │   Engine   │ → SignalDecisionResult
                    └────────────┘
```

## Source Types (Aggregator)

| Type | Weight | Perilaku |
|------|--------|----------|
| VETO | -1 | Veto seluruh sinyal jika source negatif |
| VOTER | +1 | Weighted voting (weight × confidence) |
| MULTIPLIER | 0 | Confidence multiplier (× factor) |

## Signal Aggregation
```
1. Process VETO sources first — any veto = signal rejected
2. Process MULTIPLIER sources — factor × confidence
3. Process VOTER sources — weighted sum
4. Check dominance gap (max vote vs others)
5. Check minimum confluence (≥ configured sources)
6. Return AggregatedSignal
```
