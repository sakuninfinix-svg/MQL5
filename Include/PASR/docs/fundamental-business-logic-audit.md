# Fundamental Business Logic & State Chaos Audit

> Sumber: bagian audit lama dari README `Bug Tracking List`.
> Status: dipindahkan dari README menjadi dokumen audit + GitHub Issues.
> Tujuan: menjaga konteks risiko desain tetap tersedia tanpa membuat README menjadi bug tracker panjang.

---

## Ringkasan

Setelah runtime dipusatkan ke `CPASRKernel`, fokus berikutnya adalah menstabilkan fondasi logika bisnis dan state management.

Masalah di dokumen ini bukan sekadar bug teknis. Sebagian menyentuh risiko eksekusi trading langsung: double processing, lot calculation mismatch, AI inference tanpa input valid, dan exit yang gagal tanpa konfirmasi.

---

## GitHub Issues Terkait

| ID | Issue | Fokus |
|----|-------|-------|
| FBL-001 | #187 | Single source of truth untuk posisi dan runtime state |
| FBL-002 | #188 | Centralized parameter registry dan validation |
| FBL-003 | #189 | Signal conflict resolver dan veto logic |
| FBL-004 | #190 | Single account snapshot untuk risk calculation |
| FBL-005 | #191 | AI feature validation dan fail-safe inference |
| FBL-006 | #192 | Exit confirmation queue dan unified exit policy |

---

## 1. State Management Chaos

### Gejala

Beberapa module dapat memiliki atau memindai state posisi sendiri:

- `PositionManager.ScanPositions()`
- `RecoveryManager.m_positions[]`
- `SessionState.m_open_positions[]`
- `ExitEngine` scan mandiri
- `OnTradeTransaction()` update beberapa manager sekaligus

### Dampak

- Posisi yang sama bisa diproses lebih dari sekali.
- Partial close bisa dobel.
- Trailing stop bisa konflik.
- Recovery attempt count bisa tidak sinkron.
- Daily/session counters bisa korup jika event diproses dalam urutan yang tidak diharapkan.

### Root Cause

Belum ada single source of truth untuk posisi dan belum ada state ownership map yang ditegakkan.

### Target Fix

- Implement atau enforce `CStateOwnershipMap`.
- Implement `CPositionRegistry` sebagai sumber kebenaran posisi terbuka.
- Tentukan module mana yang boleh write state tertentu.
- Tambahkan runtime diagnostics untuk unauthorized state write.

### Tracking

Lihat Issue #187.

---

## 2. Parameter Anarchy

### Gejala

Parameter kritis tersebar di banyak file sebagai hardcoded constants atau local defaults.

Contoh kategori:

- Risk limits.
- Recovery attempts.
- SR minimum bars.
- Zone projection factor.
- Pattern ratios.
- AI confidence threshold.
- Execution retry limit.
- Tick event throttling.

### Dampak

- Sulit optimasi dan backtest karena parameter tersebar.
- Mengubah satu konsep dapat butuh edit di banyak file.
- Risiko parameter drift antar module.
- Validasi parameter tidak terpusat.

### Target Fix

- Buat parameter/config registry canonical.
- Semua parameter penting punya default, range, dan validation rule.
- Jalankan pre-flight validation di `OnInit()`.
- Hot reload hanya dipertimbangkan setelah static validation stabil.

### Tracking

Lihat Issue #188.

---

## 3. Signal Conflict Resolution

### Gejala

Sumber sinyal dapat saling bertentangan tanpa tie-breaker jelas.

Contoh:

- SR bullish, Pattern bearish, AI neutral.
- Regime berbahaya tetapi sinyal lain tetap bullish.
- Sinyal lama dihitung seperti sinyal baru.

### Dampak

- Entry pada kondisi conflicting evidence.
- Kualitas sinyal sulit dijelaskan.
- Tidak ada veto emergency untuk market regime yang berbahaya.
- Backtest dan live analysis sulit diaudit.

### Target Fix

- Implement `CSignalConflictResolver`.
- Tambahkan veto layer untuk regime/market state berbahaya.
- Tambahkan recency weighting.
- Tambahkan disagreement metric.
- Hasil akhir bisa berupa `NO_TRADE` jika konflik tinggi.

### Tracking

Lihat Issue #189.

---

## 4. Risk Calculation Inconsistency

### Gejala

Risk, recovery, dan position logic bisa memakai sumber account yang berbeda pada waktu berbeda.

Contoh kategori:

- Lot sizing memakai balance.
- Position scan memakai equity.
- Recovery memakai profit/drawdown.

### Dampak

Dalam kondisi floating loss, keputusan lot size, drawdown, recovery, dan partial close bisa tidak konsisten. Ini bisa meningkatkan risiko over-leverage atau recovery yang terlalu cepat.

### Target Fix

- Implement `CAccountSnapshot`.
- Capture balance, equity, margin, free margin, profit, drawdown, dan timestamp sekali per pipeline cycle.
- Semua module risk-sensitive memakai snapshot yang sama.
- Tambahkan consistency check pada Stage 8 RiskCheck.

### Tracking

Lihat Issue #190.

---

## 5. AI Subsystem Validation

### Gejala

AI inference berisiko berjalan pada input yang tidak valid jika data pointer, event update, feature vector, atau model state bermasalah.

Risiko input:

- Data dependency null/stale.
- Feature vector uninitialized.
- NaN/Inf/out-of-range values.
- Feature dimension mismatch.
- Model version mismatch.

### Dampak

AI bisa menghasilkan confidence score yang terlihat valid tetapi sebenarnya noise. Ini berbahaya untuk backtest dan live trading karena keputusan entry/veto terlihat berbasis AI padahal inputnya invalid.

### Target Fix

- Tambahkan `AIFeatureValidation` sebelum inference.
- Reject inference pada NaN/Inf/out-of-range.
- Tambahkan model/feature version check.
- Tetapkan fallback: disable AI, no-trade, atau pass-through.
- Log semua keputusan AI invalid/fallback.

### Tracking

Lihat Issue #191.

---

## 6. Exit Logic Fragmentation

### Gejala

Exit logic dapat tersebar dan tidak punya confirmation queue.

Risiko:

- Close request gagal tanpa retry.
- Partial close state diupdate sebelum fill confirmation.
- Exit method saling konflik.
- Tidak ada taxonomy `ExitFailureReason`.

### Dampak

Posisi bisa tetap terbuka setelah close gagal, partial close menjadi tidak sinkron, dan hasil backtest/live dapat berbeda karena fill/confirmation tidak diperlakukan secara eksplisit.

### Target Fix

- Implement `CExitConfirmationQueue`.
- Track pending close/partial-close sampai fill, reject, timeout, atau retry exhausted.
- Tambahkan `ExitFailureReason` enum.
- Definisikan `CExitPolicy` dengan prioritas exit deterministic.

Contoh prioritas:

1. Hard SL.
2. Emergency risk exit.
3. Recovery exit.
4. Chandelier/trailing.
5. Time exit.
6. Profit fade.

### Tracking

Lihat Issue #192.

---

## Post-Migration Hardening Checklist

Setelah migrasi arsitektur pusat, minimal fondasi berikut harus stabil sebelum PASR dianggap layak untuk validasi trading serius:

| Checkpoint | Target |
|------------|--------|
| Compile success | Zero compile error |
| AI subsystem valid | Feature valid, data dependency valid, fallback jelas |
| Event constants valid | Semua EVENT_ID references valid |
| Single source of truth posisi | `CPositionRegistry` atau mekanisme setara aktif |
| Centralized parameters | Registry/config validation aktif |
| Signal conflict resolver | Veto dan disagreement handling aktif |
| Account snapshot consistency | `CAccountSnapshot` dipakai per pipeline cycle |
| Exit confirmation loop | Pending exit request tracked sampai final status |
| AI feature validation | Guard terhadap NaN/Inf/uninitialized |
| State ownership map | Ownership state ditegakkan atau minimal didiagnosis |

Rekomendasi: jangan menambah kompleksitas trading baru sebelum sebagian besar checkpoint di atas berstatus stabil.

---

## Dokumentasi Policy

- README: ringkasan dan onboarding.
- `Include/PASR/dokumentasi.md`: dokumentasi detail utama.
- File ini: audit fundamental business logic pasca-migrasi.
- GitHub Issues: pekerjaan aktif yang harus ditutup.

© 2026 Agsicentre — PASR EA. All rights reserved.
