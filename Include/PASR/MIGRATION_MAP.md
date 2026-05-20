# PASR Migration Map

Single source of truth for the file migration & architecture status.
Last updated: **v2.12** — 2026-05-20

---

## Migration Status Overview

| Category | Status | Version |
|---|---|---|
| `Core/` EventBus, Events, IManager | ✅ CANONICAL | v2.05 |
| `Core/Config/Types.mqh` | ✅ CANONICAL | v2.05 |
| `Core/Config/Manager.mqh` | ✅ CANONICAL | v2.05 |
| `Infra/DataManager.mqh` | ✅ CANONICAL | v2.05 |
| `Data/MarketManager.mqh` | ✅ CANONICAL | v2.05 |
| `Data/ZoneManager.mqh` | ✅ CANONICAL | v2.05 |
| `Data/SRManager.mqh` | ✅ CANONICAL | v2.05 |
| `Data/MarketRegime.mqh` | ✅ CANONICAL | v2.05 |
| `Pattern/PatternManager.mqh` | ✅ CANONICAL | v2.04 |
| `Trade/RecoveryManager.mqh` | ✅ CANONICAL | v2.05 |
| `Trade/ExecutionManager.mqh` | ✅ CANONICAL | **v2.12** |
| `Signal/SignalManager.mqh` | ✅ CANONICAL | **v2.12** |
| `UI/DashboardManager.mqh` | ✅ CANONICAL | **v2.12** |
| `AI/AIManager.mqh` | 🔶 SCAFFOLD | **v2.12** — Inference safe, Trainer TODO |

---

## AI Decomposition Status (v2.12)

`AI/AIManager.mqh` has been scaffolded into three classes:

| Class | Status | Notes |
|---|---|---|
| `CAIInference` | 🔶 SCAFFOLD | Forward pass stub; real weights TODO |
| `CAITrainer` | 🔶 SCAFFOLD | Replay buffer real; backprop TODO |
| `CAIOrchestrator` | 🔶 SCAFFOLD | Wires inference+trainer; feature build TODO |
| `CAIManager` | ✅ ALIAS | `typedef CAIOrchestrator CAIManager` — no EA refactor needed |

**Critical fix applied:** `CAIOrchestrator::OnPriceUpdate()` is intentionally empty.
All inference runs on `OnNewBar()`. Training runs on `OnTimer()` only.
Backprop is **never** called from the tick thread.

---

## Legacy Root Shims (Backward-Compat)

These files exist for EAs that use old paths. They forward to canonical files.

| File | Forwards To | Status |
|---|---|---|
| `0.EventBus.mqh` | `Core/EventBus.mqh` | ✅ Shim safe |
| `1.Events.mqh` | `Core/Events.mqh` | ✅ Shim safe |
| `2.Config.Types.mqh` | `Core/Config/Types.mqh` | ✅ Shim safe |
| `2.Config.Manager.mqh` | `Core/Config/Manager.mqh` | ✅ Shim safe |
| `3.MarketManager.mqh` | `Data/MarketManager.mqh` | ✅ Shim safe |
| `3.ZoneManager.mqh` | `Data/ZoneManager.mqh` | ✅ Shim safe |
| `4.SRManager.mqh` | `Data/SRManager.mqh` | ✅ Shim safe |
| `5.SignalManager.mqh` | `Signal/SignalManager.mqh` | ✅ Shim safe |
| `6.ExecutionManager.mqh` | `Trade/ExecutionManager.mqh` | ✅ Shim safe |
| `7.AIManager.mqh` | `AI/AIManager.mqh` | ✅ Shim safe |
| `8.RecoveryManager.mqh` | `Trade/RecoveryManager.mqh` | ✅ Shim safe |
| `9.PatternManager.mqh` | `Pattern/PatternManager.mqh` | ✅ Shim safe |
| `10.DataManager.mqh` | `Infra/DataManager.mqh` | ✅ Shim safe |
| `11.DashboardManager.mqh` | `UI/DashboardManager.mqh` | ✅ Shim safe |
| `12.MarketRegime.mqh` | `Data/MarketRegime.mqh` | ✅ Shim safe |
| `IManager.mqh` (root) | `Core/IManager.mqh` | ✅ Shim safe |
| `Globals.mqh` (root) | `Core/Globals.mqh` | ✅ Shim safe |

---

## Entry Points

```cpp
// ✅ PREFERRED — new EAs:
#include <PASR/Core/PASR.mqh>

// ✅ LEGACY — existing EAs (still works, thin forward):
#include <PASR/PASR.mqh>
```

---

## Remaining Work (v3.0 targets)

| Task | Priority | Effort |
|---|---|---|
| `CAIInference`: load real weights from `.bin` file | 🔴 HIGH | Medium |
| `CAITrainer`: implement real SGD/Adam backprop | 🔴 HIGH | Large |
| `CAIOrchestrator::BuildFeatures()`: wire to DataManager | 🟠 MEDIUM | Small |
| Delete all `N.Xxx.mqh` root shims after EA migration | 🟡 LOW | Small |
| `Core/Config/Types.mqh`: add `Validate()` method | 🟠 MEDIUM | Small |
