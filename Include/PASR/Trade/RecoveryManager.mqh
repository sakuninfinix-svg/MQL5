//+------------------------------------------------------------------+
//|                                   Trade/RecoveryManager.mqh      |
//|  Canonical name — forwards to 8.RecoveryManager.mqh (root)       |
//|  NOTE: PASR-BUG-003 (cfg undeclared scope) is NOT yet fixed      |
//|  in the legacy source. Fix is tracked in IMPROVEMENT_ROADMAP.md  |
//|  Phase 2. Do NOT remove this shim until the bug is fixed.        |
//+------------------------------------------------------------------+
#property strict
#ifndef __TRADE_RECOVERY_MANAGER_MQH__
#define __TRADE_RECOVERY_MANAGER_MQH__
#include "../8.RecoveryManager.mqh"
#endif
