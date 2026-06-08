//+------------------------------------------------------------------+
//| PASR LAYER 7 — QA / DEVTOOLS                                    |
//|                                                                  |
//| PURPOSE:                                                         |
//|   Development-only tools: unit testing, mocks, harnesses, and   |
//|   diagnostics. Keep production runtime out of this folder.      |
//|                                                                  |
//| CONTENTS:                                                        |
//|   Audit.mqh         — Runtime audit helper                    |
//|   SmokeTest.mqh     — Smoke test helpers                      |
//|   PipelineHarness.mqh — Pipeline harness and mocks             |
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
// Active QA files should be compile-gated with PASR_QA_BUILD unless a
// script explicitly includes them for a test harness.
