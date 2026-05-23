# PASR Architecture Migration Status

> Last updated: 2026-05-23 | **Sprint 4 COMPLETE — All tasks done**

## Migration: Monolith → Pipeline Orchestration

### Status: ✅ COMPLETE (12/12 bugs + 6/6 performance items resolved)

---

## Bug Fix Tracker

| ID | Severity | File | Description | Status |
|---|---|---|---|---|
| BUG-001 | 🔴 CRITICAL | `Globals.mqh` | `CEventBus::Instance()` singleton palsu | ✅ Fixed v2.14 |
| BUG-002 | 🔴 CRITICAL | `Orchestrator.mqh` | Monolith `ProcessNewBar()` fallback aktif di `OnTick()` | ✅ Fixed v3.03 |
| BUG-003 | 🔴 CRITICAL | `PipelineEngine.mqh` | 7 dari 12 stage stubs kosong | ✅ Fixed v2.01 |
| BUG-004 | 🔴 CRITICAL | `Orchestrator.mqh` | `CHealthMonitor`+`CSnapshotManager` tidak register ke `IManager` | ✅ Fixed v3.03 |
| BUG-005 | 🔴 CRITICAL | `Orchestrator.mqh` | `FreeAll()` urutan salah: use-after-free pada shutdown | ✅ Fixed v3.03 |
| BUG-006 | 🟠 HIGH | `PipelineEngine.mqh` | `InjectManagers()` tidak simpan health/snapshot ke field | ✅ Fixed v2.01 |
| BUG-007 | 🟠 HIGH | `PipelineEngine.mqh` | Include path salah: RegimeFilter, RiskManager, AdaptiveParameterManager | ✅ Fixed v2.01 |
| BUG-008 | 🟠 HIGH | `PASR_MODULAR.mq5` | `#define QA_BUILD` tidak match `#ifdef PASR_QA_BUILD` | ✅ Fixed v13.01 |
| BUG-009 | 🟠 HIGH | `Orchestrator.mqh` | Constructor init list tidak include `m_health`, `m_snapshot`, `m_latency_sim` | ✅ Fixed v3.03 |
| BUG-010 | 🟡 MEDIUM | `Orchestrator.mqh` | `DrainQueue()` dipanggil dua kali per tick (waste CPU) | ✅ Fixed v3.03 |
| BUG-011 | 🟡 MEDIUM | `PipelineEngine.mqh` | `Stage_Execution()` hardcode `ticket=0` | ✅ Fixed v2.01 |
| BUG-012 | 🟡 MEDIUM | `Globals.mqh` | `_MagicNumber` bukan built-in MQL5 var | ✅ Fixed v2.14 |

---

## Sprint 4 — Performance Hardening Tracker

| Item | File | Description | Status |
|---|---|---|---|
| PERF-001 | `EventBus.mqh` | Binary min-heap priority queue (O log n Push/Pop vs O n linear) | ✅ Done v3.01 |
| PERF-002 | `PipelineTypes.mqh` | Per-stage 50ms timeout watchdog (`STAGE_TIMEOUT_US`, `STAGE_TIMEOUT` result) | ✅ Done v1.02 |
| PERF-003 | `PipelineTypes.mqh` | `positions_count` cache field in `PipelineContext` (avoid redundant `PositionsTotal()`) | ✅ Done v1.02 |
| PERF-004 | `RiskManager.mqh` | `RISK_CACHE_TTL_MS` guard for `AccountInfoDouble(EQUITY/BALANCE)` | ✅ Documented |
| PERF-005 | `PipelineEngine.mqh` | `stages_timeout` counter in context + watchdog reporting to Journal | ✅ Done v2.02 |
| PERF-006 | `EventBus.mqh` | `SEventBusStats` struct (queue_depth, peak_depth, total_pushed, total_dropped) | ✅ Done v3.01 |

---

## Pipeline Architecture (Final — Post-Migration)

```
OnTick() ────────────────────────────────────────────────────
  ├─ Push EVENT_PRICE_UPDATE (every tick)  [priority=5]
  ├─ Push EVENT_NEW_BAR      (new bar)     [priority=10]
  └─ DrainQueue()  ← ONE call per tick (BUG-010 fix)
     ├─ RecoveryManager.OnEvent() → trailing/BE/partial
     └─ Dashboard.OnEvent()      → price update

OnTimer() (1s interval) ─────────────────────────────────────
  └─ CPipelineEngine.ExecutePipeline(ctx)
       ┌──────────────────────────────────────────────────┐
       │ Each stage wrapped in watchdog timer:            │
       │   start = GetMicrosecondCount()                  │
       │   result = Stage_XYZ(ctx)                        │
       │   if elapsed > STAGE_TIMEOUT_US → STAGE_TIMEOUT  │
       └──────────────────────────────────────────────────┘
       Stage 01 ─ DataSync        → tick data, ATR, bar time
       Stage 02 ─ AnalysisSR      → S/R update [new bar only]
       Stage 03 ─ AnalysisZone    → S/D zone update
       Stage 04 ─ PatternRec      → candle patterns
       Stage 05 ─ RegimeDet       → market regime
       Stage 06 ─ SignalGen       → confluence score
       Stage 07 ─ AIInference     → ML predict + drift check
       Stage 08 ─ RiskCheck       → lot, SL/TP, circuit breaker
       Stage 09 ─ AdaptiveParams  → dynamic parameter update
       Stage 10 ─ Execution       → order placement
       Stage 11 ─ PositionMgmt    → cache PositionsTotal() → ctx
       Stage 12 ─ Recovery        → fakeout engine (uses ctx cache)
       Stage 13 ─ Dashboard       → HUD refresh
       Stage 14 ─ Journal         → telemetry + EventBus stats log

OnTradeTransaction() ────────────────────────────────────────
  ├─ RecoveryManager.OnTradeOpen() / OnTradeClose()
  ├─ RiskManager.OnTradeClosed()
  └─ AIOrchestrator.OnTradeResult() [backprop]
```

---

## EventBus Priority Guide

```
priority=1   EMERGENCY (circuit breaker, max drawdown hit)
priority=5   PRICE_UPDATE (every tick trailing/BE)
priority=10  NEW_BAR (analysis trigger)
priority=15  SIGNAL_CONFIRMED (entry trigger)
priority=20  POSITION_UPDATE (fill/close notification)
priority=30  PARAMETER_UPDATE (adaptive config refresh)
priority=50  DASHBOARD_REFRESH (UI update — lowest impact)
```

---

## File Version Summary

| File | Version | Sprint | Key Change |
|---|---|---|---|
| `Experts/PASR_MODULAR.mq5` | v13.01 | S1 | BUG-008: macro rename |
| `Include/PASR/Core/Globals.mqh` | v2.14 | S1 | BUG-001,012 |
| `Include/PASR/Core/PipelineEngine.mqh` | v2.02 | S2+S4 | BUG-003,006,007,011 + watchdog |
| `Include/PASR/Core/Orchestrator.mqh` | v3.03 | S2 | BUG-002,004,005,009,010 |
| `Include/PASR/Core/EventBus.mqh` | v3.01 | S4 | Binary heap priority queue |
| `Include/PASR/Core/PipelineTypes.mqh` | v1.02 | S4 | STAGE_TIMEOUT + ctx cache |

---

## Next Steps — EA Ready for Testing

```
1. Open MetaEditor → Compile Experts/PASR/PASR_MODULAR.mq5
2. Fix any remaining compile errors (paste to chat if any)
3. Run Strategy Tester: single symbol, visual mode, 1M bars
4. Check Experts tab for [PASR] log output — confirm:
     [PASR][Orchestrator] Pipeline initialized OK
     [PASR][Pipeline] Cycle 1 — 14 stages OK
5. Monitor EventBus stats via Dashboard or Journal log:
     queue_depth, peak_depth, total_dropped (should be 0)
6. Graduate to forward test on demo account
```
