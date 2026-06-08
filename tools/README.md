# PASR Python Tools - Essential Only

Directory untuk Python ecosystem tools yang mendukung EA PASR.

**Status**: ✅ Optimized - Removed cosmetic files, kept only essential tools

---

## Setup

```bash
pip install -r tools/requirements.txt
```

---

## Core Tools

### 1. `retrain_ensemble.py` — AI Retraining Pipeline

Membaca `PASR_calibration.csv` dari MT5 Files/, melatih model kalibrasi,
dan mengekspor weights baru untuk pickup oleh `AIEnsemble.mqh`.

**Usage**:
```bash
python tools/retrain_ensemble.py --csv path/to/PASR_calibration.csv
```

### 2. `walkforward_harness.py` — Walk-Forward Test Harness

Membagi rentang tanggal menjadi N window IS/OOS, menjalankan backtest MT5
untuk setiap window, dan mengagregasi hasil ke HTML report.

**Usage**:
```bash
python tools/walkforward_harness.py \
    --symbol EURUSD --tf H1 \
    --start 2023-01-01 --end 2025-12-31 \
    --windows 6 --is-ratio 0.70 \
    --out wf_output
```

### 3. `optimization_manager.py` — Optimization Automation

Automates systematic parameter optimization for MT5 Strategy Tester.

### 4. `run_optimization.sh` — Optimization Runner

Shell script untuk menjalankan optimization di Linux/Wine environment.

### 5. Simulator Tools (Linux-Native)

- `pasr_simple_simulator.py` - Simple backtesting simulator (no dependencies)
- `pasr_strategy_simulator.py` - Advanced strategy simulator with numpy/pandas

### 6. Data Processing

- `preprocess_ai_training_data.py` - Preprocess AI training data
- `strategy_tester_validation.py` - Validate strategy tester setup

---

## Removed (Cosmetic/Redundant)

The following files were removed to save space and reduce clutter:

- ❌ `AI_TRAINING_DATA_GUIDE.md` - Documentation (can be regenerated)
- ❌ `AI_TRAINING_SYSTEM_GUIDE.md` - Documentation (can be regenerated)
- ❌ `OPTIMIZATION_COMPLETE_SUMMARY.md` - Status report (outdated)
- ❌ `TESTING_STATUS_SUMMARY.md` - Status report (outdated)
- ❌ `STRATEGY_TESTER_VALIDATION.md` - Documentation (redundant)
- ❌ `OPTIMIZATION_GUIDE.md` - Documentation (redundant)
- ❌ `AI_Training_Data_Template.csv` - Template (large, can be regenerated)
- ❌ `ai_training_config.json` - Config (can be regenerated)
- ❌ `pasr_best_config.json` - Results (specific to one run)
- ❌ `pasr_optimization_results.json` - Results (specific to one run)
- ❌ `compile_mt5.py` - Wine-specific tool (not needed)
- ❌ `export_onnx.py` - ONNX validation (optional, not core)
- ❌ `run_baseline_test.sh` - Redundant with optimization runner
- ❌ `run_baseline_test_wine.sh` - Redundant with optimization runner
- ❌ `__pycache__/` - Python cache (auto-generated)

**Space Saved**: ~150KB of documentation and redundant files

---

*PASR EA © 2026 - Optimized for Efficiency*
