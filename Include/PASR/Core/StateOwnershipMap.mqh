//+------------------------------------------------------------------+
//| Core/StateOwnershipMap.mqh — v1.00 (Sprint 7)                   |
//| FORMAL state ownership declaration untuk PASR architecture       |
//| Dokumen ini adalah KONTRAK — modifikasi ownership harus update   |
//| file ini terlebih dahulu sebelum coding.                         |
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_STATE_OWNERSHIP_MAP_MQH__
#define __CORE_STATE_OWNERSHIP_MAP_MQH__

//
// ╔══════════════════════════════════════════════════════════════════╗
// ║          PASR STATE OWNERSHIP MAP v1.00 (Sprint 7)             ║
// ╠══════════════════════════════════════════════════════════════════╣
// ║                                                                  ║
// ║  LAYER 1 — SESSION STATE (persists across bars, GV-backed)      ║
// ║  ┌────────────────────────────────────────────────────────────┐  ║
// ║  │ OWNER   : CSessionState (Infra/SessionState.mqh)           │  ║
// ║  │ FIELDS  : peak_equity, start_equity, current_equity        │  ║
// ║  │           daily_pnl, weekly_pnl, max_drawdown              │  ║
// ║  │           current_drawdown, open_positions                 │  ║
// ║  │           trades_today, last_trade_time                    │  ║
// ║  │ WRITE   : CSessionState ONLY via RecordTrade/SyncEquity    │  ║
// ║  │ READ    : All managers via GetSnapshot() — read-only ptr   │  ║
// ║  │ PERSIST : GlobalVariables via GVSet/GVGet                  │  ║
// ║  │ CLEANUP : CleanStaleGV() on Init() — prevents day bleed    │  ║
// ║  └────────────────────────────────────────────────────────────┘  ║
// ║                                                                  ║
// ║  LAYER 2 — HEALTH STATE (per-session, resets on EA restart)     ║
// ║  ┌────────────────────────────────────────────────────────────┐  ║
// ║  │ OWNER   : CHealthMonitor (Infra/HealthMonitor.mqh)         │  ║
// ║  │ FIELDS  : m_status, m_consecutive_errors                   │  ║
// ║  │           m_latency_samples[60], m_last_recovery_time      │  ║
// ║  │           m_is_recovering (recovery flag only)             │  ║
// ║  │           m_shutting_down (shutdown flag — SEPARATE)       │  ║
// ║  │ WRITE   : CHealthMonitor ONLY                              │  ║
// ║  │ READ    : PipelineEngine via ctx.health_status (snapshot)  │  ║
// ║  │ RESET   : Orchestrator calls ResetRecoveryFlag() after     │  ║
// ║  │           EVENT_ID_SYSTEM_RECOVER is processed             │  ║
// ║  └────────────────────────────────────────────────────────────┘  ║
// ║                                                                  ║
// ║  LAYER 3 — PIPELINE CONTEXT (ephemeral — one struct per cycle)  ║
// ║  ┌────────────────────────────────────────────────────────────┐  ║
// ║  │ OWNER   : CPipelineEngine (stack-allocated per OnTimer())  │  ║
// ║  │ WRITE CONTRACT (one writer per field group):               │  ║
// ║  │   bid/ask/atr/new_bar  → Stage_DataSync ONLY              │  ║
// ║  │   signal/strength      → Stage_SignalGen ONLY             │  ║
// ║  │   regime/confidence    → Stage_RegimeDet ONLY             │  ║
// ║  │   plan.*               → Stage_AdaptiveParams → plan_locked│  ║
// ║  │   risk_result.*        → Stage_RiskCheck ONLY             │  ║
// ║  │   ai_result.*          → Stage_AIInference ONLY           │  ║
// ║  │   exec_result.*        → Stage_Execution ONLY             │  ║
// ║  │   positions_count      → Stage_PositionMgmt ONLY          │  ║
// ║  │   health_status        → Orchestrator before stage loop   │  ║
// ║  │   session_dd/daily_pnl → Orchestrator before stage loop   │  ║
// ║  │ LIFETIME: Born at start of cycle, dies at end             │  ║
// ║  └────────────────────────────────────────────────────────────┘  ║
// ║                                                                  ║
// ║  LAYER 4 — MANAGER INTERNAL STATE (per-manager, class-owned)    ║
// ║  ┌────────────────────────────────────────────────────────────┐  ║
// ║  │ RULE: Each manager owns its OWN internal state exclusively │  ║
// ║  │ NO manager may call another manager's private methods      │  ║
// ║  │ Cross-manager communication: EventBus ONLY                 │  ║
// ║  │ Exception: Read-only accessors (IsHealthy, GetZones)       │  ║
// ║  └────────────────────────────────────────────────────────────┘  ║
// ║                                                                  ║
// ║  LAYER 5 — DASHBOARD/UI STATE (render-only, no business logic)  ║
// ║  ┌────────────────────────────────────────────────────────────┐  ║
// ║  │ OWNER   : CDashboardManager (UI/DashboardManager.mqh)      │  ║
// ║  │ RULE    : Dashboard READS SessionState snapshot ONLY       │  ║
// ║  │           Dashboard NEVER writes to any other state layer  │  ║
// ║  │           Chart objects cleaned in Shutdown() — no leaks   │  ║
// ║  │ PATTERN : DashboardManager.Update(snap, ctx) per bar       │  ║
// ║  └────────────────────────────────────────────────────────────┘  ║
// ║                                                                  ║
// ║  ANTI-PATTERNS (FORBIDDEN):                                      ║
// ║  ✗ RiskManager writing peak_equity  (SessionState owns it)      ║
// ║  ✗ TelemetryRecorder writing daily_pnl directly to GV           ║
// ║  ✗ HealthMonitor reading m_session directly                      ║
// ║  ✗ Any stage modifying plan.* after plan_locked == true         ║
// ║  ✗ GVSet() called outside CSessionState methods                 ║
// ╚══════════════════════════════════════════════════════════════════╝

#endif // __CORE_STATE_OWNERSHIP_MAP_MQH__
