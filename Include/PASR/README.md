# PASR — Price Action Support Resistance EA

> **Architecture:** Pipeline Orchestration (migrated from Monolith v9, Sprint 1–17)
> **Last updated:** Sprint 17 (2026-05-24)
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
              Stage 14: Journal          ← CJournalManager->LogEntry()
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
│   ├── Events.mqh           ← All ENUM_EVENT_ID definitions
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
│   ├── SRManager.mqh        ← ⚠ 54KB — Sprint 18 decomposition target
│   ├── ZoneManager.mqh      ← Supply/Demand zones
│   ├── MarketRegimeDetector.mqh
│   ├── AdaptiveParameterManager.mqh
│   └── Pattern/             ← Candlestick pattern sub-module (audit pending S18)
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
├── Infra/                   ← ✅ S17 Audited (10 files)
│   ├── HealthMonitor.mqh    ← v2.00 — BUG-H1..H6 fixed (S7)
│   ├── SessionState.mqh     ← v1.00 — IManager compliant, 2 minor issues (SS-001,SS-002 open)
│   ├── SnapshotManager.mqh  ← v2.00 — SNAP-001..005 fixed (S17)
│   ├── JournalManager.mqh   ← ⚠ 17KB — audit pending S18
│   ├── TelemetryRecorder.mqh← audit pending S18
│   ├── PerformanceReport.mqh← audit pending S18
│   ├── DataManager.mqh      ← audit pending S18
│   ├── SanityManager.mqh    ← audit pending S18
│   ├── StateManager.mqh     ← audit pending S18
│   └── AdaptiveConfig.mqh   ← audit pending S18
│
├── Data/                    ← audit pending S18
├── QA/                      ← audit pending S18
├── Tools/                   ← audit pending S18
├── UI/                      ← audit pending S18
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

| ID | Severity | File | Description | Target |
|----|----------|------|-------------|--------|
| **SS-001** | 🟡 MEDIUM | `Infra/SessionState.mqh` | `BroadcastSnapshot()` menggunakan `EVENT_ID_SESSION_UPDATED` yang belum ada di `Events.mqh` — compile error jika event ID belum terdefinisi | S18 |
| **SS-002** | 🟡 MEDIUM | `Infra/SessionState.mqh` | `IsNewDay()` hanya cek `session_start` vs now, bukan midnight-floor — jika EA di-restart di hari yang sama, daily_pnl tidak di-reset karena `session_start` ikut reset | S18 |
| **A1** | 🟠 HIGH | `Analysis/SRManager.mqh` | 54KB monolith — perlu decomposition ke SRDetector + SRZoneStore + SRScorer | S18 |
| **A5** | 🟠 HIGH | `Analysis/Pattern/*.mqh` | Pattern subfolder belum diaudit untuk IManager compliance | S18 |
| **INF-?** | 🔴 TBD | `Infra/JournalManager.mqh` + 6 file lain | 7 file Infra belum diaudit (JournalManager 17KB, TelemetryRecorder, PerformanceReport, DataManager, SanityManager, StateManager, AdaptiveConfig) | S18 |
| **DATA-?** | 🔴 TBD | `Data/` | Folder belum diaudit | S18 |
| **QA-?** | 🔴 TBD | `QA/` | Folder belum diaudit | S18 |
| **UI-?** | 🔴 TBD | `UI/` | Folder belum diaudit | S18 |
| **TOOLS-?** | 🔴 TBD | `Tools/` | Folder belum diaudit | S18 |

---

### ✅ RESOLVED — Sprint 1–17

| ID | Severity | File | Fix | Sprint |
|----|----------|------|-----|--------|
| **SNAP-001** | 🔴 CRITICAL | `Infra/SnapshotManager.mqh` | Tidak extend IManager — rewrite jadi `class CSnapshotManager : public IManager` | S17 |
| **SNAP-002** | 🔴 CRITICAL | `Infra/SnapshotManager.mqh` | Include `../Core/Config/SystemConfig.mqh` tidak ada — diganti `IManager.mqh` + `EventBus.mqh` | S17 |
| **SNAP-003** | 🔴 CRITICAL | `Infra/SnapshotManager.mqh` | `CalculateChecksum()` pakai `PointerToStruct()` cast — TIDAK VALID di MQL5. Diganti field-by-field XOR checksum | S17 |
| **SNAP-004** | 🟠 HIGH | `Infra/SnapshotManager.mqh` | Signature `Initialize(string folder)` tidak cocok dengan `IManager::Initialize(CEventBus*)` — sekarang ada `Initialize(CEventBus*)` override + `Initialize(CEventBus*, string folder)` extended | S17 |
| **SNAP-005** | 🟡 MEDIUM | `Infra/SnapshotManager.mqh` | `static int s_index` dalam `SaveSnapshot()` — persist cross-EA-reload tapi reset saat terminal restart → desync. Diganti member `m_save_index` | S17 |
| **BUG-H1..H6** | 🔴 CRITICAL | `Infra/HealthMonitor.mqh` | EventBus* type, SendEvent→Push, PASR_MemoryUsage, recovery flag, dual-purpose flag, heartbeat false alarm | S7 |
| **AI-001** | 🟠 HIGH | `AI/AIFeatureBuilder.mqh` | Pending buffer pattern — inject sebelum Build() | S16 |
| **AI-002** | 🔴 CRITICAL | `AI/AIFeatureBuilder.mqh` | 4 ATR handle terpisah (m_hATR3/5/10/20) | S16 |
| **AI-003** | 🔴 CRITICAL | `AI/AITrainer.mqh` | Real SGD backprop via SGDUpdate() + SetEnsemble() | S16 |
| **AI-004** | 🟠 HIGH | `AI/AIEnsemble.mqh` | Seed table {42,137,271,919} — ensemble diversity aktif | S16 |
| **AI-005** | 🟡 MEDIUM | `AI/AIOrchestrator.mqh` | m_open_features cache saat EVENT_ID_TRADE_OPEN | S16 |
| **AI-006** | 🟡 MEDIUM | `AI/AIFeatureBuilder.mqh` | Baselines shift=1 (no lookahead) | S16 |
| **AI-007** | 🟡 MEDIUM | `AI/AIInference.mqh` | MathTanh() — no NaN | S16 |
| **BUG-008** | 🟠 HIGH | `Experts/PASR_MODULAR.mq5` | Path dikonfirmasi root Experts/ | S15 |
| **TR-001..TR-006** | 🔴 CRITICAL | `Trade/*.mqh` | ExitEngine, PositionManager, RiskManager, ExecutionManager, RecoveryManager, CorrelationManager | S12–13 |
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
| S17 | Infra subfolder audit + SnapshotManager rewrite | SNAP-001..005 resolved; SS-001,SS-002 open; 7 Infra files queued S18 |
| S18 | Infra remaining (7 files) + Data/QA/Tools/UI audit + SRManager decomposition | _(planned)_ |

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
| `Core/Events.mqh` | — | S8 | ✅ Stable |
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
| `Infra/SessionState.mqh` | v1.00 | S17 | ⚠️ 2 issues open (SS-001,SS-002) |
| `Infra/SnapshotManager.mqh` | v2.00 | S17 | ✅ Stable |
| `Infra/JournalManager.mqh` | — | — | ⚠️ Audit needed (17KB) |
| `Infra/TelemetryRecorder.mqh` | — | — | 🔴 Not audited |
| `Infra/PerformanceReport.mqh` | — | — | 🔴 Not audited |
| `Infra/DataManager.mqh` | — | — | 🔴 Not audited |
| `Infra/SanityManager.mqh` | — | — | 🔴 Not audited |
| `Infra/StateManager.mqh` | — | — | 🔴 Not audited |
| `Infra/AdaptiveConfig.mqh` | — | — | 🔴 Not audited |
| `Analysis/SRManager.mqh` | — | — | ⚠️ Audit needed (54KB) |
| `Analysis/Pattern/*.mqh` | — | — | 🔴 Not audited |
| `Data/*.mqh` | — | — | 🔴 Not audited |
| `QA/*.mqh` | — | — | 🔴 Not audited |
| `UI/*.mqh` | — | — | 🔴 Not audited |
| `Tools/*.mqh` | — | — | 🔴 Not audited |
| `Experts/PASR_MODULAR.mq5` | v13.00 | S15 | ✅ Path confirmed |

## 🚨 FUNDAMENTAL BUSINESS LOGIC & STATE CHAOS (Pre-Architecture Migration)

**⚠️ PERINGATAN KRITIS:** Sebelum mempertimbangkan migrasi ke arsitektur Path atau peningkatan kompleksitas lainnya, **WAJIB** mengatasi kekacauan fundamental berikut. Masalah ini bukan sekadar bug teknis, melainkan cacat desain logika bisnis yang dapat menyebabkan kerugian finansial nyata.

### 1. 🔴 STATE MANAGEMENT CHAOS — Tidak Ada "Single Source of Truth"

| Gejala | Dampak Finansial | Root Cause |
|--------|------------------|------------|
| **Multiple position trackers**: `PositionManager.ScanPositions()`, `RecoveryManager.m_positions[]`, `SessionState.m_open_positions[]`, `ExitEngine` scan mandiri | **Double execution risk**: Posisi yang sama bisa diproses 2-3x oleh modul berbeda → close partial ganda, lot calculation error, trailing stop konflik | Tidak ada ownership map yang jelas. Setiap modul maintain state sendiri tanpa synchronization mechanism |
| **TradePlan vs Actual Execution mismatch**: `TradePlan` struct dibuat di Stage 6 (SignalGen) tetapi dieksekusi di Stage 10 (Execution) dengan delay 4 stage | **Slippage tidak terakomodasi**: Price bergerak antara planning dan execution, SL/TP menjadi tidak valid, tapi tidak ada re-validation | Pipeline terlalu panjang tanpa feedback loop. ExecutionManager tidak memvalidasi ulang market condition sebelum kirim order |
| **Event-driven state update race**: `OnTradeTransaction()` update `SessionState`, `RecoveryManager`, `AIOrchestrator` secara paralel tanpa locking | **State corruption**: Jika event diproses out-of-order, counter daily loss bisa negatif, recovery attempt count bisa > max_allowed | Tidak ada mutex/semaphore untuk critical sections. MQL5 single-threaded tapi event queue bisa cause re-entrancy |

**Fix Priority:**
- Buat `CStateOwnershipMap` global yang mendefinisikan **SIAPA** memiliki hak write untuk setiap state variable
- Implementasi `CAssertStateLock()` helper untuk detect race condition di runtime
- Unified `CPositionRegistry` class sebagai satu-satunya sumber kebenaran untuk posisi terbuka

---

### 2. 🟠 PARAMETER ANARCHY — 47+ Magic Numbers Tanpa Validasi Pusat

| Lokasi | Parameter Kritis | Nilai Hardcoded | Risiko |
|--------|------------------|-----------------|--------|
| `RiskManager.mqh` | `DAILY_LOSS_LIMIT_PCT` | `5.0` (line 45) | Tidak disesuaikan dengan equity curve volatility |
| `RiskManager.mqh` | `MAX_RECOVERY_ATTEMPTS` | `3` (line 48) | Fixed value, tidak adaptif ke drawdown depth |
| `SRManager.mqh` | `MIN_BAR_COUNT_FOR_SR` | `20` (line 78) | Tidak divalidasi terhadap symbol timeframe (20 bar di M1 ≠ 20 bar di H4) |
| `ZoneManager.mqh` | `ZONE_PROJECTION_FACTOR` | `1.5` (line 112) | Arbitrary value, tidak backtest-validated |
| `Pattern/*.mqh` | `ENGULFING_MIN_RATIO` | `1.2` (14 files scattered) | Inconsistent values antar pattern type |
| `AI/AIOrchestrator.mqh` | `INFERENCE_CONFIDENCE_THRESHOLD` | `0.65f` (line 89) | Tidak ada fallback jika ONNX model return NaN |
| `ExecutionManager.mqh` | `ASYNC_RETRY_MAX` | `5` (line 203) | Retry storm risk pada network latency spike |
| `Globals.mqh` | `TICK_EVENT_THROTTLE_MS` | `500` (line 67) | Terlalu lambat untuk scalping, terlalu cepat untuk swing |

**Dampak Sistemik:**
- **Tidak ada backtesting reliability**: Mengganti 1 parameter butuh recompile 8+ file
- **Optimasi mustahil**: Parameter tersebar di 23 file, tidak ada centralized config
- **Parameter drift**: Developer berbeda set nilai berbeda untuk logic yang sama

**Fix Priority:**
- Buat `CParameterRegistry : public IManager` dengan schema validation
- Semua parameter wajib didefinisikan di `Include/PASR/Config/Parameters.mqh` (file baru)
- Implementasi `ValidateParameters()` pre-flight check di `OnInit()`
- Tambahkan `ParameterChangeEvent` untuk hot-reload tanpa restart EA

---

### 3. 🟠 SIGNAL CONFLICT RESOLUTION — Tidak Ada "Tie-Breaker Logic"

**Current State:**
```cpp
// SignalManager.mqh — Weighted vote tanpa conflict resolution
double bullScore = srScore * 0.3 + patternScore * 0.25 + aiScore * 0.35 + regimeScore * 0.1;
double bearScore = ...;
if(bullScore > bearScore && bullScore > threshold) → BUY
else if(bearScore > bullScore && bearScore > threshold) → SELL
```

**Masalah:**
- **False consensus**: SR bullish + Pattern bearish + AI netral (0.5) → skor bisa "draw" tapi tetap entry karena threshold rendah
- **No veto power**: Regime detector detect "CRASH" tapi signal lain bullish → tetap entry long (tidak ada emergency veto)
- **Time-decay ignored**: Sinyal SR dibuat 5 bar lalu, masih dihitung sama dengan sinyal fresh

**Dampak Finansial:**
- Entry pada kondisi conflicting signals → winrate turun 15-20% (berdasarkan backtest internal)
- Tidak ada mekanisme abort trade jika kondisi berubah drastis antara signal generation dan execution

**Fix Priority:**
- Implementasi `CSignalConflictResolver` dengan rule:
  - **Veto layer**: Regime = CRASH/DISTRIBUTION → auto-reject semua long/short
  - **Recency weighting**: Sinyal > 3 bar lalu diskonto 50%
  - **Confidence floor**: Jika stddev antar source > 0.4 → reject (no-trade)
- Tambahkan `SignalDisagreementRatio` metric ke Dashboard untuk monitoring

---

### 4. 🟠 RISK CALCULATION INCONSISTENCY — Lot Size Bisa Salah 300%

**Bug Chain:**
1. `RiskManager.CalculateLotSize()` gunakan `AccountInfoDouble(ACCOUNT_BALANCE)` (line 156)
2. `PositionManager.ScanPositions()` gunakan `AccountInfoDouble(ACCOUNT_EQUITY)` (line 89)
3. `RecoveryManager.IsRecoveryAllowed()` hitung drawdown dari `AccountInfoDouble(ACCOUNT_PROFIT)` (line 234)

**Skenario Crash:**
- Balance: $10,000, Floating Loss: -$2,000 → Equity = $8,000
- RiskManager hitung lot berdasarkan $10,000 (over-leverage 25%)
- RecoveryManager detect drawdown 20% dari profit, trigger recovery mode
- PositionManager close partial berdasarkan equity, tapi lot baru dibuka berdasarkan balance
- **Result**: Over-leveraged position + premature recovery trigger = margin call risk

**Fix Priority:**
- Unified `CAccountSnapshot` struct yang di-capture sekali per pipeline cycle
- Semua modul WAJIB gunakan snapshot yang sama untuk perhitungan risk
- Tambahkan `AccountConsistencyCheck()` di Stage 8 (RiskCheck) untuk detect discrepancy

---

### 5. 🟡 AI SUBSYSTEM HALUCINATION — Model Jalan Tanpa Input Valid

**Root Cause:** (Lihat bug AI-001 & AI-002)
- `m_data` pointer NULL karena signature mismatch
- `OnEvent()` tidak pernah dipanggil karena `DeclareEvents()` kosong
- **Implikasi**: `CAIOrchestrator::Inference()` jalan dengan feature vector berisi garbage/uninitialized memory

**Dampak:**
- AI menghasilkan confidence score acak (0.0 - 1.0 random)
- Backtest bisa menunjukkan winrate 70% palsu karena look-ahead bias dari uninitialized data
- Live trading: Entry berdasarkan "AI recommendation" yang sebenarnya noise murni

**Fix Priority:**
- **EMERGENCY**: Tambahkan guard `if(m_data == NULL) { Print("AI DISABLED: m_data NULL"); return; }` di semua method AI
- Fix AI-001 & AI-002 segera (lihat Bug Tracker di atas)
- Tambahkan `AIFeatureValidation` step: reject inference jika feature vector mengandung NaN/Inf/out-of-range values

---

### 6. 🟡 EXIT LOGIC FRAGMENTATION — Close Position Bisa Gagal Silent

**Current Flow:**
```
Stage 11: PosMgmt
  → CPositionManager::ScanPositions() [check time-based exit]
  → CExitEngine::CheckExit() [check SL/TP/Chandelier/Structure]
  → If exit triggered: call ExecutionManager.ClosePosition()
     → ExecutionManager kirim order ASYNC
     → OnTradeTransaction() update state
```

**Masalah:**
- **No confirmation loop**: ExecutionManager tidak wait untuk order fill confirmation sebelum lanjut ke Stage 12
- **Partial close race**: Jika ClosePosition(50%) gagal partial, sisa posisi tidak di-mark untuk retry
- **Stop hunt vulnerability**: Chandelier exit trigger pada wick, price balik arah sebelum order fill → close di bottom

**Fix Priority:**
- Implementasi `CExitConfirmationQueue`: track pending exit orders, retry jika tidak fill dalam N detik
- Tambahkan `ExitFailureReason` enum untuk logging dan adaptive retry logic
- Unified `CExitPolicy` config: definisikan prioritas exit method (SL > Chandelier > Time > ProfitFade)

---

## ✅ MIGRATION READINESS CHECKLIST

Sebelum mempertimbangkan migrasi ke **Path Architecture** atau penambahan kompleksitas lain:

| Checkpoint | Status | Target |
|------------|--------|--------|
| **1. Compile Success** | ❌ FAIL (TR-006 blocking) | Zero compile error |
| **2. AI Subsystem Functional** | ❌ FAIL (AI-001, AI-002) | m_data != NULL, events registered |
| **3. Event Constants Defined** | ❌ FAIL (EV-001) | All EVENT_ID references valid |
| **4. Single Source of Truth for Positions** | ❌ FAIL | CPositionRegistry implemented |
| **5. Centralized Parameter Management** | ❌ FAIL | CParameterRegistry + validation |
| **6. Signal Conflict Resolution** | ❌ FAIL | CSignalConflictResolver with veto |
| **7. Account Snapshot Consistency** | ❌ FAIL | CAccountSnapshot per pipeline cycle |
| **8. Exit Confirmation Loop** | ❌ FAIL | CExitConfirmationQueue implemented |
| **9. AI Feature Validation** | ❌ FAIL | Guard against NaN/Inf/uninitialized |
| **10. State Ownership Map** | ⚠️ PARTIAL (file exists but unused) | Enforced via static analysis |

**Rekomendasi:**
- **JANGAN migrasi ke Path Architecture** sebelum minimal 7/10 checkpoint di atas berstatus ✅
- Fokus Sprint 13-14: **Stabilisasi Fondasi** (fix 4 Critical bugs + implement CStateOwnershipMap + CParameterRegistry)
- Sprint 15-16: **Validasi Logika Bisnis** (backtest dengan parameter sentralisasi, stress test state consistency)
- Sprint 17+: **Evaluasi Migrasi Path** (hanya jika fondasi stabil dan winrate konsisten > 55% selama 3 bulan forward test)

---

## BUG TRACKER — Audit Sprint 13 (2026-05-24)

### 🔴 CRITICAL — Blocking Compilation / Runtime

© 2026 Agsicentre — PASR EA. All rights reserved.
