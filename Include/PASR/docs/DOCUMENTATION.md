# PASR Documentation Index

This folder contains long-form PASR technical notes. README files stay short; active work belongs in GitHub Issues.

## Current Documents

| File | Purpose |
| --- | --- |
| `ARCHITECTURE.md` | Current kernel, registry, lifecycle, and pipeline architecture. |
| `CENTRALIZED_MODULAR_MIGRATION_PROJECT.md` | Historical migration plan and completion checklist for the centralized modular runtime. |
| `fundamental-business-logic-audit.md` | Post-migration business-logic risk map. |
| `QUICKSTART.md` | Minimal development entrypoint using `CPASRKernel`. |

## Canonical Runtime

Use:

```mql5
#include <PASR/Core/PASR.mqh>

CPASRKernel kernel;
```

Do not add new docs that describe older runtime adapters as active architecture. If a note is only a relocation placeholder, speculative benchmark, or superseded cleanup checklist, delete it instead of preserving noise.

## Documentation Rules

- Keep architecture docs aligned with `Include/PASR/Core/PASR.mqh`.
- Keep migration history separate from current usage docs.
- Do not claim production readiness without reproducible compile, tester, and forward-test evidence.
- Do not keep placeholder docs that only point to git history.
- Prefer one accurate short document over several stale reports.
