//+------------------------------------------------------------------+
//| PASR LAYER 6 — TRADE                                            |
//|                                                                  |
//| PURPOSE:                                                         |
//|   Execution layer. Receives signals from Signal layer,           |
//|   manages open positions, applies recovery logic, trailing       |
//|   stop, partial close, and forced exits.                         |
//|                                                                  |
//| CONTENTS:                                                        |
//|   TradePlan.mqh          — CTradePlan struct (SRP-extracted)     |
//|   ExecutionManager.mqh   — CExecutionManager (production)       |
//|   RecoveryManager.mqh    — RecoveryManager v2.05 (production)    |
//|                                                                  |
//| MIGRATION STATUS:                                                |
//|   ✅ TradePlan.mqh          — DONE (extracted from ExecMgr)       |
//|   ✅ ExecutionManager.mqh   — DONE (all PASR-BUG-00x applied)    |
//|   ✅ RecoveryManager.mqh    — DONE v2.05                          |
//|       BUG-001 cfg undeclared     ✔ fixed v2.02                   |
//|       BUG-002 GV ACCOUNT_LOGIN   ✔ fixed v2.02                   |
//|       BUG-003 CFG macro undef    ✔ fixed v2.04                   |
//|       BUG-007 engines[] overflow ✔ fixed v2.05                   |
//|       BUG-008 no broker check    ✔ fixed v2.05                   |
//|       BUG-009 partial dbl-close  ✔ fixed v2.05                   |
//|       BUG-010 wrong include path ✔ fixed v2.05                   |
//|                                                                  |
//| DEPENDENCY RULES:                                                |
//|   ✅ MAY include   : Core/, Infra/, Data/, Analysis/, Signal/     |
//|   ❌ MUST NOT include: UI/                                        |
//+------------------------------------------------------------------+
//
// This file is a layer documentation stub.
// It is never included by production code.
