//+------------------------------------------------------------------+
//| PASR LAYER 4 — SIGNAL / INTELLIGENCE                            |
//|                                                                  |
//| PURPOSE:                                                         |
//|   Trade signal generation: aggregates analysis from Layer 3,   |
//|   applies AI inference, and produces final SignalResult with    |
//|   direction, confidence, suggested SL/TP, and lot multiplier.  |
//|                                                                  |
//| CONTENTS:                                                        |
//|   SignalManager.mqh  — Aggregates pattern + regime + AI        |
//|                        signals into a final trade decision.    |
//|   AI/                — AI subsystem (decomposed from God Obj)  |
//|     AIOrchestrator.mqh — Coordinates inference vs training     |
//|     AIInference.mqh    — Pure forward-pass on tick thread      |
//|     AITrainer.mqh      — Backprop deferred via EventBus        |
//|                                                                  |
//| DEPENDENCY RULES (STRICT):                                       |
//|   ✅ MAY include   : Core/, Infra/, Analysis/                   |
//|   ❌ MUST NOT include: Trade/, UI/                              |
//|                                                                  |
//| CRITICAL PERFORMANCE RULE:                                       |
//|   AIInference.mqh runs on every tick — it must be O(1)/O(n)    |
//|   with n = fixed layer size. No dynamic allocation on tick.    |
//|   AITrainer.mqh runs on DEFERRED events only (NewBar or idle). |
//|   Backpropagation MUST NOT block the tick thread.              |
//+------------------------------------------------------------------+
//
// Migration status:
//   [ ] SignalManager.mqh  — pending (source: ../5.SignalManager.mqh)
//   [ ] AI/AIOrchestrator  — pending (source: ../7.AIManager.mqh + ../AI/)
//   [ ] AI/AIInference     — pending (decompose from AIOrchestrator)
//   [ ] AI/AITrainer       — pending (decompose backprop from AIOrchestrator)
