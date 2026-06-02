# Centralized Modular Pipeline Migration Project

Dokumen ini adalah catatan migrasi resmi untuk runtime **Centralized Modular Pipeline Architecture**.

## Tujuan

Migrasi PASR dari runtime lama menuju:

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

Breaking cleanup:

- `CPASRKernel` sekarang memiliki manager bootstrap, lifecycle, registry ownership, runtime tick/event loop, dan trade transaction routing.
- Compatibility surface runtime lama sudah dihapus.
- Allocation module utama dan opsional sudah melewati `CModuleFactory`, dan manager berbasis `IManager` didaftarkan sebagai owned di kernel registry.
- `AdaptiveParameterManager` sudah diaktifkan oleh `CPASRKernel` dan di-bind ke kernel-owned `MarketRegimeDetector`.
- `CPipelineEngine` sudah berada di `Orchestration/PipelineEngine.mqh`; `Core/PipelineEngine.mqh` menjadi compatibility wrapper.
- Caller runtime canonical harus memakai `CPASRKernel`.

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
- [x] EA utama memakai `g_kernel` sebagai runtime object.
- [x] QA helper memakai getter dari `g_kernel`.
- [x] Dashboard chart event memakai `g_kernel.GetDashboard()`.
- [x] Tambahkan getter lain hanya jika benar-benar diperlukan.
- [x] Hindari expose runtime internals terlalu banyak.

Acceptance criteria:

- `Experts/PASR_MODULAR.mq5` tidak memakai global runtime object lama.
- Semua event handler EA delegate ke `g_kernel`.

### Phase 2 — Module Factory Extraction

Goal: allocation manager tidak lagi tertanam penuh di runtime lama.

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

- Allocation module utama dan opsional sekarang dijalankan langsung oleh `CPASRKernel` melalui `CModuleFactory`.
- Compatibility bootstrap runtime lama sudah dihapus lewat breaking cleanup.
- Manager berbasis `IManager` yang berhasil init didaftarkan langsung ke `CPASRKernel` registry dengan `owned=true`.
- Optional manager bootstrap di kernel memakai helper `InitOptionalManager()` agar warning/continue dan registry-bind policy konsisten.
- Runtime init order dan failure policy dipertahankan.
- MetaEditor compile: `Result: 0 errors, 0 warnings`.

Acceptance criteria:

- Allocation manager punya satu tempat resmi.
- Allocation manager punya satu tempat resmi.
- Tidak ada perubahan logic trading.

### Phase 3 — Lifecycle Extraction

Goal: init/deinit order pindah ke `CLifecycleManager`.

Checklist:

- [x] `CLifecycleManager` mengelola init order.
- [x] `CLifecycleManager` mengelola deinit reverse order.
- [x] `EventBus.Register()` dipanggil dari lifecycle manager.
- [x] Debug mode diteruskan dari kernel ke module.
- [x] Failure policy ditulis jelas:
  - [x] critical module fail = `INIT_FAILED`,
  - [x] optional module fail = warning + continue.

Checkpoint 2026-06-01:

- `CPASRKernel` memakai `CLifecycleManager::InitCritical()` untuk module critical.
- Optional modules memakai `CLifecycleManager::InitOptional()` dan tetap warning + continue.
- `CPASRKernel::Shutdown()` melepas signal source non-`IManager`, lalu registry `Clear(true)` menjadi pemilik shutdown manager.
- Compatibility wrapper runtime lama sudah dihapus lewat breaking cleanup.
- `CMarketRegimeDetector` sekarang dimiliki `CPASRKernel` karena bukan turunan `IManager`.
- `AdaptiveParameterManager` sekarang dimiliki `CPASRKernel` registry karena lifecycle-nya bergantung pada `MarketRegimeDetector` milik kernel.
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
AdaptiveParameterManager
HealthMonitor
QA helpers
```

Acceptance criteria:

- Deinit order selalu reverse dari init order.
- Tidak ada double-delete.
- Registry ownership jelas: manager berbasis `IManager` yang berhasil init dimiliki registry; `EventBus`, `MarketRegimeDetector`, dan signal source non-`IManager` dimiliki kernel.

### Phase 4 — Dependency Access Cleanup

Goal: domain module tidak mencari dependency secara liar.

Checklist:

- [x] Semua nama module memakai `ModuleNames.mqh`.
- [x] `CServiceLocator` menjadi akses dependency typed.
- [x] Kurangi penggunaan pointer lintas-domain langsung di pipeline bootstrap.
- [x] Ganti `CPipelineEngine::InjectManagers()` pointer bundle dengan `SPipelineDependencies`.
- [x] Dokumentasikan dependency per module.

Checkpoint 2026-06-02:

- `ModuleNames.mqh` mencakup canonical names untuk manager utama, optional infra, dan runtime services non-`IManager`.
- `Central/DEPENDENCIES.md` mencatat owner saat ini, registry state, dan lifecycle path per module.
- Pipeline ownership sudah pindah ke `CPASRKernel`.
- `CPASRKernel::InitPipeline()` mengambil manager berbasis `IManager` dari `CServiceLocator`, bukan dari getter runtime lama.
- `CPipelineEngine::InjectManagers()` diganti oleh `CPipelineEngine::InjectDependencies(const SPipelineDependencies&)`.
- `SPipelineDependencies` menjadi satu boundary eksplisit untuk dependency stage runtime.
- `SPipelineDependencies` sudah dipersempit ke dependency yang benar-benar dipakai stage/observability; health/session context tetap disiapkan sebelum pipeline lewat kernel context preparation.
- `EventBus` sudah dimiliki `CPASRKernel` dan dipakai langsung oleh lifecycle/pipeline.
- `MarketRegimeDetector` fallback sudah dimiliki `CPASRKernel` dan masuk ke pipeline melalui `SPipelineDependencies`.
- `AdaptiveParameterManager` sudah dimiliki `CPASRKernel` registry, diinisialisasi setelah core services, lalu masuk ke pipeline melalui `CServiceLocator`.
- `RecoveryManager` sudah diaktifkan sebagai optional `IManager`, registry-owned, dan dipakai oleh `ExecutionStage`/`RecoveryStage` saat tersedia.
- `SanityManager`, `HealthMonitor`, `SessionState`, dan `TelemetryRecorder` sudah diaktifkan sebagai optional `IManager` dan registry-owned.
- `SessionState` menerima magic number sebelum init agar Global Variables memakai namespace EA yang benar sejak bootstrap.
- Pipeline context sekarang bisa menerima health/session metrics saat optional infra tersebut berhasil init.
- Pipeline observability telemetry aktif saat `TelemetryRecorder` berhasil init.
- Runtime tick/event loop, price update dispatch, pipeline context preparation, event drain, execution retry queue, dan trade transaction routing sekarang dimiliki `CPASRKernel`.
- Manager bootstrap sekarang dimiliki `CPASRKernel`; compatibility surface runtime lama sudah dihapus.

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
- Compatibility adapter runtime lama sudah dihapus.
- MetaEditor compile: `Result: 0 errors, 0 warnings`.

Acceptance criteria:

- Include lama tetap aman.
- Include baru menjadi canonical.
- Compile tidak memburuk dibanding baseline.

### Phase 7 — Documentation and Cleanup

Goal: hapus jejak arsitektur lama yang membingungkan.

Checklist:

- [x] Update `README_PASR.md`.
- [x] Update `Include/PASR/README.md`.
- [x] Update `Include/PASR/Central/README.md`.
- [x] Update `Include/PASR/Orchestration/README.md`.
- [x] Hapus file compatibility runtime lama lewat breaking cleanup.
- [x] Hapus komentar yang menyebut pure pipeline sebagai arsitektur aktif.

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
- Compatibility wrapper lama sudah dihapus; canonical runtime adalah `CPASRKernel`.
- `CPipelineEngine` berada di `Orchestration/`.
- Canonical `Core/PASR.mqh` hanya membawa core primitives, domain modules, orchestration, dan Central facade; compatibility wrappers tidak berada di canonical runtime path.
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
