# UI Module (`PASR/UI/`)

1 file — Dashboard manager with chart overlay.

## File Reference

| # | File | Class | Fungsi |
|---|------|-------|--------|
| 1 | `DashboardManager.mqh` | `CDashboardManager` | Runtime chart overlay: balance, equity, PnL, drawdown, AI score, regime, positions, signal status |

## Dashboard Display

```
╔══════════════════════════════════════╗
║  PASR v6.x  |  Magic: 123456        ║
║  Balance: 10,000.00  Equity: 9,850   ║
║  Daily PnL: +150.00  Drawdown: 1.5%  ║
║  AI Score: 0.78  Regime: TREND_UP    ║
║  Signal: BUY  Conf: 0.65  (Pattern)  ║
║  Open: 2 pos  Volume: 0.15           ║
║  Recovery: 0 active                  ║
║  Observability: [text overlay]       ║
╚══════════════════════════════════════╝
```

## Key Methods

| Method | Fungsi |
|--------|--------|
| `SetPipelineSignal(SSignal&)` | Update signal direction/confidence |
| `SetAIScore(double)` | Update AI inference score |
| `SetRegime(EMarketRegime)` | Update market regime display |
| `SetSessionDD(double)` | Update session drawdown |
| `SetObservabilityText(string)` | Set observability overlay text |
| `Update(DashContext&)` | Re-render chart comment |
| `OnTimer()` | Trigger periodic update |
| `OnChartEvent()` | Handle chart click events |
