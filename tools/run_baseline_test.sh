#!/bin/bash

###############################################################################
# PASR_MODULAR Baseline Test Runner
# Runs single baseline test without user interaction
###############################################################################

set -e

# Configuration paths
MT5_DIR="/media/agus/40A604FEA604F666/Program Files/MetaTrader 5"
MT5_DATA_DIR="/media/agus/40A604FEA604F666/Users/agsi/AppData/Roaming/MetaQuotes/Terminal/D0E8209F77C8CF37AD8BF550E51FF075"
EA_FILE="$MT5_DATA_DIR/MQL5/Experts/PASR_MODULAR.mq5"
PRESET_FILE="$MT5_DATA_DIR/MQL5/Presets/PASR_v2_Baseline.set"
OUTPUT_DIR="$MT5_DATA_DIR/Tester/Baseline"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo "========================================"
echo "PASR_MODULAR Baseline Test"
echo "========================================"
echo ""

# Check files
echo -e "${BLUE}[INFO]${NC} Checking required files..."
if [ ! -f "$MT5_DIR/metatester64.exe" ]; then
    echo -e "${RED}[ERROR]${NC} MT5 tester not found"
    exit 1
fi

if [ ! -f "$EA_FILE" ]; then
    echo -e "${RED}[ERROR]${NC} EA file not found"
    exit 1
fi

if [ ! -f "$PRESET_FILE" ]; then
    echo -e "${RED}[ERROR]${NC} Preset file not found"
    exit 1
fi

echo -e "${GREEN}[SUCCESS]${NC} All files found"

# Create output directory
mkdir -p "$OUTPUT_DIR"
echo -e "${BLUE}[INFO]${NC} Output directory: $OUTPUT_DIR"

# Run baseline test
echo ""
echo -e "${BLUE}[INFO]${NC} Starting baseline test..."
echo "Symbol: EURUSD"
echo "Timeframe: H1" 
echo "Deposit: 10000 USD"
echo "Model: Every tick"
echo ""

wine "$MT5_DIR/metatester64.exe" \
    /config:"$MT5_DATA_DIR/config/common.ini" \
    /profile:Default \
    /expert:"$EA_FILE" \
    /symbol:EURUSD \
    /period:H1 \
    /deposit:10000 \
    /currency:USD \
    /leverage:100 \
    /model:0 \
    /spread:10 \
    /optimization_mode:0 \
    /set_file:"$PRESET_FILE" \
    /tester:"$OUTPUT_DIR" \
    /portable

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}[SUCCESS]${NC} Baseline test completed"
    echo -e "${BLUE}[INFO]${NC} Results saved to: $OUTPUT_DIR"
    echo ""
    echo "To view results, open MetaTrader 5 and check the Strategy Tester results tab."
else
    echo ""
    echo -e "${RED}[ERROR]${NC} Baseline test failed"
    exit 1
fi