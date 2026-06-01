# PASR Central Dependency Map

This document records the current dependency ownership during the Centralized Modular Pipeline migration.
`CBackendAdapter` is the canonical backend in `Central/BackendAdapter.mqh`; `COrchestrator` remains only as a compatibility wrapper in `Core/Orchestrator.mqh`.

## Ownership Model

| Component | Current owner | Registry state | Lifecycle path |
| --- | --- | --- | --- |
| `EventBus` | `CBackendAdapter` compatibility backend | Not registered; non-`IManager` runtime service | Allocated by `CModuleFactory` |
| `DataManager` | `CPASRKernel` registry | Owned by `CPASRKernel` registry | Initialized by backend via `CLifecycleManager::InitCritical`; deleted by registry |
| `SRManager` | `CPASRKernel` registry | Owned by `CPASRKernel` registry | Initialized by backend via `CLifecycleManager::InitCritical`; deleted by registry |
| `ZoneManager` | `CPASRKernel` registry | Owned by `CPASRKernel` registry | Initialized by backend via `CLifecycleManager::InitCritical`; deleted by registry |
| `PatternManager` | `CPASRKernel` registry | Owned by `CPASRKernel` registry | Initialized by backend via `CLifecycleManager::InitCritical`; deleted by registry |
| `SignalManager` | `CPASRKernel` registry | Owned by `CPASRKernel` registry | Initialized by backend via `CLifecycleManager::InitCritical`; deleted by registry |
| `RegimeFilter` | `CPASRKernel` registry when allocated | Owned by `CPASRKernel` registry | Initialized by backend via `CLifecycleManager::InitOptional`; deleted by registry |
| `AIOrchestrator` | `CPASRKernel` registry when allocated | Owned by `CPASRKernel` registry | Initialized by backend via `CLifecycleManager::InitOptional`; deleted by registry |
| `RiskManager` | `CPASRKernel` registry | Owned by `CPASRKernel` registry | Initialized by backend via `CLifecycleManager::InitCritical`; deleted by registry |
| `ExecutionManager` | `CPASRKernel` registry | Owned by `CPASRKernel` registry | Initialized by backend via `CLifecycleManager::InitCritical`; deleted by registry |
| `ExitEngine` | `CPASRKernel` registry | Owned by `CPASRKernel` registry | Initialized by backend via `CLifecycleManager::InitCritical`; deleted by registry |
| `JournalManager` | `CPASRKernel` registry when allocated | Owned by `CPASRKernel` registry | Initialized by backend via `CLifecycleManager::InitOptional`; deleted by registry |
| `DashboardManager` | `CPASRKernel` registry when allocated | Owned by `CPASRKernel` registry | Initialized by backend via `CLifecycleManager::InitOptional`; deleted by registry |
| `PipelineEngine` | `CPASRKernel` | Owned directly by kernel; non-`IManager` runtime engine | Allocated by `CModuleFactory`, deleted by `CPASRKernel::Shutdown` |

## Next Ownership Target

`CPASRKernel` now owns pipeline execution and `IManager` lifetime through `CModuleRegistry`.
The remaining ownership target is non-`IManager` runtime services and final removal of backend allocation code.
