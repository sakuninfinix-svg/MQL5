# 📘 PASR Technical Documentation Hub

Selamat datang di pusat dokumentasi **Price Action Support Resistance (PASR) EA**. Dokumen ini dirancang sebagai panduan navigasi utama bagi pengembang untuk memahami, memelihara, dan mengembangkan sistem perdagangan berbasis **Centralized Modular Pipeline**.

---

## 🚀 Visi & Filosofi Sistem
> **"Centralized Control, Decentralized Logic"**
Sistem ini memisahkan mekanisme *orchestration* (urutan kerja) dari *domain logic* (strategi trading). Dengan menggunakan `CPASRKernel` sebagai jantung sistem, PASR menjamin stabilitas eksekusi tanpa mengorbankan fleksibilitas strategi.

---

## 📂 Peta Dokumentasi (Navigation Map)

### 1. Fondasi & Arsitektur
- [**ARCHITECTURE.md**](./ARCHITECTURE.md): Blueprint kernel, registry, lifecycle manager, dan 14-stage pipeline.
- [**QUICKSTART.md**](./QUICKSTART.md): Panduan cepat integrasi `CPASRKernel` ke dalam file `.mq5` baru.
- **CENTRALIZED_MODULAR_MIGRATION_PROJECT.md**: Rekaman sejarah transformasi dari sistem monolitik ke modular.

### 2. Logika Bisnis & Strategi
- [**fundamental-business-logic-audit.md**](./fundamental-business-logic-audit.md): Analisis mendalam tentang risiko logika trading, konsistensi data, dan integritas sinyal.
- [**Signal Decision Engine**: (In Progress) Dokumentasi mekanisme voting dan veto sinyal.

---

## 📈 Progress Pengembangan (Development Roadmap)

### **Status Saat Ini: Fase Hardening & Integritas Data**
Setelah sukses memigrasikan arsitektur ke model modular, fokus saat ini bergeser ke **Deterministic Trading Decisions**.

#### ✅ Selesai (Milestones)
- **Arsitektur Modular Centralized**: Kernel sepenuhnya mengontrol lifecycle dan dependency (v0.31).
- **Position Authority (FBL-001)**: Implementasi `CPositionRegistry` sebagai sumber kebenaran tunggal posisi terbuka.
- **Account Consistency (FBL-002)**: Penggunaan `SAccountSnapshot` yang menjamin kalkulasi risk tetap konsisten dalam satu siklus pipeline.
- **AI Feature Guard**: Validasi input AI sebelum inferensi dilakukan untuk mencegah "garbage in, garbage out".

#### 🛠️ Sedang Berjalan (Active Sprints)
- **Execution & Exit Ledger (FBL-005)**: Memperkuat pelacakan status order dari request hingga konfirmasi broker (DEAL_ENTRY_IN/OUT).
- **Signal Conflict Guard**: Pengembangan algoritma penengah (resolver) ketika sinyal AI dan Price Action tidak sejalan.
- **AI Model Evolution**: Riset integrasi *Transformer-based Attention* untuk prediksi volatilitas intra-day.

#### 📋 Backlog (Future Work)
- **Multi-Symbol Expansion**: Mengoptimalkan kernel untuk menangani pemindaian multi-instrumen secara simultan.
- **Adaptive Parameter Governance**: Digitalisasi parameter trading agar validasi range terjadi secara otomatis saat inisialisasi.

---

## 🛠️ Standar Pengembangan
Setiap perubahan pada kode harus melewati gerbang verifikasi berikut:
1. **Compile Guard**: Harus lolos `0 errors, 0 warnings` pada `PASR_MODULAR.mq5`.
2. **Smoke Test**: Menjalankan `PASR_Smoke.mq5` untuk memverifikasi fungsionalitas dasar kernel.
3. **Business Logic Harness**: Memastikan perubahan tidak merusak integritas data posisi dan account.

---

## 💡 Catatan Penting untuk Developer
- **Entry Point**: Selalu gunakan `#include <PASR/Core/PASR.mqh>`. Jangan meng-include manager secara individual di file EA utama.
- **OnTick Policy**: Pertahankan `OnTick()` tetap ringan. Pekerjaan berat (Analisis, AI, Risk) wajib berada di dalam `OnTimer()` melalui pipeline stages.
- **Stabilitas**: PASR saat ini berada dalam tahap *Research-Grade*. Selalu lakukan pengujian di akun demo/tester sebelum mempertimbangkan implementasi live.

---
*Terakhir Diperbarui: 2026-06-05 | Tim Arsitektur PASR*
