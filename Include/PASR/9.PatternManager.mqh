//+------------------------------------------------------------------+
//|  9.PatternManager.mqh  — BACKWARD-COMPATIBILITY SHIM             |
//|                                                                   |
//|  This file is kept so that any existing EA that includes          |
//|  "9.PatternManager.mqh" continues to compile without change.     |
//|                                                                   |
//|  All logic has been moved to Pattern/ subfolder (v3.0 refactor): |
//|    Pattern/PatternTypes.mqh      — types & structs               |
//|    Pattern/CandleUtils.mqh       — candle math                   |
//|    Pattern/ScoreEngine.mqh       — scoring engine                |
//|    Pattern/Evaluators.mqh        — 10 pattern evaluators         |
//|    Pattern/FakeoutDetector.mqh   — fakeout detection             |
//|    Pattern/PatternManager.mqh    — orchestrator                  |
//|                                                                   |
//|  MIGRATION: replace this include with:                           |
//|    #include "Pattern/PatternManager.mqh"                         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "3.00"
#property strict

#ifndef __PATTERN_MANAGER_MQH__
#define __PATTERN_MANAGER_MQH__

// Re-export everything from the new modular structure
#include "Pattern/PatternManager.mqh"

// All public symbols (PatternResult, PatternWeights, FakeoutResult,
// ENUM_PATTERN_GRADE, PatternManager, FakeoutDetector) are now available
// via the transitive includes above. No code duplication.

#endif // __PATTERN_MANAGER_MQH__
