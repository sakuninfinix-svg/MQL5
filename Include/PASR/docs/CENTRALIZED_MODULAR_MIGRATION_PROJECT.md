# Project Charter: Centralized Modular Pipeline Migration

Dokumen ini mencatat transformasi arsitektur PASR dari model monolitik/legacy menuju **Centralized Modular Pipeline Architecture**.

## 1. Visi Arsitektur

**Centralized Control, Decentralized Logic**

- **Central (Kernel):** Mengatur lifecycle, registrasi module, dependency lookup, bootstrap, runtime tick/timer, dan trade transaction routing.
- **Domain (Logic):** Tempat strategi trading hidup: Analysis, Signal, AI, Trade, dan Infra.
- **Orchestration (Pipeline):** Mengatur urutan eksekusi stage tanpa mencampuri logika strategi.

---

## 2. Status Migrasi (Executive Summary)

| Fase | Deskripsi | Status | Catatan |
| :--- | :--- | :--- | :--- |
| **0** | Baseline & Compile Check | DONE | Compile bersih pada `PASR_MODULAR.mq5`. |
| **1** | Central Facade (Kernel) | DONE | `CPASRKernel` menjadi entry point utama. |
| **2** | Module Factory | DONE | Alokasi manager dipusatkan di `CModuleFactory`. |
| **3** | Lifecycle Extraction | DONE | Init/Deinit diatur oleh `CLifecycleManager`. |
| **4** | Dependency Injection | DONE | Penggunaan `CServiceLocator` dan `SPipelineDependencies`. |
| **5** | Orchestration Split | DONE | Pipeline didelegasikan ke stage individual. |
| **6** | PipelineEngine Move | DONE | Engine canonical berada di folder `Orchestration/`. |
| **7** | Cleanup & Documentation | DONE | Runtime compatibility lama sudah dibersihkan. |
| **8** | Final Hardening | DONE | Lifecycle, stage contract, factory boundary, Data include graph, dan Pattern context cleanup sudah sinkron. |

---

## 3. Riwayat Fase Migrasi

### Fase 0 - 3: Fondasi Central

- Pembuatan `CPASRKernel`, `CModuleRegistry`, dan `CServiceLocator`.
- EA tidak lagi bergantung pada variabel global runtime yang tersebar.
- Lifecycle manager menjamin deinit dilakukan dengan urutan terbalik dari init.

### Fase 4 - 6: Pipeline & Orchestration

- `CPipelineEngine` dipecah menjadi stage terpisah (`DataSyncStage` hingga `JournalStage`).
- Logika urutan eksekusi terisolasi dari logika bisnis.
- `SPipelineDependencies` memastikan stage hanya menerima dependency yang dibutuhkan.

### Fase 7: Breaking Cleanup

- Surface area runtime lama dihapus.
- Master include `PASR.mqh` hanya memuat layer arsitektur baru.

### Fase 8: Final Hardening

- `CLifecycleManager.mqh` dinaikkan dari skeleton menjadi lifecycle tracker dengan duplicate-init guard, `LastError()`, `InitializedCount()`, dan reset state.
- `PipelineStage.mqh` dinaikkan dari skeleton menjadi interface dengan kontrak default untuk enable/debug/profiling/readiness/error/elapsed/reset.
- `Data/RegimeTypes.mqh`, `Data/SRStruct.mqh`, dan `Data/SymbolScanner.mqh` sudah berada di master include graph pada layer yang sesuai.
- Duplicate `PatternContext.mqh` tidak ada lagi di folder `Analysis/Pattern/`; folder Pattern canonical hanya berisi `PatternManager.mqh`, `PatternTypes.mqh`, dan README.
- Manager dan signal source runtime dibuat melalui `CModuleFactory`; Kernel tidak lagi membuat source signal dengan `new` langsung.

---

## 4. Definition of Done

Migrasi centralized modular lokal dianggap selesai jika:

1. `LifecycleManager` mengelola state init/deinit secara eksplisit.
2. Folder `Data/` terintegrasi dalam master include graph.
3. Tidak ada duplikasi file `Context` di domain Analysis.
4. Runtime module dan signal source dibuat melalui `CModuleFactory`.
5. Hasil compile `PASR_MODULAR.mq5` tetap `0 errors, 0 warnings`.
6. Dokumentasi sinkron dengan kenyataan file di disk.

Status lokal: **DONE**.

Tahap berikutnya adalah migrasi lanjutan yang akan dikerjakan sebagai proyek terpisah, bukan residu dari fase centralized modular migration ini.

---

Terakhir diperbarui: 2026-06-02.
