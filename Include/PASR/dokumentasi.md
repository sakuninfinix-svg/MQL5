# Dokumentasi Detail PASR

> Dokumen ini adalah versi panjang dari README PASR.
> README utama sengaja dibuat ringkas, sedangkan detail arsitektur, riwayat sprint, bug historis, dan audit notes disimpan di sini.

---

## 1. Tujuan Dokumen

File `dokumentasi.md` dipakai untuk:

- Menjelaskan arsitektur PASR secara lebih lengkap.
- Menyimpan riwayat audit dan sprint.
- Menyimpan bug historis yang sudah resolved.
- Menjadi catatan teknis panjang tanpa membuat `README.md` terlalu berat.
- Menghubungkan bug open ke GitHub Issues.

Bug aktif tidak lagi dikelola sebagai tabel panjang di README. Bug aktif harus hidup di GitHub Issues agar bisa diberi label, assignee, komentar, prioritas, dan status close.

---

## 2. Ringkasan Arsitektur

PASR sedang dimigrasikan ke **Centralized Modular Pipeline Architecture**.
Kontrol lifecycle, registry, dependency, dan pipeline ownership berada di `Central/`,
sedangkan logic trading tetap berada di module domain.

Prinsip utamanya:

1. `OnTick()` harus ringan.
2. Logic berat dijalankan dari `OnTimer()`.
3. Semua module utama diakses melalui `CPASRKernel`, dengan `CBackendAdapter` sebagai compatibility backend sementara.
4. Komunikasi antar module memakai `CEventBus`.
5. State harus dimiliki manager yang tepat, bukan tersebar di EA entry point.
6. `Experts/PASR_MODULAR.mq5` hanya menjadi wrapper lifecycle EA.
7. Include utama harus melalui `PASR/Core/PASR.mqh`.

---

## 3. Alur Runtime

```text
OnTick()
  -> Push EVENT_PRICE_UPDATE
  -> Deteksi new bar ringan
  -> Set flag new bar jika diperlukan

OnTimer()
  -> DrainQueue()
  -> CPipelineEngine::ExecutePipeline(PipelineContext)
      01 DataSync
      02 AnalysisSR
      03 AnalysisZone
      04 PatternRec
      05 RegimeDetect
      06 SignalGen
      07 AIInference
      08 RiskCheck
      09 AdaptiveParams
      10 Execution
      11 PosMgmt
      12 Recovery
      13 Dashboard
      14 Journal
  -> DrainQueue()

OnTradeTransaction()
  -> RecoveryManager
  -> SessionState
  -> AIOrchestrator backprop / feedback
```

---

## 4. Stage Pipeline

| Stage | Nama | Tanggung Jawab |
|------:|------|----------------|
| 01 | DataSync | Sinkronisasi data harga, ATR, dan cache market data |
| 02 | AnalysisSR | Analisis support dan resistance |
| 03 | AnalysisZone | Update supply/demand zone |
| 04 | PatternRec | Deteksi candlestick pattern |
| 05 | RegimeDetect | Deteksi kondisi market: trending, ranging, volatile, quiet |
| 06 | SignalGen | Gabungkan sumber sinyal dan voting/confluence |
| 07 | AIInference | Skoring AI / filter confidence |
| 08 | RiskCheck | Validasi risk, spread, correlation, max position |
| 09 | AdaptiveParams | Adaptasi parameter berdasarkan regime/session/volatility |
| 10 | Execution | Eksekusi order dan ticket capture |
| 11 | PosMgmt | Position scan, break-even, trailing, exit engine |
| 12 | Recovery | Fakeout/recovery management |
| 13 | Dashboard | Update UI/HUD |
| 14 | Journal | Logging trade dan event penting |

---

## 5. Peta Folder Detail

```text
Include/PASR/
├── Core/
│   ├── PASR.mqh
│   ├── Orchestrator.mqh
│   ├── PipelineEngine.mqh
│   ├── PipelineTypes.mqh
│   ├── Events.mqh
│   ├── EventBus.mqh
│   ├── IManager.mqh
│   ├── Globals.mqh
│   ├── AsyncOrderManager.mqh
│   ├── HighFreqTimer.mqh
│   ├── LatencyOptimizer.mqh
│   ├── StateOwnershipMap.mqh
│   └── PASR_SymbolManager.mqh
│
├── Analysis/
│   ├── SRManager.mqh
│   ├── ZoneManager.mqh
│   ├── MarketRegimeDetector.mqh
│   ├── AdaptiveParameterManager.mqh
│   └── Pattern/
│
├── Signal/
│   ├── SignalManager.mqh
│   └── SignalFilterPipeline.mqh
│
├── Trade/
│   ├── ExecutionManager.mqh
│   ├── RiskManager.mqh
│   ├── RecoveryManager.mqh
│   ├── RecoveryEngine.mqh
│   ├── ExitEngine.mqh
│   ├── PositionManager.mqh
│   ├── TradePlan.mqh
│   └── CorrelationManager.mqh
│
├── AI/
│   ├── AIOrchestrator.mqh
│   ├── AIFeatureBuilder.mqh
│   ├── AIInference.mqh
│   ├── AIEnsemble.mqh
│   ├── AITrainer.mqh
│   ├── AITypes.mqh
│   ├── ConfidenceCalibrator.mqh
│   ├── OnlineLearningGuard.mqh
│   ├── AICalibrationBridge.mqh
│   ├── AISignalSource.mqh
│   ├── ModelRegistry.mqh
│   └── ONNXBridge.mqh
│
├── Infra/
│   ├── HealthMonitor.mqh
│   ├── SessionState.mqh
│   ├── SnapshotManager.mqh
│   ├── JournalManager.mqh
│   ├── TelemetryRecorder.mqh
│   ├── PerformanceReport.mqh
│   ├── SanityManager.mqh
│   ├── StateManager.mqh
│   ├── DataManager.mqh
│   └── AdaptiveConfig.mqh
│
├── Data/
├── QA/
├── Tools/
├── UI/
└── docs/
```

---

## 6. Open Work — GitHub Issues Status

| README ID | GitHub Issue | Scope | Status |
|-----------|--------------|-------|--------|
| S21-001 | #180 | Restore `Core/PASR.mqh` master include | ✅ CLOSED |
| S21-002 | #181 | Remove legacy `PERF_METRICS` from `PASR_MODULAR.mq5` | ✅ CLOSED |
| S21-003, S21-004, S21-005, INF-7 | #182 | Fix `DataManager` / `IDataManager` contract and initialization | ✅ CLOSED |
| S21-006, S21-007, S21-008, S21-009, INF-10 | #183 | Harden `AdaptiveConfig` dependencies and validation | ✅ CLOSED |
| A1 | #184 | Decompose `Analysis/SRManager.mqh` monolith | ✅ CLOSED |
| A5 | #185 | Audit `Analysis/Pattern` module for `IManager` compliance | ✅ CLOSED |
| DATA-?, QA-?, UI-?, TOOLS-? | #186 | Audit pending PASR folders | ✅ CLOSED |

---

## 7. Detail Open Issues (Historical Reference)

### #180 — Restore `Core/PASR.mqh` master include [RESOLVED]

Status: **CLOSED**

Masalah:

`Core/PASR.mqh` ditemukan hanya berisi placeholder `PLACEHOLDER_PASR`.

Dampak:

`Experts/PASR_MODULAR.mq5` memakai master include tersebut. Pada arsitektur saat ini EA mendeklarasikan `CPASRKernel`; jika master include kosong/placeholder, class dan dependency utama tidak terdefinisi.

Arahan fix:

- Hapus placeholder.
- Jadikan `PASR.mqh` sebagai master include sungguhan.
- Pastikan include ordering stabil.
- Pastikan user cukup include satu file: `<PASR/Core/PASR.mqh>`.

Hasil:
- `Include/PASR/Core/PASR.mqh` v1.00 kini menjadi master include lengkap dengan 10 layer dependency.

---

### #181 — Remove legacy `PERF_METRICS` [RESOLVED]

Status: **CLOSED**

Masalah:

`Experts/PASR_MODULAR.mq5` masih mendefinisikan `PERF_METRICS`, padahal flag lama sudah dinyatakan removed.

Arahan fix:

- Hapus `#define PERF_METRICS`.
- Gunakan flag canonical bila masih butuh performance metrics.
- Samakan semua conditional compilation dengan dokumentasi.

Hasil:
- `PERF_METRICS` dihapus dari `PASR_MODULAR.mq5`.
- Diganti dengan `PASR_QA_BUILD` untuk QA/stress testing.

---

### #182 — Fix `DataManager` / `IDataManager` contract [RESOLVED]

Status: **CLOSED**

Masalah yang digabung:

- `DataManager` mewarisi `IDataManager`.
- `IManager.mqh` hanya forward-declare `IDataManager`.
- Definisi interface canonical belum terlihat jelas.
- Beberapa method memakai `override` terhadap kontrak yang belum jelas.
- `m_startBalance` sebaiknya masuk initializer list.

Arahan fix:

- Buat atau restore header canonical untuk `IDataManager`.
- Include header tersebut secara eksplisit sebelum inheritance.
- Pastikan method yang dioverride benar-benar ada di interface.
- Rapikan constructor initializer list.

Hasil:
- Kontrak `IDataManager` telah diperbaiki.
- `DataManager` kini comply dengan interface canonical.

---

### #183 — Harden `AdaptiveConfig` [RESOLVED]

Status: **CLOSED**

Masalah yang digabung:

- `ENUM_TRAIL_MODE`, `TRAIL_ATR`, `TRAIL_NONE`, `TRAIL_SWING` dipakai tetapi definisi canonical belum jelas.
- Setter policy tidak punya range guard.
- `SetATRThresholds()` tidak validasi `low < high`.
- `DetectSession()` hardcoded `TimeGMT()`.

Arahan fix:

- Definisikan/import `ENUM_TRAIL_MODE` dari header canonical.
- Tambahkan guard enum range.
- Validasi threshold ATR.
- Tentukan sumber waktu sesi yang canonical: UTC, broker time, atau configurable offset.

Hasil:
- `AdaptiveConfig.mqh` v2.00 telah mendefinisikan enum canonical.
- Validasi threshold dan session detection telah diperbaiki.

---

### #184 — Decompose `SRManager.mqh` [RESOLVED]

Status: **CLOSED**

Masalah:

`SRManager.mqh` berukuran besar dan menjadi monolith.

Target decomposition:

- `SRDetector` — pivot detection murni (stateless)
- `SRZoneStore` — zone storage, clustering, lifecycle
- `SRScorer` — scoring logic (merged into SRZoneStore)

Tujuan:

Membuat SR module lebih mudah diuji, dipelihara, dan tidak menjadi bottleneck arsitektur.

Hasil:
- `SRManager.mqh` v6.0.0 kini hanya 213 baris (thin orchestrator).
- `SRDetector.mqh` v1.0.1 — 243 baris (pure pivot scanner).
- `SRZoneStore.mqh` v1.0.0 — 461 baris (zone storage & lifecycle).
- Total 917 baris terpisah dengan tanggung jawab jelas.

---

### #185 — Audit `Analysis/Pattern` [RESOLVED]

Status: **CLOSED**

Target audit:

- Apakah pattern module harus menjadi manager atau helper murni.
- Apakah sudah comply dengan `IManager` bila ikut EventBus.
- Apakah include guard dan dependency sudah aman.
- Apakah ada dependency lama dari monolith.

Hasil:
- `PatternManager.mqh` v2.03 telah comply dengan `IManager`.
- Extend `IManager` dengan `Initialize()`, `DeclareEvents()`, `OnEvent()`, `HandlerName()`.
- BUG-017, BUG-018, BUG-019 telah diperbaiki.
- History tracking dengan `CPatternRecord` wrapper berfungsi.

---

### #186 — Audit `Data`, `QA`, `UI`, `Tools` [RESOLVED]

Status: **CLOSED**

Folder pending:

- `Data/` — 4 files (DataManager.mqh, RegimeTypes.mqh, SRStruct.mqh, SymbolScanner.mqh)
- `QA/` — 14 files (stress test, assertions, mocks, harnesses)
- `UI/` — 2 files (DashboardManager.mqh, README.md)
- `Tools/` — 8 files (Audit.mqh, TickCache.mqh, utilities)

Audit hasil:

**Data/**
- ✅ `DataManager.mqh` — comply dengan `IDataManager`
- ✅ `RegimeTypes.mqh` — enum definitions clean
- ✅ `SRStruct.mqh` — base struct untuk SR
- ✅ `SymbolScanner.mqh` — extend `IManager`, multi-symbol support

**QA/**
- ✅ `QAStressTest.mqh` — chaos engineering & stress testing
- ✅ `LatencySimulator.mqh` — latency injection
- ✅ `PipelineHarness.mqh` — test harness untuk pipeline
- ✅ Mock objects (`MockDataManager`, `MockEventBus`) tersedia
- ✅ Test runners (`TestRunner.mqh`, `SmokeTest.mqh`) tersedia

**UI/**
- ✅ `DashboardManager.mqh` v2.00 — full rewrite, lazy redraw
- ✅ Include guards proper
- ✅ Dependency pada `JournalManager`, `AITypes`, `TradePlan`

**Tools/**
- ✅ `Audit.mqh` — automated code quality audit
- ✅ `TickCache.mqh` — O(1) tick deduplication
- ✅ Utility files (BatchProcessor, Branchless, MemoryPool, Optimizations)

Kesimpulan:
- Semua folder telah diaudit.
- Tidak ada compile blocker yang ditemukan.
- Include guards konsisten.
- Dependency order stabil.

---

## 8. Immediate Fix Order

1. #180 — Restore master include.
2. #181 — Bersihkan legacy build flag.
3. #182 — Fix kontrak `IDataManager`.
4. #183 — Fix dependency dan validation `AdaptiveConfig`.
5. #184 — Pecah `SRManager` setelah compile blocker aman.
6. #185 — Audit Pattern.
7. #186 — Audit Data, QA, UI, Tools.

---

## 9. Sprint History

| Sprint | Focus | Key Deliverables |
|--------|-------|------------------|
| S1 | Compile fixes | BUG-007, BUG-008-S1, BUG-012 |
| S2 | Architecture integrity | BUG-001–006, BUG-009–011 |
| S7 | HealthMonitor rewrite | BUG-H1..H6 resolved |
| S8 | Runtime state ownership | SessionState wiring, Events.mqh |
| S9 | Orchestrator residuals + Analysis cleanup | O1, O4, O7, O8, X1–X7 |
| S11 | PipelineEngine + Orchestrator hardening | N01, N03, N04, N06, N07, BUG-S10-001–004 |
| S12 | Trade subfolder audit | TR-001–005 |
| S13 | CorrelationManager migration | TR-006 |
| S14 | AI subfolder audit | AI-001..AI-007 found |
| S15 | BUG-008 path confirmation | BUG-008 resolved |
| S16 | AI subfolder fixes | AI-001..AI-007 resolved |
| S17 | Infra audit partial | SNAP-001..005 resolved |
| S18 | Infra audit | JNL-001..005 + SS-002 resolved |
| S19 | Infra audit | TEL/RPT/SAN/STM bugs logged |
| S20 | Infra fixes | TEL, SAN, STM fixes; RPT clear |
| S21 | Issue migration | Open bugs moved to GitHub Issues #180–#186 |

---

## 10. Historical Resolved Bug Summary

| ID | Severity | File | Fix | Sprint |
|----|----------|------|-----|--------|
| TEL-001 | CRITICAL | `Infra/TelemetryRecorder.mqh` | `Initialize()` -> `Init(IDataManager*, CEventBus*) override` | S20 |
| TEL-002 | CRITICAL | `Infra/TelemetryRecorder.mqh` | `EventSubscribe()` -> `m_bus.Subscribe()` via IManager contract | S20 |
| TEL-003 | HIGH | `Infra/TelemetryRecorder.mqh` | `CFile` object methods -> `FileOpen/FileWrite/FileFlush/FileClose` built-in | S20 |
| TEL-004 | MEDIUM | `Infra/TelemetryRecorder.mqh` | `m_buffer_count` init fixed to `0`; flush only when full | S20 |
| SAN-001..004 | CRITICAL/HIGH/MEDIUM | `Infra/SanityManager.mqh` | EventBus subscription, freshness check, bid gap detection, event tag payload | S20 |
| STM-001..003 | HIGH/MEDIUM | `Infra/StateManager.mqh` | FNV-1a hash, daily reset fix, OnDeinit contract | S20 |
| RPT-001..003 | HIGH | `Infra/PerformanceReport.mqh` | NULL guard, JOURNAL_DAILY_SIZE explicit, explicit includes | S20 |
| JNL-001..005 | CRITICAL | `Infra/JournalManager.mqh` | IManager extend, include fix, OnEvent, CSV flags, PASRLog* | S18 |
| SS-002 | MEDIUM | `Infra/SessionState.mqh` | `IsNewDay()` midnight-floor fix | S18 |
| SNAP-001..005 | CRITICAL | `Infra/SnapshotManager.mqh` | IManager extend, include fix, checksum, signature override, static-to-member index | S17 |
| AI-001..007 | CRITICAL | `AI/*.mqh` | AIFeatureBuilder, SGD backprop, ensemble diversity, MathTanh guard | S16 |
| TR-001..006 | CRITICAL | `Trade/*.mqh` | ExitEngine, PositionManager, RiskManager, ExecutionManager, RecoveryManager, CorrelationManager | S12–13 |
| BUG-H1..H6 | CRITICAL | `Infra/HealthMonitor.mqh` | EventBus pointer type, SendEvent to Push, PASR_MemoryUsage, flags | S7 |
| BUG-001..012 | CRITICAL | `Core/*.mqh` | Monolith cleanup, pipeline wiring, compile fixes | S1–2 |
| O1,O4,O7,O8 | CRITICAL | `Core/Orchestrator.mqh` | ENUM_PIPELINE_STAGE, SessionState wiring, BarChanged race, JournalManager | S9 |
| X1–X7 | CRITICAL | `Core/PASR_Executor.mqh` | Deleted monolith zombie executor | S9 |
| S8-001,S8-005 | CRITICAL | `Core/Events.mqh` | Missing event IDs | S8 |
| N01,N03,N04,N06,N07 | CRITICAL | `Core/*.mqh` | PipelineEngine and Orchestrator hardening | S11 |
| BUG-S10-001..004 | CRITICAL | `Signal/*.mqh` | SignalFilterPipeline and SignalManager compile fixes | S11 |

---

## 11. Quick Start

```cpp
#include <PASR/Core/PASR.mqh>

CPASRKernel kernel;

int OnInit()
  {
   if(kernel.Init(cfg) != INIT_SUCCEEDED)
      return INIT_FAILED;
   EventSetTimer(1);
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   kernel.OnTick();
  }

void OnTimer()
  {
   kernel.OnTimer();
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   kernel.OnTradeTransaction(trans, request, result);
  }

void OnDeinit(const int reason)
  {
   kernel.OnDeinit(reason);
  }
```

---

## 12. Dokumentasi Policy

Rekomendasi pemakaian dokumen:

- `README.md`: ringkasan dan onboarding cepat.
- `dokumentasi.md`: detail panjang, catatan audit, history, dan design notes.
- GitHub Issues: bug aktif dan backlog yang harus dikerjakan.
- Pull Request: perubahan kode dan review.

Prinsip penting:

- Jangan hapus history audit tanpa alasan.
- Jangan jadikan README sebagai bug tracker penuh.
- Jangan menutup issue sampai fix benar-benar masuk kode.
- Jika bug besar punya beberapa sub-bug, boleh digabung menjadi satu issue jika domainnya sama.
- Jika issue terlalu besar, pecah menjadi issue turunan.

---

© 2026 Agsicentre — PASR EA. All rights reserved.
