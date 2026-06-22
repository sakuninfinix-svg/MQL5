# PASR Training Tools

This folder contains the active training pipeline for `PASR_PRERELEASE.mq5`.

## Active Pipeline

1. Run `PASR_DATA_EXPORTER.mq5` in MT5 Strategy Tester to export:
   - `PASR_trades_export.csv`
   - `PASR_ohlcv_export.csv`
2. Place both files in `MQL5/tools/output/`.
3. Run:

```bash
bash training/run_pipeline.sh
```

The pipeline imports real MT5 trades, recomputes 34 runtime-compatible AI features, trains the MLP as `34->64->32->1`, and writes `PASR_mlp_m*.bin` for `AIInference.mqh`.

## Runtime Alignment Notes

- `PASR_PRERELEASE.mq5` uses `PASR_mlp_m0.bin` as the default offline MLP weights file, and `AIEnsemble.mqh` loads the matching `PASR_mlp_m*.bin` files when present.
- GBR is disabled by default until a real `PASR_gbr_m0.onnx` trainer/export path exists.
- `PASR_DATA_EXPORTER.mq5` exports real MT5 trades and OHLCV, but its entry generator is a simple MA/ATR strategy. For production-grade labels, export trade history from the actual `PASR_PRERELEASE.mq5` strategy run or update the exporter to mirror the EA signal pipeline.

## Active Files

- `PASR_DATA_EXPORTER.mq5`: MT5 Strategy Tester exporter.
- `real_feature_extractor.py`: 34-feature extractor aligned to `AIFeatureBuilder.mqh`.
- `import_mt5_trades.py`: builds `output/MT5_Training_Data.csv` from real MT5 exports.
- `preprocess_ai_training_data.py`: optional CSV validation/preprocessing.
- `train_mlp_classifier.py`: exports `PASR_mlp_m*.bin` compatible with `AIInference.mqh`.
- `calibrate_numpy.py`: optional confidence calibration export.
- `auto_retrain.py` and `watch_trades.sh`: real-data retraining workflow.
- `tune_regression_scorer.py` and scorer-specific trainers: auxiliary scorer weights.

## Archived

`archive/` contains legacy synthetic simulators and experimental direction/volatility research. They are kept for reference, but they are not part of the active EA training pipeline.
