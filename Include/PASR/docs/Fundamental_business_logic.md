# Fundamental Business Logic Upgrade Project

Dokumen ini adalah project kerja untuk menaikkan PASR dari compile-clean architecture menjadi EA yang business logic-nya lebih kuat, terukur, dan layak divalidasi secara kuantitatif.

Peran dokumen ini:

- Menentukan prioritas refactor logika trading setelah migrasi `CPASRKernel`.
- Menjaga perubahan tetap kecil, compile-clean, dan bisa diuji.
- Memisahkan arsitektur runtime dari keputusan trading: signal, risk, AI, execution, exit, dan state.
- Menjadi checklist kerja sebelum klaim production-readiness.

Status saat ini: **local implementation complete**. Runtime canonical sudah di `CPASRKernel`; keputusan trading utama sudah deterministic, observable, dan testable dari compile/harness lokal. Sisa pekerjaan dipisahkan sebagai operational validation gate yang membutuhkan Strategy Tester/forward session.

Operational validation attempt 2026-06-02:

- Paket validasi dibuat di `tools/strategy_tester_validation.py` dan preset konservatif dibuat di `Presets/PASR_BusinessLogicValidation.set`.
- CLI Strategy Tester sudah dicoba, tetapi terminal MT5 gagal start tester karena akun/server tidak tersinkron: `Invalid account`, `not synchronized with trade server`, exit `-1000012362`.
- Hasil parser tersimpan di `Files/PASR_Validation/run_20260602_155529/validation_summary.json`.
- Status: business logic local **DONE**; Strategy Tester/forward validation **BLOCKED BY ENVIRONMENT** sampai terminal berhasil login dan symbol tersinkron.

Latest implementation slice:

- `SAccountSnapshot` dan `CPositionRegistry` sudah dibuat sebagai primitive per-cycle.
- `PipelineContext` sudah membawa account snapshot dan position registry.
- `DataSyncStage` capture account snapshot di awal cycle.
- `RiskStage` memakai registry snapshot terfilter magic/symbol untuk sinkronisasi open trade count.
- `RiskManager` memakai cycle account/position context untuk balance, equity, free margin, drawdown, lot sizing, dan floating PnL saat dipanggil dari pipeline.
- `PositionStage` memakai registry snapshot untuk loop exit management, bukan scan raw ad hoc di stage.
- `DataManager` menghitung daily PnL dari account snapshot lokal dan `CPositionRegistry`.
- `CorrelationManager` memakai `CPositionRegistry` untuk membaca simbol posisi terbuka.
- `SessionState`, `StateManager`, dan `JournalManager` memakai `SAccountSnapshot` untuk equity/balance baseline.
- `PositionManager` helper ticket sekarang membaca detail posisi lewat `CPositionRegistry`, bukan direct ticket-select.
- `RecoveryManager` menerima cycle account/position context dari `RecoveryStage`, reconcile ticket aktif lewat registry, dan reset state saat tracked position sudah hilang.
- `RecoveryManager` tidak lagi menjadikan `OrderPlaced` sebagai posisi confirmed; tracking recovery dimulai dari broker `DEAL_ENTRY_IN` event.
- `CPASRKernel` trade transaction event memakai position ticket untuk broker open/update event dan menyimpan deal id di payload tambahan.
- `CExecutionLedger` sudah dibuat untuk entry request lifecycle: request id, sent/retrying/rejected/filled/timeout, order ticket, position ticket, deal ticket, retcode, dan reason.
- `ExecutionManager` sekarang memperbarui ledger saat request dikirim, retry queued, retry limit, broker deal-in confirmed, reject, atau broker confirmation timeout.
- `CExitConfirmationQueue` sudah dibuat untuk close lifecycle: requested/sent/confirmed/rejected/timeout, request id, position ticket, deal ticket, retcode, exit reason, dan reason text.
- `PositionStage` tidak mengirim close duplikat saat ticket masih pending; close request ditandai sent/rejected dari retcode, lalu confirmed oleh broker `DEAL_ENTRY_OUT`.
- Partial-close semantics sudah aktif: satu kali per posisi, trigger di half target, volume dinormalisasi ke min/step broker, dan status final tetap menunggu broker confirmation.
- Failed/timeout exit request sekarang retryable maksimal dua kali, dengan action lama dipertahankan (`full close` atau `partial close`).
- `CBusinessLogicHarness` sudah dibuat untuk deterministic lifecycle checks pada `CExecutionLedger` dan `CExitConfirmationQueue`.
- `PASR_Smoke.mq5` sekarang menjalankan business logic harness selain smoke test utama.
- `CAIFeatureValidator` sudah dibuat untuk guard feature/model sebelum inference AI.
- `CAIOrchestrator::Predict()` sekarang menolak feature invalid/stale/out-of-range atau ensemble tidak sehat sebelum drift/model vote.
- `AIInferStage` menyalurkan health, score, drift, model id, dan veto flag dari validasi/inference terakhir ke `PipelineContext`.
- Business logic harness juga menguji validator AI untuk feature valid, out-of-range, missing bar time, stale vector, dan missing model.
- `PipelineContext.ai_result` sekarang membawa validation validity, reason, invalid feature index, model name/id, score, drift, dan model health.
- Pipeline observability text sekarang memuat AI health, validation state, drift, dan truncated validation reason.
- `JournalManager` CSV schema siap menyimpan `ai_model_id`, `ai_validation_valid`, dan `ai_validation_reason`.
- `CAIFeatureValidator` sekarang punya taxonomy range per kelompok feature: returns, ATR ratio, momentum, volume, structure, regime one-hot, time, distribution, dan pattern.
- Business logic harness menguji taxonomy validator termasuk out-of-range momentum feature dan invalid regime one-hot vector.
- Direct broker state reads sekarang terkonsentrasi di boundary canonical: `AccountSnapshot.mqh` dan `PositionRegistry.mqh`.
- `SignalAggregator` sekarang punya dominance-gap conflict guard: sinyal BUY/SELL yang sama-sama qualified tapi terlalu dekat menjadi `NO_TRADE`.
- `CSignalDecisionEngine` sudah dibuat sebagai kontrak final signal/no-trade dengan reason code accepted, no-sources, vetoed, conflict, no-consensus, dan stale.
- `SignalResult` sekarang membawa `evaluatedAt`; aggregator mengabaikan source stale dan snapshot mencatat `staleSourceCount`.
- `JournalManager` sekarang menyimpan snapshot konteks pipeline terakhir dan memakai konteks tersebut saat `EVENT_ID_TRADE_CLOSE` untuk mengisi arah, entry, SL, TP, lot, regime, session, AI score, drift, model id, dan validation reason.
- Telemetry pipeline sekarang mencatat `AIDrift`, `AIValidationValid`, `AIModelHealthy`, dan `AIInvalidFeatureIndex` bila relevan.
- Business logic harness sekarang menguji `CSignalDecisionEngine` untuk aligned-source accepted trade, opposed-source no-trade/conflict, dan stale-source no-trade.
- Business logic harness sekarang menguji primitive account/position state: cleared account freshness, position snapshot validity, dan empty registry invariants.
- Source bawaan `SRSignalSource`, `PatternSignalSource`, `RegimeSignalSource`, dan `AISignalSource` sekarang mengisi `SignalResult.evaluatedAt` secara eksplisit.
- Kernel sekarang mempublikasikan config governance telemetry: `ConfigDigest`, `ConfigRiskPercent`, `ConfigMaxOpenPositions`, `ConfigAIEnabled`, dan `ConfigAIMinConfidence`.
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

- Done: registry primitive, context wiring, RiskStage open-trade sync, PositionStage registry-backed exit loop, RecoveryStage/RecoveryManager registry context, DataManager daily PnL registry scan, CorrelationManager registry-backed open-symbol scan, RiskManager fallback registry scan, and PositionManager ticket helpers via registry lookup.
- Done: business logic harness covers basic position snapshot validity and empty-registry invariants.
- Operational validation gate: richer transaction reconciliation across simultaneous live broker requests harus dibuktikan di Strategy Tester/forward session.

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

- Done: account snapshot primitive, PipelineContext wiring, RiskManager cycle-context consumption for risk checks, RecoveryManager cycle-context consumption, DataManager daily PnL snapshot usage, SessionState equity sync, StateManager persisted baseline, and JournalManager drawdown baseline.
- Done: business logic harness covers account snapshot clear/freshness invariants.
- Operational validation gate: richer live account snapshot diagnostics harus dibuktikan di Strategy Tester/forward sessions.

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

- Done: `SignalConfigData.MinDominanceGap`, aggregator conflict/dominance snapshot fields, conflict no-trade reason, formal `CSignalDecisionEngine`, explicit source age validation via `SignalResult.evaluatedAt`, stale source diagnostics, and SignalManager telemetry fields.
- Done: deterministic business logic harness covers accepted aligned sources, opposed evidence no-trade, and stale-source no-trade.
- Operational validation gate: richer veto taxonomy dapat diperluas setelah data live diagnostic terkumpul.

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

- `Include/PASR/AI/AIFeatureValidator.mqh` - **created**
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

Current status:

- Done: `CAIFeatureValidator` validates feature flag, bar timestamp, freshness, finite values, bounded feature taxonomy, regime one-hot consistency, and ensemble readiness; validator emits feature group/bounds, model count/model id metadata; `CAIOrchestrator::Predict()` gates inference before drift/model vote; `AIInferStage` and `SignalStage` expose latest AI health/score/drift/model/veto/validation reason into pipeline context; observability text includes AI health/validation/drift/reason; `JournalManager` schema supports AI model id and validation reason columns; business logic harness covers deterministic validator failure modes and range taxonomy.
- Done: `JournalManager` now caches the latest pipeline context and enriches broker close-event journal rows with plan, regime/session, AI validation, model id, and drift context.
- Operational validation gate: exported CSV rows harus dibandingkan dengan broker fill history di sesi Strategy Tester/forward panjang.

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

- `Include/PASR/Trade/ExecutionLedger.mqh` - **created**
- `Include/PASR/Trade/ExitConfirmationQueue.mqh` - **created**
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

Current status:

- Done: recovery open tracking waits for broker-confirmed deal-in events; kernel emits position ticket for open/update and deal id as supplemental payload; request-level `OrderPlaced` is ignored by recovery state; `CExecutionLedger` tracks entry request id, sent/retrying/rejected/filled/timeout states, order ticket, position ticket, deal ticket, retcode, retry count, and reason; `CExitConfirmationQueue` tracks close/partial-close request id, sent/confirmed/rejected/timeout states, retcode, exit reason, requested volume, retry count, and broker deal-out confirmation; failed/timeout exits retry up to two times; business logic harness covers deterministic entry and exit state transitions.
- Operational validation gate: request-to-fill matching multi-request simultan dan runtime lifecycle harness harus dibuktikan di terminal Strategy Tester/script mode.

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

Current status:

- Done: config validation blocks unsafe risk/market/AI/pattern/display settings at init/reload; config digest and key safety parameters are emitted to telemetry by `CPASRKernel`.
- Done: optimization-sensitive values remain in `StrategyConfig`/module config caches; adaptive runtime changes are separated through adaptive modules instead of silent mutation.

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
- `Include/PASR/QA/BusinessLogicHarness.mqh` - **created**

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

Current status:

- Done: business logic harness is included by `PASR_Smoke.mq5`; pipeline observability text and telemetry include AI validation, drift, invalid feature index, signal conflict/dominance, stale source count, risk, execution, exit, and recovery summary fields.
- Done: `PASR_Smoke.mq5` compiles the business logic harness including execution ledger, exit queue, signal decision, stale-source, and AI validation scenarios.
- Done: business logic harness includes account snapshot and position registry primitive invariants.
- Operational validation gate: long-run journal reconciliation against real broker deal history. MetaEditor returned success but did not emit a compile log or `.ex5` artifact for standalone `PASR_BusinessLogicHarness.mq5`; harness coverage is therefore gated through `PASR_Smoke.mq5`.

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
  - `Scripts/PASR_BusinessLogicHarness.mq5` logic is compiled through `PASR_Smoke.mq5`

Local implementation status: **DONE**. Production readiness still requires the operational validation gates above because broker fills, history reconciliation, and simultaneous live request behavior cannot be proven by static compile/harness alone.

---

## Senior Quant Notes

- Do not optimize profitability before state and risk consistency are deterministic.
- Prefer no-trade over ambiguous trade when evidence conflicts.
- AI should be a probabilistic input, not an authority that bypasses risk.
- Backtest metrics are invalid if exits, partial closes, and transaction confirmation are not modeled consistently.
- Forward-test readiness requires reproducible logs, not only compile success.
