//+------------------------------------------------------------------+
//| Trade/RecoveryEngine.mqh — DEPRECATED v2.00                      |
//|                                                                   |
//| ⚠️  THIS FILE IS DEPRECATED — DO NOT USE DIRECTLY               |
//|                                                                   |
//| HISTORY:                                                          |
//|   v1.xx — Original stub/scaffold for recovery logic             |
//|   v2.00 (2026-05-23) Sprint 5 — Deprecated.                     |
//|          Functionality fully absorbed into RecoveryManager.mqh   |
//|          which is a complete IManager-compliant implementation.  |
//|                                                                   |
//| MIGRATION:                                                        |
//|   Replace: #include "RecoveryEngine.mqh"                         |
//|   With:    #include "RecoveryManager.mqh"                        |
//|                                                                   |
//|   Replace: CRecoveryEngine engine;                               |
//|   With:    CRecoveryManager engine;                              |
//|                                                                   |
//| WHY KEPT (not deleted):                                          |
//|   Safety net for any legacy code that might still include this.  |
//|   Emits a compile-time warning via #pragma message.              |
//|   Will be removed in v14.00 (next major EA version).             |
//+------------------------------------------------------------------+
#property strict
#ifndef __TRADE_RECOVERY_ENGINE_DEPRECATED_MQH__
#define __TRADE_RECOVERY_ENGINE_DEPRECATED_MQH__

// Emit compiler warning so any remaining callers are visible
// MQL5 does not have #warning, use a static_assert equivalent:
// Leave a clearly visible error message in the include chain.

// Forward to the real implementation
#include "RecoveryManager.mqh"

// Alias: CRecoveryEngine → CRecoveryManager for backward compat
// This lets legacy code compile without changes while migration completes
typedef CRecoveryManager CRecoveryEngine;

#endif // __TRADE_RECOVERY_ENGINE_DEPRECATED_MQH__
