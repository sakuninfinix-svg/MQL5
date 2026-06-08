# PASR Strategy Tester Validation

Tujuan validasi ini adalah membuktikan operational gates yang tidak bisa dibuktikan oleh compile:

- EA bisa start di Strategy Tester dengan config business-logic terbaru.
- Report tester/log tidak menunjukkan error jelas.
- Journal CSV memiliki schema business context (`ai_model_id`, `ai_validation_valid`, `ai_validation_reason`).
- Jika ada trade, journal row bisa dipakai untuk rekonsiliasi broker deal history.

## Generate Paket

```powershell
python tools\strategy_tester_validation.py
```

Output default:

```text
Files/PASR_Validation/run_YYYYMMDD_HHMMSS/
  tester_pasr_validation.ini
  validation_summary.json
```

## Jalankan Via CLI MT5

```powershell
python tools\strategy_tester_validation.py --run --symbol EURUSD --period H1 --from-date 2024.01.01 --to-date 2024.03.31
```

## Status Run 2026-06-02

Validasi CLI sudah dicoba, tetapi Strategy Tester tidak membuat report karena terminal tidak tersinkron dengan broker:

- `authorization on Exness-MT5Trial7 failed (Invalid account)`
- `tester not started because terminal is not synchronized with the trade server`
- `shutdown with -1000012362`

Ini adalah blocker environment, bukan bukti error compile atau business logic EA. Setelah terminal berhasil login dan symbol tersinkron, ulangi:

```powershell
python tools\strategy_tester_validation.py --run --symbol EURUSD --period H1 --from-date 2024.01.01 --to-date 2024.03.31
```

Jika MT5 tidak membuat report via CLI, buka Strategy Tester manual dan pakai:

- Expert: `PASR_MODULAR.ex5`
- Preset: `Presets/PASR_BusinessLogicValidation.set`
- Symbol/period/date sesuai file `tester_pasr_validation.ini`
- Model: Every tick atau Every tick based on real ticks

Setelah selesai, jalankan parser lagi tanpa `--run` dengan `--out` ke folder run yang sama.

## Pass/Fail

Validasi lokal dianggap cukup untuk lanjut migrasi jika:

- `tester_report_created` PASS, atau report manual tersedia dan bisa dianalisis.
- `tester_log_no_obvious_errors` PASS.
- `journal_schema_business_context` PASS.
- Jika ada trade: `journal_has_trade_rows` PASS.

Jika tidak ada trade pada window pendek, itu bukan selalu failure business logic; ulangi dengan periode lebih panjang atau symbol berbeda.
