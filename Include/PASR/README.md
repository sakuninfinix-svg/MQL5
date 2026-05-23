# PASR — Price Action Support Resistance EA

> **Architecture:** Pipeline Orchestration (migrated from Monolith v9, Sprint 1–16)
> **Last updated:** Sprint 16 (2026-05-24)
> **Compile target:** `Experts/PASR_MODULAR.mq5`

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
              Stage  7: AIInference      ← CAIOrchestrator v2.02 (26-dim, real SGD, ensemble diversity)
              Stage  8: RiskCheck        ← CRiskManager + CCorrelationManager + IsSpreadAcceptable()
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
│   ├── SRManager.mqh        ← ⚠ 54KB — Sprint 17 decomposition target
│   ├── ZoneManager.mqh      ← Supply/Demand zones
│   ├── MarketRegimeDetector.mqh
│   ├── AdaptiveParameterManager.mqh
│   └── Pattern/             ← Candlestick pattern sub-module (audit pending S17)
│
├── Signal/                  ← v4.02 — Signal generation & regime filtering
│   ├── SignalManager.mqh    ← v4.02 — aggregator, 4 sources
│   └── SignalFilterPipeline.mqh ← v1.02 — MTF + custom filter pipeline
│
├── Trade/                   ← ✅ S13 Fully Audited — 8 files
│   ├── ExecutionManager.mqh ← v3.02 — async retry + stops clamp
│   ├── RiskManager.mqh      ← v2.02 — circuit breaker, daily loss, lot calc
│   ├── RecoveryManager.mqh  ← v2.18 — fakeout detection, partial close
│   ├── RecoveryEngine.mqh   ← struct + state machine per position
│   ├── ExitEngine.mqh       ← v2.01 — Chandelier + Structure + ProfitFade exits
│   ├── PositionManager.mqh  ← v3.00 — pipeline-aware scanner, ScanPositions(ctx)
│   ├── TradePlan.mqh        ← struct TradePlan
│   └── CorrelationManager.mqh ← ✅ v2.00 — IManager pipeline, S13
│
├── AI/                      ← ✅ S16 Fully Audited — 7 bugs resolved
│   ├── AITypes.mqh          ← Shared structs, zero deps
│   ├── AIOrchestrator.mqh   ← v2.02 — AI-001,003,005 fixed; InjectContext, open-feat cache
│   ├── AIFeatureBuilder.mqh ← v2.01 — AI-001,002,006 fixed; pending inject, 4x ATR, baseline shift
│   ├── AIInference.mqh      ← v2.01 — AI-007 fixed; MathTanh(), seed param, SGDUpdate()
│   ├── AIEnsemble.mqh       ← v2.01 — AI-004 fixed; seed table {42,137,271,919}, GetModel()
│   ├── AITrainer.mqh        ← v2.01 — AI-003 fixed; RunSGD() via SetEnsemble() wiring
│   ├── AICalibrationBridge.mqh
│   ├── ConfidenceCalibrator.mqh
│   ├── AISignalSource.mqh
│   ├── ModelRegistry.mqh
│   ├── ONNXBridge.mqh
│   └── OnlineLearningGuard.mqh
│
├── Phase7/                  ← HealthMonitor, SnapshotManager, SessionState (audit pending S17)
└── Dashboard/               ← Chart rendering, telemetry, journal (audit pending S17)

Experts/
├── PASR_MODULAR.mq5         ← ✅ EA entry point v13.00 (confirmed path — root Experts/ folder)
├── PASR.mq5                 ← Legacy monolith (deprecated, do not extend)
└── PASR/                    ← Reserved folder (empty / future multi-symbol variant)
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
| **A1** | 🟠 HIGH | `Analysis/SRManager.mqh` | 54KB monolith — perlu decomposition ke SRDetector + SRZoneStore + SRScorer | S17 |
| **A5** | 🟠 HIGH | `Analysis/Pattern/*.mqh` | Pattern subfolder belum diaudit untuk IManager compliance | S17 |
| **P7-?** | 🔴 TBD | `Phase7/*.mqh` | Phase7 subfolder belum diaudit | S17 |
| **DS-?** | 🔴 TBD | `Dashboard/*.mqh` | Dashboard subfolder belum diaudit | S17 |

---

### ✅ RESOLVED — Sprint 1–16

| ID | Severity | File | Fix | Sprint |
|----|----------|------|-----|--------|
| **AI-001** | 🟠 HIGH | `AI/AIFeatureBuilder.mqh` | `InjectStructure()`/`InjectRegime()` sekarang menulis ke **pending buffer** (`m_pending_*`). `Build()` apply pending buffer ke `f[]` sebelum copy-out — injection selalu masuk ke feature vector. `AIOrchestrator::InjectContext()` harus dipanggil sebelum `Predict()`. | S16 |
| **AI-002** | 🔴 CRITICAL | `AI/AIFeatureBuilder.mqh` | `ATRRatio()` monolitik dihapus — diganti `ATRRatioByHandle(handle)`. Dibuat 4 handle terpisah: `m_hATR3`, `m_hATR5`, `m_hATR10`, `m_hATR20`. Feature f[4]–f[7] kini return nilai berbeda (genuine multi-period volatility). | S16 |
| **AI-003** | 🔴 CRITICAL | `AI/AITrainer.mqh` + `AI/AIInference.mqh` | `MaybeRetrain()` memanggil `RunSGD(mini_batch)` yang melakukan real backprop via `CAIInference::SGDUpdate()`. `CAIInference` mendapat method `SGDUpdate()` baru (full backprop: output layer, hidden2, hidden1). `CAITrainer` menerima ensemble pointer via `SetEnsemble()`. `CAIOrchestrator::Initialize()` memanggil `m_trainer->SetEnsemble(m_ensemble)`. | S16 |
| **AI-004** | 🟠 HIGH | `AI/AIEnsemble.mqh` | Seed table `AI_ENSEMBLE_SEEDS[] = {42, 137, 271, 919}` ditambah. Setiap `CAIInference` dibuat dengan seed berbeda via `new CAIInference(AI_ENSEMBLE_SEEDS[i])`. Weights Xavier-random kini unik per model. `agreement` tidak lagi selalu 1.0. | S16 |
| **AI-005** | 🟡 MEDIUM | `AI/AIOrchestrator.mqh` | `m_open_features` (SAIFeatureVector) di-cache saat `EVENT_ID_TRADE_OPEN`. `OnTradeResult()` menggunakan cached features jika valid, fallback ke `GetLastFeatures()` jika tidak ada cached (posisi dibuka sebelum AI init). | S16 |
| **AI-006** | 🟡 MEDIUM | `AI/AIFeatureBuilder.mqh` | `UpdateBaselines()` menggunakan `CopyBuffer(m_hATR14, 0, 1, 1, atrVal)` dan `iVolume(..., 1)` — explicit `shift=1`. Partial lookahead pada baselines dihilangkan. | S16 |
| **AI-007** | 🟡 MEDIUM | `AI/AIInference.mqh` | `Tanh(double x)` diganti dari `(exp(2x)-1)/(exp(2x)+1)` ke `return MathTanh(x)`. Tidak ada double-`exp()`, tidak ada NaN pada x > 350. | S16 |
| **BUG-008** | 🟠 HIGH | `Experts/PASR_MODULAR.mq5` | Path dikonfirmasi: `Experts/PASR_MODULAR.mq5` (root, bukan subfolder). README compile target dikoreksi. | S15 |
| **TR-006** | 🔴 CRITICAL | `Trade/CorrelationManager.mqh` | Full migration v1.0 → v2.00: IManager extend, DeclareEvents(), OnEvent(), RefreshSymbolList(), Shutdown() double-free guard. | S13 |
| **TR-001** | 🔴 CRITICAL | `Trade/ExitEngine.mqh` | Infinite loop emergency stop, IManager rewrite v2.01 | S12 |
| **TR-002** | 🔴 CRITICAL | `Trade/PositionManager.mqh` | `m_data` always NULL, double-subscribe fix, rewrite v3.00 | S12 |
| **TR-003** | 🔴 CRITICAL | `Trade/RiskManager.mqh` | Double-accumulation dailyLoss fix v2.02 | S12 |
| **TR-004** | 🟠 HIGH | `Trade/ExecutionManager.mqh` | SL/TP stops-level clamp v3.02 | S12 |
| **TR-005** | 🟡 MEDIUM | `Trade/RecoveryManager.mqh` | Day-of-month key → midnight-floor datetime fix v2.18 | S12 |
| BUG-001 | 🔴 CRITICAL | `Core/Globals.mqh` | Removed `CEventBus::Instance()` fake singleton | S2 |
| BUG-002 | 🔴 CRITICAL | `Core/Orchestrator.mqh` | Removed monolith `ProcessNewBar()` fallback in OnTick | S2 |
| BUG-003 | 🔴 CRITICAL | `Core/PipelineEngine.mqh` | All 7 empty stage stubs implemented | S2 |
| BUG-004 | 🔴 CRITICAL | `Core/Orchestrator.mqh` | HealthMonitor + SnapshotManager registered via `InitManager()` | S2 |
| BUG-005 | 🔴 CRITICAL | `Core/Orchestrator.mqh` | `FreeAll()` strict reverse init order, EventBus deleted last | S2 |
| BUG-006 | 🟠 HIGH | `Core/PipelineEngine.mqh` | `InjectManagers()` stores health/snapshot fields | S2 |
| BUG-007 | 🔴 CRITICAL | `Core/PipelineEngine.mqh` | Fixed 3 wrong `#include` paths | S1 |
| BUG-008-S1 | 🔴 CRITICAL | `Experts/PASR_MODULAR.mq5` | Macro `QA_BUILD` → `PASR_QA_BUILD` | S1 |
| BUG-009 | 🔴 CRITICAL | `Core/Orchestrator.mqh` | Constructor init list: `m_health(NULL)`, `m_snapshot(NULL)`, `m_session(NULL)` | S2 |
| BUG-010 | 🟡 MEDIUM | `Core/Orchestrator.mqh` | Eliminated redundant double `DrainQueue()` | S2 |
| BUG-011 | 🟡 MEDIUM | `Core/PipelineEngine.mqh` | Ticket hardcode `0` → `ctx.exec_result.ticket` | S2 |
| BUG-012 | 🟡 MEDIUM | `Core/Globals.mqh` | `_MagicNumber` → explicit `magic` param | S1 |
| O1 | 🔴 CRITICAL | `Core/Orchestrator.mqh` | `ENUM_PIPELINE_STAGE` undefined type fix | S9 |
| O4 | 🟠 HIGH | `Core/Orchestrator.mqh` | SessionState init wiring fixed | S9 |
| O7 | 🔴 CRITICAL | `Core/Orchestrator.mqh` | `BarChanged()` double-flip race → `m_new_bar_flag` pattern | S9 |
| O8 | 🟠 HIGH | `Core/Orchestrator.mqh` | `CJournalManager` passed as NULL → owned member `m_journal` | S9 |
| X1–X7 | 🔴 CRITICAL | `Core/PASR_Executor.mqh` | DELETED — monolith zombie, 7 bugs | S9 |
| A2 | 🟠 HIGH | `Analysis/Optimized/` | DELETED entire orphaned folder | S9 |
| A3 | 🟡 LOW | `Analysis/OPTIMIZATION_SUMMARY.md` | DELETED dev artifact | S9 |
| S8-001 | 🔴 CRITICAL | `Core/Events.mqh` | Added missing event IDs | S8 |
| S8-005 | 🔴 CRITICAL | `Core/Events.mqh` | Removed non-existent `data_i[]` from `PASREvent` | S8 |
| N01 | 🔴 CRITICAL | `Core/PipelineEngine.mqh` | Stage_AnalysisSR event dispatch fix | S11 |
| N03 | 🟠 HIGH | `Core/Orchestrator.mqh` | OnDeinit() double-shutdown fix | S11 |
| N04 | 🟠 HIGH | `Core/PipelineEngine.mqh` | Stage_RiskCheck false-alarm exit fix | S11 |
| N06 | 🟠 HIGH | `Core/Orchestrator.mqh` | RegisterManager() NULL bus guard | S11 |
| N07 | 🔴 CRITICAL | `Core/PipelineEngine.mqh` | SkipIfNull() undefined behavior fix | S11 |
| BUG-S10-001 | 🔴 CRITICAL | `Signal/SignalFilterPipeline.mqh` | `support`/`resistance` undefined compile error | S11 |
| BUG-S10-002 | 🟠 HIGH | `Signal/SignalFilterPipeline.mqh` | `RunCustomFilters()` never called from pipeline | S11 |
| BUG-S10-003 | 🟠 HIGH | `Signal/SignalFilterPipeline.mqh` | MTF referencePrice: tick price → bar close | S11 |
| BUG-S10-004 | 🔴 CRITICAL | `Signal/SignalManager.mqh` | `RunCompletePipeline()` signature mismatch compile error | S11 |

---

## Sprint History

| Sprint | Focus | Key Deliverables |
|--------|-------|------------------|
| S1 | Compile fixes | BUG-007, BUG-008-S1, BUG-012 |
| S2 | Architecture integrity | BUG-001–006, BUG-009–011 |
| S8 | Runtime state ownership | SessionState wiring, Events.mqh |
| S9 | Orchestrator residuals + Analysis cleanup | O1, O4, O7, O8, X1–X7, A2–A3 |
| S10 | Signal layer (merged → S11) | — |
| S11 | PipelineEngine + Orchestrator hardening | N01, N03, N04, N06, N07, BUG-S10-001–004 |
| S12 | Trade subfolder audit | TR-001–005 resolved, TR-006 carried to S13 |
| S13 | CorrelationManager migration | TR-006 resolved (v1.0 → v2.00 full IManager rewrite) |
| S14 | AI subfolder audit | AI-001..AI-007 ditemukan (7 bugs) |
| S15 | BUG-008 path confirmation + README sync | BUG-008 resolved |
| S16 | AI subfolder fixes | AI-001..AI-007 **resolved** — inject order, 4x ATR, real SGD, ensemble seeds, stale-feature cache, baseline shift=1, MathTanh() |
| S17 | Phase7 + Dashboard audit + SRManager decomposition | _(planned)_ |

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
| `Trade/CorrelationManager.mqh` | v2.00 | S13 | ✅ Stable |
| `AI/AIOrchestrator.mqh` | v2.02 | S16 | ✅ Stable |
| `AI/AIFeatureBuilder.mqh` | v2.01 | S16 | ✅ Stable |
| `AI/AIInference.mqh` | v2.01 | S16 | ✅ Stable |
| `AI/AIEnsemble.mqh` | v2.01 | S16 | ✅ Stable |
| `AI/AITrainer.mqh` | v2.01 | S16 | ✅ Stable |
| `AI/AITypes.mqh` | — | S14 | ✅ Clean |
| `Experts/PASR_MODULAR.mq5` | v13.00 | S15 | ✅ Path confirmed |
| `Analysis/SRManager.mqh` | — | — | ⚠️ Audit needed (54KB) |
| `Analysis/Pattern/*.mqh` | — | — | ⚠️ Audit needed |
| `Phase7/*.mqh` | — | — | 🔴 Not audited |
| `Dashboard/*.mqh` | — | — | 🔴 Not audited |

---

© 2026 Agsicentre — PASR EA. All rights reserved.
