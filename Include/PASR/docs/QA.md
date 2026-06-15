# QA Module (`PASR/QA/`)

17 files — Testing framework: assertions, unit tests, smoke tests, Monte Carlo, walk-forward, mocks.

## File Reference

| # | File | Class | Fungsi |
|---|------|-------|--------|
| 1 | `Assertions.mqh` | `CAssertions`, `QA` namespace | Core assertions: `ASSERT_TRUE`, `ASSERT_EQ`, `ASSERT_APPROX`, `ASSERT_RANGE`, `ASSERT_FAIL` (+ macros) |
| 2 | `AssertHelpers.mqh` | — | Extended macros: `ASSERT_STAGE_OK`, `ASSERT_NO_TIMEOUT`, `ASSERT_SIGNAL_EQ`, `ASSERT_EVENT_PUSHED` |
| 3 | `Test.mqh` | `CPASRTest` | Lightweight test runner: `Expect()`, `ExpectEq()`, `ExpectNear()`, `Summary()` |
| 4 | `TestRunner.mqh` | `CTestRunner` | Test execution framework: `Run()`, `Skip()`, `PrintSummary()`, pass/fail/skip/duration |
| 5 | `SmokeTest.mqh` | `CPASRSmoke` | 5 end-to-end smoke tests: Kernel, Regime, Signal v3, Risk, Dashboard |
| 6 | `StrategyTestSuite.mqh` | — | 8 strategy profiles, fitness computation, result validation |
| 7 | `WalkForwardFramework.mqh` | — | Rolling window OOS validation, overfitting detection (PF degradation, DD increase) |
| 8 | `MonteCarloFramework.mqh` | — | 6 randomization methods, VaR/CVaR, robustness assessment |
| 9 | `OptimizationSets.mqh` | — | 3 optimization sets: Conservative (5 params), Moderate (10 params), AI-Focused (8 params) |
| 10 | `SignalManagerTest.mqh` | `CSignalManagerTest` | 10 unit tests for SignalManager v3 |
| 11 | `RiskManagerTest.mqh` | `CRiskManagerTest` | 8 unit tests for RiskManager (Phase 4) |
| 12 | `QAStressTest.mqh` | `CQAStressTest` | HFT tick chaos simulation, pool exhaustion, circuit breaker testing |
| 13 | `PipelineHarness.mqh` | `CPipelineHarness` | Full 14-stage pipeline runner with synthetic data (trending + ranging) |
| 14 | `MockEventBus.mqh` | `CMockEventBus` | Stub EventBus with event history (256), passthrough mode |
| 15 | `MockDataManager.mqh` | `CMockDataManager` | Synthetic tick/bar injector, playback control (4096 ticks, 1024 bars) |
| 16 | `LatencySimulator.mqh` | `CLatencySimulator` | Backtest-only latency + requote simulation |
| 17 | `BusinessLogicHarness.mqh` | `CBusinessLogicHarness` | 8 lifecycle tests: state primitives, execution ledger, exit queue, signal decision, feature validation |

## Running Tests

```cpp
// Smoke tests
#include <PASR/QA/SmokeTest.mqh>
CPASRSmoke smoke;
smoke.RunAll();

// Unit tests
#include <PASR/QA/TestRunner.mqh>
#include <PASR/QA/SignalManagerTest.mqh>
CSignalManagerTest signalTests;
signalTests.RunAll();

// Pipeline test harness
#include <PASR/QA/PipelineHarness.mqh>
CPipelineHarness harness;
harness.Initialize();
harness.LoadScenario_Trending();
harness.RunCycles(100);
harness.PrintReport();

// Monte Carlo
#include <PASR/QA/MonteCarloFramework.mqh>
SMCSummary summary;
RunMonteCarlo(summary, trades, tradeCount, config, "report.csv");
```

## Monte Carlo Methods

| Method | Deskripsi |
|--------|-----------|
| `MC_METHOD_SHUFFLE` | Fisher-Yates trade shuffle |
| `MC_METHOD_BLOCK_SHUFFLE` | Block-wise permutation |
| `MC_METHOD_BOOTSTRAP` | Resampling with replacement |
| `MC_METHOD_MUTATE` | PnL mutation (Gaussian) |
| `MC_METHOD_SPREAD` | Spread injection |
| `MC_METHOD_SLIPPAGE` | Slippage injection |

## Walk-Forward Framework

| Parameter | Default |
|-----------|---------|
| Train window | 6 months |
| Test window | 3 months |
| Step | 1 month |
| Overfitting threshold | PF degradation > 30% |
| DD increase flag | Max DD > 2× train DD |
