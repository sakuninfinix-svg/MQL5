# Analysis Module (`PASR/Analysis/`)

12 files — Market analysis: Support/Resistance, Zone, Pattern, Regime, Adaptive Parameters.

## Arsitektur

```
Analysis/
  ├── SRDetector.mqh         — Pivot detection (swing high/low)
  ├── SRZoneStore.mqh         — S/R zone storage + indexing
  ├── SRZoneScorer.mqh        — Zone scoring (stub)
  ├── SRManager.mqh           — SR pipeline orchestrator
  ├── ZoneManager.mqh         — Supply/Demand zone manager
  ├── MarketRegimeDetector.mqh — Rule-based regime detection
  ├── MarketRegimeScorer.mqh   — Regime confidence scorer
  ├── HMMRegimeDetector.mqh    — HMM-based regime detection
  ├── AdaptiveParameterManager.mqh — Dynamic SL/TP/lot sizing
  ├── CNNPatternRecognizer.mqh — 1D CNN pattern recognition
  └── Pattern/
        ├── PatternTypes.mqh    — Pattern enum definitions
        └── PatternManager.mqh  — Probabilistic pattern scoring
```

## File Reference

| # | File | Class | Fungsi |
|---|------|-------|--------|
| 1 | `SRDetector.mqh` | `CSRDetector` | Swing high/low pivot detection with configurable left/right bars |
| 2 | `SRZoneStore.mqh` | `CSRZoneStore` | Indexed zone store (binary search), merging, aging, breakout detection |
| 3 | `SRZoneScorer.mqh` | `CSRZoneScorer` | Stub — zone proximity/strength scoring |
| 4 | `SRManager.mqh` | `CAnalysisSRManager` | **Orchestrator**: pivot scan → store → age → merge → cleanup |
| 5 | `ZoneManager.mqh` | `CAnalysisZoneManager` | Supply/Demand zones from impulsive moves + base bars |
| 6 | `MarketRegimeDetector.mqh` | `CMarketRegimeDetector` | ATR/ADX/BB-based regime detection with hysteresis |
| 7 | `MarketRegimeScorer.mqh` | `CMarketRegimeScorer` | ADX+ATR regime confidence score (0-1) |
| 8 | `HMMRegimeDetector.mqh` | `CHMMRegimeDetector` | 6-state Hidden Markov Model for regime detection |
| 9 | `AdaptiveParameterManager.mqh` | `CAdaptiveParameterManager` | Regime-aware SL/TP/lot/entry threshold adaptation |
| 10 | `CNNPatternRecognizer.mqh` | `CCNNPatternRecognizer` | 1D CNN (2 conv + dense) for 20-candle OHLC pattern classification |
| 11 | `Pattern/PatternTypes.mqh` | — | `ENUM_PATTERN_TYPE`: 12 patterns (Pinbar, Engulfing, Inside Bar, Fakey, Tweezer, Doji, Harami, Morning/Evening Star) |
| 12 | `PatternManager.mqh` | `CPatternManager` | Logistic regression pattern scoring, 5 primary patterns, regime-aware weighting |

## Regime Detection

### MarketRegimeDetector (Rule-based)
```
Input: ATR(14), ADX(14), Bollinger Bandwidth(20,2)
Logic:
  - Squeeze: BB bandwidth < threshold
  - Volatile: ATR ratio > threshold
  - Trend: ADX > threshold + DI+/DI- direction
  - Range: low ADX + moderate ATR
  - Crash: sudden ATR spike + momentum down
Output: EMarketRegime (TREND_UP, TREND_DOWN, RANGE, VOLATILE, SQUEEZE, CRASH, TRANSITION)
```

### HMMRegimeDetector (Probabilistic)
```
States: TREND_UP, TREND_DOWN, RANGE, VOLATILE, SQUEEZE, TRANSITION
Algorithm: Forward algorithm with online transition matrix learning
Features: normalized trend_strength, volatility, momentum
```

## Pattern Detection (PatternManager)

| Pattern | Metrik |
|---------|--------|
| Pinbar | Body ratio, wick ratio, direction |
| Engulfing | Body ratio ≥ threshold |
| Tweezer | Equal highs/lows + reversal |
| Fakey | Inside bar + breakout failure |
| Inside Bar Breakout | Inside bar + outside breakout |

All patterns scored via logistic regression with trainable weights (`PASR_pattern_weights.bin`).

## SR Pipeline Flow (SRManager)
```
OnNewBar()
  1. Compute ATR
  2. SRDetector.Scan() — find pivots
  3. SRZoneStore.AddOrUpdate() — store zones
  4. SRZoneStore.CheckBroken() — breakout validation
  5. SRZoneStore.AgeAndRefresh() — decay
  6. SRZoneStore.MergeNearby() — merge overlapping
  7. SRZoneStore.RemoveStale() — garbage collect
```
