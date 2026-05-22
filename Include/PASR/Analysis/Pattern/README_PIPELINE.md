# Pattern Pipeline Architecture - Refactoring Guide

## 🎯 Overview

Arsitektur baru menggunakan **Pipeline Pattern** untuk menggantikan struktur monolithic sebelumnya. Setiap tahap deteksi pattern dipisahkan menjadi modul independen yang dapat diuji dan digunakan kembali.

## 📁 Struktur Folder Baru

```
Pattern/
├── Core/                      # Komponen inti pipeline
│   ├── IPatternStage.mqh      # Interface untuk semua stages
│   ├── PatternContext.mqh     # Context object untuk data sharing
│   └── PatternPipeline.mqh    # Pipeline orchestrator
├── Strategies/                # Implementasi strategi pattern
│   ├── IPatternStrategy.mqh   # Base strategy interface (existing)
│   ├── PinbarStrategy.mqh     # Pinbar detection (existing)
│   ├── EngulfingStrategy.mqh  # Engulfing detection (existing)
│   ├── InsideBarStrategy.mqh  # Inside bar detection (NEW)
│   ├── FakeyStrategy.mqh      # Fakey detection (NEW)
│   └── HaramiStrategy.mqh     # Harami detection (NEW)
├── Stages/                    # Pipeline stages (NEW)
│   ├── PreprocessingStage.mqh # Data preparation & validation
│   ├── DetectionStage.mqh     # Pattern detection orchestration
│   ├── ValidationStage.mqh    # Context & regime validation
│   └── ScoringStage.mqh       # Final scoring & grading
├── Config/                    # Configuration
│   └── PatternConfig.mqh      # Parameter configuration
├── Context/                   # Context objects (existing)
│   └── PatternContext.mqh     # Legacy context (deprecated)
├── CandleUtils.mqh            # Utility functions (existing)
├── FakeoutDetector.mqh        # Fakeout detection (existing)
├── ScoreEngine.mqh            # Scoring engine (existing)
└── PatternManager.mqh         # Main manager (updated to use pipeline)
```

## 🔄 Migration dari Monolithic ke Pipeline

### Sebelum (Monolithic)
```mql5
// Semua logika di satu file besar
CPatternManager::Detect()
{
   // 500+ baris kode untuk semua pattern
   CheckPinbar();
   CheckEngulfing();
   CheckInsideBar();
   // ... dst
}
```

### Sesudah (Pipeline)
```mql5
// Modular dan terpisah
CPatternPipeline pipeline;
pipeline.AddStage(new CPreprocessingStage());
pipeline.AddStage(new CDetectionStage());
pipeline.AddStage(new CValidationStage());
pipeline.AddStage(new CScoringStage());

pipeline.Execute(context);
```

## ✅ Keuntungan Arsitektur Pipeline

1. **Separation of Concerns**: Setiap stage punya tanggung jawab jelas
2. **Testability**: Mudah unit test per stage
3. **Extensibility**: Tambah pattern baru tanpa modifikasi existing code
4. **Maintainability**: Debug lebih mudah, isolasi error
5. **Performance**: Bisa parallelize stages yang independent
6. **Flexibility**: Enable/disable stages dinamis

## 🚀 Cara Menggunakan

### 1. Setup Pipeline
```mql5
#include "Core\PatternPipeline.mqh"
#include "Strategies\PinbarStrategy.mqh"

CPatternPipeline *g_pipeline = NULL;

void OnInit()
{
   g_pipeline = new CPatternPipeline("MainPatternPipeline");
   
   // Add detection strategies as stages
   g_pipeline.AddStage(new CPinbarStrategy());
   g_pipeline.AddStage(new CEngulfingStrategy());
   
   // Initialize
   if(!g_pipeline->Init())
   {
      Print("Failed to initialize pipeline");
   }
}
```

### 2. Execute Pipeline
```mql5
void OnTick()
{
   // Prepare context
   CPatternContext context;
   MqlRates rates[];
   CopyRates(_Symbol, _Period, 0, 100, rates);
   
   context.Init(_Symbol, _Period, rates, currentRegime, currentATR);
   
   // Execute pipeline
   ENUM_PIPELINE_STATUS status = g_pipeline->Execute(context);
   
   if(status == PIPELINE_COMPLETED)
   {
      // Process results
      for(int i = 0; i < context.GetResultCount(); i++)
      {
         SPatternResult *result = context.GetResult(i);
         if(result->IsValid())
         {
            Print("Pattern detected: ", result.ToString());
         }
      }
   }
}
```

### 3. Custom Stage Implementation
```mql5
class CMyCustomStage : public IPatternStage
{
public:
   virtual ENUM_STAGE_STATUS Process(CPatternContext &ctx) override
   {
      // Custom logic here
      if(!ctx.IsValid())
         return STAGE_FAIL;
      
      // Do something with candles
      for(int i = 0; i < ctx.GetBarsCount(); i++)
      {
         const SCandleData &candle = ctx.GetCandle(i);
         // Analyze candle...
      }
      
      return STAGE_OK;
   }
};
```

## 📊 Stage Flow Diagram

```
Input Data
    ↓
[Preprocessing Stage] → Validate & normalize data
    ↓
[Detection Stage] → Run all pattern strategies
    ↓
[Validation Stage] → Check regime & context filters
    ↓
[Scoring Stage] → Calculate final scores
    ↓
Output Results
```

## 🔧 Configuration

Setiap strategy dapat dikonfigurasi secara independen:

```mql5
CPinbarStrategy *pinbar = new CPinbarStrategy();
pinbar.SetMinWickRatio(0.6);    // Minimum 60% wick
pinbar.SetMinBodyRatio(0.3);    // Maximum 30% body
pinbar.SetMinStrength(0.5);     // Minimum strength threshold

pipeline.AddStage(pinbar);
```

## 📈 Statistics & Monitoring

Pipeline menyediakan statistik lengkap:

```mql5
Print(pipeline.GetReport());

// Output:
// === Pattern Pipeline Report ===
// Name: MainPatternPipeline
// Status: PIPELINE_COMPLETED
// Total Runs: 150
// Successful Runs: 148
// Success Rate: 98.67%
// Total Patterns: 342
// Avg Score: 72.45
// Last Run: 2024.05.22 16:30:00
// --- Stages ---
// 1. PinbarStrategy [Enabled]
// 2. EngulfingStrategy [Enabled]
// 3. InsideBarStrategy [Disabled]
```

## ⚠️ Breaking Changes

- `Evaluators.mqh` telah dihapus (digantikan oleh individual strategies)
- `PatternContext.mqh` di folder `Context/` deprecated, gunakan `Core/PatternContext.mqh`
- Method signature di `PatternManager.Detect()` berubah untuk mendukung pipeline

## 📝 Next Steps

1. ✅ Core pipeline infrastructure (DONE)
2. ✅ PatternContext refactoring (DONE)
3. ✅ PinbarStrategy migration (DONE)
4. ⏳ EngulfingStrategy migration
5. ⏳ InsideBarStrategy implementation
6. ⏳ FakeyStrategy implementation
7. ⏳ HaramiStrategy implementation
8. ⏳ Update PatternManager untuk integrate pipeline
9. ⏳ Unit tests untuk setiap stage
10. ⏳ Documentation update

## 🤝 Contributing

Untuk menambah pattern baru:
1. Buat class yang extend `IPatternStage` atau `CBasePatternStrategy`
2. Implementasikan method `Process()` atau `Detect()`
3. Tambahkan ke pipeline dengan `pipeline.AddStage()`
4. Write unit tests
5. Update dokumentasi

---

**Version**: 1.0.0  
**Last Updated**: 2024-05-22  
**Author**: PASR Architecture Team
