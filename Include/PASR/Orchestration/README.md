# PASR Orchestration Layer

Folder ini adalah target pemisahan logic orchestration dari `Core/`.

## Peran

`Orchestration/` bertugas mengatur urutan kerja trading runtime:

```text
DataSync → Analysis → Pattern → Regime → Signal → AI → Risk → Execution → Position → Recovery → Dashboard → Journal
```

Layer ini hanya menentukan:

- stage apa yang dipanggil,
- urutan stage,
- kapan stage dilewati,
- kapan pipeline abort,
- bagaimana `PipelineContext` dibawa antar stage,
- bagaimana fallback dipakai.

Layer ini tidak boleh berisi logic domain seperti:

- hitung support/resistance,
- deteksi candlestick pattern,
- kalkulasi lot,
- kirim order,
- training AI.

## Hubungan dengan Central

```text
Central/CPASRKernel
        ↓ owns / boots
Orchestration/CPipelineEngine
        ↓ calls
Data, Analysis, Signal, AI, Trade, Infra modules
```

`Central/` menjawab **siapa module yang hidup**.

`Orchestration/` menjawab **kapan module dipanggil**.

## Status migrasi

Saat ini `CPipelineEngine` masih berada di:

```text
Include/PASR/Core/PipelineEngine.mqh
```

Folder ini disiapkan sebagai target akhir. Migrasi dilakukan bertahap agar compile lama tetap aman.

## Target akhir

```text
Include/PASR/Orchestration/
├── PipelineEngine.mqh
├── PipelineContext.mqh
├── PipelineResult.mqh
├── PipelineStage.mqh
└── Stages/
    ├── DataSyncStage.mqh
    ├── AnalysisSRStage.mqh
    ├── AnalysisZoneStage.mqh
    ├── PatternStage.mqh
    ├── RegimeStage.mqh
    ├── SignalStage.mqh
    ├── RiskStage.mqh
    ├── ExecutionStage.mqh
    ├── PositionStage.mqh
    ├── RecoveryStage.mqh
    ├── DashboardStage.mqh
    └── JournalStage.mqh
```

## Migration rule

Sampai semua stage dipisah, file lama di `Core/` tetap menjadi sumber implementasi runtime. File di `Orchestration/` boleh berupa adapter/wrapper dulu.
