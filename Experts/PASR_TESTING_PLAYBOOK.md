# PASR v2.16.0 — Step-by-Step Testing Playbook

## Phase 0: Compilation Verification (5 minutes)

### Step 0.1: Open MetaEditor
1. Open MetaTrader 5
2. Press F4 (or Tools → MetaQuotes Language Editor)
3. Navigate to `Experts/PASR_FULL_TEST_RUNNER.mq5`

### Step 0.2: Compile
1. Press F7 (or Compile)
2. Check Output window — must show:
   ```
   0 errors, 0 warnings
   ```
3. If errors found → check include paths in `#include` statements

### Step 0.3: Verify All EAs Compile
Compile these in order:
1. `PASR_FULL_TEST_RUNNER.mq5` — main test runner
2. `PASR_STRATEGY_TESTER.mq5` — legacy tester
3. `PASR_MODULAR.mq5` — production EA (if available)

---

## Phase 1: Initial Backtest (15 minutes)

### Step 1.1: Configure Strategy Tester
1. Open Strategy Tester (Ctrl+R)
2. EA: `PASR_FULL_TEST_RUNNER.ex5`
3. Symbol: `EURUSD` (or your primary pair)
4. Period: `M15`
5. Date Range: `2024.01.01` to `2026.01.01` (2+ years)
6. Mode: `Every tick based on real ticks`
7. Optimization: `Disabled`
8. Forward: `0` (no forward mode)

### Step 1.2: Set Inputs
1. Load preset: `PASR_Default.set`
2. Set `InpProfile = 1` (Moderate)
3. Set `InpTestMode = 0` (Single Backtest)
4. Set `InpEnableAI = false` (test rules first)

### Step 1.3: Run Backtest
1. Click Start
2. Wait for completion
3. Check Results tab:
   - **Total Trades**: > 30
   - **Profit**: > 0
   - **Profit Factor**: > 1.2
   - **Max Drawdown**: < 15%
   - **Sharpe Ratio**: > 0.3

### Step 1.4: Check Experts Log
Scroll through Experts tab for:
- `[PASRKernel] Centralized Modular Pipeline facade initialized` — confirms kernel init
- `[Exec] v3.20 Init OK` — confirms execution manager
- No `[ERROR]` or `[WARN]` messages

---

## Phase 2: Profile Comparison (30 minutes)

### Step 2.1: Test All 8 Profiles
Run backtest with same settings, change `InpProfile` each time:

| Run | InpProfile | Expected | Note |
|-----|------------|----------|------|
| 1 | 0 (Conservative) | Low DD, few trades | Capital preservation |
| 2 | 1 (Moderate) | Baseline | Reference point |
| 3 | 2 (Aggressive) | More trades, higher DD | High variance |
| 4 | 3 (Trend Only) | Few trades, high PF | Trend-filtered |
| 5 | 4 (Range Only) | Medium trades, high WR | Mean reversion |
| 6 | 5 (AI Driven) | Similar to Moderate | AI gate active |
| 7 | 6 (Pattern Heavy) | Few trades, high quality | Pattern-driven |
| 8 | 7 (Breakout) | Few trades, high RR | Volatility expansion |

### Step 2.2: Record Results
Create a table:
```
Profile | Trades | Profit | PF | WR% | DD% | Sharpe | Fitness
--------|--------|--------|----|-----|-----|--------|--------
Conserv|   ?    |   ?    | ?  |  ?  |  ?  |   ?    |   ?
Moderat|   ?    |   ?    | ?  |  ?  |  ?  |   ?    |   ?
...
```

### Step 2.3: Select Top 3
Rank by **Fitness** score. Select top 3 for optimization.

---

## Phase 3: Optimization (1-2 hours)

### Step 3.1: Set A — Conservative (validate edge)
1. Set `InpProfile` = your best profile from Phase 2
2. Enable optimization:
   - Algorithm: `Fast genetic based`
   - Sort by: `Custom Max`
3. Optimize these parameters:
   ```
   InpRiskPercentOverride    : 0.50 → 2.00, step 0.25
   InpSLMultiplierOverride   : 1.00 → 3.00, step 0.25
   InpTPMultiplierOverride   : 1.50 → 4.00, step 0.25
   InpADXThresholdOverride   : 15.0 → 35.0, step 2.5
   InpMinConfluenceOverride  : 1 → 3, step 1
   ```
4. Total combinations: ~500-2000 (runs in 10-30 min)

### Step 3.2: Analyze Results
1. Go to Optimization Results tab
2. Sort by `Custom Max` (fitness)
3. Look at top 10 results:
   - Check that parameters are not at extremes
   - Verify trades > 50, PF > 1.3, DD < 15%

### Step 3.3: Set B — Deep Optimization (optional)
If Set A looks good, expand to 10 parameters:
```
Add: InpSignalMinScoreOverride  : 0.30 → 0.55, step 0.05
Add: InpMinRRRatioOverride      : 1.2 → 2.5, step 0.15
Add: InpMinPatternScoreOverride : 35.0 → 60.0, step 5.0
Add: InpMaxDailyLossPctOverride : 2.0 → 5.0, step 0.5
Add: InpMaxDrawdownPctOverride  : 8.0 → 20.0, step 2.0
```
This creates ~50,000 combinations — may take 1-2 hours.

---

## Phase 4: Walk-Forward Validation (30 minutes)

### Step 4.1: Split Data
1. Take your best parameter set from Phase 3
2. Split data into windows:
   - Train: 2024.01.01 → 2024.06.30 (6 months)
   - Test: 2024.07.01 → 2024.09.30 (3 months)
   - Roll forward 1 month each iteration

### Step 4.2: Run Each Window
For each window:
1. Set training date range → run optimization → record best params
2. Set test date range → run with those params → record metrics

### Step 4.3: Evaluate
Criteria:
- **Consistency Score**: ≥ 60% of windows profitable
- **Stability Score**: ≥ 50% of windows pass all criteria
- **Degradation**: test PF / train PF ≥ 0.50

If any criterion fails → strategy may be overfitted. Simplify and re-test.

---

## Phase 5: Monte Carlo Stress Test (15 minutes)

### Step 5.1: Export Trade History
1. Run backtest with best params
2. Export trade history from Journal tab
3. Convert to `SMCTrade` format (manual or script)

### Step 5.2: Run Simulation
1. Include `MonteCarloFramework.mqh` in a test script
2. Set `SMCConfig.numSimulations = 1000`
3. Set `SMCConfig.method = MC_TRADE_RANDOMIZE`
4. Run and check:
   - **Profitable Sims**: ≥ 80%
   - **Median PF**: ≥ 1.2
   - **5th % PF**: ≥ 1.0
   - **95th % DD**: ≤ 25%

---

## Phase 6: Forward Testing (1 month minimum)

### Step 6.1: Deploy to Demo
1. Open demo account in MT5
2. Attach `PASR_FULL_TEST_RUNNER.ex5` to chart
3. Use best params from optimization
4. Set `InpEnableAI = false` initially

### Step 6.2: Monitor Daily
Check these metrics:
- Daily PnL vs backtest expectation
- Max drawdown stays within limits
- Trade frequency matches backtest
- No execution errors in Journal

### Step 6.3: Weekly Review
Every Sunday:
- Compare cumulative PnL to backtest projection
- Check if trade distribution matches (win rate, avg profit/loss)
- Review any stopped-out trades — were SL levels appropriate?

### Step 6.4: Go/No-Go Decision (after 1 month)
**GO if:**
- Demo PnL within 20% of backtest projection
- Max DD within limits
- No execution errors
- ≥ 50 trades executed

**NO-GO if:**
- Demo PnL significantly worse than backtest
- DD exceeded limits
- Multiple execution errors
- Trade frequency < 50% of expected

---

## Phase 7: Live Deployment (after successful demo)

### Step 7.1: Start Small
1. Open live account
2. Use minimum lot size (0.01)
3. Set `InpRiskPercentOverride = 0.5` (conservative)
4. Run for 2 weeks

### Step 7.2: Scale Up Gradually
If 2 weeks OK:
- Week 3: Increase to `RiskPercent = 1.0`
- Week 4-6: Monitor, no changes
- Week 7+: Increase to `RiskPercent = 1.5` if performing well

### Step 7.3: Ongoing Monitoring
- **Daily**: Check PnL, open positions, journal errors
- **Weekly**: Review performance vs backtest, adjust if needed
- **Monthly**: Full backtest with updated data, re-optimize if drift detected
- **Quarterly**: Complete re-optimization + walk-forward + Monte Carlo

---

## Quick Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| No trades generated | Signal score too high | Lower `InpSignalMinScoreOverride` |
| Too many losing trades | ADX threshold too low | Increase `InpADXThresholdOverride` |
| Large drawdowns | Risk too high | Reduce `InpRiskPercentOverride` |
| Orders rejected | Wrong filling mode | Fixed — now auto-detects |
| EA won't compile | Include path error | Check `#include` paths use `<PASR/...>` |
| Pipeline ABORT | Risk check failed | Check `InpMaxDailyLossPct`, `InpMaxDrawdownPct` |

---

*PASR v2.16.0 — Complete Testing Playbook*
