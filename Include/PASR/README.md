# PASR — Price Action Support Resistance EA

> **Architecture:** Pipeline Orchestration (migrated from Monolith v9, Sprint 1–11)
> **Last updated:** Sprint 11 (2026-05-24)
> **Compile target:** `Experts/PASR/PASR_MODULAR.mq5`

---

## Architecture Overview

PASR menggunakan **Pipeline Orchestration** — semua logika dieksekusi sebagai stage berurutan di dalam `CPipelineEngine::ExecutePipeline()` yang dipanggil dari `OnTimer()`.

```
OnTick()  → Push EVENT_PRICE_UPDATE (no logic)
           → set m_new_bar_flag jika bar baru (consumed once di OnTimer)
OnTimer() → DrainQueue()
          → CPipelineEngine::ExecutePipeline(PipelineContext)
              Stage  1: DataSync         ← m_data->OnTick()
              Stage  2: AnalysisSR       ← m_bus.Dispatch(EVENT_ID_NEW_BAR)
              Stage  3: AnalysisZone     ← m_zone->Update() on new bar
              Stage  4: PatternRec       ← m_pattern->OnTick()
              Stage  5: RegimeDetect     ← m_regime_det->Evaluate()
              Stage  6: SignalGen        ← CSignalManager (4 sources, weighted vote)
              Stage  7: AIInference      ← CAIOrchestrator (26-dim ONNX)
              Stage  8: RiskCheck        ← CRiskManager + IsSpreadAcceptable()
              Stage  9: AdaptiveParams   ← CAdaptiveParameterManager->OnNewBar()
              Stage 10: Execution        ← CExecutionManager + ticket capture
              Stage 11: PosMgmt          ← CExecutionManager->ManagePositions()
              Stage 12: Recovery         ← CRecoveryManager->OnTick()
              Stage 13: Dashboard        ← CDashboardManager->OnTimer()
              Stage 14: Journal          ← CJournalManager->LogEntry()
          → DrainQueue()
OnTradeTransaction() → RecoveryManager + SessionState + AIOrchestrator backprop
```

---

## Folder Map

```
Include/PASR/
├── Core/                    ← Infrastructure (EventBus, IManager, Pipeline engine)
│   ├── PASR.mqh             ← Master include — use this, NEVER include sub-files directly
│   ├── Orchestrator.mqh     ← v3.06 — owns all managers, wires OnTick/OnTimer/OnDeinit
│   ├── PipelineEngine.mqh   ← v1.01 — 14-stage execution engine (fully implemented)
│   ├── PipelineTypes.mqh    ← PipelineContext, enums, SExecutionResult
│   ├── Events.mqh           ← All ENUM_EVENT_ID definitions
│   ├── EventBus.mqh         ← Pub/sub message bus (O(n log n) heap drain)
│   ├── IManager.mqh         ← Base interface for all managers
│   ├── Globals.mqh          ← v2.15 — GVKey helpers, PASRLog*, CPerfTimer, IsSpreadAcceptable()
│   ├── AsyncOrderManager.mqh
│   ├── HighFreqTimer.mqh
│   ├── LatencyOptimizer.mqh
│   ├── StateOwnershipMap.mqh
│   └── PASR_SymbolManager.mqh
│
├── Analysis/                ← Market analysis managers
│   ├── SRManager.mqh        ← S/R detection (⚠ 54KB, Sprint 12 decomposition target)
│   ├── ZoneManager.mqh      ← Supply/Demand zones
│   ├── MarketRegimeDetector.mqh
│   ├── AdaptiveParameterManager.mqh
│   └── Pattern/             ← Candlestick pattern sub-module (audit pending)
│
├── Signal/                  ← v4.02 — Signal generation & regime filtering
│   ├── SignalManager.mqh    ← v4.02 — aggregator, 4 sources
│   └── SignalFilterPipeline.mqh ← v1.02 — MTF + custom filter pipeline
│
├── Trade/                   ← Execution, Risk, Recovery managers
├── AI/                      ← AIOrchestrator, ONNX integration
├── Phase7/                  ← HealthMonitor, SnapshotManager, SessionState
└── Dashboard/               ← Chart rendering, telemetry, journal
```

---

## Compilation Flags

```cpp
#define PASR_QA_BUILD    // Enable QA modules (LatencySimulator, chaos tests)
#define PASR_DEBUG       // Verbose logging per manager
```

> ⚠️ **Old flags removed:** `QA_BUILD` (renamed → `PASR_QA_BUILD`), `OOP_ARCHITECTURE`, `PERF_METRICS` — do NOT use these.

---

## Bug Tracker

### 🔴 OPEN — Pending subfolder audits

| ID | Severity | File | Description | Target |
|----|----------|------|-------------|--------|
| A1 | 🟠 HIGH | `Analysis/SRManager.mqh` | 54KB monolith — perlu decomposition ke SRDetector + SRZoneStore + SRScorer | Sprint 12 |
| A5 | 🟠 HIGH | `Analysis/Pattern/*.mqh` | Pattern subfolder belum diaudit untuk IManager compliance | Sprint 12 |
| TR-? | 🔴 TBD | `Trade/*.mqh` | Trade subfolder: architecture belum diaudit | Sprint 12 |
| AI-? | 🔴 TBD | `AI/*.mqh` | AI subfolder: ONNX wiring belum diaudit | Sprint 12 |
| P7-? | 🔴 TBD | `Phase7/*.mqh` | Phase7 subfolder belum diaudit | Sprint 12 |
| DS-? | 🔴 TBD | `Dashboard/*.mqh` | Dashboard subfolder belum diaudit | Sprint 12 |
| BUG-008 | 🟠 HIGH | `Experts/PASR/PASR_MODULAR.mq5` | File EA tidak ditemukan di repo — perlu konfirmasi path dan commit | Sprint 12 |

---

### ✅ RESOLVED — Sprint 1–11

| ID | Severity | File | Fix | Sprint |
|----|----------|------|-----|--------|
| BUG-001 | 🔴 CRITICAL | `Core/Globals.mqh` | Removed `CEventBus::Instance()` fake singleton. Replaced with explicit bus param `PASRDispatchEvent(ev, bus)` | S2 |
| BUG-002 | 🔴 CRITICAL | `Core/Orchestrator.mqh` | Removed monolith `ProcessNewBar()` fallback in OnTick. OnTick is now pure event-push only | S2 |
| BUG-003 | 🔴 CRITICAL | `Core/PipelineEngine.mqh` | All 7 empty stage stubs implemented (Stage_AnalysisZone, PatternRec, Recovery, Dashboard, Journal, AdaptiveParams, Execution) | S2 |
| BUG-004 | 🔴 CRITICAL | `Core/Orchestrator.mqh` | HealthMonitor + SnapshotManager now registered via `InitManager()`, properly subscribe to EventBus | S2 |
| BUG-005 | 🔴 CRITICAL | `Core/Orchestrator.mqh` | `FreeAll()` fixed to strict reverse init order. EventBus deleted last | S2 |
| BUG-006 | 🟠 HIGH | `Core/PipelineEngine.mqh` | `InjectManagers()` now stores health/snapshot into `m_health`/`m_snapshot` member fields | S2 |
| BUG-007 | 🔴 CRITICAL | `Core/PipelineEngine.mqh` | Fixed 3 wrong `#include` paths (RegimeFilter → Signal/, RiskManager → Trade/, AdaptiveParameterManager → Analysis/) | S1 |
| BUG-008 | 🔴 CRITICAL | `Experts/PASR/PASR_MODULAR.mq5` | Macro `QA_BUILD` → `PASR_QA_BUILD` — README confirmed; EA file pending commit verification | S1 |
| BUG-009 | 🔴 CRITICAL | `Core/Orchestrator.mqh` | Constructor init list completed: `m_health(NULL)`, `m_snapshot(NULL)`, `m_session(NULL)` added | S2 |
| BUG-010 | 🟡 MEDIUM | `Core/Orchestrator.mqh` | Eliminated redundant double `DrainQueue()`. Simplified to single canonical `m_bus.Drain()` | S2 |
| BUG-011 | 🟡 MEDIUM | `Core/PipelineEngine.mqh` | `Stage_Execution()` ticket hardcoded `0` → uses `ctx.exec_result.ticket` | S2 |
| BUG-012 | 🟡 MEDIUM | `Core/Globals.mqh` | `_MagicNumber` (not MQL5 built-in) replaced with explicit `magic` param in `GVKey()` | S1 |
| O1 | 🔴 CRITICAL | `Core/Orchestrator.mqh` | `ENUM_PIPELINE_STAGE` (undefined type) → `EnumToString(ENUM_STAGE_RESULT)` | S9 |
| O4 | 🟠 HIGH | `Core/Orchestrator.mqh` | SessionState init wiring fixed | S9 |
| O7 | 🔴 CRITICAL | `Core/Orchestrator.mqh` | `BarChanged()` race: dipanggil dua kali (OnTick + OnTimer), double-flip `m_lastBarTime`. Fixed dengan `m_new_bar_flag` — set di OnTick, consumed+reset di OnTimer | S9 |
| O8 | 🟠 HIGH | `Core/Orchestrator.mqh` | `CJournalManager` selalu dipassing sebagai `NULL` ke `InjectManagers()`. Added sebagai owned member `m_journal`, initialized di `Init()` | S9 |
| X1–X7 | 🔴 CRITICAL | `Core/PASR_Executor.mqh` | **DELETED** — 2024 monolith zombie. 7 bugs: no IManager, `Sleep()` recursive deadlock, `EXEC_NONE`/`EXEC_FAILED` enum collision, duplicate `ExecutionRequest` struct, duplicate switch case, no include guard. Superseded by `CExecutionManager` + `CAsyncOrderManager` | S9 |
| A2 | 🟠 HIGH | `Analysis/Optimized/` | **DELETED** entire folder (6 files) — orphaned parallel refactoring experiment, tidak pernah diwire ke PASR.mqh atau pipeline | S9 |
| A3 | 🟡 LOW | `Analysis/OPTIMIZATION_SUMMARY.md` | **DELETED** — dev artifact, bukan official documentation | S9 |
| S8-001 | 🔴 CRITICAL | `Core/Events.mqh` | Added missing `EVENT_ID_PRICE_UPDATE`, `EVENT_ID_TIMER`, `EVENT_ID_POSITION_UPDATE` (compile errors in OnTick/OnTimer) | S8 |
| S8-005 | 🔴 CRITICAL | `Core/Events.mqh` | Removed non-existent `data_i[]` array from `PASREvent`. Replaced with `data1`/`data2` double fields | S8 |
| N01 | 🔴 CRITICAL | `Core/PipelineEngine.mqh` | `Stage_AnalysisSR` push event tanpa dispatch — SR `OnEvent()` tidak pernah fired di timer path. Fix: `m_bus.Dispatch(ev)` dipanggil langsung setelah Push | S11 |
| N03 | 🟠 HIGH | `Core/Orchestrator.mqh` | `OnDeinit()` memanggil `m_health->Shutdown()` + `m_ai_orch->Deinit()` + `m_dash->Destroy()` secara manual, lalu `FreeAll()` menjalankan hal yang sama lagi (double-shutdown/free). Fix: `OnDeinit()` hanya stop timer + log. `FreeAll()` adalah satu-satunya owner teardown | S11 |
| N04 | 🟠 HIGH | `Core/PipelineEngine.mqh` | `Stage_RiskCheck` set `ctx.exit_reason = STAGE_SKIP` pada soft rejection — meracuni exit_reason dan trigger false-alarm debug log di Orchestrator. Fix: exit_reason tidak dioverwrite; hanya `exit_message` yang ditulis | S11 |
| N06 | 🟠 HIGH | `Core/Orchestrator.mqh` | `RegisterManager()` tidak guard `m_bus == NULL`. Jika bus alokasi gagal, `m_bus.Register()` crash. Fix: early-return jika `m_bus == NULL` | S11 |
| N07 | 🔴 CRITICAL | `Core/PipelineEngine.mqh` | `SkipIfNull()` menggunakan `CheckPointer(void*)` — undefined behavior di MQL5, bisa return `POINTER_DYNAMIC` untuk pointer NULL sehingga semua 14 stage guard tidak berfungsi. Fix: ganti dengan `ptr == NULL` plain check | S11 |
| BUG-S10-001 | 🔴 CRITICAL | `Signal/SignalFilterPipeline.mqh` | `support`/`resistance` undefined — `GetZoneContext()` tidak assign ke local vars sebelum dipakai. Compile error | S11 |
| BUG-S10-002 | 🟠 HIGH | `Signal/SignalFilterPipeline.mqh` | `RunCustomFilters()` ada di class tapi tidak pernah dipanggil dari `RunCompletePipeline()`. Custom filters tidak pernah aktif | S11 |
| BUG-S10-003 | 🟠 HIGH | `Signal/SignalFilterPipeline.mqh` | MTF `referencePrice` menggunakan `ctx.bid` (tick price) bukan `ctx.close` (bar close) — filter MTF tidak konsisten dengan bar-based analysis | S11 |
| BUG-S10-004 | 🔴 CRITICAL | `Signal/SignalManager.mqh` | Call site `RunCompletePipeline()` di `SignalManager` menggunakan signature lama (3 param) sedangkan v1.01 sudah 5 param — compile error | S11 |

---

## Sprint History

| Sprint | Focus | Key Deliverables |
|--------|-------|------------------|
| S1 | Compile fixes | BUG-007, BUG-008, BUG-012 |
| S2 | Architecture integrity | BUG-001–006, BUG-009–011 |
| S8 | Runtime state ownership | SessionState wiring, Events.mqh fixes, health/snapshot injection |
| S9 | Orchestrator residuals + Analysis cleanup | O1, O4, O7, O8, X1–X7 (PASR_Executor deleted), A2–A3 (Optimized/ deleted) |
| S10 | Signal layer audit (planned → executed S11) | SignalFilterPipeline, SignalManager wiring |
| S11 | PipelineEngine + Orchestrator hardening | N01, N03, N04, N06, N07, BUG-S10-001–004 |
| S12 | Trade/AI/Phase7/Dashboard audit + A1 decomposition | _(planned)_ |

---

## Quick Start

```cpp
// Include ONE file only — never include sub-files directly
#include <PASR/Core/PASR.mqh>

// In OnInit:
COrchestrator orch;
if(orch.Init(cfg) != INIT_SUCCEEDED) return INIT_FAILED;
EventSetTimer(1);

// In OnTick:
orch.OnTick();

// In OnTimer:
orch.OnTimer();

// In OnTradeTransaction:
orch.OnTradeTransaction(trans, request, result);

// In OnDeinit:
orch.OnDeinit(reason);
// Note: EventKillTimer() is called inside orch.OnDeinit()
```

---

## Version Index — Core Files

| File | Version | Last Sprint | Status |
|------|---------|-------------|--------|
| `Core/Orchestrator.mqh` | v3.06 | S11 | ✅ Stable |
| `Core/PipelineEngine.mqh` | v1.01 | S11 | ✅ Stable |
| `Core/Globals.mqh` | v2.15 | S11 | ✅ Stable |
| `Core/Events.mqh` | — | S8 | ✅ Stable |
| `Core/EventBus.mqh` | — | S8 | ✅ Stable |
| `Signal/SignalManager.mqh` | v4.02 | S11 | ✅ Stable |
| `Signal/SignalFilterPipeline.mqh` | v1.02 | S11 | ✅ Stable |
| `Analysis/SRManager.mqh` | — | — | ⚠️ Audit needed (54KB) |
| `Analysis/Pattern/*.mqh` | — | — | ⚠️ Audit needed |
| `Trade/*.mqh` | — | — | 🔴 Not audited |
| `AI/*.mqh` | — | — | 🔴 Not audited |
| `Phase7/*.mqh` | — | — | 🔴 Not audited |
| `Dashboard/*.mqh` | — | — | 🔴 Not audited |

---

© 2026 Agsicentre — PASR EA. All rights reserved.
