# Fundamental Business Logic Upgrade Project

Dokumen ini adalah project kerja untuk menaikkan PASR dari compile-clean architecture menjadi EA yang business logic-nya lebih kuat, terukur, dan layak divalidasi secara kuantitatif.

Peran dokumen ini:

- Menentukan prioritas refactor logika trading setelah migrasi `CPASRKernel`.
- Menjaga perubahan tetap kecil, compile-clean, dan bisa diuji.
- Memisahkan arsitektur runtime dari keputusan trading: signal, risk, AI, execution, exit, dan state.
- Menjadi checklist kerja sebelum klaim production-readiness.

Status saat ini: **post-migration hardening**. Runtime canonical sudah di `CPASRKernel`; pekerjaan berikutnya adalah membuat keputusan trading deterministic, observable, dan testable.

Latest implementation slice:

- `SAccountSnapshot` dan `CPositionRegistry` sudah dibuat sebagai primitive per-cycle.
- `PipelineContext` sudah membawa account snapshot dan position registry.
- `DataSyncStage` capture account snapshot di awal cycle.
- `RiskStage` memakai registry snapshot terfilter magic/symbol untuk sinkronisasi open trade count.
- `RiskManager` memakai cycle account/position context untuk balance, equity, free margin, drawdown, lot sizing, dan floating PnL saat dipanggil dari pipeline.
- `PositionStage` memakai registry snapshot untuk loop exit management, bukan scan raw ad hoc di stage.
- `DataManager` menghitung daily PnL dari account snapshot lokal dan `CPositionRegistry`.
- `CorrelationManager` memakai `CPositionRegistry` untuk membaca simbol posisi terbuka.
- `SignalAggregator` sekarang punya dominance-gap conflict guard: sinyal BUY/SELL yang sama-sama qualified tapi terlalu dekat menjadi `NO_TRADE`.
- Compile gate terakhir hijau untuk `PASR_MODULAR`, `PASR_Smoke`, dan `PASR_PipelineHarness_Smoke`.

---

## North Star

Versi terbaik PASR harus punya karakter berikut:

1. Satu sumber kebenaran untuk posisi, account snapshot, dan lifecycle trade.
2. Sinyal tidak langsung menjadi order; semua sinyal melewati resolver, veto, risk, dan execution policy.
3. AI hanya boleh memengaruhi keputusan jika input valid, model sehat, confidence cukup, dan fallback jelas.
4. Risk dihitung dari account snapshot yang sama untuk seluruh pipeline cycle.
5. Exit dan partial close harus menunggu konfirmasi transaksi, bukan sekadar asumsi request berhasil.
6. Semua keputusan entry/exit punya reason code yang bisa diaudit di journal/telemetry.
7. Compile gate hijau sebelum dan sesudah setiap fase.

---

## Workstreams

| ID | Workstream | Outcome |
| --- | --- | --- |
| FBL-001 | Position State Authority | `CPositionRegistry` menjadi sumber kebenaran posisi terbuka. |
| FBL-002 | Account Snapshot and Risk Consistency | Satu `CAccountSnapshot` per pipeline cycle untuk risk-sensitive modules. |
| FBL-003 | Signal Decision Engine | Resolver sinyal dengan confluence, conflict, veto, recency, dan reason code. |
| FBL-004 | AI Validation Gate | Feature/model validation sebelum inference dan fallback policy eksplisit. |
| FBL-005 | Execution and Exit Confirmation | Entry/exit request dilacak sampai fill/reject/timeout. |
| FBL-006 | Config and Parameter Governance | Parameter trading punya owner, range, validation, dan default yang jelas. |
| FBL-007 | Observability and QA Gates | Semua keputusan penting bisa diuji dan direkonstruksi. |

---

## Phase 0 - Baseline Lock

Goal: memastikan kondisi awal sebelum logika bisnis disentuh.

Deliverables:

- Simpan compile baseline untuk:
  - `Experts/PASR_MODULAR.mq5`
  - `Scripts/PASR_Smoke.mq5`
  - `Scripts/PASR_PipelineHarness_Smoke.mq5`
- Catat current pipeline order dan manager ownership.
- Catat semua module yang masih langsung memanggil `PositionsTotal()`, `PositionGet*`, `AccountInfo*`, atau close/open trade request.

Acceptance criteria:

- Compile baseline `0 errors, 0 warnings`.
- Daftar state reader/writer tersedia di dokumen atau issue.
- Tidak ada perubahan formula trading di fase ini.

---

## Phase 1 - Position State Authority

Problem:

Beberapa module bisa membaca atau memproses posisi sendiri:

- `PositionManager.ScanPositions()`
- `RiskManager` open-position loop
- `ExitEngine` position checks
- `RecoveryManager` internal position state
- `SessionState` counters
- `OnTradeTransaction()` fan-out ke beberapa manager

Target design:

```text
MT5 PositionsTotal()/PositionGet*
        |
        v
CPositionRegistry
        |
        +-- immutable per-cycle position snapshot
        +-- ticket lookup
        +-- magic/symbol filter
        +-- transaction reconciliation
```

Proposed files:

- `Include/PASR/Trade/PositionRegistry.mqh` - **created**
- update `Trade/PositionManager.mqh`
- update `Orchestration/Stages/PositionStage.mqh`
- update `Trade/RiskManager.mqh`
- update `Trade/RecoveryManager.mqh`
- update `Infra/SessionState.mqh`

Implementation steps:

1. Buat `SPositionSnapshot` dan `CPositionRegistry`.
2. Registry scan posisi sekali per pipeline cycle.
3. `PositionManager` menjadi facade/cache reader, bukan owner state utama.
4. `RiskManager`, `ExitEngine`, `RecoveryManager`, dan `SessionState` membaca snapshot registry.
5. `OnTradeTransaction()` update registry/reconcile event, lalu module lain membaca state yang sama.

Acceptance criteria:

- Dalam satu pipeline cycle tersedia satu registry snapshot posisi utama.
- Semua ticket punya `symbol`, `magic`, `type`, `volume`, `openPrice`, `sl`, `tp`, `profit`, `swap`, `commission`, `openTime`.
- Partial close dan close tidak menaikkan counter sebelum transaksi terkonfirmasi.
- Compile gate hijau.

Current status:

- Done: registry primitive, context wiring, RiskStage open-trade sync, PositionStage registry-backed exit loop, DataManager daily PnL registry scan, and CorrelationManager registry-backed open-symbol scan.
- Pending: transaction reconciliation, PositionManager raw ticket helper fallback cleanup, and confirmed close/partial-close ledger.

Risk controls:

- Jangan hapus scanner lama sebelum registry memberi hasil setara.
- Tambahkan diagnostics untuk mismatch: registry count vs raw MT5 count.

---

## Phase 2 - Account Snapshot and Risk Consistency

Problem:

Risk, recovery, lot sizing, drawdown, and session logic bisa membaca account state pada waktu berbeda. Dalam floating loss cepat, ini bisa menghasilkan keputusan yang tidak konsisten.

Target design:

```text
Pipeline cycle start
        |
        v
CAccountSnapshot::Capture()
        |
        +-- balance
        +-- equity
        +-- margin/free margin
        +-- floating PnL
        +-- daily/session PnL
        +-- drawdown
        +-- spread and symbol trade constraints
```

Proposed files:

- `Include/PASR/Infra/AccountSnapshot.mqh` - **created**
- update `Core/PipelineTypes.mqh`
- update `Orchestration/Stages/DataSyncStage.mqh`
- update `Trade/RiskManager.mqh`
- update `Trade/RecoveryManager.mqh`
- update `Infra/SessionState.mqh`

Implementation steps:

1. Buat `SAccountSnapshot`.
2. Capture snapshot di awal pipeline setelah DataSync.
3. Masukkan snapshot ke `PipelineContext`.
4. Risk sizing memakai snapshot, bukan langsung `AccountInfoDouble()` berkali-kali.
5. Telemetry mencatat snapshot id/time agar keputusan risk bisa direkonstruksi.

Acceptance criteria:

- RiskCheck, recovery, session drawdown, dan execution lot memakai snapshot yang sama.
- Lot size tidak berubah karena pembacaan account kedua di cycle yang sama.
- Snapshot stale detection aktif.
- Compile gate hijau.

Current status:

- Done: account snapshot primitive, PipelineContext wiring, RiskManager cycle-context consumption for risk checks, and DataManager daily PnL snapshot usage.
- Pending: RecoveryManager, SessionState, StateManager, JournalManager, and fallback account diagnostics still need explicit snapshot integration.

---

## Phase 3 - Signal Decision Engine

Problem:

PASR punya beberapa sumber sinyal: SR, Pattern, AI, Regime, dan rule fallback. Saat sumber berbeda arah, sistem butuh resolver formal, bukan sekadar aggregate sederhana.

Target design:

```text
Signal sources
        |
        v
CSignalDecisionEngine
        |
        +-- source validation
        +-- recency weighting
        +-- conflict score
        +-- veto rules
        +-- final direction
        +-- final confidence
        +-- reason code
```

Proposed files:

- `Include/PASR/Signal/SignalDecisionEngine.mqh`
- update `Signal/SignalAggregator.mqh`
- update `Signal/SignalManager.mqh`
- update `Orchestration/Stages/SignalStage.mqh`

Decision policy:

| Condition | Action |
| --- | --- |
| AI invalid and rules weak | `NO_TRADE` |
| Regime dangerous and signal weak | veto |
| SR and Pattern align, AI neutral | allow rule-based signal with lower risk multiplier |
| AI strong but SR/Pattern conflict | require higher confidence or no trade |
| Signal stale | ignore source |
| High disagreement | no trade with conflict reason |

Acceptance criteria:

- Every final signal has `direction`, `confidence`, `primarySource`, `sourceCount`, `conflictScore`, `vetoReason`.
- No trade is a first-class decision, not an error.
- Signal source age is tracked.
- Compile gate hijau.

Current status:

- Done: `SignalConfigData.MinDominanceGap`, aggregator conflict/dominance snapshot fields, conflict no-trade reason, and SignalManager telemetry fields.
- Pending: formal `CSignalDecisionEngine`, explicit source age validation, richer veto taxonomy, and deterministic harness cases for conflicting evidence.

---

## Phase 4 - AI Validation Gate

Problem:

AI inference can look valid even when input feature vector is stale, incomplete, NaN/Inf, out of range, or model state is unhealthy.

Target design:

```text
CAIFeatureBuilder
        |
        v
CAIFeatureValidator
        |
        v
CAIOrchestrator::Predict()
```

Proposed files:

- `Include/PASR/AI/AIFeatureValidator.mqh`
- update `AI/AIFeatureBuilder.mqh`
- update `AI/AIOrchestrator.mqh`
- update `AI/AITypes.mqh`
- update `Orchestration/Stages/AIInferStage.mqh`

Validation rules:

- Feature dimension must equal `AI_FEATURE_DIM`.
- No NaN/Inf.
- Bounded features must stay in expected range.
- Timestamp/freshness must be known.
- Model ensemble must be ready and healthy.
- Drift above threshold triggers fallback.

Fallback policy:

| Failure | Fallback |
| --- | --- |
| Invalid feature vector | AI disabled for cycle; rule fallback allowed only if strong |
| Model unavailable | AI unavailable reason; rule fallback |
| Drift too high | no-trade or reduced-risk fallback |
| Confidence below threshold | no-trade unless rules are strong and risk is low |

Acceptance criteria:

- AI output always includes `valid`, `healthy`, `reason`, `confidence`, `drift`.
- Invalid AI cannot silently approve a trade.
- AI feature validation is visible in telemetry/journal.
- Compile gate hijau.

---

## Phase 5 - Execution and Exit Confirmation

Problem:

Order request success is not the same as position lifecycle success. Exit and partial close must be confirmed through trade transaction events.

Target design:

```text
Trade request
        |
        v
CExecutionLedger
        |
        +-- pending entry
        +-- pending close
        +-- pending partial close
        +-- retry state
        +-- transaction reconciliation
```

Proposed files:

- `Include/PASR/Trade/ExecutionLedger.mqh`
- `Include/PASR/Trade/ExitConfirmationQueue.mqh`
- update `Trade/ExecutionManager.mqh`
- update `Trade/ExitEngine.mqh`
- update `Trade/RecoveryManager.mqh`
- update `Central/PASRKernel.mqh` trade transaction routing

Exit priority:

1. Broker hard SL/TP event.
2. Emergency risk exit.
3. Confirmed recovery exit.
4. Chandelier/trailing exit.
5. Time exit.
6. Profit fade / discretionary policy.

Acceptance criteria:

- Entry/exit request has correlation id.
- Fill/reject/timeout is tracked.
- Partial close state updates only after confirmation.
- Retry policy is bounded and reason-coded.
- Compile gate hijau.

---

## Phase 6 - Config and Parameter Governance

Problem:

Some behavior is configured centrally, but business-critical thresholds can still drift across modules.

Target design:

- `StrategyConfig` remains canonical static config.
- Each module reads from config once through `IDataManager::GetConfigCache()`.
- Validation happens before runtime starts.
- Runtime adaptive changes produce an explicit derived policy, not silent mutation.

Implementation steps:

1. Audit hardcoded risk/signal/AI/exit constants.
2. Move business-critical thresholds into `StrategyConfig`.
3. Extend `Core/Config/Validator.mqh`.
4. Add a config digest/version to telemetry.
5. Document which parameters are optimization-safe and which are safety guards.

Acceptance criteria:

- No hidden hardcoded risk limit remains in trade execution path.
- Invalid config fails init.
- Config changes are observable.
- Compile gate hijau.

---

## Phase 7 - Observability and QA

Goal:

Every important trading decision must be explainable after the fact.

Required telemetry fields:

- cycle id
- account snapshot timestamp
- position registry snapshot id
- signal decision summary
- AI validation result
- risk decision
- execution request id
- exit request id
- final action: no trade, entry, modify, close, partial close

QA scripts to add or extend:

- `Scripts/PASR_Smoke.mq5`
- `Scripts/PASR_PipelineHarness_Smoke.mq5`
- `Scripts/PASR_BusinessLogicHarness.mq5`

Test scenarios:

1. Conflicting SR/Pattern/AI signals produce no-trade.
2. Invalid AI features cannot approve trade.
3. Drawdown snapshot blocks entry consistently.
4. Duplicate trade transaction does not double count PnL.
5. Partial close request is not final until transaction confirms.
6. Position registry matches filtered MT5 positions.

Acceptance criteria:

- Business logic harness compiles.
- Deterministic scenario tests pass in log.
- No phase can close without compile gate.

---

## Implementation Order

Recommended order:

1. Phase 0 - Baseline Lock
2. Phase 1 - Position State Authority
3. Phase 2 - Account Snapshot and Risk Consistency
4. Phase 3 - Signal Decision Engine
5. Phase 4 - AI Validation Gate
6. Phase 5 - Execution and Exit Confirmation
7. Phase 6 - Config and Parameter Governance
8. Phase 7 - Observability and QA

Reasoning:

- Position and account state must be stable before risk/execution decisions are trusted.
- Signal resolution must exist before AI/rule fallback can be safely blended.
- Execution confirmation must come after state ownership so it has a reliable ledger to update.

---

## Definition of Done

PASR business logic upgrade is done when:

- `CPositionRegistry` or equivalent is the single source of position state.
- `SAccountSnapshot` is used for all risk-sensitive decisions in a pipeline cycle.
- `CSignalDecisionEngine` produces final trade/no-trade decisions with reason codes.
- AI inference is guarded by feature/model validation.
- Execution and exit requests are reconciled with trade transactions.
- Config validation blocks unsafe parameter sets at init.
- Telemetry can reconstruct why an order was or was not opened/closed.
- Compile gates are green:
  - `Experts/PASR_MODULAR.mq5`
  - `Scripts/PASR_Smoke.mq5`
  - `Scripts/PASR_PipelineHarness_Smoke.mq5`
  - future `Scripts/PASR_BusinessLogicHarness.mq5`

---

## Senior Quant Notes

- Do not optimize profitability before state and risk consistency are deterministic.
- Prefer no-trade over ambiguous trade when evidence conflicts.
- AI should be a probabilistic input, not an authority that bypasses risk.
- Backtest metrics are invalid if exits, partial closes, and transaction confirmation are not modeled consistently.
- Forward-test readiness requires reproducible logs, not only compile success.
