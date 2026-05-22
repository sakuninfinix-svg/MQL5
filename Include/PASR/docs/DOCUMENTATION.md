# PASR Framework — Architecture & API Reference

## Architecture Overview

PASR menggunakan **7-layer architecture** dengan dependency flow satu arah (lower layers tidak boleh depend ke layer lebih tinggi):

```
L0: Tools/Optimizations     ← macros, CStringPool (no MQL5 deps)
L1: Core/Config/Types       ← plain structs only
L2: Core/EventBus           ← Event, IEventHandler, EventBus
L3: Core/Events             ← concrete event classes
L4: Core/IManager           ← base interface: Init/Shutdown/OnNewBar
L5: Globals                 ← GVKey(), helpers, CPerfTimer
L6: Data/DataManager        ← indicator + symbol data cache
L7: Core/Config/Manager     ← loads+validates StrategyConfig
L8: Data/MarketRegime       ← trend/range/volatile regime
L9: Analysis/ZoneManager    ← supply/demand zone detection (v2.01)
L10: Data/MarketManager     ← spread, session, conditions
L11: Data/SRManager         ← S/R level calculation
L12: Analysis/PatternManager <- candlestick pattern recognition
L13: Signal/SignalManager   ← entry/exit signal orchestration
L14: AI/CAIOrchestrator     ← ML inference & regime enhancement (26-dim, v4.02)
L15: Trade/ExecutionManager ← CTrade wrapper, SL/TP management
L16: Trade/RecoveryManager  ← error recovery, GV state cleanup
L17: UI/DashboardManager    ← chart overlay dashboard
```

## Key Design Patterns

### Event-Driven Communication

Managers communicate exclusively through EventBus — never direct pointer calls:

```mql5
// PUBLISH
CSignalEvent event(SIGNAL_BUY, 1.0, close);
m_bus.Publish(event);

// SUBSCRIBE
m_bus.Subscribe(EVENT_SIGNAL, GetPointer(this));

// HANDLE
void OnEvent(const CEvent *evt) override {
    if (evt.GetId() == EVENT_SIGNAL) { ... }
}
```

### Config Caching Pattern

Ambil config SATU kali per manager, bukan per-fungsi:

```mql5
class CMyManager : public IManager {
private:
    StrategyConfig m_cfg;           // cached config
    bool           m_cfgDirty;

    void RefreshConfig() {
        if (m_cfgDirty) {
            m_data.GetConfigCache(m_cfg);
            m_cfgDirty = false;
        }
    }

public:
    void OnEvent(const CEvent *evt) override {
        if (evt.GetId() == EVENT_CONFIG_RELOAD)
            m_cfgDirty = true;      // lazy reload
    }
};
```

### Account-Safe GlobalVariables

SELALU gunakan GVKey() atau helper dari Globals.mqh:

```mql5
// BERBAHAYA — collision antara live/demo:
GlobalVariableSet("TRADE_STATE", 1.0);

// AMAN — auto prefix account_symbol_magic:
GVSet("TRADE_STATE", 1.0);
```

## Performance Budget

| Handler | Budget | Strategy |
|---------|--------|----------|
| OnTick() | <100µs | Early return, no allocs |
| OnNewBar() | <2ms | Deferred heavy compute |
| EventBus dispatch | <50µs | Array-based queue |
| Dashboard render | 1 Hz max | Throttle with GetMicrosecondCount() |

## Critical Known Issues (to fix)

1. **RecoveryManager::ClearEngineGVs()** — `cfg` tidak di-declare di scope. Fix:
   ```mql5
   StrategyConfig cfg;
   m_data.GetConfigCache(cfg);
   ```
2. **CAIOrchestrator training** — deferred ke EventBus queue (tidak blocking tick thread).
3. **DashboardManager** — tambah throttle 1Hz sebelum rebuild string.
