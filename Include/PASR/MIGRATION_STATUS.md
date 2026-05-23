# PASR Architecture Migration Status

> Last updated: 2026-05-23 | **ALL SPRINTS COMPLETE**

## Migration: Monolith → Pipeline Orchestration

### Status: ✅ COMPLETE (12/12 bugs + 6/6 perf + 5/5 sprint5 tasks resolved)

---

## Bug Fix Tracker

| ID | Severity | File | Description | Status |
|---|---|---|---|---|
| BUG-001 | 🔴 CRITICAL | `Globals.mqh` | `CEventBus::Instance()` singleton palsu | ✅ v2.14 |
| BUG-002 | 🔴 CRITICAL | `Orchestrator.mqh` | Monolith `ProcessNewBar()` fallback di `OnTick()` | ✅ v3.03 |
| BUG-003 | 🔴 CRITICAL | `PipelineEngine.mqh` | 7/12 stage stubs kosong | ✅ v2.01 |
| BUG-004 | 🔴 CRITICAL | `Orchestrator.mqh` | Health+Snapshot tidak register ke IManager | ✅ v3.03 |
| BUG-005 | 🔴 CRITICAL | `Orchestrator.mqh` | `FreeAll()` urutan salah — use-after-free | ✅ v3.03 |
| BUG-006 | 🟠 HIGH | `PipelineEngine.mqh` | `InjectManagers()` tidak simpan health/snapshot | ✅ v2.01 |
| BUG-007 | 🟠 HIGH | `PipelineEngine.mqh` | Include path salah (3 files) | ✅ v2.01 |
| BUG-008 | 🟠 HIGH | `PASR_MODULAR.mq5` | `#define QA_BUILD` vs `#ifdef PASR_QA_BUILD` | ✅ v13.01 |
| BUG-009 | 🟠 HIGH | `Orchestrator.mqh` | Constructor init list incomplete | ✅ v3.03 |
| BUG-010 | 🟡 MEDIUM | `Orchestrator.mqh` | `DrainQueue()` dipanggil 2x per tick | ✅ v3.03 |
| BUG-011 | 🟡 MEDIUM | `PipelineEngine.mqh` | `ticket=0` hardcode di Stage_Execution | ✅ v2.01 |
| BUG-012 | 🟡 MEDIUM | `Globals.mqh` | `_MagicNumber` bukan built-in MQL5 | ✅ v2.14 |

---

## Sprint 4 — Performance Hardening

| Item | File | Description | Status |
|---|---|---|---|
| PERF-001 | `EventBus.mqh` v3.01 | Binary min-heap O(log n) Push/Pop | ✅ Done |
| PERF-002 | `PipelineTypes.mqh` v1.02 | Per-stage 50ms timeout watchdog | ✅ Done |
| PERF-003 | `PipelineTypes.mqh` v1.02 | `positions_count` cache in PipelineContext | ✅ Done |
| PERF-004 | `RiskManager.mqh` | `RISK_CACHE_TTL_MS` equity/balance cache | ✅ Documented |
| PERF-005 | `PipelineEngine.mqh` v2.02 | `stages_timeout` counter + watchdog report | ✅ Done |
| PERF-006 | `EventBus.mqh` v3.01 | `SEventBusStats` telemetry struct | ✅ Done |

---

## Sprint 5 — Dependency Completion & Dedup

| Item | File | Description | Status |
|---|---|---|---|
| S5-001 | — | Confirm all PipelineEngine includes exist | ✅ All present |
| S5-002 | `Analysis/Pattern/README.md` | Pattern/ dir scaffold documented | ✅ Done |
| S5-003 | `Trade/RecoveryEngine.mqh` v2.00 | Deprecated → typedef alias to RecoveryManager | ✅ Done |
| S5-004 | `Signal/ZoneSignalSource.mqh` v1.00 | 3rd PASR pillar Zone signal source created | ✅ Done |
| S5-005 | `Trade/PositionManager.mqh` v2.00 | Pipeline-integrated: `ScanPositions(ctx)` | ✅ Done |

---

## Sprint 6 — QA Infrastructure (PLANNED)

| Item | File | Description | Priority |
|---|---|---|---|
| S6-001 | `QA/MockEventBus.mqh` | Stub bus untuk unit test tanpa MT5 terminal | 🟠 HIGH |
| S6-002 | `QA/MockDataManager.mqh` | Inject tick data dari array (replay) | 🟠 HIGH |
| S6-003 | `QA/PipelineHarness.mqh` | Run pipeline cycle penuh dari MQL5 Script | 🟠 HIGH |
| S6-004 | `QA/AssertHelpers.mqh` | `ASSERT_EQ`, `ASSERT_GT`, `ASSERT_TRUE` macros | 🟡 MEDIUM |
| S6-005 | `Infra/SnapshotManager.mqh` | Async non-blocking file write via timer queue | 🟡 MEDIUM |
| S6-006 | `Signal/ZoneSignalSource.mqh` | Register ke `SignalManager` di `Orchestrator.Init()` | 🟡 MEDIUM |

---

## Complete File Inventory (All Folders Confirmed)

```
Experts/PASR/
  PASR_MODULAR.mq5          v13.01  ✅

Include/PASR/
  Core/
    AsyncOrderManager.mqh           ✅
    ConfigTypes.mqh                 ✅
    EventBus.mqh              v3.01  ✅ (heap)
    EventPool.mqh                   ✅
    Events.mqh                      ✅
    Globals.mqh               v2.14  ✅
    HighFreqTimer.mqh               ✅
    IManager.mqh                    ✅
    LatencyOptimizer.mqh            ✅
    Orchestrator.mqh          v3.03  ✅
    PASR.mqh                        ✅
    PASR.Types.mqh                  ✅
    PASR_Executor.mqh               ✅
    PASR_SymbolManager.mqh          ✅
    PipelineEngine.mqh        v2.01  ✅
    PipelineTypes.mqh         v1.02  ✅
    Config/                         ✅
  Analysis/
    AdaptiveParameterManager.mqh    ✅
    MarketRegimeDetector.mqh        ✅
    SRManager.mqh                   ✅
    ZoneManager.mqh                 ✅
    Pattern/                  scaffold ✅
  Signal/
    ISignalSource.mqh               ✅
    PatternSignalSource.mqh         ✅
    RegimeFilter.mqh                ✅
    RegimeSignalSource.mqh          ✅
    SignalFilter.mqh                ✅
    SignalManager.mqh               ✅
    SRSignalSource.mqh              ✅
    ZoneSignalSource.mqh      v1.00  ✅ NEW
    AI/
      AICalibrationBridge.mqh       ✅
      AIEnsemble.mqh                ✅
      AIFeatureBuilder.mqh          ✅
      AIInference.mqh               ✅
      AIOrchestrator.mqh            ✅
      AISignalSource.mqh            ✅
      AITrainer.mqh                 ✅
      AITypes.mqh                   ✅
      ConfidenceCalibrator.mqh      ✅
      ModelRegistry.mqh             ✅
      ONNXBridge.mqh                ✅
      OnlineLearningGuard.mqh       ✅
  Trade/
    CorrelationManager.mqh          ✅
    ExecutionManager.mqh            ✅
    ExitEngine.mqh                  ✅
    PositionManager.mqh       v2.00  ✅ UPDATED
    RecoveryEngine.mqh        DEPRECATED ✅ (alias)
    RecoveryManager.mqh             ✅
    RiskManager.mqh                 ✅
    TradePlan.mqh                   ✅
  Infra/
    AdaptiveConfig.mqh              ✅
    DataManager.mqh                 ✅
    HealthMonitor.mqh               ✅
    JournalManager.mqh              ✅
    PerformanceReport.mqh           ✅
    SanityManager.mqh               ✅
    SnapshotManager.mqh             ✅
    StateManager.mqh                ✅
    TelemetryRecorder.mqh           ✅
    Optimizations/                  ✅
  QA/                        EMPTY  ⚠️ (Sprint 6)
  UI/                               ✅
  Tools/                            ✅
  Data/                             ✅
  docs/                             ✅
```

---

## Signal Confluence Architecture (Final)

```
SignalManager
  ├─ SRSignalSource      weight=0.40  (S/R level proximity)
  ├─ ZoneSignalSource    weight=0.35  (Supply/Demand zone) ← NEW Sprint 5
  ├─ PatternSignalSource weight=0.25  (Candle pattern)
  ├─ RegimeSignalSource  weight=0.00  (Multiplier/filter, not additive)
  └─ AISignalSource      weight=0.00  (Override if confidence > threshold)

Final score = SR*0.40 + Zone*0.35 + Pattern*0.25
Regime filter: blocks signal if regime != TRENDING
AI override:   if ai_score > 0.75, use AI direction regardless
```

---

## Next: Compile & Test

```
1. MetaEditor → Compile Experts/PASR/PASR_MODULAR.mq5
2. Fix any remaining compile errors (paste to chat)
3. Strategy Tester: visual mode, 1M bars, XAUUSD/EURUSD
4. Check Experts tab output:
     [PASR][Orchestrator] Pipeline initialized OK
     [PASR][Pipeline] Cycle 1 — 14 stages OK
     [PASR][EventBus] Stats: depth=0 peak=3 pushed=47 dropped=0
5. Sprint 6: QA infrastructure (run after stable compile)
```
