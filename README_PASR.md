# PASR Modular EA — Project Context

> PASR = Price Action Support Resistance
> Repository: `sakuninfinix-svg/MQL5`
> Main compile target: `Experts/PASR_MODULAR.mq5`
> Primary include root: `Include/PASR/`

---

## Purpose

`README_PASR.md` menjelaskan konteks proyek PASR secara ringkas dan realistis. Dokumen ini bukan bug tracker, bukan audit report panjang, dan bukan klaim production-readiness.

Untuk detail panjang, gunakan:

- `Include/PASR/README.md` — ringkasan dokumentasi PASR di dalam folder include.
- `Include/PASR/docs/DOCUMENTATION.md` — indeks dokumen teknis yang masih aktif.
- `Include/PASR/docs/ARCHITECTURE.md` — arsitektur runtime canonical saat ini.
- `Include/PASR/dokumentasi.md` — dokumentasi detail, sprint history, dan issue mapping.
- `Include/PASR/docs/fundamental-business-logic-audit.md` — audit risiko fundamental business logic.
- GitHub Issues — sumber utama bug aktif, backlog, dan rencana refactor.

---

## Current Architecture Direction

PASR saat ini memakai arsitektur **Centralized Modular Pipeline**:

```text
OnTick()
  -> push price/update event
  -> detect new-bar flag ringan

OnTimer()
  -> drain EventBus queue
  -> execute ordered pipeline stages
  -> drain EventBus queue again

OnTradeTransaction()
  -> update trade/recovery/session/AI feedback paths
```

Target desain:

1. `OnTick()` tetap ringan.
2. Analisis berat berjalan pada timer/new-bar pipeline.
3. `CPASRKernel` menjadi coordinator utama lifecycle, registry, runtime event loop, dan pipeline.
4. Manager berkomunikasi lewat `CEventBus` dan kontrak interface yang jelas.
5. State trading tidak tersebar tanpa owner.
6. Bug aktif tidak disimpan di README, tetapi di GitHub Issues.

---

## Runtime Pipeline

Pipeline detail dapat berubah, tetapi arah besarnya adalah:

| Stage | Area | Responsibility |
|------:|------|----------------|
| 01 | DataSync | Sinkronisasi price/indicator/cache data |
| 02 | AnalysisSR | Support/resistance analysis |
| 03 | AnalysisZone | Supply/demand zone update |
| 04 | PatternRec | Candlestick pattern recognition |
| 05 | RegimeDetect | Market regime/session/volatility detection |
| 06 | SignalGen | Confluence and signal generation |
| 07 | AIInference | AI confidence/filtering path |
| 08 | RiskCheck | Risk, spread, drawdown, correlation checks |
| 09 | AdaptiveParams | Adaptive parameter policy |
| 10 | Execution | Order planning/execution |
| 11 | PosMgmt | Break-even, trailing, position scan, exit checks |
| 12 | Recovery | Fakeout/recovery logic |
| 13 | Dashboard | UI/HUD updates |
| 14 | Journal | Journal, telemetry, reports |

---

## Repository Layout

```text
MQL5/
├── Experts/
│   ├── PASR_MODULAR.mq5       # Main modular EA target
│   └── PASR.mq5               # Legacy monolith, do not extend
│
└── Include/PASR/
    ├── Core/                  # EventBus, Events, IManager, master include, utilities
    ├── Central/               # CPASRKernel, registry, service locator, lifecycle, factory
    ├── Orchestration/         # Canonical pipeline engine and split stages
    ├── Analysis/              # SR, Zone, MarketRegime, AdaptiveParameter, Pattern
    ├── Signal/                # SignalManager, signal filters/sources
    ├── Trade/                 # Execution, Risk, Recovery, Exit, Position, Correlation
    ├── AI/                    # AI orchestration, features, inference, trainer, model registry
    ├── Infra/                 # Data, state, telemetry, journal, sanity, health, adaptive config
    ├── Data/                  # Data-related modules, pending audit
    ├── QA/                    # Test and QA utilities, pending audit
    ├── Tools/                 # Utility scripts/tools, pending audit
    ├── UI/                    # Dashboard/UI modules, pending audit
    ├── docs/                  # Long-form technical notes
    ├── README.md              # PASR include-level README
    └── dokumentasi.md         # Detailed PASR documentation
```

---

## Build Flags

Current documented flags:

```cpp
#define PASR_QA_BUILD    // Enable QA/stress modules when supported
#define PASR_DEBUG       // Verbose/debug logging when supported
```

Old flags that should not be used as current contract:

```cpp
QA_BUILD
OOP_ARCHITECTURE
PERF_METRICS
```

Remaining cleanup for legacy `PERF_METRICS` is tracked in Issue #181.

---

## Current Open Work

The active tracker is GitHub Issues. Important groups:

### Compile and architecture blockers

| Issue | Scope |
|------:|-------|
| #180 | Restore `Core/PASR.mqh` as real master include |
| #181 | Remove legacy `PERF_METRICS` from `PASR_MODULAR.mq5` |
| #182 | Fix `DataManager` / `IDataManager` contract |
| #183 | Harden `AdaptiveConfig` dependencies and validation |
| #196 | Full compile and QA status check |

### Fundamental business logic risks

| Issue | Scope |
|------:|-------|
| #187 | Single source of truth for position/runtime state |
| #188 | Centralized parameter registry and validation |
| #189 | Signal conflict resolver and veto logic |
| #190 | Single account snapshot for risk calculation |
| #191 | AI feature validation and fail-safe inference |
| #192 | Exit confirmation queue and unified exit policy |

### Audit and refactor follow-ups

| Issue | Scope |
|------:|-------|
| #193–#195 | Sprint 10 signal/risk/execution/AI audits |
| #197–#202 | Optimization follow-ups from v1.20 summary |
| #203–#214 | Architecture/audit report follow-ups |

---

## Production Readiness Note

PASR should be treated as **active development / research-grade** until compile blockers, state ownership, risk consistency, AI validation, and exit confirmation are confirmed stable.

Do not interpret older claims such as “institutional-grade,” “80–100 pairs,” “<0.3ms/tick,” or “99.5% execution reliability” as verified current guarantees unless supported by reproducible benchmark and forward-test evidence.

---

## Development Policy

- README files should stay short and useful.
- Long explanations belong in `dokumentasi.md` or `Include/PASR/docs/`.
- Active work belongs in GitHub Issues.
- Historical audit files should be migrated to Issues/docs, then removed when obsolete.
- Do not close an issue until the fix is present in code or explicitly marked obsolete.
- Prefer small, reviewable fixes over broad rewrites.

---

## Quick Start for Development

1. Open `Experts/PASR_MODULAR.mq5` in MetaEditor.
2. Compile with `#property strict` enabled.
3. Use `CPASRKernel` as the canonical runtime entry.
4. Run/verify QA compile gates once compile is stable.
5. Use `CPASRKernel` only; do not reintroduce legacy runtime compatibility callers.

Minimal intended EA lifecycle:

```cpp
#include <PASR/Core/PASR.mqh>

CPASRKernel kernel;

int OnInit()
  {
   // Build/load StrategyConfig here.
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

## Recommended Work Order

1. Keep `Experts/PASR_MODULAR.mq5`, `PASR_Smoke`, and `PASR_PipelineHarness_Smoke` compile-clean.
2. Confirm master include and interface contracts.
3. Validate risk/account/position state ownership.
4. Validate AI feature inputs and fallback behavior.
5. Validate exit confirmation and order lifecycle.
6. Audit pending modules: `Data`, `QA`, `UI`, `Tools`.
7. Add benchmarks only after compile and runtime path are stable.
8. Consider multi-symbol expansion last.

---

## Related Documentation

- `Include/PASR/README.md`
- `Include/PASR/dokumentasi.md`
- `Include/PASR/docs/fundamental-business-logic-audit.md`
- GitHub Issues #98, #180–#214

---

© 2026 Agsicentre — PASR EA. All rights reserved.
