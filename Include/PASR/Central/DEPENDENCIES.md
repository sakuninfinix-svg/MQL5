# PASR Central Dependency Map

This document records the current dependency ownership after the Centralized Modular Pipeline migration.
`CPASRKernel` is the canonical runtime owner. Legacy runtime compatibility files have been removed by breaking cleanup.

## Ownership Model

| Component | Current owner | Registry state | Lifecycle path |
| --- | --- | --- | --- |
| `EventBus` | `CPASRKernel` | Not registered; non-`IManager` runtime service | Allocated by `CModuleFactory`, injected into lifecycle/pipeline, deleted by kernel |
| `DataManager` | `CPASRKernel` registry | Owned by `CPASRKernel` registry | Initialized by kernel via `CLifecycleManager::InitCritical`; deleted by registry |
| `SRManager` | `CPASRKernel` registry | Owned by `CPASRKernel` registry | Initialized by kernel via `CLifecycleManager::InitCritical`; deleted by registry |
| `ZoneManager` | `CPASRKernel` registry | Owned by `CPASRKernel` registry | Initialized by kernel via `CLifecycleManager::InitCritical`; deleted by registry |
| `PatternManager` | `CPASRKernel` registry | Owned by `CPASRKernel` registry | Initialized by kernel via `CLifecycleManager::InitCritical`; deleted by registry |
| `SignalManager` | `CPASRKernel` registry | Owned by `CPASRKernel` registry | Initialized by kernel via `CLifecycleManager::InitCritical`; deleted by registry |
| `RegimeFilter` | `CPASRKernel` registry when allocated | Owned by `CPASRKernel` registry | Initialized by kernel via `CLifecycleManager::InitOptional`; deleted by registry |
| `MarketRegimeDetector` | `CPASRKernel` | Not registered; non-`IManager` fallback service | Allocated by `CModuleFactory`, injected through `SPipelineDependencies`, deleted by kernel |
| `AdaptiveParameterManager` | `CPASRKernel` registry when allocated | Owned by `CPASRKernel` registry | Initialized by kernel after core services; bound to kernel-owned `MarketRegimeDetector`; deleted by registry |
| `AIOrchestrator` | `CPASRKernel` registry when allocated | Owned by `CPASRKernel` registry | Initialized by kernel via `CLifecycleManager::InitOptional`; deleted by registry |
| `RiskManager` | `CPASRKernel` registry | Owned by `CPASRKernel` registry | Initialized by kernel via `CLifecycleManager::InitCritical`; deleted by registry |
| `ExecutionManager` | `CPASRKernel` registry | Owned by `CPASRKernel` registry | Initialized by kernel via `CLifecycleManager::InitCritical`; deleted by registry |
| `ExitEngine` | `CPASRKernel` registry | Owned by `CPASRKernel` registry | Initialized by kernel via `CLifecycleManager::InitCritical`; deleted by registry |
| `RecoveryManager` | `CPASRKernel` registry when allocated | Owned by `CPASRKernel` registry | Initialized by kernel via `CLifecycleManager::InitOptional`; deleted by registry |
| `JournalManager` | `CPASRKernel` registry when allocated | Owned by `CPASRKernel` registry | Initialized by kernel via `CLifecycleManager::InitOptional`; deleted by registry |
| `DashboardManager` | `CPASRKernel` registry when allocated | Owned by `CPASRKernel` registry | Initialized by kernel via `CLifecycleManager::InitOptional`; deleted by registry |
| `SanityManager` | `CPASRKernel` registry when allocated | Owned by `CPASRKernel` registry | Initialized by kernel via `CLifecycleManager::InitOptional`; deleted by registry |
| `HealthMonitor` | `CPASRKernel` registry when allocated | Owned by `CPASRKernel` registry | Initialized by kernel via `CLifecycleManager::InitOptional`; deleted by registry |
| `SessionState` | `CPASRKernel` registry when allocated | Owned by `CPASRKernel` registry | Magic configured before kernel lifecycle init; deleted by registry |
| `TelemetryRecorder` | `CPASRKernel` registry when allocated | Owned by `CPASRKernel` registry | Initialized by kernel via `CLifecycleManager::InitOptional`; deleted by registry |
| `PipelineEngine` | `CPASRKernel` | Owned directly by kernel; non-`IManager` runtime engine | Allocated by `CModuleFactory`, deleted by `CPASRKernel::Shutdown` |

## Next Ownership Target

`CPASRKernel` now owns manager bootstrap, pipeline execution, runtime tick/event loop preparation, trade transaction routing, and `IManager` lifetime through `CModuleRegistry`.
`CPASRKernel::InitPipeline()` now resolves registry-owned managers through `CServiceLocator` and passes them to the pipeline as `SPipelineDependencies`.
`SPipelineDependencies` is limited to runtime stage and observability dependencies; health/session values are prepared in `PipelineContext` before pipeline execution.
Breaking cleanup removed runtime compatibility files; new callers must use `CPASRKernel`.
