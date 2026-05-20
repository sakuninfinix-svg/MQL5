//+------------------------------------------------------------------+
//| PASR LAYER 3 — ANALYSIS/PATTERN SUBLAYER                        |
//|                                                                  |
//| PURPOSE:                                                         |
//|   Candlestick and price action pattern detection engine.        |
//|                                                                  |
//| CONTENTS:                                                        |
//|   PatternManager.mqh — Orchestrator. Owns all evaluators.      |
//|                        Called by SignalManager via interface.   |
//|   Evaluators.mqh     — One evaluation function per pattern.    |
//|                        Pure logic: input = OHLCV array.        |
//|                        Output = PatternResult struct.          |
//|   ScoreEngine.mqh    — Scores and ranks PatternResult set.     |
//|                        Applies regime and confluence weights.   |
//|                                                                  |
//| DEPENDENCY RULES:                                               |
//|   PatternManager.mqh : Core/ + Infra/ + Evaluators + ScoreEngine|
//|   Evaluators.mqh     : Core/Config/Types.mqh only              |
//|   ScoreEngine.mqh    : Core/Config/Types.mqh only              |
//|                                                                  |
//| STATUS: ✅ MIGRATED — files exist and are production-ready      |
//+------------------------------------------------------------------+
