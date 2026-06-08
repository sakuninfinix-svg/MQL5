# PASR Central Layer

Central layer adalah pusat kontrol untuk migrasi **Centralized Modular Pipeline Architecture**.

Tujuan folder ini bukan memindahkan semua logic trading ke satu tempat, tetapi memisahkan tanggung jawab pusat dari runtime lama sampai runtime canonical sepenuhnya dimiliki `CPASRKernel`. Compatibility runtime lama sudah dihapus lewat breaking cleanup.

## Prinsip

```text
centralized control, decentralized logic
```

Central layer hanya bertanggung jawab untuk:

1. registrasi module,
2. lifecycle init/deinit,
3. dependency lookup,
4. health summary,
5. config handoff,
6. pipeline bootstrap,
7. safe shutdown.

Central layer **tidak boleh** berisi logic:

- pattern recognition,
- support/resistance calculation,
- signal voting detail,
- AI inference detail,
- lot calculation,
- order execution,
- recovery strategy.

Logic domain tetap berada di folder domain:

```text
Data/
Analysis/
Signal/
AI/
Trade/
Infra/
QA/
```

## Target akhir

```text
Experts/PASR_MODULAR.mq5
        ↓
CPASRKernel
        ↓
CModuleRegistry + CServiceLocator + CLifecycleManager
        ↓
CPipelineEngine
        ↓
Data → Analysis → Signal → AI → Risk → Execution → Journal
```

## Migrasi bertahap

### Fase 1 — Non-breaking foundation ✅

- Tambahkan folder `Central/`.
- Tambahkan `CPASRKernel` sebagai facade baru.
- Tambahkan `CModuleRegistry` untuk daftar module.
- Tambahkan `CServiceLocator` untuk lookup manager.
- Tambahkan `CLifecycleManager` untuk init/deinit seragam.
- `Core/PASR.mqh` sudah menyertakan layer `Central/` sebagai canonical runtime facade.

### Fase 2 — Kernel entrypoint ✅

- `CPASRKernel` menjadi entrypoint runtime dari EA utama.
- `Experts/PASR_MODULAR.mq5` sudah memakai `CPASRKernel g_kernel` sebagai entry point.
- Runtime tick/event loop, trade transaction routing, dan pipeline timer sudah berjalan di kernel.

### Fase 3 — Extract responsibilities ⏳

Pindahkan bertahap dari runtime lama:

- allocation factory → `CModuleFactory` ✅,
- module registry ownership → `CModuleRegistry`,
- init/deinit order → `CLifecycleManager` ✅,
- dependency access → `CServiceLocator`,
- pipeline ownership → `CPASRKernel` ✅.

### Fase 4 — Split pipeline stages ⏳

Pecah `CPipelineEngine` menjadi stage file kecil di `Orchestration/Stages/`.

### Fase 5 — Clean master include ⏳

`Core/PASR.mqh` tetap menjadi master include, tetapi layer include menjadi:

```text
Core primitives
Domain types
Infra
Analysis
AI
Signal
Trade
Central
Orchestration
```

## Status

Fase 1 sampai Fase 6 sudah selesai secara struktural. Sistem sekarang memakai `CPASRKernel` sebagai facade pusat, dan allocation module utama/opsional sudah lewat `CModuleFactory`.

`CPASRKernel` sekarang memiliki bootstrap manager, lifecycle init/deinit, registry ownership, runtime tick/event loop, pipeline context preparation, execution retry drain, trade-transaction routing, dan `CPipelineEngine`. `AdaptiveParameterManager` juga sudah diaktifkan dari kernel karena bergantung pada kernel-owned `MarketRegimeDetector`.

Breaking cleanup sudah menghapus compatibility surface runtime lama. Caller lama harus migrasi ke `CPASRKernel`.

Current ownership/dependency status is tracked in `Central/DEPENDENCIES.md`.
