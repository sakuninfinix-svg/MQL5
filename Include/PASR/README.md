# PASR Framework - Professional Automated SR Trading System

[![Version](https://img.shields.io/badge/version-2.00-blue.svg)]()
[![MQL5](https://img.shields.io/badge/platform-MQL5-green.svg)]()
[![License](https://img.shields.io/badge/license-Proprietary-red.svg)]()

## 🎯 Overview

**PASR (Professional Automated SR)** adalah framework trading algoritmik berbasis MQL5 yang mengimplementasikan **Supply & Demand** strategy dengan arsitektur event-driven yang modern, scalable, dan high-performance.

### Key Features

✅ **Event-Driven Architecture** - Loose coupling dengan EventBus pattern  
✅ **Layered Architecture** - 7-layer separation of concerns  
✅ **SOLID Principles** - Maintainable dan extensible codebase  
✅ **AI/ML Integration** - Machine learning untuk signal enhancement  
✅ **Config Caching** - Optimized access untuk parameter strategy  
✅ **Indicator Caching** - Lazy evaluation untuk performance  
✅ **Recovery Management** - Robust error handling dan self-healing  
✅ **Multi-Timeframe Analysis** - Comprehensive market perspective  

---

## 📁 Project Structure

```
Include/PASR/
├── PASR.mqh                        # Master include (satu baris untuk semua)
├── Globals.mqh                     # Global utilities & singletons
├── Core/                           # L0-L4: Foundation layer
│   ├── EventBus.mqh                # Event messaging system
│   ├── Events.mqh                  # Concrete event definitions
│   ├── IManager.mqh                # Base interface for all managers
│   └── Config/
│       ├── Types.mqh               # Config type definitions
│       └── Manager.mqh             # Config loading & validation
├── Data/                           # L5-L8: Market data layer
│   ├── DataManager.mqh             # Indicator cache
│   ├── MarketManager.mqh           # Market conditions
│   ├── ZoneManager.mqh             # Supply/demand zones
│   ├── SRManager.mqh               # Support/resistance
│   └── MarketRegime.mqh            # Regime detection
├── Analysis/                       # L9: Analysis layer
│   └── PatternManager.mqh          # Pattern recognition
├── Signal/                         # L10: Signal generation
│   └── SignalManager.mqh           # Signal orchestration
├── AI/                             # L11: AI/ML layer
│   └── AIManager.mqh               # ML orchestration
├── Trade/                          # L12: Execution layer
│   ├── ExecutionManager.mqh        # Order execution
│   └── RecoveryManager.mqh         # Error recovery
├── UI/                             # L13: Presentation layer
│   └── DashboardManager.mqh        # Dashboard
├── Tools/                          # Dev tools (tidak di-include oleh PASR.mqh)
│   ├── Optimizations.mqh           # Performance macros
│   ├── Audit.mqh                   # Code quality audit
│   ├── Test.mqh                    # Unit testing framework
│   ├── BatchProcessor.mqh          # Batch processing
│   ├── MemoryPool.mqh              # Memory pool
│   └── Branchless.mqh              # Branchless math helpers
└── docs/                           # Dokumentasi (bukan kode)
    ├── QUICKSTART.md
    ├── DOCUMENTATION.md
    ├── IMPROVEMENT_ROADMAP.md
    └── PERFORMANCE_OPTIMIZATION.md
```

> **Backward Compatibility:** File lama (`0.EventBus.mqh`, `10.DataManager.mqh`, dst) masih ada sebagai shim dan tetap compile normal. EA yang sudah ada tidak perlu diubah.

---

## 🚀 Quick Start

### 1. Include dalam EA Kamu

```mql5
// Satu baris ini sudah cukup untuk semua layer
#include <PASR/PASR.mqh>
```

### 2. Atau include layer tertentu saja

```mql5
// Hanya butuh EventBus?
#include <PASR/Core/EventBus.mqh>

// Hanya butuh Signal layer?
#include <PASR/Signal/SignalManager.mqh>

// Hanya butuh Tools?
#include <PASR/Tools/Audit.mqh>
#include <PASR/Tools/Test.mqh>
```

---

## 📊 Performance Metrics

| Metric | Target | Status |
|--------|--------|--------|
| Event Dispatch Latency | <50µs | ✅ Optimized |
| Memory per Symbol | <2KB | ✅ Cached |
| Tick Processing | <100µs | ✅ Batched |
| Code Coverage | >80% | 🔄 In Progress |

---

## 🛠️ Development Tools

### Code Quality Audit

```mql5
#include <PASR/Tools/Audit.mqh>

PASRAuditor auditor;
auditor.RunFullAudit();
```

### Unit Testing

```mql5
#include <PASR/Tools/Test.mqh>

TestRunner runner;
runner.RegisterTest(myTest);
TestSuiteReport report = runner.RunAll();
report.LogReport();
```

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| **[docs/QUICKSTART.md](docs/QUICKSTART.md)** | Getting started dalam 5 menit |
| **[docs/DOCUMENTATION.md](docs/DOCUMENTATION.md)** | Architecture deep dive & API reference |
| **[docs/IMPROVEMENT_ROADMAP.md](docs/IMPROVEMENT_ROADMAP.md)** | 90-day enhancement plan |
| **[docs/PERFORMANCE_OPTIMIZATION.md](docs/PERFORMANCE_OPTIMIZATION.md)** | Advanced optimization techniques |

---

## 🎯 Architecture Highlights

### Event-Driven Design

```
┌─────────────▝      ┌──────────────▝      ┌─────────────▝
│  Publishers │─────▶│   EventBus   │─────▶│  Subscribers│
│  (Managers) │      │  (Mediator)  │      │  (Handlers) │
└─────────────┘      └──────────────┘      └─────────────┘
```

### Layered Architecture

```
L13: UI/DashboardManager
   ⬆️ depends on
L12: Trade/ (Execution, Recovery)
   ⬆️ depends on
L11: AI/AIManager
   ⬆️ depends on
L10: Signal/SignalManager
   ⬆️ depends on
L9:  Analysis/PatternManager
   ⬆️ depends on
L8-L11: Data/ (DataManager, ZoneManager, MarketManager, SRManager, MarketRegime)
   ⬆️ depends on
L7:  Core/Config/Manager
   ⬆️ depends on
L4:  Core/IManager
   ⬆️ depends on
L2-L3: Core/EventBus + Core/Events
   ⬆️ depends on
L1:  Core/Config/Types
   ⬆️ depends on
L0:  Tools/Optimizations (macros only)
```

---

## 📈 Roadmap

### Phase 1 (Days 1-30): Foundation ✅
- [x] Audit tool created
- [x] Test framework created
- [x] Folder structure migration complete
- [x] Master include (PASR.mqh) with enforced load order
- [ ] 60% code coverage

### Phase 2 (Days 31-60): Performance 🔄
- [ ] Event dispatch <50µs
- [ ] Memory <2.5KB/symbol
- [ ] Tick batching implemented
- [ ] Lazy indicator updates

### Phase 3 (Days 61-90): Advanced Features
- [ ] Multi-symbol support
- [ ] Enhanced AI features
- [ ] Advanced risk management

---

## 📝 Notes untuk Developer

- **Include baru:** gunakan path `Core/`, `Data/`, `Signal/`, `Trade/`, `UI/`, `Tools/`
- **Include lama:** file `0.EventBus.mqh`, `10.DataManager.mqh` dll masih berfungsi (shim)
- **Jangan include Tools/ dari PASR.mqh** — Tools adalah dev-only, bukan production include
- **Load order diatur di PASR.mqh** — jangan ubah urutan include di file tersebut

---

## 📠 Support

- **Documentation:** `docs/` folder
- **Code Quality:** `#include <PASR/Tools/Audit.mqh>`
- **Performance:** `docs/PERFORMANCE_OPTIMIZATION.md`

---

## 📄 License

Proprietary - Copyright 2026 Agsicentre

---

**Built with ❤️ for Algorithmic Trading**
