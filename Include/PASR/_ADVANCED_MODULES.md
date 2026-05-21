# PASR Advanced Performance Modules

> **Status:** Optional opt-in modules. **NOT included by default** in `PASR_MODULAR.mq5`.
> Safe to ignore for standard EA operation. Include only when profiling
> confirms a specific bottleneck.

---

## Files in This Layer

| File | Size | Purpose | When to use |
|------|------|---------|-------------|
| `PASR.Optimizations.mqh` | 24KB | Tick-rate limiter, indicator handle cache, price cache, zone lookup acceleration | Tick volume > 10k/day on VPS with tight CPU budget |
| `PASR.Branchless.mqh` | 12KB | Branchless math helpers: `SignNoZero`, `ClampD`, `LerpD`, conditional-move patterns | Hot-path signal scoring loops |
| `PASR.BatchProcessor.mqh` | 13KB | Batch bar-data processing, OHLCV vectorized reads for multi-symbol or multi-TF analysis | Portfolio EA or walk-forward harness |
| `PASR.MemoryPool.mqh` | 14KB | Fixed-size object pool for `RecoveryEngine*`, `SRZone*`, reused pattern structs | Avoids heap fragmentation on 24/7 VPS runs > 30 days |

---

## How to Opt-In

Add the desired include **after** all standard Trade/Analysis includes
in `PASR_MODULAR.mq5`, before `AI/` includes:

```mql5
//--- [OPT] Advanced performance layer (uncomment as needed)
// #include <PASR/PASR.Optimizations.mqh>   // tick-rate + cache
// #include <PASR/PASR.Branchless.mqh>      // branchless math
// #include <PASR/PASR.BatchProcessor.mqh>  // batch OHLCV (portfolio)
// #include <PASR/PASR.MemoryPool.mqh>      // memory pool (long-run VPS)
```

Each module is self-contained and does not modify existing manager
interfaces — they expose utility classes/functions used alongside
existing managers.

---

## Dependency Notes

- `PASR.Optimizations.mqh` → depends on `Core/Config.mqh`, `Infra/DataManager.mqh`
- `PASR.Branchless.mqh`    → no dependencies (pure math)
- `PASR.BatchProcessor.mqh`→ depends on `Infra/DataManager.mqh`
- `PASR.MemoryPool.mqh`    → depends on `Trade/RecoveryEngine.mqh`, `Analysis/SRManager.mqh`

---

## Why Not Wired by Default?

These modules add compile-time complexity and increase the include
graph depth. For single-symbol, single-TF usage on modern VPS hardware,
the standard module stack is already performant. These are provided for:

1. **Profiling-driven optimization** — only optimize what the profiler shows
2. **Portfolio EA adaptation** — BatchProcessor enables multi-symbol loops
3. **Long-duration live VPS** — MemoryPool prevents heap fragmentation after weeks of operation

---

*Last updated: 2026-05-21 — Kategori-1 cleanup, v4.01*
