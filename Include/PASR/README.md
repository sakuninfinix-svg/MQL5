# PASR Framework — Professional Automated SR Trading System

[![Version](https://img.shields.io/badge/version-2.00-blue.svg)]()
[![MQL5](https://img.shields.io/badge/platform-MQL5-green.svg)]()
[![License](https://img.shields.io/badge/license-Proprietary-red.svg)]()

> **Single source of truth** untuk arsitektur PASR.  
> File ini menggabungkan semua konsep dari `_README.mqh` per-layer  
> menjadi satu dokumen yang komprehensif dan tidak redundan.

---

## 🎯 Overview

**PASR (Professional Automated SR)** adalah framework trading algoritmik berbasis MQL5 yang mengimplementasikan strategi **Supply & Demand** dengan arsitektur event-driven modern, 7-layer separation of concerns, dan AI/ML terintegrasi.

### Key Features

| Feature | Status | Keterangan |
|---------|--------|------------|
| Event-Driven Architecture | ✅ Done | EventBus pattern, loose coupling |
| 7-Layer Architecture | ✅ Done | Strict dependency rules per layer |
| SOLID Principles | ✅ Done | Maintainable & extensible |
| AI/ML Integration | ✅ Done | Decomposed dari God Object, deferred training |
| Config Caching | ✅ Done | m_cfg member, refresh per-bar bukan per-fungsi |
| Indicator Caching | ✅ Done | Lazy evaluation, no redundant iCall |
| Recovery Management | 🔄 Fixing | Bug scope `cfg` sedang diperbaiki |
| Account-Safe GV Keys | ✅ Done | `GVKey()` helper di Globals.mqh |
| Multi-Timeframe Analysis | 🔄 Planned | Phase 2 |

---

## 📁 Project Structure

```
Include/PASR/
│
├── PASR.mqh                            # ★ Master include — satu baris untuk semua
├── Globals.mqh                         # GVKey(), PASRLog, CPerfTimer, validators
│
├── Core/                               # ─── LAYER 1: Foundation (zero deps) ───
│   ├── _README.mqh                     # Layer spec & dependency rules
│   ├── IManager.mqh                    # Abstract base class semua manager
│   ├── EventBus.mqh                    # Priority event queue & dispatcher
│   ├── Events.mqh                      # Semua event struct/enum definitions
│   └── Config/
│       ├── _README.mqh                 # Config sublayer spec
│       ├── Types.mqh                   # StrategyConfig + semua sub-struct
│       └── Manager.mqh                 # Config validation, reload, distribution
│
├── Infra/                              # ─── LAYER 2: Infrastructure / Plumbing ───
│   ├── _README.mqh                     # Layer spec & dependency rules
│   ├── DataManager.mqh                 # ATR/fractal cache, lot sizing, daily PnL
│   ├── MarketManager.mqh               # Session hours, spread, news filter
│   └── ZoneManager.mqh                 # Supply/demand zone detection & storage
│
├── Analysis/                           # ─── LAYER 3: Analysis / Domain ───
│   ├── _README.mqh                     # Layer spec & dependency rules
│   ├── SRManager.mqh                   # S/R level detection & scoring
│   ├── MarketRegime.mqh                # ADX/ATR regime + volatility filter
│   └── Pattern/
│       ├── _README.mqh                 # Pattern sublayer spec
│       ├── PatternManager.mqh          # Orchestrator, delegates ke evaluators
│       ├── Evaluators.mqh              # Per-pattern evaluation logic
│       └── ScoreEngine.mqh             # Pattern scoring & confluence weighting
│
├── Signal/                             # ─── LAYER 4: Signal / Intelligence ───
│   ├── _README.mqh                     # Layer spec & dependency rules
│   ├── SignalManager.mqh               # Aggregates pattern+regime+AI → SignalResult
│   └── AI/                             # AI sublayer (decomposed dari 7.AIManager.mqh)
│       ├── _README.mqh                 # AI sublayer spec & latency budget
│       ├── AIOrchestrator.mqh          # Thin coordinator, SATU-SATUNYA yg di-include
│       ├── AIInference.mqh             # Pure forward-pass, zero alloc, per-tick
│       ├── AITrainer.mqh               # Backprop deferred via EventBus (NewBar only)
│       ├── AIFeatureBuilder.mqh        # Feature extraction dari DataManager
│       └── AITypes.mqh                 # Shared AI types (NN weights, config)
│
├── Trade/                              # ─── LAYER 5: Trade / Execution ───
│   ├── _README.mqh                     # Layer spec, security rule, recovery rule
│   ├── ExecutionManager.mqh            # CTrade wrapper, SL/TP, partial, breakeven
│   └── RecoveryManager.mqh             # Drawdown detection, GV-persisted state
│
├── UI/                                 # ─── LAYER 6: Presentation ───
│   ├── _README.mqh                     # Layer spec & dependency rules
│   └── DashboardManager.mqh            # Chart overlay: equity, positions, regime
│
├── QA/                                 # ─── LAYER 7: Dev Tools (NOT production) ───
│   ├── _README.mqh                     # QA layer spec & PASR_QA_BUILD guard
│   ├── Audit.mqh                       # Runtime audit log
│   ├── Test.mqh                        # Unit test runner
│   └── Optimizations.mqh              # Performance macros & helpers
│
├── docs/                               # Dokumentasi extended (bukan kode)
│   ├── QUICKSTART.md                   # Getting started dalam 5 menit
│   ├── DOCUMENTATION.md               # Architecture deep dive & API reference
│   ├── IMPROVEMENT_ROADMAP.md          # 90-day enhancement plan
│   └── PERFORMANCE_OPTIMIZATION.md    # Advanced optimization techniques
│
└── [legacy shims — backward compat]   # File lama tetap ada, compile normal
    ├── 0.EventBus.mqh                  # → Core/EventBus.mqh
    ├── 1.Events.mqh                    # → Core/Events.mqh
    ├── 2.Config.Types.mqh              # → Core/Config/Types.mqh
    ├── 2.Config.Manager.mqh            # → Core/Config/Manager.mqh
    ├── 3.MarketManager.mqh             # → Infra/MarketManager.mqh
    ├── 3.ZoneManager.mqh               # → Infra/ZoneManager.mqh
    ├── 4.SRManager.mqh                 # → Analysis/SRManager.mqh
    ├── 5.SignalManager.mqh             # → Signal/SignalManager.mqh
    ├── 6.ExecutionManager.mqh          # → Trade/ExecutionManager.mqh
    ├── 7.AIManager.mqh                 # → Signal/AI/AIOrchestrator.mqh
    ├── 8.RecoveryManager.mqh           # → Trade/RecoveryManager.mqh
    ├── 9.PatternManager.mqh            # → Analysis/Pattern/PatternManager.mqh
    ├── 10.DataManager.mqh              # → Infra/DataManager.mqh
    ├── 11.DashboardManager.mqh         # → UI/DashboardManager.mqh
    └── 12.MarketRegime.mqh             # → Analysis/MarketRegime.mqh
```

---

## 🏗️ Layer Architecture

### Dependency Flow (satu arah — tidak boleh terbalik)

```
┌─────────────────────────────────────────────────────┐
│  QA (Layer 7)     — dev only, #ifdef PASR_QA_BUILD  │
│  Boleh include semua layer. TIDAK boleh di-include  │
│  oleh production .mqh atau .mq5 manapun.            │
└────────────────────┬────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────┐
│  UI (Layer 6)     — DashboardManager                │
│  MAY include : Core, Infra, Analysis, Signal, Trade │
│  MUST NOT    : ─                                    │
└────────────────────┬────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────┐
│  Trade (Layer 5)  — Execution, Recovery             │
│  MAY include : Core, Infra                          │
│  MAY read    : Analysis types (via parameters)      │
│  MUST NOT    : Signal/, UI/                         │
└────────────────────┬────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────┐
│  Signal (Layer 4) — SignalManager + AI sublayer     │
│  MAY include : Core, Infra, Analysis                │
│  MUST NOT    : Trade/, UI/                          │
│                                                     │
│  Signal/AI/       — sublayer dari Signal            │
│    AIInference  → per-tick, zero alloc, O(layers)  │
│    AITrainer    → deferred via EventBus (NewBar)    │
│    AIOrchestrator → satu-satunya yg di-include      │
│                     oleh SignalManager              │
└────────────────────┬────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────┐
│  Analysis (Layer 3) — SR, Regime, Pattern           │
│  MAY include : Core, Infra                          │
│  MUST NOT    : Signal/, Trade/, UI/                 │
│                                                     │
│  CATATAN:                                           │
│  - Pattern/ files tidak boleh include SRManager     │
│    atau MarketRegime (data dikirim via parameter)   │
│  - MarketRegime tidak boleh include DataManager     │
│    langsung (gunakan IDataProvider interface)       │
└────────────────────┬────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────┐
│  Infra (Layer 2)  — DataManager, Market, Zone       │
│  MAY include : Core only                            │
│  MUST NOT    : Analysis/, Signal/, Trade/, UI/      │
│                                                     │
│  CATATAN:                                           │
│  - DataManager TIDAK boleh include Config/Manager   │
│    Config diinjeksi via InitConfigCache(cfg&)       │
│  - MarketRegimeFilter diakses via extern pointer    │
│    g_regimeFilter dari Globals.mqh                 │
└────────────────────┬────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────┐
│  Core (Layer 1)   — IManager, EventBus, Config      │
│  MAY include : Core/ only                           │
│  MUST NOT    : semua layer lain                     │
│                                                     │
│  RATIONALE: Core tidak boleh tahu business logic.   │
│  Jika Core file butuh type dari layer lain →        │
│  gunakan forward declaration atau interface.        │
└─────────────────────────────────────────────────────┘
```

### Layer Summary

| Layer | Folder | Isi | Boleh include |
|-------|--------|-----|-----------------|
| L1 | `Core/` | IManager, EventBus, Events, Config | Core/ saja |
| L2 | `Infra/` | DataManager, MarketManager, ZoneManager | Core/ |
| L3 | `Analysis/` | SRManager, MarketRegime, Pattern/ | Core/, Infra/ |
| L4 | `Signal/` | SignalManager, AI/ | Core/, Infra/, Analysis/ |
| L5 | `Trade/` | ExecutionManager, RecoveryManager | Core/, Infra/ |
| L6 | `UI/` | DashboardManager | Semua L1-L5 |
| L7 | `QA/` | Audit, Test, Optimizations | Semua layer |

---

## 🚀 Quick Start

### Production EA

```mql5
// Satu baris — semua layer tersedia dengan load order yang benar
#include <PASR/PASR.mqh>
```

### Include layer tertentu saja

```mql5
// Hanya event system:
#include <PASR/Core/EventBus.mqh>

// Hanya infrastructure:
#include <PASR/Infra/DataManager.mqh>

// Hanya signal layer:
#include <PASR/Signal/SignalManager.mqh>
```

### Development / QA Build

```mql5
// Aktifkan QA tools — HANYA untuk dev/test build, tidak untuk production!
#define PASR_QA_BUILD
#include <PASR/PASR.mqh>
#include <PASR/QA/Test.mqh>
#include <PASR/QA/Audit.mqh>
```

### Debug Logging

```mql5
// Aktifkan verbose logging
#define PASR_DEBUG
#include <PASR/PASR.mqh>
```

---

## 🔑 Globals.mqh — Safety Helpers

### Account-Safe GlobalVariable Keys

**WAJIB digunakan** untuk semua GlobalVariable. Mencegah state corruption antara
instance live + demo yang berjalan bersamaan dengan magic number yang sama.

```mql5
#include <PASR/Globals.mqh>

// Format key: "<login>_<symbol>_<magic>_<purpose>"
// Contoh: "123456789_EURUSD_12345_TRADE_STATE"

// Set:
GVSet("TRADE_STATE", 1.0);

// Get (dengan default jika belum ada):
double state = GVGet("TRADE_STATE", 0.0);

// Delete:
GVDelete("TRADE_STATE");

// Check exists:
if (GVExists("TRADE_STATE")) { ... }
```

### Performance Profiling

```mql5
#include <PASR/Globals.mqh>

void OnTick() {
    CPerfTimer timer;
    timer.Start();

    // ... logic ...

    ulong us = timer.Elapsed();
    if (us > 100) timer.Log("OnTick"); // alert jika > 100µs
}
```

---

## ⚡ Performance Budget

| Handler | Target | Strategi |
|---------|--------|----------|
| `OnTick()` total | < 100µs | Early return, zero alloc, no string ops |
| `OnNewBar()` total | < 2ms | Deferred compute via EventBus |
| EventBus dispatch | < 50µs | Array-based queue, no map lookup |
| `AIInference` per-tick | < 0.5ms | O(layers), no dynamic alloc |
| `AITrainer` per-NewBar | < 50ms | Deferred, tidak pernah di OnTick() |
| Dashboard render | 1 Hz max | Throttle dengan `GetMicrosecondCount()` |
| Config cache refresh | Per-bar | `m_cfg` member, bukan per-fungsi copy |

---

## 🛠️ Development Tools (QA Layer)

> ⚠️ **Tidak boleh masuk production build.** Gunakan `#define PASR_QA_BUILD`.

### Code Quality Audit

```mql5
#define PASR_QA_BUILD
#include <PASR/QA/Audit.mqh>

PASRAuditor auditor;
auditor.RunFullAudit();
```

### Unit Testing

```mql5
#define PASR_QA_BUILD
#include <PASR/QA/Test.mqh>

TestRunner runner;
runner.RegisterTest(myTest);
TestSuiteReport report = runner.RunAll();
report.LogReport();
```

---

## 🐛 Known Issues (v1.x bugs — must fix)

> Bugs ini didokumentasikan di `Trade/_README.mqh` dan `Analysis/_README.mqh`.

| ID | File | Bug | Severity | Fix |
|----|------|-----|----------|-----|
| PASR-BUG-001 | `8.RecoveryManager.mqh` | `cfg` digunakan tanpa deklarasi di scope `ClearEngineGVs()` | 🔴 Critical | Tambah `StrategyConfig cfg; CheckPointer(m_data); m_data.GetConfigCache(cfg);` |
| PASR-BUG-002 | `6.ExecutionManager.mqh` | `ScavengePendingGVs()` O(total_GVs × positions) setiap bar | 🔴 Critical | Cache GV keys di `string m_gvKeys[]`, update hanya saat trade open/close |
| PASR-BUG-003 | `6.ExecutionManager.mqh` | GV keys tanpa `AccountLogin` prefix | 🟠 High | Ganti semua dengan `GVKey()` dari Globals.mqh |
| PASR-BUG-004 | `7.AIManager.mqh` | Backprop jalan synchronous di tick thread | 🟠 High | Pindah ke deferred EventBus event (AITrainer sudah siap di Signal/AI/) |
| PASR-BUG-005 | `11.DashboardManager.mqh` | String rebuild setiap `OnPriceUpdate` | 🟡 Medium | Throttle 1 Hz dengan `GetMicrosecondCount()` guard |
| PASR-BUG-006 | Multiple files | `StrategyConfig cfg` copy per-fungsi | 🟡 Medium | Pakai `m_cfg` member, refresh per-bar via `ConfigReloadEvent` |

---

## 📊 Migration Status

Track progress migrasi dari file numbered ke canonical path.

| Source (lama) | Target (baru) | Status |
|---------------|---------------|--------|
| `0.EventBus.mqh` | `Core/EventBus.mqh` | ✅ Shim done |
| `1.Events.mqh` | `Core/Events.mqh` | ✅ Shim done |
| `2.Config.Types.mqh` | `Core/Config/Types.mqh` | ✅ Shim done |
| `2.Config.Manager.mqh` | `Core/Config/Manager.mqh` | ✅ Shim done |
| `3.MarketManager.mqh` | `Infra/MarketManager.mqh` | ⏳ Pending full migration |
| `3.ZoneManager.mqh` | `Infra/ZoneManager.mqh` | ⏳ Pending full migration |
| `4.SRManager.mqh` | `Analysis/SRManager.mqh` | ⏳ Pending full migration |
| `5.SignalManager.mqh` | `Signal/SignalManager.mqh` | ✅ Shim done |
| `6.ExecutionManager.mqh` | `Trade/ExecutionManager.mqh` | ✅ Shim done + PASR-BUG-002/003 to fix |
| `7.AIManager.mqh` | `Signal/AI/AIOrchestrator.mqh` | ✅ Decomposed (Orchestrator+Inference+Trainer) |
| `8.RecoveryManager.mqh` | `Trade/RecoveryManager.mqh` | ✅ Shim done + PASR-BUG-001 to fix |
| `9.PatternManager.mqh` | `Analysis/Pattern/PatternManager.mqh` | ✅ Shim done |
| `10.DataManager.mqh` | `Infra/DataManager.mqh` | ⏳ Pending full migration |
| `11.DashboardManager.mqh` | `UI/DashboardManager.mqh` | ✅ Shim done + PASR-BUG-005 to fix |
| `12.MarketRegime.mqh` | `Analysis/MarketRegime.mqh` | ⏳ Pending full migration |
| `PASR.Audit.mqh` | `QA/Audit.mqh` | ⏳ Pending full migration |
| `PASR.Test.mqh` | `QA/Test.mqh` | ⏳ Pending full migration |
| `PASR.Optimizations.mqh` | `QA/Optimizations.mqh` | ⏳ Pending full migration |

---

## 📈 Roadmap

### Phase 1 — Foundation (Days 1-30) 🔄 In Progress

- [x] Audit tool created (`QA/Audit.mqh`)
- [x] Test framework created (`QA/Test.mqh`)
- [x] Folder structure defined per `_README.mqh` layer specs
- [x] Shims created untuk semua canonical paths
- [x] `PASR.mqh` master include dengan enforced load order
- [x] `Globals.mqh` dengan `GVKey()` account-safe helper
- [x] AI decomposed: `AIOrchestrator` + `AIInference` + `AITrainer`
- [ ] Fix PASR-BUG-001 (`RecoveryManager` cfg scope)
- [ ] Fix PASR-BUG-002 (`ScavengePendingGVs` O(n×m))
- [ ] Fix PASR-BUG-003 (GV keys → `GVKey()`)
- [ ] Fix PASR-BUG-004 (backprop deferred)
- [ ] 60% test coverage di `QA/Test.mqh`

### Phase 2 — Performance (Days 31-60)

- [ ] Event dispatch ≤ 50µs verified dengan `CPerfTimer`
- [ ] Full migration semua pending file ke canonical paths
- [ ] Enum `ENUM_EVENT_ID` menggantikan `#define EVENT_ID_*`
- [ ] Memory per symbol ≤ 2KB (audit dengan `QA/Audit.mqh`)
- [ ] Lazy indicator updates
- [ ] Tick batching

### Phase 3 — Scalability (Days 61-90)

- [ ] Multi-symbol support
- [ ] Config hot-reload tanpa restart EA
- [ ] ONNX model support via `AIInference.mqh`
- [ ] Test coverage ≥ 80%
- [ ] Performance regression test suite

---

## 📝 Developer Notes

### Rules yang TIDAK boleh dilanggar

1. **Dependency rules** — setiap layer hanya boleh include layer di bawahnya (lihat tabel Layer Summary)
2. **GV keys** — SELALU gunakan `GVKey()` dari `Globals.mqh`, TIDAK PERNAH hardcode string GV
3. **AI Trainer** — TIDAK PERNAH dipanggil langsung dari `OnTick()`, hanya via deferred EventBus event
4. **QA layer** — TIDAK PERNAH masuk production build, wajib dibungkus `#ifdef PASR_QA_BUILD`
5. **Config copy** — TIDAK PERNAH `StrategyConfig cfg; m_data.GetConfigCache(cfg)` di dalam fungsi — selalu pakai `m_cfg` member
6. **Legacy shims** — TIDAK perlu diubah, biarkan tetap ada untuk backward compat EA lama

### Untuk EA baru

```mql5
#include <PASR/PASR.mqh>          // ← satu baris ini saja
```

### Untuk EA lama (tidak perlu diubah)

```mql5
#include <PASR/10.DataManager.mqh>  // ← masih berfungsi via shim
```

### Kalau butuh hanya satu sublayer

```mql5
#include <PASR/Signal/AI/AIOrchestrator.mqh>   // AI saja
#include <PASR/Analysis/Pattern/PatternManager.mqh>  // Pattern saja
#include <PASR/QA/Audit.mqh>  // Audit saja (dev build)
```

---

## 📚 Extended Documentation

| Dokumen | Isi |
|---------|-----|
| [docs/QUICKSTART.md](docs/QUICKSTART.md) | Getting started dalam 5 menit |
| [docs/DOCUMENTATION.md](docs/DOCUMENTATION.md) | Architecture deep dive & API reference |
| [docs/IMPROVEMENT_ROADMAP.md](docs/IMPROVEMENT_ROADMAP.md) | 90-day enhancement plan |
| [docs/PERFORMANCE_OPTIMIZATION.md](docs/PERFORMANCE_OPTIMIZATION.md) | Profiling & optimization patterns |

---

## 📄 License

Proprietary — Copyright 2026 Agsicentre

---

**Built with ❤️ for Algorithmic Trading**
