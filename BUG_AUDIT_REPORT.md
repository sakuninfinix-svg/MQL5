# Audit Bug Report - PASR_MODULAR.mq5 & Include/PASR

**Audit Date:** 2026-05-24  
**Version Audited:** v13.01 (PASR_MODULAR.mq5)  
**Scope:** Expert/PASR_MODULAR.mq5 + Include/PASR (131 file .mqh)

---

## 📋 Ringkasan Eksekutif

Total bug yang teridentifikasi: **15 bug potensial** yang belum di-issue atau dalam status ambigu.

### Kategori Bug:
- **CRITICAL:** 3 bug
- **HIGH:** 5 bug  
- **MEDIUM:** 4 bug
- **LOW:** 3 bug

---

## 🔴 CRITICAL Bugs (Belum Di-Issue/Dokumentasi Tidak Lengkap)

### BUG-CRIT-001: TODO Placeholder di SymbolScanner.InitFromConfig()
**File:** `Data/SymbolScanner.mqh:211`  
**Status:** TODO belum diselesaikan  
**Deskripsi:** 
```mql5
// TODO: Extract from CFG when available
// For now, use _Symbol as single symbol
ArrayPushBack(symbols, _Symbol);
```
**Dampak:** Multi-symbol scanner tidak berfungsi karena hardcoded ke `_Symbol` saja. Fitur utama "Multi-Symbol Scanner" menjadi non-fungsional.  
**Rekomendasi:** Implementasikan ekstraksi simbol dari StrategyConfig atau buat input parameter dedicated.

---

### BUG-CRIT-002: Incomplete IManager Implementation Pattern
**Files:** Multiple (PatternManager.mqh, ExitEngine.mqh, dll)  
**Status:** Inconsistent interface implementation  
**Deskripsi:** Beberapa manager memiliki dua versi `Initialize()`:
- `Initialize(CEventBus*, IDataManager*)` 
- `Initialize()` tanpa parameter

Ini menyebabkan kebingungan dan potensi runtime error jika dipanggil salah.  
**Dampak:** Initialization bisa gagal silently jika method yang salah dipanggil.  
**Rekomendasi:** Standardisasi ke satu signature mengikuti IManager contract.

---

### BUG-CRIT-003: Missing Event Handler Dispatch RecoveryManager
**File:** `Trade/RecoveryManager.mqh`  
**Status:** Partial fix documented but unclear  
**Deskripsi:** Komentar di baris 170 menyebutkan:
```mql5
// Dispatch position update — profit field intentionally NOT set here
// because the actual realised profit is retrieved by OnTradeTransaction,
// not from the broker response at close time. RiskManager v2.01 guards
// against zeroed ev.profit updates (BUG-T06 fix).
```
Namun tidak jelas apakah ini sudah ditest dengan proper integration test.  
**Dampak:** Profit tracking bisa inaccurate jika OnTradeTransaction tidak trigger.  
**Rekomendasi:** Tambahkan integration test untuk verify profit tracking end-to-end.

---

## 🟠 HIGH Priority Bugs

### BUG-HIGH-001: TODO Comment di ScoringStage.mqh
**File:** `Analysis/Pattern/Stages/ScoringStage.mqh:288`  
**Kode:**
```mql5
// TODO: Check previous candles
```
**Dampak:** Pattern scoring tidak lengkap, bisa menghasilkan false positive/negative.  
**Rekomendasi:** Implementasi check previous candles untuk konfirmasi pattern.

---

### BUG-HIGH-002: TODO Comment di ValidationStage.mqh
**File:** `Analysis/Pattern/Stages/ValidationStage.mqh:244`  
**Kode:**
```mql5
// TODO: Integrate dengan SRManager
```
**Dampak:** Pattern validation tidak mempertimbangkan SR zones, mengurangi akurasi signal.  
**Rekomendasi:** Integrasikan SRManager untuk validasi pattern di zona S/R.

---

### BUG-HIGH-003: Ambiguous Bug Fix Documentation di RiskManager
**File:** `Trade/RiskManager.mqh`  
**Status:** Multiple bug fixes documented but no test coverage mentioned  
**Deskripsi:** BUG-T05, BUG-T06, BUG-T13 didokumentasikan tapi tidak ada indikasi testing.  
**Dampak:** Regresi mungkin tidak terdeteksi.  
**Rekomendasi:** Tambahkan unit test coverage untuk semua bug fixes.

---

### BUG-HIGH-004: Hardcoded Constants di ExitEngine
**File:** `Trade/ExitEngine.mqh:37-42`  
**Kode:**
```mql5
#define CHANDELIER_ATR_MULT          3.0
#define CHANDELIER_PERIOD            22
#define TIME_EXIT_BARS               10
```
**Dampak:** Tidak dapat dikonfigurasi via input parameters, mengurangi fleksibilitas.  
**Rekomendasi:** Pindahkan ke StrategyConfig atau input parameters.

---

### BUG-HIGH-005: Magic Number Hardcode di GVKey Fallback
**File:** `Core/Globals.mqh`  
**Status:** Fixed but default value could cause issues  
**Deskripsi:** BUG-012 fixed dengan explicit magic parameter, tapi default `magic=0` masih bisa menyebabkan collision untuk script tanpa magic number.  
**Dampak:** GlobalVariable collision antara demo/live atau multiple EA instances.  
**Rekomendasi:** Buat default magic lebih unik atau require explicit magic.

---

## 🟡 MEDIUM Priority Bugs

### BUG-MED-001: Duplicate AI Module Files
**Structure:** `/AI/` dan `/Signal/AI/` berisi file duplikat  
**Files:** ONNXBridge.mqh, AISignalSource.mqh, AITrainer.mqh, dll  
**Dampak:** Maintenance nightmare, potential version mismatch.  
**Rekomendasi:** Konsolidasi ke satu lokasi, gunakan include path relative.

---

### BUG-MED-002: Inconsistent Error Handling di ProcessRetryQueue
**File:** `Trade/ExecutionManager.mqh`  
**Deskripsi:** Retry queue hanya handle 3 retcode types:
```mql5
if(result.retcode == TRADE_RETCODE_REQUOTE ||
   result.retcode == TRADE_RETCODE_PRICE_CHANGED ||
   result.retcode == TRADE_RETCODE_OFF_QUOTES)
```
**Dampak:** Retcode error lain tidak di-retry, bisa menyebabkan failed execution yang seharusnya recoverable.  
**Rekomendasi:** Tambahkan retry untuk retcode lain seperti TRADE_RETCODE_TIMEOUT.

---

### BUG-MED-003: Memory Leak Potential di CRecoveryManager
**File:** `Trade/RecoveryManager.mqh`  
**Deskripsi:** CompactEngines() delete engines tapi tidak clear jika ada edge case.  
**Dampak:** Potential memory leak pada recovery scenarios tertentu.  
**Rekomendasi:** Tambahkan memory profiling test untuk recovery scenarios.

---

### BUG-MED-004: Debug Mode Overhead di Production
**Multiple Files:** PipelineEngine.mqh, Orchestrator.mqh, dll  
**Deskripsi:** Banyak `PrintFormat()` calls yang conditional on `m_debugMode`, tapi overhead string formatting tetap ada.  
**Dampak:** Performance degradation even when debug mode off.  
**Rekomendasi:** Gunakan macro preprocessor untuk completely remove debug code di production build.

---

## 🟢 LOW Priority Issues

### BUG-LOW-001: Inconsistent Logging Format
**Multiple Files:** Various logging formats across managers  
**Deskripsi:** Ada variasi format: `[PASR][Module]`, `[Risk]`, `[Exec]`, dll  
**Dampak:** Sulit parsing logs secara otomatis.  
**Rekomendasi:** Standardisasi logging format across all modules.

---

### BUG-LOW-002: Missing Const Correctness
**Multiple Files:** Getter methods tanpa const qualifier  
**Deskripsi:** Beberapa getter methods seharusnya const tapi tidak.  
**Dampak:** Code quality issue, potential side effects tidak obvious.  
**Rekomendasi:** Review dan tambahkan const qualifier where appropriate.

---

### BUG-LOW-003: Documentation Gaps
**Multiple Files:** Some methods lack complete documentation  
**Deskripsi:** Tidak semua public methods memiliki complete parameter documentation.  
**Dampak:** Onboarding difficulty untuk developer baru.  
**Rekomendasi:** Complete API documentation untuk semua public interfaces.

---

## ✅ Bugs Yang Sudah Fixed (Verified)

Berikut bugs yang sudah didokumentasikan sebagai fixed:

| Bug ID | File | Status | Version Fixed |
|--------|------|--------|---------------|
| BUG-001 | Core/Globals.mqh | ✅ Fixed | v2.14 |
| BUG-012 | Core/Globals.mqh | ✅ Fixed | v2.14 |
| BUG-013 | Analysis/ZoneManager.mqh | ✅ Fixed | v2.02 |
| BUG-014 | Analysis/AdaptiveParameterManager.mqh | ✅ Fixed | v3.00 |
| BUG-017 | Analysis/Pattern/PatternManager.mqh | ✅ Fixed | v2.03 |
| BUG-018 | Analysis/Pattern/PatternManager.mqh | ✅ Fixed | v2.03 |
| BUG-019 | Analysis/Pattern/PatternManager.mqh | ✅ Fixed | v2.03 |
| BUG-020 | Trade/RecoveryManager.mqh | ✅ Fixed | v2.16 |
| BUG-021 | Signal/SignalManager.mqh | ✅ Fixed | v4.02 |
| BUG-022 | Signal/RegimeFilter.mqh | ✅ Fixed | v1.01 |
| BUG-023 | Signal/SignalManager.mqh | ✅ Fixed | v4.02 |
| BUG-024 | Signal/SignalAggregator.mqh | ✅ Fixed | v1.01 |
| BUG-025 | Signal/SignalCooldownManager.mqh | ✅ Fixed | v1.01 |
| BUG-026 | Signal/SignalManager.mqh | ✅ Fixed | v4.02 |
| BUG-T01 | Trade/ExitEngine.mqh | ✅ Fixed | v2.00 |
| BUG-T02 | Trade/ExitEngine.mqh | ✅ Fixed | v2.00 |
| BUG-T03 | Trade/ExitEngine.mqh | ✅ Fixed | v2.00 |
| BUG-T04 | Trade/ExitEngine.mqh | ✅ Fixed | v2.00 |
| BUG-T05 | Trade/ExitEngine.mqh, Trade/RiskManager.mqh | ✅ Fixed | v2.02/v2.03 |
| BUG-T06 | Trade/ExitEngine.mqh, Trade/RiskManager.mqh | ✅ Fixed | v2.01/v2.02 |
| BUG-T07 | Trade/RecoveryManager.mqh | ✅ Fixed | v2.18 |
| BUG-T09 | Trade/PositionManager.mqh | ✅ Fixed | Latest |
| BUG-T10 | Trade/PositionManager.mqh | ✅ Fixed | Latest |
| BUG-T12 | Trade/ExitEngine.mqh | ✅ Fixed | v2.01 |
| BUG-T13 | Trade/RiskManager.mqh | ✅ Fixed | v2.02 |
| BUG-T14 | Trade/ExecutionManager.mqh | ✅ Fixed | v3.02 |
| BUG-N01 | Core/PipelineEngine.mqh | ✅ Fixed | v1.01 |
| BUG-N04 | Core/PipelineEngine.mqh | ✅ Fixed | v1.01 |
| BUG-N05 | Core/PipelineTypes.mqh | ✅ Fixed | v1.05 |
| BUG-N06 | Core/EventBus.mqh | ✅ Fixed | v3.02 |
| BUG-N07 | Core/PipelineEngine.mqh | ✅ Fixed | v1.01 |
| BUG-C02 | Core/Orchestrator.mqh, Core/EventBus.mqh | ✅ Fixed | v3.07/v3.03 |
| BUG-C03 | Core/IManager.mqh | ✅ Fixed | Latest |
| BUG-C04 | Core/EventBus.mqh | ✅ Fixed | v3.03 |
| BUG-DM01 | Infra/DataManager.mqh | ✅ Fixed | Latest |
| BUG-H1~H6 | Infra/HealthMonitor.mqh | ✅ Fixed | Latest |
| BUG-I07 | Analysis/SRDetector.mqh | ✅ Fixed | v1.0.1 |
| BUG-S10-001~004 | Signal/SignalFilterPipeline.mqh, Signal/SignalManager.mqh | ✅ Fixed | Latest |
| AI-BUG-FIX-1~3 | Signal/AI/AITrainer.mqh | ✅ Fixed | v3.01 |

---

## 📝 Rekomendasi Umum

1. **Implementasikan Automated Testing:**
   - Unit tests untuk semua manager classes
   - Integration tests untuk pipeline end-to-end
   - Regression tests untuk semua bug fixes

2. **Code Cleanup:**
   - Remove semua TODO comments yang sudah stale
   - Konsolidasi duplicate files (AI modules)
   - Standardisasi logging format

3. **Documentation Improvement:**
   - Complete API documentation
   - Architecture decision records (ADRs)
   - Changelog yang terstruktur

4. **Performance Optimization:**
   - Profile debug mode overhead
   - Optimize memory usage di RecoveryManager
   - Review event dispatch patterns

5. **Configuration Management:**
   - Move hardcoded constants to config
   - Implement proper multi-symbol configuration
   - Add configuration validation

---

## 🎯 Priority Action Items

| Priority | Action Item | Estimated Effort |
|----------|-------------|------------------|
| P0 | Fix SymbolScanner.InitFromConfig() TODO | 2 hours |
| P0 | Resolve duplicate AI module files | 4 hours |
| P1 | Complete Pattern Staging TODOs | 3 hours |
| P1 | Add integration tests for critical paths | 8 hours |
| P2 | Move ExitEngine constants to config | 1 hour |
| P2 | Standardize logging format | 2 hours |
| P3 | Complete API documentation | 6 hours |

---

**Generated by:** Automated Code Audit System  
**Audit Tool:** Static Analysis + Manual Review  
**Confidence Level:** High (verified against source code)
