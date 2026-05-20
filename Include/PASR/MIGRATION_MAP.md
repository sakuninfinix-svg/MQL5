# PASR Migration Map

Single source of truth for the legacy → modular file migration.

## Status Legend
- ✅ DONE — Forwarding shim exists, canonical file in place
- ⚠️ SHIM — Canonical forwards to legacy (legacy still holds real code)
- 🔴 TODO — Not yet migrated
- 🗑️ DEPRECATED — Safe to delete after v3.0 cutover

---

## Layer 0 — Core

| Legacy File | Canonical File | Status | Notes |
|---|---|---|---|
| `IManager.mqh` (root) | `Core/IManager.mqh` | ⚠️ SHIM | Core/IManager → root/IManager |
| `Globals.mqh` (root) | `Core/Globals.mqh` | ⚠️ SHIM | Core/Globals → root/Globals |
| `0.EventBus.mqh` | `Core/EventBus.mqh` | ⚠️ SHIM | Core/EventBus → 0.EventBus |
| `1.Events.mqh` | `Core/Events.mqh` | ⚠️ SHIM | Core/Events → 1.Events |
| `2.Config.Types.mqh` | `Core/ConfigTypes.mqh` | ⚠️ SHIM | Core/ConfigTypes → 2.Config.Types |

## Layer 2 — Infra

| Legacy File | Canonical File | Status | Notes |
|---|---|---|---|
| `2.Config.Manager.mqh` | `Infra/ConfigManager.mqh` | ⚠️ SHIM | Infra/ConfigManager → 2.Config.Manager |
| `10.DataManager.mqh` | `Infra/DataManager.mqh` | ⚠️ SHIM | Infra/DataManager → 10.DataManager |

## Layer 3 — Analysis

| Legacy File | Canonical File | Status | Notes |
|---|---|---|---|
| `3.MarketManager.mqh` | `Analysis/MarketManager.mqh` | ⚠️ SHIM | Forwards to legacy |
| `3.ZoneManager.mqh` | `Analysis/ZoneManager.mqh` | ⚠️ SHIM | Forwards to legacy |
| `4.SRManager.mqh` | `Analysis/SRManager.mqh` | ⚠️ SHIM | Forwards to legacy |
| `12.MarketRegime.mqh` | `Analysis/MarketRegime.mqh` | ⚠️ SHIM | Forwards to legacy |

## Layer 4 — Signal

| Legacy File | Canonical File | Status | Notes |
|---|---|---|---|
| `5.SignalManager.mqh` | `Signal/SignalManager.mqh` | ⚠️ SHIM | Forwards to legacy |

## Layer 5 — Trade

| Legacy File | Canonical File | Status | Notes |
|---|---|---|---|
| `6.ExecutionManager.mqh` | `Trade/ExecutionManager.mqh` | ⚠️ SHIM | Forwards to legacy |
| `8.RecoveryManager.mqh` | `Trade/RecoveryManager.mqh` | ✅ DONE | v2.05 — real code in Trade/ |

## Layer 5a — AI

| Legacy File | Canonical File | Status | Notes |
|---|---|---|---|
| `7.AIManager.mqh` | `AI/AIManager.mqh` | ⚠️ SHIM | Forwards to legacy; decompose in v3.0 |

## Layer 6 — Pattern *(already modular)*

| Legacy File | Canonical File | Status | Notes |
|---|---|---|---|
| `9.PatternManager.mqh` | `Pattern/PatternManager.mqh` | ✅ DONE | Migration complete since v2.04 |

## Layer 7 — UI

| Legacy File | Canonical File | Status | Notes |
|---|---|---|---|
| `11.DashboardManager.mqh` | `UI/DashboardManager.mqh` | ⚠️ SHIM | Forwards to legacy |

---

## Phase 2 Checklist (v3.0 — real code move)

Once all `#include` call-sites in EA `.mq5` files are updated to canonical paths,
the legacy root files can be deleted.

```
[ ] Update PASR.mqh to #include canonical paths only
[ ] Search all Experts/ .mq5 for legacy #include paths, update
[ ] Delete 0.EventBus.mqh through 12.MarketRegime.mqh root files
[ ] Delete IManager.mqh, Globals.mqh root files
[ ] Tag release v3.0
```

---

## Folder Architecture (Target State)

```
Include/PASR/
├── PASR.mqh               ← Master include (EA entry point)
├── Core/                  ← Layer 0: Zero dependencies
│   ├── EventBus.mqh
│   ├── Events.mqh
│   ├── ConfigTypes.mqh
│   ├── IManager.mqh
│   └── Globals.mqh
├── Infra/                 ← Layer 2: Broker API wrappers
│   ├── ConfigManager.mqh
│   └── DataManager.mqh
├── Analysis/              ← Layer 3: Market analysis
│   ├── MarketManager.mqh
│   ├── ZoneManager.mqh
│   ├── SRManager.mqh
│   └── MarketRegime.mqh
├── Signal/                ← Layer 4: Signal generation
│   └── SignalManager.mqh
├── AI/                    ← Layer 5a: Inference + training
│   └── AIManager.mqh
├── Trade/                 ← Layer 6: Execution + recovery
│   ├── ExecutionManager.mqh
│   └── RecoveryManager.mqh
├── Pattern/               ← Layer 3b: Candlestick analysis
│   ├── PatternManager.mqh
│   ├── Evaluators.mqh
│   ├── ScoreEngine.mqh
│   ├── FakeoutDetector.mqh
│   ├── CandleUtils.mqh
│   └── PatternTypes.mqh
├── UI/                    ← Layer 7: Dashboard (read-only)
│   └── DashboardManager.mqh
├── Tools/                 ← Utilities (no trading logic)
├── QA/                    ← Test files
└── docs/                  ← All .md documentation files
```
