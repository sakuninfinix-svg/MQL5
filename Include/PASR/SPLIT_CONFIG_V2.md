# Config Module Split - v2.0 (2026-05-20)

## Overview
The `2.Config.mqh` file has been successfully split into two separate modules:
- `2.Config.Types.mqh` - Type definitions, enums, structs, and helper functions
- `2.Config.Manager.mqh` - ConfigManager class and RecoveryEngine

## Rationale
1. **Separation of Concerns**: Types and business logic are now clearly separated
2. **Faster Compilation**: Files that only need types don't compile manager code
3. **Better Modularity**: Easier to maintain and test independently
4. **Clearer Dependencies**: Explicit separation between data structures and managers

## File Contents

### 2.Config.Types.mqh (1203 lines)
Contains:
- All ENUMs:
  - ENUM_PATTERN_TYPE
  - ENUM_CONFIG_FIELD_ID
  - ENUM_EVENT_ID
  - ENUM_ENTRY_MODE
  - ENUM_TPSL_MODE
  - ENUM_SR_MODE
  - ENUM_NEWS_LEVEL
  - ENUM_TRADE_STATE
  - ENUM_VALIDATION_SEVERITY
  
- All Structs:
  - InstrumentContext
  - StrategyConfig
  - ConfigSnapshot
  - ValidationResult
  - ValidationIssue
  - ConfigChange
  - SignalResult
  
- Input Parameters (input group declarations)
- Helper Functions:
  - Compare() for arrays
  - GetChanges() for config comparison
  
- Global Instance:
  - CFG (global StrategyConfig instance)

### 2.Config.Manager.mqh (467 lines)
Contains:
- ConfigManager Class:
  - Singleton pattern implementation
  - Configuration loading and validation
  - Context-aware initialization
  - Change tracking
  
- RecoveryEngine Class:
  - State persistence to Global Variables
  - State recovery after restart/disconnect
  - Trade state management

## Migration Guide

### Before (v1.x):
```mql5
#include <PASR/2.Config.mqh>
```

### After (v2.0):
```mql5
#include <PASR/2.Config.Types.mqh>
#include <PASR/2.Config.Manager.mqh>
```

**Note**: Most files already include both via IManager.mqh or other managers.

## Updated Files

All files in `/workspace/Include/PASR/` have been updated:
- ✅ 1.Events.mqh
- ✅ IManager.mqh
- ✅ 9.PatternManager.mqh
- ✅ 10.DataManager.mqh
- ✅ 11.DashboardManager.mqh
- ✅ PASR_MODULAR.mq5 (EA)

## Documentation Updates

Updated documentation files:
- ✅ DOCUMENTATION.md
- ✅ OPTIMIZATION_V130_COMPLETE.md
- ✅ dependency_analysis.txt

## Backward Compatibility

⚠️ **Breaking Change**: Any external code directly including `2.Config.mqh` must update to include both new files.

## Testing Checklist

- [x] All .mqh files compile without errors
- [x] No circular dependencies introduced
- [x] All enums and structs accessible from dependent files
- [x] ConfigManager singleton works correctly
- [x] RecoveryEngine state persistence functional
- [x] EA compiles successfully

## Benefits

1. **Clearer Architecture**: Types vs. Logic separation
2. **Maintainability**: Smaller, focused files
3. **Testability**: Can mock types without manager overhead
4. **Documentation**: Each file has single responsibility

## Future Considerations

1. If compilation speed becomes critical, some managers could include only `2.Config.Types.mqh` if they don't need ConfigManager functionality.
2. Consider extracting RecoveryEngine to its own file if it grows significantly.
3. Add unit tests for ConfigManager and RecoveryEngine independently.
