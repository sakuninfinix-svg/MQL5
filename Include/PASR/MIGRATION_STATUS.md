# PASR Architecture Migration Status

> Last updated: 2026-05-23 (Sprint 7) | **ALL 7 SPRINTS COMPLETE**

## Migration: Monolith → Pipeline Orchestration

### Status: ✅ COMPLETE (13 bugs + 6 perf + 5 S5 + 6 S6 + 2 S7 tasks resolved)

---

## Bug Fix Tracker

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
| BUG-013 | 🟠 HIGH | `ZoneManager.mqh` | `OnEvent()` override missing — EventBus dispatch silent fail | ✅ v2.02 |

---

## Sprint 4 — Performance Hardening

| Item | File | Description | Status |
|---|---|---|---|
| PERF-001 | `EventBus.mqh` v3.01 | Binary min-heap O(log n) | ✅ Done |
| PERF-002 | `PipelineTypes.mqh` v1.02 | 50ms stage timeout watchdog | ✅ Done |
| PERF-003 | `PipelineTypes.mqh` v1.02 | `positions_count` cache in ctx | ✅ Done |
| PERF-004 | `RiskManager.mqh` | `RISK_CACHE_TTL_MS` equity cache | ✅ Done |
| PERF-005 | `PipelineEngine.mqh` v2.02 | `stages_timeout` counter | ✅ Done |
| PERF-006 | `EventBus.mqh` v3.01 | `SEventBusStats` telemetry | ✅ Done |

---

## Sprint 5 — Dependency Completion & Dedup

| Item | File | Status |
|---|---|---|
| S5-001 | Dependency audit — all includes present | ✅ |
| S5-002 | `Analysis/Pattern/README.md` scaffold | ✅ |
| S5-003 | `Trade/RecoveryEngine.mqh` deprecated | ✅ |
| S5-004 | `Signal/ZoneSignalSource.mqh` v1.00 | ✅ |
| S5-005 | `Trade/PositionManager.mqh` v2.00 | ✅ |

---

## Sprint 6 — QA Infrastructure

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

## Sprint 7 — Manager Connectivity Audit

| Item | File | Description | Status |
|---|---|---|---|
| S7-001 | `Analysis/ZoneManager.mqh` v2.02 | BUG-013: Add missing `OnEvent()` override | ✅ FIXED |
| S7-002 | `Analysis/SRManager.mqh` v6.0 | Full pipeline audit — PASS | ✅ OK |
| S7-003 | `Analysis/SRDetector.mqh` | Pivot scan logic audit — PASS | ✅ OK |
| S7-004 | `Analysis/SRZoneStore.mqh` | Zone lifecycle audit — PASS | ✅ OK |
| S7-005 | `Core/Orchestrator.mqh` v3.05 | Full bug audit — all BUGs fixed | ✅ OK |
| S7-006 | `Core/PipelineEngine.mqh` v2.02 | All stages reviewed — PASS | ✅ OK |

---

## Sprint 8 — Roadmap (Next Steps)

| Item | Target File | Task |
|---|---|---|
| S8-001 | `Analysis/PatternManager.mqh` | Audit OnEvent() + pattern logic completeness |
| S8-002 | `Signal/SignalManager.mqh` | Verify confluence scoring with ZoneSignalSource |
| S8-003 | `Trade/RiskManager.mqh` | Audit equity cache + max drawdown circuit |
| S8-004 | `Trade/ExecutionManager.mqh` | Audit slippage + async order flow |
| S8-005 | `Signal/AI/AIOrchestrator.mqh` | Audit ONNX inference path + online learning |
| S8-006 | Full compile test | MetaEditor F7 compile — 0 errors, 0 warnings target |

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

## Signal Confluence Architecture (Final)

```
SignalManager (confluence weighted sum)
  ├─ SRSignalSource       weight=0.40  (S/R level proximity)
  ├─ ZoneSignalSource     weight=0.35  (Supply/Demand zone) ← S5-004
  ├─ PatternSignalSource  weight=0.25  (Candle pattern)
  ├─ RegimeSignalSource   weight=0.00  (Filter/multiplier)
  └─ AISignalSource       weight=0.00  (Override >0.75 confidence)

Final score = SR*0.40 + Zone*0.35 + Pattern*0.25
Regime:    blocks signal if regime == RANGING
AI:        if ai_score > 0.75 → override direction
```

---

## Pipeline Stage Map (v2.02 — All Stages Active)

```
OnTick()  → Push EVENT_PRICE_UPDATE / EVENT_NEW_BAR → DrainQueue()

OnTimer() → CPipelineEngine::ExecutePipeline(ctx)
  Stage 1:  DataSync      → m_data->OnTick()
  Stage 2:  AnalysisSR    → EventBus: EVENT_NEW_BAR → m_sr->OnNewBar()
  Stage 3:  AnalysisZone  → EventBus: EVENT_NEW_BAR → m_zone->OnNewBar()  ← BUG-013 FIXED
  Stage 4:  PatternRec    → EventBus: EVENT_NEW_BAR → m_pattern->OnNewBar()
  Stage 5:  RegimeDet     → m_regime_det->Update() + DetectSession()
  Stage 6:  SignalGen     → m_signal->Evaluate() → ctx.signal
  Stage 7:  AIInfer       → m_ai_orch->Predict() → ctx.ai_score
  Stage 8:  RiskCheck     → m_risk->Check() → ctx.risk_result
  Stage 9:  AdaptParams   → m_adaptive->UpdateParameters()
  Stage 10: Execution     → m_exec->Execute() → ctx.exec_result
  Stage 11: PosMgmt       → position trailing + BE management
  Stage 12: Recovery      → m_recovery->OnTick()
  Stage 13: Dashboard     → m_dash->Update()
  Stage 14: Journal       → m_telemetry->Log() + m_journal->Write()

OnTradeTransaction() → m_recovery->OnTradeOpen/Close()
                     → m_risk->OnTradeClosed()
                     → m_session->RecordTrade(profit)
                     → m_ai_orch->OnTradeResult() [online learning]
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

Step 4: If any FAIL → paste Experts tab output to chat
```
