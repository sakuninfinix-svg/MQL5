//+------------------------------------------------------------------+
//| Include/PASR/Analysis/Pattern/README.md                          |
//|                                                                  |
//| Pattern Recognition Module Documentation                         |
//|                                                                  |
//+------------------------------------------------------------------+

## 📁 Struktur File

```
/Include/PASR/Analysis/Pattern/
├── PatternTypes.mqh        # ENUM_PATTERN_TYPE dan struktur data
├── CandleUtils.mqh         # [BARU] Utility fungsi candlestick
├── Evaluators.mqh          # [BARU] Class evaluator untuk setiap pattern
├── FakeoutDetector.mqh     # [BARU] Deteksi false breakout & liquidity grab
├── ScoreEngine.mqh         # [BARU] Engine scoring terpusat
├── PatternManager.mqh      # Manager utama (menggunakan semua modul di atas)
└── README.md               # Dokumentasi ini
```

## 📊 ENUM_PATTERN_TYPE Values

| Enum Value | Name | Description |
|------------|------|-------------|
| 0 | PATTERN_NONE | Tidak ada pola |
| 1 | PATTERN_PINBAR | Pinbar (reversal) |
| 2 | PATTERN_ENGULFING | Engulfing (reversal) |
| 3 | PATTERN_INSIDE_BAR | Inside Bar |
| 4 | PATTERN_INSIDE_BAR_BREAKOUT | Inside Bar Breakout |
| 5 | PATTERN_FAKEY | Fakey (false breakout) |
| 6 | PATTERN_BOTTOM | Tweezer Bottom/Top |
| 7 | PATTERN_DOJI | Doji (indecision) |
| 8 | PATTERN_HARAMI | Harami (reversal) |
| 9 | PATTERN_OUTSIDE_BAR | Outside Bar |
| 10 | PATTERN_MORNING_STAR | Morning Star (3-candle) |
| 11 | PATTERN_EVENING_STAR | Evening Star (3-candle) |

## 🔧 Usage

```mql5
#include <PASR/Analysis/Pattern/PatternManager.mqh>
#include <PASR/Analysis/Pattern/PatternTypes.mqh>
#include <PASR/Analysis/Pattern/CandleUtils.mqh>
#include <PASR/Analysis/Pattern/Evaluators.mqh>
#include <PASR/Analysis/Pattern/FakeoutDetector.mqh>
#include <PASR/Analysis/Pattern/ScoreEngine.mqh>
```

## 🏗️ Architecture Notes (v2.01)

### New Modules Added:

1. **CandleUtils.mqh** - Utility functions for candlestick analysis
   - Basic OHLC accessors with bounds checking
   - Derived metrics (range, body, wicks)
   - Pattern helpers (IsInsideBar, IsOutsideBar, IsDoji)
   - ATR normalization utilities
   - Multi-candle comparison functions

2. **Evaluators.mqh** - Object-oriented pattern evaluators
   - Base class `CPatternEvaluator` with common scoring logic
   - Specific evaluators: `CPinbarEvaluator`, `CEngulfingEvaluator`, `CTweezerEvaluator`, `CFakeyEvaluator`, `CInsideBarEvaluator`
   - Regime-aware weighting built-in
   - Rejection and follow-through strength modifiers

3. **FakeoutDetector.mqh** - Advanced false breakout detection
   - Liquidity Grab patterns
   - False Breakout at Support/Resistance
   - Wyckoff Spring/Upthrust patterns
   - Configurable strength thresholds

4. **ScoreEngine.mqh** - Unified scoring system
   - Multi-component scoring (pattern, rejection, momentum, location, regime, volume, confluence)
   - Normalized 0-10 scale with letter grades (A+ to F)
   - Configurable weights for each component
   - Signal strength classifiers (Strong/Moderate/Weak)

### Core Principles:
- ENUM_PATTERN_TYPE unified enum replaces separate BULL/BEAR enums
- Direction determined by context (dir parameter in votes)
- Regime-aware weighting via CalculateRegimeWeight()
- Confluence scoring with multi-pattern aggregation
- Backward compatibility aliases provided

## 📝 Migration Note (v2.01)

- Old EPatternType now typedef'd to ENUM_PATTERN_TYPE
- PATTERN_PINBAR_BULL/BEAR aliases map to PATTERN_PINBAR
- Direction now in SPatternResult.direction (1 or -1)
- New modular architecture allows swapping evaluators
- ScoreEngine provides consistent scoring across all patterns

## 🎯 Example Usage

```mql5
// Initialize components
CPatternManager patternMgr;
CScoreEngine scoreEngine;
CFakeoutDetector fakeoutDetector;

patternMgr.Initialize();
scoreEngine.SetMinValidScore(1.6);
fakeoutDetector.SetMinStrength(0.6);

// Detect patterns
SPatternResult result;
if(patternMgr.Detect(rates, shift, atrPoints, regime, result))
{
   if(result.found)
   {
      // Calculate detailed score
      SScoreComponents components;
      components.patternScore = scoreEngine.CalculatePatternScore(result.type, result.confluenceScore);
      components.rejectionScore = scoreEngine.CalculateRejectionScore(rates, shift, result.direction);
      components.momentumScore = scoreEngine.CalculateMomentumScore(rates, shift, result.direction);
      
      SFinalScore final = scoreEngine.Calculate(components);
      
      if(final.isValid && final.grade >= "B")
      {
         // High quality signal - consider trading
      }
   }
}

// Check for fakeouts
SFakeoutResult fakeout;
if(fakeoutDetector.Detect(rates, shift, fakeout))
{
   if(fakeout.isFakeout && fakeout.strength >= 0.7)
   {
      // Strong fakeout signal detected
   }
}
```

