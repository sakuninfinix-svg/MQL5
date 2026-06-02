# PASR Architecture

PASR is an MQL5 Expert Advisor framework built around a centralized runtime kernel and a modular trading pipeline.

Current canonical entrypoint:

```mql5
#include <PASR/Core/PASR.mqh>

CPASRKernel kernel;
```

`CPASRKernel` owns lifecycle, service lookup, manager registry, runtime event flow, trade transaction routing, and pipeline execution. Legacy runtime compatibility adapters have been removed; new callers must use the kernel directly.

## Runtime Flow

```text
Experts/PASR_MODULAR.mq5
        |
        v
CPASRKernel
        |
        +-- CModuleRegistry
        +-- CServiceLocator
        +-- CLifecycleManager
        +-- CPipelineEngine
                |
                v
        Orchestration/Stages/*
```

EA event handlers are intentionally thin:

```text
OnInit()             -> kernel.Init(config)
OnTick()             -> kernel.OnTick()
OnTimer()            -> kernel.OnTimer()
OnTradeTransaction() -> kernel.OnTradeTransaction(...)
OnDeinit()           -> kernel.OnDeinit(reason)
```

Heavy analysis and trading decisions run from the timer-driven pipeline, not directly from `OnTick()`.

## Include Layers

The master include is `Include/PASR/Core/PASR.mqh`. It controls include order and should be the only include needed by EA callers.

Current include order:

| Layer | Scope |
| --- | --- |
| 0 | Config and core primitives |
| 0b | Cross-layer data-only types |
| 1 | Core utilities |
| 2 | Infra managers and data providers |
| 3 | Analysis modules |
| 4 | Trade primitive types |
| 5 | AI modules |
| 6 | Signal modules |
| 7 | Trade managers |
| 8 | UI and QA helpers |
| 9 | Orchestration interfaces, stages, and pipeline engine |
| 10 | Central kernel, registry, service locator, lifecycle, factory |

## Pipeline Stages

`CPipelineEngine` is canonical in `Include/PASR/Orchestration/PipelineEngine.mqh`.

Runtime stage delegates live in `Include/PASR/Orchestration/Stages/`:

```text
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
11 PositionMgmt
12 Recovery
13 Dashboard
14 Journal
```

Pipeline dependencies cross the orchestration boundary through `SPipelineDependencies`. Runtime context values such as health/session metrics are prepared by the kernel before execution.

## Ownership Rules

- `CPASRKernel` owns non-`IManager` runtime services such as `EventBus`, fallback market regime detector, signal sources, and the pipeline engine.
- `CModuleRegistry` owns registered `IManager` instances when they are successfully initialized with `owned=true`.
- `CLifecycleManager` controls init/deinit order and reverse shutdown.
- `CServiceLocator` is the typed lookup boundary for managers used by the kernel and pipeline.
- Domain logic stays in domain folders: `Analysis/`, `Signal/`, `AI/`, `Trade/`, `Infra/`, `Data/`, `UI/`, and `QA/`.

## Dependency Policy

- Do not reintroduce legacy runtime adapters.
- Do not make domain modules pull dependencies through ad hoc globals.
- Prefer registry/service-locator lookup in central runtime code.
- Keep `OnTick()` light; expensive work belongs in timer/new-bar pipeline stages.
- Keep trading formulas and AI/risk behavior separate from architecture cleanup unless the change explicitly targets business logic.

## Verification Gates

After changing architecture or include ownership, compile:

```text
Experts/PASR_MODULAR.mq5
Scripts/PASR_Smoke.mq5
Scripts/PASR_PipelineHarness_Smoke.mq5
```

The expected migration baseline is `0 errors, 0 warnings` for all three.
