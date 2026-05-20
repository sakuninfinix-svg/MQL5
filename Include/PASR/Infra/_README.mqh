//+------------------------------------------------------------------+
//| PASR LAYER 2 — INFRASTRUCTURE / DATA                            |
//|                                                                  |
//| PURPOSE:                                                         |
//|   Platform-level services: indicator caching, account state,   |
//|   session filtering, spread monitoring, and S/R zone storage.  |
//|   These are pure "plumbing" — they hold no trading logic.       |
//|                                                                  |
//| CONTENTS:                                                        |
//|   DataManager.mqh   — ATR/fractal cache, lot sizing, daily PnL |
//|   MarketManager.mqh — Session hours, spread, news filter       |
//|   ZoneManager.mqh   — Supply/demand zone detection & storage   |
//|                                                                  |
//| DEPENDENCY RULES (STRICT):                                       |
//|   ✅ MAY include   : Core/ only                                 |
//|   ❌ MUST NOT include: Analysis/, Signal/, Trade/, UI/          |
//|                                                                  |
//| NOTES:                                                           |
//|   - MarketRegimeFilter is accessed via extern pointer           |
//|     g_regimeFilter (declared in Globals.mqh). Infra layer must  |
//|     never directly include Analysis/MarketRegime.mqh.           |
//|   - DataManager.mqh must NOT include Config/Manager.mqh.        |
//|     Config is injected via InitConfigCache(StrategyConfig&).    |
//+------------------------------------------------------------------+
//
// Migration status:
//   [ ] DataManager.mqh   — pending (source: ../10.DataManager.mqh)
//   [ ] MarketManager.mqh — pending (source: ../3.MarketManager.mqh)
//   [ ] ZoneManager.mqh   — pending (source: ../3.ZoneManager.mqh)
