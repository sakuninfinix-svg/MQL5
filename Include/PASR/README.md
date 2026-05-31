# PASR — Price Action Support Resistance EA

> Architecture: Centralized Modular Pipeline Architecture
> Last updated: Central layer migration, 2026-05-31
> Compile target: `Experts/PASR_MODULAR.mq5`

---

## Purpose

README ini berfungsi sebagai dokumentasi arsitektur, peta folder, panduan build, dan ringkasan status. Bug tracker detail tidak lagi disimpan penuh di README; semua bug open dipindahkan ke GitHub Issues agar bisa diberi label, assignee, diskusi, dan status close.

---

## Architecture Overview

PASR sekarang bergerak menuju **Centralized Modular Pipeline Architecture**.

Entry point EA memakai `CPASRKernel` sebagai pusat lifecycle dan service facade. Untuk fase kompatibilitas, `CPASRKernel` masih mendelegasikan runtime ke `COrchestrator` lama, sehingga behavior pipeline tetap sama sambil tanggung jawab dipindahkan bertahap ke `Central/` dan `Orchestration/`.

```text
Experts/PASR_MODULAR.mq5
        ↓
CPASRKernel
        ↓
CModuleRegistry + CServiceLocator + CLifecycleManager
        ↓
COrchestrator compatibility backend
        ↓
CPipelineEngine::ExecutePipeline(PipelineContext)
        ↓
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
```

Runtime event flow tetap:

```text
OnTick()             -> g_kernel.OnTick()
OnTimer()            -> g_kernel.OnTimer() -> pipeline execution
OnTradeTransaction() -> g_kernel.OnTradeTransaction()
OnDeinit()           -> g_kernel.OnDeinit()
```

---

## Folder Map

```text
Include/PASR/
├── Core/           Core primitives, EventBus, IManager, legacy backend adapters
├── Central/        Kernel facade, module registry, service locator, lifecycle manager
├── Orchestration/  Pipeline/stage interfaces and future split-stage implementation
├── Analysis/       SR, Zone, Regime, AdaptiveParameter, Pattern modules
├── Signal/         SignalManager and SignalFilterPipeline
├── Trade/          Execution, Risk, Recovery, Exit, Position, Correlation
├── AI/             AIOrchestrator, FeatureBuilder, Inference, Ensemble, Trainer
├── Infra/          Health, SessionState, Snapshot, Journal, Telemetry, State, DataManager
├── Data/           Pending audit, see Issue #186
├── QA/             Pending audit, see Issue #186
├── Tools/          Pending audit, see Issue #186
├── UI/             Pending audit, see Issue #186
└── docs/           Internal documentation

Experts/
├── PASR_MODULAR.mq5   Main EA entry point using CPASRKernel
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

## Central Migration Status

| Phase | Status | Scope |
|------|--------|-------|
| Fase 1 | Done | Add `Central/`, `CPASRKernel`, `CModuleRegistry`, `CServiceLocator`, `CLifecycleManager` |
| Fase 2 | Done | `Experts/PASR_MODULAR.mq5` now uses `CPASRKernel g_kernel` |
| Fase 3 | In progress | Extract allocation/lifecycle/dependency ownership from `Core/Orchestrator*.mqh` |
| Fase 4 | In progress | Add `Orchestration/` and `IPipelineStage` target interface |
| Fase 5 | Pending | Move `CPipelineEngine` implementation out of `Core/` after compile stability |

---

## Open Work Moved to GitHub Issues

| README ID | GitHub Issue | Scope |
|-----------|--------------|-------|
| S21-001 | #180 | Restore `Core/PASR.mqh` as real master include |
| S21-002 | #181 | Remove legacy `PERF_METRICS` from `PASR_MODULAR.mq5` |
| S21-003, S21-004, S21-005, INF-7 | #182 | Fix `DataManager` / `IDataManager` contract and initialization |
| S21-006, S21-007, S21-008, S21-009, INF-10 | #183 | Harden `AdaptiveConfig` dependencies and validation |
| A1 | #184 | Decompose `Analysis/SRManager.mqh` monolith |
| A5 | #185 | Audit `Analysis/Pattern` module for `IManager` compliance |
| DATA-?, QA-?, UI-?, TOOLS-? | #186 | Audit pending PASR folders |

S21-010 adalah dokumentasi issue yang diselesaikan oleh migrasi ini: README tidak lagi menjadi bug tracker utama.

---

## Immediate Fix Order

1. Compile-test `Experts/PASR_MODULAR.mq5` after `CPASRKernel` adoption.
2. Fix any include/type errors introduced by `Central/` and `Orchestration/` headers.
3. Extract manager allocation from `Core/OrchestratorInit.mqh` into a central factory/registry.
4. Extract lifecycle init/deinit ordering into `CLifecycleManager`.
5. Move `CPipelineEngine` implementation to `Orchestration/` only after compile stability.
6. Decompose `Analysis/SRManager.mqh` and audit `Analysis/Pattern` after core compile is stable.

---

## Quick Start

```cpp
#include <PASR/Core/PASR.mqh>

CPASRKernel kernel;

int OnInit()
  {
   StrategyConfig cfg;
   if(kernel.Init(cfg) != INIT_SUCCEEDED)
      return INIT_FAILED;
   EventSetTimer(1);
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   kernel.OnTick();
  }

void OnTimer()
  {
   kernel.OnTimer();
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   kernel.OnTradeTransaction(trans, request, result);
  }

void OnDeinit(const int reason)
  {
   kernel.OnDeinit(reason);
  }
```

---

## Version Index

| File | Version | Status |
|------|---------|--------|
| `Core/PASR.mqh` | central include order | Active |
| `Central/PASRKernel.mqh` | v0.12 | Compatibility facade |
| `Central/ModuleRegistry.mqh` | v0.10 | Active |
| `Central/ServiceLocator.mqh` | v0.11 | Active |
| `Central/LifecycleManager.mqh` | v0.10 | Skeleton |
| `Central/ModuleNames.mqh` | v0.10 | Active |
| `Orchestration/PipelineStage.mqh` | v0.10 | Skeleton |
| `Core/Orchestrator.mqh` | v3.11 | Compatibility backend |
| `Core/PipelineEngine.mqh` | v2.03 | Compatibility backend |
| `Signal/SignalManager.mqh` | v4.02 | Stable |
| `Trade/ExecutionManager.mqh` | v3.02 | Stable |
| `Trade/RiskManager.mqh` | v2.02 | Stable |
| `Trade/RecoveryManager.mqh` | v2.18 | Stable |
| `Trade/ExitEngine.mqh` | v2.01 | Stable |
| `Trade/PositionManager.mqh` | v3.00 | Stable |
| `Trade/CorrelationManager.mqh` | v2.00 | Stable |
| `AI/AIOrchestrator.mqh` | v3.10 | Stable |
| `Infra/DataManager.mqh` | v2.00 | See #182 |
| `Infra/AdaptiveConfig.mqh` | v2.00 | See #183 |
| `Analysis/SRManager.mqh` | unknown | See #184 |
| `Analysis/Pattern/*.mqh` | unknown | See #185 |
| `Data/*.mqh` | unknown | See #186 |
| `QA/*.mqh` | unknown | See #186 |
| `UI/*.mqh` | unknown | See #186 |
| `Tools/*.mqh` | unknown | See #186 |
| `Experts/PASR_MODULAR.mq5` | v13.03 | Centralized Modular Pipeline entry |
