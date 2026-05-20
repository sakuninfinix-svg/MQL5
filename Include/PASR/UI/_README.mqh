//+------------------------------------------------------------------+
//| PASR LAYER 6 — USER INTERFACE / PRESENTATION                    |
//|                                                                  |
//| PURPOSE:                                                         |
//|   Chart dashboard rendering: equity curve, open positions,     |
//|   signal status, regime indicator, AI confidence score.        |
//|                                                                  |
//| CONTENTS:                                                        |
//|   DashboardManager.mqh — Comment-based dashboard, throttled    |
//|                           to 1 Hz via m_lastRenderUs guard.    |
//|                                                                  |
//| DEPENDENCY RULES (STRICT):                                       |
//|   ✅ MAY include   : Core/, Infra/ (read-only)                  |
//|   ✅ MAY read      : Analysis/, Signal/, Trade/ via pointers    |
//|   ❌ MUST NOT write to: any other layer's state                 |
//|   ❌ MUST NOT include: Trade/ or Signal/ headers directly       |
//|      (use extern pointers + forward declarations instead)       |
//|                                                                  |
//| PERFORMANCE RULE:                                               |
//|   Dashboard MUST be throttled. String building is expensive.   |
//|   Maximum render frequency: 1 Hz (1000ms between renders).     |
//|   Use m_dirtyFlag to skip render when no data has changed.     |
//|   NEVER concatenate strings inside OnTick() directly.          |
//+------------------------------------------------------------------+
//
// Migration status:
//   [✅] DashboardManager.mqh — DONE (source: ../11.DashboardManager.mqh)
//        Already refactored with 1Hz throttle + dirty flag.
