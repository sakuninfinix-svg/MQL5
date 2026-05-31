# PASR Central Layer

Central layer adalah pusat kontrol untuk migrasi **Centralized Modular Pipeline Architecture**.

Tujuan folder ini bukan memindahkan semua logic trading ke satu tempat, tetapi memisahkan tanggung jawab pusat dari `Core/Orchestrator.mqh` yang saat ini masih memegang lifecycle, dependency, event routing, dan pipeline bootstrap sekaligus.

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
- `Core/PASR.mqh` sudah menyertakan layer `Central/` setelah backend legacy.

### Fase 2 — Adapter ke orchestrator lama ✅

- `CPASRKernel` menjalankan `COrchestrator` lama sebagai backend.
- `Experts/PASR_MODULAR.mq5` sudah memakai `CPASRKernel g_kernel` sebagai entry point.
- Runtime behavior masih didelegasikan ke orchestrator lama agar migrasi tetap aman.

### Fase 3 — Extract responsibilities ⏳

Pindahkan bertahap dari `Core/Orchestrator.mqh`:

- allocation manager → `CModuleRegistry`,
- init/deinit order → `CLifecycleManager`,
- dependency access → `CServiceLocator`,
- pipeline ownership → `CPASRKernel`.

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
Compatibility adapters
```

## Status

Fase 1 dan Fase 2 sudah selesai secara struktural. Sistem sekarang memakai `CPASRKernel` sebagai facade pusat, tetapi manager allocation dan pipeline execution masih berada di backend `COrchestrator` lama.

Langkah berikutnya adalah mengekstrak allocation dan lifecycle manager dari `Core/OrchestratorInit.mqh` ke `Central/` secara bertahap.
