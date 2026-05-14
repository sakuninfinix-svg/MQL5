# FIX REPAINTING - CLOSED BAR DATA ONLY

## Masalah yang Diperbaiki

Sebelumnya, beberapa fungsi menggunakan `rates[0]` (bar yang sedang terbentuk) untuk:
- Generasi sinyal trading
- Deteksi pola price action
- Tracking zone reuse
- Fakeout detection
- Update indikator

**Dampak**: Sinyal dapat berubah (repaint) seiring pembentukan bar, menyebabkan:
- Backtest tidak akurat (menggunakan data final bar yang belum tersedia saat live)
- Sinyal palsu saat harga bergerak dalam bar
- Zone support/resistance berubah mid-bar
- Fakeout terdeteksi pada wick yang mungkin retract

## Solusi

**Prinsip Utama**: Hanya gunakan bar yang sudah TERTUTUP (closed/confirmed) untuk semua operasi analisis.

### Perubahan File

#### 1. `Experts/PASR_MODULAR.mq5` ✅ (Sudah Fixed)
```mql5
// OnTick() - NewBarEvent dispatch
if(CopyRates(eaCfg.symbolName, eaCfg.timeframe, 0, 2, rates) > 1)
{
   // Use rates[1] - the CLOSED bar (rates[0] is still forming)
   DispatchEvent(new NewBarEvent(
       lastClosedBar,
       rates[1].open, rates[1].high, rates[1].low, rates[1].close,
       eaCfg.timeframe));
}
```

#### 2. `Include/PASR/1.Events.mqh` ✅ (Sudah Fixed)
```mql5
// ReplayRecordedEvents()
if(CopyRates(_Symbol, _Period, 0, 2, rates) > 1)
{
   // Use rates[1] - the last CLOSED bar
   e = new NewBarEvent(rates[1].time, rates[1].open, rates[1].high,
                       rates[1].low, rates[1].close, _Period);
}
```

#### 3. `Include/PASR/5.SignalManager.mqh` ✅ (Fixed in this commit)
```mql5
// IsZoneReuseBlocked() - Check zone reuse on confirmed bar
if (CopyRates(m_symbol, m_period, 1, 1, rates) <= 0)  // Was: 0, 1
   return false;

// RegisterZoneUse() - Register zone on confirmed bar
if (CopyRates(m_symbol, m_period, 1, 1, rates) <= 0)  // Was: 0, 1
   return;

// DetectSignalCore() - Already uses shift 1
if (!FetchCandleBatch(1, cfg.pattern_lookback + 5, rates))  // Start from shift 1
```

#### 4. `Include/PASR/8.RecoveryManager.mqh` ✅ (Fixed in this commit)
```mql5
// DetectAndHandleFakeout() - Use closed bars for fakeout detection
if (CopyRates(_Symbol, _Period, 1, 3, ctx.rates) < 3)  // Was: 0, 3
{
   // ctx.rates[0] now refers to last CLOSED bar
}
```

#### 5. `Include/PASR/3.MarketManager.mqh` ✅ (Fixed in this commit)
```mql5
// IsEntryCooldownActive() - Check cooldown on confirmed bar
if (CopyRates(m_symbol, m_period, 1, 1, rates) <= 0)  // Was: 0, 1

// UpdateLossStreak() - Record loss bar time on confirmed bar
if (CopyRates(m_symbol, m_period, 1, 1, rates) > 0)  // Was: 0, 1
```

#### 6. `Include/PASR/10.DataManager.mqh` ✅ (Fixed in this commit)
```mql5
// UpdateIndicators() - Update indicator cache on confirmed bar
if (CopyRates(m_symbol, m_period, 1, 1, rates) <= 0)  // Was: 0, 1
```

#### 7. `Include/PASR/4.SRManager.mqh` ✅ (Already Correct)
```mql5
// IsBroken() - Already uses shift 1
if (CopyRates(m_symbol, m_period, 1, bars, rates) < bars)
```

## Validasi Data yang Sudah Ada

File `Include/PASR/5.SignalManager.mqh` sudah memiliki validasi data:

```mql5
bool ValidateCandleData(const MqlRates &rates[], int shift)
{
   // Outlier detection: Range > 5x previous candle
   if(prevRange > 0 && currentRange > (prevRange * 5.0))
      return false;
   
   // Stale data: Zero range or invalid OHLC
   if(currentRange <= 0 || high < low || open <= 0 || close <= 0)
      return false;
   
   // Gap detection: Large gap from previous close (logged but not rejected)
   if(gap > (prevRange * 2.0))
      Log("Large gap detected");
   
   return true;
}
```

## Manfaat Perbaikan

1. **Tidak Ada Repainting**: Sinyal yang dihasilkan tidak akan berubah mid-bar
2. **Backtest Akurat**: Hasil backtest mencerminkan kondisi live trading
3. **Konsistensi**: Data yang digunakan sama antara live dan historical testing
4. **Deteksi Fakeout Lebih Baik**: Tidak terkecoh oleh wick yang retract
5. **Zone Tracking Stabil**: Level support/resistance tidak berubah mid-bar

## Testing Checklist

- [ ] Backtest dengan tick data quality "Every tick"
- [ ] Forward test di demo account
- [ ] Verifikasi log sinyal tidak berubah mid-bar
- [ ] Cek konsistensi antara backtest dan live results
- [ ] Monitor deteksi fakeout pada news events

## Catatan Penting

**Perbedaan Shift Indexing:**
- `CopyRates(Symbol, Period, 0, count, rates)` → rates[0] = bar saat ini (forming)
- `CopyRates(Symbol, Period, 1, count, rates)` → rates[0] = bar terakhir yang tertutup

Setelah perubahan ini, semua `rates[0]` dalam konteks handler merujuk pada **bar tertutup terakhir**, bukan bar yang sedang terbentuk.

## Git Ignore

✅ File `.gitignore` tidak diubah sesuai permintaan.
