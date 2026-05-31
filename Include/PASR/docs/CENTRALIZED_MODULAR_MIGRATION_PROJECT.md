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
- `ModuleNames.mqh` dibuat sebagai canonical module names.
- `Experts/PASR_MODULAR.mq5` sudah memakai `CPASRKernel g_kernel`.
- `Orchestration/` dibuat.
- `IPipelineStage` dibuat sebagai target interface split-stage.
- `Core/PASR.mqh` sudah include `Central/` dan `Orchestration/` secara resmi.

Masih compatibility backend:

- `COrchestrator` masih memegang allocation manager.
- `COrchestrator` masih memegang `OnTick`, `OnTimer`, `OnTradeTransaction` backend.
- `CPipelineEngine` masih berada di `Core/PipelineEngine.mqh`.
- `OrchestratorInit.mqh` masih menjadi bootstrap utama manager.

## Migration Phases

### Phase 0 — Compile Baseline

Goal: memastikan kondisi setelah `CPASRKernel` adoption diketahui jelas.

Checklist:

- [ ] Compile `Experts/PASR_MODULAR.mq5` di MetaEditor.
- [ ] Catat semua error compiler apa adanya.
- [ ] Pisahkan error menjadi kategori:
  - [ ] include order,
  - [ ] unknown class/type,
  - [ ] enum/macro conflict,
  - [ ] missing method,
  - [ ] legacy compile blocker,
  - [ ] new Central migration blocker.
- [ ] Fix hanya error yang muncul dari `Central/` dan `Orchestration/` dulu.
- [ ] Jangan pindahkan `PipelineEngine` sebelum phase ini hijau.

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

- [ ] Buat `CModuleFactory`.
- [ ] Pindahkan allocation sederhana satu per satu:
  - [ ] `CEventBus`,
  - [ ] `CDataManager`,
  - [ ] `CAnalysisSRManager`,
  - [ ] `CAnalysisZoneManager`,
  - [ ] `CPatternManager`,
  - [ ] `CSignalManager`,
  - [ ] `CRiskManager`,
  - [ ] `CExecutionManager`,
  - [ ] `CExitEngine`.
- [ ] Module opsional tetap boleh gagal tanpa mematikan EA:
  - [ ] `CRegimeFilter`,
  - [ ] `CAIOrchestrator`,
  - [ ] `CJournalManager`,
  - [ ] `CDashboardManager`.
- [ ] Setelah setiap 2–3 module dipindah, compile checkpoint.

Acceptance criteria:

- Allocation manager punya satu tempat resmi.
- `OrchestratorInit.mqh` mulai mengecil.
- Tidak ada perubahan logic trading.

### Phase 3 — Lifecycle Extraction

Goal: init/deinit order pindah dari `COrchestrator` ke `CLifecycleManager`.

Checklist:

- [ ] `CLifecycleManager` mengelola init order.
- [ ] `CLifecycleManager` mengelola deinit reverse order.
- [ ] `EventBus.Register()` dipanggil dari lifecycle manager.
- [ ] Debug mode diteruskan dari kernel ke module.
- [ ] Failure policy ditulis jelas:
  - [ ] critical module fail = `INIT_FAILED`,
  - [ ] optional module fail = warning + continue.

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
- Registry ownership jelas: owned atau borrowed.

### Phase 4 — Dependency Access Cleanup

Goal: domain module tidak mencari dependency secara liar.

Checklist:

- [ ] Semua nama module memakai `ModuleNames.mqh`.
- [ ] `CServiceLocator` menjadi akses dependency typed.
- [ ] Kurangi penggunaan pointer lintas-domain langsung di pipeline.
- [ ] Dokumentasikan dependency per module.

Acceptance criteria:

- Tidak ada string literal nama module di central registry selain `ModuleNames.mqh`.
- Dependency injection lebih eksplisit.

### Phase 5 — Orchestration Split Preparation

Goal: mempersiapkan pemindahan pipeline tanpa mematahkan compile.

Checklist:

- [x] `Orchestration/README.md` dibuat.
- [x] `IPipelineStage` dibuat.
- [ ] Buat wrapper/adaptor stage pertama tanpa mengubah runtime:
  - [ ] `DataSyncStage.mqh`,
  - [ ] `SignalStage.mqh`,
  - [ ] `RiskStage.mqh`.
- [ ] `CPipelineEngine` tetap sebagai sumber runtime sampai semua stage siap.

Acceptance criteria:

- Stage interface bisa di-include tanpa error.
- Tidak ada circular include baru.

### Phase 6 — PipelineEngine Move

Goal: pindahkan implementasi pipeline dari `Core/` ke `Orchestration/`.

Checklist:

- [ ] Buat `Include/PASR/Orchestration/PipelineEngine.mqh`.
- [ ] Pindahkan `CPipelineEngine` secara utuh terlebih dahulu.
- [ ] `Core/PipelineEngine.mqh` menjadi compatibility wrapper sementara.
- [ ] Update `Core/PASR.mqh` include order.
- [ ] Compile checkpoint.
- [ ] Baru pecah stage satu per satu.

Acceptance criteria:

- Include lama tetap aman.
- Include baru menjadi canonical.
- Compile tidak memburuk dibanding baseline.

### Phase 7 — Documentation and Cleanup

Goal: hapus jejak arsitektur lama yang membingungkan.

Checklist:

- [ ] Update `README_PASR.md`.
- [ ] Update `Include/PASR/README.md`.
- [ ] Update `Include/PASR/Central/README.md`.
- [ ] Update `Include/PASR/Orchestration/README.md`.
- [ ] Tandai file compatibility backend.
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
- `COrchestrator` lama sudah menjadi adapter kecil atau dihapus.
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
