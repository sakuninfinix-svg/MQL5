# Phase 3 — Manual Cleanup Guide

> Run these commands from your **MQL5 data folder root**  
> (e.g. `C:/Users/<you>/AppData/Roaming/MetaQuotes/Terminal/<ID>/MQL5/`)

## What Needs to Move

After audit Phase 1-3, the following files are in the wrong location.  
They clutter the `Include/PASR/` root and make the project harder to navigate.

### 1 — Orphan `.md` docs at `Include/PASR/` root

These should all live inside `Include/PASR/docs/`:

| File | Move to |
|------|---------|
| `IMPROVEMENT_ROADMAP.md` | `docs/IMPROVEMENT_ROADMAP.md` *(already exists — delete root copy)* |
| `MIGRATION_MAP.md` | `docs/MIGRATION_MAP.md` |
| `OPTIMIZATION_PHASE2.md` | `docs/OPTIMIZATION_PHASE2.md` |
| `OPTIMIZATION_REPORT.md` | `docs/OPTIMIZATION_REPORT.md` |
| `PERFORMANCE_OPTIMIZATION.md` | `docs/PERFORMANCE_OPTIMIZATION.md` |
| `QUICKSTART.md` | `docs/QUICKSTART.md` *(already exists — delete root copy)* |

```bash
# Run from Include/PASR/
git mv MIGRATION_MAP.md          docs/MIGRATION_MAP.md
git mv OPTIMIZATION_PHASE2.md    docs/OPTIMIZATION_PHASE2.md
git mv OPTIMIZATION_REPORT.md    docs/OPTIMIZATION_REPORT.md
git mv PERFORMANCE_OPTIMIZATION.md docs/PERFORMANCE_OPTIMIZATION.md
git rm IMPROVEMENT_ROADMAP.md    # duplicate of docs/IMPROVEMENT_ROADMAP.md
git rm QUICKSTART.md             # duplicate of docs/QUICKSTART.md
```

### 2 — `check_circular.sh` at `Include/PASR/` root

This is a developer tool script, not source code:

```bash
git mv check_circular.sh docs/tools/check_circular.sh
```

### 3 — `PASR.*.mqh` utility files at `Include/PASR/` root

These should move into typed subfolders:

| File | Move to | Reason |
|------|---------|--------|
| `PASR.Audit.mqh` | `QA/Audit.mqh` | Belongs with test/QA tooling |
| `PASR.Test.mqh` | `QA/Test.mqh` | Belongs with test/QA tooling |
| `PASR.BatchProcessor.mqh` | `Tools/BatchProcessor.mqh` | General utility |
| `PASR.Branchless.mqh` | `Tools/Branchless.mqh` | Performance utility |
| `PASR.MemoryPool.mqh` | `Tools/MemoryPool.mqh` | Memory management utility |
| `PASR.Optimizations.mqh` | `Tools/Optimizations.mqh` | Performance utility |

```bash
# Run from Include/PASR/
git mv PASR.Audit.mqh          QA/Audit.mqh
git mv PASR.Test.mqh           QA/Test.mqh
git mv PASR.BatchProcessor.mqh Tools/BatchProcessor.mqh
git mv PASR.Branchless.mqh     Tools/Branchless.mqh
git mv PASR.MemoryPool.mqh     Tools/MemoryPool.mqh
git mv PASR.Optimizations.mqh  Tools/Optimizations.mqh
```

> **After moving**, update any `#include` paths that reference the old locations.
> Search for `#include "PASR.Audit.mqh"` etc. with grep:
> ```bash
> grep -r 'PASR\.Audit\|PASR\.Test\|PASR\.Batch\|PASR\.Branchless\|PASR\.Memory\|PASR\.Optim' Include/PASR/
> ```

## Expected Result After Cleanup

```
Include/PASR/
├── README.md                  ← stays here (project entry point)
├── Core/
│   ├── PASR.mqh               ← master include (single entry point)
│   ├── IManager.mqh
│   ├── EventBus.mqh
│   ├── Events.mqh
│   ├── Globals.mqh
│   └── Config/
│       ├── Types.mqh
│       ├── Validator.mqh
│       └── Manager.mqh
├── AI/
├── Analysis/
├── Data/
├── Pattern/
├── Signal/
├── Trade/
├── Tools/
│   ├── BatchProcessor.mqh
│   ├── Branchless.mqh
│   ├── MemoryPool.mqh
│   └── Optimizations.mqh
├── QA/
│   ├── Audit.mqh
│   └── Test.mqh
├── UI/
└── docs/
    ├── ARCHITECTURE.md
    ├── DOCUMENTATION.md
    ├── IMPROVEMENT_ROADMAP.md
    ├── MIGRATION_MAP.md
    ├── OPTIMIZATION_PHASE2.md
    ├── OPTIMIZATION_REPORT.md
    ├── PERFORMANCE_OPTIMIZATION.md
    ├── PHASE3_CLEANUP.md      ← this file
    ├── QUICKSTART.md
    └── tools/
        └── check_circular.sh
```

## Why This Matters

- **11 files at the root** make it impossible to see which files are source code vs. docs vs. tools at a glance
- `#include` paths in MQL5 are resolved by the compiler exactly as written — stale paths after a rename will cause compile errors if not updated
- `git mv` preserves full commit history on each file, unlike delete+recreate
