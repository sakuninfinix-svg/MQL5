# PASR — Price Action Support Resistance EA

> **Architecture:** Pipeline Orchestration (migrated from Monolith v9, Sprint 1–9)  
> **Last updated:** Sprint 9 (2026-05-23)  
> **Compile target:** `Experts/PASR/PASR_MODULAR.mq5`

---

## Architecture Overview

PASR menggunakan **Pipeline Orchestration** — semua logika dieksekusi sebagai stage berurutan di dalam `CPipelineEngine::ExecutePipeline()` yang dipanggil dari `OnTimer()`.

```
OnTick()  → Push EVENT_PRICE_UPDATE / EVENT_NEW_BAR → DrainQueue()
OnTimer() → CPipelineEngine::ExecutePipeline(PipelineContext)
              Stage  1: DataSync
              Stage  2: AnalysisSR      ← CAnalysisSRManager
              Stage  3: AnalysisZone    ← CAnalysisZoneManager
              Stage  4: PatternRec      ← CPatternManager
              Stage  5: RegimeDetect    ← CRegimeFilter
              Stage  6: SignalGen       ← CSignalManager (4 sources, weighted vote)
              Stage  7: AIInference     ← CAIOrchestrator (26-dim ONNX)
              Stage  8: RiskCheck       ← CRiskManager
              Stage  9: AdaptiveParams  ← CAdaptiveParameterManager
              Stage 10: Execution       ← CExecutionManager
              Stage 11: PosMgmt         ← (trailing/BE via RecoveryManager)
              Stage 12: Recovery        ← CRecoveryManager
              Stage 13: Dashboard       ← CDashboardManager
              Stage 14: Journal         ← CJournalManager
OnTradeTransaction() → RecoveryManager + SessionState + AIOrchestrator backprop
```

---

## Folder Map

```
Include/PASR/
├── Core/                    ← Infrastructure (EventBus, IManager, Pipeline engine)
│   ├── PASR.mqh             ← Master include — use this, never include sub-files directly
│   ├── Orchestrator.mqh     ← Owns all managers, wires OnTick/OnTimer/OnDeinit
│   ├── PipelineEngine.mqh   ← 14-stage execution engine
│   ├── PipelineTypes.mqh    ← PipelineContext, enums, SExecutionResult
│   ├── Events.mqh           ← All ENUM_EVENT_ID definitions
│   ├── EventBus.mqh         ← Pub/sub message bus
│   ├── IManager.mqh         ← Base interface for all managers
│   ├── Globals.mqh          ← GVKey helpers, PASRLog, CPerfTimer
│   ├── AsyncOrderManager.mqh
│   ├── HighFreqTimer.mqh
│   ├── LatencyOptimizer.mqh
│   ├── StateOwnershipMap.mqh
│   └── PASR_SymbolManager.mqh
│
├── Analysis/                ← Market analysis managers
│   ├── SRManager.mqh        ← S/R detection (⚠ 54KB, Sprint 10 decomposition target)
│   ├── ZoneManager.mqh      ← Supply/Demand zones
│   ├── MarketRegimeDetector.mqh
│   ├── AdaptiveParameterManager.mqh
│   └── Pattern/             ← Candlestick pattern sub-module (audit pending)
│
├── Signal/                  ← Signal generation & regime filtering
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

## Bug Tracker — Active & Resolved

### 🔴 OPEN — Pending subfolder audits

| ID | Severity | File | Description | Target |
|----|----------|------|-------------|--------|
| A1 | 🟠 HIGH | `Analysis/SRManager.mqh` | 54KB monolith — needs decomposition to SRDetector + SRZoneStore + SRScorer | Sprint 10 |
| A5 | 🟠 HIGH | `Analysis/Pattern/*.mqh` | Pattern subfolder not yet audited for IManager compliance | Sprint 10 |
| SF-? | 🔴 TBD | `Signal/*.mqh` | Signal subfolder: architecture not yet audited | Sprint 10 |
| TR-? | 🔴 TBD | `Trade/*.mqh` | Trade subfolder: architecture not yet audited | Sprint 10 |
| AI-? | 🔴 TBD | `AI/*.mqh` | AI subfolder: ONNX wiring not yet audited | Sprint 10 |
| P7-? | 🔴 TBD | `Phase7/*.mqh` | Phase7 subfolder not yet audited | Sprint 10 |
| DS-? | 🔴 TBD | `Dashboard/*.mqh` | Dashboard subfolder not yet audited | Sprint 10 |

### ✅ RESOLVED — Sprint 1–9

| ID | Severity | File | Fix | Sprint |
|----|----------|------|-----|--------|
| BUG-001 | 🔴 CRITICAL | `Core/Globals.mqh` | Removed `CEventBus::Instance()` fake singleton. Replaced with explicit bus param `PASRDispatchEvent(ev, bus)` | S2 |
| BUG-002 | 🔴 CRITICAL | `Core/Orchestrator.mqh` | Removed monolith `ProcessNewBar()` fallback in OnTick | S2 |
| BUG-003 | 🔴 CRITICAL | `Core/PipelineEngine.mqh` | All 7 empty stage stubs implemented (Stage_AnalysisZone, PatternRec, Recovery, Dashboard, Journal, AdaptiveParams, Execution) | S2 |
| BUG-004 | 🔴 CRITICAL | `Core/Orchestrator.mqh` | HealthMonitor + SnapshotManager now registered via `InitManager()`, properly subscribe to EventBus | S2 |
| BUG-005 | 🔴 CRITICAL | `Core/Orchestrator.mqh` | `FreeAll()` fixed to strict reverse init order. EventBus deleted last | S2 |
| BUG-006 | 🟠 HIGH | `Core/PipelineEngine.mqh` | `InjectManagers()` now stores health/snapshot into `m_health`/`m_snapshot` member fields | S2 |
| BUG-007 | 🔴 CRITICAL | `Core/PipelineEngine.mqh` | Fixed 3 wrong `#include` paths (RegimeFilter, RiskManager, AdaptiveParameterManager) | S1 |
| BUG-008 | 🔴 CRITICAL | `Experts/PASR/PASR_MODULAR.mq5` | Macro renamed `QA_BUILD` → `PASR_QA_BUILD` to match all `#ifdef` guards | S1 |
| BUG-009 | 🔴 CRITICAL | `Core/Orchestrator.mqh` | Constructor init list completed: `m_health(NULL)`, `m_snapshot(NULL)` added | S2 |
| BUG-010 | 🟡 MEDIUM | `Core/Orchestrator.mqh` | Eliminated redundant double `DrainQueue()` call in OnTick | S2 |
| BUG-011 | 🟡 MEDIUM | `Core/PipelineEngine.mqh` | `Stage_Execution()` ticket hardcoded `0` → uses `ctx.exec_result.ticket` | S2 |
| BUG-012 | 🟡 MEDIUM | `Core/Globals.mqh` | `_MagicNumber` (not MQL5 built-in) replaced with explicit `magic` param in `GVKey()` | S1 |
| O1 | 🔴 CRITICAL | `Core/Orchestrator.mqh` | `ENUM_PIPELINE_STAGE` (undefined type) → `EnumToString(ENUM_STAGE_RESULT)` | S9 |
| O7 | 🔴 CRITICAL | `Core/Orchestrator.mqh` | `BarChanged()` race condition: called twice (OnTick + OnTimer), flipping `m_lastBarTime` twice. Fixed with `m_new_bar_flag` member — set once in OnTick, consumed+reset in OnTimer | S9 |
| O8 | 🟠 HIGH | `Core/Orchestrator.mqh` | `CJournalManager` always passed as `NULL` to `InjectManagers()`. Added as owned member `m_journal`, initialized in `Init()` | S9 |
| X1–X7 | 🔴 CRITICAL | `Core/PASR_Executor.mqh` | **DELETED** — 2024 monolith zombie. 7 bugs: no IManager, `Sleep()` recursive deadlock, `EXEC_NONE`/`EXEC_FAILED` enum collision with PipelineTypes, duplicate `ExecutionRequest` struct, duplicate switch case, no include guard. Superseded by `CExecutionManager` + `CAsyncOrderManager` | S9 |
| A2 | 🟠 HIGH | `Analysis/Optimized/` | **DELETED** entire folder (6 files) — orphaned parallel refactoring experiment, never wired to PASR.mqh or pipeline | S9 |
| A3 | 🟡 LOW | `Analysis/OPTIMIZATION_SUMMARY.md` | **DELETED** — dev artifact, not official documentation | S9 |
| S8-001 | 🔴 CRITICAL | `Core/Events.mqh` | Added missing `EVENT_ID_PRICE_UPDATE`, `EVENT_ID_TIMER`, `EVENT_ID_POSITION_UPDATE` (compile errors in OnTick/OnTimer) | S8 |
| S8-005 | 🔴 CRITICAL | `Core/Events.mqh` | Removed non-existent `data_i[]` array from `PASREvent`. Replaced with `data1`/`data2` double fields | S8 |

---

## Sprint History

| Sprint | Focus | Key Deliverables |
|--------|-------|------------------|
| S1 | Compile fixes | BUG-007, BUG-008, BUG-012 |
| S2 | Architecture integrity | BUG-001–006, BUG-009–011 |
| S8 | Runtime state ownership | SessionState wiring, Events.mqh fixes, health/snapshot injection |
| S9 | Orchestrator residuals + Analysis cleanup | O1, O7, O8, X1–X7 (PASR_Executor deleted), A2–A3 (Optimized/ deleted) |
| S10 | Subfolder audit (planned) | Analysis/Pattern, Signal/, Trade/, AI/, Phase7/, Dashboard/ |

---

## Quick Start

```cpp
// Include ONE file only — never include sub-files directly
#include <PASR/Core/PASR.mqh>

// In OnInit:
COrchestrator orch;
if(orch.Init() != INIT_SUCCEEDED) return INIT_FAILED;
EventSetTimer(1);

// In OnTick:
orch.OnTick();

// In OnTimer:
orch.OnTimer();

// In OnTradeTransaction:
orch.OnTradeTransaction(trans, request, result);

// In OnDeinit:
orch.OnDeinit(reason);
EventKillTimer();
```

---

© 2026 Agsicentre — PASR EA. All rights reserved.
