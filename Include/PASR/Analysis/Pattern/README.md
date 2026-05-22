//+------------------------------------------------------------------+
//| Include/PASR/Analysis/Pattern/README.md                          |
//|                                                                  |
//| Pattern Recognition Module Documentation                         |
//|                                                                  |
//| CANONICAL PATTERN MODULE LOCATION:                               |
//|   Include/PASR/Analysis/Pattern/                                 |
//|     - PatternManager.mqh   (full implementation)                 |
//|     - PatternTypes.mqh     (enums + structs)                     |
//|                                                                  |
//| ENUM_PATTERN_TYPE Values:                                        |
//|   PATTERN_NONE                = 0  // Tidak ada pola             |
//|   PATTERN_PINBAR              = 1  // Pinbar (reversal)          |
//|   PATTERN_ENGULFING           = 2  // Engulfing (reversal)       |
//|   PATTERN_INSIDE_BAR          = 3  // Inside Bar                 |
//|   PATTERN_INSIDE_BAR_BREAKOUT = 4  // Inside Bar Breakout        |
//|   PATTERN_FAKEY               = 5  // Fakey (false breakout)     |
//|   PATTERN_BOTTOM              = 6  // Tweezer Bottom/Top         |
//|   PATTERN_DOJI                = 7  // Doji (indecision)          |
//|   PATTERN_HARAMI              = 8  // Harami (reversal)          |
//|   PATTERN_OUTSIDE_BAR         = 9  // Outside Bar                |
//|   PATTERN_MORNING_STAR        = 10 // Morning Star (3-candle)    |
//|   PATTERN_EVENING_STAR        = 11 // Evening Star (3-candle)    |
//|                                                                  |
//| Usage:                                                           |
//|   #include <PASR/Analysis/Pattern/PatternManager.mqh>            |
//|   #include <PASR/Analysis/Pattern/PatternTypes.mqh>              |
//|                                                                  |
//| Architecture Notes (v2.01):                                      |
//|   - ENUM_PATTERN_TYPE unified enum replaces separate BULL/BEAR  |
//|   - Direction determined by context (dir parameter in votes)    |
//|   - Regime-aware weighting via CalculateRegimeWeight()          |
//|   - Confluence scoring with multi-pattern aggregation           |
//|   - Backward compatibility aliases provided                     |
//|                                                                  |
//| Migration Note (v2.01):                                          |
//|   - Old EPatternType now typedef'd to ENUM_PATTERN_TYPE         |
//|   - PATTERN_PINBAR_BULL/BEAR aliases map to PATTERN_PINBAR      |
//|   - Direction now in SPatternResult.direction (1 or -1)         |
//|                                                                  |
//+------------------------------------------------------------------+
// (documentation file only)

