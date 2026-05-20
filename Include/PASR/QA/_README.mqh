//+------------------------------------------------------------------+
//| PASR LAYER 7 — QA / DEVTOOLS                                    |
//|                                                                  |
//| PURPOSE:                                                         |
//|   Development-only tools: unit testing, audit logging,         |
//|   performance profiling. NEVER included in production builds.  |
//|                                                                  |
//| CONTENTS:                                                        |
//|   Audit.mqh         — Runtime audit log (from PASR.Audit.mqh)  |
//|   Test.mqh          — Unit test runner (from PASR.Test.mqh)    |
//|   Optimizations.mqh — Optimization helpers (PASR.Optimizations) |
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
//   [ ] Audit.mqh         — pending (source: ../PASR.Audit.mqh)
//   [ ] Test.mqh          — pending (source: ../PASR.Test.mqh)
//   [ ] Optimizations.mqh — pending (source: ../PASR.Optimizations.mqh)
