#!/bin/bash

###############################################################################
# PASR_MODULAR Optimization Runner
# Automated systematic parameter optimization for MT5 Strategy Tester
###############################################################################

set -e  # Exit on error

# Configuration paths (auto-detect from script location)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLS_DIR="$SCRIPT_DIR"
MQL5_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$(cd "$MQL5_DIR/.." && pwd)"
MT5_DIR="/home/agus/.mt5/drive_c/Program Files/MetaTrader 5"
EA_FILE="$MQL5_DIR/Experts/PASR_MODULAR.mq5"
PRESETS_DIR="$MQL5_DIR/Presets"
TESTER_DIR="$DATA_DIR/Tester"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Check dependencies
check_dependencies() {
    log_info "Checking dependencies..."
    
    if ! command -v wine &> /dev/null; then
        log_error "Wine is not installed. Please install Wine first."
        exit 1
    fi
    
    if [ ! -f "$MT5_DIR/terminal64.exe" ]; then
        log_error "MT5 terminal not found at $MT5_DIR/terminal64.exe"
        exit 1
    fi
    
    if [ ! -f "$MT5_DIR/metatester64.exe" ]; then
        log_error "MT5 tester not found at $MT5_DIR/metatester64.exe"
        exit 1
    fi
    
    if [ ! -f "$EA_FILE" ]; then
        log_error "EA file not found at $EA_FILE"
        exit 1
    fi
    
    log_success "All dependencies check passed"
}

# Create directories
setup_directories() {
    log_info "Setting up directories..."
    
    mkdir -p "$TESTER_DIR/Baseline"
    mkdir -p "$TESTER_DIR/Risk_Optimization"  
    mkdir -p "$TESTER_DIR/Market_Optimization"
    mkdir -p "$TESTER_DIR/Pattern_Optimization"
    mkdir -p "$TOOLS_DIR/reports"
    
    log_success "Directories created"
}

# Compile the EA
compile_ea() {
    log_info "Compiling PASR_MODULAR EA..."
    
    wine "$MT5_DIR/MetaEditor64.exe" /compile:"$EA_FILE" /close
    
    if [ $? -eq 0 ]; then
        log_success "EA compiled successfully"
    else
        log_warning "EA compilation had issues, continuing anyway..."
    fi
}

# Run single test
run_single_test() {
    local test_name=$1
    local preset_file=$2
    local output_dir=$3
    
    log_info "Running $test_name..."
    
    local cmd="wine \"$MT5_DIR/metatester64.exe\" \
        /config:\"$MT5_DATA_DIR/config/common.ini\" \
        /profile:Default \
        /expert:\"$EA_FILE\" \
        /symbol:EURUSD \
        /period:H1 \
        /deposit:10000 \
        /currency:USD \
        /leverage:100 \
        /model:0 \
        /spread:10 \
        /optimization_mode:0 \
        /set_file:\"$preset_file\" \
        /tester:\"$output_dir\" \
        /portable"
    
    eval $cmd
    
    if [ $? -eq 0 ]; then
        log_success "$test_name completed"
    else
        log_error "$test_name failed"
        return 1
    fi
}

# Run optimization
run_optimization() {
    local phase_name=$1
    local preset_file=$2
    local output_dir=$3
    
    log_info "Running $phase_name optimization..."
    
    local cmd="wine \"$MT5_DIR/metatester64.exe\" \
        /config:\"$MT5_DATA_DIR/config/common.ini\" \
        /profile:Default \
        /expert:\"$EA_FILE\" \
        /symbol:EURUSD \
        /period:H1 \
        /deposit:10000 \
        /currency:USD \
        /leverage:100 \
        /model:0 \
        /spread:10 \
        /optimization_mode:2 \
        /optimization_criteria:0 \
        /set_file:\"$preset_file\" \
        /tester:\"$output_dir\" \
        /forward:false \
        /portable"
    
    eval $cmd
    
    if [ $? -eq 0 ]; then
        log_success "$phase_name optimization completed"
    else
        log_error "$phase_name optimization failed"
        return 1
    fi
}

# Parse results and generate report
generate_report() {
    log_info "Generating optimization report..."
    
    # This is a placeholder for actual result parsing
    # MT5 generates HTML/XML reports that need to be parsed
    
    local report_file="$TOOLS_DIR/reports/optimization_report_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" << EOF
PASR_MODULAR Optimization Report
=================================
Date: $(date)
EA Version: 2.15.0

Optimization Phases Completed:
1. Baseline Test
2. Risk Parameter Optimization  
3. Market Parameter Optimization
4. Pattern Parameter Optimization

Results Summary:
- Total tests run: [To be parsed from MT5 results]
- Best fitness score: [To be parsed from MT5 results]
- Best parameters: [To be parsed from MT5 results]

Performance Metrics:
- Profit: [To be parsed]
- Profit Factor: [To be parsed]
- Recovery Factor: [To be parsed]
- Sharpe Ratio: [To be parsed]
- Maximum Drawdown: [To be parsed]
- Total Trades: [To be parsed]

Note: This is a template report. Actual results need to be parsed from MT5 output files.
EOF
    
    log_success "Report generated at $report_file"
}

# Main execution
main() {
    echo "======================================"
    echo "PASR_MODULAR Optimization Runner"
    echo "======================================"
    echo ""
    
    check_dependencies
    setup_directories
    
    # Optional: Compile EA
    read -p "Compile EA before testing? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        compile_ea
    fi
    
    # Run baseline test
    log_info "Starting optimization process..."
    run_single_test "Baseline Test" \
        "$PRESETS_DIR/PASR_EPIC_MASTER.set" \
        "$TESTER_DIR/Baseline"
    
    # Ask user for optimization approach
    echo ""
    log_info "Select optimization approach:"
    echo "1) Full systematic optimization (Risk -> Market -> Pattern)"
    echo "2) Risk parameters only"
    echo "3) Market parameters only"  
    echo "4) Pattern parameters only"
    echo "5) Skip optimization, generate report from existing results"
    
    read -p "Enter choice (1-5): " choice
    
    case $choice in
        1)
            log_info "Running full systematic optimization..."
            run_optimization "Risk_Optimization" \
                "$PRESETS_DIR/PASR_EPIC_MASTER.set" \
                "$TESTER_DIR/Risk_Optimization"
            
            run_optimization "Market_Optimization" \
                "$PRESETS_DIR/PASR_EPIC_MASTER.set" \
                "$TESTER_DIR/Market_Optimization"
            
            run_optimization "Pattern_Optimization" \
                "$PRESETS_DIR/PASR_EPIC_MASTER.set" \
                "$TESTER_DIR/Pattern_Optimization"
            ;;
        2)
            run_optimization "Risk_Optimization" \
                "$PRESETS_DIR/PASR_EPIC_MASTER.set" \
                "$TESTER_DIR/Risk_Optimization"
            ;;
        3)
            run_optimization "Market_Optimization" \
                "$PRESETS_DIR/PASR_EPIC_MASTER.set" \
                "$TESTER_DIR/Market_Optimization"
            ;;
        4)
            run_optimization "Pattern_Optimization" \
                "$PRESETS_DIR/PASR_EPIC_MASTER.set" \
                "$TESTER_DIR/Pattern_Optimization"
            ;;
        5)
            log_info "Skipping optimization, parsing existing results..."
            ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac
    
    # Generate report
    generate_report
    
    echo ""
    log_success "Optimization process completed!"
    log_info "Check the reports directory for detailed results"
}

# Run main function
main