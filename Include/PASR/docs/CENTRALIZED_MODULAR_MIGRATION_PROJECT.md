# Centralized Modular Pipeline Migration Project

Dokumen ini adalah project plan resmi untuk menjaga migrasi PASR tidak putus di tengah jalan.

## Tujuan

Migrasi PASR dari arsitektur pipeline/orchestrator lama menuju:

```text
Centralized Modular Pipeline Architecture
```

Prinsip utama:

```text
centralized control, decentralized logic
```

Artinya `Central/` mengatur lifecycle, registry, dependency, dan bootstrap; sedangkan logic trading tetap berada di folder domain: `Data/`, `Analysis/`, `Signal/`, `AI/`, `Trade/`, `Infra/`, `QA/`.

## Non-goals

Migrasi ini tidak bertujuan untuk:

- rewrite seluruh EA dari nol,
- memindahkan semua logic ke satu God Object,
- membuat AI langsung mengirim order,
- mengubah strategi entry/exit sebelum compile stabil,
- memindahkan `CPipelineEngine` sebelum include order stabil.

## Current State

Sudah selesai:

- `Central/` dibuat.
- `CPASRKernel` dibuat sebagai facade pusat.
- `CModuleRegistry` dibuat.
- `CServiceLocator` dibuat.
- `CLifecycleManager` dibuat sebagai skeleton.
- `CModuleFactory` dibuat sebagai titik allocation resmi tahap awal.
- `ModuleNames.mqh` dibuat sebagai canonical module names.
- `Experts/PASR_MODULAR.mq5` sudah memakai `CPASRKernel g_kernel`.
- `CPASRKernel` sudah memiliki dan menjalankan `CPipelineEngine`.
- `CPASRKernel` registry sudah menjadi owner lifetime untuk manager berbasis `IManager`.
- `Orchestration/` dibuat.
- `IPipelineStage` dibuat sebagai target interface split-stage.
- `Core/PASR.mqh` sudah include `Central/` dan `Orchestration/` secara resmi.

Masih compatibility backend:

- `COrchestrator` masih compatibility wrapper di `Core/Orchestrator.mqh`.
- `CBackendAdapter` masih memegang allocation/bootstrap code, `OnTick`, dan `OnTradeTransaction` backend.
- Manager berbasis `IManager` didaftarkan sebagai owned di kernel registry.
- `CBackendAdapter.OnTimer()` sudah compatibility no-op; timer pipeline dijalankan oleh `CPASRKernel`.
- `CPipelineEngine` sudah berada di `Orchestration/PipelineEngine.mqh`; `Core/PipelineEngine.mqh` menjadi compatibility wrapper.
- `CBackendAdapter` menjadi backend canonical di `Central/BackendAdapter.mqh`.
- `Central/BackendAdapterInit.mqh` masih menjadi bootstrap utama manager.

## Migration Phases

### Phase 0 — Compile Baseline

Goal: memastikan kondisi setelah `CPASRKernel` adoption diketahui jelas.

Checklist:

- [x] Compile `Experts/PASR_MODULAR.mq5` di MetaEditor.
- [x] Catat semua error compiler apa adanya.
- [x] Pisahkan error menjadi kategori:
  - [x] include order,
  - [x] unknown class/type,
  - [x] enum/macro conflict,
  - [x] missing method,
  - [x] legacy compile blocker,
  - [x] new Central migration blocker.
- [x] Fix hanya error yang muncul dari `Central/` dan `Orchestration/` dulu.
- [x] Jangan pindahkan `PipelineEngine` sebelum phase ini hijau.

Checkpoint 2026-06-01:

- MetaEditor compile command tanpa `/inc` menghasilkan `Result: 0 errors, 0 warnings`.
- Command dengan `/inc:<MQL5>\Include` menghasilkan false positive include path `MQL5\Include\Include\...`; gunakan compile command tanpa `/inc` untuk baseline.

Acceptance criteria:

- `PASR_MODULAR.mq5` minimal sampai error lama yang sudah diketahui, atau compile bersih.
- Tidak ada error baru yang berasal dari `CPASRKernel`, `ModuleNames`, `ModuleRegistry`, `ServiceLocator`, atau `PipelineStage`.

### Phase 1 — Central Facade Hardening

Goal: kernel menjadi facade yang stabil untuk semua akses dari EA utama.

Checklist:

- [x] `CPASRKernel` memiliki `Init`, `OnTick`, `OnTimer`, `OnTradeTransaction`, `OnDeinit`.
- [x] EA utama memakai `g_kernel`, bukan `g_orch`.
- [x] QA helper memakai getter dari `g_kernel`.
- [x] Dashboard chart event memakai `g_kernel.GetDashboard()`.
- [x] Tambahkan getter lain hanya jika benar-benar diperlukan.
- [x] Hindari expose backend terlalu banyak.

Acceptance criteria:

- `Experts/PASR_MODULAR.mq5` tidak memakai global `COrchestrator g_orch`.
- Semua event handler EA delegate ke `g_kernel`.

### Phase 2 — Module Factory Extraction

Goal: allocation manager tidak lagi tertanam penuh di `OrchestratorInit.mqh`.

Target file baru:

```text
Include/PASR/Central/ModuleFactory.mqh
```

Checklist:

- [x] Buat `CModuleFactory`.
- [x] Pindahkan allocation sederhana satu per satu:
  - [x] `CEventBus`,
  - [x] `CDataManager`,
  - [x] `CAnalysisSRManager`,
  - [x] `CAnalysisZoneManager`,
  - [x] `CPatternManager`,
  - [x] `CSignalManager`,
  - [x] `CRiskManager`,
  - [x] `CExecutionManager`,
  - [x] `CExitEngine`.
- [x] Module opsional tetap boleh gagal tanpa mematikan EA:
  - [x] `CRegimeFilter`,
  - [x] `CAIOrchestrator`,
  - [x] `CJournalManager`,
  - [x] `CDashboardManager`.
- [x] Setelah setiap 2–3 module dipindah, compile checkpoint.

Checkpoint 2026-06-01:

- Allocation di `Central/BackendAdapterInit.mqh` untuk module utama dan opsional sudah melalui `Central/CModuleFactory`.
- Canonical backend init sudah pindah ke `Central/BackendAdapterInit.mqh`; `Core/OrchestratorInit.mqh` hanya wrapper.
- Manager berbasis `IManager` yang berhasil init didaftarkan ke `CPASRKernel` registry dengan `owned=true`.
- Runtime init order dan failure policy belum diubah.
- MetaEditor compile: `Result: 0 errors, 0 warnings`.

Acceptance criteria:

- Allocation manager punya satu tempat resmi.
- `OrchestratorInit.mqh` mulai mengecil.
- Tidak ada perubahan logic trading.

### Phase 3 — Lifecycle Extraction

Goal: init/deinit order pindah dari `COrchestrator` ke `CLifecycleManager`.

Checklist:

- [x] `CLifecycleManager` mengelola init order.
- [x] `CLifecycleManager` mengelola deinit reverse order.
- [x] `EventBus.Register()` dipanggil dari lifecycle manager.
- [x] Debug mode diteruskan dari kernel ke module.
- [x] Failure policy ditulis jelas:
  - [x] critical module fail = `INIT_FAILED`,
  - [x] optional module fail = warning + continue.

Checkpoint 2026-06-01:

- `Central/BackendAdapterInit.mqh` memakai `CLifecycleManager::InitCritical()` untuk module critical.
- Optional modules memakai `CLifecycleManager::InitOptional()` dan tetap warning + continue.
- `Central/BackendAdapter.mqh::FreeAll()` memakai `CLifecycleManager::DeinitOne()` untuk manager berbasis `IManager` dalam urutan reverse yang sudah ada.
- Canonical backend adapter berada di `Central/BackendAdapter.mqh`; `Core/Orchestrator.mqh` hanya wrapper `COrchestrator : CBackendAdapter`.
- Saat kernel registry menjadi owner manager, backend tidak melakukan delete manager untuk mencegah double-delete; registry `Clear(true)` menjadi pemilik shutdown manager.
- `CMarketRegimeDetector` tetap deinit langsung karena bukan turunan `IManager`.
- MetaEditor compile: `Result: 0 errors, 0 warnings`.

Critical modules:

```text
EventBus
DataManager
SRManager
ZoneManager
PatternManager
SignalManager
RiskManager
ExecutionManager
ExitEngine
PipelineEngine
```

Optional modules:

```text
RegimeFilter
AIOrchestrator
JournalManager
DashboardManager
TelemetryRecorder
SnapshotManager
HealthMonitor
QA helpers
```

Acceptance criteria:

- Deinit order selalu reverse dari init order.
- Tidak ada double-delete.
- Registry ownership jelas: owned atau borrowed. *(Masih compatibility: kernel registry mem-bind backend services sebagai borrowed, backend orchestrator masih pemilik object.)*

### Phase 4 — Dependency Access Cleanup

Goal: domain module tidak mencari dependency secara liar.

Checklist:

- [x] Semua nama module memakai `ModuleNames.mqh`.
- [x] `CServiceLocator` menjadi akses dependency typed.
- [x] Kurangi penggunaan pointer lintas-domain langsung di pipeline.
- [x] Dokumentasikan dependency per module.

Checkpoint 2026-06-01:

- `CPASRKernel::InitPipeline()` sekarang melakukan injection manager ke `CPipelineEngine` melalui `CServiceLocator` untuk dependency yang sudah tercatat di registry.
- Akses langsung ke `CBackendAdapter` tetap dipakai hanya untuk compatibility-only services yang belum menjadi entry `IManager`, yaitu `EventBus` dan `CMarketRegimeDetector`.
- `CPipelineEngine` tetap menerima pointer eksplisit via `InjectManagers()` agar logic trading tidak berubah.
- Tidak ada perubahan strategi entry, risk, execution, maupun exit.

Acceptance criteria:

- Pipeline tidak lagi bergantung pada getter backend untuk semua manager utama.
- Dependency utama yang registry-owned dibaca melalui typed locator: Data, SR, Zone, Pattern, Signal, AI, RegimeFilter, Risk, Execution, Recovery, Dashboard, Journal, Sanity, Telemetry, Adaptive, Health, Snapshot, Exit.
- Legacy compatibility masih dijaga agar compile baseline tidak pecah.

## Audit 2026-06-01

### Ringkasan audit

Status migrasi: **Phase 0–4 selesai secara kode dan dokumentasi**, dengan backend compatibility masih dipertahankan supaya EA tidak perlu rewrite besar.

### Keputusan arsitektur

- `CPASRKernel` tetap menjadi facade utama EA.
- `CBackendAdapter` tetap menjadi jembatan sementara untuk bootstrap dan event compatibility.
- `CModuleRegistry` menjadi owner manager berbasis `IManager` saat kernel mengaktifkan `BindOwnerRegistry(&m_registry, true)`.
- `CServiceLocator` menjadi jalur dependency typed untuk pipeline.
- `CPipelineEngine` tetap berada di `Orchestration/` dan tetap di-inject eksplisit agar behavior trading tidak berubah.

### Risiko yang sudah ditahan

- Double-delete manager utama dicegah oleh pola `m_registry_owns_managers` di backend free path.
- Optional module failure tetap tidak mematikan EA.
- Pipeline ownership dipisahkan dari manager ownership: pipeline hanya consumer pointer, registry/backend yang mengatur lifetime.

### Sisa pekerjaan yang sengaja tidak disentuh

- Split setiap stage pipeline menjadi class `IPipelineStage` mandiri.
- Memindahkan `EventBus` ke registry owner model.
- Memindahkan `CMarketRegimeDetector` menjadi `IManager` atau wrapper registry-compatible.
- Refactor AI model/inference lebih dalam.
- Menambahkan workflow CI MetaEditor otomatis; compile tetap perlu dijalankan lokal di MetaEditor.

## Next Phase — Phase 5 Split Stage Extraction

Target berikutnya:

- Ubah method internal seperti `Stage_DataSync`, `Stage_SignalGen`, `Stage_RiskCheck`, dan `Stage_Execution` menjadi class stage mandiri.
- `CPipelineStageRegistry` tidak hanya menyimpan ID, tapi juga object stage.
- Setiap stage menerima `CServiceLocator` atau context dependency yang jelas.
- Acceptance criteria: `CPipelineEngine` mengecil menjadi executor, bukan tempat semua logic stage.
