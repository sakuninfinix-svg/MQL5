# PASR Framework

> **Price Action Support/Resistance** — Production-grade Expert Advisor framework for MetaTrader 5.
> Version: 3.x (Modular Architecture) · Copyright 2026, Agsicentre

---

## Quick Start

```mql5
// In your EA .mq5 file — ONE line replaces all old numeric includes
#include <PASR/Core/PASR.mqh>
```

This single include guarantees the correct load order across all 8 layers automatically.

---

## Folder Structure (Current — v3.x Modular)

```
Include/PASR/
│
├── Core/                        ← L1: Foundation (zero business logic)
│   ├── PASR.mqh                 ← ★ MASTER INCLUDE — start here
│   ├── IManager.mqh             → stub → ../IManager.mqh
│   ├── EventBus.mqh             → stub → ../0.EventBus.mqh
│   ├── Events.mqh               → stub → ../1.Events.mqh
│   └── Config/
│       ├── Types.mqh            → stub → ../2.Config.Types.mqh
│       └── Manager.mqh          → stub → ../2.Config.Manager.mqh
│
├── Infra/                       ← L2: Infrastructure (PRODUCTION files)
│   ├── DataManager.mqh          ★ Production — bug-fixed, account-safe GVs
│   └── DataManager.shim.mqh    (backward-compat shim, remove in v4.0)
│
├── Data/                        ← L3: Data access aliases → Infra/ or root
│   ├── DataManager.mqh          → Infra/DataManager.mqh (production)
│   ├── MarketManager.mqh        → 3.MarketManager.mqh (pending migration)
│   ├── ZoneManager.mqh          → 3.ZoneManager.mqh   (pending migration)
│   ├── SRManager.mqh            → 4.SRManager.mqh      (pending migration)
│   └── MarketRegime.mqh         → 12.MarketRegime.mqh  (pending migration)
│
├── Analysis/                    ← L3+: (subfolders — pending population)
├── Signal/                      ← L4: (sublayer AI/ pending)
├── AI/                          ← L4 sub: AIManager decomposition (pending)
│
├── Trade/                       ← L6: Trade execution layer
│   ├── TradePlan.mqh            ★ Production — SRP-extracted from ExecMgr
│   ├── ExecutionManager.mqh     ★ Production — all PASR-BUG-00x fixes applied
│   ├── RecoveryManager.mqh      → stub → 8.RecoveryManager.mqh
│   │                              ⚠ PASR-BUG-003 pending in legacy source
│   ├── ExecutionManager.shim.mqh (backward-compat, remove in v4.0)
│   └── _README.mqh              (layer documentation)
│
├── UI/                          ← L7: Dashboard (pending migration)
├── Pattern/                     ← Analysis sub (pending)
├── QA/                          ← L8: Audit/Test tools (pending)
├── Tools/                       ← Utilities (pending)
│
├── docs/                        ← Internal documentation
├── PASR.mqh                     ← Root forward → Core/PASR.mqh
├── Globals.mqh                  ← Consolidated extern declarations
│
│── ── LEGACY ROOT FILES (still authoritative — migration in progress) ──────
├── 0.EventBus.mqh               ★ Active source
├── 1.Events.mqh                 ★ Active source
├── 2.Config.Types.mqh           ★ Active source (53 KB — split planned v4.0)
├── 2.Config.Manager.mqh         ★ Active source
├── 3.MarketManager.mqh          ★ Active source
├── 3.ZoneManager.mqh            ★ Active source
├── 4.SRManager.mqh              ★ Active source
├── 5.SignalManager.mqh          ★ Active source
├── 6.ExecutionManager.mqh       ⚠ Legacy — superseded by Trade/ExecutionManager.mqh
├── 7.AIManager.mqh              ⚠ God object — decomposition pending (AI/ folder)
├── 8.RecoveryManager.mqh        ⚠ Active but has PASR-BUG-003 (cfg scope)
├── 9.PatternManager.mqh         ★ Active source
├── 10.DataManager.mqh           ⚠ Legacy — superseded by Infra/DataManager.mqh
├── 11.DashboardManager.mqh      ★ Active source (pending → UI/)
├── 12.MarketRegime.mqh          ★ Active source
│
├── IManager.mqh                 ★ Active source (abstract base)
└── PASR.Audit/Test/Opt.mqh     ★ QA tools (PASR_QA_BUILD only)
```

---

## Layer Architecture

| Layer | Folder | Responsibility | Dependency Rule |
|-------|--------|---------------|-----------------|
| L1 | `Core/` | IManager, EventBus, Events, Config | May only include other `Core/` files |
| L2 | `Infra/` | DataManager (GV state, cache, PnL) | May include `Core/` only |
| L3 | `Data/` | Market data access aliases | Forwards to `Infra/` or root sources |
| L3+ | `Analysis/` | SRManager, ZoneManager, MarketRegime | May include `Core/`, `Infra/`, `Data/` |
| L4 | `Signal/` + `AI/` | SignalManager, AIManager | May include L1–L3 only |
| L5 | `Pattern/` | CandlePatternManager | May include L1–L3 only |
| L6 | `Trade/` | TradePlan, ExecutionManager, RecoveryManager | May include L1–L5 |
| L7 | `UI/` | DashboardManager | May include all lower layers |
| L8 | `QA/` | Audit, Test, Optimizer | Dev builds only (`#ifdef PASR_QA_BUILD`) |

**Golden Rule:** Higher layers NEVER include lower layers. Violations = circular dependency.

---

## Migration Status

| File | New Canonical Path | Status | Notes |
|------|--------------------|--------|-------|
| `IManager.mqh` | `Core/IManager.mqh` | 🔄 Stub ready | Source still at root |
| `0.EventBus.mqh` | `Core/EventBus.mqh` | 🔄 Stub ready | Source still at root |
| `1.Events.mqh` | `Core/Events.mqh` | 🔄 Stub ready | Source still at root |
| `2.Config.Types.mqh` | `Core/Config/Types.mqh` | 🔄 Stub ready | 53 KB — split in v4.0 |
| `2.Config.Manager.mqh` | `Core/Config/Manager.mqh` | 🔄 Stub ready | |
| `10.DataManager.mqh` | `Infra/DataManager.mqh` | ✅ **DONE** | All bugs fixed |
| `6.ExecutionManager.mqh` | `Trade/ExecutionManager.mqh` | ✅ **DONE** | All bugs fixed |
| `Trade/TradePlan.mqh` | *(new file — extracted)* | ✅ **DONE** | SRP extract |
| `8.RecoveryManager.mqh` | `Trade/RecoveryManager.mqh` | 🔄 Stub ready | ⚠ BUG-003 pending |
| `3.MarketManager.mqh` | `Analysis/MarketManager.mqh` | ⏳ Pending | |
| `3.ZoneManager.mqh` | `Analysis/ZoneManager.mqh` | ⏳ Pending | |
| `4.SRManager.mqh` | `Analysis/SRManager.mqh` | ⏳ Pending | |
| `12.MarketRegime.mqh` | `Analysis/MarketRegime.mqh` | ⏳ Pending | extern sprawl issue |
| `7.AIManager.mqh` | `AI/AIOrchestrator.mqh` + `AI/AIInference.mqh` + `AI/AITrainer.mqh` | ⏳ Pending | God object decomp |
| `5.SignalManager.mqh` | `Signal/SignalManager.mqh` | ⏳ Pending | |
| `9.PatternManager.mqh` | `Pattern/PatternManager.mqh` | ⏳ Pending | |
| `11.DashboardManager.mqh` | `UI/DashboardManager.mqh` | ⏳ Pending | |

---

## Bug Fix Register

| ID | Severity | File | Description | Status |
|----|----------|------|-------------|--------|
| PASR-BUG-001 | 🔴 Critical | `Infra/DataManager.mqh` | GV keys missing `ACCOUNT_LOGIN` prefix → multi-instance state corruption | ✅ Fixed |
| PASR-BUG-002 | 🔴 Critical | `Trade/ExecutionManager.mqh` | `ScavengePendingGVs()` O(n²) on every bar → CPU spike | ✅ Fixed |
| PASR-BUG-003 | 🔴 Critical | `8.RecoveryManager.mqh` | `cfg` undeclared in `ClearEngineGVs()` → runtime NULL crash | ⏳ Pending |
| PASR-BUG-004 | 🟠 High | `Trade/ExecutionManager.mqh` | Dashboard string rebuilt on every tick → heap churn | ✅ Fixed |
| PASR-BUG-005 | 🟠 High | `Infra/DataManager.mqh` | Daily PnL formula missing floating component | ✅ Fixed |
| PASR-BUG-006 | 🟠 High | Multiple | `extern` declarations duplicated across 3+ files → linker collision | ✅ Fixed via `Globals.mqh` |

---

## Include Path Reference

```mql5
// ── Recommended (always use these canonical paths) ──────────────────────
#include <PASR/Core/PASR.mqh>              // Everything, correct load order
#include <PASR/Infra/DataManager.mqh>      // Data layer only
#include <PASR/Trade/ExecutionManager.mqh> // Trade layer only
#include <PASR/Trade/TradePlan.mqh>        // Trade plan struct

// ── Config sub-includes ───────────────────────────────────────────────────
#include <PASR/Core/Config/Types.mqh>      // StrategyConfig struct
#include <PASR/Core/Config/Manager.mqh>    // CConfigManager

// ── Legacy paths (still work via shims — deprecated, remove in v4.0) ─────
#include <PASR/10.DataManager.mqh>         // ⚠ Use Infra/DataManager.mqh instead
#include <PASR/6.ExecutionManager.mqh>     // ⚠ Use Trade/ExecutionManager.mqh instead
```

---

## Development Guidelines

### Adding a New Manager

1. Create in the correct layer folder (e.g., `Analysis/MyManager.mqh`)
2. Inherit from `IManager` (via `Core/IManager.mqh`)
3. Subscribe to events via `EventBus` — never call other managers directly
4. Add a canonical stub in the appropriate alias folder if needed
5. Register the include in `Core/PASR.mqh` at the correct layer position
6. Add GV keys with `AccountInfoInteger(ACCOUNT_LOGIN)` prefix

### GlobalVariable Key Convention

```mql5
// CORRECT — account-safe, magic-number-scoped
string key = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))
           + "_PASR_"
           + IntegerToString(MagicNumber)
           + "_KeyName";

// WRONG — causes live/demo cross-contamination
string key = "PASR_" + IntegerToString(MagicNumber) + "_KeyName";
```

### QA Build

Enable the full audit/test suite by defining `PASR_QA_BUILD` before the include:

```mql5
#define PASR_QA_BUILD
#include <PASR/Core/PASR.mqh>
```

---

## Documentation

| File | Contents |
|------|----------|
| `README.md` | This file — architecture overview |
| `QUICKSTART.md` | Step-by-step EA integration guide |
| `DOCUMENTATION.md` | Full API reference |
| `IMPROVEMENT_ROADMAP.md` | Prioritized refactor backlog |
| `PERFORMANCE_OPTIMIZATION.md` | Performance analysis & benchmarks |
| `OPTIMIZATION_PHASE2.md` | Phase 2 optimization plan |
| `OPTIMIZATION_REPORT.md` | Optimization audit results |
| `docs/` | Internal architecture notes |

---

## Version History

| Version | Changes |
|---------|---------|
| v3.x | Modular subfolder architecture; `Core/PASR.mqh` master include; production `Infra/DataManager.mqh`; `Trade/ExecutionManager.mqh` + `TradePlan.mqh`; `Globals.mqh` extern consolidation; all PASR-BUG-00x fixes except BUG-003 |
| v2.x | 12-file flat numeric prefix system (0.EventBus … 12.MarketRegime) |
| v1.x | Initial monolithic EA structure |
