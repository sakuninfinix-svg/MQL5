# PASR — Price Action Support Resistance EA

> **Architecture:** Pipeline Orchestration (migrated from Monolith v9, Sprint 1–19)
> **Last updated:** Sprint 19 (2026-05-24)
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
│   ├── SRManager.mqh        ← ⚠ 54KB — Sprint 20 decomposition target
│   ├── ZoneManager.mqh      ← Supply/Demand zones
│   ├── MarketRegimeDetector.mqh
│   ├── AdaptiveParameterManager.mqh
│   └── Pattern/             ← Candlestick pattern sub-module (audit pending S20)
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
├── Infra/                   ← ✅ S19 Audited (10/10 files)
│   ├── HealthMonitor.mqh    ← v2.00 — BUG-H1..H6 fixed (S7)
│   ├── SessionState.mqh     ← v1.01 — SS-001 CLOSED, SS-002 FIXED (S18)
│   ├── SnapshotManager.mqh  ← v2.00 — SNAP-001..005 fixed (S17)
│   ├── JournalManager.mqh   ← v2.00 — JNL-001..005 fixed (S18) ✅
│   ├── TelemetryRecorder.mqh← v1.00 — TEL-001..004 found (S19) ⚠ fix S20
│   ├── PerformanceReport.mqh← v1.00 — RPT-001..003 found (S19) ⚠ fix S20
│   ├── DataManager.mqh      ← audit pending S20
│   ├── SanityManager.mqh    ← v1.00 — SAN-001..004 found (S19) ⚠ fix S20
│   ├── StateManager.mqh     ← v1.00 — STM-001..003 found (S19) ⚠ fix S20
│   └── AdaptiveConfig.mqh   ← audit pending S20
│
├── Data/                    ← audit pending S20
├── QA/                      ← audit pending S20
├── Tools/                   ← audit pending S20
├── UI/                      ← audit pending S20
└── docs/                    ← internal documentation

Experts/
├── PASR_MODULAR.mq5         ← ✅ EA entry point v13.00
└── PASR.mq5                 ← Legacy monolith (deprecated, do not extend)
```

---

## Compilation Flags

```cpp
#define PASR_QA_BUILD    // Enable QA modules (LatencySimulator, chaos tests)
#define PASR_DEBUG       // Verbose logging per manager
```

> ⚠️ **Old flags removed:** `QA_BUILD`, `OOP_ARCHITECTURE`, `PERF_METRICS` — do NOT use.

---

## Bug Tracker

### 🔴 OPEN

#### Infra/TelemetryRecorder.mqh — 4 bugs (S19 audit)

| ID | Severity | Description |
|----|----------|-------------|
| **TEL-001** | 🔴 CRITICAL | `Initialize()` override signature salah — `virtual bool Initialize() override` tidak match `IManager::Initialize(IDataManager*, CEventBus*)`. Compile error karena IManager tidak punya `Initialize()` tanpa parameter. Perlu diganti `virtual bool Init(IDataManager *data, CEventBus *bus) override` |
| **TEL-002** | 🔴 CRITICAL | `EventSubscribe()` dipanggil tapi method ini **tidak ada** di `IManager` — harusnya `m_bus->Subscribe(this, EVENT_ID_*)` atau `RegisterEvent()` sesuai EventBus contract |
| **TEL-003** | 🟠 HIGH | `#include <File.mqh>` — MQL5 standard library path pakai `<>` bukan `""`, tapi `CFile` class dari `<File.mqh>` tidak expose `WriteString()` + `WriteLine()` + `Flush()` — semua I/O harus lewat `FileWrite*()` built-in function dengan handle int, bukan object method |
| **TEL-004** | 🟡 MEDIUM | `m_buffer_size = ArrayResize(m_buffer, MAX_BUFFER_SIZE)` di constructor — `ArrayResize()` me-return jumlah elemen berhasil di-resize, bukan index. `m_buffer_size` harusnya dimulai dari `0` (jumlah elemen terisi), bukan `MAX_BUFFER_SIZE`. Setiap push baru harusnya `m_buffer[m_buffer_size++]` tapi constructor langsung set ke 100 sehingga buffer selalu dianggap penuh dan setiap push langsung Flush() |

#### Infra/PerformanceReport.mqh — 3 bugs (S19 audit)

| ID | Severity | Description |
|----|----------|-------------|
| **RPT-001** | 🔴 CRITICAL | `m_journal.GetEntry(i)` return `const JournalEntry *` — pointer ke internal array. Tapi `JournalEntry` struct tidak dideklarasikan di `PerformanceReport.mqh`, hanya ada di `JournalManager.mqh`. Include ada tapi jika `JournalManager.mqh` berubah struct-nya, `RPT` tidak recompile. Tidak ada guard terhadap NULL pointer sebelum akses `e.aiScore`, `e.direction`, dll — bisa segfault jika journal kosong |
| **RPT-002** | 🟠 HIGH | `m_journal.GetDailyPnL(dailyPnL)` dipanggil dengan `double dailyPnL[]` (array lokal) — tapi signature `GetDailyPnL()` di `JournalManager.mqh` v2.00 belum diaudit. Jika `JOURNAL_DAILY_SIZE` tidak didefinisikan di JournalManager include, `BuildEquitySVG(dailyPnL, JOURNAL_DAILY_SIZE)` akan compile error karena `JOURNAL_DAILY_SIZE` undefined |
| **RPT-003** | 🟡 MEDIUM | `ENUM_MARKET_REGIME` dan `ENUM_TRADING_SESSION` digunakan di `BuildRegimeRows()` dan `BuildSessionRows()` tapi tidak di-include. Depend pada transitif include dari `JournalManager.mqh` — rawan break jika include chain berubah. Harus explicit `#include "../Analysis/MarketRegimeDetector.mqh"` |

#### Infra/SanityManager.mqh — 4 bugs (S19 audit)

| ID | Severity | Description |
|----|----------|-------------|
| **SAN-001** | 🔴 CRITICAL | `Init(IDataManager *data, CEventBus *bus) override` dipanggil tapi tidak ada `EventSubscribe()` atau `m_bus->Subscribe()` — `CSanityManager` tidak menerima events apapun dari EventBus. Tidak subscribe ke `EVENT_ID_SYSTEM_WARNING` padahal dia yang dispatch event tersebut (circular gap) |
| **SAN-002** | 🔴 CRITICAL | `CheckFreshness()` selalu return `true` — body berisi comment "Basic check passed, detailed stale check done in OnTimer" tapi **tidak ada OnTimer handler**. Stale tick detection adalah salah satu alasan utama SanityManager ada, tapi fungsinya dead code |
| **SAN-003** | 🟠 HIGH | `CheckPriceGap()` pakai `tick.last` bukan `tick.bid`. Di Forex, `tick.last` selalu `0` karena tidak ada last-traded-price — hanya `bid` dan `ask` yang valid. Gap check tidak pernah aktif di Forex instrument |
| **SAN-004** | 🟡 MEDIUM | `SendEvent()` membangun `PASREvent` dengan hanya `id`, `priority`, `tag` — tidak mengisi `payload` atau `string_value` dengan `msg` yang dikirim. Message hilang, subscriber menerima event kosong tanpa context |

#### Infra/StateManager.mqh — 3 bugs (S19 audit)

| ID | Severity | Description |
|----|----------|-------------|
| **STM-001** | 🟠 HIGH | `ComputeStateCRC()` bukan CRC32 sejati — hanya XOR beberapa field dengan seed `0x12345678`. Collision rate sangat tinggi: dua state berbeda dengan field yang XOR-cancel bisa menghasilkan CRC sama. Contoh: `consecLoss=1, tradesToday=2` vs `consecLoss=3, tradesToday=0` → XOR sama. Untuk financial state persistence, perlu CRC32 polinom atau minimal FNV-1a hash |
| **STM-002** | 🟡 MEDIUM | `CheckDailyReset()` kondisi: `today > m_state.lastTradeDate && m_state.tradesToday > 0` — reset hanya terjadi jika sudah ada trade hari sebelumnya. Jika EA restart di hari baru setelah hari tanpa trade, `dailyStartBalance` tidak di-update ke balance saat ini. Balance bisa stale dari beberapa hari lalu |
| **STM-003** | 🟡 MEDIUM | `CStateManager` tidak extend `IManager` — standalone class. Tidak masalah secara desain (StateManager dipanggil langsung oleh RiskManager, bukan pipeline), tapi perlu dikonfirmasi di Orchestrator bahwa `m_state->OnDeinit()` dipanggil sebelum `FreeAll()` agar final save terjadi |

#### Analysis & Lainnya

| ID | Severity | File | Description | Target |
|----|----------|------|-------------|--------|
| **A1** | 🟠 HIGH | `Analysis/SRManager.mqh` | 54KB monolith — perlu decomposition ke SRDetector + SRZoneStore + SRScorer | S20 |
| **A5** | 🟠 HIGH | `Analysis/Pattern/*.mqh` | Pattern subfolder belum diaudit untuk IManager compliance | S20 |
| **INF-10** | 🔴 TBD | `Infra/AdaptiveConfig.mqh` | Belum diaudit | S20 |
| **INF-7** | 🔴 TBD | `Infra/DataManager.mqh` | Belum diaudit | S20 |
| **DATA-?** | 🔴 TBD | `Data/` | Folder belum diaudit | S20 |
| **QA-?** | 🔴 TBD | `QA/` | Folder belum diaudit | S20 |
| **UI-?** | 🔴 TBD | `UI/` | Folder belum diaudit | S20 |
| **TOOLS-?** | 🔴 TBD | `Tools/` | Folder belum diaudit | S20 |

---

### ✅ RESOLVED — Sprint 1–18

| ID | Severity | File | Fix | Sprint |
|----|----------|------|-----|--------|
| **JNL-001** | 🔴 CRITICAL | `Infra/JournalManager.mqh` | Tidak extend IManager — rewrite `class CJournalManager : public IManager` | S18 |
| **JNL-002** | 🔴 CRITICAL | `Infra/JournalManager.mqh` | Include `AdaptiveConfig.mqh` bukan `IManager.mqh` — pipeline contract violation | S18 |
| **JNL-003** | 🔴 CRITICAL | `Infra/JournalManager.mqh` | `OnPositionClosed()` tidak via EventBus — Stage_Journal tidak bisa trigger. `OnEvent(EVENT_ID_TRADE_CLOSED)` ditambahkan | S18 |
| **JNL-004** | 🟠 HIGH | `Infra/JournalManager.mqh` | CSV open `FILE_READ\|FILE_WRITE` untuk append — flag tidak valid MQL5. Diganti `FILE_WRITE\|FILE_CSV\|FILE_ANSI` + `FileSeek(SEEK_END)` | S18 |
| **JNL-005** | 🟡 MEDIUM | `Infra/JournalManager.mqh` | Standalone `LogInfo/LogWarn/LogError()` — digantikan `PASRLog*` dari `Globals.mqh` | S18 |
| **SS-002** | 🟡 MEDIUM | `Infra/SessionState.mqh` | `IsNewDay()` bandingkan `session_start` bukan midnight-floor — fixed dengan `MidnightFloor()` helper + `GV_TODAY_MIDNIGHT` persistence | S18 |
| **SS-001** | 🟡 MEDIUM | `Infra/SessionState.mqh` | `EVENT_ID_SESSION_UPDATED` belum ada di Events.mqh — **CLOSED**: sudah ada di v2.14 (S8) | S8 |
| **SNAP-001..005** | 🔴 CRITICAL | `Infra/SnapshotManager.mqh` | IManager extend, include fix, PointerToStruct→XOR checksum, signature override, static→member index | S17 |
| **BUG-H1..H6** | 🔴 CRITICAL | `Infra/HealthMonitor.mqh` | EventBus* type, SendEvent→Push, PASR_MemoryUsage, recovery flag, dual-purpose flag, heartbeat false alarm | S7 |
| **AI-001..007** | 🔴 CRITICAL | `AI/*.mqh` | AIFeatureBuilder pending buffer, ATR handle consolidation, real SGD backprop, ensemble diversity, open_features cache, baseline shift, MathTanh NaN guard | S16 |
| **BUG-008** | 🟠 HIGH | `Experts/PASR_MODULAR.mq5` | Path dikonfirmasi root Experts/ | S15 |
| **TR-001..006** | 🔴 CRITICAL | `Trade/*.mqh` | ExitEngine, PositionManager, RiskManager, ExecutionManager, RecoveryManager, CorrelationManager | S12–13 |
| BUG-001..012 | 🔴 CRITICAL | `Core/*.mqh` | Monolith cleanup, pipeline wiring, compile fixes | S1–2 |
| O1,O4,O7,O8 | 🔴 CRITICAL | `Core/Orchestrator.mqh` | ENUM_PIPELINE_STAGE, SessionState wiring, BarChanged race, JournalManager | S9 |
| X1–X7 | 🔴 CRITICAL | `Core/PASR_Executor.mqh` | DELETED — monolith zombie | S9 |
| S8-001,S8-005 | 🔴 CRITICAL | `Core/Events.mqh` | Missing event IDs, non-existent data_i[] | S8 |
| N01,N03,N04,N06,N07 | 🔴 CRITICAL | `Core/*.mqh` | PipelineEngine + Orchestrator hardening | S11 |
| BUG-S10-001..004 | 🔴 CRITICAL | `Signal/*.mqh` | SignalFilterPipeline + SignalManager compile fixes | S11 |

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
| S19 | Infra audit — TelemetryRecorder, PerformanceReport, SanityManager, StateManager | TEL-001..004, RPT-001..003, SAN-001..004, STM-001..003 logged |
| S20 | Fix TEL/RPT/SAN/STM bugs + DataManager + AdaptiveConfig + Data/QA/Tools/UI | _(planned)_ |

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
| `Infra/TelemetryRecorder.mqh` | v1.00 | S19 | ⚠️ 4 bugs open (TEL-001..004) |
| `Infra/PerformanceReport.mqh` | v1.00 | S19 | ⚠️ 3 bugs open (RPT-001..003) |
| `Infra/SanityManager.mqh` | v1.00 | S19 | ⚠️ 4 bugs open (SAN-001..004) |
| `Infra/StateManager.mqh` | v1.00 | S19 | ⚠️ 3 bugs open (STM-001..003) |
| `Infra/DataManager.mqh` | — | — | 🔴 Not audited |
| `Infra/AdaptiveConfig.mqh` | — | — | 🔴 Not audited |
| `Analysis/SRManager.mqh` | — | — | ⚠️ Audit needed (54KB) |
| `Analysis/Pattern/*.mqh` | — | — | 🔴 Not audited |
| `Data/*.mqh` | — | — | 🔴 Not audited |
| `QA/*.mqh` | — | — | 🔴 Not audited |
| `UI/*.mqh` | — | — | 🔴 Not audited |
| `Tools/*.mqh` | — | — | 🔴 Not audited |
| `Experts/PASR_MODULAR.mq5` | v13.00 | S15 | ✅ Path confirmed |

---

© 2026 Agsicentre — PASR EA. All rights reserved.
