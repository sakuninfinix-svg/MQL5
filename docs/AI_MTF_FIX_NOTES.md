# AI Multi-Timeframe Fix Notes

This branch fixes the immediate runtime MTF issues found in the audit and wires GBR into the explicit MTF inference path.

## Implemented

1. `AIFeatureBuilder` is now timeframe-aware.
   - Indicator handles are initialized with an active `ENUM_TIMEFRAMES` instead of hardcoded `PERIOD_CURRENT`.
   - Price, volume, z-score, skew, and bar-time extraction now use the active timeframe.
   - Added `SetTimeframe()` and `Build(out, tf)` for explicit timeframe extraction.

2. Runtime MTF feature extraction is enabled when `cfg.Signal.UseMTF == true`.
   - Default `Build(out)` now produces a weighted fused feature vector from H4/H1/M15/M5.
   - Weights: H4=0.35, H1=0.30, M15=0.25, M5=0.10.
   - Structural and pattern features are preserved consistently across each timeframe build.

3. `AIOrchestrator` now routes GBR through `CGBRInference::PredictMTF()` when MTF is enabled.
   - It prebuilds H4/H1/M15/M5 feature vectors before the main fused feature build so pending Pattern/SR context is not lost.
   - It falls back to single-vector `Predict(fv, ...)` if the MTF path is unavailable.
   - `model_id` now reports `ensemble+gbr_mtf` or `lstm+ensemble+gbr_mtf` when the MTF path is used.

4. `AISignalSource` no longer calls `CAIOrchestrator::Predict()` during `SignalStage`.
   - This removes the double-predict and circular signal-generation/gating loop.
   - AI remains active as a post-signal gate in `AIInferStage`.

## Manual checks recommended in MetaEditor

- Compile `Experts/PASR_PRERELEASE.mq5`.
- Run a quick Strategy Tester pass with `InpUseMTF=true`, `InpEnableAI=true`, and `InpEnableGBR=true`.
- Check tester logs for `[AIOrchestrator] GBR MTF prediction` and `model_id` values ending in `gbr_mtf`.
- Confirm AI prediction happens only at `AIInferStage`, not `SignalStage`.
