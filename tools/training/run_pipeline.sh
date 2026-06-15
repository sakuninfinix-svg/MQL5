#!/usr/bin/env bash
# ============================================================================
# PASR ML Training Pipeline — Real MT5 Data
# ============================================================================
# Usage:
#   1. Run PASR_DATA_EXPORTER.mq5 in MT5 Strategy Tester (EURUSD H1, 12-24 months)
#   2. Copy output CSVs to tools/output/:
#        cp PASR_trades_export.csv output/
#        cp PASR_ohlcv_export.csv output/
#   3. Run this script:
#        bash training/run_pipeline.sh
#
# Override defaults:
#   TRADE_CSV=output/my_trades.csv OHLCV_CSV=output/my_ohlcv.csv bash training/run_pipeline.sh
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$(dirname "$SCRIPT_DIR")"
cd "$TOOLS_DIR"

# Configurable paths
TRADE_CSV="${TRADE_CSV:-output/PASR_trades_export.csv}"
OHLCV_CSV="${OHLCV_CSV:-output/PASR_ohlcv_export.csv}"
TRAINING_CSV="${TRAINING_CSV:-output/MT5_Training_Data.csv}"
OUT_DIR="${OUT_DIR:-output}"
SYMBOL="${SYMBOL:-EURUSD}"
TIMEFRAME="${TIMEFRAME:-H1}"

# Training hyperparameters
EPOCHS="${EPOCHS:-300}"
LR="${LR:-0.003}"
BATCH_SIZE="${BATCH_SIZE:-32}"
DROPOUT="${DROPOUT:-0.15}"
HIDDEN="${HIDDEN:-32,16}"
SEEDS="${SEEDS:-42,137,73}"

echo "============================================================"
echo "PASR ML Training Pipeline"
echo "============================================================"
echo "Trade CSV:    $TRADE_CSV"
echo "OHLCV CSV:    $OHLCV_CSV"
echo "Training CSV: $TRAINING_CSV"
echo "Output dir:   $OUT_DIR"
echo "Symbol:       $SYMBOL $TIMEFRAME"
echo "Arch:         34->${HIDDEN}->1"
echo "Epochs:       $EPOCHS (lr=$LR, batch=$BATCH_SIZE)"
echo "============================================================"

# Preflight checks
if [ ! -f "$TRADE_CSV" ]; then
    echo ""
    echo "ERROR: Trade CSV not found: $TRADE_CSV"
    echo ""
    echo "Steps to generate:"
    echo "  1. Open MT5 → Strategy Tester"
    echo "  2. Select PASR_DATA_EXPORTER expert"
    echo "  3. Symbol: $SYMBOL, Period: $TIMEFRAME"
    echo "  4. Run backtest (12-24 months recommended)"
    echo "  5. Copy PASR_trades_export.csv to $OUT_DIR/"
    echo ""
    exit 1
fi

if [ ! -f "$OHLCV_CSV" ]; then
    echo ""
    echo "ERROR: OHLCV CSV not found: $OHLCV_CSV"
    echo ""
    echo "Steps to generate:"
    echo "  1. Open MT5 → View → Symbols → Bars (or Ctrl+U)"
    echo "  2. Select $SYMBOL $TIMEFRAME → Export bars to CSV"
    echo "  3. Save as $OHLCV_CSV"
    echo ""
    echo "OR: PASR_DATA_EXPORTER.mq5 can export OHLCV automatically"
    echo "    if InpExportOHLCV=true is set in EA inputs."
    echo ""
    exit 1
fi

echo ""
echo "Step 1/3: Import MT5 trades + compute features..."
echo "------------------------------------------------------------"
python3 "$SCRIPT_DIR/import_mt5_trades.py" \
    --csv "$TRADE_CSV" \
    --ohlcv "$OHLCV_CSV" \
    --output "$TRAINING_CSV" \
    --symbol "$SYMBOL" \
    --timeframe "$TIMEFRAME"

if [ ! -f "$TRAINING_CSV" ]; then
    echo "ERROR: Training CSV was not created: $TRAINING_CSV"
    exit 1
fi

N_SAMPLES=$(wc -l < "$TRAINING_CSV")
N_SAMPLES=$((N_SAMPLES - 1))  # minus header
echo "  → $N_SAMPLES training samples ready"

echo ""
echo "Step 2/3: Train MLP classifier..."
echo "------------------------------------------------------------"
python3 "$SCRIPT_DIR/train_mlp_classifier.py" \
    --csv "$TRAINING_CSV" \
    --out "$OUT_DIR" \
    --epochs "$EPOCHS" \
    --lr "$LR" \
    --batch-size "$BATCH_SIZE" \
    --dropout "$DROPOUT" \
    --hidden "$HIDDEN" \
    --seeds "$SEEDS"

echo ""
echo "Step 3/3: Calibrate model outputs..."
echo "------------------------------------------------------------"

CALIBRATION_CSV="$OUT_DIR/PASR_calibration.csv"
if [ -f "$CALIBRATION_CSV" ]; then
    python3 "$SCRIPT_DIR/calibrate_numpy.py" \
        --csv "$CALIBRATION_CSV" \
        --out "$OUT_DIR"
else
    echo "  SKIP: $CALIBRATION_CSV not found."
    echo "  Calibration requires running the EA in live/demo mode"
    echo "  to collect prediction vs outcome data."
    echo "  The MLP models are still usable without calibration."
fi

echo ""
echo "============================================================"
echo "Pipeline complete!"
echo "============================================================"
echo ""
echo "Output files:"
echo "  Models:       $OUT_DIR/PASR_mlp_m*.bin"
echo "  Report:       $OUT_DIR/mlp_classifier_report.json"
if [ -f "$OUT_DIR/calibration_params.json" ]; then
    echo "  Calibration:  $OUT_DIR/calibration_params.json"
fi
echo ""
echo "Deploy to MT5:"
echo "  1. Copy $OUT_DIR/PASR_mlp_m*.bin → MQL5/Files/"
if [ -f "$OUT_DIR/PASR_calibration_params.bin" ]; then
    echo "  2. Copy $OUT_DIR/PASR_calibration_params.bin → MQL5/Files/"
fi
echo "  3. Restart EA or reload chart"
echo ""
