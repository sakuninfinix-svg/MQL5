# Analysis/Pattern/ — Per-Pattern Class Scaffold

> Status: Reserved for future refactoring sprint

## Purpose

This directory is a scaffold placeholder for the future split of
`Analysis/PatternManager.mqh` into individual pattern detector classes.

## Planned Structure

```
Pattern/
  IPatternDetector.mqh         — interface: Detect(bars[], &result)
  Detectors/
    BullishEngulfing.mqh
    BearishEngulfing.mqh  
    PinBar.mqh
    InsideBar.mqh
    MorningStar.mqh
    EveningStar.mqh
    ThreeWhiteSoldiers.mqh
    ThreeBlackCrows.mqh
    Doji.mqh
    HammerHangingMan.mqh
```

## Current State

All pattern detection logic currently lives in `../PatternManager.mqh`.
Do NOT split prematurely — wait until PatternManager exceeds ~500 lines
or when adding >3 new pattern types.

## Migration Trigger

When PatternManager.mqh > 500 lines OR pattern count > 10:
1. Create `IPatternDetector.mqh` interface
2. Move each pattern to its own `Detectors/XYZ.mqh`
3. PatternManager becomes a registry+aggregator
4. Update PipelineEngine Stage_PatternRec accordingly
