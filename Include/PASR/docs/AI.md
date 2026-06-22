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
| 4 | `AIFeatureValidator.mqh` | `CAIFeatureValidator` | Validasi features: NaN/Inf, zero ratio, outlier z-score, ensemble readiness |
| 5 | `MLPModel.mqh` | `CMLPModel` | 2-layer MLP (34→64→32→1), He init, forward, SGD online update |
| 6 | `AIEnsemble.mqh` | `CAIEnsemble` | Multi-model voting ensemble with ONNX integration |
| 7 | `ONNXBridge.mqh` | `CONNXBridge` | ONNX runtime: scalar + sequence inference modes |
| 8 | `AIInference.mqh` | `CAIInference` | Standalone MLP (34→64→32→1), load/save weights, online SGD |
| 9 | `LSTMInference.mqh` | `CLSTMInference` | 2-layer LSTM (hidden=128, seq=50) untuk time series |
| 10 | `AttentionFusion.mqh` | `CAttentionFusion` | 4-head dot-product attention fusion of MLP + LSTM |
| 11 | `ConfidenceCalibrator.mqh` | `CConfidenceCalibrator` | Platt scaling + agreement-weighted calibration |
| 12 | `OnlineLearningGuard.mqh` | `COnlineLearningGuard` | Concept drift detection, feature z-score drift, veto |
| 13 | `AITrainer.mqh` | `CAITrainer` | Ring buffer (500), retrain every 50, online SGD |
| 14 | `AIOrchestrator.mqh` | `CAIOrchestrator` | **Main AI brain**: feature build → validate → ensemble → LSTM → attention → calibrate → drift check → risk decision |
| 15 | `AICalibrationBridge.mqh` | `CAICalibrationBridge` | Sync confidence threshold dengan `CAdaptiveConfig` |
| 16 | `AISignalSource.mqh` | `CAISignalSource` | `ISignalSource` adapter wrapping `CAIOrchestrator` |
| 17 | `AIRetrainTrigger.mqh` | `CAIRetrainTrigger` | Auto retrain: trade counter + weights file change detection |
| 18 | `ModelRegistry.mqh` | `CModelRegistry` | 8-model registry dengan activation, versioning, perf tracking |

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

## MTF Architecture (v2.16.0+)

### GBR MTF Late Fusion (Primary Runtime)

```
AIFeatureBuilder.Build(tf=H4)
AIFeatureBuilder.Build(tf=H1)
AIFeatureBuilder.Build(tf=M15)
AIFeatureBuilder.Build(tf=M5)
        ↓
GBRInference.PredictMTF(fv_array, mtf_result)
        ↓
gbr_score + gbr_confidence
```

Timeframe weights:
- H4 = 0.35 → bias utama / macro structure
- H1 = 0.30 → validasi trend/structure
- M15 = 0.25 → timing setup
- M5 = 0.10 → trigger precision

### Fallback Chain
```
PredictMTF() → Predict(fv_current) → Ensemble Vote → VETO
```

### Model ID Telemetry
Setiap inferensi mengembalikan `model_id`:
- `gbr_mtf` — GBR MTF late fusion aktif
- `gbr_single` — GBR single timeframe fallback
- `ensemble_only` — Ensemble MLP/ONNX only
- `lstm_attention` — LSTM + Attention fusion

## Online Learning Pipeline

```
Trade Close → AIRetrainTrigger.Check() 
    → CAITrainer.AddSample(features, label, weight)
    → Retrain every 50 samples (configurable)
    → Update ensemble weights
    → Persist to disk (PASR_mlp_m0.bin)
```

Labeling: `hit_tp_before_sl` → +1, `hit_sl_before_tp` → -1, else 0

## Regime-Aware Strategy Selection

| Regime | Strategy | Entry Threshold | Risk Multiplier |
|--------|----------|-----------------|-----------------|
| TREND_UP/DOWN | STRAT_TREND_FOLLOW | 0.60 | 1.20 |
| RANGE | STRAT_RANGE_TRADING | 0.65 | 1.10 |
| VOLATILE | STRAT_BREAKOUT | 0.85 | 0.90 |
| CRASH/UNKNOWN | STRAT_CONSERVATIVE | 0.95 | 0.10 |
| TRANSITION | STRAT_SCALP_AI | 0.70 | 1.00 |

## Hard Gates (Priority Order)

1. **Feature Invalid** → NO_TRADE
2. **Regime CRASH/UNKNOWN** → NO_TRADE
3. **Volatility Extreme** → NO_TRADE / reduce risk
4. **MTF Conflict** → NO_TRADE
5. **Pattern Weak** → NO_TRADE
6. **Drift High** → VETO
7. **Confidence < Dynamic Threshold** → NO_TRADE
8. **Expected R < MinExpectedR** → NO_TRADE
9. **Failure Prob > MaxFailureProbability** → NO_TRADE
10. **All Pass** → Confidence fusion determines entry/risk

## Configuration (PASR_PRERELEASE.mq5 Inputs)

```mql5
input group "AI"
input bool   InpEnableAI = false;
input double InpAIMinConfidence = 0.60;
input double InpAILearningRate = 0.0003;
input int    InpAITrainIntervalBars = 5;
input int    InpAIReplayBufferSize = 512;
input int    InpAIMinibatchSize = 32;
input bool   InpAIPersistWeights = true;
input string InpAIModelFileName = "PASR_gbr_m0.bin";
input bool   InpAIEnableOnnx = false;
input string InpAIModelOnnxFileName = "PASR_sequence.onnx";

input group "GBR Configuration"
input bool   InpEnableGBR = true;
input int    InpGBRN_estimators = 150;
input double InpGBRLearning_rate = 0.05;
input int    InpGBRMax_depth = 4;
input double InpGBRMin_samples_split = 0.03;
input double InpGBRMin_samples_leaf = 0.015;
input double InpGBRSubsample = 0.8;
input double InpGBRColsample_bytree = 0.7;
input double InpGBRReg_alpha = 0.05;
input double InpGBRReg_lambda = 0.8;
input double InpGBRGamma = 0.05;
input string InpGBRModelPath = "PASR_gbr_m0.onnx";

input group "AI Regime Thresholds"
input double InpAITrendEntryThreshold = 0.60;
input double InpAITrendRiskMultiplier = 1.20;
input double InpAIRangeEntryThreshold = 0.65;
input double InpAIRangeRiskMultiplier = 1.10;
input double InpAIVolatileEntryThreshold = 0.85;
input double InpAIVolatileRiskMultiplier = 0.90;
input double InpAIConservativeEntryThreshold = 0.95;
input double InpAIConservativeRiskMultiplier = 0.10;
input double InpAIScalpEntryThreshold = 0.70;
input double InpAIScalpRiskMultiplier = 1.00;

input group "AI Decision Rules"
input double InpAIMinExpectedR = 0.50;
input double InpAIMaxFailureProbability = 0.55;
input double InpAIStrongConfidenceBuffer = 0.10;
input double InpAIStrongConfidenceMin = 0.75;
input double InpAIStrongExpectedR = 1.20;
input double InpAIStrongMaxFailureProbability = 0.40;
input double InpAIDriftFailureWeight = 0.35;
input double InpAIRegimeFailureWeight = 0.25;
input double InpAIConfidenceRewardWeight = 2.00;
input double InpAIEdgeRewardWeight = 1.25;
input double InpAIRegimeRewardWeight = 0.75;
input double InpAIFailurePenaltyWeight = 1.40;
input double InpAIRiskFailureWeight = 0.45;
```

## Integration Points

| Stage | Role | AI Component |
|-------|------|--------------|
| `SignalStage` | Technical signal formation | Pattern + SR + Regime (NO AI) |
| `AIInferStage` | AI confidence/gating | AIOrchestrator.PredictSignal() |
| `RiskStage` | Deterministic risk clamp | AI risk_multiplier as input |
| `ExecutionStage` | Order execution | No AI |

**Critical**: AI tidak dipanggil di SignalStage. AI hanya menjadi **filter/gate** setelah sinyal teknikal terbentuk di AIInferStage.

## Training Pipeline (Offline → Online)

### Offline Training (Python)
```
Data Export → Feature Engineering → Labeling → Model Training → ONNX Export → MQL5/Files
```

### Online Training (MQL5 Runtime)
```
Trade Result → AITrainer.AddSample() → Ring Buffer → Retrain (SGD) → Ensemble Update → Persist
```

### Data Export
`PASR_DATA_EXPORTER.mq5` exports:
- OHLCV + indicators per timeframe
- Labels: future_return_R, max_favorable_R, max_adverse_R, hit_tp_before_sl
- Regime labels from HMMRegimeDetector
- Pattern labels from CNNPatternRecognizer

## Deployment Checklist

- [ ] MetaEditor compile: 0 errors
- [ ] `InpEnableAI=false` tidak mengubah jalur trading non-AI
- [ ] GBR MTF model loads atau fallback ke single-TF aman
- [ ] Telemetry `model_id` menunjukkan mode inferensi aktif
- [ ] Online learning tidak mengubah bobot tanpa validasi drift guard
- [ ] Backtest: AI-on vs AI-off → profit factor ≥ baseline setelah cost
- [ ] Max drawdown ≤ baseline + toleransi
- [ ] Trade frequency memadai (daily trades target)