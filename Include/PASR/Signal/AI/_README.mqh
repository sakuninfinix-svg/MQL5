//+------------------------------------------------------------------+
//| PASR LAYER 5b — AI/ML INFERENCE (26-DIM FEATURE SYSTEM)          |
//|                                                                  |
//| PURPOSE:                                                         |
//|   AI/ML inference layer. Runs ONNX models or native NN for       |
//|   market regime scoring and signal confidence weighting.         |
//|   Training is deferred — NEVER runs synchronously on tick thread.|
//|                                                                  |
//| ARCHITECTURE v4.01:                                              |
//|   - 26-dimensional feature vector (F01-F26)                      |
//|   - Expert routing (Trend/MeanReversion/Momentum)                |
//|   - Dual-path inference: Neural Net + Linear Expert Model        |
//|   - Drift detection via FeatureEngine statistical analysis       |
//|                                                                  |
//| CONTENTS (14 files):                                             |
//|   AITypes.mqh            — Core types, enums, structs (26-dim)   |
//|   FeatureEngine.mqh      — Advanced stats (Z-score, skew, kurt)  |
//|   AIFeatureBuilder.mqh   — 26-dim feature engineering pipeline   |
//|   AIInference.mqh        — Expert routing + forward pass (<1ms)  |
//|   AIOrchestrator.mqh     — CAIOrchestrator: model mgmt + infer   |
//|   AISignalSource.mqh     — Bridge: CAIOrchestrator → ISignalSource |\n//|   AITrainer.mqh          — Backprop + replay buffer (bar-freq)   |
//|   ConfidenceCalibrator.mqh — Platt scaling + probability calibration |
//|   AICalibrationBridge.mqh — Calibration ↔ Inference bridge       |
//|   AIEnsemble.mqh         — Multi-model ensemble voting           |
//|   ModelRegistry.mqh      — Model lifecycle management            |
//|   ONNXBridge.mqh         — ONNX model loader interface           |
//|   OnlineLearningGuard.mqh — Safe online learning constraints     |
//|                                                                  |
//| DEPENDENCY RULES:                                                |
//|   ✅ MAY include   : Core/, Infra/, Analysis/, Data/             |
//|   ❌ MUST NOT include: Signal/, Trade/, UI/ (except AISignalSource) |
//|                                                                  |
//| ARCHITECTURE v4.02 (CLEAN):                                      |
//|   - AIManager REMOVED (was deprecated 8-dim legacy system)       |
//|   - Single AI system: CAIOrchestrator with 26-dim features       |
//|   - All components migrated to modern architecture               |
//+------------------------------------------------------------------+
//
// This file is a layer documentation stub — never included.
