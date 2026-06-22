# PASR Training Guide

## Overview

PASR_PRERELEASE.mq5 membutuhkan dua jenis training:

### 1. AI/ML Model Training (Sudah Ada)
**File yang sudah ada di `training/` folder:**
- `train_mlp_classifier.py` - Training MLP (34→64→32→1)
- `import_mt5_trades.py` - Import MT5 trade data
- `real_feature_extractor.py` - Extract 34 features
- `preprocess_ai_training_data.py` - Preprocessing
- `calibrate_numpy.py` - Kalibrasi
- `auto_retrain.py` - Online retraining

**Cara menjalankan:**
```bash
cd training/
bash run_pipeline.sh
```

### 2. Parameter Optimization
- `optimize_pasr_parameters.py` - Optimasi setting EA
- `run_complete_training_pipeline.sh` - Workflow lengkap

**Cara menjalankan:**
```bash
cd training/
python3 optimize_pasr_parameters.py --symbol EURUSD --timeframe M15 --months 12
```

## Pipeline Lengkap

Jalankan pipeline lengkap untuk kedua jenis training:

```bash
cd training/
bash run_complete_training_pipeline.sh
```

Pipeline ini akan:
1. Export data dari MT5
2. Training AI/ML models (MLP + GBR)
3. Optimasi parameter EA
4. Generate file .set yang teroptimasi
5. Validasi dan deployment

## Target Kriteria

- Profit Factor >= 1.5
- Daily trading >= 10 trade/hari
- Maximum drawdown <= 15%

## AI/ML Components

### MLP (Multi-Layer Perceptron)
- Architecture: 34→64→32→1
- Focal loss untuk class imbalance
- Gradient clipping untuk stability
- Cosine annealing learning rate
- Dropout untuk regularization

### GBR (Gradient Boosting Regressor)
- Multi-timeframe analysis
- 150 trees (optimal range: 100-200)
- Learning rate: 0.05 (optimal range: 0.01-0.1)
- Max depth: 4 (optimal range: 3-6)

### Feature Extraction
- 34 runtime-compatible features
- Trend indicators
- Volatility measures
- Pattern recognition
- Market regime detection

## Parameter Optimization

Parameter yang dioptimasi:
- Risk parameters (lot size, SL/TP, drawdown)
- Market parameters (ATR, ADX, spread filter)
- Signal parameters (lookback, confluence, score)
- Pattern parameters (score, lookback, ratios)
- AI parameters (confidence, learning rate)

## Deployment

Setelah training selesai:
1. Copy `PASR_mlp_m*.bin` → `MQL5/Files/`
2. Copy `PASR_OPTIMIZED.set` → `MQL5/Experts/`
3. Load .set file di MT5
4. Enable AI di EA settings
5. Test di demo account dulu

## Monitoring

- Monitor performance selama 2-4 minggu
- Re-optimize jika performance menurun
- Update model AI secara berkala
- Adjust risk management berdasarkan account size
