# PASR_MODULAR AI Training Data Guide
## Comprehensive Guide for Preparing AI Training Data

### 📋 Overview
Guide ini menjelaskan cara mengisi template data training untuk sistem AI PASR_MODULAR. Sistem AI menggunakan 34 dimensi feature untuk membuat keputusan trading yang cerdas.

### 🎯 Target Training Data
- **Minimum**: 500-1000 samples untuk basic training
- **Optimal**: 5000+ samples untuk robust performance  
- **Ideal**: 10,000+ samples untuk production-grade AI
- **Balance**: Campuran profitable (label=1.0) dan unprofitable (label=-1.0) trades

### 📊 Feature Dimensions Explained (34 Total)

#### **Price Returns (Features 0-3)**
Measure price change over different periods, normalized to -1 to 1 range.

```csv
f0: Price return 1 bar back   (Current close - Close 1 bar ago) / Close 1 bar ago
f1: Price return 2 bars back  (Current close - Close 2 bars ago) / Close 2 bars ago  
f2: Price return 3 bars back  (Current close - Close 3 bars ago) / Close 3 bars ago
f3: Price return 5 bars back  (Current close - Close 5 bars ago) / Close 5 bars ago
```

**Calculation Example**:
```
Current close: 1.1000
Close 1 bar ago: 1.0995
f0 = (1.1000 - 1.0995) / 1.0995 = 0.00045 / 1.0995 ≈ 0.0004
Normalized to 0.05 range: f0_normalized = 0.0004 / 0.05 = 0.008 → ~0.01
```

**Normalization**: Divide by 0.05 (5% typical max move) and clamp to -1 to 1

#### **ATR Ratios (Features 4-7)**
Current ATR relative to historical baseline, normalized to 0-1 range.

```csv
f4: ATR ratio 3 period
f5: ATR ratio 5 period
f6: ATR ratio 10 period  
f7: ATR ratio 20 period
```

**Calculation**:
```
ATR_current / ATR_baseline, then normalize to 0-1 by dividing by 3.0
Example: ATR_current = 0.0015, ATR_baseline = 0.0010
f4 = (0.0015 / 0.0010) / 3.0 = 1.5 / 3.0 = 0.5
```

#### **Technical Indicators (Features 8-11)**
Standard technical indicators normalized to 0-1 range.

```csv
f8:  RSI (0-100) → normalize to 0-1: RSI/100
f9:  MACD histogram normalized by ATR
f10: CCI (-200 to +200) → normalize to 0-1: (CCI+200)/400
f11: Stochastic (0-100) → normalize to 0-1: Stoch/100
```

**RSI Example**:
```
RSI = 65 → f8 = 65/100 = 0.65
```

**MACD Histogram Example**:
```
MACD_hist = 0.0002, ATR_baseline = 0.0010
f9 = (0.0002 / 0.0010) * 0.5 + 0.5 = 0.2 * 0.5 + 0.5 = 0.6
```

#### **Volume Analysis (Features 12-15)**
Volume-based features to detect market participation.

```csv
f12: Volume ratio (current vol / previous vol)
f13: OBV delta normalized by volume baseline
f14: Volume spike detection (1 if vol > 2x baseline, else 0)
f15: MFI (0-100) → normalize to 0-1: MFI/100
```

**Volume Ratio Example**:
```
Current volume = 150, Previous volume = 100
f12 = min(150/100 / 5.0, 1.0) = min(1.5 / 5.0, 1.0) = min(0.3, 1.0) = 0.3
```

#### **Structure Features (Features 16-18)**
Support/Resistance quality metrics.

```csv
f16: SR distance normalized (0 = far, 1 = very close)
f17: Zone strength normalized (0 = weak, 1 = very strong)
f18: Pattern score normalized (0 = low quality, 1 = high quality)
```

**SR Distance Example**:
```
Distance to nearest SR = 50 pips, ATR = 100 pips
f16 = 1.0 - min(50/100, 1.0) = 1.0 - 0.5 = 0.5
```

#### **Market Regime (Features 19-21)**
One-hot encoded market regime classification.

```csv
f19: Trend regime (1 if TREND_UP or TREND_DOWN, else 0)
f20: Range regime (1 if RANGE, else 0)
f21: Volatile regime (1 if VOLATILE or CRASH, else 0)
```

**Example - Trend Market**:
```
f19 = 1.0, f20 = 0.0, f21 = 0.0
```

**Example - Range Market**:
```
f19 = 0.0, f20 = 1.0, f21 = 0.0
```

#### **Time Features (Features 22-23)**
Temporal patterns for intraday/weekly effects.

```csv
f22: Hour of day (0-23) → normalize to 0-1: hour/23
f23: Day of week (0-6, Mon=0) → normalize to 0-1: day/6
```

**Example**:
```
Time: 14:00 (2 PM) → f22 = 14/23 = 0.61
Day: Wednesday (day 2) → f23 = 2/6 = 0.33
```

#### **Statistical Features (Features 24-25)**
Price distribution characteristics.

```csv
f24: Z-score of price over last 20 bars, normalized to -1 to 1
f25: Return skewness over last 20 bars, normalized to -1 to 1
```

**Z-Score Example**:
```
Current price = 1.1000, 20-bar mean = 1.0990, std = 0.0010
z = (1.1000 - 1.0990) / 0.0010 = 1.0
f24 = max(-1.0, min(1.0, 1.0/3.0)) = 0.33
```

#### **Advanced Pattern Features (Features 26-33)**
Pattern recognition metrics from price action analysis.

```csv
f26: Pattern buy probability (0-1)
f27: Pattern sell probability (0-1)
f28: Pattern conflict indicator (0-1, higher = more conflict)
f29: Pattern dominance gap (0-1)
f30: Pattern rejection quality (0-1)
f31: Pattern trap quality (0-1)
f32: Pattern reclaim quality (0-1)
f33: Pattern follow-through (0-1)
```

These features come from advanced pattern recognition system. If you don't have pattern recognition system, set all to 0.5 (neutral).

### 🏷️ Label Assignment

**Label Values**:
```csv
1.0: Profitable trade (good trade)
-1.0: Unprofitable trade (bad trade)
0.0: No trade (should have stayed out)
```

**Label Assignment Logic**:
```
IF trade was profitable AND hit TP before SL:
    label = 1.0
ELSE IF trade was unprofitable AND hit SL before TP:
    label = -1.0
ELSE IF no trade was taken:
    label = 0.0
ELSE:
    label = (profit > 0) ? 1.0 : -1.0
```

### ⚖️ Weight Assignment

**Weight Purpose**: Give more importance to certain samples during training.

**Weight Guidelines**:
```csv
0.1-0.5: Low importance (noise, uncertain signals)
0.5-1.0: Normal importance (standard trades)
1.0-1.5: High importance (clear, high-confidence signals)
1.5-2.0: Very high importance (exceptional trade setups)
```

**Weight Calculation Formula**:
```
weight = confidence + abs(realized_R) * 0.25
weight = clamp(weight, 0.1, 2.0)
```

**Example**:
```
AI confidence at entry: 0.75
Realized R-multiple: 2.0
weight = 0.75 + 2.0 * 0.25 = 0.75 + 0.5 = 1.25
```

### 📅 Metadata Fields

```csv
timestamp: Unix timestamp or ISO format (2024-06-01 14:30:00)
symbol: Currency pair (EURUSD, GBPUSD, etc.)
timeframe: Timeframe (M1, M5, M15, H1, H4, D1)
label: Training label (1.0, -1.0, 0.0)
weight: Sample importance (0.1-2.0)
regime: Market regime (TREND_UP, RANGE, VOLATILE, CRASH)
trade_type: Trade direction (BUY, SELL, NO_TRADE)
profit_pips: Actual profit/loss in pips (if available)
duration_bars: Trade duration in bars (if available)
notes: Additional context or comments
```

### 🔄 Data Collection Process

#### **Method 1: Manual Collection**
1. Run EA in demo/simulation mode
2. Record market conditions at each signal
3. Track trade outcomes
4. Calculate feature values manually
5. Fill in template

#### **Method 2: Automated Collection**
1. Enable AI logging in EA configuration
2. Run EA in data collection mode
3. Export logs to CSV format
4. Post-process to match template format

#### **Method 3: Historical Backtest**
1. Run Strategy Tester on historical data
2. Export trade results with market conditions
3. Calculate features for each trade entry point
4. Label based on trade outcomes

### 🧪 Feature Calculation Examples

#### **Complete Example - Trend Following Buy Trade**

```csv
# Market conditions at signal time
Price: EURUSD 1.1000
Previous closes: [1.0995, 1.0990, 1.0988, 1.0980]
ATR (14): 0.0010
RSI: 65
MACD hist: 0.0002
CCI: 50
Stochastic: 70
Current volume: 150, Previous: 100
MFI: 60
SR distance: 50 pips
Zone strength: 0.8
Pattern score: 0.75
Regime: TREND_UP
Time: 14:00 Wednesday
20-bar Z-score: 1.0
20-bar skewness: 0.3
Pattern features: [0.7, 0.3, 0.2, 0.4, 0.6, 0.3, 0.5, 0.7]

# Feature calculations
f0 = (1.1000-1.0995)/1.0995/0.05 = 0.008/0.05 = 0.16 → ~0.2
f1 = (1.1000-1.0990)/1.0990/0.05 = 0.018/0.05 = 0.36 → ~0.4
f2 = (1.1000-1.0988)/1.0988/0.05 = 0.022/0.05 = 0.44 → ~0.4
f3 = (1.1000-1.0980)/1.0980/0.05 = 0.036/0.05 = 0.72 → ~0.7
f4-f7: ATR ratios = [0.6, 0.5, 0.4, 0.8] (example)
f8 = 65/100 = 0.65 → ~0.7
f9 = 0.0002/0.0010*0.5+0.5 = 0.6
f10 = (50+200)/400 = 0.625 → ~0.6
f11 = 70/100 = 0.7
f12 = min(150/100/5.0, 1.0) = 0.3
f13-f15: Volume features = [0.5, 0.2, 0.6] (example)
f16 = 1.0 - 50/100 = 0.5
f17 = 0.8
f18 = 0.75 → ~0.8
f19-f21: [1.0, 0.0, 0.0] (trend regime)
f22 = 14/23 = 0.61 → ~0.6
f23 = 2/6 = 0.33 → ~0.3
f24 = 1.0/3.0 = 0.33 → ~0.3
f25 = 0.3/3.0 = 0.1 → ~0.1
f26-f33: Pattern features as given

# Result (if trade was profitable)
0.2,0.4,0.4,0.7,0.6,0.5,0.4,0.8,0.7,0.6,0.6,0.7,0.3,0.5,0.2,0.6,0.5,0.8,0.8,1.0,0.0,0.0,0.6,0.3,0.3,0.1,0.7,0.3,0.2,0.4,0.6,0.3,0.5,0.7,1714521600,EURUSD,H1,1.0,1.25,TREND_UP,BUY,45.5,12,Strong trend following setup
```

### ⚠️ Important Guidelines

**Data Quality**:
- Ensure feature values are properly normalized (0-1 range for most)
- Remove duplicate samples
- Handle missing values (set to 0.5 for neutral)
- Balance positive/negative samples

**Time Period Coverage**:
- Include data from different market conditions
- Cover multiple currency pairs if possible
- Span different timeframes
- Include both trending and ranging periods

**Label Accuracy**:
- Ensure labels reflect actual trade outcomes
- Use realistic profit/loss values
- Include both successful and failed trades
- Don't cherry-pick only profitable trades

**Feature Consistency**:
- Use same calculation method for all samples
- Normalize consistently across all data
- Document any special cases or exceptions
- Validate feature ranges before training

### 📈 Data Validation Checklist

Before using training data:
- [ ] All 44 columns present per row
- [ ] Feature values in valid ranges (mostly 0-1)
- [ ] Labels are 1.0, -1.0, or 0.0 only
- [ ] Weights in range 0.1-2.0
- [ ] Timestamps are valid
- [ ] Symbol names are consistent
- [ ] No missing values (or handled properly)
- [ ] Balanced class distribution
- [ ] Sufficient sample size (>500)
- [ ] Multiple market conditions represented

### 🚀 Next Steps

1. **Collect initial dataset** (500-1000 samples minimum)
2. **Validate data quality** using checklist above
3. **Preprocess data** using provided script
4. **Train AI model** using configuration file
5. **Validate performance** on test set
6. **Iterate and improve** with more data

---

**Generated for PASR_MODULAR v2.15.0 AI Training System**
**Framework Version**: 1.0
**Last Updated**: 2026-06-08