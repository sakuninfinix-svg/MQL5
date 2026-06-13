# PASR Python Tools — Essential AI/Optimization Toolkit

Directory untuk Python ecosystem tools yang mendukung **10 model AI** di EA PASR:

| # | Model | Bentuk | Output File | Training Script |
|---|-------|--------|-------------|-----------------|
| 1 | 🧠 **MLP Regressor** | 34→64→32→1 NN | `PASR_mlp_m*.bin` | `training/train_mlp.py` |
| 2 | 🎯 **Confidence Calibration** | Platt scaling | `PASR_calibration_params.bin` | `training/retrain_ensemble.py` |
| 3 | 📊 **Entry Quality Scorer** | Logistic Regression 8-fitur | `PASR_entry_quality_weights.bin` | `training/train_entry_quality_weights.py` |
| 4 | 🔄 **Recovery Scorer** | Logistic Regression 7-fitur | `PASR_recovery_weights.bin` | `training/train_recovery_weights.py` |
| 5 | 🕐 **Session Quality Scorer** | Logistic Regression 7-fitur | `PASR_session_quality_weights.bin` | `training/train_session_quality_weights.py` |
| 6 | 📐 **SR Zone Scorer** | Logistic Regression 7-fitur | `PASR_sr_zone_weights.bin` | `training/tune_regression_scorer.py` |
| 7 | 🚪 **Exit Pressure Scorer** | Logistic Regression 7-fitur | `PASR_exit_pressure_weights.bin` | `training/tune_regression_scorer.py` |
| 8 | 🌡️ **Regime Classifier** | One-vs-rest 5-class | `PASR_regime_weights.bin` | `training/tune_regression_scorer.py` |
| 9 | 🔷 **Pattern Classifier** | 5-pattern multi-class | `PASR_pattern_weights.bin` | `training/tune_regression_scorer.py` |
| 10 | 🔗 **ONNX Sequence Model** | [1,64,12]→[1,2] | `PASR_sequence.onnx` | `export_onnx.py` |

---

## Setup

```bash
pip install -r tools/requirements.txt
```

---

## Recommended AI Workflow

### 1. Generate / prepare training data

Untuk MLP (model #1), buat CSV dengan kolom `f0..f33`, `label`, dan optional `weight`.

```bash
python tools/training/generate_quality_training_data.py \
  --output output/AI_Training_Data_Raw.csv \
  --samples-per-regime 2000
```

### 2. Preprocess training data

```bash
python tools/training/preprocess_ai_training_data.py \
  --input output/AI_Training_Data_Raw.csv \
  --output output/AI_Training_Data_Processed.csv
```

### 3. Train MLP weights (Model #1)

```bash
python tools/training/train_mlp.py \
  --csv output/AI_Training_Data_Processed.csv \
  --out output
```

Output: `PASR_mlp_m0.bin`, `PASR_mlp_m1.bin`, `mlp_training_report.json`

Copy `.bin` ke `MT5/MQL5/Files/`. `AIEnsemble.mqh` memuatnya otomatis.

### 4. Train confidence calibration (Model #2)

Input `PASR_calibration.csv` dengan kolom:

```text
score,outcome,rr
```

`outcome`: `+1` win, `-1` loss, `0` pending/ignored.

```bash
python tools/training/retrain_ensemble.py \
  --csv PASR_calibration.csv \
  --out output
```

Output: `PASR_calibration_params.bin` → copy ke `MT5/MQL5/Files/`

### 5. Train scorer weights (Model #3-5)

```bash
# Entry quality (8 fitur)
python tools/training/train_entry_quality_weights.py --csv entry_quality.csv --out output

# Recovery (7 fitur)
python tools/training/train_recovery_weights.py --csv recovery.csv --out output

# Session quality (7 fitur)
python tools/training/train_session_quality_weights.py --csv session_quality.csv --out output
```

### 6. Train SR Zone / Exit Pressure / Regime / Pattern (Model #6-9)

Semua menggunakan `tune_regression_scorer.py`:

```bash
# SR Zone (7 fitur)
python tools/training/tune_regression_scorer.py --scorer sr_zone --csv sr_zone.csv --out output

# Exit Pressure (7 fitur)
python tools/training/tune_regression_scorer.py --scorer exit_pressure --csv exit_pressure.csv --out output

# Regime classifier (6 fitur, 5 kelas)
python tools/training/tune_regression_scorer.py --scorer regime --csv regime.csv --out output

# Pattern classifier (5 fitur, 5 pola)
python tools/training/tune_regression_scorer.py --scorer pattern --csv pattern.csv --out output
```

### 7. Optional ONNX sequence model (Model #10)

```bash
python tools/export_onnx.py --out output/PASR_sequence.onnx
```

Input: `[1, 64, 12]` → Output: `[1, 2]` = `[direction, confidence]`

Copy ke `MT5/MQL5/Files/`, aktifkan `InpAIEnableOnnx=true`.

---

## Directory Structure

```
tools/
├── training/           # 🎯 AI model training scripts
│   ├── train_mlp.py
│   ├── train_mlp_numpy.py
│   ├── train_entry_quality_weights.py
│   ├── train_recovery_weights.py
│   ├── train_session_quality_weights.py
│   ├── retrain_ensemble.py
│   ├── calibrate_numpy.py
│   ├── preprocess_ai_training_data.py
│   ├── generate_quality_training_data.py
│   ├── generate_calibration_data.py
│   └── tune_regression_scorer.py
├── archived/           # 📦 Simulator/analisis usang (bisa dihapus)
│   ├── pasr_simple_simulator.py
│   ├── pasr_strategy_simulator.py
│   ├── comprehensive_backtest.py
│   ├── analyze_pf.py
│   ├── quick_pf_analysis.py
│   └── optimization_manager.py
├── export_onnx.py           # ONNX model export
├── walkforward_harness.py   # Walk-forward validation
├── strategy_tester_validation.py # MT5 tester validation
├── compile_mq5.sh           # Compile via MetaEditor
├── run_optimization.sh      # Optimization runner
├── AI_Training_Data_Validation.json # Validation report
├── requirements.txt
└── README.md
```

---

## Training Tools (di `training/`)

### `train_mlp.py` — Main MLP Training Exporter

Melatih MLP `34->64->32->1` dari CSV fitur `f0..f33` dan mengekspor bobot binary yang kompatibel dengan `AIInference.mqh::LoadWeights()`.

### `train_mlp_numpy.py` — NumPy-only MLP Trainer

Alternatif `train_mlp.py` tanpa dependensi scikit-learn. Cocok untuk environment minimal.

### `train_entry_quality_weights.py` — Entry Quality Scorer

Melatih logistic regression 8 fitur untuk menilai kualitas entry. Output: `PASR_entry_quality_weights.bin`.

### `train_recovery_weights.py` — Recovery Eligibility Scorer

Melatih logistic regression 7 fitur untuk menentukan apakah recovery/re-entry layak. Output: `PASR_recovery_weights.bin`.

### `train_session_quality_weights.py` — Session Quality Scorer

Melatih logistic regression 7 fitur untuk menilai kondisi sesi trading. Output: `PASR_session_quality_weights.bin`.

### `retrain_ensemble.py` — Confidence Calibration Pipeline

Melatih parameter Platt/confidence calibration dari `PASR_calibration.csv` dan mengekspor `PASR_calibration_params.bin` untuk `ConfidenceCalibrator.mqh`.

### `calibrate_numpy.py` — NumPy-only Calibration

Alternatif `retrain_ensemble.py` tanpa scikit-learn. Output format sama.

### `preprocess_ai_training_data.py` — Data Preprocessor

Validasi struktur CSV, normalisasi fitur ke [0,1], balancing dataset, dan deduplikasi.

### `generate_quality_training_data.py` — Synthetic Data Generator

Menghasilkan data training realistis dengan multiple market regimes yang cocok dengan `AIFeatureBuilder.mqh`.

### `generate_calibration_data.py` — Calibration Data Generator

Menghasilkan data kalibrasi sintetis untuk `retrain_ensemble.py`.

### `tune_regression_scorer.py` — Universal Hyperparameter Tuner

Grid-search untuk semua binary scorer (entry_quality, recovery, session_quality, sr_zone, exit_pressure, regime, pattern).

---

## Other Tools

### `walkforward_harness.py` — Walk-Forward Test Harness

Membagi rentang tanggal menjadi beberapa window IS/OOS, menjalankan backtest MT5, dan mengagregasi hasil ke HTML report.

```bash
python tools/walkforward_harness.py \
  --symbol EURUSD --tf H1 \
  --start 2023-01-01 --end 2025-12-31 \
  --windows 6 --is-ratio 0.70 \
  --out wf_output
```

### `run_optimization.sh` — Optimization Runner

Shell script untuk menjalankan optimization di Linux/Wine environment. Jalankan via terminal, bukan Python.

### `strategy_tester_validation.py` — MT5 Tester Validation

Validasi apakah setup MT5 tester berfungsi dengan benar. Cek compile, symbol availability, account, dll.

### `export_onnx.py` — ONNX Sequence Model Export

Export PASR sequence model placeholder ke ONNX format untuk `ONNXBridge.mqh`.

### `compile_mq5.sh` — MQL5 Compiler

Compile file `.mq5` via wine MetaEditor64. Gunakan untuk quick compile.

> **Catatan:** File `pasr_simple_simulator.py`, `pasr_strategy_simulator.py`, `comprehensive_backtest.py`, `analyze_pf.py`, `quick_pf_analysis.py`, dan `optimization_manager.py` sudah diarsipkan ke `tools/archived/`. Script tersebut menggunakan data sintetis dan hasilnya tidak relevan untuk pengambilan keputusan real. Jika diperlukan di masa depan, masih bisa diakses dari folder `archived/`.

---

## Deployment Files Summary

| File | Generated by | Consumed by | Copy to |
|---|---|---|---|
| `PASR_mlp_m0.bin` | `training/train_mlp.py` | `AIEnsemble.mqh` / `AIInference.mqh` | `MT5/MQL5/Files/` |
| `PASR_mlp_m1.bin` | `training/train_mlp.py` | `AIEnsemble.mqh` / `AIInference.mqh` | `MT5/MQL5/Files/` |
| `PASR_entry_quality_weights.bin` | `training/train_entry_quality_weights.py` | Entry Quality Scorer | `MT5/MQL5/Files/` |
| `PASR_recovery_weights.bin` | `training/train_recovery_weights.py` | Recovery Scorer | `MT5/MQL5/Files/` |
| `PASR_session_quality_weights.bin` | `training/train_session_quality_weights.py` | Session Quality Scorer | `MT5/MQL5/Files/` |
| `PASR_calibration_params.bin` | `training/retrain_ensemble.py` | `ConfidenceCalibrator.mqh` | `MT5/MQL5/Files/` |
| `PASR_sequence.onnx` | `export_onnx.py` or external training | `ONNXBridge.mqh` | `MT5/MQL5/Files/` |

---

*PASR EA © 2026 - Optimized for practical AI deployment*