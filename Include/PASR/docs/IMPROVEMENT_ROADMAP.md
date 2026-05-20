# PASR Framework — 90-Day Improvement Roadmap

## Phase 1 (Days 1-30): Foundation & Safety ✅ IN PROGRESS

### Critical Bugs to Fix (Week 1)
- [ ] `RecoveryManager::ClearEngineGVs()` — undeclared `cfg` variable crash
- [ ] All GV keys — add AccountLogin prefix via `GVKey()` helper
- [ ] `ScavengePendingGVs()` — O(n×m) loop → cache GV keys in string array
- [ ] `2.Config.Types.mqh` — tambah `bool Validate(string &errors[])` method

### Architecture Cleanup (Week 2)
- [ ] Enum `ENUM_EVENT_ID` menggantikan `#define EVENT_ID_*` macros
- [ ] Centralize `extern *g_regimeFilter` ke `Globals.mqh`
- [ ] Remove direct `#include "2.Config.Manager.mqh"` dari DataManager

### Code Quality (Week 3-4)
- [ ] DashboardManager — throttle render ke 1 Hz
- [ ] Replace per-function `StrategyConfig cfg` copies dengan `m_cfg` member
- [ ] Unit test framework setup (`Tools/Test.mqh` coverage)

## Phase 2 (Days 31-60): Performance

- [ ] EventBus dispatch ≤ 50µs verified dengan CPerfTimer
- [ ] Memory per symbol ≤ 2KB (audit dengan Tools/Audit.mqh)
- [ ] Lazy indicator updates — compute only when requested
- [ ] Tick batching — batch micro-movements sebelum dispatch
- [ ] AI backprop — deferred training via EventBus queue

## Phase 3 (Days 61-90): Scalability

- [ ] Multi-symbol support (symbol-keyed manager instances)
- [ ] Config hot-reload tanpa EA restart
- [ ] Advanced AI features (ONNX model support)
- [ ] Comprehensive test coverage >80%
- [ ] Performance regression test suite
