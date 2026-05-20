# PASR Migration Map

Single source of truth for the file migration & architecture status.  
Last updated: **v2.13** — 2026-05-20

---

## Migration Status — ALL CANONICAL ✅

| Module | Canonical Path | Status | Since |
|---|---|---|---|
| EventBus | `Core/EventBus.mqh` | ✅ CANONICAL | **v2.13** |
| Events | `Core/Events.mqh` | ✅ CANONICAL | **v2.13** |
| IManager | `Core/IManager.mqh` | ✅ CANONICAL | **v2.13** |
| Globals | `Core/Globals.mqh` | ✅ CANONICAL | **v2.13** |
| Config Types | `Core/Config/Types.mqh` | ✅ CANONICAL | v2.05 |
| Config Manager | `Core/Config/Manager.mqh` | ✅ CANONICAL | v2.05 |
| DataManager | `Infra/DataManager.mqh` | ✅ CANONICAL | v2.05 |
| MarketManager | `Data/MarketManager.mqh` | ✅ CANONICAL | v2.05 |
| ZoneManager | `Data/ZoneManager.mqh` | ✅ CANONICAL | v2.05 |
| SRManager | `Data/SRManager.mqh` | ✅ CANONICAL | v2.05 |
| MarketRegime | `Data/MarketRegime.mqh` | ✅ CANONICAL | v2.05 |
| PatternManager | `Pattern/PatternManager.mqh` | ✅ CANONICAL | v2.04 |
| SignalManager | `Signal/SignalManager.mqh` | ✅ CANONICAL | v2.12 |
| ExecutionManager | `Trade/ExecutionManager.mqh` | ✅ CANONICAL | v2.12 |
| RecoveryManager | `Trade/RecoveryManager.mqh` | ✅ CANONICAL | v2.05 |
| DashboardManager | `UI/DashboardManager.mqh` | ✅ CANONICAL | v2.12 |
| AIManager | `AI/AIManager.mqh` | 🔶 SCAFFOLD | v2.12 |

**16/17 modules fully canonical. AI scaffold ready — needs weight loading + backprop.**

---

## Legacy Shims (root numbered files)

All numbered files are now **thin forwarders only** — no real code.

| Shim File | Forwards To | Safe to Delete When |
|---|---|---|
| `0.EventBus.mqh` | `Core/EventBus.mqh` | All EAs use Core/ path |
| `1.Events.mqh` | `Core/Events.mqh` | All EAs use Core/ path |
| `2.Config.Types.mqh` | `Core/Config/Types.mqh` | All EAs use Core/ path |
| `2.Config.Manager.mqh` | `Core/Config/Manager.mqh` | All EAs use Core/ path |
| `3.MarketManager.mqh` | `Data/MarketManager.mqh` | All EAs use Data/ path |
| `3.ZoneManager.mqh` | `Data/ZoneManager.mqh` | All EAs use Data/ path |
| `4.SRManager.mqh` | `Data/SRManager.mqh` | All EAs use Data/ path |
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

## Docs Cleanup (v2.13)

Stale `.md` files removed from source root (moved/superseded by README.md):
- ~~`OPTIMIZATION_REPORT.md`~~ — deleted
- ~~`OPTIMIZATION_PHASE2.md`~~ — deleted  
- ~~`PERFORMANCE_OPTIMIZATION.md`~~ — deleted
- ~~`IMPROVEMENT_ROADMAP.md`~~ — deleted
- ~~`DOCUMENTATION.md`~~ — deleted

---

## Remaining Work — v3.0

| Task | Priority | Effort |
|---|---|---|
| `CAIInference`: real weight loading from `.onnx` / `.bin` | 🔴 HIGH | Large |
| `CAITrainer`: SGD/Adam backprop implementation | 🔴 HIGH | Large |
| `CAIOrchestrator::BuildFeatures()`: wire to DataManager | 🟠 MEDIUM | Small |
| `Core/Config/Types.mqh`: add `Validate()` method | 🟠 MEDIUM | Small |
| Delete all `N.Xxx.mqh` shims after EA migration complete | 🟡 LOW | Trivial |
