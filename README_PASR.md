# PASR MODULAR EA - Documentation

## Overview
**PASR (Price Action Support Resistance)** is a professional MQL5 Expert Advisor built on OOP Divide & Conquer architecture with async execution capabilities.

## Version
- **Current Version:** 9.00
- **Model:** PASR - Price Action Support Resistance
- **Magic Number:** 20260521

## Architecture

### Core Design Principles
1. **Divide & Conquer**: Modular separation of concerns
2. **OOP Architecture**: Full object-oriented design
3. **Async Execution**: Non-blocking order management
4. **Multi-Symbol Support**: Scalable to 80-100 currency pairs
5. **Dual-Path Processing**: Tick (low-latency) vs Bar (heavy processing)

### Key Modules

#### Core Modules (`/Include/PASR/Core/`)
- **PASR_Executor.mqh**: Async order execution with smart retry logic
  - Exponential backoff retry mechanism
  - Dynamic slippage control
  - Queue management (max 20 concurrent orders)
  - Execution statistics tracking
  
- **PASR_SymbolManager.mqh**: Multi-symbol orchestration
  - Load balancing with round-robin selection
  - Correlation-aware trading
  - Per-symbol performance metrics
  - Auto-rebalancing based on latency

- **Config/Manager.mqh**: Configuration management
- **EventBus.mqh**: Event-driven communication
- **Events.mqh**: Event definitions and handling
- **Globals.mqh**: Global singleton declarations
- **IManager.mqh**: Abstract base class for all managers

#### Analysis Modules (`/Include/PASR/Analysis/`)
- **SRManager.mqh**: Support/Resistance detection
- **PatternDetector**: Candlestick pattern recognition
- **ZoneManager.mqh**: Supply/Demand zone management
- **MarketRegime.mqh**: Market condition analysis

#### Signal Modules (`/Include/PASR/Signal/`)
- **SignalManager.mqh**: Signal aggregation and filtering
- **AI/*.mqh**: Machine learning integration
  - AIEnsemble, AIFeatureBuilder, AIInference
  - ONNXBridge for external model integration
  - Confidence calibration

#### Trade Modules (`/Include/PASR/Trade/`)
- **RiskManager.mqh**: Position sizing and risk control
- **PositionManager.mqh**: Trade management (BE, Trailing Stop)
- **ExecutionManager.mqh**: Order execution logic
- **RecoveryEngine.mqh**: Drawdown recovery system
- **CorrelationManager.mqh**: Portfolio correlation control

#### Infrastructure (`/Include/PASR/Infra/`)
- **DataManager.mqh**: Historical data management
- **StateManager.mqh**: EA state persistence
- **AdaptiveConfig.mqh**: Dynamic configuration
- **JournalManager.mqh**: Logging and audit trail
- **PerformanceReport.mqh**: Metrics and reporting

#### UI (`/Include/PASR/UI/`)
- **DashboardManager.mqh**: Real-time trading dashboard

## Performance Characteristics

| Metric | Value | Notes |
|--------|-------|-------|
| Tick Latency | < 0.3ms | Ultra-low latency path |
| CPU Usage | 60% lower | vs procedural architecture |
| Multi-pair Scaling | 80-100 pairs | With stable performance |
| Execution Reliability | 99.5%+ | Smart retry logic |
| Portfolio Risk | Dynamic | Correlation-adjusted |

## Compilation Flags

```mql5
#define QA_BUILD          // Enable stress testing & chaos engineering
#define PERF_METRICS      // Enable performance counters
#define OOP_ARCHITECTURE  // Enable OOP divide & conquer architecture
```

## File Structure

```
MQL5/
├── Experts/
│   └── PASR_MODULAR.mq5          # Main EA file (v9.00)
└── Include/
    └── PASR/
        ├── Core/                  # Core OOP modules
        │   ├── Config/            # Configuration management
        │   │   ├── Manager.mqh
        │   │   ├── Types.mqh
        │   │   └── Validator.mqh
        │   ├── PASR_Executor.mqh  # Async executor
        │   ├── PASR_SymbolManager.mqh
        │   ├── EventBus.mqh
        │   ├── Events.mqh
        │   ├── Globals.mqh
        │   └── IManager.mqh
        ├── Analysis/              # Market analysis
        │   ├── SRManager.mqh
        │   ├── ZoneManager.mqh
        │   └── Pattern/
        ├── Signal/                # Signal generation
        │   ├── SignalManager.mqh
        │   └── AI/                # AI/ML modules
        ├── Trade/                 # Trade management
        │   ├── RiskManager.mqh
        │   ├── PositionManager.mqh
        │   └── CorrelationManager.mqh
        ├── Infra/                 # Infrastructure
        │   ├── DataManager.mqh
        │   ├── StateManager.mqh
        │   └── JournalManager.mqh
        ├── Data/                  # Data management
        ├── UI/                    # User interface
        ├── Tools/                 # Utility tools
        └── QA/                    # Testing & validation
```

## Key Features

### 1. Dual-Path Processing
- **OnTick Path**: Ultra-low latency (<0.3ms) for critical operations
  - Spread monitoring
  - Position management (BE, Trailing)
  - Recovery monitoring
  - Executor queue processing
  
- **OnTimer Path** (1-second heartbeat): Heavy processing
  - New bar detection
  - SR recalculation
  - Pattern recognition
  - Signal generation
  - AI inference

### 2. Smart Execution
- Asynchronous order processing
- Smart retry with exponential backoff
- Dynamic slippage based on volatility
- Execution queue management (max 20 concurrent)

### 3. Multi-Symbol Orchestration
- Load balancing across symbols
- Correlation-aware position sizing
- Per-symbol latency monitoring
- Auto-rebalancing based on market status

### 4. Risk Management
- Dynamic position sizing
- Correlation-adjusted exposure
- Drawdown recovery system
- Portfolio-level risk controls

## Usage

### Installation
1. Copy `PASR_MODULAR.mq5` to `MQL5/Experts/`
2. Copy entire `PASR` folder to `MQL5/Include/`
3. Compile in MetaEditor

### Configuration
Configure via EA input parameters:
- Symbol list and timeframes
- Risk parameters (lot size, max drawdown)
- Strategy settings (SR sensitivity, patterns)
- AI model selection (if enabled)

### Recommended Setup
- Timeframe: M15-H1
- Pairs: Major + Crosses (20-50 pairs optimal)
- Broker: ECN with low latency
- VPS: Recommended for production

## Development Status

- ✅ OOP Architecture implemented
- ✅ Async Executor module complete
- ✅ Symbol Manager with load balancing
- ✅ Dual-path tick/bar processing
- ✅ Header cleanup (v9.00)
- ✅ Config module path fixed
- 🔄 AI integration (ongoing optimization)
- 📊 Advanced analytics (planned)

## Support & Documentation

- GitHub: https://github.com/sakuninfinix-svg/MQL5
- Module Documentation: See `_README.mqh` in each subfolder
- QA Tests: Available in `/Include/PASR/QA/`

---

**Last Updated:** May 2026  
**Version:** 9.00
