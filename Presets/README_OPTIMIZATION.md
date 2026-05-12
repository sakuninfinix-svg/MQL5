# 📊 PANDUAN OPTIMASI PASR_MODULAR v1.30

## 🎯 Langkah-Langkah Backtest & Optimasi

### 1️⃣ **Fase 1: Fast Optimization** (Cari Parameter Terbaik)

**File Preset:** `PASR_FastOptimization.set`

**Pengaturan Strategy Tester MT5:**
- **Symbol:** EURUSD, GBPUSD, XAUUSD (uji satu per satu)
- **Timeframe:** M15 atau H1
- **Mode:** "Open prices only" (untuk kecepatan)
- **Date Range:** 1-2 tahun terakhir
- **Optimization:** Genetic Algorithm (cepat) atau Full (lengkap)

**Parameter yang Dioptimasi (Centang di MT5):**
```
InpSR_Sensitivity      : 10 to 30 by 1
InpTP_Multiplier       : 1.5 to 3.0 by 0.1
InpSL_Multiplier       : 0.5 to 1.5 by 0.1
InpRiskPercent         : 0.5 to 2.0 by 0.1
InpSR_LookbackBars     : 30 to 100 by 10
```

**Target:** Temukan kombinasi dengan:
- Profit Factor > 1.5
- Max Drawdown < 20%
- Total Trades > 100 (statistik signifikan)

---

### 2️⃣ **Fase 2: Realistic Validation** (Uji Kondisi Nyata)

**File Preset:** `PASR_RealisticValidation.set`

**Pengaturan Strategy Tester MT5:**
- **Symbol:** Sama dengan fase 1
- **Timeframe:** Sama dengan fase 1
- **Mode:** **"Every tick based on real ticks"** (WAJIB!)
- **Date Range:** Periode berbeda dari fase 1 (out-of-sample)
- **Optimization:** None (gunakan parameter terbaik dari fase 1)

**Parameter yang Disesuaikan:**
Ganti nilai berikut dengan hasil terbaik dari Fase 1:
```
InpSR_Sensitivity      = [Hasil Terbaik Fase 1]
InpTP_Multiplier       = [Hasil Terbaik Fase 1]
InpSL_Multiplier       = [Hasil Terbaik Fase 1]
```

**Kriteria Lulus:**
- Profit Factor > 1.3 (sedikit turun wajar)
- Drawdown konsisten dengan fase 1
- Tidak ada loss berturut-turut > 5 kali

---

### 3️⃣ **Fase 3: Forward Test** (Demo Account)

**Langkah:**
1. Export parameter terbaik dari Fase 2
2. Load di MT5 Live/Demo account
3. Jalankan minimal 2-4 minggu
4. Monitor performa real-time vs backtest

**Checklist Monitoring:**
- [ ] Spread real-time sesuai asumsi backtest
- [ ] Eksekusi order tanpa requote berlebihan
- [ ] Drawdown tidak melebihi 120% dari backtest
- [ ] Profit konsisten dengan ekspektasi

---

## 🔧 PARAMETER KRITIS YANG HARUS DISESUAIKAN

### A. **Berdasarkan Pair Trading**

| Pair | SR_Sensitivity | SR_DistancePoints | MaxSpreadPoints |
|------|----------------|-------------------|-----------------|
| EURUSD | 15-20 | 300-500 | 15-20 |
| GBPUSD | 18-25 | 400-600 | 20-25 |
| XAUUSD (Gold) | 25-35 | 800-1500 | 30-50 |
| USDJPY | 12-18 | 250-400 | 10-15 |
| BTCUSD | 30-45 | 2000-5000 | 50-100 |

### B. **Berdasarkan Timeframe**

| Timeframe | SR_LookbackBars | TP_Multiplier | SL_Multiplier |
|-----------|-----------------|---------------|---------------|
| M15 | 30-50 | 1.5-2.0 | 0.8-1.0 |
| H1 | 50-100 | 2.0-2.5 | 1.0-1.2 |
| H4 | 100-200 | 2.5-3.5 | 1.2-1.5 |
| D1 | 200-500 | 3.0-5.0 | 1.5-2.0 |

### C. **Berdasarkan Kondisi Market**

| Kondisi | RiskPercent | MaxOpenOrders | UseTrendFilter |
|---------|-------------|---------------|----------------|
| Normal | 1.0-2.0% | 2-3 | true |
| Volatile | 0.5-1.0% | 1-2 | true |
| Sideways | 0.5-1.0% | 1 | false |
| News High-Impact | 0% (Stop) | 0 | N/A |

---

## ⚠️ TIPS PENTING

1. **Jangan Overfitting!**
   - Jika parameter hanya bagus di 1 pair/timeframe, abaikan
   - Pilih parameter yang konsisten di berbagai kondisi

2. **Slippage & Spread Realistis**
   - Gunakan `SlippagePoints=3-5` untuk validasi
   - Jangan gunakan 0 slippage (tidak realistis)

3. **Out-of-Sample Testing**
   - Selalu uji di periode waktu yang BERBEDA dari optimasi
   - Contoh: Optimize 2020-2022, Validate 2023-2024

4. **Monitor Drawdown**
   - Max DD > 25% = Parameter terlalu agresif
   - Max DD < 5% = Mungkin terlalu konservatif (peluang terlewat)

5. **Profit Factor Sweet Spot**
   - PF 1.3 - 2.0 = Ideal (sustainable)
   - PF > 3.0 = Curigai overfitting
   - PF < 1.2 = Perlu perbaikan strategi

---

## 📁 STRUKTUR FILE

```
/workspace/
├── Experts/
│   └── PASR_MODULAR.mq5          # EA Utama v1.30
├── Include/PASR/
│   ├── 1.Config.mqh              # Konfigurasi & Caching
│   ├── 2.EventBus.mqh            # Event System
│   ├── 3.MarketManager.mqh       # Market Data
│   ├── 4.SRManager.mqh           # Support Resistance
│   ├── 5.RiskManager.mqh         # Risk Calculation
│   ├── 6.ExecutionManager.mqh    # Order Execution
│   ├── 7.PositionManager.mqh     # Position Tracking
│   ├── 8.RecoveryManager.mqh     # Error Recovery
│   ├── 9.TrailingManager.mqh     # Trailing Stop
│   ├── 10.NewsManager.mqh        # News Filter (optional)
│   └── 11.DashboardManager.mqh   # UI Dashboard
├── Presets/
│   ├── PASR_FastOptimization.set    # Untuk Optimasi Cepat
│   ├── PASR_RealisticValidation.set # Untuk Validasi Akhir
│   └── README_OPTIMIZATION.md       # Panduan ini
└── OPTIMIZATION_SUMMARY_V120.md  # Dokumentasi Teknis
```

---

## 🚀 QUICK START

```bash
# 1. Copy file .set ke folder presets MT5
cp /workspace/Presets/*.set "C:\Users\<User>\AppData\Roaming\MetaQuotes\Terminal\<ID>\MQL5\Presets\PASR_MODULAR\"

# 2. Buka MT5 -> Strategy Tester

# 3. Load PASR_FastOptimization.set

# 4. Klik "Optimization" -> Start

# 5. Setelah selesai, export hasil terbaik

# 6. Load PASR_RealisticValidation.set, update parameter dengan hasil terbaik

# 7. Jalankan backtest dengan mode "Every tick based on real ticks"

# 8. Jika lolos, deploy ke Demo Account!
```

---

## 📞 SUPPORT

Jika ada pertanyaan atau masalah:
1. Cek log file di tab "Experts" MT5
2. Pastikan `InpLogLevel=1` untuk info detail
3. Verifikasi semua file include terinstall dengan benar
4. Pastikan broker mendukung hedging jika menggunakan fitur multi-position

**Happy Trading & Good Luck!** 📈💰
