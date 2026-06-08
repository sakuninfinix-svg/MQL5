# 🧠 Proyek Pengembangan Artificial Intelligence (AI) PASR

Dokumen ini merinci arsitektur AI yang sedang berjalan di sistem PASR dan menguraikan grand design untuk pengembangan kapabilitas kecerdasan buatan di masa depan, dengan fokus pada Deep Learning.

## 1. Desain AI Saat Ini (Current AI Architecture)

Arsitektur AI PASR saat ini menggunakan pendekatan **Hybrid AI-Signal Filtering**, di mana AI berperan sebagai **Confidence Layer** dan **Veto Mechanism** terhadap sinyal trading berbasis Price Action/Support Resistance tradisional. Ini dirancang untuk robustness dan fleksibilitas.

### 1.1 Tujuan Utama
- **Confidence Scoring**: Memberikan skor probabilitas (0-1) terhadap validitas sinyal.
- **Veto Mechanism**: Memblokir trading jika input AI tidak valid atau model tidak sehat.
- **Adaptif**: Model dapat diperbarui secara independen tanpa perubahan kode MQL5 yang signifikan.

### 1.2 Komponen Kunci (`Include/PASR/AI/`)

- **`AIFeatureBuilder.mqh`**:
    - **Fungsi**: Mengumpulkan dan membangun vektor fitur (input) dari data pasar historis dan real-time. Ini mengubah data mentah (harga, volume, indikator teknikal) menjadi format numerik yang dapat dipahami oleh model AI.
    - **Output**: `float[]` atau `double[]` sebagai *tensor* fitur.

- **`CAIFeatureValidator.mqh`**:
    - **Fungsi**: Bertindak sebagai gerbang kualitas data. Sebelum fitur diserahkan ke model AI, validator ini memeriksa:
        - Kualitas data (tidak ada NaN/Inf).
        - Freshness (data tidak kadaluarsa).
        - Konsistensi dimensi fitur.
        - Batasan nilai (fitur berada dalam rentang yang diharapkan).
    - **Output**: `bool isValid`, `string reason`, `bool isStale`.
    - **Peran Kritis**: Mencegah "garbage in, garbage out" dan memastikan robustness sistem.

- **`AIEnsemble.mqh`**:
    - **Fungsi**: Mengelola dan mengkoordinasikan beberapa model AI. Ini memungkinkan penggunaan teknik *ensemble learning* (misalnya, voting atau averaging dari beberapa model) untuk meningkatkan stabilitas dan mengurangi *overfitting*.
    - **Output**: Agregasi skor dari model-model individual.

- **`ONNXBridge.mqh`**:
    - **Fungsi**: Jembatan untuk inferensi model ONNX (Open Neural Network Exchange). Ini memungkinkan model Deep Learning yang dilatih di lingkungan Python (misalnya, TensorFlow, PyTorch, Scikit-learn) untuk dieksekusi secara native di MQL5.
    - **Peran Kritis**: Memisahkan proses training (Python) dari inferensi (MQL5), memungkinkan pengembangan model yang canggih.

- **`ConfidenceCalibrator.mqh`**:
    - **Fungsi**: Mengkalibrasi output mentah dari model AI menjadi probabilitas yang lebih dapat diinterpretasikan dan akurat secara statistik. Misalnya, mengubah skor 0.7 dari model menjadi "70% peluang keberhasilan".

- **`AIOrchestrator.mqh`**:
    - **Fungsi**: Komponen sentral AI yang mengkoordinasikan seluruh alur: dari pembangunan fitur, validasi, inferensi ensemble, hingga kalibrasi. Juga menangani logika *veto* jika `CAIFeatureValidator` gagal atau model ensemble tidak sehat.
    - **Output**: Final AI score (`float`), `bool isValid`, `bool isVetoed`, `string vetoReason`.

- **`AISignalSource.mqh`**:
    - **Fungsi**: Mengintegrasikan output dari `AIOrchestrator` sebagai salah satu sumber sinyal ke dalam `CSignalAggregator` di layer Signal.

### 1.3 Alur Kerja AI dalam Pipeline

```mermaid
flowchart TD
    A[Data Manager] --> B[AIFeatureBuilder: Build Tensors]
    B --> C{CAIFeatureValidator: Check Features}
    C -- Invalid/Stale --> D[AIOrchestrator: Set Veto Flag]
    C -- Valid/Clean --> E[AIEnsemble: Run Models (via ONNXBridge)]
    E --> F[ConfidenceCalibrator: Calibrate Score]
    F --> G[AIOrchestrator: Aggregate & Finalize Score]
    G --> H[PipelineContext: Update AI Score & Veto]
    D --> H
    H --> I[AIInferStage: Publish to Pipeline]
    I --> J[SignalAggregator: Use AI as Input]
```

## 2. Grand Design AI Masa Depan (Future AI Development)

Dengan fondasi modular yang telah dibangun, PASR siap untuk mengintegrasikan model Deep Learning yang lebih canggih. Fokus akan bergeser dari AI sebagai filter pasif menjadi **Decision Enhancer** dan **Autonomous Agent**.

### 2.1 Evolusi Model Prediksi Utama: Transformer-based Attention

-   **Konsep**: Menggunakan arsitektur Transformer, yang populer di NLP, untuk menganalisis data *time series* pasar. Transformer memanfaatkan *Self-Attention Mechanism* untuk menangkap dependensi jangka panjang dan hubungan antar titik data (bar) secara efisien, tidak seperti RNN/CNN tradisional.
-   **Aplikasi**:
    -   **Prediksi Volatilitas Intraday**: Transformer dapat menganalisis *order flow*, *tick data*, atau rentang harga dari ratusan bar sebelumnya untuk memprediksi probabilitas periode volatilitas tinggi/rendah yang akan datang, membantu dalam penyesuaian strategi atau risk management.
    -   **Pattern Recognition Tingkat Lanjut**: Menggantikan logika `CPatternManager` yang berbasis aturan dengan deteksi pola harga kompleks yang dipelajari secara otomatis, yang mungkin tidak dapat diidentifikasi manusia.
    -   **Market Regime Embedding**: Menghasilkan representasi vektor (embedding) dari kondisi pasar saat ini, yang dapat digunakan sebagai input untuk model downstream lainnya.
-   **Integrasi**: `ONNXBridge` akan diperbarui untuk mendukung arsitektur Transformer. `AIFeatureBuilder` akan ditingkatkan untuk menghasilkan *sequence-based features* dengan *positional encoding*. `AIOrchestrator` akan mengelola inferensi Transformer.
-   **Tugas di Roadmap**: `AI Model Evolution: Riset integrasi *Transformer-based Attention* untuk prediksi volatilitas intra-day` (aktif).

### 2.2 Deep Reinforcement Learning (DRL) untuk Pengambilan Keputusan Dinamis

-   **Konsep**: DRL melatih agen AI untuk berinteraksi dengan lingkungan (pasar) dan belajar kebijakan optimal (entry, exit, hold, volume) melalui *trial and error*, memaksimalkan *reward* (profit) dan meminimalkan *penalty* (loss).
-   **Aplikasi**:
    -   **Adaptive Exit Strategy**: Menggantikan atau melengkapi `CExitEngine` dengan strategi exit yang dinamis, belajar dari kondisi pasar yang berubah, bukan hanya level SL/TP statis.
    -   **Optimal Order Sizing**: Menentukan volume trading yang optimal secara adaptif, memperhitungkan kondisi pasar, *risk appetite* yang dipelajari, dan kondisi akun saat ini.
    -   **Entry Timing Optimasi**: Menyempurnakan waktu entry bukan hanya berdasarkan sinyal, tetapi juga konteks eksekusi dan probabilitas pergerakan harga.
-   **Integrasi**: `AIOrchestrator` akan diperluas untuk memanggil *DRL agent* untuk keputusan *action* (entry/exit/hold) atau *policy score*. `CExecutionManager` dan `CExitEngine` akan menerima *action* atau *guidance* dari DRL. Lingkungan simulasi (backtesting) MQL5 akan menjadi krusial untuk training DRL.

### 2.3 Variational Autoencoders (VAEs) untuk Anomali & Regime Detection

-   **Konsep**: VAE adalah model generatif yang belajar representasi
