# PASR — Price Action Support Resistance EA

> Architecture: Pipeline Orchestration
> Last updated: Sprint 21 issue migration, 2026-05-24
> Compile target: `Experts/PASR_MODULAR.mq5`

---

## Purpose

README ini berfungsi sebagai dokumentasi arsitektur, peta folder, panduan build, dan ringkasan status. Bug tracker detail tidak lagi disimpan penuh di README; semua bug open dipindahkan ke GitHub Issues agar bisa diberi label, assignee, diskusi, dan status close.

---

## Architecture Overview

PASR menggunakan Pipeline Orchestration. `OnTick()` hanya mendorong event harga dan flag new-bar, sedangkan logic utama dieksekusi berurutan dari `OnTimer()` melalui `CPipelineEngine::ExecutePipeline()`.

```text
OnTick()  -> Push EVENT_PRICE_UPDATE
           -> set m_new_bar_flag jika bar baru
OnTimer() -> DrainQueue()
          -> ExecutePipeline(PipelineContext)
              01 DataSync
              02 AnalysisSR
              03 AnalysisZone
              04 PatternRec
              05 RegimeDetect
              06 SignalGen
              07 AIInference
              08 RiskCheck
              09 AdaptiveParams
              10 Execution
              11 PosMgmt
              12 Recovery
              13 Dashboard
              14 Journal
          -> DrainQueue()
OnTradeTransaction() -> RecoveryManager + SessionState + AIOrchestrator backprop
```

---

## Folder Map

```text
Include/PASR/
├── Core/        Infrastructure: EventBus, IManager, PipelineEngine, Orchestrator
├── Analysis/    SR, Zone, Regime, AdaptiveParameter, Pattern modules
├── Signal/      SignalManager and SignalFilterPipeline
├── Trade/       Execution, Risk, Recovery, Exit, Position, Correlation
├── AI/          AIOrchestrator, FeatureBuilder, Inference, Ensemble, Trainer
├── Infra/       Health, SessionState, Snapshot, Journal, Telemetry, State, DataManager
├── Data/        Pending audit, see Issue #186
├── QA/          Pending audit, see Issue #186
├── Tools/       Pending audit, see Issue #186
├── UI/          Pending audit, see Issue #186
└── docs/        Internal documentation

Experts/
├── PASR_MODULAR.mq5   Main EA entry point
└── PASR.mq5           Legacy monolith, deprecated
```

---

## Compilation Flags

```cpp
#define PASR_QA_BUILD    // Enable QA modules
#define PASR_DEBUG       // Verbose logging per manager
```

Old flags removed: `QA_BUILD`, `OOP_ARCHITECTURE`, `PERF_METRICS`.
Remaining `PERF_METRICS` cleanup is tracked in Issue #181.

---

## Open Work Moved to GitHub Issues

| README ID | GitHub Issue | Scope |
|-----------|--------------|-------|
| S21-001 | #180 | Restore `Core/PASR.mqh` master include |
| S21-002 | #181 | Remove legacy `PERF_METRICS` from `PASR_MODULAR.mq5` |
| S21-003, S21-004, S21-005, INF-7 | #182 | Fix `DataManager` / `IDataManager` contract and initialization |
| S21-006, S21-007, S21-008, S21-009, INF-10 | #183 | Harden `AdaptiveConfig` dependencies and validation |
| A1 | #184 | Decompose `Analysis/SRManager.mqh` monolith |
| A5 | #185 | Audit `Analysis/Pattern` module for `IManager` compliance |
| DATA-?, QA-?, UI-?, TOOLS-? | #186 | Audit pending PASR folders |

S21-010 adalah dokumentasi issue yang diselesaikan oleh migrasi ini: README tidak lagi menjadi bug tracker utama.

---

## Immediate Fix Order

1. #180 — Restore `Core/PASR.mqh` as real master include.
2. #181 — Remove or replace legacy `PERF_METRICS` usage.
3. #182 — Define canonical `IDataManager` contract and fix `DataManager`.
4. #183 — Define/import canonical `ENUM_TRAIL_MODE` and harden `AdaptiveConfig`.
5. #184 — Decompose `SRManager.mqh` after compile blockers are handled.
6. #185 and #186 — Continue module audits and split concrete bugs into separate issues.

---

## Quick Start

```cpp
#include <PASR/Core/PASR.mqh>

COrchestrator orch;

int OnInit()
  {
   if(orch.Init(cfg) != INIT_SUCCEEDED)
      return INIT_FAILED;
   EventSetTimer(1);
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   orch.OnTick();
  }

void OnTimer()
  {
   orch.OnTimer();
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   orch.OnTradeTransaction(trans, request, result);
  }

void OnDeinit(const int reason)
  {
   orch.OnDeinit(reason);
  }
```

---

## Version Index

| File | Version | Status |
|------|---------|--------|
| `Core/PASR.mqh` | unknown | See #180 |
| `Core/Orchestrator.mqh` | v3.06 | Stable |
| `Core/PipelineEngine.mqh` | v1.01 | Stable |
| `Signal/SignalManager.mqh` | v4.02 | Stable |
| `Trade/ExecutionManager.mqh` | v3.02 | Stable |
| `Trade/RiskManager.mqh` | v2.02 | Stable |
| `Trade/RecoveryManager.mqh` | v2.18 | Stable |
| `Trade/ExitEngine.mqh` | v2.01 | Stable |
| `Trade/PositionManager.mqh` | v3.00 | Stable |
| `Trade/CorrelationManager.mqh` | v2.00 | Stable |
| `AI/AIOrchestrator.mqh` | v2.02 | Stable |
| `Infra/DataManager.mqh` | v2.00 | See #182 |
| `Infra/AdaptiveConfig.mqh` | v2.00 | See #183 |
| `Analysis/SRManager.mqh` | unknown | See #184 |
| `Analysis/Pattern/*.mqh` | unknown | See #185 |
| `Data/*.mqh` | unknown | See #186 |
| `QA/*.mqh` | unknown | See #186 |
| `UI/*.mqh` | unknown | See #186 |
| `Tools/*.mqh` | unknown | See #186 |
| `Experts/PASR_MODULAR.mq5` | v13.01 | See #181 |
