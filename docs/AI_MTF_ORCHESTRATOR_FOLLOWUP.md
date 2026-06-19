# AIOrchestrator MTF Wiring Notes

This branch now includes the GBR-specific late-fusion path in `CAIOrchestrator::Predict()`.

## Implemented wiring

The orchestrator now does the following when `m_cfg.Signal.UseMTF == true`, GBR is enabled, and a GBR model is loaded:

1. Prebuilds four timeframe-specific `SAIFeatureVector` values:
   - H4
   - H1
   - M15
   - M5

2. Builds those vectors before the main fused `m_feat.Build(fv)` call.
   - This order is intentional because `Build(out)` clears pending Pattern/SR context after the main feature vector is built.
   - Prebuilding preserves context injection for the GBR MTF array.

3. Calls:

```mql5
m_gbr.PredictMTF(gbr_mtf_fv, mtf_result)
```

4. Falls back to:

```mql5
m_gbr.Predict(fv, gbr_score, gbr_conf)
```

if the MTF path cannot be built or inference fails.

## Runtime log markers

When the MTF path is used, debug logs should show:

```text
[AIOrchestrator] GBR MTF prediction: <score> (conf=<confidence>, tf=<n>)
```

The inference result model id should become one of:

```text
ensemble+gbr_mtf
lstm+ensemble+gbr_mtf
```

## Remaining validation

This branch has not been compiled in MetaEditor from here. Validate with:

- `InpUseMTF=true`
- `InpEnableAI=true`
- `InpEnableGBR=true`
- a loaded GBR ONNX model path

Then run a short Strategy Tester pass and confirm the EA compiles and logs the MTF GBR path.
