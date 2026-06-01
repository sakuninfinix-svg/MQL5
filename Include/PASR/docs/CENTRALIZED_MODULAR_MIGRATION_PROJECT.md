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

- `CBackendAdapter` masih memegang orchestration init order, tetapi allocation module utama sudah melewati `CModuleFactory`.
- `CBackendAdapter` masih memegang allocation/bootstrap code, `OnTick`, dan `OnTradeTransaction` backend, tetapi manager berbasis `IManager` didaftarkan sebagai owned di kernel registry.
- `CBackendAdapter.OnTimer()` sudah compatibility no-op; timer pipeline dijalankan oleh `CPASRKernel`.
- `CPipelineEngine` sudah berada di `Orchestration/PipelineEngine.mqh`; `Core/PipelineEngine.mqh` menjadi compatibility wrapper.
- `CBackendAdapter` menjadi backend canonical di `Central/BackendAdapter.mqh`; `COrchestrator` hanya compatibility wrapper di `Core/Orchestrator.mqh`.
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
- [ ] Tambahkan getter lain hanya jika benar-benar diperlukan.
- [ ] Hindari expose backend terlalu banyak.

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

Goal: init/deinit order pindah dari compatibility backend ke `CLifecycleManager`.

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
- Registry ownership jelas: manager berbasis `IManager` yang berhasil init dimiliki registry; non-`IManager` runtime services masih compatibility-owned oleh backend.

### Phase 4 — Dependency Access Cleanup

Goal: domain module tidak mencari dependency secara liar.

Checklist:

- [x] Semua nama module memakai `ModuleNames.mqh`.
- [x] `CServiceLocator` menjadi akses dependency typed.
- [ ] Kurangi penggunaan pointer lintas-domain langsung di pipeline.
- [x] Dokumentasikan dependency per module.

Checkpoint 2026-06-01:

- `ModuleNames.mqh` mencakup canonical names untuk manager utama, optional infra, dan runtime services non-`IManager`.
- `Central/DEPENDENCIES.md` mencatat owner saat ini, registry state, dan lifecycle path per module.
- Direct pointer injection di `CPipelineEngine::InjectManagers()` masih ada dan menjadi target Phase 4 lanjutan sebelum pipeline ownership dipindahkan.
- Pipeline ownership sudah pindah ke `CPASRKernel`; direct pointer injection masih ada sebagai adapter boundary dari backend manager provider ke kernel-owned pipeline.

Acceptance criteria:

- Tidak ada string literal nama module di central registry selain `ModuleNames.mqh`.
- Dependency injection lebih eksplisit.

### Phase 5 — Orchestration Split Preparation

Goal: mempersiapkan pemindahan pipeline tanpa mematahkan compile.

Checklist:

- [x] `Orchestration/README.md` dibuat.
- [x] `IPipelineStage` dibuat.
- [x] Buat wrapper/adaptor semua runtime stage utama tanpa mengubah runtime:
  - [x] `DataSyncStage.mqh`,
  - [x] `AnalysisSRStage.mqh`,
  - [x] `AnalysisZoneStage.mqh`,
  - [x] `PatternStage.mqh`,
  - [x] `RegimeStage.mqh`,
  - [x] `SignalStage.mqh`,
  - [x] `AIInferStage.mqh`,
  - [x] `RiskStage.mqh`,
  - [x] `AdaptiveParamsStage.mqh`,
  - [x] `ExecutionStage.mqh`,
  - [x] `PositionStage.mqh`,
  - [x] `RecoveryStage.mqh`,
  - [x] `DashboardStage.mqh`,
  - [x] `JournalStage.mqh`.
- [x] `CPipelineEngine` tetap sebagai sumber runtime sampai semua stage siap.
- [x] Delegasikan semua runtime stage utama dari `CPipelineEngine`:
  - [x] `DataSyncStage`,
  - [x] `AnalysisSRStage`,
  - [x] `AnalysisZoneStage`,
  - [x] `PatternStage`,
  - [x] `RegimeStage`,
  - [x] `SignalStage`,
  - [x] `AIInferStage`,
  - [x] `RiskStage`,
  - [x] `AdaptiveParamsStage`,
  - [x] `ExecutionStage`,
  - [x] `PositionStage`,
  - [x] `RecoveryStage`,
  - [x] `DashboardStage`,
  - [x] `JournalStage`.

Checkpoint 2026-06-01:

- Adapter stage awal dibuat di `Orchestration/Stages/`.
- `DataSyncStage`, `AnalysisSRStage`, `AnalysisZoneStage`, `PatternStage`, `RegimeStage`, `SignalStage`, `AIInferStage`, `RiskStage`, `AdaptiveParamsStage`, `ExecutionStage`, `PositionStage`, `RecoveryStage`, `DashboardStage`, dan `JournalStage` sudah menjadi runtime implementation yang dipanggil oleh `CPipelineEngine`.
- `Core/PASR.mqh` include adapter tersebut sebagai compile guard.
- MetaEditor compile: `PASR_MODULAR`, `PASR_Smoke`, dan `PASR_PipelineHarness_Smoke` sama-sama `Result: 0 errors, 0 warnings`.

Acceptance criteria:

- Stage interface bisa di-include tanpa error.
- Tidak ada circular include baru.

### Phase 6 — PipelineEngine Move

Goal: pindahkan implementasi pipeline dari `Core/` ke `Orchestration/`.

Checklist:

- [x] Buat `Include/PASR/Orchestration/PipelineEngine.mqh`.
- [x] Pindahkan `CPipelineEngine` secara utuh terlebih dahulu.
- [x] `Core/PipelineEngine.mqh` menjadi compatibility wrapper sementara.
- [x] Update `Core/PASR.mqh` include order.
- [x] Compile checkpoint.
- [x] Pecah semua runtime stage utama satu per satu.

Checkpoint 2026-06-01:

- `Stage_DataSync()` di `CPipelineEngine` sudah delegate ke `CDataSyncStage::Execute()`.
- `Stage_AnalysisSR()` di `CPipelineEngine` sudah delegate ke `CAnalysisSRStage::Execute()`.
- `Stage_AnalysisZone()` di `CPipelineEngine` sudah delegate ke `CAnalysisZoneStage::Execute()`.
- `Stage_PatternRec()` di `CPipelineEngine` sudah delegate ke `CPatternStage::Execute()`.
- `Stage_RegimeDet()` di `CPipelineEngine` sudah delegate ke `CRegimeStage::Execute()`.
- `Stage_SignalGen()` di `CPipelineEngine` sudah delegate ke `CSignalStage::Execute()`.
- `Stage_AIInfer()` di `CPipelineEngine` sudah delegate ke `CAIInferStage::Execute()`.
- `Stage_RiskCheck()` di `CPipelineEngine` sudah delegate ke `CRiskStage::Execute()`.
- `Stage_AdaptiveParams()` di `CPipelineEngine` sudah delegate ke `CAdaptiveParamsStage::Execute()`.
- `Stage_Execution()` di `CPipelineEngine` sudah delegate ke `CExecutionStage::Execute()`.
- `Stage_PosMgmt()` di `CPipelineEngine` sudah delegate ke `CPositionStage::Execute()`.
- `Stage_Recovery()` di `CPipelineEngine` sudah delegate ke `CRecoveryStage::Execute()`.
- `Stage_Dashboard()` di `CPipelineEngine` sudah delegate ke `CDashboardStage::Execute()`.
- `Stage_Journal()` di `CPipelineEngine` sudah delegate ke `CJournalStage::Execute()`.
- Behavior runtime dipertahankan: DataSync tetap update tick/price/ATR/session; AnalysisSR tetap dispatch event new-bar; AnalysisZone tetap menjalankan price/new-bar hooks; PatternRec tetap new-bar/profiling gate; RegimeDet tetap memilih `RegimeFilter` lalu fallback detector; SignalGen tetap menjalankan AI-primary plus rule fallback; AIInfer tetap mengisi health flag AI; RiskCheck tetap mengisi `ctx.risk_result`, `ctx.trading_allowed`, dan rejection message; Adaptive tetap hanya jalan saat new bar; Execution tetap build/execute `TradePlan` dan memanggil recovery hook saat trade open; PositionMgmt tetap filter magic number dan menutup posisi berdasarkan `ExitEngine`; Recovery tetap menjalankan price/new-bar hooks; Dashboard/Journal tetap menerima observability text terakhir.
- MetaEditor compile: `PASR_MODULAR`, `PASR_Smoke`, dan `PASR_PipelineHarness_Smoke` sama-sama `Result: 0 errors, 0 warnings`.

Checkpoint 2026-06-01:

- `CPipelineEngine` canonical implementation moved to `Include/PASR/Orchestration/PipelineEngine.mqh`.
- `Include/PASR/Core/PipelineEngine.mqh` is now a compatibility wrapper.
- `Core/PASR.mqh` includes the orchestration engine directly.
- `CPASRKernel` allocates, injects, executes, and deletes `CPipelineEngine`.
- `CBackendAdapter.OnTimer()` is a compatibility no-op.
- MetaEditor compile: `Result: 0 errors, 0 warnings`.

Acceptance criteria:

- Include lama tetap aman.
- Include baru menjadi canonical.
- Compile tidak memburuk dibanding baseline.

### Phase 7 — Documentation and Cleanup

Goal: hapus jejak arsitektur lama yang membingungkan.

Checklist:

- [ ] Update `README_PASR.md`.
- [x] Update `Include/PASR/README.md`.
- [x] Update `Include/PASR/Central/README.md`.
- [x] Update `Include/PASR/Orchestration/README.md`.
- [x] Tandai file compatibility backend.
- [ ] Hapus komentar yang menyebut pure pipeline sebagai arsitektur aktif.

Acceptance criteria:

- Dokumentasi tidak saling bertentangan.
- Quick start memakai `CPASRKernel`.

## Work Rules

1. Jangan pindahkan lebih dari satu tanggung jawab besar dalam satu batch.
2. Setelah setiap batch, lakukan compile checkpoint.
3. Kalau compile error muncul, fix error dari batch terakhir dulu.
4. Jangan mengubah logic trading saat migrasi arsitektur.
5. Jangan ubah AI/training/risk formula sampai arsitektur stabil.
6. Semua file baru harus punya header versi.
7. Semua compatibility adapter harus diberi komentar jelas.
8. Hindari circular include.
9. Prefer facade/wrapper sebelum move fisik file besar.
10. Jika ragu, dokumentasikan TODO daripada memaksa rewrite.

## Definition of Done

Migrasi dianggap selesai jika:

- `Experts/PASR_MODULAR.mq5` memakai `CPASRKernel` secara penuh.
- `CPASRKernel` tidak lagi hanya wrapper pasif, tetapi mengelola registry/lifecycle/pipeline ownership.
- `COrchestrator` lama sudah menjadi compatibility wrapper; backend canonical adalah `CBackendAdapter`.
- `CPipelineEngine` berada di `Orchestration/`.
- `Core/` hanya berisi primitive, event, interfaces, common types, dan master include.
- Compile bersih atau hanya menyisakan issue lama yang terdokumentasi.
- README utama dan docs konsisten.

## Recovery Plan

Jika migrasi menyebabkan compile rusak berat:

1. Jangan lanjut refactor.
2. Bandingkan commit terakhir yang compile.
3. Revert batch terakhir saja.
4. Buat issue khusus dengan log error compiler.
5. Pecah batch menjadi perubahan lebih kecil.

## Project Issue Index

Master issue dan phase issue dibuat di GitHub agar progress bisa dilacak dari luar chat.
