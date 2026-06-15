# AI Module (`PASR/AI/`)

18 files — Machine Learning subsystem untuk trading signals.

## Arsitektur

```
AITypes (structs/enums)
  ├── MLPModel (Multi-Layer Perceptron)
  ├── LSTMInference (LSTM time series)
  ├── ONNXBridge (ONNX runtime wrapper)
  ├── AttentionFusion (attention-based fusion)
  ├── AIEnsemble (voting ensemble)
  │     ├── MLPModel × N
  │     └── ONNXBridge (optional)
  ├── AIFeatureBuilder (34-dim features)
  ├── SequenceFeatureBuilder (64×12 tensor)
  ├── AIFeatureValidator (quality checks)
  ├── AIInference (standalone MLP)
  ├── ConfidenceCalibrator (Platt scaling)
  ├── OnlineLearningGuard (drift detection)
  ├── AITrainer (online SGD training)
  ├── AIOrchestrator (main AI brain)
  │     └── all components above
  ├── AISignalSource (ISignalSource adapter)
  ├── AICalibrationBridge (AdaptiveConfig bridge)
  ├── AIRetrainTrigger (auto retrain)
  └── ModelRegistry (model lifecycle)
```

## File Reference

| # | File | Class | Fungsi |
|---|------|-------|--------|
| 1 | `AITypes.mqh` | — | Structs: `SAIInferenceResult`, `SAIFeatureVector`, `SAISequenceTensor`, `SAITrainSample`, `SAIEnsembleVote`, `SAIModelPerf`, `SAIRiskDecision`, `SAITradeLabel`. Enums: `ENUM_AI_MODEL_TYPE`, `ENUM_AI_DECISION_CLASS`, `ENUM_AI_LABEL_CLASS`, `EActiveStrategy` |
| 2 | `AIFeatureBuilder.mqh` | `CAIFeatureBuilder` | Build 34-dim feature vector (RSI, MACD, CCI, Stoch, MFI, ATRs, volume, price returns, z-score, skew, pattern, regime, time) |
| 3 | `SequenceFeatureBuilder.mqh` | `CSequenceFeatureBuilder` | Build 64×12 sequence tensor for Transformer/ONNX |
| 4 | `AIFeatureValidator.mqh` | `CAIFeatureValidator` | Validate features: NaN/Inf, zero ratio, outlier z-score, ensemble readiness |
| 5 | `MLPModel.mqh` | `CMLPModel` | 2-layer MLP (34→64→32→1), He init, forward, SGD online update |
| 6 | `AIEnsemble.mqh` | `CAIEnsemble` | Multi-model voting ensemble with ONNX integration |
| 7 | `ONNXBridge.mqh` | `CONNXBridge` | ONNX runtime: scalar + sequence inference modes |
| 8 | `AIInference.mqh` | `CAIInference` | Standalone MLP (34→64→32→1), load/save weights, online SGD |
| 9 | `LSTMInference.mqh` | `CLSTMInference` | 2-layer LSTM (hidden=128, seq=50) for time series |
| 10 | `AttentionFusion.mqh` | `CAttentionFusion` | 4-head dot-product attention fusion of MLP + LSTM |
| 11 | `ConfidenceCalibrator.mqh` | `CConfidenceCalibrator` | Platt scaling + agreement-weighted calibration |
| 12 | `OnlineLearningGuard.mqh` | `COnlineLearningGuard` | Concept drift detection, feature z-score drift, veto |
| 13 | `AITrainer.mqh` | `CAITrainer` | Ring buffer (500), retrain every 50, online SGD |
| 14 | `AIOrchestrator.mqh` | `CAIOrchestrator` | **Main AI brain**: feature build → validate → ensemble → LSTM → attention → calibrate → drift check → risk decision |
| 15 | `AICalibrationBridge.mqh` | `CAICalibrationBridge` | Sync confidence threshold with `CAdaptiveConfig` |
| 16 | `AISignalSource.mqh` | `CAISignalSource` | `ISignalSource` adapter wrapping `CAIOrchestrator` |
| 17 | `AIRetrainTrigger.mqh` | `CAIRetrainTrigger` | Auto retrain: trade counter + weights file change detection |
| 18 | `ModelRegistry.mqh` | `CModelRegistry` | 8-model registry with activation, versioning, perf tracking |

## Constants

| Constant | Value | Keterangan |
|----------|-------|------------|
| `AI_FEATURE_DIM` | 34 | Dimensi feature vector |
| `AI_SEQ_LEN` | 64 | Sequence length untuk LSTM/ONNX |
| `ENSEMBLE_MODEL_COUNT` | 3 | Jumlah model dalam ensemble |
| `MLP_HIDDEN1` | 64 | Hidden layer 1 size |
| `MLP_HIDDEN2` | 32 | Hidden layer 2 size |
| `LSTM_HIDDEN_SIZE` | 128 | LSTM hidden state |
| `LSTM_SEQUENCE_LENGTH` | 50 | LSTM sequence buffer |
| `ATTN_HEAD_DIM` | 16 | Attention head dimension |
| `ATTN_NUM_HEADS` | 4 | Number of attention heads |
| `AI_DEFAULT_CONF_THRESHOLD` | 0.55 | Confidence threshold default |
| `TRAINER_MAX_SAMPLES` | 500 | Max training samples |
| `TRAINER_RETRAIN_EVERY` | 50 | Retrain interval |
| `GUARD_WINDOW` | 100 | Drift reference window |

## Pipeline Inference Flow (AIOrchestrator)

```
Predict()
  1. Build features (scalar + sequence)
  2. Validate features (NaN/Inf/outlier)
  3. Compute drift score (OnlineLearningGuard)
  4. Ensemble vote (MLPs + optional ONNX)
  5. LSTM forward pass
  6. Attention fusion (MLP + LSTM)
  7. Calibrate confidence (Platt scaling + agreement)
  8. Validate result (veto if drift too high)
  9. Return SAIInferenceResult

PredictDecision()
  → Predict() + risk analysis (expected R, failure prob, SL/TP)

PredictSignal()
  → PredictDecision() + SSignal construction (entry, SL, TP)
```
