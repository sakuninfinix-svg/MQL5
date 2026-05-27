# PASR_MODULAR.mq5 Architecture Audit Report

## Executive Summary

**Audit Date:** 2026-01-XX  
**Primary Target:** Experts/PASR_MODULAR.mq5  
**Canonical Master Include:** Include/PASR/Core/PASR.mqh  
**Total Files Analyzed:** 127 (.mq5/.mqh files)

---

## 1. File-by-File Audit Table

### Experts/PASR_MODULAR.mq5 (PRIMARY TARGET)

| Attribute | Value |
|-----------|-------|
| **Status:** | ACTIVE_CANONICAL |
| **Used by PASR_MODULAR include graph:** | N/A (root file) |
| **Main responsibility:** | EA entry point, orchestrator delegation |
| **Legacy indicators found:** | None |
| **MQL4 syntax found:** | None - Uses proper MQL5 APIs (PositionGetTicket, PositionSelectByTicket, SymbolInfoDouble, SymbolInfoInteger) |
| **Duplicate/conflicting symbols:** | None |
| **Broken includes:** | None |
| **Missing dependencies:** | None |
| **Functions/classes that must be preserved:** | GetOpenPositionTicket(), GetSpreadPips(), DetectSession(), DebugPrint() |
| **Recommended action:** | Keep as-is |
| **Patch needed:** | No |
| **Risk level:** | P0-safe |
| **Notes:** | Clean architecture with proper COrchestrator delegation. Version 13.01 with BUG-008 fix applied. |

---

### Include/PASR/Core/PASR.mqh (CANONICAL MASTER)

| Attribute | Value |
|-----------|-------|
| **Status:** | ACTIVE_CANONICAL |
| **Used by PASR_MODULAR include graph:** | YES (direct) |
| **Main responsibility:** | Master include managing all dependency loading order |
| **Legacy indicators found:** | None |
| **MQL4 syntax found:** | None |
| **Duplicate/conflicting symbols:** | None |
| **Broken includes:** | None - All 69 includes resolve correctly |
| **Missing dependencies:** | None |
| **Functions/classes that must be preserved:** | Include guard __CORE_PASR_MASTER_MQH__ |
| **Recommended action:** | Keep as-is |
| **Patch needed:** | No |
| **Risk level:** | P0-safe |
| **Notes:** | Properly layered architecture (Layer 0-8). All includes use relative paths from Core/ directory. |

---

### Include/PASR/Tools/ Folder Analysis

| File | Status | Recommendation |
|------|--------|----------------|
| BatchProcessor.mqh | UNUSED_BUT_KEEP_DOC | Forwarder to Infra/Optimizations/BatchProcessor.mqh - kept for backward compatibility |
| Branchless.mqh | UNUSED_BUT_KEEP_DOC | Forwarder to Infra/Optimizations/Branchless.mqh |
| MemoryPool.mqh | UNUSED_BUT_KEEP_DOC | Forwarder to Infra/Optimizations/MemoryPool.mqh |
| Optimizations.mqh | UNUSED_BUT_KEEP_DOC | Forwarder to Infra/Optimizations/Optimizations.mqh |
| Test.mqh | UNUSED_BUT_KEEP_DOC | Forwarder to QA/Test.mqh |
| TickCache.mqh | ACTIVE_NEEDS_PATCH | Used by SignalScanner.mqh - contains unique logic |
| Audit.mqh | ACTIVE_NEEDS_PATCH | Standalone audit tool - not in PASR.mqh include graph |
| check_circular.sh | LEGACY_DELETE | Shell script for circular dependency check - not used in EA |

**Issue:** Tools/ folder is NOT included in PASR.mqh master include graph. These files are orphaned unless explicitly included elsewhere.

---

### Include/PASR/Data/ Folder Analysis

| File | Status | Recommendation |
|------|--------|----------------|
| DataManager.mqh | UNUSED_BUT_KEEP_DOC | Empty forwarder (784 bytes) - Infra/DataManager.mqh is canonical |
| RegimeTypes.mqh | ACTIVE_NEEDS_PATCH | Used by 10+ files via ../Data/RegimeTypes.mqh references |
| SRStruct.mqh | ACTIVE_NEEDS_PATCH | Used by SignalManager, SignalScorer, SRDetector, SRZoneStore |
| SymbolScanner.mqh | MIGRATE_UNIQUE_LOGIC_THEN_DELETE | CSymbolScanner class defined but NOT used by PASR_MODULAR include graph |

**Critical Finding:** Data/ folder is NOT in PASR.mqh include graph, but files ARE referenced by other active modules via relative paths (../Data/...). This creates inconsistent include patterns.

---

### Include/PASR/Infra/Optimizations/ Folder

| File | Status | Recommendation |
|------|--------|----------------|
| BatchProcessor.mqh | ACTIVE_CANONICAL | Full implementation (220+ lines) - canonical location |
| Branchless.mqh | ACTIVE_CANONICAL | Full implementation (380+ lines) - canonical location |
| MemoryPool.mqh | ACTIVE_CANONICAL | Referenced by Tools/MemoryPool.mqh forwarder |
| Optimizations.mqh | ACTIVE_CANONICAL | Full implementation (570+ lines) - canonical location |

**Status:** Healthy - these are the canonical implementations. Tools/ files forward here.

---

### Legacy/Suspicious Files Found

#### 1. Experts/PASR_V2_Optimized.mq5
- **Status:** LEGACY_DELETE (candidate)
- **Reason:** Includes non-existent `<PASR/MQL5Compatibility.mqh>` and `<PASR/Execution/MarketManager.mqh>`
- **References obsolete API:** IsEntryCooldownActive() mentioned in comments but function doesn't exist
- **Not used by:** PASR_MODULAR.mq5
- **Recommendation:** DELETE - broken includes, legacy EA version

#### 2. Experts/PASR.mq5
- **Status:** LEGACY_DELETE (candidate)
- **Reason:** Only includes `<Trade\Trade.mqh>` - old architecture
- **Not used by:** PASR_MODULAR.mq5
- **Recommendation:** DELETE - superseded by PASR_MODULAR.mq5

#### 3. Experts/CEK.mq5, kinjun.mq5, kinjun_bounce.mq5, Sis_EA.mq5, TPSL_kosong.mq5
- **Status:** LEGACY_DELETE (candidate)
- **Reason:** Unrelated EAs, not part of PASR architecture
- **Recommendation:** DELETE or MOVE to /Archive folder

#### 4. Include/PASR/Tools/check_circular.sh
- **Status:** LEGACY_DELETE
- **Reason:** Shell script, not MQL5 code, not used in compilation
- **Recommendation:** DELETE

---

## 2. P0 Compile Blockers

### CRITICAL: Broken Include in PASR_V2_Optimized.mq5
```
Line 13: #include <PASR/MQL5Compatibility.mqh>
```
- **File does not exist** at Include/PASR/MQL5Compatibility.mqh
- **Impact:** PASR_V2_Optimized.mq5 will NOT compile
- **Fix:** DELETE file (it's legacy anyway)

### CRITICAL: Missing Include in PASR_V2_Optimized.mq5
```
Line 12: #include <PASR/Execution/MarketManager.mqh>
```
- **Folder does not exist:** Include/PASR/Execution/
- **Class does not exist:** CMarketManager not found anywhere in codebase
- **Impact:** Compilation failure
- **Fix:** DELETE file

### WARNING: Data/ Folder Not in Master Include Graph
- Files like RegimeTypes.mqh, SRStruct.mqh are referenced via `../Data/...` from multiple active modules
- But Data/ folder is NOT listed in PASR.mqh include hierarchy
- **Risk:** If PASR.mqh is cleaned up to enforce strict layering, these includes could break
- **Fix:** Either add Data/ to PASR.mqh OR migrate files to appropriate canonical folders

---

## 3. P1 Architecture Cleanup Items

### 1. Tools/ Folder Orphaned
- **Issue:** Tools/ folder not in PASR.mqh include graph
- **Files affected:** Audit.mqh, Test.mqh, BatchProcessor.mqh, Branchless.mqh, MemoryPool.mqh, Optimizations.mqh, TickCache.mqh
- **Recommendation:** 
  - TickCache.mqh: Add to PASR.mqh (used by SymbolScanner)
  - Audit.mqh: Move to QA/ or delete (not used by EA)
  - Forwarder files (BatchProcessor, Branchless, MemoryPool, Optimizations, Test): Can be deleted if no external users

### 2. Data/ Folder Inconsistency
- **Issue:** Data/ folder exists but not in PASR.mqh
- **Files actively used:** RegimeTypes.mqh (10+ includes), SRStruct.mqh (5+ includes)
- **Recommendation:** Add Layer "Data Types" to PASR.mqh before Infra layer:
  ```mqh
  // Layer 1: Data types (before Infra)
  #include "../Data/RegimeTypes.mqh"
  #include "../Data/SRStruct.mqh"
  ```

### 3. Duplicate PatternContext Files
```
/workspace/Include/PASR/Analysis/Pattern/Core/PatternContext.mqh
/workspace/Include/PASR/Analysis/Pattern/Context/PatternContext.mqh
```
- **Issue:** Two files with same name in different folders
- **Check:** Are they identical? Do they serve different purposes?
- **Recommendation:** Investigate and consolidate

### 4. Unused QA Test Files
- MockDataManager.mqh, MockEventBus.mqh, SignalManagerTest.mqh, RiskManagerTest.mqh
- **Status:** Only used by PipelineHarness.mqh and TestRunner.mqh
- **Recommendation:** Keep for QA testing, but document as test-only modules

---

## 4. Files Safe to Delete

### Immediate Deletion (No Dependencies)
1. **Experts/PASR_V2_Optimized.mq5** - Broken includes, legacy
2. **Experts/PASR.mq5** - Superseded by PASR_MODULAR.mq5
3. **Experts/CEK.mq5** - Unrelated EA
4. **Experts/kinjun.mq5** - Unrelated EA
5. **Experts/kinjun_bounce.mq5** - Unrelated EA
6. **Experts/Sis_EA.mq5** - Unrelated EA
7. **Experts/TPSL_kosong.mq5** - Unrelated EA
8. **Include/PASR/Tools/check_circular.sh** - Shell script, not MQL5

### Conditional Deletion (After Verification)
9. **Include/PASR/Tools/BatchProcessor.mqh** - If no external projects use it
10. **Include/PASR/Tools/Branchless.mqh** - If no external projects use it
11. **Include/PASR/Tools/MemoryPool.mqh** - If no external projects use it
12. **Include/PASR/Tools/Optimizations.mqh** - If no external projects use it
13. **Include/PASR/Tools/Test.mqh** - If no external projects use it
14. **Include/PASR/Data/DataManager.mqh** - Empty forwarder, Infra/DataManager.mqh is canonical

---

## 5. Files with Unique Logic to Migrate

### Include/PASR/Data/SymbolScanner.mqh
- **Class:** CSymbolScanner : public IManager
- **Current usage:** NOT used by PASR_MODULAR include graph
- **Unique logic:** Multi-symbol scanning with TickCache integration
- **Recommendation:** 
  - Option A: Add to PASR.mqh if multi-symbol support is needed
  - Option B: Delete if single-symbol operation is sufficient
  - Option C: Document as optional module

### Include/PASR/Tools/TickCache.mqh
- **Current usage:** Included by SymbolScanner.mqh
- **Unique logic:** High-performance tick filtering
- **Recommendation:** If SymbolScanner is kept, move TickCache to Infra/ or keep in Tools/ but add to PASR.mqh

### Include/PASR/Tools/Audit.mqh
- **Current usage:** Standalone audit tool
- **Unique logic:** Code quality auditing framework
- **Recommendation:** Move to QA/ folder (more appropriate location)

---

## 6. Patch Plan

### Phase 1: P0 Compile Blockers (SAFE TO APPLY IMMEDIATELY)
1. Delete Experts/PASR_V2_Optimized.mq5 (broken includes)
2. Delete Include/PASR/Tools/check_circular.sh (non-MQL5 file)

### Phase 2: P1 Architecture Fixes (REQUIRES VERIFICATION)
1. Add Data/RegimeTypes.mqh and Data/SRStruct.mqh to PASR.mqh
2. Investigate duplicate PatternContext files
3. Decide on SymbolScanner.mqh fate (keep/delete/migrate)

### Phase 3: P2 Cleanup (OPTIONAL)
1. Delete unrelated EAs (CEK, kinjun, etc.) or move to /Archive
2. Consolidate Tools/ forwarders
3. Move Audit.mqh to QA/
4. Delete legacy PASR.mq5 (old EA)

---

## 7. MQL5 Compliance Verification

### ✅ PASR_MODULAR.mq5 - COMPLIANT
- Uses PositionGetTicket()/PositionSelectByTicket() for position iteration
- Uses SymbolInfoDouble()/SymbolInfoInteger() for market data
- Uses CTrade-based execution via ExecutionManager
- No MQL4 APIs detected

### ✅ All Core/ Files - COMPLIANT
- Proper MQL5 event handling
- Indicator handles with CopyBuffer/CopyRates
- No MarketInfo, OrderSelect, OP_BUY, OP_SELL found

### ⚠️ PASR_V2_Optimized.mq5 - NON-COMPLIANT
- References non-existent MQL5Compatibility.mqh
- Comments reference missing MarketManager.IsEntryCooldownActive()
- Cannot verify full compliance due to broken includes

---

## 8. Include Graph Summary

```
PASR_MODULAR.mq5
├── PASR/Core/PASR.mqh (MASTER)
│   ├── Layer 0: Config/Types, Globals, Events, EventBus, IManager, PipelineTypes
│   ├── Layer 1: StateOwnershipMap, PASR_SymbolManager, LatencyOptimizer, AsyncOrderManager, HighFreqTimer
│   ├── Layer 2: Infra/* (10 managers)
│   ├── Layer 3: Analysis/* (5 managers including Pattern)
│   ├── Layer 4: AI/* (11 modules)
│   ├── Layer 5: Signal/* (2 managers)
│   ├── Layer 6: Trade/* (7 managers)
│   ├── Layer 7: UI/DashboardManager, QA/LatencySimulator
│   └── Layer 8: PipelineEngine, Orchestrator, OrchestratorInit
└── PASR/QA/QAStressTest.mqh (conditional)
```

**Missing from graph:**
- Data/ folder (but referenced by other modules)
- Tools/ folder (mostly forwarders)
- QA/ test helpers (intentionally separate)

---

## 9. Recommendations

### Immediate Actions (P0)
1. ✅ Delete PASR_V2_Optimized.mq5
2. ✅ Delete check_circular.sh

### Short-term (P1)
1. Add Data/RegimeTypes.mqh and Data/SRStruct.mqh to PASR.mqh Layer 1
2. Decide on SymbolScanner.mqh (add to graph or delete)
3. Investigate PatternContext duplication

### Long-term (P2)
1. Archive or delete unrelated EAs
2. Clean up Tools/ forwarders
3. Document optional modules
4. Add include validation tests

---

## 10. Risk Assessment

| Component | Risk Level | Justification |
|-----------|------------|---------------|
| PASR_MODULAR.mq5 | LOW | Clean, well-structured, compiles |
| PASR.mqh | LOW | Proper layering, all includes valid |
| Core/ | LOW | No issues found |
| Infra/ | LOW | Canonical implementations |
| Trade/ | LOW | MQL5-compliant |
| AI/ | LOW | ONNX integration ready |
| Signal/ | LOW | Proper ISignalSource pattern |
| Analysis/ | MEDIUM | Duplicate PatternContext files |
| Data/ | MEDIUM | Not in master include graph |
| Tools/ | MEDIUM | Orphaned from main graph |
| QA/ | LOW | Test modules properly isolated |
| Experts/*.mq5 (legacy) | HIGH | Broken includes, should be deleted |

---

**END OF AUDIT REPORT**
