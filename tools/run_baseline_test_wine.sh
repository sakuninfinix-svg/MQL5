#!/bin/bash

###############################################################################
# PASR_MODULAR Baseline Test Runner for Wine
# Uses Windows-style paths for Wine compatibility
###############################################################################

set -e

# Windows paths for Wine
MT5_DIR="C:\\Program Files\\MetaTrader 5"
MT5_DATA_DIR="C:\\Users\\agsi\\AppData\\Roaming\\MetaQuotes\\Terminal\\D0E8209F77C8CF37AD8BF550E51FF075"
EA_FILE="$MT5_DATA_DIR\\MQL5\\Experts\\PASR_MODULAR.mq5"
PRESET_FILE="$MT5_DATA_DIR\\MQL5\\Presets\\PASR_v2_Baseline.set"
OUTPUT_DIR="$MT5_DATA_DIR\\Tester\\Baseline"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo "========================================"
echo "PASR_MODULAR Baseline Test (Wine)"
echo "========================================"
echo ""

# Convert paths for Wine
echo -e "${BLUE}[INFO]${NC} Converting paths for Wine..."

# Create output directory using Linux path first
LINUX_OUTPUT_DIR="/media/agus/40A604FEA604F666/Users/agsi/AppData/Roaming/MetaQuotes/Terminal/D0E8209F77C8CF37AD8BF550E51FF075/Tester/Baseline"
mkdir -p "$LINUX_OUTPUT_DIR"

echo -e "${GREEN}[SUCCESS]${NC} Output directory created"

# Run baseline test with Wine
echo ""
echo -e "${BLUE}[INFO]${NC} Starting baseline test with Wine..."
echo "Symbol: EURUSD"
echo "Timeframe: H1" 
echo "Deposit: 10000 USD"
echo "Model: Every tick"
echo ""

wine "C:\\Program Files\\MetaTrader 5\\metatester64.exe" \
    /config:"$MT5_DATA_DIR\\config\\common.ini" \
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
    echo -e "${BLUE}[INFO]${NC} Results saved to: $LINUX_OUTPUT_DIR"
    echo ""
    echo "To view results, open MetaTrader 5 and check the Strategy Tester results tab."
else
    echo ""
    echo -e "${RED}[ERROR]${NC} Baseline test failed"
    echo "Note: Wine might need additional configuration for MetaTrader 5"
    exit 1
fi