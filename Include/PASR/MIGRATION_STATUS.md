# PASR Architecture Migration Status

> Last updated: 2026-05-23 | Sprint 3/4 complete

## Migration: Monolith → Pipeline Orchestration

### Status: ✅ COMPLETE (12/12 bugs resolved)

---

## Bug Fix Tracker

| ID | Severity | File | Description | Status |
|---|---|---|---|---|
| BUG-001 | 🔴 CRITICAL | `Globals.mqh` | `CEventBus::Instance()` singleton palsu | ✅ Fixed v2.14 |
| BUG-002 | 🔴 CRITICAL | `Orchestrator.mqh` | Monolith `ProcessNewBar()` fallback aktif di `OnTick()` | ✅ Fixed v3.03 |
| BUG-003 | 🔴 CRITICAL | `PipelineEngine.mqh` | 7 dari 12 stage stubs kosong | ✅ Fixed v2.01 |
| BUG-004 | 🔴 CRITICAL | `Orchestrator.mqh` | `CHealthMonitor`+`CSnapshotManager` tidak register ke `IManager` | ✅ Fixed v3.03 |
| BUG-005 | 🔴 CRITICAL | `Orchestrator.mqh` | `FreeAll()` urutan salah: use-after-free pada shutdown | ✅ Fixed v3.03 |
| BUG-006 | 🟠 HIGH | `PipelineEngine.mqh` | `InjectManagers()` menerima health/snapshot tapi tidak simpan ke field | ✅ Fixed v2.01 |
| BUG-007 | 🟠 HIGH | `PipelineEngine.mqh` | Include path salah: RegimeFilter, RiskManager, AdaptiveParameterManager | ✅ Fixed v2.01 |
| BUG-008 | 🟠 HIGH | `PASR_MODULAR.mq5` | `#define QA_BUILD` tidak match `#ifdef PASR_QA_BUILD` | ✅ Fixed v13.01 |
| BUG-009 | 🟠 HIGH | `Orchestrator.mqh` | Constructor init list tidak include `m_health`, `m_snapshot`, `m_latency_sim` | ✅ Fixed v3.03 |
| BUG-010 | 🟡 MEDIUM | `Orchestrator.mqh` | `DrainQueue()` dipanggil dua kali per tick (waste CPU) | ✅ Fixed v3.03 |
| BUG-011 | 🟡 MEDIUM | `PipelineEngine.mqh` | `Stage_Execution()` hardcode `ticket=0` — recovery tidak bisa track posisi | ✅ Fixed v2.01 |
| BUG-012 | 🟡 MEDIUM | `Globals.mqh` | `_MagicNumber` bukan built-in MQL5 var | ✅ Fixed v2.14 |

---

## Pipeline Architecture (Post-Migration)

```
OnTick() ────────────────────────────────────────────────────
  ├─ Push EVENT_PRICE_UPDATE (every tick)
  ├─ Push EVENT_NEW_BAR      (new bar only)
  └─ DrainQueue()            (once per tick)
     ├─ RecoveryManager.OnEvent() → trailing/BE/partial
     └─ Dashboard.OnEvent()    → price update

OnTimer() (1s interval) ───────────────────────────────
  └─ CPipelineEngine.ExecutePipeline(ctx)
       Stage 01 ─ DataSync        → tick data, ATR, bar time
       Stage 02 ─ AnalysisSR      → S/R zone update [new bar only]
       Stage 03 ─ AnalysisZone    → S/D zone update [new bar only]
       Stage 04 ─ PatternRec      → candle pattern detection
       Stage 05 ─ RegimeDet       → market regime classification
       Stage 06 ─ SignalGen       → signal confluence score
       Stage 07 ─ AIInference     → ML predict, drift check
       Stage 08 ─ RiskCheck       → lot size, circuit breaker
       Stage 09 ─ AdaptiveParams  → dynamic SL/TP
       Stage 10 ─ Execution       → market order placement
       Stage 11 ─ PositionMgmt    → open position scan
       Stage 12 ─ Recovery        → fakeout recovery engine
       Stage 13 ─ Dashboard       → HUD refresh
       Stage 14 ─ Journal         → telemetry log

OnTradeTransaction() ──────────────────────────────────
  ├─ RecoveryManager.OnTradeOpen()/OnTradeClose()
  ├─ RiskManager.OnTradeClosed()
  └─ AIOrchestrator.OnTradeResult() [backprop]
```

---

## Sprint Status

| Sprint | Scope | Status |
|---|---|---|
| Sprint 1 | Compile fixes: BUG-007, BUG-008, BUG-001 | ✅ Done |
| Sprint 2 | Architecture: BUG-002, BUG-004, BUG-005, BUG-009, BUG-010 | ✅ Done |
| Sprint 3 | Runtime: BUG-003, BUG-006, BUG-011, BUG-012 | ✅ Done |
| Sprint 4 | Performance hardening | 🟡 Planned |

---

## Sprint 4 — Performance Hardening (Planned)

```
[ ] EventBus: priority queue (heap sort vs O(n) linear scan)
[ ] Stage_Recovery: cache PositionsTotal() in ctx to avoid MT5 API call
[ ] CPipelineEngine: per-stage timeout watchdog (abort if stage > 50ms)
[ ] CAIOrchestrator: ONNX model lazy-load on first Predict() call
[ ] CSnapshotManager: async/non-blocking file write
[ ] Stage_AnalysisSR: incremental update (only recalc on new candle body)
[ ] RiskManager: cache equity/balance (avoid 2x TerminalInfo call per tick)
```

---

## File Version Summary

| File | Version | Key Change |
|---|---|---|
| `Experts/PASR_MODULAR.mq5` | v13.01 | BUG-008: macro rename |
| `Include/PASR/Core/Orchestrator.mqh` | v3.03 | BUG-002,004,005,009,010 |
| `Include/PASR/Core/PipelineEngine.mqh` | v2.01 | BUG-003,006,007,011 |
| `Include/PASR/Core/Globals.mqh` | v2.14 | BUG-001,012 |
