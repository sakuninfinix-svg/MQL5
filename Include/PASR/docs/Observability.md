# Observability Module (`PASR/Observability/`)

1 file — Metric names and unit definitions.

## File Reference

| # | File | Fungsi |
|---|------|--------|
| 1 | `ObservabilityTypes.mqh` | `#define` constants for metric names and unit strings |

## Metric Prefixes

| Prefix | Contoh |
|--------|--------|
| `Obs_` | General observability |
| `Pipeline_Latency_` | Stage execution latencies |
| `Execution_Slippage` | Order slippage tracking |
| `Signal_Strength` | Signal confidence scores |

## Units

`value`, `chars`, `normalized`, `score`, `points`, `enum`, `microseconds`

Used by: `CTelemetryRecorder`, `CDashboardManager`, `CJournalManager`.
