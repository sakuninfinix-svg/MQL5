# PASR Framework — Performance Optimization Guide

## Profiling dengan CPerfTimer

```mql5
#include <PASR/Globals.mqh>

void OnTick() {
    CPerfTimer timer;
    timer.Start();

    // ... logic ...

    ulong elapsed = timer.Elapsed();
    if (elapsed > 100)  // alert jika > 100µs
        PrintFormat("[PERF] OnTick slow: %dµs", elapsed);
}
```

## Dashboard Throttle Pattern

```mql5
// Di DashboardManager — render max 1x per detik
void OnPriceUpdate(const double bid, const double ask) {
    static ulong s_lastRender = 0;
    if (GetMicrosecondCount() - s_lastRender < 1000000) return;
    s_lastRender = GetMicrosecondCount();
    // ... render logic ...
}
```

## Config Caching Pattern

```mql5
// SEBELUM (BURUK — struct copy per-fungsi):
void CalculateStopLoss() {
    StrategyConfig cfg;          // 400B copy setiap fungsi dipanggil!
    m_data.GetConfigCache(cfg);
    return cfg.StopLoss;
}

// SESUDAH (BAIK — satu kali per bar):
class CMyManager : public IManager {
    StrategyConfig m_cfg;

    void OnNewBar() {
        m_data.GetConfigCache(m_cfg);  // refresh hanya sekali per bar
    }

    void CalculateStopLoss() {
        return m_cfg.StopLoss;         // zero-copy read
    }
};
```

## GV Key Caching (Fix ScavengePendingGVs)

```mql5
// SEBELUM (BURUK — O(n×m) setiap bar):
void ScavengePendingGVs() {
    for (int i = 0; i < total_gvs; i++) {     // scan ALL global vars
        for (int j = 0; j < positions; j++) { // cross-check positions
            // O(n*m) — catastrophic on live accounts
        }
    }
}

// SESUDAH (BAIK — O(1) lookup per position):
class CExecutionManager : public IManager {
    string m_gvKeys[];            // cached GV keys
    int    m_gvCount;

    void OnTradeOpen(const ulong ticket) {
        // Add key to cache on trade open
        int n = ArraySize(m_gvKeys);
        ArrayResize(m_gvKeys, n + 1);
        m_gvKeys[n] = GVKey("TICKET_" + IntegerToString(ticket));
        m_gvCount++;
    }

    void ScavengePendingGVs() {
        // O(m) — only iterate known keys
        for (int i = 0; i < m_gvCount; i++) {
            if (!GlobalVariableCheck(m_gvKeys[i])) {
                // removed from cache
                ArrayRemove(m_gvKeys, i, 1);
                m_gvCount--;
                i--;
            }
        }
    }
};
```

## Memory Optimization

- Gunakan `ZeroMemory(array)` bukan manual zero-fill loops
- Deklarasi string builder sebagai `static` di dalam fungsi yang sering dipanggil
- Hindari `ArrayCopy()` untuk array besar di hot path — gunakan pointer/index trick
- Pool allocator untuk event objects yang sering di-create/destroy
