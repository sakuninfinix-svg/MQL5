# PASR — Price Action Support Resistance EA

> **Architecture:** Pipeline Orchestration (migrated from Monolith v9, Sprint 1–12)
> **Last updated:** Sprint 12 (2026-05-24)
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
              Stage 11: PosMgmt          ← CPositionManager->ScanPositions() + CExitEngine->CheckExit()
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
│   ├── SRManager.mqh        ← S/R detection (⚠ 54KB, Sprint 13 decomposition target)
│   ├── ZoneManager.mqh      ← Supply/Demand zones
│   ├── MarketRegimeDetector.mqh
│   ├── AdaptiveParameterManager.mqh
│   └── Pattern/             ← Candlestick pattern sub-module (audit pending)
│
├── Signal/                  ← v4.02 — Signal generation & regime filtering
│   ├── SignalManager.mqh    ← v4.02 — aggregator, 4 sources
│   └── SignalFilterPipeline.mqh ← v1.02 — MTF + custom filter pipeline
│
├── Trade/                   ← ✅ S12 Audited — 6 files
│   ├── ExecutionManager.mqh ← v3.02 — async retry + stops clamp (BUG-T14)
│   ├── RiskManager.mqh      ← v2.02 — circuit breaker, daily loss, lot calc
│   ├── RecoveryManager.mqh  ← v2.18 — fakeout detection, partial close, equity decay guard
│   ├── RecoveryEngine.mqh   ← struct + state machine per position
│   ├── ExitEngine.mqh       ← v2.01 — Chandelier + Structure + ProfitFade exits
│   ├── PositionManager.mqh  ← v3.00 — pipeline-aware scanner, ScanPositions(ctx)
│   ├── TradePlan.mqh        ← struct TradePlan (direction, lot, sl, tp, comment)
│   └── CorrelationManager.mqh ← 🔴 TR-006 OPEN — full monolith v1.0, belum dimigrasi
│
├── AI/                      ← AIOrchestrator, ONNX integration (audit pending)
├── Phase7/                  ← HealthMonitor, SnapshotManager, SessionState (audit pending)
└── Dashboard/               ← Chart rendering, telemetry, journal (audit pending)
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

### 🔴 OPEN

| ID | Severity | File | Description | Target |
|----|----------|------|-------------|--------|
| **TR-006** | 🔴 CRITICAL | `Trade/CorrelationManager.mqh` | Full monolith v1.0 — belum dimigrasi ke IManager pipeline. `Initialize()` bukan override `Init(data,bus)`, tidak ada `DeclareEvents()`/`AddEvent()`, include path salah (`#include <PASR/Core/IManager.h>` — ekstensi `.h` tidak ada), include `<PASR/Tools/TickCache.mqh>` tidak ada di repo. **Tidak dapat compile.** | S13 |
| **A1** | 🟠 HIGH | `Analysis/SRManager.mqh` | 54KB monolith — perlu decomposition ke SRDetector + SRZoneStore + SRScorer | S13 |
| **A5** | 🟠 HIGH | `Analysis/Pattern/*.mqh` | Pattern subfolder belum diaudit untuk IManager compliance | S13 |
| **AI-?** | 🔴 TBD | `AI/*.mqh` | AI subfolder: ONNX wiring belum diaudit | S13 |
| **P7-?** | 🔴 TBD | `Phase7/*.mqh` | Phase7 subfolder belum diaudit | S13 |
| **DS-?** | 🔴 TBD | `Dashboard/*.mqh` | Dashboard subfolder belum diaudit | S13 |
| **BUG-008** | 🟠 HIGH | `Experts/PASR/PASR_MODULAR.mq5` | File EA tidak ditemukan di repo — perlu konfirmasi path dan commit | S13 |

---

### ✅ RESOLVED — Sprint 1–12

| ID | Severity | File | Fix | Sprint |
|----|----------|------|-----|--------|
| **TR-001** | 🔴 CRITICAL | `Trade/ExitEngine.mqh` | `#include <PASR/Core/IManager.h>` → `.mqh`. Class tidak extend IManager, 5 bugs (T01–T05) termasuk infinite loop EVENT_ID_EMERGENCY_STOP re-dispatch (T12). Fully rewritten ke v2.01 dengan IManager pipeline integration | S12 (S3A) |
| **TR-002** | 🔴 CRITICAL | `Trade/PositionManager.mqh` | `Initialize(CEventBus*)` bukan true override → `m_data` selalu NULL (crash). `DeclareEvents()` pakai `m_bus.Subscribe()` langsung → double-subscribe. Event ID `TRADE_CLOSED`/`TRADE_OPENED` tidak ada → `POSITION_UPDATE`. Rewritten ke v3.00 | S12 (S3A) |
| **TR-003** | 🔴 CRITICAL | `Trade/RiskManager.mqh` | Double-accumulation dailyLoss: `OnTradeClosed()` + `OnEvent(POSITION_UPDATE)` keduanya akumulasi P&L → daily limit hit 2x lebih cepat. Fix: `OnTradeClosed()` hapus akumulasi (v2.02 BUG-T13). Guard ev.profit≠0 ditambah (v2.01 BUG-T06) | S12 (S3B) |
| **TR-004** | 🟠 HIGH | `Trade/ExecutionManager.mqh` | SL/TP tidak divalidasi terhadap `SYMBOL_TRADE_STOPS_LEVEL` sebelum order dikirim → broker reject `TRADE_RETCODE_INVALID_STOPS` jika price bergerak antara TradePlan creation dan execution. Fix: `ClampStopsToMinLevel()` dengan safety margin 1.1× (v3.02 BUG-T14) | S12 (S3B) |
| **TR-005** | 🟡 MEDIUM | `Trade/RecoveryManager.mqh` | `IsRecoveryAllowed()` + `RecordRecoveryAttempt()` + `OnNewBar()` daily reset menggunakan `TimeToStruct().day` (day-of-month 1–31) sebagai key unik. Pada tanggal 1 di bulan berbeda, counter reset prematur. Fix: midnight-floor datetime `(datetime)(now - now%86400)` — konsisten dengan RiskManager pattern (v2.18 BUG-T07) | S12 (S3B) |
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
| X1–X7 | 🔴 CRITICAL | `Core/PASR_Executor.mqh` | **DELETED** — 2024 monolith zombie. 7 bugs: no IManager, `Sleep()` recursive deadlock, enum collision, duplicate structs. Superseded by `CExecutionManager` + `CAsyncOrderManager` | S9 |
| A2 | 🟠 HIGH | `Analysis/Optimized/` | **DELETED** entire folder (6 files) — orphaned parallel refactoring experiment | S9 |
| A3 | 🟡 LOW | `Analysis/OPTIMIZATION_SUMMARY.md` | **DELETED** — dev artifact | S9 |
| S8-001 | 🔴 CRITICAL | `Core/Events.mqh` | Added missing `EVENT_ID_PRICE_UPDATE`, `EVENT_ID_TIMER`, `EVENT_ID_POSITION_UPDATE` | S8 |
| S8-005 | 🔴 CRITICAL | `Core/Events.mqh` | Removed non-existent `data_i[]` array from `PASREvent`. Replaced with `data1`/`data2` double fields | S8 |
| N01 | 🔴 CRITICAL | `Core/PipelineEngine.mqh` | `Stage_AnalysisSR` push event tanpa dispatch — SR `OnEvent()` tidak pernah fired di timer path | S11 |
| N03 | 🟠 HIGH | `Core/Orchestrator.mqh` | `OnDeinit()` double-shutdown: manual teardown + `FreeAll()` keduanya jalan. Fix: `OnDeinit()` hanya stop timer + log | S11 |
| N04 | 🟠 HIGH | `Core/PipelineEngine.mqh` | `Stage_RiskCheck` overwrite `ctx.exit_reason` pada soft rejection → false-alarm exit trigger. Fix: hanya `exit_message` yang ditulis | S11 |
| N06 | 🟠 HIGH | `Core/Orchestrator.mqh` | `RegisterManager()` crash jika `m_bus == NULL`. Fix: early-return guard | S11 |
| N07 | 🔴 CRITICAL | `Core/PipelineEngine.mqh` | `SkipIfNull()` menggunakan `CheckPointer(void*)` — undefined behavior, semua 14 stage guard tidak berfungsi. Fix: plain `ptr == NULL` check | S11 |
| BUG-S10-001 | 🔴 CRITICAL | `Signal/SignalFilterPipeline.mqh` | `support`/`resistance` undefined — compile error | S11 |
| BUG-S10-002 | 🟠 HIGH | `Signal/SignalFilterPipeline.mqh` | `RunCustomFilters()` tidak pernah dipanggil dari `RunCompletePipeline()` | S11 |
| BUG-S10-003 | 🟠 HIGH | `Signal/SignalFilterPipeline.mqh` | MTF `referencePrice` menggunakan tick price bukan bar close | S11 |
| BUG-S10-004 | 🔴 CRITICAL | `Signal/SignalManager.mqh` | Call site `RunCompletePipeline()` signature mismatch (3 vs 5 param) — compile error | S11 |

---

## Sprint History

| Sprint | Focus | Key Deliverables |
|--------|-------|------------------|
| S1 | Compile fixes | BUG-007, BUG-008, BUG-012 |
| S2 | Architecture integrity | BUG-001–006, BUG-009–011 |
| S8 | Runtime state ownership | SessionState wiring, Events.mqh fixes |
| S9 | Orchestrator residuals + Analysis cleanup | O1, O4, O7, O8, X1–X7, A2–A3 |
| S10 | Signal layer audit (planned → executed S11) | SignalFilterPipeline, SignalManager wiring |
| S11 | PipelineEngine + Orchestrator hardening | N01, N03, N04, N06, N07, BUG-S10-001–004 |
| S12 | Trade subfolder audit | TR-001 (ExitEngine), TR-002 (PositionManager), TR-003 (RiskManager), TR-004 (ExecutionManager), TR-005 (RecoveryManager). **TR-006 (CorrelationManager) OPEN** |
| S13 | CorrelationManager migration + AI/Phase7/Dashboard audit | _(planned)_ |

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
| `Trade/ExecutionManager.mqh` | v3.02 | S12 | ✅ Stable |
| `Trade/RiskManager.mqh` | v2.02 | S12 | ✅ Stable |
| `Trade/RecoveryManager.mqh` | v2.18 | S12 | ✅ Stable |
| `Trade/ExitEngine.mqh` | v2.01 | S12 | ✅ Stable |
| `Trade/PositionManager.mqh` | v3.00 | S12 | ✅ Stable |
| `Trade/TradePlan.mqh` | — | S12 | ✅ Stable |
| `Trade/RecoveryEngine.mqh` | — | S12 | ✅ Stable |
| `Trade/CorrelationManager.mqh` | v1.0 | — | 🔴 TR-006 OPEN — compile error |
| `Analysis/SRManager.mqh` | — | — | ⚠️ Audit needed (54KB) |
| `Analysis/Pattern/*.mqh` | — | — | ⚠️ Audit needed |
| `AI/*.mqh` | — | — | 🔴 Not audited |
| `Phase7/*.mqh` | — | — | 🔴 Not audited |
| `Dashboard/*.mqh` | — | — | 🔴 Not audited |

---

© 2026 Agsicentre — PASR EA. All rights reserved.
