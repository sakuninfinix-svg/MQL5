//+------------------------------------------------------------------+
//|                                              9.PatternManager.mqh |
//|                                       Copyright 2026, Agsicentre |
//|  @deprecated  BACKWARD-COMPATIBILITY SHIM — DO NOT INCLUDE       |
//|               THIS FILE IN NEW CODE.                              |
//|                                                                   |
//|  This file is kept ONLY so that old EA files that were compiled   |
//|  before the Pattern/ subfolder migration continue to build        |
//|  without modification.                                            |
//|                                                                   |
//|  STATUS : DEPRECATED since v2.04 / PASR.mqh v1.10               |
//|  REPLACE WITH : #include "Pattern/PatternManager.mqh"            |
//|  SAFE TO DELETE : YES — after all callers are migrated            |
//|                                                                   |
//|  CURRENT KNOWN CALLERS (as of migration commit):                  |
//|    - PASR.mqh              → MIGRATED (now uses Pattern/)         |
//|    - PASR_MODULAR.mq5      → MIGRATED (uses PASR.mqh)             |
//|    - 8.RecoveryManager.mqh → MIGRATED (now uses Pattern/)         |
//|    - DOCUMENTATION.md      → doc-only ref, no compile impact      |
//|    - Audit .md files       → doc-only ref, no compile impact      |
//+------------------------------------------------------------------+

#ifndef __9_PATTERN_MANAGER_SHIM_MQH__
#define __9_PATTERN_MANAGER_SHIM_MQH__

// Forward to the real modular implementation.
// All PatternManager:: call sites remain valid — no changes needed in callers.
#include "Pattern/PatternManager.mqh"

#endif // __9_PATTERN_MANAGER_SHIM_MQH__
