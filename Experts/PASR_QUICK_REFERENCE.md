# PASR v2.16.0 — Quick Reference Card

## File Structure
```
Experts/
├── PASR_MODULAR.mq5          ← Main EA (production)
├── PASR_FULL_TEST_RUNNER.mq5 ← Test runner (all frameworks)
├── PASR_STRATEGY_TESTER.mq5  ← Legacy tester (single profile)
├── PASR_Default.set          ← Strategy Tester preset
├── PASR_MASTER_AUDIT_REPORT_V2.md
└── PASR_AUDIT_REPORT_AND_TEST_STRATEGY.md

Include/PASR/
├── Core/           ← PipelineTypes, EventBus, Globals, Events
├── Central/        ← PASRKernel, ModuleFactory, Lifecycle
├── AI/             ← MLP, LSTM, ONNX, Ensemble, Trainer, Guard
├── Trade/          ← RiskManager, ExecutionManager, ExitEngine
├── Orchestration/  ← PipelineEngine, 14 Stage classes
├── Analysis/       ← RegimeDetector, PatternManager, SRManager
├── Signal/         ← SignalManager, RegimeFilter
├── Infra/          ← Telemetry, Journal, Health, Session
└── QA/             ← StrategyTestSuite, WalkForward, MonteCarlo, OptSets
```

## 37 Fixes Applied (3 Rounds)
| Round | Focus | Fixes |
|-------|-------|-------|
| 1 | Core + Pipeline | 22 (3 P0, 3 P1, 8 High, 8 Medium) |
| 2 | Trade Layer | 5 (3 High, 2 Medium) |
| 3 | AI Subsystem | 8 (3 High, 5 Medium) + 2 noted |
| **+1** | Cross-ref fix | 1 (AIInferStage Predict signature) |

## 4 Test Frameworks
| Framework | File | Purpose |
|-----------|------|---------|
| Strategy Test Suite | `QA/StrategyTestSuite.mqh` | 8 profiles + fitness |
| Walk-Forward | `QA/WalkForwardFramework.mqh` | Overfitting detection |
| Monte Carlo | `QA/MonteCarloFramework.mqh` | Robustness + VaR |
| Optimization Sets | `QA/OptimizationSets.mqh` | 3 parameter sets |

## How to Test

### Quick Backtest
1. Open MT5 → Strategy Tester
2. Select `PASR_FULL_TEST_RUNNER.ex5`
3. Load `PASR_Default.set`
4. Set `InpProfile` (0-7) for strategy type
5. Run "Every tick based on real ticks"

### Full Comparison
1. Set `InpTestMode = TEST_FULL_COMPARISON`
2. Run each profile (0-7) sequentially
3. Compare fitness scores in Experts log

### Optimization
1. Set `InpTestMode = TEST_OPTIMIZATION_SET_A` (start conservative)
2. Enable optimization on: RiskPercent, SLMultiplier, TPMultiplier
3. Sort by "Custom Max"
4. Re-run with Set B (10 params) if Set A passes

### Walk-Forward
1. Split data: first 70% train, last 30% test
2. Optimize on train, validate on test
3. Check consistency ≥ 60%, stability ≥ 50%

### Monte Carlo
1. Export trade history from backtest
2. Run 1000 simulations (trade shuffle)
3. Check: profitable ≥ 80%, p5 PF ≥ 1.0

## 8 Strategy Profiles
| ID | Name | Risk% | AI | Best For |
|----|------|-------|----|----------|
| 0 | Conservative | 0.5 | Yes | Capital preservation |
| 1 | Moderate | 1.0 | No | General baseline |
| 2 | Aggressive | 2.0 | Yes | High frequency |
| 3 | Trend Only | 1.0 | Yes | Trending markets |
| 4 | Range Only | 0.8 | Yes | Sideways markets |
| 5 | AI Driven | 1.0 | Yes | Adaptive conditions |
| 6 | Pattern Heavy | 1.0 | Yes | Structure markets |
| 7 | Breakout | 1.5 | Yes | Volatility expansion |

## Deployment Checklist
- [ ] Compile: zero errors, zero warnings
- [ ] Backtest 2 years: fitness > 0, DD < 15%, PF > 1.2
- [ ] Optimize: top 3 by Custom Max
- [ ] Walk-forward: consistency ≥ 60%
- [ ] Monte Carlo: profitable ≥ 80%
- [ ] Demo test: 1 month / 50+ trades
- [ ] Live: minimum capital, monitor daily

## Key Metrics Thresholds
| Metric | Minimum | Target |
|--------|---------|--------|
| Profit Factor | > 1.0 | > 1.5 |
| Recovery Factor | > 1.0 | > 2.0 |
| Win Rate | > 40% | > 50% |
| Max DD | < 25% | < 15% |
| Sharpe Ratio | > 0.3 | > 1.0 |
| Trades | > 30 | > 100 |
| Fitness | > 0 | > 5.0 |

## Emergency Contacts
- Circuit breaker: auto-halts at MaxDailyLossPct
- Spread filter: blocks trades when spread > threshold
- Ledger timeout: clears pending orders after 120s
- Manual: close all positions, disable EA
