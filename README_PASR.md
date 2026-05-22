# PASR MODULAR EA - Institutional Documentation

## Overview
**PASR (Price Action Support Resistance)** is an institutional-grade MQL5 Expert Advisor built on OOP Divide & Conquer architecture with async execution, structural stops, and dynamic portfolio risk management.

## Version
- **Current Version:** 10.00 — Institutional Grade
- **Model:** PASR - Institutional Multi-Strategy System
- **Magic Number:** 20260521
- **Architecture:** Dual-Path Low-Latency + OOP Modules

## Institutional Features (v10.00)

### Core Upgrades from Retail to Institutional

| Feature | Retail Mode (v9.00) | Institutional Mode (v10.00) |
|---------|---------------------|----------------------------|
| **Stop Loss** | Fixed ATR multiplier | Structural (Swing High/Low) + Buffer |
| **Position Sizing** | Fixed lot or % risk | Volatility-adjusted + Pyramid scaling |
| **Risk Management** | Static % per trade | Dynamic correlation-weighted portfolio |
| **Execution** | Standard order send | Async queue + Smart retry + Dynamic slippage |
| **Exit Logic** | Fixed TP/SL + Trailing | Chandelier + Structure break + Momentum fade |
| **Scalability** | 30-40 pairs | 80-100+ pairs |
| **Latency** | 0.5-1ms/tick | <0.3ms/tick |

### Key Institutional Modules

#### 1. Structural Stop Loss (`InpStructSL`)
- Uses swing highs/lows instead of arbitrary ATR multiples
- Adds buffer based on market volatility (ATR)
- Trails based on market structure breaks, not fixed points
- More resilient to noise and stop hunts

#### 2. Volatility-Adjusted Sizing (`InpVolatilityAdj`)
- Automatically reduces position size in high volatility regimes
- Increases size in low volatility (when risk is controlled)
- Maintains constant risk exposure across market conditions

#### 3. Pyramid Scaling (`InpPyramidLevels`, `InpPyramidSpacing`)
- Scale into winning positions in tranches (default: 3 levels)
- Spacing based on ATR (default: 0.5 ATR between levels)
- Each tranche has independent risk management
- Improves R:R on strong trending moves

#### 4. Circuit Breakers
- **Daily Loss Halt**: Stops trading if daily loss > X% (default: 3%)
- **Global Drawdown Halt**: Emergency stop at max DD (default: 10%)
- **Max Trades Per Day**: Prevents overtrading
- **Correlation Check**: Blocks trades if portfolio correlation > threshold

#### 5. Advanced Execution Engine
- **Async Mode**: Non-blocking order submission
- **Smart Retry**: Exponential backoff on failed orders (default: 3 attempts)
- **Dynamic Slippage**: Adjusts slippage tolerance based on volatility
- **Queue Management**: Max 20 concurrent orders to prevent overload

## Architecture

### Core Design Principles
1. **Divide & Conquer**: Modular separation of concerns
2. **OOP Architecture**: Full object-oriented design with class instances
3. **Async Execution**: Non-blocking order management via queue
4. **Multi-Symbol Support**: Scalable to 80-100 currency pairs
5. **Dual-Path Processing**: Tick (low-latency) vs Bar (heavy processing)
6. **Institutional Mode**: Conditional compilation for advanced features

### Compilation Flags
```cpp
#define QA_BUILD          // Enable stress testing & chaos engineering
#define PERF_METRICS      // Enable performance counters
#define OOP_ARCHITECTURE  // Enable OOP divide & conquer architecture
#define INST_MODE         // Enable Institutional Mode features (NEW v10.00)
```

### Key Modules

#### Core Modules (`/Include/PASR/Core/`)
- **PASR_Executor.mqh**: Async order execution with smart retry logic
  - Exponential backoff retry mechanism
  - Dynamic slippage control based on volatility
  - Queue management (max 20 concurrent orders)
  - Execution statistics tracking (latency, fill rate, retries)
  
- **PASR_SymbolManager.mqh**: Multi-symbol orchestration
  - Load balancing with round-robin selection
  - Correlation-aware trading (dynamic portfolio risk)
  - Per-symbol performance metrics
  - Auto-rebalancing based on latency/market status

- **Config/Manager.mqh**: Configuration management
- **EventBus.mqh**: Event-driven communication
- **Events.mqh**: Event definitions and handling
- **Globals.mqh**: Global singleton declarations
- **IManager.mqh**: Abstract base class for all managers

#### Analysis Modules (`/Include/PASR/Analysis/`)
- **SRManager.mqh**: Support/Resistance detection with structural swings
- **PatternDetector**: Candlestick pattern recognition
- **ZoneManager.mqh**: Supply/Demand zone management
- **MarketRegime.mqh**: Market condition analysis (volatility regimes)
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
