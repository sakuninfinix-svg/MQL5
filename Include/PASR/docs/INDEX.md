# PASR Framework — Panduan Pengembangan Expert Advisor

**Version:** 6.x  
**Total Files:** 188 MQH  
**Total Size:** ~2 MB  
**Folder:** `MQL5/Include/PASR/`

---

## Arsitektur (Layered Architecture)

```
┌─────────────────────────────────────────────────────────────┐
│                      CENTRAL (Kernel)                        │
│  PASRKernel · ModuleRegistry · ServiceLocator · Lifecycle    │
│  ModuleFactory · ModuleNames                                  │
├─────────────────────────────────────────────────────────────┤
│                     ORCHESTRATION (Pipeline)                  │
│  PipelineEngine · 14 Pipeline Stages                          │
├──────────┬──────────┬──────────┬──────────┬─────────────────┤
│   Core    │  Signal   │   Trade   │    AI     │   Analysis    │
│  EventBus │  Manager  │ Execution │Orchestrator│ SR/Zone/Pat.  │
│  Config   │ Sources   │  Risk     │ MLP/LSTM  │  Regime/HMM   │
│  IManager │ Filters   │  Exit     │ Ensemble  │  Adaptive     │
├──────────┴──────────┴──────────┴──────────┴─────────────────┤
│                    INFRA · DATA · UI                          │
│  DataManager · Journal · Telemetry · Dashboard · Session     │
├─────────────────────────────────────────────────────────────┤
│                        QA (Testing)                           │
│  Assertions · SmokeTests · PipelineHarness · MonteCarlo      │
│  WalkForward · MockObjects · OptimizationSets                 │
└─────────────────────────────────────────────────────────────┘
```

---

## Modul

| Modul | File | Deskripsi |
|-------|------|-----------|
| [AI](AI.md) | 18 | Machine Learning (MLP, LSTM, Ensemble, ONNX, Attention Fusion, Feature Engineering) |
| [Analysis](Analysis.md) | 12 | Support/Resistance, Market Regime, Pattern Recognition, HMM, Adaptive Parameters |
| [Central](Central.md) | 6 | Kernel bootstrap, Module Registry, Service Locator, Factory Pattern, Lifecycle |
| [Core](Core.md) | 15 | EventBus, Config Manager, IManager Base, Pipeline Types, Globals, Latency Optimizer |
| [Data](Data.md) | 3 | SR Structs, Regime Types, Symbol Scanner |
| [Infra](Infra.md) | 13 | DataManager, Journal, Telemetry, Session, State, Health Monitor, Audit Log |
| [Observability](Observability.md) | 1 | Observability constants and metric definitions |
| [Orchestration](Orchestration.md) | 19 | Pipeline Engine, 14 Pipeline Stages, Stage Registry |
| [QA](QA.md) | 17 | Assertions, Smoke Tests, Unit Tests, Monte Carlo, Walk-Forward, Mocks |
| [Signal](Signal.md) | 17 | Signal Sources, Aggregator, Filter Pipeline, Decision Engine, Config, Cooldown |
| [Trade](Trade.md) | 13 | Risk Manager, Execution, Exit Engine, Position Manager, Recovery, Trade Plan |
| [UI](UI.md) | 1 | Dashboard Manager with observability overlay |
| **Total** | **134** (documented) + 54 (utility) = **188** |

---

## Cara Menggunakan

### Quick Start
```cpp
#include <PASR/Core/PASR.mqh>   // Master include — tarik semua modul

// Di OnInit():
CPASRKernel kernel;
int result = kernel.Init(config);

// Di OnTick():
kernel.OnTick();

// Di OnTimer():
kernel.OnTimer();

// Di OnDeinit():
kernel.OnDeinit(reason);
```

### Flow Pipeline
```
Tick → Sanity Check → DataSync → AnalysisSR → AnalysisZone → Pattern → Regime
  → SignalGen → AIInfer → RiskCheck → AdaptiveParams → Execution
  → PositionMgmt → Recovery → Dashboard → Journal
```

---

## Dependency Order (Include Layer)

```
Layer 0:   Config/Types → Config/Validator → Config/Manager
Layer 0b:  Globals → Events → EventBus → IManager
Layer 1:   PipelineTypes → RegimeTypes → SRStruct
Layer 2:   Infra (DataManager, Journal, Telemetry, etc.)
Layer 3:   Analysis (SR, Zone, Pattern, Regime, Adaptive)
Layer 4:   AI (Features, MLP, LSTM, Ensemble, ONNX, Orchestrator)
Layer 5:   Signal (Sources, Aggregator, Filters, Decision Engine)
Layer 6:   Trade (Risk, Execution, Exit, Recovery, Position)
Layer 7:   UI (Dashboard)
Layer 8:   QA (Tests, Mocks, Harness)
Layer 9:   Orchestration (Pipeline Engine, Stages)
Layer 10:  Central (Kernel, Registry, ServiceLocator)
```
