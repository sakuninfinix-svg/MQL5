//+------------------------------------------------------------------+
//| PASR LAYER 3 — ANALYSIS / DOMAIN                                |
//|                                                                  |
//| PURPOSE:                                                         |
//|   Market analysis: support/resistance levels, market regime     |
//|   classification, volatility filtering, and candlestick/price  |
//|   action pattern recognition.                                   |
//|                                                                  |
//| CONTENTS:                                                        |
//|   SRManager.mqh      — S/R level detection & scoring           |
//|   MarketRegime.mqh   — ADX/ATR regime + volatility filter       |
//|   Pattern/           — Candlestick & price action patterns      |
//|     PatternManager.mqh — Orchestrator, delegates to evaluators  |
//|     Evaluators.mqh     — Per-pattern evaluation logic           |
//|     ScoreEngine.mqh    — Pattern scoring & confluence weighting |
//|                                                                  |
//| DEPENDENCY RULES (STRICT):                                       |
//|   ✅ MAY include   : Core/, Infra/                              |
//|   ❌ MUST NOT include: Signal/, Trade/, UI/                     |
//|                                                                  |
//| NOTES:                                                           |
//|   - MarketRegime.mqh must NOT include Infra/DataManager.mqh     |
//|     directly. DataManager is accessed via the IDataProvider     |
//|     interface pointer (forward-declared, never included).       |
//|   - Pattern/ subfolder files must NOT include SRManager.mqh     |
//|     or MarketRegime.mqh. The orchestrator (PatternManager.mqh)  |
//|     owns those relationships and passes data as function args.  |
//+------------------------------------------------------------------+
//
// Migration status:
//   [ ] SRManager.mqh      — pending (source: ../4.SRManager.mqh)
//   [ ] MarketRegime.mqh   — pending (source: ../12.MarketRegime.mqh)
//   [ ] Pattern/           — DONE (already migrated)
