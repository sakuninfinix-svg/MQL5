# PASR — Price Action Support Resistance EA

> **Architecture:** Pipeline Orchestration (migrated from Monolith v9, Sprint 1–20)
> **Last updated:** Sprint 21 audit notes (2026-05-24)
> **Compile target:** `Experts/PASR_MODULAR.mq5`

---

## Architecture Overview

PASR menggunakan **Pipeline Orchestration** — semua logika dieksekusi sebagai stage berurutan di dalam `CPipelineEngine::ExecutePipeline()` yang dipanggil dari `OnTimer()`.

```
OnTick()  → Push EVENT_PRICE_UPDATE (no logic)
           → set m_new_bar_flag jika bar baru (consumed once di OnTimer)
OnTimer() → DrainQueue()
          → CPipelineEngine::ExecutePipeline(PipelineContext)
              Stage  1: DataSync
              Stage  2: AnalysisSR
              Stage  3: AnalysisZone
              Stage  4: PatternRec
              Stage  5: RegimeDetect
              Stage  6: SignalGen
              Stage  7: AIInference
              Stage  8: RiskCheck
              Stage  9: AdaptiveParams
              Stage 10: Execution
              Stage 11: PosMgmt
              Stage 12: Recovery
              Stage 13: Dashboard
              Stage 14: Journal
```

---

## Sprint 21 Audit Notes — 2026-05-24

Audit ini dilakukan dari repository `sakuninfinix-svg/MQL5` branch `main` melalui GitHub connector. Temuan di bawah belum diperbaiki di kode; README ini hanya memperbarui bug tracker sesuai permintaan.

### 🔴 OPEN — Newly Confirmed

| ID | Severity | File | Description | Impact | Target |
|----|----------|------|-------------|--------|--------|
| **S21-001** | 🔴 CRITICAL | `Core/PASR.mqh` | Master include saat ini hanya berisi literal `PLACEHOLDER_PASR`, bukan daftar include modular. | `Experts/PASR_MODULAR.mq5` memakai `#include <PASR/Core/PASR.mqh>` lalu langsung mendeklarasikan `COrchestrator`; jika master include placeholder, class utama dan dependensi tidak terdefinisi sehingga compile gagal. | S21 |
| **S21-002** | 🔴 CRITICAL | `Experts/PASR_MODULAR.mq5` | EA masih mendefinisikan `#define PERF_METRICS`, sedangkan README menyatakan flag lama `PERF_METRICS` sudah removed dan tidak boleh dipakai. | Kontrak build tidak konsisten; conditional compilation bisa mengaktifkan jalur lama/zombie atau membuat hasil audit README menyesatkan. | S21 |
| **S21-003** | 🔴 CRITICAL | `Infra/DataManager.mqh` | `class DataManager : public IDataManager`, tetapi `Core/IManager.mqh` hanya melakukan forward declaration `class IDataManager;` dan tidak mendefinisikan interface tersebut. | Jika tidak ada definisi `IDataManager` sebelum include ini, inheritance dari incomplete type akan gagal compile. Jika definisinya terselip di include lain, dependency order rapuh dan bertentangan dengan master include yang placeholder. | S21 |
| **S21-004** | 🔴 CRITICAL | `Infra/DataManager.mqh` | Method `Init`, `OnTick`, `OnBar`, `OnTrade` memakai `override` terhadap `IDataManager`, tetapi interface `IDataManager` tidak terlihat pada audit statis. | Risiko error `method marked override but does not override`; kontrak manager/data bus belum jelas. | S21 |
| **S21-005** | 🟠 HIGH | `Infra/DataManager.mqh` | Constructor tidak menginisialisasi `m_startBalance` di initializer list, melainkan di body setelah field lain. | Bukan compile blocker, tetapi style tidak konsisten dan berisiko pada ekspansi struct/class berikutnya; sebaiknya masuk initializer list penuh. | S21 |
| **S21-006** | 🔴 CRITICAL | `Infra/AdaptiveConfig.mqh` | File memakai `ENUM_TRAIL_MODE`, `TRAIL_ATR`, `TRAIL_NONE`, `TRAIL_SWING`, tetapi include langsung hanya `../Core/IManager.mqh`; audit search tidak menemukan definisi enum tersebut di repo. | Compile blocker bila enum trail mode memang belum didefinisikan secara global sebelum file ini. | S21 |
| **S21-007** | 🟠 HIGH | `Infra/AdaptiveConfig.mqh` | `SetRegimePolicy()` dan `SetSessionPolicy()` menulis array memakai index enum tanpa range guard. | Jika input enum invalid/corrupt dari caller, bisa out-of-bounds write ke fixed arrays. | S21 |
| **S21-008** | 🟡 MEDIUM | `Infra/AdaptiveConfig.mqh` | `SetATRThresholds(low, high)` tidak validasi `low < high` dan tidak clamp nilai minimum. | Threshold ATR bisa terbalik/negatif dan membuat klasifikasi volatilitas tidak valid. | S21 |
| **S21-009** | 🟡 MEDIUM | `Infra/AdaptiveConfig.mqh` | `DetectSession()` memakai `TimeGMT()` hardcoded, sementara EA memiliki input session UTC/broker dan README menyebut adaptive params. | Perilaku sesi tidak configurable; berisiko mismatch dengan broker time/session policy yang dipakai modul lain. | S21 |
| **S21-010** | 🟠 HIGH | `README.md` / status audit | README lama menandai Infra sebagai `S20 FULLY AUDITED & FIXED (10/10 files clean)`, tetapi `DataManager.mqh` dan `AdaptiveConfig.mqh` masih berstatus audit pending dan kini punya bug confirmed. | Status dokumentasi overclaim; bisa membuat audit berikutnya melewatkan modul penting. | S21 |

### 🔴 OPEN — Existing / Pending Scope

| ID | Severity | File | Description | Target |
|----|----------|------|-------------|--------|
| **A1** | 🟠 HIGH | `Analysis/SRManager.mqh` | 54KB monolith — perlu decomposition ke SRDetector + SRZoneStore + SRScorer | S21 |
| **A5** | 🟠 HIGH | `Analysis/Pattern/*.mqh` | Pattern subfolder belum diaudit untuk IManager compliance | S21 |
| **DATA-?** | 🔴 TBD | `Data/` | Folder belum diaudit | S21 |
| **QA-?** | 🔴 TBD | `QA/` | Folder belum diaudit | S21 |
| **UI-?** | 🔴 TBD | `UI/` | Folder belum diaudit | S21 |
| **TOOLS-?** | 🔴 TBD | `Tools/` | Folder belum diaudit | S21 |

---

## Immediate Fix Order

1. Restore `Core/PASR.mqh` as real master include and remove `PLACEHOLDER_PASR`.
2. Remove or rename legacy `PERF_METRICS` usage in `Experts/PASR_MODULAR.mq5` to the current supported macro contract.
3. Define canonical `IDataManager` interface in a stable header, then make `DataManager` implement it with explicit include order.
4. Define/import canonical `ENUM_TRAIL_MODE` before `AdaptiveConfig.mqh` uses it, or move trail mode enum into a canonical config/types header.
5. Add range guards to AdaptiveConfig setters and validate ATR threshold ordering.
6. Reconcile session source: UTC, broker time, or configurable offset must be consistent across EA inputs and AdaptiveConfig.

---

## Compilation Flags

```cpp
#define PASR_QA_BUILD    // Enable QA modules (LatencySimulator, chaos tests)
#define PASR_DEBUG       // Verbose logging per manager
```

> ⚠️ **Old flags removed:** `QA_BUILD`, `OOP_ARCHITECTURE`, `PERF_METRICS` — do NOT use. Current audit found `PERF_METRICS` still present in `Experts/PASR_MODULAR.mq5`.

---

## Quick Start

```cpp
// Include ONE file only — never include sub-files directly
#include <PASR/Core/PASR.mqh>

// In OnInit:
COrchestrator orch;
if(orch.Init(cfg) != INIT_SUCCEEDED) return INIT_FAILED;
EventSetTimer(1);

// In OnTick:
orch.OnTick();

// In OnTimer:
orch.OnTimer();

// In OnTradeTransaction:
orch.OnTradeTransaction(trans, request, result);

// In OnDeinit:
orch.OnDeinit(reason);
```

---

## Version Index — Audit Status

| File | Version | Last Sprint | Status |
|------|---------|-------------|--------|
| `Core/PASR.mqh` | — | S21 audit | 🔴 CRITICAL: placeholder master include |
| `Experts/PASR_MODULAR.mq5` | v13.01 | S21 audit | 🔴 CRITICAL: still uses removed `PERF_METRICS` flag |
| `Infra/DataManager.mqh` | v2.00 | S21 audit | 🔴 CRITICAL: `IDataManager` inheritance/interface unresolved |
| `Infra/AdaptiveConfig.mqh` | v2.00 | S21 audit | 🔴 CRITICAL: `ENUM_TRAIL_MODE` dependency unresolved |
| `Analysis/SRManager.mqh` | — | — | ⚠️ Audit needed (54KB) |
| `Analysis/Pattern/*.mqh` | — | — | 🔴 Not audited |
| `Data/*.mqh` | — | — | 🔴 Not audited |
| `QA/*.mqh` | — | — | 🔴 Not audited |
| `UI/*.mqh` | — | — | 🔴 Not audited |
| `Tools/*.mqh` | — | — | 🔴 Not audited |

---

© 2026 Agsicentre — PASR EA. All rights reserved.
