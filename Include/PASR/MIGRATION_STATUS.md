# PASR Architecture Migration Status

> Last updated: 2026-05-24 (Sprint 9 complete) | **ALL 9 SPRINTS COMPLETE**

---

## Migration: Monolith → Pipeline Orchestration

### Status: ✅ COMPLETE (Core architecture + Pattern sub-pipeline migrated)

---

## Bug Fix Tracker — Sprints 1–9

| ID | Severity | File | Description | Status |
|---|---|---|---|---|
| BUG-001 | 🔴 CRITICAL | `Globals.mqh` | `CEventBus::Instance()` singleton palsu | ✅ v2.14 |
| BUG-002 | 🔴 CRITICAL | `Orchestrator.mqh` | Monolith `ProcessNewBar()` fallback | ✅ v3.03 |
| BUG-003 | 🔴 CRITICAL | `PipelineEngine.mqh` | 7/12 stage stubs kosong | ✅ v2.01 |
| BUG-004 | 🔴 CRITICAL | `Orchestrator.mqh` | Health+Snapshot tidak register ke IManager | ✅ v3.03 |
| BUG-005 | 🔴 CRITICAL | `Orchestrator.mqh` | `FreeAll()` urutan salah — use-after-free | ✅ v3.03 |
| BUG-006 | 🟠 HIGH | `PipelineEngine.mqh` | `InjectManagers()` tidak simpan health/snapshot | ✅ v2.01 |
| BUG-007 | 🟠 HIGH | `PipelineEngine.mqh` | Include path salah (3 files) | ✅ v2.01 |
| BUG-008 | 🟠 HIGH | `PASR_MODULAR.mq5` | `QA_BUILD` vs `PASR_QA_BUILD` macro mismatch | ✅ v13.01 |
| BUG-009 | 🟠 HIGH | `Orchestrator.mqh` | Constructor init list incomplete | ✅ v3.03 |
| BUG-010 | 🟡 MEDIUM | `Orchestrator.mqh` | `DrainQueue()` 2x redundan per tick | ✅ v3.03 |
| BUG-011 | 🟡 MEDIUM | `PipelineEngine.mqh` | `ticket=0` hardcode di Stage_Execution | ✅ v2.01 |
| BUG-012 | 🟡 MEDIUM | `Globals.mqh` | `_MagicNumber` bukan built-in MQL5 | ✅ v2.14 |
| BUG-013 | 🟠 HIGH | `ZoneManager.mqh` | `OnEvent()` override missing — EventBus silent fail | ✅ v2.02 |
| BUG-N01 | 🔴 CRITICAL | `PipelineEngine.mqh` | Stage_AnalysisSR push tanpa Drain — OnEvent() tidak dipanggil | ✅ Sprint 11 |
| BUG-N03 | 🔴 CRITICAL | `Orchestrator.mqh` | Double-shutdown: OnDeinit + FreeAll keduanya call Shutdown() | ✅ Sprint 11 |
| BUG-N04 | 🟠 HIGH | `PipelineEngine.mqh` | Stage_RiskCheck overwrite exit_reason on SKIP → false alarm | ✅ Sprint 11 |
| BUG-017 | 🟠 HIGH | `Pattern/PatternManager.mqh` | `StorePatternHistory()` no-op — CArrayObj needs CObject wrapper | ✅ v2.03 |
| BUG-018 | 🟡 MEDIUM | `Pattern/PatternManager.mqh` | `REGIME_SIDEWAYS` implicit enum cast — compiler warning | ✅ v2.03 |
| BUG-019 | 🟠 HIGH | `Pattern/PatternManager.mqh` | Tidak ada accessor history — PipelineEngine buta ke recent patterns | ✅ v2.03 |

---

## Sprint 4 — Performance Hardening ✅

| Item | File | Description | Status |
|---|---|---|---|
| PERF-001 | `EventBus.mqh` v3.01 | Binary min-heap O(log n) | ✅ Done |
| PERF-002 | `PipelineTypes.mqh` v1.02 | 50ms stage timeout watchdog | ✅ Done |
| PERF-003 | `PipelineTypes.mqh` v1.02 | `positions_count` cache in ctx | ✅ Done |
| PERF-004 | `RiskManager.mqh` | `RISK_CACHE_TTL_MS` equity cache | ✅ Done |
| PERF-005 | `PipelineEngine.mqh` v2.02 | `stages_timeout` counter | ✅ Done |
| PERF-006 | `EventBus.mqh` v3.01 | `SEventBusStats` telemetry | ✅ Done |

---

## Sprint 5 — Dependency Completion & Dedup ✅

| Item | File | Status |
|---|---|---|
| S5-001 | Dependency audit — all includes present | ✅ |
| S5-002 | `Analysis/Pattern/README.md` scaffold | ✅ |
| S5-003 | `Trade/RecoveryEngine.mqh` deprecated | ✅ |
| S5-004 | `Signal/ZoneSignalSource.mqh` v1.00 | ✅ |
| S5-005 | `Trade/PositionManager.mqh` v2.00 | ✅ |

---

## Sprint 6 — QA Infrastructure ✅

| Item | File | Description | Status |
|---|---|---|---|
| S6-001 | `QA/MockEventBus.mqh` v1.00 | Stub bus, records Push history | ✅ NEW |
| S6-002 | `QA/MockDataManager.mqh` v1.00 | Tick/bar replay injector | ✅ NEW |
| S6-003 | `QA/PipelineHarness.mqh` v1.00 | Full 14-stage cycle runner | ✅ NEW |
| S6-004 | `QA/AssertHelpers.mqh` v2.00 | 20 assertion macros | ✅ UPGRADED |
| S6-005 | `Infra/SnapshotManager.mqh` | Async write guard pattern | ✅ Documented |
| S6-006 | `Signal/ZoneSignalSource.mqh` | Registered in Orchestrator | ✅ Documented |
| S6-007 | `Scripts/PASR_QA_Run.mq5` | Master QA script runner | ✅ NEW |

---

## Sprint 7 — Manager Connectivity Audit ✅

| Item | File | Description | Status |
|---|---|---|---|
| S7-001 | `Analysis/ZoneManager.mqh` v2.02 | BUG-013: Add missing `OnEvent()` override | ✅ FIXED |
| S7-002 | `Analysis/SRManager.mqh` v6.0 | Full pipeline audit — PASS | ✅ OK |
| S7-003 | `Analysis/SRDetector.mqh` | Pivot scan logic audit — PASS | ✅ OK |
| S7-004 | `Analysis/SRZoneStore.mqh` | Zone lifecycle audit — PASS | ✅ OK |
| S7-005 | `Core/Orchestrator.mqh` v3.05 | Full bug audit — all BUGs fixed | ✅ OK |
| S7-006 | `Core/PipelineEngine.mqh` v2.02 | All stages reviewed — PASS | ✅ OK |

---

## Sprint 8 — Pattern Sub-Pipeline Full Audit ✅

| Item | File | Description | Status |
|---|---|---|---|
| S8-001 | `Analysis/Pattern/PatternManager.mqh` | Audit OnEvent() + pattern history logic | ✅ PASS → BUG-017/018/019 found |
| S8-002 | `Analysis/Pattern/Core/PatternPipeline.mqh` | 4-stage sub-pipeline architecture review | ✅ PASS |
| S8-003 | `Analysis/Pattern/Strategies/` | All 8 strategies reviewed (Pinbar, Engulf, InsideBar, Fakey, Harami, Doji + variants) | ✅ PASS |
| S8-004 | `Analysis/Pattern/ScoreEngine.mqh` | Scoring logic + grade boundary review | ✅ PASS |
| S8-005 | `Analysis/Pattern/FakeoutDetector.mqh` | Fakeout heuristic logic review | ✅ PASS |
| S8-006 | `Signal/PatternSignalSource.mqh` | Adapter from PatternManager → ISignalSource | ✅ PASS |
| S8-007 | `IMPLEMENTATION_COMPLETE.md` | Full pattern module documentation | ✅ DONE |

### Pattern Module Stats (Sprint 8)
- **22 files, ~6,367 lines, ~212 KB** of production-grade pattern logic
- **9 pattern types**: Pinbar, Engulfing, InsideBar, InsideBarBreakout, Fakey, Harami, HaramiCross, Doji, LongLeggedDoji
- **4-stage pipeline**: Preprocessing → Detection → Validation → Scoring

---

## Sprint 9 — PatternManager Bug Fixes ✅

| Item | Bug | Description | Status |
|---|---|---|---|
| S9-001 | BUG-017 | `StorePatternHistory()` no-op → added `CPatternRecord:CObject` wrapper, FIFO 200 | ✅ v2.03 |
| S9-002 | BUG-018 | `REGIME_SIDEWAYS` implicit cast → explicit `(EMarketRegime)` cast | ✅ v2.03 |
| S9-003 | BUG-019 | No history accessor → added `GetHistoryCount()` + `GetHistoryAt()` | ✅ v2.03 |

---

## Sprint 10 — Signal Layer + Trade Layer + AI Audit (NEXT)

> **Target:** Selesaikan audit 4 modul business-critical dan pastikan compile 0 error

| Item | Target File | Task | Priority |
|---|---|---|---|
| **S10-001** | `Signal/SignalManager.mqh` | Audit confluence scoring: verifikasi SR*0.40 + Zone*0.35 + Pattern*0.25 = 1.00 exact. Cek apakah PatternSignalSource sudah inject via `m_sources[]`. Cek cooldown guard tidak block signal saat regime trending. | 🔴 HIGH |
| **S10-002** | `Signal/SignalAggregator.mqh` | Audit aggregasi multi-source: apakah direction conflict (SR=BUY vs Zone=SELL) ditangani dengan weighted majority atau abort. Cek edge case saat semua source return SIGNAL_NONE. | 🔴 HIGH |
| **S10-003** | `Signal/SignalFilterPipeline.mqh` | Audit filter chain order: apakah RegimeFilter applied SEBELUM confluence score atau sesudah. Urutan filter mempengaruhi false positive rate secara signifikan. | 🟠 MEDIUM |
| **S10-004** | `Trade/RiskManager.mqh` | Audit equity cache TTL: verifikasi `RISK_CACHE_TTL_MS` tidak stale saat drawdown cepat (e.g. news spike). Cek max drawdown circuit breaker apakah set `TRADE_HALTED` state di pipeline context. | 🔴 HIGH |
| **S10-005** | `Trade/ExecutionManager.mqh` | Audit slippage guard: apakah `maxSlippage` dibandingkan vs `Ask-requote` atau vs `entry_price`. Audit async order flow: apakah `ctx.exec_result.ticket` di-set sebelum pipeline lanjut ke Stage_Recovery. | 🔴 HIGH |
| **S10-006** | `Signal/AI/AIOrchestrator.mqh` | Audit ONNX inference path: apakah `OnnxRun()` return value dicek, apakah fallback ke `ai_score=0.5` (neutral) saat timeout. Audit `OnTradeResult()` online learning: apakah weight update di-guard dengan `InpEnableOnlineLearning`. | 🟠 MEDIUM |
| **S10-007** | Full compile test (MetaEditor F7) | Target: **0 errors, 0 warnings**. Known risk area: `Context/PatternContext.mqh` deprecated include masih di-reference. | 🔴 CRITICAL |

### Sprint 10 Success Criteria
- [ ] `SignalManager` confirmed: 3 sources registered, weights sum = 1.00, PatternSignalSource connected via `GetHistoryAt()`
- [ ] `RiskManager` confirmed: drawdown circuit halts pipeline execution, not just logs
- [ ] `ExecutionManager` confirmed: async ticket available before Stage_Recovery executes
- [ ] `AIOrchestrator` confirmed: ONNX fallback path tested, online learning guarded
- [ ] MetaEditor F7 compile: 0 errors, 0 warnings on both `PASR_MODULAR.mq5` and `PASR_QA_Run.mq5`

---

## Pipeline Stage Map (v2.02 — All Stages Active)

```
OnTick()  → Push EVENT_PRICE_UPDATE / EVENT_NEW_BAR → DrainQueue()

OnTimer() → CPipelineEngine::ExecutePipeline(ctx)
  Stage 1:  DataSync      → m_data->OnTick()
  Stage 2:  AnalysisSR    → EventBus: EVENT_NEW_BAR → m_sr->OnNewBar() + Drain()
  Stage 3:  AnalysisZone  → EventBus: EVENT_NEW_BAR → m_zone->OnNewBar() + Drain()
  Stage 4:  PatternRec    → EventBus: EVENT_NEW_BAR → m_pattern->OnNewBar() + Drain()
  Stage 5:  RegimeDet     → m_regime_det->Update() + DetectSession()
  Stage 6:  SignalGen     → m_signal->Evaluate() → ctx.signal
              └─ SignalManager: SR*0.40 + Zone*0.35 + Pattern*0.25
              └─ RegimeFilter: block if REGIME_RANGING
              └─ AI override: if ai_score > 0.75 → override direction
  Stage 7:  AIInfer       → m_ai_orch->Predict() → ctx.ai_score
  Stage 8:  RiskCheck     → m_risk->Check() → ctx.risk_result
              └─ Circuit breaker: if drawdown > limit → TRADE_HALTED
  Stage 9:  AdaptParams   → m_adaptive->UpdateParameters()
  Stage 10: Execution     → m_exec->Execute() → ctx.exec_result (ticket set here)
  Stage 11: PosMgmt       → position trailing + BE management
  Stage 12: Recovery      → m_recovery->OnTick() (uses ctx.exec_result.ticket)
  Stage 13: Dashboard     → m_dash->Update()
  Stage 14: Journal       → m_telemetry->Log() + m_journal->Write()

OnTradeTransaction() → m_recovery->OnTradeOpen/Close()
                     → m_risk->OnTradeClosed()
                     → m_session->RecordTrade(profit)
                     → m_ai_orch->OnTradeResult() [online learning, guarded]
```

---

## Signal Confluence Architecture (Final)

```
SignalManager (confluence weighted sum)
  ├─ SRSignalSource       weight=0.40  (S/R level proximity)
  ├─ ZoneSignalSource     weight=0.35  (Supply/Demand zone)
  ├─ PatternSignalSource  weight=0.25  (Candle pattern — reads PatternManager.GetHistoryAt())
  ├─ RegimeSignalSource   weight=0.00  (Filter/multiplier only)
  └─ AISignalSource       weight=0.00  (Override if ai_score > 0.75)

Final score = SR*0.40 + Zone*0.35 + Pattern*0.25
Regime:    blocks signal if regime == RANGING
AI:        if ai_score > 0.75 → override direction
```

---

## QA Folder — Final Inventory

```
Include/PASR/QA/
  Assertions.mqh          v1.00  (original, kept for compat)
  AssertHelpers.mqh       v2.00  ✅ UPGRADED — 20 macros
  Audit.mqh                      (existing)
  LatencySimulator.mqh           (existing)
  MockDataManager.mqh     v1.00  ✅ NEW — tick/bar replay
  MockEventBus.mqh        v1.00  ✅ NEW — push recorder
  PipelineHarness.mqh     v1.00  ✅ NEW — 14-stage runner
  QAStressTest.mqh               (existing)
  README.md                      (existing)
  RiskManagerTest.mqh            (existing)
  SignalManagerTest.mqh          (existing)
  SmokeTest.mqh                  (existing)
  Test.mqh                       (existing)
  TestRunner.mqh                 (existing)

Experts/PASR/Scripts/
  PASR_QA_Run.mq5         v1.00  ✅ NEW — master runner script
```

---

## How to Run QA

```
Step 1: Compile
  MetaEditor → Open Experts/PASR/PASR_MODULAR.mq5 → F7
  MetaEditor → Open Experts/PASR/Scripts/PASR_QA_Run.mq5 → F7
  Target: 0 errors, 0 warnings

Step 2: Run QA Script
  MT5 → Navigator → Scripts → PASR_QA_Run → drag to any chart
  Input: InpRunSmokeTests=true, InpRunPipelineTests=true

Step 3: Check Experts tab for:
  ===== PASR QA Suite v1.00 =====
  [QA] Test_EventBus_PushOrder: PASS
  [QA] Test_MockDataManager_Replay: PASS
  [QA] Test_AssertHelpers_Self: PASS
  [QA] Test_PipelineHarness_Trending: PASS | pass_rate=100.0%
  [QA] Test_PipelineHarness_Ranging: PASS | pass_rate=XX.X%
  ===== QA COMPLETE: 5 PASS / 0 FAIL =====

Step 4: If any FAIL → paste Experts tab output to chat for analysis
```

---

## Deprecated Files — Safe to Delete

```
Include/PASR/Analysis/Pattern/Context/PatternContext.mqh  ← use Core/ version
Include/PASR/Trade/RecoveryEngine.mqh                    ← replaced by RecoveryManager.mqh
```
