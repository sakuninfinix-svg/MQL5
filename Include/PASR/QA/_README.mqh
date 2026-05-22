//+------------------------------------------------------------------+
//| PASR LAYER 7 — QA / DEVTOOLS                                    |
//|                                                                  |
//| PURPOSE:                                                         |
//|   Development-only tools: unit testing, audit logging,         |
//|   performance profiling. NEVER included in production builds.  |
//|                                                                  |
//| CONTENTS:                                                        |
//|   Audit.mqh         — Runtime audit log (from Infra/Optimizations)  |
//|   Test.mqh          — Unit test runner (from QA/Test.mqh)    |
//|   Optimizations.mqh — Optimization helpers (Infra/Optimizations) |
//|                                                                  |
//| DEPENDENCY RULES:                                               |
//|   ✅ MAY include   : any layer (QA needs full system access)    |
//|   ❌ MUST NEVER be included by any production .mqh or .mq5 file|
//|                                                                  |
//| COMPILE GUARD (mandatory in every QA file):                     |
//|                                                                  |
//|   #ifdef PASR_QA_BUILD                                          |
//|   // ... all QA code here                                       |
//|   #endif // PASR_QA_BUILD                                       |
//|                                                                  |
//|   The EA defines PASR_QA_BUILD only in test/debug builds.      |
//|   In production OnInit(), the #define is absent, so this       |
//|   entire file compiles to zero bytes.                           |
//+------------------------------------------------------------------+
//
// Migration status:
//   [✓] Audit.mqh         — completed
//   [✓] Test.mqh          — completed
//   [✓] Optimizations.mqh — completed (moved to Infra/Optimizations/)
//   [✓] BatchProcessor.mqh — completed (moved to Infra/Optimizations/)
//   [✓] MemoryPool.mqh    — completed (moved to Infra/Optimizations/)
//   [✓] Branchless.mqh    — completed (moved to Infra/Optimizations/)
