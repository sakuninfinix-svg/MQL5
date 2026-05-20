# PASR Framework - Refactoring Guide

## 📁 New Folder Structure (V4.00)

```
/Include/PASR/
├── Core/                    # Core framework components
│   ├── 0.EventBus.mqh       # Event-driven core (OPT-010 to OPT-013)
│   ├── 1.Events.mqh         # Event definitions
│   ├── 2.Config.Types.mqh   # Configuration types
│   ├── 2.Config.Manager.mqh # Configuration manager
│   ├── Globals.mqh          # Global definitions
│   ├── IManager.mqh         # Manager interface
│   └── PASR.mqh             # Main include file
│
├── Data/                    # Data layer (Layer 3-4)
│   ├── 3.MarketManager.mqh  # Market data management
│   ├── 3.ZoneManager.mqh    # Supply/demand zones
│   └── 4.SRManager.mqh      # Support/resistance levels
│
├── Strategy/                # Strategy layer (Layer 5-6)
│   ├── 5.SignalManager.mqh  # Signal generation
│   ├── 6.ExecutionManager.mqh # Order execution
│   └── AI/                  # AI/ML components
│       ├── 7.AIManager.mqh  # AI orchestration
│       ├── AIFeatureBuilder.mqh
│       ├── AIInference.mqh
│       ├── AIOrchestrator.mqh
│       ├── AITrainer.mqh
│       └── AITypes.mqh
│
├── Infrastructure/          # Supporting infrastructure (Layer 8-12)
│   ├── 8.RecoveryManager.mqh  # Recovery trading
│   ├── 9.PatternManager.mqh   # Pattern recognition
│   ├── 10.DataManager.mqh     # Data management hub
│   ├── 11.DashboardManager.mqh # Dashboard UI
│   └── 12.MarketRegime.mqh    # Market regime detection
│
├── Optimizations/           # Performance optimizations
│   ├── PASR.Optimizations.mqh    # OPT-010 to OPT-013
│   ├── PASR.BatchProcessor.mqh   # OPT-014: Batch processing
│   ├── PASR.MemoryPool.mqh       # OPT-015: Object pooling
│   └── PASR.Branchless.mqh       # OPT-016: Branchless programming
│
├── Testing/                 # Testing & audit tools
│   ├── PASR.Test.mqh        # Unit testing framework
│   └── PASR.Audit.mqh       # Code quality audit
│
├── Documentation/           # All documentation
│   ├── README.md            # Main entry point
│   ├── QUICKSTART.md        # Getting started
│   ├── DOCUMENTATION.md     # Architecture deep dive
│   ├── IMPROVEMENT_ROADMAP.md # 90-day roadmap
│   ├── PERFORMANCE_OPTIMIZATION.md # Performance guide
│   ├── OPTIMIZATION_REPORT.md # V3.00 report
│   └── OPTIMIZATION_PHASE2.md   # Phase 2 optimizations
│
└── Scripts/                 # Utility scripts
    └── check_circular.sh    # Circular dependency checker
```

## 🔧 Include Path Changes

### Before Refactoring:
```mql5
#include "PASR.Optimizations.mqh"
#include "0.EventBus.mqh"
#include "1.Events.mqh"
#include "2.Config.Types.mqh"
```

### After Refactoring:
```mql5
// From Core/ files:
#include "../Optimizations/PASR.Optimizations.mqh"
#include "Core/0.EventBus.mqh"
#include "Core/1.Events.mqh"
#include "Core/2.Config.Types.mqh"

// From Data/ files:
#include "../Core/IManager.mqh"
#include "../Infrastructure/10.DataManager.mqh"

// From Strategy/ files:
#include "../Core/IManager.mqh"
#include "../Infrastructure/10.DataManager.mqh"
#include "../Data/4.SRManager.mqh"

// From user EA:
#include <PASR/Core/PASR.mqh>  // Recommended: Single include
```

## 📦 Module Dependencies

### Layer 0-2: Core (No dependencies on other layers)
- `0.EventBus.mqh` → `../Optimizations/PASR.Optimizations.mqh`
- `1.Events.mqh` → `Core/0.EventBus.mqh`, `Core/2.Config.Types.mqh`
- `2.Config.*.mqh` → Standard MQL5 libraries only

### Layer 3-4: Data (Depends on Core)
- `3.MarketManager.mqh` → `Core/IManager.mqh`, `Infrastructure/10.DataManager.mqh`
- `3.ZoneManager.mqh` → `Core/IManager.mqh`, `Infrastructure/10.DataManager.mqh`, `Data/4.SRManager.mqh`
- `4.SRManager.mqh` → `Core/IManager.mqh`, `Infrastructure/10.DataManager.mqh`

### Layer 5-6: Strategy (Depends on Core + Data)
- `5.SignalManager.mqh` → `Core/IManager.mqh`, `Infrastructure/10.DataManager.mqh`, `Data/4.SRManager.mqh`, `Infrastructure/12.MarketRegime.mqh`
- `6.ExecutionManager.mqh` → `Core/IManager.mqh`, `Infrastructure/10.DataManager.mqh`, `<Trade/Trade.mqh>`

### Layer 7: AI (Depends on Core + Strategy)
- `AI/*.mqh` → Core + Strategy components

### Layer 8-12: Infrastructure (Depends on Core + Data)
- `8.RecoveryManager.mqh` → `Core/IManager.mqh`, `Infrastructure/10.DataManager.mqh`, `Infrastructure/9.PatternManager.mqh`, `Infrastructure/12.MarketRegime.mqh`, `<Trade/Trade.mqh>`
- `9.PatternManager.mqh` → `Core/2.Config.*.mqh`
- `10.DataManager.mqh` → `Core/IManager.mqh`, `Core/2.Config.*.mqh`
- `11.DashboardManager.mqh` → `Core/IManager.mqh`
- `12.MarketRegime.mqh` → `Core/IManager.mqh`

### Optimizations (Standalone)
- `PASR.Optimizations.mqh` → Standard MQL5 only
- `PASR.BatchProcessor.mqh` → `Core/0.EventBus.mqh`
- `PASR.MemoryPool.mqh` → Standard MQL5 only
- `PASR.Branchless.mqh` → Standard MQL5 only

## ✅ Refactoring Checklist

### Files Updated:
- [x] `Core/0.EventBus.mqh` - Path to Optimizations updated
- [x] `Core/1.Events.mqh` - Paths to Core files updated
- [ ] `Core/2.Config.Manager.mqh` - Verify paths
- [ ] `Core/PASR.mqh` - Update all includes
- [ ] `Data/*.mqh` - Update all includes
- [ ] `Strategy/*.mqh` - Update all includes
- [ ] `Infrastructure/*.mqh` - Update all includes
- [ ] `Optimizations/*.mqh` - Verify cross-references
- [ ] `Testing/*.mqh` - Update all includes

### Testing Required:
- [ ] Compile all files without errors
- [ ] Run unit tests (PASR.Test.mqh)
- [ ] Run code audit (PASR.Audit.mqh)
- [ ] Backtest with sample EA
- [ ] Verify no circular dependencies

## 🚀 Migration Guide for Existing Projects

### Option 1: Update Includes (Recommended)
```mql5
// Old way (no longer works):
#include <PASR/0.EventBus.mqh>

// New way (use folder structure):
#include <PASR/Core/0.EventBus.mqh>

// Best way (use main include):
#include <PASR/Core/PASR.mqh>
```

### Option 2: Create Symbolic Links (Advanced)
For backward compatibility, create symlinks in root:
```bash
ln -s Core/0.EventBus.mqh 0.EventBus.mqh
ln -s Core/1.Events.mqh 1.Events.mqh
# ... etc
```

## 📊 Benefits of Refactoring

1. **Better Organization**: Clear separation of concerns by layer
2. **Easier Navigation**: Find files faster with logical grouping
3. **Reduced Coupling**: Explicit dependencies between layers
4. **Scalability**: Easy to add new components to appropriate folders
5. **Maintainability**: Clear ownership and responsibility per folder
6. **Performance**: Optimizations grouped together for easy access
7. **Testing**: Dedicated testing folder for all test utilities
8. **Documentation**: All docs in one place, versioned together

## 🎯 Next Steps

1. Complete include path updates for all files
2. Test compilation of entire framework
3. Run full test suite
4. Update user documentation with new paths
5. Create migration script for existing EAs
6. Tag release as V4.00-Refactored

---

**Version**: 4.00  
**Date**: May 2026  
**Status**: In Progress
