# Phase 5 Split Stage Extraction Progress

Tanggal: 2026-06-01
Branch: `migration/centralized-modular-phase4`

## Tujuan Phase 5

Mengubah `CPipelineEngine` secara bertahap dari class yang menyimpan semua logic stage menjadi executor yang menjalankan object stage mandiri berbasis `IPipelineStage`.

Prinsip migrasi:

- jangan ubah logic trading sebelum compile baseline hijau,
- jangan pindahkan semua stage sekaligus,
- buat contract stage stabil lebih dulu,
- setiap stage harus bisa di-enable/disable dan menerima debug/profiling flag,
- runtime lama tetap berjalan sampai stage object benar-benar siap menggantikan method internal.

## Progress saat ini

Sudah dilakukan:

- `IPipelineStage` diperkuat dengan hook compatibility:
  - `SetEnabled(bool)`,
  - `SetDebugMode(bool)`,
  - `SetProfilingEnabled(bool)`.
- File baru `Orchestration/Stages/PipelineStageBase.mqh` dibuat sebagai base class reusable.
- Master include `Core/PASR.mqh` sudah include `PipelineStageBase.mqh`.
- Scaffold stage awal sudah dipindahkan ke `CPipelineStageBase`:
  - `CDataSyncStage`,
  - `CSignalStage`,
  - `CRiskStage`.

## Status runtime

Runtime trading belum diubah.

`CPipelineEngine` masih memakai method internal seperti:

```text
Stage_DataSync()
Stage_SignalGen()
Stage_RiskCheck()
Stage_Execution()
```

Ini disengaja agar compile baseline tetap mudah dilacak. Scaffold stage baru belum mengambil alih execution flow.

## File yang disentuh Phase 5 awal

```text
Include/PASR/Orchestration/PipelineStage.mqh
Include/PASR/Orchestration/Stages/PipelineStageBase.mqh
Include/PASR/Orchestration/Stages/DataSyncStage.mqh
Include/PASR/Orchestration/Stages/SignalStage.mqh
Include/PASR/Orchestration/Stages/RiskStage.mqh
Include/PASR/Core/PASR.mqh
```

## Compile checklist untuk user

Compile lokal di MetaEditor:

```text
Experts/PASR_MODULAR.mq5
```

Gunakan compile command tanpa:

```text
/inc:<MQL5>\Include
```

Karena baseline sebelumnya menunjukkan opsi `/inc` dapat membuat path salah seperti:

```text
MQL5\Include\Include\...
```

## Kalau compile error muncul

Prioritas fix:

1. error dari `PipelineStageBase.mqh`,
2. error dari inheritance `CDataSyncStage`, `CSignalStage`, `CRiskStage`,
3. error include order di `Core/PASR.mqh`,
4. baru setelah itu error lama di module trading/AI.

## Next safe step setelah compile hijau

Langkah berikut yang paling aman:

1. Tambahkan registry object stage secara opsional di `CPipelineStageRegistry` tanpa mengganti ID table lama.
2. Tambahkan satu extracted stage pertama untuk `DataSync` sebagai adapter non-invasive.
3. Jalankan `DataSync` object hanya jika flag eksperimen aktif.
4. Setelah compile dan runtime aman, baru pindahkan `SignalGen`, `RiskCheck`, dan `Execution`.
