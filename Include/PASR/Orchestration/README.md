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

Saat ini implementasi canonical `CPipelineEngine` berada di:

```text
Include/PASR/Orchestration/PipelineEngine.mqh
```

Include lama tetap aman melalui compatibility wrapper:

```text
Include/PASR/Core/PipelineEngine.mqh
```

Migrasi dilakukan bertahap agar compile lama tetap aman.

Semua runtime stage utama sudah tersedia dan di-include oleh master include:

```text
Include/PASR/Orchestration/Stages/DataSyncStage.mqh
Include/PASR/Orchestration/Stages/AnalysisSRStage.mqh
Include/PASR/Orchestration/Stages/AnalysisZoneStage.mqh
Include/PASR/Orchestration/Stages/PatternStage.mqh
Include/PASR/Orchestration/Stages/RegimeStage.mqh
Include/PASR/Orchestration/Stages/SignalStage.mqh
Include/PASR/Orchestration/Stages/AIInferStage.mqh
Include/PASR/Orchestration/Stages/RiskStage.mqh
Include/PASR/Orchestration/Stages/AdaptiveParamsStage.mqh
Include/PASR/Orchestration/Stages/ExecutionStage.mqh
Include/PASR/Orchestration/Stages/PositionStage.mqh
Include/PASR/Orchestration/Stages/RecoveryStage.mqh
Include/PASR/Orchestration/Stages/DashboardStage.mqh
Include/PASR/Orchestration/Stages/JournalStage.mqh
```

`DataSyncStage`, `AnalysisSRStage`, `AnalysisZoneStage`, `PatternStage`, `RegimeStage`, `SignalStage`, `AIInferStage`, `RiskStage`, `AdaptiveParamsStage`, `ExecutionStage`, `PositionStage`, `RecoveryStage`, `DashboardStage`, dan `JournalStage` sudah dipakai runtime melalui `CPipelineEngine` delegation.
`CPipelineEngine` sekarang berperan sebagai dispatcher, registry runner, health/session gate, dan publisher observability; logic per-stage berada di file stage masing-masing.

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
    ├── AIInferStage.mqh
    ├── RiskStage.mqh
    ├── AdaptiveParamsStage.mqh
    ├── ExecutionStage.mqh
    ├── PositionStage.mqh
    ├── RecoveryStage.mqh
    ├── DashboardStage.mqh
    └── JournalStage.mqh
```

## Migration rule

`CPipelineEngine` tetap menjaga urutan pipeline, fallback behavior, abort policy, stage registry, dan observability.
Perubahan behavior domain harus dilakukan di module domain atau file stage terkait, bukan dengan mengembalikan logic besar ke engine.
