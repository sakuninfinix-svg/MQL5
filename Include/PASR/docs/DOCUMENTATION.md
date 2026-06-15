# 📘 PASR Technical Documentation Hub

Selamat datang di pusat dokumentasi **Price Action Support Resistance (PASR) EA**. Dokumen ini adalah pintu masuk tunggal untuk memahami, memelihara, dan mengembangkan sistem trading berbasis **Centralized Modular Pipeline** — terdiri dari **188 file MQH** yang tersebar di **12 modul** dengan total ~2 MB kode.

---

## 🚀 Visi & Filosofi Sistem
> **"Centralized Control, Decentralized Logic"**
Sistem memisahkan mekanisme *orchestration* (urutan kerja) dari *domain logic* (strategi trading). `CPASRKernel` menjadi jantung sistem, menjamin stabilitas eksekusi tanpa mengorbankan fleksibilitas strategi. Komunikasi antar modul dilakukan secara *decoupled* via `CEventBus` (asinkron) dan `CServiceLocator` (sinkron).

---

## 📂 Peta Dokumentasi (22 Dokumen)

Dokumentasi terbagi dalam dua kategori:

### A. Referensi Struktural per Modul (13 dokumen)
Dokumen ini berisi inventaris file, dependency graph, dan public API setiap modul. Disusun berdasarkan layer arsitektur:

| Layer | Dokumen | File | Deskripsi |
|-------|---------|------|-----------|
| **Kernel** | [`Central.md`](./Central.md) | 6 | Bootstrap, Registry, ServiceLocator, Factory, Lifecycle |
| **Orkestrasi** | [`Orchestration.md`](./Orchestration.md) | 19 | Pipeline engine, 14 stages, stage registry |
| **Core** | [`Core.md`](./Core.md) | 15 | EventBus, Config, IManager, Types, Globals |
| **Data** | [`Data.md`](./Data.md) | 3 | SR structs, Regime types, Symbol scanner |
| **Infra** | [`Infra.md`](./Infra.md) | 13 | DataManager, Journal, Telemetry, Session, State, Health |
| **Analysis** | [`Analysis.md`](./Analysis.md) | 12 | SR/Zone/Pattern, Regime, HMM, Adaptive params |
| **AI** | [`AI.md`](./AI.md) | 18 | MLP, LSTM, Ensemble, ONNX, Attention, Feature engineering |
| **Signal** | [`Signal.md`](./Signal.md) | 17 | Sources, Aggregator, Filter pipeline, Decision engine |
| **Trade** | [`Trade.md`](./Trade.md) | 13 | Risk, Execution, Exit, Position, Recovery |
| **UI** | [`UI.md`](./UI.md) | 1 | Dashboard dengan overlay observability |
| **Observability** | [`Observability.md`](./Observability.md) | 1 | Konstanta dan definisi metrik |
| **QA** | [`QA.md`](./QA.md) | 17 | Assertions, Smoke tests, Monte Carlo, Walk-forward, Mocks |

### B. Dokumentasi Lintas-Modul (9 dokumen)
Dokumen yang membahas aspek arsitektur, alur bisnis, dan strategi pengembangan secara horizontal:

| Dokumen | Fokus |
|---------|-------|
| [`INDEX.md`](./INDEX.md) | **Master index** — layer diagram, tabel modul, dependency order, quick start |
| [`ARCHITECTURE.md`](./ARCHITECTURE.md) | Blueprint kernel, registry, lifecycle, 14-stage pipeline |
| [`QUICKSTART.md`](./QUICKSTART.md) | Panduan cepat integrasi `CPASRKernel` ke `.mq5` baru |
| [`COMPONENT_INTERACTION.md`](./COMPONENT_INTERACTION.md) | Diagram alur interaksi (EventBus, Ledger, Pipeline stages) |
| [`CENTRALIZED_MODULAR_MIGRATION_PROJECT.md`](./CENTRALIZED_MODULAR_MIGRATION_PROJECT.md) | Sejarah transformasi monolitik → modular (8 fase, selesai) |
| [`PHASE5_SPLIT_STAGE_PROGRESS.md`](./PHASE5_SPLIT_STAGE_PROGRESS.md) | Progress ekstraksi stage ke object mandiri (Phase 5) |
| [`Fundamental_business_logic.md`](./Fundamental_business_logic.md) | Audit logika bisnis, konsistensi data, integritas sinyal |
| [`Artificial_Inteligent_Development.md`](./Artificial_Inteligent_Development.md) | Status lengkap pengembangan AI (100% code complete) |
| [`OPTIMIZATION_SUMMARY.md`](./OPTIMIZATION_SUMMARY.md) | Ringkasan optimasi LSTM, Attention, HMM, CNN, Adaptive Pipeline |

---

## 📈 Status Pengembangan

### ✅ Sudah Tercapai (Code Complete — 100%)
Seluruh modul AI telah selesai ditulis dan siap diintegrasikan:

| Komponen | Modul | Integrasi |
|----------|-------|-----------|
| **SequenceFeatureBuilder** | `AI/` | Tensor [64×12] dengan InjectRegime & InjectStructure |
| **ONNXBridge v2** | `AI/` | Load, Run, RunSequence, RunSequenceTensor, RunFV |
| **AIEnsemble ONNX slot** | `AI/` | Fallback MLP jika ONNX gagal, blend vote ONNX (w=1.5) + MLP |
| **AIFeatureValidator** | `AI/` | NaN, outlier, shape, stale validation |
| **LSTMInference** | `AI/` | 2-layer LSTM (128 hidden, seq=50) — terintegrasi di AIOrchestrator |
| **AttentionFusion** | `AI/` | 4-head attention fusion — terintegrasi di AIOrchestrator |
| **ConfidenceCalibrator** | `AI/` | Platt scaling + agreement-weighted calibration |
| **OnlineLearningGuard** | `AI/` | Drift detection (z-score), veto mechanism |
| **AITrainer** | `AI/` | Ring buffer 500, retrain every 50, online SGD |
| **AIOrchestrator** | `AI/` | Pipeline: feature → validate → ensemble → LSTM → attention → calibrate → drift |
| **AISignalSource** | `AI/` | ISignalSource adapter, w=1.2 voter |
| **HMMRegimeDetector** | `Analysis/` | 6-state HMM, forward algorithm, online learning |
| **CNNPatternRecognizer** | `Analysis/` | 1D CNN (2 conv + dense), 6 pattern output |
| **AdaptivePipelineEngine** | `Orch/` | Regime-adaptive pipeline wrapper |
| **DynamicWeightManager** | `Signal/` | Bayesian weight adaptation, perf tracking |

### ⚠️ Perlu Integrasi Manual
Komponen berikut sudah ada kode tetapi belum diaktifkan di runtime:
1. **DynamicWeightManager → SignalManager** — ikuti `SignalManagerIntegration.mqh`
2. **HMMRegimeDetector → PASRKernel** — opsional, bisa ganti `MarketRegimeDetector`
3. **CNNPatternRecognizer → PatternManager** — opsional, augmentasi pattern detection
4. **AdaptivePipelineEngine → PASRKernel** — opsional, ganti `PipelineEngine`

### ❌ Menunggu Resource Eksternal
- **Compile gate diverifikasi** — butuh MetaEditor dengan full include chain
- **ONNX model nyata** — butuh `#define PASR_ENABLE_ONNX` + file `.onnx` hasil training Python
- **Training pipeline Python** — `tools/train_transformer.py` belum dibuat
- **Walk-forward test Transformer** — menunggu model ONNX siap
- **Dashboard backend aktif** — implementasi setelah model siap

---

## 🧭 Arah Pengembangan Lanjutan

### Fase 1: Integrasi Runtime (Sekarang)
- Integrasi DynamicWeightManager ke SignalManager
- Smoke test dengan LSTM + Attention aktif (tanpa ONNX)
- Validasi latency inferensi < 50ms per siklus

### Fase 2: Training Pipeline Python (Jangka Pendek)
- Buat `tools/train_transformer.py` (PyTorch → ONNX export)
- Training model MVP dengan validasi accuracy > baseline MLP
- Verifikasi ONNX load di MT5 via `ONNXBridge`
- Dokumentasi hyperparameter dan prosedur retrain

### Fase 3: Advanced AI (Jangka Menengah)
- Implementasi **SAITransformerHeads** struct untuk multi-head Transformer
- **no_trade_prob** veto source — abstain jika semua model tidak yakin
- **AdaptiveParamsStage** volatility head — SL/TP adaptif berdasarkan volatilitas
- Full walk-forward test dengan Transformer backend
- Dashboard dengan informasi backend aktif, model version, latency

### Fase 4: Production Hardening (Jangka Panjang)
- Multi-symbol expansion — kernel scanning multi-instrument simultan
- Adaptive parameter governance — validasi range otomatis saat init
- Prosedur retrain periodik terdokumentasi
- Strategy Tester 0 errors di semua timeframe (M5, M15, M30, H1)

---

## 🛠️ Standar Pengembangan
Setiap perubahan harus melewati gerbang berikut:
1. **Compile Guard**: `0 errors, 0 warnings` 
2. **Smoke Test**: `PASR_Smoke.mq5` — verifikasi kernel bootstrapping.
3. **Business Logic Harness**: Tidak merusak integritas posisi dan account.

---

## 💡 Catatan Penting untuk Developer
- **Entry Point**: Selalu `#include <PASR/Core/PASR.mqh>`. Jangan include manager individual.
- **OnTick Policy**: `OnTick()` ringan. Pekerjaan berat (Analisis, AI, Risk) di `OnTimer()` via pipeline.
- **Stabilitas**: PASR masih *Research-Grade*. Uji di demo/tester sebelum live.
- **Dokumentasi Baru**: Tambahkan file `.md` di folder `docs/` dan daftarkan di halaman ini serta `INDEX.md`.

---
*Terakhir Diperbarui: 2026-06-15 | Tim Arsitektur PASR*
