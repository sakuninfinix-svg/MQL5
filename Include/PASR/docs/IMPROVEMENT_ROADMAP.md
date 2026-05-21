# PASR EA — Improvement Roadmap

Live tracker for all audit phases. Updated after each phase commit.

## Phase Status Summary

| Phase | Commit | Status | Files Changed |
|-------|--------|--------|---------------|
| Phase 1 | (prior) | ✅ Done | RecoveryManager, EventBus, IManager base |
| Phase 2 | `3b695be` | ✅ Done | ExecutionManager, AIOrchestrator |
| Phase 3 | `HEAD` | ✅ Done | Validator (3 new rules), docs cleanup guide |
| Phase 4 | — | 🔲 Planned | Manual root cleanup (see PHASE3_CLEANUP.md) |

---

## All Fixed Issues (Phase 1–3)

| # | File | Issue | Severity | Phase | Status |
|---|------|-------|----------|-------|--------|
| 1 | RecoveryManager | `cfg` undeclared in `ClearEngineGVs()` | 🔴 Critical | 1 | ✅ Fixed |
| 2 | IManager | `BuildGVPrefix()` missing account login | 🔴 Critical | 1 | ✅ Fixed |
| 3 | EventBus | Priority queue O(n²) bubble sort | 🟠 High | 1 | ✅ Fixed |
| 4 | Events | `#define EVENT_ID_*` macros → enum ENUM_EVENT_ID | 🟠 High | 1 | ✅ Fixed |
| 5 | IManager | Per-function StrategyConfig copy via GetConfigCache() | 🟠 High | 1 | ✅ Fixed |
| 6 | Config/Types | Monolithic struct → 5 sub-structs (SRP) | 🟠 High | 1 | ✅ Fixed |
| 7 | Validator | No validation at all on StrategyConfig | 🔴 Critical | 1 | ✅ Fixed (25 rules) |
| 8 | ExecutionManager | Global `BuildGVPrefix()` duplicate — linker risk | 🔴 Critical | 2 | ✅ Fixed |
| 9 | ExecutionManager | Direct `#include Globals.mqh` — double extern | 🔴 Critical | 2 | ✅ Fixed |
| 10 | AIOrchestrator | Stale include paths (`IManager.mqh`, `10.DataManager.mqh`) | 🔴 Critical | 2 | ✅ Fixed |
| 11 | AIOrchestrator | `ModelConfig.status` field undeclared but used | 🔴 Critical | 2 | ✅ Fixed |
| 12 | AIOrchestrator | `Init()` signature mismatch with IManager base | 🔴 Critical | 2 | ✅ Fixed |
| 13 | AIOrchestrator | Training synchronous on tick thread | 🔴 Critical | 2 | ✅ Fixed (deferred) |
| 14 | Validator | Missing `DisplayConfig.FontSize` range check | 🟡 Medium | 3 | ✅ Fixed (Rule 26) |
| 15 | Validator | No total-risk guard (RiskPercent × MaxPositions) | 🔴 Critical | 3 | ✅ Fixed (Rule 27) |
| 16 | Validator | `ModelFileName` path traversal not blocked | 🟠 High | 3 | ✅ Fixed (Rule 28) |

---

## Phase 4 — Planned (Manual Cleanup)

See `PHASE3_CLEANUP.md` for exact git commands.

**Files to move:**

| File | From | To |
|------|------|----|
| `MIGRATION_MAP.md` | PASR root | `docs/` |
| `OPTIMIZATION_PHASE2.md` | PASR root | `docs/` |
| `OPTIMIZATION_REPORT.md` | PASR root | `docs/` |
| `PERFORMANCE_OPTIMIZATION.md` | PASR root | `docs/` |
| `IMPROVEMENT_ROADMAP.md` (root) | PASR root | delete (dup) |
| `QUICKSTART.md` (root) | PASR root | delete (dup) |
| `check_circular.sh` | PASR root | `docs/tools/` |
| `PASR.Audit.mqh` | PASR root | `QA/` |
| `PASR.Test.mqh` | PASR root | `QA/` |
| `PASR.BatchProcessor.mqh` | PASR root | `Tools/` |
| `PASR.Branchless.mqh` | PASR root | `Tools/` |
| `PASR.MemoryPool.mqh` | PASR root | `Tools/` |
| `PASR.Optimizations.mqh` | PASR root | `Tools/` |

**Estimate:** 30 minutes via git mv locally, then one push.

---

## Architecture Quality After Phase 3

| Dimension | Before Audit | After Phase 3 | Delta |
|-----------|-------------|---------------|-------|
| Architecture | 6/10 | 7.5/10 | +1.5 |
| Code Quality | 6/10 | 8/10 | +2.0 |
| Performance | 5/10 | 7.5/10 | +2.5 |
| Security | 4/10 | 7/10 | +3.0 |
| Maintainability | 5/10 | 7/10 | +2.0 |
| Scalability | 5/10 | 6.5/10 | +1.5 |

> Full Phase 4 (cleanup) will push Architecture and Maintainability to 8.5+ by removing the root folder clutter.
