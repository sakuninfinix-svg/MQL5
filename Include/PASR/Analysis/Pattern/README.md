# Pattern Module - Institutional Grade Architecture v2.0

## 📁 Struktur Folder Baru

```
Pattern/
├── PatternTypes.mqh              # ENUM definitions & type aliases
├── PatternManager.mqh            # Main orchestrator (legacy compatibility)
├── CandleUtils.mqh               # Candle analysis utilities
├── Evaluators.mqh                # Legacy evaluators (deprecated)
├── FakeoutDetector.mqh           # Fakeout detection
├── ScoreEngine.mqh               # Scoring engine
├── Config/
│   └── PatternConfig.mqh         # Dynamic parameter management
├── Context/
│   └── PatternContext.mqh        # Rich context enrichment
├── Strategies/
│   ├── IPatternStrategy.mqh      # Abstract strategy interface
│   ├── PinbarStrategy.mqh        # Pinbar detection strategy
│   ├── EngulfingStrategy.mqh     # Engulfing detection strategy
│   └── PatternStrategyFactory.mqh # Strategy factory & pool
└── README.md                     # This file
```

## 🎯 Peningkatan Arsitektur

### 1. **Strategic Pattern Detection**
- Menggunakan **Strategy Pattern** untuk deteksi yang modular
- Setiap pattern memiliki strategi terpisah yang dapat di-customize
- Mudah menambahkan pattern baru tanpa mengubah kode existing

### 2. **Dynamic Configuration**
```cpp
CPatternConfigManager config;
config.Init();
config.SetRegime(REGIME_TRENDING_STRONG);  // Auto-adjust parameters

SPinbarParams params = config.GetPinbarParams();
params.minTailRatio = 0.7;  // Override if needed
```

### 3. **Context Enrichment**
- **Market Context**: Regime, volatility, trend strength, session
- **Location Context**: S/R confluence, Fibonacci, psychological levels
- **MTF Context**: Multi-timeframe alignment
- **Volume Context**: Volume spikes, divergences, momentum

```cpp
CPatternContext context;
context.Init();

SMarketContext marketCtx;
marketCtx.regime = REGIME_TRENDING_STRONG;
marketCtx.atr = 0.0050;
context.SetMarketContext(marketCtx);

SLocationContext locCtx;
locCtx.nearSupport = true;
locCtx.srStrength = 85.0;
context.SetLocationContext(locCtx);

double totalScore = context.GetTotalContextScore();  // 0-100
```

### 4. **Template Method Pattern**
Base strategy menyediakan workflow standar:
1. CheckPatternShape() → Validasi bentuk pattern
2. CheckPatternLocation() → Validasi lokasi
3. CheckPatternSize() → Validasi ukuran vs volatilitas
4. EvaluatePatternStrength() → Hitung raw score
5. ApplyContextAdjustment() → Adjust dengan context
6. ValidatePattern() → Final validation
7. GetRiskLevels() → Set SL/TP

## 📊 Usage Example

```cpp
#include "Pattern/Strategies/PatternStrategyFactory.mqh"
#include "Pattern/Context/PatternContext.mqh"
#include "Pattern/Config/PatternConfig.mqh"

// Initialize
CPatternConfigManager config;
config.Init();
config.SetRegime(regimeDetector.GetCurrentRegime());

CPatternStrategyFactory factory;
factory.Init(&config);

// Build context
CPatternContext context;
context.Init();
// ... populate context ...

// Detect patterns at current bar
CArrayObj *patterns = factory.DetectAllPatterns(0, context);

// Process results
for(int i = 0; i < patterns.Total(); i++)
{
   SPatternResult *result = (SPatternResult*)patterns.At(i);
   if(result.IsValid())
   {
      Print(result.ToString());
      
      // Get position size modifier
      double sizeMod = context.GetPositionSizeModifier();
      double lots = baseLots * sizeMod;
      
      // Execute trade
      if(result.finalScore >= 75.0 && sizeMod > 0.5)
      {
         Trade(result.direction, result.entryPrice, 
               result.stopLoss, result.takeProfit, lots);
      }
   }
}
```

## 🔧 Migration Guide

### Dari Legacy PatternManager

**Old:**
```cpp
PatternManager pm;
pm.Detect(shift);
```

**New:**
```cpp
CPatternContext context;
// ... build context ...
CArrayObj *results = factory.DetectAllPatterns(shift, context);
```

### Parameter Customization

**Old:** Hardcoded values di Evaluators.mqh

**New:**
```cpp
SPinbarParams params = config.GetPinbarParams();
params.minTailRatio = 0.75;        // Custom threshold
params.requireSRConfluence = true; // Require S/R
params.regimeMultiplier = 1.2;     // Adjust for regime

strategy.SetParameters(params);
```

## 📈 Scoring System

### Raw Score Components
- **Shape Quality**: 0-40 points
- **Size Appropriateness**: 0-20 points  
- **Location Strength**: 0-25 points
- **Prior Context**: 0-15 points

### Context Adjustments
- **S/R Confluence**: +0-20%
- **MTF Alignment**: +0-15%
- **Volume Confirmation**: +0-10%
- **Regime Bonus/Penalty**: ±10%

### Final Grading
- **A+** (90-100): Exceptional setup, full size
- **A** (80-89): High quality, 75-100% size
- **B** (70-79): Good setup, 50-75% size
- **C** (60-69): Marginal, 25-50% size
- **D** (50-59): Weak, consider skipping
- **F** (<50): Reject

## 🚀 Future Enhancements

1. **Inside Bar Strategy** - Belum diimplementasi
2. **Fakey Strategy** - Belum diimplementasi  
3. **Double/Triple Top-Bottom** - Pattern recognition
4. **Harmonic Patterns** - Gartley, Bat, Butterfly
5. **Machine Learning Integration** - AI-based pattern scoring
6. **Backtest Framework** - Built-in pattern performance tracking

## ⚠️ Breaking Changes

- `Evaluators.mqh` sekarang deprecated, gunakan Strategies
- Pattern detection sekarang memerlukan CPatternContext
- Parameters sekarang dinamis berdasarkan regime
- Score sekarang 0-100 scale (bukan arbitrary units)

## 📝 Best Practices

1. **Always use context**: Jangan detect pattern tanpa context
2. **Respect regime**: Parameters auto-adjust, jangan override kecuali perlu
3. **Check MTF alignment**: Higher TF alignment significantly improves win rate
4. **Volume confirmation**: Avoid patterns on low volume
5. **Location matters**: Patterns at S/R perform much better
6. **Size appropriately**: Use GetPositionSizeModifier() untuk dynamic sizing

## 📞 Support

Untuk pertanyaan atau issue, silakan buat ticket di repository PASR Framework.
