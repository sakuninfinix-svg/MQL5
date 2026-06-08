# 🚀 PASR EPIC MASTER PRESET - User Guide

## 📋 Ringkasan Optimasi

Dari **8 file preset** yang terfragmentasi dan duplikat, kini telah disatukan menjadi **1 file EPIC MASTER** yang powerful dan lengkap.

### 🗑️ File yang Dihapus (7 file)
- `PASR_BusinessLogicValidation.set` (duplikat dengan "salin 1")
- `PASR_BusinessLogicValidation (salin 1).set` (duplikat manual)
- `PASR_BusinessLogicValidation.set.bak-20260605` (backup lama)
- `PASR_FastOptimization.set` (fungsi digabung ke EPIC)
- `PASR_RealisticValidation.set` (fungsi digabung ke EPIC)
- `PASR_v2_Baseline.set` (fungsi digabung ke EPIC)
- `PASR_v2_MarketOptimization.ini` (range digabung ke komentar EPIC)
- `PASR_v2_PatternOptimization.ini` (range digabung ke komentar EPIC)
- `PASR_v2_RiskOptimization.ini` (range digabung ke komentar EPIC)

### ✅ File Baru (1 file)
- **`PASR_EPIC_MASTER.set`** - Single source of truth untuk semua kebutuhan

---

## 🎯 Fitur EPIC MASTER Preset

### 1. **Auto-Detect Mode**
Sistem otomatis mendeteksi mode operasi:
```mql5
if(MQLInfoInteger(MQL_OPTIMIZATION)) {
   // Optimization Mode: Fast, minimal logging, sampled telemetry
} else {
   // Normal Mode: Full features, detailed logging, complete telemetry
}
```

### 2. **Smart Parameter Ranges**
Setiap parameter memiliki komentar `OptRange` yang menunjukkan rentang optimal untuk optimization:
```
InpRiskPercent=1.0    ; OptRange: 0.5,1.0,1.5,2.0,2.5,3.0
InpSLMultiplier=1.5   ; OptRange: 1.0,1.5,2.0,2.5,3.0
```

### 3. **All-in-One Design**
Menggabungkan fungsi dari semua preset lama:
- ✅ Business Logic Validation
- ✅ Fast Optimization
- ✅ Realistic Validation
- ✅ Baseline Configuration
- ✅ Market/Pattern/Risk Optimization ranges

---

## 📖 Cara Penggunaan

### 🔬 Step 1: Fast Screening (Optimization Awal)
```
1. Load PASR_EPIC_MASTER.set di Strategy Tester
2. Pilih Symbol & Timeframe (rekomendasi: M15/H1)
3. Mode: Optimization → Genetic Algorithm
4. Klik Start
```
**Tujuan:** Mencari region parameter yang promising dalam waktu singkat.

### 🎯 Step 2: Deep Optimization
```
1. Gunakan parameter terbaik dari Step 1
2. Mode: "Every tick based on real ticks"
3. Perkecil step optimization untuk hasil lebih akurat
4. Jalankan optimization penuh (bisa berjam-jam)
```
**Tujuan:** Mendapatkan parameter optimal dengan akurasi tinggi.

### ✅ Step 3: Forward Validation
```
1. Export top 3 parameter sets dari Step 2
2. Test pada data out-of-sample (periode berbeda)
3. Verifikasi konsistensi profit di berbagai kondisi market
```
**Tujuan:** Memastikan strategi tidak overfitting.

### 🚀 Step 4: Live Deployment
```
1. Pilih parameter set terbaik
2. Edit preset:
   - InpDebugMode=false
   - InpShowDashboard=true
   - InpUseTrailingStop=true
   - InpRiskPercent=0.5 (lebih konservatif)
3. Deploy di VPS untuk 24/7 operation
```
**Tujuan:** Trading live dengan proteksi maksimal.

---

## ⚡ Performance Tips

| Scenario | Rekomendasi Parameter |
|----------|----------------------|
| **Optimization** | `InpEnableAI=false`, `InpShowDashboard=false` |
| **Live Trading** | `InpUseTrailingStop=true`, `InpRiskPercent=0.5` |
| **Scalping** | `InpATRPeriod=7-10`, `InpSpreadFilterPips=2` |
| **Swing Trading** | `InpATRPeriod=21-28`, `InpTPMultiplier=3.0+` |
| **High Volatility** | `InpSLMultiplier=2.0+`, `InpMaxDailyLossPct=5.0` |
| **Low Volatility** | `InpMinPatternScore=50+`, `InpADXPeriod=21` |

---

## 📊 Struktur Parameter

### Risk Management
- `InpRiskPercent` - Persentase risiko per trade
- `InpMaxDailyLossPct` - Batas kerugian harian
- `InpMaxDrawdownPct` - Batas drawdown maksimal
- `InpMaxOpenPositions` - Jumlah posisi simultan

### Exit Strategy
- `InpSLMultiplier` - Stop Loss multiplier (x ATR)
- `InpTPMultiplier` - Take Profit multiplier (x ATR)
- `InpUseBreakEven` - Auto move SL to BE
- `InpUseTrailingStop` - Trailing stop dinamis

### Market Filters
- `InpATRPeriod` - ATR calculation period
- `InpADXPeriod` - ADX trend strength period
- `InpADXTrendThreshold` - Minimum ADX untuk entry
- `InpSpreadFilterPips` - Maksimal spread yang diizinkan

### Pattern Recognition
- `InpEnablePatterns` - Enable/disable pattern detection
- `InpMinPatternScore` - Minimum score untuk valid pattern
- `InpPinBarRatio` - Pin bar shadow/body ratio
- `InpEngulfMultiplier` - Engulfing pattern multiplier

### AI Engine (Advanced)
- `InpEnableAI` - Enable AI prediction module
- `InpAIMinConfidence` - Minimum confidence threshold
- `InpAILearningRate` - Online learning rate
- `InpAIPersistWeights` - Save model between sessions

---

## 🛡️ Safety Features

1. **Max Daily Loss** - Auto stop trading jika loss harian mencapai limit
2. **Max Drawdown** - Proteksi dari drawdown berlebihan
3. **Consecutive Loss Limit** - Stop setelah N loss berturut-turut
4. **Recovery Cooldown** - Delay antara recovery attempts
5. **Spread Filter** - Skip trading saat spread terlalu tinggi
6. **Session Filter** - Trade hanya di jam aktif

---

## 📝 Contoh Quick Start

### Untuk Pemula (Conservative)
```ini
InpRiskPercent=0.5
InpMaxDailyLossPct=2.0
InpSLMultiplier=2.0
InpTPMultiplier=3.0
InpUseTrailingStop=true
InpMinPatternScore=50.0
```

### Untuk Advanced (Aggressive Optimization)
```ini
InpRiskPercent=2.0
InpMaxDailyLossPct=5.0
InpSLMultiplier=1.5
InpTPMultiplier=2.5
InpUseTrailingStop=false
InpMinPatternScore=40.0
```

---

## 🔄 Migrasi dari Preset Lama

Jika Anda menggunakan preset lama, cukup ganti dengan `PASR_EPIC_MASTER.set`:

| Preset Lama | Pengganti di EPIC |
|-------------|------------------|
| `BusinessLogicValidation` | Set `InpDebugMode=true`, `InpRiskPercent=0.5` |
| `FastOptimization` | Gunakan default, disable AI & Dashboard |
| `RealisticValidation` | Enable filters, tighten spreads |
| `Baseline` | Default values sudah sesuai |
| `*Optimization.ini` | Lihat komentar `OptRange` di setiap parameter |

---

## 💡 Best Practices

1. **Selalu test dengan "Every tick based on real ticks"** untuk akurasi maksimal
2. **Gunakan data quality tinggi** (real ticks dari broker)
3. **Forward test minimal 3 bulan** sebelum live trading
4. **Monitor performance bulanan** dan adjust parameter jika perlu
5. **Backup preset custom** Anda sebelum melakukan perubahan besar
6. **Gunakan VPS** untuk live trading agar tidak terputus

---

## 📞 Support & Troubleshooting

### Masalah: Optimization terlalu lambat
**Solusi:** 
- Set `InpEnableAI=false`
- Set `InpShowDashboard=false`
- Gunakan Genetic Algorithm bukan Full Enumeration
- Kurangi jumlah step di OptRange

### Masalah: Hasil optimization tidak konsisten
**Solusi:**
- Gunakan data quality lebih tinggi
- Perpanjang periode testing
- Tighten filter (spread, volatility, session)
- Validate dengan forward testing

### Masalah: Live trading berbeda dengan backtest
**Solusi:**
- Pastikan menggunakan "Every tick based on real ticks"
- Check slippage dan execution delay
- Verify spread settings realistic
- Enable `InpFilterNewsTime=true` untuk hindari news spike

---

## 📈 Version History

- **v3.00** (Current) - EPIC MASTER: All-in-one preset dengan auto-detect mode
- **v2.15** - Separate optimization configs (Market, Pattern, Risk)
- **v2.00** - Initial baseline + validation presets
- **v1.30** - Fast optimization + realistic validation split

---

**🎉 Selamat Trading dengan PASR EPIC MASTER!**

*Satu preset untuk menguasai semuanya - Optimization, Validation, dan Live Trading.*
