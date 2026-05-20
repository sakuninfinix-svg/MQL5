# PASR Framework V4.00 - Refactored Edition

[![Version](https://img.shields.io/badge/version-4.00--refactored-blue.svg)]()
[![MQL5](https://img.shields.io/badge/platform-MQL5-green.svg)]()
[![License](https://img.shields.io/badge/license-Proprietary-red.svg)]()
[![Status](https://img.shields.io/badge/status-production--ready-brightgreen.svg)]()

## 🎯 Overview

**PASR (Professional Automated SR) V4.00** adalah framework trading algoritmik MQL5 yang telah di-refactor dengan **folder structure** yang terorganisir, mengimplementasikan **Supply & Demand** strategy dengan arsitektur event-driven yang modern, scalable, dan high-performance.

### ✨ What's New in V4.00

📁 **Organized Folder Structure** - Clear separation by layer and responsibility  
⚡ **Advanced Optimizations** - OPT-010 to OPT-016 implemented  
🧪 **Dedicated Testing** - Unit testing framework & audit tools  
📚 **Comprehensive Docs** - All documentation in one place  
🔧 **Better Maintainability** - Easier navigation and updates  

---

## 📁 New Folder Structure (V4.00)

```
/Include/PASR/
│
├── 📂 Core/                    # Layer 0-2: Core Framework
│   ├── 0.EventBus.mqh          # Event-driven core (OPT-010 to OPT-013)
│   ├── 1.Events.mqh            # Event definitions (all types)
│   ├── 2.Config.Types.mqh      # Configuration data structures
│   ├── 2.Config.Manager.mqh    # Configuration management
│   ├── Globals.mqh             # Global utilities & constants
│   ├── IManager.mqh            # Base manager interface
│   └── PASR.mqh                # Main include file (use this!)
│
├── 📂 Data/                    # Layer 3-4: Data Management
│   ├── 3.MarketManager.mqh     # Market data & tick handling
│   ├── 3.ZoneManager.mqh       # Supply/demand zone detection
│   └── 4.SRManager.mqh         # Support/resistance calculation
│
├── 📂 Strategy/                # Layer 5-6: Strategy Logic
│   ├── 5.SignalManager.mqh     # Signal generation engine
│   ├── 6.ExecutionManager.mqh  # Order execution & position mgmt
│   └── 📂 AI/                  # AI/ML Components (Layer 7)
│       ├── 7.AIManager.mqh     # AI orchestration
│       ├── AIFeatureBuilder.mqh # Feature engineering
│       ├── AIInference.mqh     # Model inference
│       ├── AIOrchestrator.mqh  # AI workflow coordination
│       ├── AITrainer.mqh       # Online learning
│       └── AITypes.mqh         # AI data structures
│
├── 📂 Infrastructure/          # Layer 8-12: Supporting Services
│   ├── 8.RecoveryManager.mqh   # Recovery trading logic
│   ├── 9.PatternManager.mqh    # Pattern recognition engine
│   ├── 10.DataManager.mqh      # Data hub & indicator caching
│   ├── 11.DashboardManager.mqh # Dashboard UI components
│   └── 12.MarketRegime.mqh     # Market regime detection
│
├── 📂 Optimizations/           # Performance Modules
│   ├── PASR.Optimizations.mqh    # OPT-010 to OPT-013
│   │   ├── CStringPool              # String pooling (zero allocation)
│   │   ├── CPreAllocatedArray       # Array pre-allocation
│   │   ├── CRITICAL_FUNCTION        # Inline macros
│   │   └── CacheAligned structs     # 64-byte alignment
│   ├── PASR.BatchProcessor.mqh     # OPT-014: Batch processing
│   ├── PASR.MemoryPool.mqh         # OPT-015: Object pooling
│   └── PASR.Branchless.mqh         # OPT-016: Branchless programming
│
├── 📂 Testing/                 # Quality Assurance
│   ├── PASR.Test.mqh           # Unit testing framework
│   └── PASR.Audit.mqh          # Code quality auditor
│
├── 📂 Documentation/           # All Documentation
│   ├── README.md               # Original README (v1.00)
│   ├── README_V4.md            # This file - V4.00 guide
│   ├── QUICKSTART.md           # Getting started (5 min)
│   ├── DOCUMENTATION.md        # Architecture deep dive
│   ├── REFACTORING_GUIDE.md    # Migration & refactoring guide
│   ├── IMPROVEMENT_ROADMAP.md  # 90-day roadmap
│   ├── PERFORMANCE_OPTIMIZATION.md # Performance tuning
│   ├── OPTIMIZATION_REPORT.md  # V3.00 optimization report
│   └── OPTIMIZATION_PHASE2.md  # Phase 2 optimizations
│
└── 📂 Scripts/                 # Utility Scripts
    ├── check_circular.sh       # Circular dependency checker
    └── refactor_includes.sh    # Automated include refactoring
```

---

## 🚀 Quick Start (V4.00)

### Option 1: Single Include (Recommended)
```mql5
// In your EA file:
#include <PASR/Core/PASR.mqh>

int OnInit()
{
   // PASR framework automatically initialized
   return INIT_SUCCEEDED;
}
```

### Option 2: Selective Includes
```mql5
// Include only what you need:
#include <PASR/Core/0.EventBus.mqh>
#include <PASR/Core/1.Events.mqh>
#include <PASR/Strategy/5.SignalManager.mqh>
```

### Option 3: With Optimizations
```mql5
// Full framework with optimizations:
#include <PASR/Core/PASR.mqh>
#include <PASR/Optimizations/PASR.Optimizations.mqh>
#include <PASR/Optimizations/PASR.BatchProcessor.mqh>

int OnInit()
{
   COptimizationInitializer::InitializeAll();
   return INIT_SUCCEEDED;
}
```

---

## 📊 Performance Benchmarks (V4.00)

| Metric | V1.00 | V3.00 | V4.00 (Refactored) | Improvement |
|--------|-------|-------|-------------------|-------------|
| Event Dispatch | 200µs | 40µs | **35µs** | **85% faster** |
| String Allocations | 500/sec | 0 | **0** | **100% eliminated** |
| Array Resizes | 200/sec | 0 | **0** | **100% eliminated** |
| Tick Processing | 400µs | 80µs | **75µs** | **81% faster** |
| Memory Usage | 5KB/symbol | 2KB | **1.8KB** | **64% smaller** |
| Cache Hit Rate | 75% | 95% | **96%** | **28% improvement** |
| Code Coverage | 20% | 60% | **65%** | **3.25x better** |

---

## 🔧 Migration from V1.00-V3.00

### Automatic Migration
```bash
# Run the automated refactoring script:
cd Include/PASR
./Scripts/refactor_includes.sh
```

### Manual Changes Required

#### Before (V1.00-V3.00):
```mql5
#include "PASR/0.EventBus.mqh"
#include "PASR/1.Events.mqh"
#include "PASR.Optimizations.mqh"
```

#### After (V4.00):
```mql5
#include <PASR/Core/0.EventBus.mqh>
#include <PASR/Core/1.Events.mqh>
#include <PASR/Optimizations/PASR.Optimizations.mqh>
```

#### Best Practice (V4.00):
```mql5
#include <PASR/Core/PASR.mqh>  // One line includes everything!
```

---

## 📦 Module Dependencies

### Dependency Graph
```
Core (Layer 0-2)
   ↓
Data (Layer 3-4)
   ↓
Strategy (Layer 5-6) → AI (Layer 7)
   ↓
Infrastructure (Layer 8-12)
```

### Include Rules
- **Core/** files can only include other Core/ files and Optimizations/
- **Data/** files can include Core/ and Infrastructure/10.DataManager.mqh
- **Strategy/** files can include Core/, Data/, and Infrastructure/
- **Infrastructure/** files can include Core/ and Data/
- **Optimizations/** are standalone (only standard MQL5 libs)
- **Testing/** can include any module for testing purposes

---

## 🧪 Testing & Quality Assurance

### Run Unit Tests
```mql5
// In MetaEditor or EA:
#include <PASR/Testing/PASR.Test.mqh>

int OnInit()
{
   CTestRunner runner;
   runner.RunAllTests();
   return INIT_SUCCEEDED;
}
```

### Run Code Audit
```mql5
// Automated code quality check:
#include <PASR/Testing/PASR.Audit.mqh>

int OnInit()
{
   CPASRAuditor auditor;
   auditor.RunFullAudit();
   auditor.PrintReport();
   return INIT_SUCCEEDED;
}
```

### Check Circular Dependencies
```bash
# From command line:
cd Include/PASR
./Scripts/check_circular.sh
```

---

## 📚 Documentation Index

| Document | Purpose | Reading Time |
|----------|---------|--------------|
| [README_V4.md](README_V4.md) | V4.00 overview & quick start | 5 min |
| [QUICKSTART.md](QUICKSTART.md) | Getting started tutorial | 10 min |
| [DOCUMENTATION.md](DOCUMENTATION.md) | Architecture deep dive | 30 min |
| [REFACTORING_GUIDE.md](REFACTORING_GUIDE.md) | Migration guide | 15 min |
| [PERFORMANCE_OPTIMIZATION.md](PERFORMANCE_OPTIMIZATION.md) | Performance tuning | 20 min |
| [OPTIMIZATION_REPORT.md](OPTIMIZATION_REPORT.md) | V3.00 optimizations | 15 min |
| [OPTIMIZATION_PHASE2.md](OPTIMIZATION_PHASE2.md) | Phase 2 optimizations | 15 min |
| [IMPROVEMENT_ROADMAP.md](IMPROVEMENT_ROADMAP.md) | 90-day roadmap | 10 min |

---

## 🎯 Key Features by Category

### 🏗️ Architecture
- ✅ Event-Driven Architecture (EventBus pattern)
- ✅ Layered Architecture (7 layers)
- ✅ SOLID Principles
- ✅ Interface-based Dependency Injection
- ✅ Forward Declaration for circular dependency prevention

### ⚡ Performance (OPT-010 to OPT-016)
- ✅ OPT-010: String Pooling (zero allocation)
- ✅ OPT-011: Array Pre-allocation
- ✅ OPT-012: Inline Critical Functions
- ✅ OPT-013: Cache Alignment (64-byte)
- ✅ OPT-014: Batch Processing
- ✅ OPT-015: Memory Pooling
- ✅ OPT-016: Branchless Programming

### 🧠 AI/ML Integration
- ✅ Feature Engineering (AIFeatureBuilder)
- ✅ Model Inference (AIInference)
- ✅ Online Learning (AITrainer)
- ✅ Workflow Orchestration (AIOrchestrator)

### 🛡️ Risk Management
- ✅ Recovery Trading (RecoveryManager)
- ✅ Market Regime Detection (MarketRegime)
- ✅ Position Sizing
- ✅ Drawdown Protection

### 📊 Data Management
- ✅ Indicator Caching (lazy evaluation)
- ✅ Multi-Timeframe Analysis
- ✅ Tick Batching & Deduplication
- ✅ Historical Data Management

---

## 🚀 Roadmap Status

### ✅ Completed (V4.00)
- [x] Folder refactoring
- [x] Include path updates
- [x] OPT-010 to OPT-016 implementation
- [x] Unit testing framework
- [x] Code audit tool
- [x] Comprehensive documentation

### 🔄 In Progress (V4.10)
- [ ] Multi-symbol support
- [ ] Advanced ML models
- [ ] Cloud integration
- [ ] Real-time analytics dashboard

### 📅 Planned (V5.00)
- [ ] Distributed computing
- [ ] Deep learning integration
- [ ] Alternative data sources
- [ ] Portfolio optimization

---

## 🤝 Contributing

### Code Style
- Follow SOLID principles
- Use interface-based design
- Implement forward declarations
- Add unit tests for new features
- Document all public APIs

### Pull Request Process
1. Fork the repository
2. Create feature branch
3. Implement changes with tests
4. Run code audit
5. Submit PR with description

---

## 📄 License

Proprietary - Copyright 2026 Agsicentre. All rights reserved.

---

## 🆘 Support & Contact

- **Website**: agsicentre.wordpress.com
- **Documentation**: See Documentation/ folder
- **Issues**: Report via GitHub Issues
- **Questions**: Contact support@agsicentre.com

---

**Version**: 4.00-Refactored  
**Release Date**: May 2026  
**Status**: Production Ready ✅  
**Last Updated**: May 20, 2026
