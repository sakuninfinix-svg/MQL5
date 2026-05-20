# PASR Migration Map

Single source of truth for the file migration & architecture status.

## Architecture Discovered (Actual State)

The PASR framework was **already substantially migrated** before the v2.05 audit.
The correct canonical entry point is `Core/PASR.mqh`, not root `PASR.mqh`.

### Real Migration State

| Category | Status | Notes |
|---|---|---|
| `Core/` EventBus, Events, IManager | ✅ CANONICAL | Real code lives here |
| `Core/Config/Types.mqh` | ✅ CANONICAL | Split from 2.Config.Types.mqh |
| `Core/Config/Manager.mqh` | ✅ CANONICAL | Split from 2.Config.Manager.mqh |
| `Infra/DataManager.mqh` | ✅ CANONICAL | Production account-safe impl |
| `Data/MarketManager.mqh` | ✅ CANONICAL | Forwards to Infra/ production |
| `Data/ZoneManager.mqh` | ✅ CANONICAL | Forwards to legacy or Infra/ |
| `Data/SRManager.mqh` | ✅ CANONICAL | Forwards to legacy or Infra/ |
| `Data/MarketRegime.mqh` | ✅ CANONICAL | Forwards to legacy or Infra/ |
| `Pattern/PatternManager.mqh` | ✅ CANONICAL | Since v2.04 |
| `Trade/RecoveryManager.mqh` | ✅ CANONICAL | v2.05, full production code |
| `Trade/ExecutionManager.mqh` | ⚠️ SHIM | Forwards to 6.ExecutionManager.mqh |
| `AI/AIManager.mqh` | ⚠️ SHIM | Forwards to 7.AIManager.mqh |
| `Signal/SignalManager.mqh` | ⚠️ SHIM | Forwards to 5.SignalManager.mqh |
| `UI/DashboardManager.mqh` | ⚠️ SHIM | Forwards to 11.DashboardManager.mqh |
| `Analysis/*.mqh` | ⚠️ ALIAS | Forwards to Data/ canonical files |

### Legacy Root Files (Backward-Compat Shims)

These files still exist for EA consumers that use old paths.
They are shims — real code has moved.

| File | Forwards To | Delete When |
|---|---|---|
| `0.EventBus.mqh` | `Core/EventBus.mqh` | All EAs use Core/ path |
| `1.Events.mqh` | `Core/Events.mqh` | All EAs use Core/ path |
| `2.Config.Types.mqh` | `Core/Config/Types.mqh` | All EAs use Core/ path |
| `2.Config.Manager.mqh` | `Core/Config/Manager.mqh` | All EAs use Core/ path |
| `3.MarketManager.mqh` | `Data/MarketManager.mqh` | All EAs use Data/ path |
| `3.ZoneManager.mqh` | `Data/ZoneManager.mqh` | All EAs use Data/ path |
| `4.SRManager.mqh` | `Data/SRManager.mqh` | All EAs use Data/ path |
| `5.SignalManager.mqh` | `Signal/SignalManager.mqh` | Requires Signal/ real code |
| `6.ExecutionManager.mqh` | `Trade/ExecutionManager.mqh` | Requires Trade/ real code |
| `7.AIManager.mqh` | `AI/AIManager.mqh` | Requires AI/ decomposition |
| `8.RecoveryManager.mqh` | `Trade/RecoveryManager.mqh` | ✅ DONE — shim safe to keep |
| `9.PatternManager.mqh` | `Pattern/PatternManager.mqh` | ✅ DONE |
| `10.DataManager.mqh` | `Infra/DataManager.mqh` | All EAs use Infra/ path |
| `11.DashboardManager.mqh` | `UI/DashboardManager.mqh` | Requires UI/ real code |
| `12.MarketRegime.mqh` | `Data/MarketRegime.mqh` | All EAs use Data/ path |
| `IManager.mqh` (root) | `Core/IManager.mqh` | All EAs use Core/ path |
| `Globals.mqh` (root) | `Core/Globals.mqh` | All EAs use Core/ path |

---

## Correct Entry Points

```
// New canonical EA include (preferred):
#include <PASR/Core/PASR.mqh>

// Legacy EA include (still works, forwards to above):
#include <PASR/PASR.mqh>
```

---

## Next Phase — Remaining Shims to Replace with Real Code

These `N.Xxx.mqh` files still hold real logic and have not been fully moved:

| Priority | File | Target | Blocker |
|---|---|---|---|
| 🔴 HIGH | `7.AIManager.mqh` | `AI/` decomposition | Needs split: Inference / Trainer / Orchestrator |
| 🟠 MEDIUM | `6.ExecutionManager.mqh` | `Trade/ExecutionManager.mqh` | ScavengePendingGVs O(n²) fix needed first |
| 🟡 LOW | `5.SignalManager.mqh` | `Signal/SignalManager.mqh` | Stable, low risk |
| 🟡 LOW | `11.DashboardManager.mqh` | `UI/DashboardManager.mqh` | Add 1Hz throttle then move |

---

## Folder Architecture (Current Target State)

```
Include/PASR/
├── PASR.mqh               ← Thin forwarder → Core/PASR.mqh
├── Core/
│   ├── PASR.mqh           ← TRUE master include (EA entry point)
│   ├── EventBus.mqh       ← CANONICAL
│   ├── Events.mqh         ← CANONICAL  
│   ├── IManager.mqh       ← CANONICAL
│   ├── Globals.mqh        → ../Globals.mqh (root)
│   └── Config/
│       ├── Types.mqh      ← CANONICAL (from 2.Config.Types)
│       └── Manager.mqh    ← CANONICAL (from 2.Config.Manager)
├── Infra/
│   └── DataManager.mqh    ← CANONICAL production
├── Data/                  ← Named aliases → Infra/ / legacy
├── Analysis/              ← Named aliases → Data/
├── Pattern/               ← CANONICAL (PatternManager + sub-files)
├── Signal/                ← SHIM → 5.SignalManager.mqh
├── AI/                    ← SHIM → 7.AIManager.mqh (decompose v3.0)
├── Trade/
│   ├── ExecutionManager.mqh ← SHIM → 6.ExecutionManager.mqh
│   └── RecoveryManager.mqh  ← CANONICAL v2.05
├── UI/                    ← SHIM → 11.DashboardManager.mqh
├── Tools/
├── QA/
└── docs/
```
