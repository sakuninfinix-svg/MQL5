//+------------------------------------------------------------------+
//| PASR LAYER 5a — AI                                              |
//|                                                                  |
//| PURPOSE:                                                         |
//|   AI/ML inference layer. Runs ONNX models or native NN for       |
//|   market regime scoring and signal confidence weighting.         |
//|   Training is deferred — NEVER runs synchronously on tick thread.|
//|                                                                  |
//| CONTENTS:                                                        |
//|   AIManager.mqh    — NN inference + async training dispatcher    |
//|                                                                  |
//| FUTURE DECOMPOSITION (v3.0 target):                              |
//|   AIInference.mqh  — Pure inference path (tick-safe, <1ms)       |
//|   AITrainer.mqh    — Backprop + replay buffer (bar-frequency)    |
//|   AIOrchestrator.mqh — Coordinates inference + training          |
//|                                                                  |
//| DEPENDENCY RULES:                                                |
//|   ✅ MAY include   : Core/, Infra/, Analysis/                    |
//|   ❌ MUST NOT include: Signal/, Trade/, UI/                      |
//+------------------------------------------------------------------+
//
// This file is a layer documentation stub — never included.
