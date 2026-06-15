# Central Module (`PASR/Central/`)

6 files — Kernel bootstrap, module registry, service locator, factory, lifecycle.

## Arsitektur

```
Central/
  ├── ModuleNames.mqh         — Canonical module name constants
  ├── ModuleRegistry.mqh       — Named IManager* registry (max 64)
  ├── ServiceLocator.mqh       — Typed accessor facade
  ├── ModuleFactory.mqh        — Static factory for all module types
  ├── LifecycleManager.mqh     — Init/deinit lifecycle manager
  └── PASRKernel.mqh           — Main kernel orchestrator
```

## File Reference

| # | File | Class | Fungsi |
|---|------|-------|--------|
| 1 | `ModuleNames.mqh` | — | `#define` constants: `PASR_MOD_DATA_MANAGER`, `PASR_MOD_SR_MANAGER`, etc. (24 modules) |
| 2 | `ModuleRegistry.mqh` | `CModuleRegistry` | Fixed array (64) of `(name, IManager*, owned)`. Register, replace, unregister, lookup, clear |
| 3 | `ServiceLocator.mqh` | `CServiceLocator` | Typed getters: `Data()`, `SR()`, `Zone()`, `Pattern()`, `Signal()`, `AI()`, `Risk()`, `Execution()`, `Exit()`, `Recovery()`, `Journal()`, `Dashboard()`, `Sanity()`, `Telemetry()`, `Adaptive()`, `Health()`, `Session()` |
| 4 | `ModuleFactory.mqh` | `CModuleFactory` | Static `Create*()` for all PASR managers and signal sources |
| 5 | `LifecycleManager.mqh` | `CLifecycleManager` | `InitOne()`, `InitCritical()`, `InitOptional()`, `InitRegistered()`, `DeinitOne()`, `DeinitRegistered()` |
| 6 | `PASRKernel.mqh` | `CPASRKernel` | **Main entry point**. States: STOPPED → STARTING → READY → FAILED → SHUTTING_DOWN |

## Kernel Lifecycle

### Init Sequence
```
1. InitCoreServices()
   - DataManager (critical)
   - SanityManager (optional)
   - HealthMonitor (optional)
   - SessionState (optional)

2. InitAnalysisAndSignalStack()
   - SRManager, ZoneManager, RegimeFilter
   - PatternManager, SignalManager
   - Signal sources (Pattern, SR, Regime, AI if enabled)

3. InitAIStack() (optional)
   - AIOrchestrator, AISignalSource

4. InitTradingStack()
   - RiskManager, ExecutionManager
   - ExitEngine, RecoveryManager

5. InitObservabilityStack()
   - AuditLog, Telemetry, Journal, Dashboard

6. InitPipeline()
   - Create PipelineEngine, inject all dependencies
```

### Runtime Loop
```
OnTick()
  → SanityManager.ValidateTick()
  → DataManager.OnTick()
  → Health check

OnTimer()
  → Detect new bar
  → Prepare PipelineContext
  → Drain EventBus
  → Process execution retries
  → Run PipelineEngine.ExecutePipeline()
```

### Entry Point (EA)
```cpp
#include <PASR/Core/PASR.mqh>

CPASRKernel kernel;

int OnInit() {
    return kernel.Init(config);
}

void OnTick() {
    kernel.OnTick();
}

void OnTimer() {
    kernel.OnTimer();
}

void OnDeinit(const int reason) {
    kernel.OnDeinit(reason);
}

void OnTradeTransaction(...) {
    kernel.OnTradeTransaction(trans, request, result);
}

void OnChartEvent(...) {
    kernel.OnChartEvent(id, lparam, dparam, sparam);
}
```
