# AI Multi-Timeframe Fix Notes

This branch fixes the immediate runtime MTF issues found in the audit.

## Implemented

1. `AIFeatureBuilder` is now timeframe-aware.
   - Indicator handles are initialized with an active `ENUM_TIMEFRAMES` instead of hardcoded `PERIOD_CURRENT`.
   - Price, volume, z-score, skew, and bar-time extraction now use the active timeframe.
   - Added `SetTimeframe()` and `Build(out, tf)` for explicit timeframe extraction.

2. Runtime MTF feature extraction is enabled when `cfg.Signal.UseMTF == true`.
   - Default `Build(out)` now produces a weighted fused feature vector from H4/H1/M15/M5.
   - Weights: H4=0.35, H1=0.30, M15=0.25, M5=0.10.
   - Structural and pattern features are preserved consistently across each timeframe build.

3. `AISignalSource` no longer calls `CAIOrchestrator::Predict()` during `SignalStage`.
   - This removes the double-predict and circular signal-generation/gating loop.
   - AI remains active as a post-signal gate in `AIInferStage`.

## Remaining follow-up

The next cleaner architectural step is to modify `AIOrchestrator` so GBR calls `CGBRInference::PredictMTF()` directly with four separate `SAIFeatureVector` values. This branch already makes runtime AI features MTF-aware without a large orchestrator rewrite.

## Manual checks recommended in MetaEditor

- Compile `Experts/PASR_PRERELEASE.mq5`.
- Run a quick Strategy Tester pass with `InpUseMTF=true` and `InpEnableAI=true`.
- Compare tester logs to confirm AI is evaluated only at `AIInferStage`.
