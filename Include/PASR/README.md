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
              Stage  1: DataSync         ← m_data->OnTick()
              Stage  2: AnalysisSR       ← m_bus.Dispatch(EVENT_ID_NEW_BAR)
              Stage  3: AnalysisZone     ← m_zone->Update() on new bar
              Stage  4: PatternRec       ← m_pattern->OnTick()
              Stage  5: RegimeDetect     ← m_regime_det->Evaluate()
              Stage  6: SignalGen        ← CSignalManager (4 sources, weighted vote)
              Stage  7: AIInference      ← CAIOrchestrator v2.02 (26-dim, real SGD, ensemble diversity)
              Stage  8: RiskCheck        ← CRiskManager + CCorrelationManager + IsSpreadAcceptable()
              Stage  9: AdaptiveParams   ← CAdaptiveParameterManager->OnNewBar()
              Stage 10: Execution        ← CExecutionManager + ticket capture
              Stage 11: PosMgmt          ← CPositionManager->ScanPositions() + CExitEngine->CheckExit()
              Stage 12: Recovery         ← CRecoveryManager->OnTick()
              Stage 13: Dashboard        ← CDashboardManager->OnTimer()
              Stage 14: Journal          ← CJournalManager (via EventBus EVENT_ID_TRADE_CLOSED)
          → DrainQueue()
OnTradeTransaction() → RecoveryManager + SessionState + AIOrchestrator backprop
```

---

## Folder Map

```
Include/PASR/
├── Core/                    ← Infrastructure (EventBus, IManager, Pipeline engine)
│   ├── PASR.mqh             ← Master include — use this, NEVER include sub-files directly
│   ├── Orchestrator.mqh     ← v3.06 — owns all managers, wires OnTick/OnTimer/OnDeinit
│   ├── PipelineEngine.mqh   ← v1.01 — 14-stage execution engine (fully implemented)
│   ├── PipelineTypes.mqh    ← PipelineContext, enums, SExecutionResult
│   ├── Events.mqh           ← All ENUM_EVENT_ID definitions (v2.14)
│   ├── EventBus.mqh         ← Pub/sub message bus (O(n log n) heap drain)
│   ├── IManager.mqh         ← Base interface for all managers
│   ├── Globals.mqh          ← v2.15 — GVKey helpers, PASRLog*, CPerfTimer, IsSpreadAcceptable()
│   ├── AsyncOrderManager.mqh
│   ├── HighFreqTimer.mqh
│   ├── LatencyOptimizer.mqh
│   ├── StateOwnershipMap.mqh
│   └── PASR_SymbolManager.mqh
│
├── Analysis/                ← Market analysis managers
│   ├── SRManager.mqh        ← ⚠ 54KB — Sprint 21 decomposition target
│   ├── ZoneManager.mqh      ← Supply/Demand zones
│   ├── MarketRegimeDetector.mqh
│   ├── AdaptiveParameterManager.mqh
│   └── Pattern/             ← Candlestick pattern sub-module (audit pending S21)
│
├── Signal/                  ← v4.02 — Signal generation & regime filtering
│   ├── SignalManager.mqh    ← v4.02
│   └── SignalFilterPipeline.mqh ← v1.02
│
├── Trade/                   ← ✅ S13 Fully Audited — 8 files
│   ├── ExecutionManager.mqh ← v3.02
│   ├── RiskManager.mqh      ← v2.02
│   ├── RecoveryManager.mqh  ← v2.18
│   ├── RecoveryEngine.mqh
│   ├── ExitEngine.mqh       ← v2.01
│   ├── PositionManager.mqh  ← v3.00
│   ├── TradePlan.mqh
│   └── CorrelationManager.mqh ← v2.00
│
├── AI/                      ← ✅ S16 Fully Audited
│   ├── AIOrchestrator.mqh   ← v2.02
│   ├── AIFeatureBuilder.mqh ← v2.01
│   ├── AIInference.mqh      ← v2.01
│   ├── AIEnsemble.mqh       ← v2.01
│   ├── AITrainer.mqh        ← v2.01
│   ├── AITypes.mqh
│   ├── ConfidenceCalibrator.mqh
│   ├── OnlineLearningGuard.mqh
│   ├── AICalibrationBridge.mqh
│   ├── AISignalSource.mqh
│   ├── ModelRegistry.mqh
│   └── ONNXBridge.mqh
│
├── Infra/                   ← ⚠ S21 reopened: DataManager + AdaptiveConfig require fixes
│   ├── HealthMonitor.mqh    ← v2.00 — BUG-H1..H6 fixed (S7)
│   ├── SessionState.mqh     ← v1.01 — SS-001 CLOSED, SS-002 FIXED (S18)
│   ├── SnapshotManager.mqh  ← v2.00 — SNAP-001..005 fixed (S17)
│   ├── JournalManager.mqh   ← v2.00 — JNL-001..005 fixed (S18) ✅
│   ├── TelemetryRecorder.mqh← v2.00 — TEL-001..004 fixed (S20) ✅
│   ├── PerformanceReport.mqh← v1.00 — RPT-001..003 CLEAR (S20) ✅
│   ├── SanityManager.mqh    ← v2.00 — SAN-001..004 fixed (S20) ✅
│   ├── StateManager.mqh     ← v2.00 — STM-001..003 fixed (S20) ✅
│   ├── DataManager.mqh      ← S21 audit: critical interface issues
│   └── AdaptiveConfig.mqh   ← S21 audit: critical enum/dependency issues
│
├── Data/                    ← audit pending S21
├── QA/                      ← audit pending S21
├── Tools/                   ← audit pending S21
├── UI/                      ← audit pending S21
└── docs/                    ← internal documentation

Experts/
├── PASR_MODULAR.mq5         ← ✅ EA entry point v13.01
└── PASR.mq5                 ← Legacy monolith (deprecated, do not extend)
```

---

## Compilation Flags

```cpp
#define PASR_QA_BUILD    // Enable QA modules (LatencySimulator, chaos tests)
#define PASR_DEBUG       // Verbose logging per manager
```

> ⚠️ **Old flags removed:** `QA_BUILD`, `OOP_ARCHITECTURE`, `PERF_METRICS` — do NOT use.
> S21 audit note: `PERF_METRICS` masih ditemukan di `Experts/PASR_MODULAR.mq5` dan harus dibersihkan.

---

## Bug Tracker

### 🔴 OPEN — Sprint 21 Newly Confirmed

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
| **S21-009** | 🟡 MEDIUM | `Infra/AdaptiveConfig.mqh` | `DetectSession()` memakai `TimeGMT()` hardcoded, sementara EA memiliki input session UTC/broker. | Perilaku sesi tidak configurable; berisiko mismatch dengan broker time/session policy yang dipakai modul lain. | S21 |
| **S21-010** | 🟠 HIGH | `README.md` / status audit | README lama menandai Infra sebagai `S20 FULLY AUDITED & FIXED (10/10 files clean)`, tetapi `DataManager.mqh` dan `AdaptiveConfig.mqh` masih pending dan kini punya bug confirmed. | Status dokumentasi overclaim; audit berikutnya bisa melewatkan modul penting. | S21 |

### 🔴 OPEN — Existing / Pending Scope

| ID | Severity | File | Description | Target |
|----|----------|------|-------------|--------|
| **A1** | 🟠 HIGH | `Analysis/SRManager.mqh` | 54KB monolith — perlu decomposition ke SRDetector + SRZoneStore + SRScorer | S21 |
| **A5** | 🟠 HIGH | `Analysis/Pattern/*.mqh` | Pattern subfolder belum diaudit untuk IManager compliance | S21 |
| **INF-7** | 🔴 TBD | `Infra/DataManager.mqh` | Belum diaudit; superseded by S21-003..S21-005 but kept for continuity until closed | S21 |
| **INF-10** | 🔴 TBD | `Infra/AdaptiveConfig.mqh` | Belum diaudit; superseded by S21-006..S21-009 but kept for continuity until closed | S21 |
| **DATA-?** | 🔴 TBD | `Data/` | Folder belum diaudit | S21 |
| **QA-?** | 🔴 TBD | `QA/` | Folder belum diaudit | S21 |
| **UI-?** | 🔴 TBD | `UI/` | Folder belum diaudit | S21 |
| **TOOLS-?** | 🔴 TBD | `Tools/` | Folder belum diaudit | S21 |

---

### ✅ RESOLVED — Sprint 1–20

| ID | Severity | File | Fix | Sprint |
|----|----------|------|-----|--------|
| **TEL-001** | 🔴 CRITICAL | `Infra/TelemetryRecorder.mqh` | `Initialize()` → `Init(IDataManager*, CEventBus*) override` | S20 |
| **TEL-002** | 🔴 CRITICAL | `Infra/TelemetryRecorder.mqh` | `EventSubscribe()` → `m_bus.Subscribe()` via IManager contract | S20 |
| **TEL-003** | 🟠 HIGH | `Infra/TelemetryRecorder.mqh` | `CFile` object methods → `FileOpen/FileWrite/FileFlush/FileClose` built-in | S20 |
| **TEL-004** | 🟡 MEDIUM | `Infra/TelemetryRecorder.mqh` | `m_buffer_count` init dari `MAX_BUFFER_SIZE` → `0`; flush only when full | S20 |
| **SAN-001** | 🔴 CRITICAL | `Infra/SanityManager.mqh` | Tidak subscribe EventBus → `m_bus.Subscribe(this, EVENT_ID_SYSTEM_INFO)` | S20 |
| **SAN-002** | 🔴 CRITICAL | `Infra/SanityManager.mqh` | `CheckFreshness()` dead code → real elapsed-seconds staleness check | S20 |
| **SAN-003** | 🟠 HIGH | `Infra/SanityManager.mqh` | `tick.last` (0 di Forex) → `tick.bid` untuk gap detection | S20 |
| **SAN-004** | 🟡 MEDIUM | `Infra/SanityManager.mqh` | `SendEvt()` payload kosong → message disimpan di `evt.tag` | S20 |
| **STM-001** | 🟠 HIGH | `Infra/StateManager.mqh` | XOR fake-CRC → FNV-1a 32-bit hash, `STATE_FILE_VERSION` bump ke 0x0200 | S20 |
| **STM-002** | 🟡 MEDIUM | `Infra/StateManager.mqh` | `CheckDailyReset()` skip update jika `tradesToday==0` → unconditional update | S20 |
| **STM-003** | 🟡 MEDIUM | `Infra/StateManager.mqh` | `OnDeinit()` contract didokumentasikan — Orchestrator WAJIB call sebelum delete | S20 |
| **RPT-001..003** | 🟠 HIGH | `Infra/PerformanceReport.mqh` | NULL guard, JOURNAL_DAILY_SIZE explicit, explicit includes — **CLEAR**: file sudah fix di S19 | S20 |
| **JNL-001..005** | 🔴 CRITICAL | `Infra/JournalManager.mqh` | IManager extend, include fix, OnEvent, CSV flags, PASRLog* | S18 |
| **SS-002** | 🟡 MEDIUM | `Infra/SessionState.mqh` | `IsNewDay()` midnight-floor fix | S18 |
| **SNAP-001..005** | 🔴 CRITICAL | `Infra/SnapshotManager.mqh` | IManager extend, include fix, checksum, signature override, static→member index | S17 |
| **AI-001..007** | 🔴 CRITICAL | `AI/*.mqh` | AIFeatureBuilder, SGD backprop, ensemble diversity, MathTanh guard | S16 |
| **TR-001..006** | 🔴 CRITICAL | `Trade/*.mqh` | ExitEngine, PositionManager, RiskManager, ExecutionManager, RecoveryManager, CorrelationManager | S12–13 |
| **BUG-H1..H6** | 🔴 CRITICAL | `Infra/HealthMonitor.mqh` | EventBus* type, SendEvent→Push, PASR_MemoryUsage, flags | S7 |
| BUG-001..012 | 🔴 CRITICAL | `Core/*.mqh` | Monolith cleanup, pipeline wiring, compile fixes | S1–2 |
| O1,O4,O7,O8 | 🔴 CRITICAL | `Core/Orchestrator.mqh` | ENUM_PIPELINE_STAGE, SessionState wiring, BarChanged race, JournalManager | S9 |
| X1–X7 | 🔴 CRITICAL | `Core/PASR_Executor.mqh` | DELETED — monolith zombie | S9 |
| S8-001,S8-005 | 🔴 CRITICAL | `Core/Events.mqh` | Missing event IDs | S8 |
| N01,N03,N04,N06,N07 | 🔴 CRITICAL | `Core/*.mqh` | PipelineEngine + Orchestrator hardening | S11 |
| BUG-S10-001..004 | 🔴 CRITICAL | `Signal/*.mqh` | SignalFilterPipeline + SignalManager compile fixes | S11 |

---

## Immediate Fix Order

1. Restore `Core/PASR.mqh` as real master include and remove `PLACEHOLDER_PASR`.
2. Remove or rename legacy `PERF_METRICS` usage in `Experts/PASR_MODULAR.mq5` to the current supported macro contract.
3. Define canonical `IDataManager` interface in a stable header, then make `DataManager` implement it with explicit include order.
4. Define/import canonical `ENUM_TRAIL_MODE` before `AdaptiveConfig.mqh` uses it, or move trail mode enum into a canonical config/types header.
5. Add range guards to AdaptiveConfig setters and validate ATR threshold ordering.
6. Reconcile session source: UTC, broker time, or configurable offset must be consistent across EA inputs and AdaptiveConfig.

---

## Sprint History

| Sprint | Focus | Key Deliverables |
|--------|-------|------------------|
| S1 | Compile fixes | BUG-007, BUG-008-S1, BUG-012 |
| S2 | Architecture integrity | BUG-001–006, BUG-009–011 |
| S7 | HealthMonitor rewrite | BUG-H1..H6 resolved |
| S8 | Runtime state ownership | SessionState wiring, Events.mqh |
| S9 | Orchestrator residuals + Analysis cleanup | O1, O4, O7, O8, X1–X7 |
| S11 | PipelineEngine + Orchestrator hardening | N01, N03, N04, N06, N07, BUG-S10-001–004 |
| S12 | Trade subfolder audit | TR-001–005 |
| S13 | CorrelationManager migration | TR-006 (v1.0 → v2.00) |
| S14 | AI subfolder audit | AI-001..AI-007 ditemukan |
| S15 | BUG-008 path confirmation | BUG-008 resolved |
| S16 | AI subfolder fixes | AI-001..AI-007 resolved |
| S17 | Infra audit partial — SnapshotManager rewrite | SNAP-001..005 resolved |
| S18 | Infra audit — JournalManager + SessionState fix | JNL-001..005 + SS-002 resolved |
| S19 | Infra audit — TEL/RPT/SAN/STM bugs logged | 14 bugs found |
| S20 | Fix TEL-001..004 + SAN-001..004 + STM-001..003 + RPT audit clear | Infra fixed except DataManager/AdaptiveConfig reopened by S21 audit |
| S21 | DataManager + AdaptiveConfig + master include audit | S21-001..S21-010 logged; Data/QA/Tools/UI still pending |

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

## Version Index — Core Files

| File | Version | Last Sprint | Status |
|------|---------|-------------|--------|
| `Core/PASR.mqh` | — | S21 audit | 🔴 CRITICAL: placeholder master include |
| `Core/Orchestrator.mqh` | v3.06 | S11 | ✅ Stable |
| `Core/PipelineEngine.mqh` | v1.01 | S11 | ✅ Stable |
| `Core/Globals.mqh` | v2.15 | S11 | ✅ Stable |
| `Core/Events.mqh` | v2.14 | S8 | ✅ Stable |
| `Core/EventBus.mqh` | — | S8 | ✅ Stable |
| `Signal/SignalManager.mqh` | v4.02 | S11 | ✅ Stable |
| `Signal/SignalFilterPipeline.mqh` | v1.02 | S11 | ✅ Stable |
| `Trade/ExecutionManager.mqh` | v3.02 | S12 | ✅ Stable |
| `Trade/RiskManager.mqh` | v2.02 | S12 | ✅ Stable |
| `Trade/RecoveryManager.mqh` | v2.18 | S12 | ✅ Stable |
| `Trade/ExitEngine.mqh` | v2.01 | S12 | ✅ Stable |
| `Trade/PositionManager.mqh` | v3.00 | S12 | ✅ Stable |
| `Trade/CorrelationManager.mqh` | v2.00 | S13 | ✅ Stable |
| `AI/AIOrchestrator.mqh` | v2.02 | S16 | ✅ Stable |
| `AI/AIFeatureBuilder.mqh` | v2.01 | S16 | ✅ Stable |
| `AI/AIInference.mqh` | v2.01 | S16 | ✅ Stable |
| `AI/AIEnsemble.mqh` | v2.01 | S16 | ✅ Stable |
| `AI/AITrainer.mqh` | v2.01 | S16 | ✅ Stable |
| `Infra/HealthMonitor.mqh` | v2.00 | S7 | ✅ Stable |
| `Infra/SessionState.mqh` | v1.01 | S18 | ✅ Stable |
| `Infra/SnapshotManager.mqh` | v2.00 | S17 | ✅ Stable |
| `Infra/JournalManager.mqh` | v2.00 | S18 | ✅ Stable |
| `Infra/TelemetryRecorder.mqh` | v2.00 | S20 | ✅ Stable |
| `Infra/PerformanceReport.mqh` | v1.00 | S20 | ✅ Stable |
| `Infra/SanityManager.mqh` | v2.00 | S20 | ✅ Stable |
| `Infra/StateManager.mqh` | v2.00 | S20 | ✅ Stable |
| `Infra/DataManager.mqh` | v2.00 | S21 audit | 🔴 CRITICAL: `IDataManager` inheritance/interface unresolved |
| `Infra/AdaptiveConfig.mqh` | v2.00 | S21 audit | 🔴 CRITICAL: `ENUM_TRAIL_MODE` dependency unresolved |
| `Analysis/SRManager.mqh` | — | — | ⚠️ Audit needed (54KB) |
| `Analysis/Pattern/*.mqh` | — | — | 🔴 Not audited |
| `Data/*.mqh` | — | — | 🔴 Not audited |
| `QA/*.mqh` | — | — | 🔴 Not audited |
| `UI/*.mqh` | — | — | 🔴 Not audited |
| `Tools/*.mqh` | — | — | 🔴 Not audited |
| `Experts/PASR_MODULAR.mq5` | v13.01 | S21 audit | 🔴 CRITICAL: still uses removed `PERF_METRICS` flag |

---

© 2026 Agsicentre — PASR EA. All rights reserved.
