# Pattern Subsystem — Architecture Guide

> Refactored from `9.PatternManager.mqh` (42 KB monolith) → 6 focused modules.

## Folder Structure

```
Include/PASR/Pattern/
├── PatternTypes.mqh      — Enums, structs, PatternWeights, PatternVote
├── CandleUtils.mqh       — Pure static candle math (zero dependencies)
├── ScoreEngine.mqh       — Scoring: Intrinsic/Context/Momentum/Confluence/Normalize
├── Evaluators.mqh        — 10 pattern evaluator implementations
├── FakeoutDetector.mqh   — Stop-hunt / fakeout detection
├── PatternManager.mqh    — Orchestrator: Evaluate() + Detect() legacy wrapper
└── README.md             — This file
```

## Dependency Graph (strictly layered, no cycles)

```
Config.Types
    └── PatternTypes
            ├── CandleUtils          (no upward deps)
            │       └── ScoreEngine  (depends: PatternTypes + CandleUtils)
            │               └── Evaluators  (depends: all above)
            ├── FakeoutDetector      (depends: PatternTypes only)
            └── PatternManager       (orchestrator — depends on all layers)
```

## SRP Responsibility Map

| File | One Responsibility |
|------|--------------------|
| `PatternTypes.mqh` | Data contracts (structs/enums) |
| `CandleUtils.mqh` | Candle geometry math |
| `ScoreEngine.mqh` | Score computation & normalisation |
| `Evaluators.mqh` | Pattern detection logic |
| `FakeoutDetector.mqh` | Fakeout / SL-hunt detection |
| `PatternManager.mqh` | Orchestration + public API |

## How to Use

```cpp
// Include only the orchestrator — it transitively includes everything
#include <PASR/Pattern/PatternManager.mqh>

// Then call:
PatternWeights weights;            // uses default weights
PatternResult r = PatternManager::Evaluate(cfg, rates, shift, atrValue, weights);
if (r.IsActionable()) { ... }
```

## How to Add a New Pattern

1. Add its `ENUM_PATTERN_TYPE` value to `2.Config.Types.mqh`.
2. Add its weight field to `PatternWeights` in `PatternTypes.mqh`.
3. Implement `static void MyPattern(...)` in `Evaluators.mqh` following the existing template.
4. Register it in `PatternManager::Evaluate()` — extend the `votes[]` array to `[11]` and add one `Evaluators::MyPattern(...)` call.
5. No other files need to change.

## Bugs Fixed (carried over from v2.02)

- **PM-BUG-1** `EvaluateMorningStar`: missing `return` after `dir==0` — preserved in `Evaluators::MorningStar`.
- **PM-BUG-4** Array-bound guard corrected to `shift<2 || (shift+2)>=ArraySize` — in `PatternManager::Evaluate`.
