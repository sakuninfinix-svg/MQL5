//+------------------------------------------------------------------+
//| PASR LAYER 5 — TRADE / EXECUTION                                |
//|                                                                  |
//| PURPOSE:                                                         |
//|   Order management: sending, modifying, and closing trades.    |
//|   Drawdown recovery: martingale guard, hedging, position       |
//|   rescue strategies.                                            |
//|                                                                  |
//| CONTENTS:                                                        |
//|   ExecutionManager.mqh — CTrade wrapper, SL/TP management,     |
//|                          partial close, breakeven, trailing.   |
//|   RecoveryManager.mqh  — Drawdown detection, recovery modes,   |
//|                          GV-persisted state across restarts.   |
//|                                                                  |
//| DEPENDENCY RULES (STRICT):                                       |
//|   ✅ MAY include   : Core/, Infra/                              |
//|   ✅ MAY read      : Analysis/ types via function parameters    |
//|   ❌ MUST NOT include: Signal/, UI/                             |
//|                                                                  |
//| SECURITY RULE:                                                   |
//|   ALL GlobalVariable keys MUST be prefixed with:               |
//|     IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))          |
//|   to prevent state corruption between live/demo instances       |
//|   running on the same terminal with the same magic number.     |
//|                                                                  |
//| RECOVERY SAFETY RULE:                                           |
//|   RecoveryManager.mqh must NEVER call GetConfigCache() without  |
//|   first verifying the DataManager pointer is valid via          |
//|   CheckPointer(). The cfg variable scope bug (PASR-BUG-RECOVERY)|
//|   from v1.x must not recur.                                     |
//+------------------------------------------------------------------+
//
// Migration status:
//   [ ] ExecutionManager.mqh — pending (source: ../6.ExecutionManager.mqh)
//   [ ] RecoveryManager.mqh  — pending (source: ../8.RecoveryManager.mqh)
