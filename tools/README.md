# PASR Python Tools

Directory untuk Python ecosystem tools yang mendukung EA PASR.

---

## Setup

```bash
pip install -r tools/requirements.txt
```

---

## 1. `retrain_ensemble.py` — AI Retraining Pipeline

Membaca `PASR_calibration.csv` dari MT5 Files/, melatih model kalibrasi,
dan mengekspor weights baru untuk pickup oleh `AIEnsemble.mqh`.

### Workflow

```
MT5 EA running live/demo
    └─ OnDeinit() → ExportCalibrationCSV()
           └─ MQL5/Files/PASR_calibration.csv
                  │
                  ▼
           retrain_ensemble.py
                  │
                  ├─ output/PASR_weights.bin   ← copy ke MQL5/Files/
                  ├─ output/weights.json        ← human-readable
                  └─ output/calib_report.html   ← open di browser
                  │
                  ▼
           Copy PASR_weights.bin → MT5/MQL5/Files/
           Restart EA dengan InpLoadWeights=true
```

### Usage

```bash
# Basic
python tools/retrain_ensemble.py --csv path/to/PASR_calibration.csv

# Dengan options
python tools/retrain_ensemble.py \
    --csv   MQL5/Files/PASR_calibration.csv \
    --out   output/retrain_20260521 \
    --method platt          # atau: isotonic
```

### Deployment

1. Copy `output/PASR_weights.bin` ke `C:/Users/.../AppData/Roaming/MetaQuotes/Terminal/.../MQL5/Files/`
2. Di MT5: EA input `InpLoadWeights = true`
3. Restart EA

---

## 2. `walkforward_harness.py` — Walk-Forward Test Harness

Membagi rentang tanggal menjadi N window IS/OOS, menjalankan backtest MT5
untuk setiap window, dan mengagregasi hasil ke HTML report.

### Usage

```bash
# Mock mode (tanpa MT5 — untuk testing pipeline)
python tools/walkforward_harness.py \
    --symbol EURUSD --tf H1 \
    --start 2023-01-01 --end 2025-12-31 \
    --windows 6 --is-ratio 0.70 \
    --out wf_output

# Live mode (Windows + MT5 installed)
python tools/walkforward_harness.py \
    --mt5  "C:/Program Files/MetaTrader 5/terminal64.exe" \
    --ea   PASR_MODULAR \
    --symbol EURUSD --tf H1 \
    --start 2022-01-01 --end 2025-12-31 \
    --windows 8 --deposit 10000
```

### Output

```
wf_output/
├── tester_w1.ini ... tester_wN.ini   ← MT5 config files
├── wf_charts.png                     ← equity curves + stats charts
├── wf_report.html                    ← full HTML report
└── wf_summary.json                   ← machine-readable summary
```

### Interpretation

| Metric | Good | Warn | Poor |
|--------|------|------|------|
| Profit Factor | > 1.5 | 1.1–1.5 | < 1.1 |
| Win Windows | > 60% | 40–60% | < 40% |
| Avg Max DD | < 10% | 10–20% | > 20% |

---

## 3. ONNX Integration (opsional)

Jika ingin menggunakan model ONNX di EA:

```bash
# Install tambahan
pip install skl2onnx onnxruntime

# Setelah retrain, konversi ke ONNX:
python tools/export_onnx.py --weights output/weights.json --out output/PASR_model.onnx

# Copy ke MT5 Files/
# Di EA: Include/PASR/Signal/AI/ONNXBridge.mqh sudah siap menerima model ini
```

Lihat `Include/PASR/Signal/AI/ONNXBridge.mqh` untuk detail loading di sisi MQL5.

---

*PASR EA © 2026*
