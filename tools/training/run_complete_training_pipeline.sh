#!/bin/bash
# ============================================================================
# PASR Complete Training Pipeline
# ============================================================================
# This script provides a complete workflow for:
# 1. Data export from MT5
# 2. AI/ML model training (MLP + GBR)
# 3. Parameter optimization for profitable trading
# 4. Validation and deployment
#
# Target: Profit Factor >= 1.5, Daily trading >= 10 trade/day
#
# AI/ML Components:
# - MLP (Multi-Layer Perceptron): 34->64->32->1 architecture
# - GBR (Gradient Boosting Regressor): Multi-timeframe analysis
# - Feature extraction: 34 runtime-compatible features
# - Auto-retrain: Online learning capability
# ============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$(dirname "$SCRIPT_DIR")"
MQL5_DIR="$(dirname "$TOOLS_DIR")"
OUTPUT_DIR="$MQL5_DIR/tools/output"

# MT5 Configuration
MT5_WINE_PREFIX="/home/agus/.mt5"
MT5_TERMINAL="$MT5_WINE_PREFIX/drive_c/Program Files/MetaTrader 5"
MT5_METAEDITOR="$MT5_TERMINAL/MetaEditor64.exe"
MT5_TESTER="$MT5_TERMINAL/metatester64.exe"

# EA Configuration
EA_PATH="$MQL5_DIR/Experts/PASR_PRERELEASE.mq5"
DATA_EXPORTER="$MQL5_DIR/Experts/PASR_DATA_EXPORTER.mq5"

# Default parameters
SYMBOL="${SYMBOL:-EURUSD}"
TIMEFRAME="${TIMEFRAME:-M15}"
MONTHS="${MONTHS:-12}"
MAX_ITERATIONS="${MAX_ITERATIONS:-50}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ============================================================================
# Step 1: Data Export from MT5
# ============================================================================
step1_export_data() {
    log_info "Step 1/5: Exporting data from MT5..."

    # Check if data exporter exists
    if [ ! -f "$DATA_EXPORTER" ]; then
        log_error "Data exporter not found: $DATA_EXPORTER"
        return 1
    fi

    # Compile data exporter
    log_info "Compiling PASR_DATA_EXPORTER.mq5..."
    WINEPREFIX="$MT5_WINE_PREFIX" wine "$MT5_METAEDITOR" "/compile:$DATA_EXPORTER" "/close"

    if [ $? -ne 0 ]; then
        log_error "Failed to compile data exporter"
        return 1
    fi

    log_success "Data exporter compiled successfully"

    # Run data exporter in MT5 Strategy Tester
    log_info "Running data exporter in MT5 Strategy Tester..."
    log_warning "This step requires manual execution in MT5:"
    log_warning "1. Open MT5 Strategy Tester"
    log_warning "2. Select PASR_DATA_EXPORTER expert"
    log_warning "3. Symbol: $SYMBOL, Period: $TIMEFRAME"
    log_warning "4. Date range: Last $MONTHS months"
    log_warning "5. Enable 'Export OHLCV' in EA inputs"
    log_warning "6. Run backtest"
    log_warning "7. Copy output files to $OUTPUT_DIR/"

    # Check if export files exist
    if [ -f "$OUTPUT_DIR/PASR_trades_export.csv" ] && [ -f "$OUTPUT_DIR/PASR_ohlcv_export.csv" ]; then
        log_success "Export files found"
        return 0
    else
        log_warning "Export files not found. Please complete manual export step."
        read -p "Press Enter when export files are ready..."

        if [ -f "$OUTPUT_DIR/PASR_trades_export.csv" ] && [ -f "$OUTPUT_DIR/PASR_ohlcv_export.csv" ]; then
            log_success "Export files found"
            return 0
        else
            log_error "Export files still not found"
            return 1
        fi
    fi
}

# ============================================================================
# Step 2: AI Model Training
# ============================================================================
step2_train_ai() {
    log_info "Step 2/5: Training AI models..."

    # Check if training data exists
    if [ ! -f "$OUTPUT_DIR/PASR_trades_export.csv" ]; then
        log_error "Trade export not found. Run Step 1 first."
        return 1
    fi

    if [ ! -f "$OUTPUT_DIR/PASR_ohlcv_export.csv" ]; then
        log_error "OHLCV export not found. Run Step 1 first."
        return 1
    fi

    # Run the existing training pipeline
    log_info "Running ML training pipeline..."
    bash "$SCRIPT_DIR/run_pipeline.sh"

    if [ $? -eq 0 ]; then
        log_success "AI models trained successfully"

        # Copy trained models to MQL5/Files/
        if [ -f "$OUTPUT_DIR/PASR_mlp_m0.bin" ]; then
            cp "$OUTPUT_DIR/PASR_mlp_m0.bin" "$MQL5_DIR/Files/"
            log_success "AI model copied to MQL5/Files/"
        fi

        return 0
    else
        log_error "AI training failed"
        return 1
    fi
}

# ============================================================================
# Step 3: Parameter Optimization
# ============================================================================
step3_optimize_parameters() {
    log_info "Step 3/5: Optimizing EA parameters..."

    # Check if Python script exists
    if [ ! -f "$SCRIPT_DIR/optimize_pasr_parameters.py" ]; then
        log_error "Optimization script not found"
        return 1
    fi

    # Make script executable
    chmod +x "$SCRIPT_DIR/optimize_pasr_parameters.py"

    # Run optimization
    log_info "Running parameter optimization (this may take a while)..."
    python3 "$SCRIPT_DIR/optimize_pasr_parameters.py" \
        --symbol "$SYMBOL" \
        --timeframe "$TIMEFRAME" \
        --months "$MONTHS" \
        --max-iterations "$MAX_ITERATIONS"

    if [ $? -eq 0 ]; then
        log_success "Parameter optimization completed"

        # Check if best configuration was found
        if [ -f "$OUTPUT_DIR/optimization_results.json" ]; then
            log_success "Optimization results saved"
            return 0
        else
            log_warning "No optimization results found"
            return 1
        fi
    else
        log_error "Parameter optimization failed"
        return 1
    fi
}

# ============================================================================
# Step 4: Generate Optimized Set File
# ============================================================================
step4_generate_set_file() {
    log_info "Step 4/5: Generating optimized .set file..."

    if [ ! -f "$OUTPUT_DIR/optimization_results.json" ]; then
        log_error "Optimization results not found. Run Step 3 first."
        return 1
    fi

    # Extract best parameters from results
    log_info "Extracting best parameters..."

    # Use Python to extract and generate set file
    python3 << EOF
import json
import sys

try:
    with open('$OUTPUT_DIR/optimization_results.json', 'r') as f:
        results = json.load(f)

    best_config = results.get('best_config', {})
    params = best_config.get('params', {})

    if not params:
        print("ERROR: No parameters found in optimization results", file=sys.stderr)
        sys.exit(1)

    # Generate .set file
    set_content = "; PASR Optimized Configuration\n"
    set_content += f"; Generated: {results.get('timestamp', 'Unknown')}\n"
    set_content += f"; Optimization Score: {best_config.get('score', 0):.3f}\n\n"

    for key, value in params.items():
        if isinstance(value, bool):
            value = 1 if value else 0
        set_content += f"{key}={value}\n"

    set_file = '$OUTPUT_DIR/PASR_OPTIMIZED.set'
    with open(set_file, 'w') as f:
        f.write(set_content)

    print(f"Optimized .set file generated: {set_file}")

    # Print summary
    metrics = best_config.get('metrics', {})
    print("\nOptimization Summary:")
    print(f"  Profit Factor: {metrics.get('profit_factor', 0):.2f}")
    print(f"  Daily Trades: {metrics.get('daily_trades', 0):.1f}")
    print(f"  Drawdown: {metrics.get('drawdown_pct', 0):.1f}%")
    print(f"  Win Rate: {metrics.get('win_rate', 0):.1f}%")

except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
EOF

    if [ $? -eq 0 ]; then
        log_success "Optimized .set file generated"
        return 0
    else
        log_error "Failed to generate .set file"
        return 1
    fi
}

# ============================================================================
# Step 5: Validation and Deployment
# ============================================================================
step5_validate_deploy() {
    log_info "Step 5/5: Validation and deployment..."

    # Compile EA with optimized parameters
    log_info "Compiling PASR_PRERELEASE.mq5 with optimized parameters..."

    if [ ! -f "$OUTPUT_DIR/PASR_OPTIMIZED.set" ]; then
        log_error "Optimized .set file not found. Run Step 4 first."
        return 1
    fi

    # Compile EA
    WINEPREFIX="$MT5_WINE_PREFIX" wine "$MT5_METAEDITOR" "/compile:$EA_PATH" "/close"

    if [ $? -ne 0 ]; then
        log_error "Failed to compile EA"
        return 1
    fi

    log_success "EA compiled successfully"

    # Copy files for deployment
    log_info "Preparing deployment files..."

    DEPLOY_DIR="$OUTPUT_DIR/deployment"
    mkdir -p "$DEPLOY_DIR"

    # Copy EA
    cp "$EA_PATH" "$DEPLOY_DIR/"

    # Copy optimized set file
    cp "$OUTPUT_DIR/PASR_OPTIMIZED.set" "$DEPLOY_DIR/"

    # Copy AI models if they exist
    if [ -f "$MQL5_DIR/Files/PASR_mlp_m0.bin" ]; then
        cp "$MQL5_DIR/Files/PASR_mlp_m0.bin" "$DEPLOY_DIR/"
    fi

    # Generate deployment instructions
    cat > "$DEPLOY_DIR/DEPLOYMENT_INSTRUCTIONS.txt" << EOF
PASR PRERELEASE - Optimized Configuration Deployment
====================================================

Optimization Results:
- Symbol: $SYMBOL
- Timeframe: $TIMEFRAME
- Period: $MONTHS months
- Target: PF >= 1.5, Daily trading >= 10 trade/day

Deployment Steps:
1. Copy PASR_PRERELEASE.mq5 to MT5 Experts folder
2. Copy PASR_OPTIMIZED.set to MT5 Experts folder (same location as EA)
3. Copy PASR_mlp_m0.bin to MT5 Files folder (if using AI)
4. In MT5, open PASR_PRERELEASE properties
5. Load PASR_OPTIMIZED.set
6. Enable AI if trained models are available
7. Test on demo account before live trading

Important Notes:
- This configuration is optimized for historical data
- Forward testing is recommended before live deployment
- Monitor performance and re-optimize periodically
- Risk management parameters should be adjusted based on account size
EOF

    log_success "Deployment files prepared in $DEPLOY_DIR"

    # Generate final report
    cat > "$OUTPUT_DIR/TRAINING_PIPELINE_REPORT.txt" << EOF
PASR COMPLETE TRAINING PIPELINE - FINAL REPORT
==============================================

Execution Date: $(date)
Symbol: $SYMBOL
Timeframe: $TIMEFRAME
Optimization Period: $MONTHS months

Pipeline Steps Completed:
✓ Step 1: Data Export from MT5
✓ Step 2: AI Model Training
✓ Step 3: Parameter Optimization
✓ Step 4: Optimized Configuration Generation
✓ Step 5: Validation and Deployment

Target Criteria:
- Profit Factor >= 1.5
- Daily Trading >= 10 trade/day
- Maximum Drawdown <= 15%

Files Generated:
- $OUTPUT_DIR/PASR_trades_export.csv (MT5 trade data)
- $OUTPUT_DIR/PASR_ohlcv_export.csv (MT5 OHLCV data)
- $OUTPUT_DIR/MT5_Training_Data.csv (AI training data)
- $OUTPUT_DIR/PASR_mlp_m0.bin (Trained AI model)
- $OUTPUT_DIR/optimization_results.json (Optimization results)
- $OUTPUT_DIR/PASR_OPTIMIZED.set (Optimized parameters)
- $OUTPUT_DIR/deployment/ (Deployment package)

Next Steps:
1. Review optimization results in $OUTPUT_DIR/optimization_summary.txt
2. Test optimized configuration on demo account
3. Monitor performance for 2-4 weeks
4. Re-optimize if performance degrades
5. Deploy to live account only after successful validation

Contact: Check training/README.md for detailed documentation
EOF

    log_success "Final report generated: $OUTPUT_DIR/TRAINING_PIPELINE_REPORT.txt"

    return 0
}

# ============================================================================
# Main Menu
# ============================================================================
show_menu() {
    echo ""
    echo "============================================================"
    echo "PASR Complete Training Pipeline"
    echo "============================================================"
    echo "Configuration:"
    echo "  Symbol: $SYMBOL"
    echo "  Timeframe: $TIMEFRAME"
    echo "  Period: $MONTHS months"
    echo "  Max Iterations: $MAX_ITERATIONS"
    echo ""
    echo "Target: Profit Factor >= 1.5, Daily trading >= 1 trade/day"
    echo ""
    echo "Options:"
    echo "  1) Run complete pipeline (all steps)"
    echo "  2) Step 1: Export data from MT5"
    echo "  3) Step 2: Train AI models"
    echo "  4) Step 3: Optimize parameters"
    echo "  5) Step 4: Generate optimized .set file"
    echo "  6) Step 5: Validate and deploy"
    echo "  7) Configure parameters"
    echo "  0) Exit"
    echo "============================================================"
}

configure_parameters() {
    echo ""
    echo "Configure Parameters:"
    echo "====================="

    read -p "Symbol [$SYMBOL]: " input
    SYMBOL="${input:-$SYMBOL}"

    read -p "Timeframe [$TIMEFRAME]: " input
    TIMEFRAME="${input:-$TIMEFRAME}"

    read -p "Period in months [$MONTHS]: " input
    MONTHS="${input:-$MONTHS}"

    read -p "Max iterations [$MAX_ITERATIONS]: " input
    MAX_ITERATIONS="${input:-$MAX_ITERATIONS}"

    echo ""
    echo "New Configuration:"
    echo "  Symbol: $SYMBOL"
    echo "  Timeframe: $TIMEFRAME"
    echo "  Period: $MONTHS months"
    echo "  Max Iterations: $MAX_ITERATIONS"
}

# ============================================================================
# Main Execution
# ============================================================================
main() {
    # Create output directory
    mkdir -p "$OUTPUT_DIR"

    while true; do
        show_menu
        read -p "Select option: " choice

        case $choice in
            1)
                log_info "Running complete pipeline..."
                step1_export_data && \
                step2_train_ai && \
                step3_optimize_parameters && \
                step4_generate_set_file && \
                step5_validate_deploy

                if [ $? -eq 0 ]; then
                    log_success "Complete pipeline finished successfully!"
                    echo ""
                    echo "Check results in: $OUTPUT_DIR"
                else
                    log_error "Pipeline failed at some step"
                fi
                ;;
            2)
                step1_export_data
                ;;
            3)
                step2_train_ai
                ;;
            4)
                step3_optimize_parameters
                ;;
            5)
                step4_generate_set_file
                ;;
            6)
                step5_validate_deploy
                ;;
            7)
                configure_parameters
                ;;
            0)
                log_info "Exiting..."
                exit 0
                ;;
            *)
                log_error "Invalid option"
                ;;
        esac

        read -p "Press Enter to continue..."
    done
}

# Run main function
main
