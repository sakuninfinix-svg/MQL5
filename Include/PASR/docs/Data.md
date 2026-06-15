# Data Module (`PASR/Data/`)

3 files — Core data structures and symbol scanning.

## File Reference

| # | File | Structs/Classes | Fungsi |
|---|------|-----------------|--------|
| 1 | `SRStruct.mqh` | `SRZone`, `SRZoneResult`, `SRCluster` | S/R zone: price boundaries, strength, touch count, validation, clustering |
| 2 | `RegimeTypes.mqh` | `SRegimeSnapshot`, `EMarketRegime` enum | `EMarketRegime`: UNKNOWN, TREND_UP, TREND_DOWN, RANGE, VOLATILE, TRANSITION, CRASH, SQUEEZE |
| 3 | `SymbolScanner.mqh` | `CSymbolScanner` (extends IManager), `SymbolInfoEx`, `SymbolFilterCriteria` | Multi-symbol watchlist: round-robin scanning, session/spread/trade filters |

## SRZone Struct (SRStruct.mqh)

```cpp
struct SRZone {
    double priceHigh, priceLow, priceCenter;
    double strength;           // 0.0 - 1.0
    int touchCount;
    bool isValid, isBroken;
    datetime formedAt, lastTouched;
    bool IsPriceInZone(double price);
    double DistanceFrom(double price);
    string ToString();
};
```

## EMarketRegime (RegimeTypes.mqh)

| Regime | Deskripsi |
|--------|-----------|
| `UNKNOWN` | Not yet detected |
| `TREND_UP` | Strong uptrend (high ADX, DI+ > DI-) |
| `TREND_DOWN` | Strong downtrend (high ADX, DI- > DI+) |
| `RANGE` | Low volatility, no clear direction |
| `VOLATILE` | High ATR, erratic price action |
| `TRANSITION` | Switching between regimes |
| `CRASH` | Sudden volatility spike with downward momentum |
| `SQUEEZE` | Very low BB bandwidth (breakout imminent) |

Helper: `MarketRegimeName(EMarketRegime regime)` returns string.
