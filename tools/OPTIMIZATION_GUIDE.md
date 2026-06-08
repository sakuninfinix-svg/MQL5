# PASR_MODULAR Optimization Guide
## Systematic Parameter Optimization for MetaTrader 5 EA

### Overview
This guide provides a comprehensive approach to optimizing the PASR_MODULAR Expert Advisor using systematic parameter testing and genetic optimization in MetaTrader 5 Strategy Tester.

### Optimization Strategy
The optimization follows a phased approach to efficiently find the best parameter combination:

#### Phase 1: Risk Parameters (High Priority)
**Objective**: Find optimal risk management settings that balance profit vs drawdown

**Parameters to Optimize**:
- `InpRiskPercent`: 0.5-3.0% (Risk per trade)
- `InpSLMultiplier`: 1.0-3.0 (Stop Loss ATR multiplier)
- `InpTPMultiplier`: 1.5-4.0 (Take Profit ATR multiplier)
- `InpMaxDailyLossPct`: 2.0-10.0% (Daily loss limit)
- `InpMaxDrawdownPct`: 5.0-20.0% (Maximum drawdown)
- `InpMaxOpenPositions`: 1-5 (Concurrent positions)
- `InpUseBreakEven`: true/false (Break-even functionality)
- `InpBreakEvenATRMult`: 0.5-2.0 (Break-even trigger)
- `InpUseTrailingStop`: true/false (Trailing stop)
- `InpTrailATRMult`: 0.5-2.0 (Trailing stop distance)

**Why First**: Risk parameters have the highest impact on trading performance and capital preservation.

#### Phase 2: Market Parameters (Medium Priority)
**Objective**: Optimize market condition filters and indicators

**Parameters to Optimize**:
- `InpATRPeriod`: 7-35 (ATR calculation period)
- `InpADXPeriod`: 7-35 (ADX trend period)
- `InpADXTrendThreshold`: 20-40 (Minimum trend strength)
- `InpSpreadFilterPips`: 2-10 (Maximum spread allowed)
- `InpSessionStartHour`: 0-8 (Trading session start)
- `InpSessionEndHour`: 16-23 (Trading session end)
- `InpFilterNewsTime`: true/false (News filtering)
- `InpNewsBufferMinutes`: 15-60 (News buffer)

**Why Second**: Market parameters refine entry/exit quality after risk parameters are set.

#### Phase 3: Pattern Parameters (Lower Priority)
**Objective**: Fine-tune pattern recognition settings

**Parameters to Optimize**:
- `InpEnablePatterns`: true/false (Pattern detection)
- `InpMinPatternScore`: 35-60 (Minimum pattern quality)
- `InpPatternLookbackBars`: 30-80 (Pattern detection range)
- `InpPinBarRatio`: 1.5-3.0 (Pin bar requirements)
- `InpEngulfMultiplier`: 1.0-1.5 (Engulfing candle multiplier)
- `InpRequireConfirmation`: true/false (Pattern confirmation)

**Why Last**: Pattern parameters provide fine-tuning after core strategy is optimized.

### Fitness Function
The EA uses a comprehensive fitness function that evaluates:

```
Fitness = Log(1 + Profit) 
        + 2 × Log(1 + Profit Factor)
        + 1.5 × Log(1 + Recovery Factor)
        + Log(1 + Expected Payoff)
        + 0.25 × Sharpe Ratio
        + Min(2.0, Trades/50)
        - 0.15 × Equity Drawdown %
```

**Constraints**:
- Minimum 20 trades required
- Profit must be positive
- Heavily penalizes negative profit and high drawdown

### Tools and Setup

#### 1. Configuration Files
Located in `MQL5/Presets/`:
- `PASR_v2_Baseline.set` - Current default parameters
- `PASR_v2_RiskOptimization.ini` - Risk parameter ranges
- `PASR_v2_MarketOptimization.ini` - Market parameter ranges  
- `PASR_v2_PatternOptimization.ini` - Pattern parameter ranges

#### 2. Automation Scripts
Located in `MQL5/tools/`:
- `run_optimization.sh` - Main optimization runner
- `optimization_manager.py` - Python optimization manager

### Usage Instructions

#### Option 1: Automated Script (Recommended)
```bash
cd /media/agus/40A604FEA604F666/Users/agsi/AppData/Roaming/MetaQuotes/Terminal/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/tools
./run_optimization.sh
```

Follow the prompts to:
1. Compile the EA (optional but recommended)
2. Run baseline test
3. Select optimization approach
4. Generate final report

#### Option 2: Manual MetaTrader 5 Testing
1. Open MetaTrader 5
2. Press F4 or View → Strategy Tester
3. Select PASR_MODULAR expert
4. Load preset file from MQL5/Presets/
5. Configure testing parameters:
   - Symbol: EURUSD (or your preferred pair)
   - Timeframe: H1 (recommended)
   - Model: Every tick (most accurate)
   - Deposit: 10000 USD
   - Leverage: 1:100
6. For optimization:
   - Check "Optimization" checkbox
   - Select "Genetic algorithm" mode
   - Set optimization criteria to "Custom max"
   - Click "Start" to begin optimization

#### Option 3: Command Line Testing
```bash
# Single test
wine "/media/agus/40A604FEA604F666/Program Files/MetaTrader 5/metatester64.exe" \
    /config:"/media/agus/40A604FEA604F666/Users/agsi/AppData/Roaming/MetaQuotes/Terminal/D0E8209F77C8CF37AD8BF550E51FF075/config/common.ini" \
    /profile:Default \
    /expert:"/media/agus/40A604FEA604F666/Users/agsi/AppData/Roaming/MetaQuotes/Terminal/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/Experts/PASR_MODULAR.mq5" \
    /symbol:EURUSD \
    /period:H1 \
    /deposit:10000 \
    /currency:USD \
    /leverage:100 \
    /model:0 \
    /spread:10 \
    /optimization_mode:0 \
    /set_file:"/media/agus/40A604FEA604F666/Users/agsi/AppData/Roaming/MetaQuotes/Terminal/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/Presets/PASR_v2_Baseline.set" \
    /tester:"/media/agus/40A604FEA604F666/Users/agsi/AppData/Roaming/MetaQuotes/Terminal/D0E8209F77C8CF37AD8BF550E51FF075/Tester/Baseline" \
    /portable
```

### Testing Recommendations

#### Backtest Settings
- **Timeframe**: H1 (recommended for PASR strategy)
- **Model**: "Every tick" (most accurate)
- **Period**: At least 1 year of historical data
- **Spread**: Set to realistic values for your broker
- **Deposit**: Minimum 10000 USD for proper risk testing

#### Optimization Settings
- **Algorithm**: Genetic (faster convergence)
- **Criteria**: Custom max (uses EA fitness function)
- **Timeout**: Set adequate time for thorough search
- **Passes**: Let it run until convergence

### Expected Results

#### Good Performance Indicators
- **Profit Factor**: > 1.5 (ideally > 2.0)
- **Recovery Factor**: > 2.0 (ideally > 3.0)
- **Sharpe Ratio**: > 0.5 (ideally > 1.0)
- **Maximum Drawdown**: < 15% (ideally < 10%)
- **Total Trades**: > 50 (for statistical significance)
- **Expected Payoff**: Positive and stable

#### Warning Signs
- **Profit Factor** < 1.2: Strategy not profitable enough
- **Recovery Factor** < 1.0: Risk of ruin too high
- **Maximum Drawdown** > 25%: Risk management too loose
- **Total Trades** < 20: Not enough statistical significance
- **High variance** between similar parameters: Strategy unstable

### Troubleshooting

#### Common Issues

1. **Wine errors**: Ensure Wine is properly configured
   ```bash
   winecfg  # Configure Wine settings
   ```

2. **Compilation errors**: Check MQL5 syntax and dependencies
   ```bash
   wine "C:/Program Files/MetaTrader 5/MetaEditor64.exe" /compile:"EA_PATH"
   ```

3. **Tester crashes**: Reduce optimization parameters or timeout
   - Use narrower parameter ranges
   - Increase timeout settings
   - Use "Full enumeration" for small parameter spaces

4. **No results generated**: Check file permissions and paths
   - Ensure MT5 data directory is writable
   - Verify preset file format

### Advanced Optimization

#### Multi-Timeframe Testing
Test across different timeframes (M15, H1, H4) to find optimal timeframe for the strategy.

#### Multi-Symbol Testing
Test on different currency pairs to identify which pairs work best with PASR strategy.

#### Forward Testing
After backtest optimization, run forward tests on out-of-sample data to validate performance.

#### Walk-Forward Optimization
Use MT5's walk-forward optimization feature for more robust validation.

### Results Analysis

#### Key Metrics to Monitor
1. **Consistency**: Results should be consistent across different time periods
2. **Robustness**: Strategy should perform well on different symbols
3. **Stability**: Similar parameters should produce similar results
4. **Drawdown**: Maximum drawdown should be within acceptable limits

#### Result Files Location
- **MT5 Tester**: `Tester/[Phase_Name]/`
- **Reports**: `MQL5/tools/reports/`
- **Optimization cache**: `Tester/optimization_cache/`

### Next Steps After Optimization

1. **Validate Results**: Run forward tests on recent data
2. **Demo Trading**: Test on demo account for 1-2 weeks
3. **Small Live Test**: Start with minimal risk on live account
4. **Monitor Performance**: Track real-time performance vs backtest
5. **Adjust Parameters**: Fine-tune based on live performance

### Safety Considerations

⚠️ **Important Warnings**:
- Past performance does not guarantee future results
- Always use proper risk management
- Start with small position sizes
- Monitor drawdown levels closely
- Have emergency stop mechanisms in place
- Regular parameter re-optimization may be needed

### Support and Maintenance

#### Regular Tasks
- Weekly performance review
- Monthly parameter re-optimization
- Quarterly strategy health check
- Annual comprehensive backtest

#### Files to Update
- Add new presets to `MQL5/Presets/`
- Update optimization ranges in `.ini` files
- Document successful parameter combinations
- Track performance over time

---

**Generated for PASR_MODULAR v2.15.0**
**Last Updated**: 2026-06-08
**Optimization Framework Version**: 1.0