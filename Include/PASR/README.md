# PASR — Price Action Support Resistance EA

> **Architecture:** Pipeline Orchestration (migrated from Monolith v9, Sprint 1–14)
> **Last updated:** Sprint 14 (2026-05-24)
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
              Stage  7: AIInference      ← CAIOrchestrator (26-dim MLP/ONNX)
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
│   ├── SRManager.mqh        ← ⚠ 54KB — Sprint 15 decomposition target
│   ├── ZoneManager.mqh      ← Supply/Demand zones
│   ├── MarketRegimeDetector.mqh
│   ├── AdaptiveParameterManager.mqh
│   └── Pattern/             ← Candlestick pattern sub-module (audit pending)
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
├── AI/                      ← ⚠ S14 Audited — 7 bugs found (AI-001..AI-007)
│   ├── AITypes.mqh          ← Shared structs, zero deps
│   ├── AIOrchestrator.mqh   ← v2.01 — top-level AI subsystem (IManager)
│   ├── AIFeatureBuilder.mqh ← 26-dim feature eng, IManager, FIX#4 leakage guard
│   ├── AIInference.mqh      ← MLP 26→64→32→1, random init (no ONNX yet)
│   ├── AIEnsemble.mqh       ← Weighted ensemble, 2 models
│   ├── AITrainer.mqh        ← Circular buffer, online retrain trigger
│   ├── AICalibrationBridge.mqh
│   ├── ConfidenceCalibrator.mqh
│   └── OnlineLearningGuard.mqh
│
├── Phase7/                  ← HealthMonitor, SnapshotManager, SessionState (audit pending S15)
└── Dashboard/               ← Chart rendering, telemetry, journal (audit pending S15)
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
| **AI-001** | 🟠 HIGH | `AI/AIFeatureBuilder.mqh` | `InjectStructure()` / `InjectRegime()` memodifikasi `m_last_features[]` **setelah** `Build()` selesai — tapi `Build()` sudah copy ke `out.features` sebelum inject dipanggil. Artinya feature vector yang masuk ke `CAIInference::Forward()` **tidak pernah mengandung** injected structure/regime data. Pipeline: `Build(fv)` → `Vote(fv,...)` tapi inject dipanggil belakangan oleh orchestrator eksternal. Fix: `InjectStructure()` dan `InjectRegime()` harus dipanggil **sebelum** `Build()`, atau `Build()` harus menerima struct context. | S15 |
| **AI-002** | 🔴 CRITICAL | `AI/AIFeatureBuilder.mqh` | `ATRRatio(int period)` menerima parameter `period` (3/5/10/20) tapi **mengabaikannya** — selalu menggunakan satu handle `m_hATR14`. Semua 4 ATR features (f[4]–f[7]) return nilai **identik**, bukan multi-period volatility. Fix: buat 4 handle ATR terpisah (periode 3, 5, 10, 20) atau gunakan `CopyBuffer` dengan period berbeda. | S15 |
| **AI-003** | 🔴 CRITICAL | `AI/AITrainer.mqh` | `MaybeRetrain()` hanya print log dan reset counter — **tidak memanggil SGD update apapun** pada model weights. `m_lr` dideklarasi tapi tidak pernah digunakan. Trainer adalah **no-op**: online learning tidak terjadi. Fix: implementasi SGD weight update pada `CAIInference` model, atau dispatch `EVENT_AI_MODEL_UPDATED` via bus agar model pull weights baru. | S15 |
| **AI-004** | 🟠 HIGH | `AI/AIEnsemble.mqh` | Dua model ensemble dibuat dengan `new CAIInference()` tapi keduanya dipanggil `Initialize(bus)` yang memanggil `InitRandomWeights()` dengan `MathSrand(42)` — **seed sama, weights identik**. Ensemble 2 model menghasilkan output yang persis sama, `agreement` selalu 1.0. Fix: set seed berbeda per model atau load weights berbeda per model. | S15 |
| **AI-005** | 🟡 MEDIUM | `AI/AIOrchestrator.mqh` | `OnTradeResult()` memanggil `m_feat->GetLastFeatures()` untuk membuat training sample — tapi `GetLastFeatures()` return pointer ke `m_last_features[]` yang sudah berisi features dari **build terakhir**, bukan dari trade yang menghasilkan profit/loss ini. Jika ada beberapa bar antara entry dan exit, features sudah stale. Fix: cache `SAIFeatureVector` saat trade open (di `OnEvent(EVENT_ID_TRADE_OPEN)`), gunakan cached features saat trade close. | S15 |
| **AI-006** | 🟡 MEDIUM | `AI/AIFeatureBuilder.mqh` | `GetIndicatorValue()` menerima `shift` parameter tapi fungsi internal `ATRRatio()` memanggil dengan `shift=0` — kemudian FIX#4 guard mengubah ke `shift=1`. Namun `UpdateBaselines()` juga memanggil `GetIndicatorValue(m_hATR14, 0, 0)` **tanpa** melewati guard karena dipanggil sebelum `m_useClosedBarsOnly` check. Baselines di-update dari bar yang masih open (current bar) — partial lookahead masih ada untuk baselines. Fix: gunakan `shift=1` eksplisit di `UpdateBaselines()`. | S15 |
| **AI-007** | 🟡 MEDIUM | `AI/AIInference.mqh` | `Tanh()` implementasi manual: `(exp(2x)-1)/(exp(2x)+1)` menghitung `exp(2x)` **dua kali**. Untuk x > 350, `MathExp(2x)` overflow ke `INF` → `INF/INF = NaN` → output NaN masuk ke pipeline. MQL5 memiliki `MathTanh()` built-in. Fix: ganti dengan `return MathTanh(x)`. | S15 |
| **A1** | 🟠 HIGH | `Analysis/SRManager.mqh` | 54KB monolith — perlu decomposition ke SRDetector + SRZoneStore + SRScorer | S15 |
| **A5** | 🟠 HIGH | `Analysis/Pattern/*.mqh` | Pattern subfolder belum diaudit untuk IManager compliance | S15 |
| **P7-?** | 🔴 TBD | `Phase7/*.mqh` | Phase7 subfolder belum diaudit | S15 |
| **DS-?** | 🔴 TBD | `Dashboard/*.mqh` | Dashboard subfolder belum diaudit | S15 |
| **BUG-008** | 🟠 HIGH | `Experts/PASR/PASR_MODULAR.mq5` | File EA tidak ditemukan di repo — perlu konfirmasi path dan commit | S15 |

---

### ✅ RESOLVED — Sprint 1–13

| ID | Severity | File | Fix | Sprint |
|----|----------|------|-----|--------|
| **TR-006** | 🔴 CRITICAL | `Trade/CorrelationManager.mqh` | Full migration v1.0 → v2.00: (A) `#include IManager.h` → `.mqh`. (B) class tidak extend IManager → `public IManager` explicit. (C) member fields `m_data`/`m_bus` ditambah. (D) `Initialize()` monolith → `Init(data,bus)` override. (E) `DeclareEvents()` ditambah: subscribe `EVENT_ID_NEW_BAR` + `EVENT_ID_TIMER`. (F) `OnEvent()` ditambah: NEW_BAR → `RefreshSymbolList()` + `UpdateMatrix()`, TIMER → staleness check. (G) `RefreshSymbolList()` baru: build tracked symbols dari open positions. (H) `OnTick(string)/OnTimer()/OnTrade()` monolith overrides dihapus. (I) `Shutdown()` guard double-free + `m_bus=NULL`. (J) `GetStats()` helper ditambah. Note: `TickCache.mqh` include dihapus — tidak dibutuhkan, `CopyClose()` digunakan langsung | S13 |
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
| BUG-008 | 🔴 CRITICAL | `Experts/PASR/PASR_MODULAR.mq5` | Macro `QA_BUILD` → `PASR_QA_BUILD` | S1 |
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
| S1 | Compile fixes | BUG-007, BUG-008, BUG-012 |
| S2 | Architecture integrity | BUG-001–006, BUG-009–011 |
| S8 | Runtime state ownership | SessionState wiring, Events.mqh |
| S9 | Orchestrator residuals + Analysis cleanup | O1, O4, O7, O8, X1–X7, A2–A3 |
| S10 | Signal layer (planned → S11) | — |
| S11 | PipelineEngine + Orchestrator hardening | N01, N03, N04, N06, N07, BUG-S10-001–004 |
| S12 | Trade subfolder audit | TR-001–005 resolved, TR-006 carried to S13 |
| S13 | CorrelationManager migration | TR-006 resolved (v1.0 → v2.00 full IManager rewrite) |
| S14 | AI subfolder audit | AI-001..AI-007 ditemukan (7 bugs): inject order, ATR multi-period, trainer no-op, ensemble seed, stale features, baseline lookahead, Tanh NaN overflow |
| S15 | AI fixes + Phase7 + Dashboard audit | _(planned)_ |

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
| `AI/AIOrchestrator.mqh` | v2.01 | S14 | ⚠️ Bugs AI-001..AI-007 |
| `AI/AIFeatureBuilder.mqh` | — | S14 | ⚠️ Bugs AI-001, AI-002, AI-006 |
| `AI/AIInference.mqh` | — | S14 | ⚠️ Bug AI-007 |
| `AI/AIEnsemble.mqh` | — | S14 | ⚠️ Bug AI-004 |
| `AI/AITrainer.mqh` | — | S14 | ⚠️ Bug AI-003 (trainer no-op) |
| `AI/AITypes.mqh` | — | S14 | ✅ Clean |
| `Analysis/SRManager.mqh` | — | — | ⚠️ Audit needed (54KB) |
| `Analysis/Pattern/*.mqh` | — | — | ⚠️ Audit needed |
| `Phase7/*.mqh` | — | — | 🔴 Not audited |
| `Dashboard/*.mqh` | — | — | 🔴 Not audited |

---

© 2026 Agsicentre — PASR EA. All rights reserved.
