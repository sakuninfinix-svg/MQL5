# Analysis/Pattern

Folder ini adalah tempat yang tepat untuk candlestick pattern recognition karena pattern adalah bagian dari domain analysis, bukan signal execution atau central orchestration.

Runtime canonical saat ini:

```text
PatternTypes.mqh
PatternManager.mqh
```

`CPatternManager` adalah `IManager` yang dimiliki `CPASRKernel` melalui registry. Runtime pipeline memanggilnya dari `Orchestration/Stages/PatternStage.mqh` pada `new_bar`, lalu hasil terakhir dipakai oleh:

- `Signal/PatternSignalSource.mqh`
- `Orchestration/Stages/SignalStage.mqh`
- AI feature injection melalui `SPatternFeatureSnapshot`

## Policy

- Jangan menambah sub-pipeline lokal di folder ini selama `CPatternManager` masih cukup kecil dan compile-clean.
- Jangan menyimpan scaffold strategi yang tidak di-wire ke `PatternStage`.
- Tambahkan pattern baru langsung ke manager hanya jika kompleksitasnya masih wajar.
- Jika jumlah pattern atau kompleksitas sudah terlalu besar, buat refactor nyata yang langsung terhubung ke `PatternStage` dan compile gate.

## Compile Gates

Setelah mengubah folder ini, compile:

```text
Experts/PASR_MODULAR.mq5
Scripts/PASR_Smoke.mq5
Scripts/PASR_PipelineHarness_Smoke.mq5
```
