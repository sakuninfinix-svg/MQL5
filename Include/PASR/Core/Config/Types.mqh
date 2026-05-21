//+------------------------------------------------------------------+
//|                                       Core/Config/Types.mqh     |
//|                                       Copyright 2026, Agsicentre|
//|                                                                  |
//|  PURPOSE: Canonical StrategyConfig + 5 domain sub-structs.      |
//|    - Pure data: NO methods, NO includes, NO EventBus            |
//|    - DO NOT add #include here — keep this a pure data header     |
//|    - Consumed by: IManager, CConfigManager, CConfigValidator    |
//|    - Sub-structs enforce SRP at the config data level            |
//|                                                                  |
//|  SUB-STRUCT MAP:                                                  |
//|    StrategyConfig                                                |
//|      .Risk     → RiskConfig    (lot, %, SL/TP mult, BE, trail,  |
//|                                  recovery, partial, expiry)     |
//|      .Market   → MarketConfig  (ATR/ADX, spread, session, news) |
//|      .AI       → AIConfig      (enable, confidence, lr, replay) |
//|      .Pattern  → PatternConfig (enable, score, lookback, ratios)|
//|      .Display  → DisplayConfig (panel, arrows, alerts, colors)  |
//|                                                                  |
//|  CHANGE LOG:                                                     |
//|  v2.14 (2026-05-21) — Phase 6 fields added to RiskConfig:       |
//|    + RecoveryEnabled        — bool, master switch for recovery   |
//|    + MaxRecoveryAttempts    — int,  max retries before abandon   |
//|    + RecoveryCooldownBars   — int,  bars to wait between retries |
//|    + PartialClosePct        — double, fraction to partial close  |
//|    + MaxTradeDurationDays   — int, force-close after N days (0=off)|
//|  All new fields have safe production defaults.                   |
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_CONFIG_TYPES_MQH__
#define __CORE_CONFIG_TYPES_MQH__

//+------------------------------------------------------------------+
//| RiskConfig — all risk management parameters                      |
//+------------------------------------------------------------------+
struct RiskConfig
  {
   //--- Lot sizing (mutually exclusive: use one, set other to 0)
   double LotSize;              // fixed lot size (0 = use RiskPercent)
   double RiskPercent;          // % of equity per trade (0 = use LotSize)

   //--- SL / TP
   double SLMultiplier;         // StopLoss  = ATR * SLMultiplier
   double TPMultiplier;         // TakeProfit = ATR * TPMultiplier

   //--- Session & drawdown limits
   double MaxDailyLossPct;      // EA halts if daily drawdown exceeds this %
   int    MaxOpenPositions;     // max concurrent open positions

   //--- Break-even
   bool   UseBreakEven;         // move SL to break-even when in profit
   double BreakEvenATRMult;     // BE trigger: price moved ATR * this mult

   //--- Trailing stop
   bool   UseTrailingStop;      // enable ATR-based trailing stop
   double TrailATRMult;         // trail distance = ATR * this mult

   //--- [Phase 6] Recovery system
   // RecoveryEnabled: master switch. When false, RecoveryManager skips
   //   all SL-hit handling and lets MT5 close the position normally.
   bool   RecoveryEnabled;      // default: true

   // MaxRecoveryAttempts: after this many attempts the engine gives up
   //   and marks the position as DONE. Prevents infinite retry loops.
   int    MaxRecoveryAttempts;  // default: 3   (range: 1..10)

   // RecoveryCooldownBars: minimum bars to wait between recovery attempts.
   //   Prevents rapid-fire SL adjustments on choppy bars.
   int    RecoveryCooldownBars; // default: 5   (range: 1..50)

   //--- [Phase 6] Partial close
   // PartialClosePct: fraction of lot to close when price reaches
   //   TPMultiplier * 0.5 ATR profit. 0 = disabled.
   // Example: 0.5 = close 50% of position at half-TP.
   double PartialClosePct;      // default: 0.5 (range: 0.1..0.9; 0 = off)

   //--- [Phase 6] Trade expiry
   // MaxTradeDurationDays: force-close any position older than N days.
   //   Useful for preventing stale recovery positions from sitting open
   //   over weekends. 0 = disabled.
   int    MaxTradeDurationDays; // default: 0   (range: 0..30; 0 = off)

   RiskConfig()
      : LotSize(0.01),          RiskPercent(1.0),
        SLMultiplier(1.5),      TPMultiplier(2.5),
        MaxDailyLossPct(3.0),   MaxOpenPositions(3),
        UseBreakEven(true),     BreakEvenATRMult(1.0),
        UseTrailingStop(false), TrailATRMult(1.0),
        //--- Phase 6 defaults
        RecoveryEnabled(true),        MaxRecoveryAttempts(3),
        RecoveryCooldownBars(5),
        PartialClosePct(0.5),         MaxTradeDurationDays(0) {}
  };

//+------------------------------------------------------------------+
//| MarketConfig — indicator & session parameters                    |
//+------------------------------------------------------------------+
struct MarketConfig
  {
   int    ATRPeriod;            // iATR period (bars)
   int    ADXPeriod;            // iADX period (bars)
   double ADXTrendThreshold;    // ADX > this value = trending market
   double SpreadFilterPips;     // skip entry if current spread > this (pips)
   int    SessionStartHour;     // trading session start hour (broker time)
   int    SessionEndHour;       // trading session end hour (broker time)
   bool   FilterNewsTime;       // pause trading around news events
   int    NewsBufferMinutes;    // minutes before+after news to skip

   MarketConfig()
      : ATRPeriod(14), ADXPeriod(14), ADXTrendThreshold(25.0),
        SpreadFilterPips(3.0),
        SessionStartHour(0), SessionEndHour(23),
        FilterNewsTime(false), NewsBufferMinutes(30) {}
  };

//+------------------------------------------------------------------+
//| AIConfig — AI/ML subsystem parameters                            |
//+------------------------------------------------------------------+
struct AIConfig
  {
   bool   EnableAI;             // master switch: enable AI signal filter
   double MinConfidence;        // min softmax score required to emit signal
   double LearningRate;         // backpropagation learning rate
   int    TrainIntervalBars;    // minimum bars between training cycles
   int    ReplayBufferSize;     // experience replay buffer capacity
   int    MinibatchSize;        // samples per backpropagation step
   bool   PersistWeights;       // save/load trained weights to/from file
   string ModelFileName;        // weight file name (relative to MQL5/Common)

   AIConfig()
      : EnableAI(false),        MinConfidence(0.60),
        LearningRate(0.001),    TrainIntervalBars(5),
        ReplayBufferSize(512),  MinibatchSize(32),
        PersistWeights(true),   ModelFileName("PASR_weights.bin") {}
  };

//+------------------------------------------------------------------+
//| PatternConfig — pattern recognition parameters                   |
//+------------------------------------------------------------------+
struct PatternConfig
  {
   bool   EnablePatterns;       // master switch: enable pattern filter
   double MinPatternScore;      // minimum composite score [0-100]
   int    LookbackBars;         // bars to look back when scanning patterns
   double PinBarRatio;          // min wick:body ratio to qualify as pin bar
   double EngulfMultiplier;     // engulf: current body must be >= prev * this
   bool   RequireConfirmation;  // wait for bar close before acting on signal

   PatternConfig()
      : EnablePatterns(true), MinPatternScore(60.0),
        LookbackBars(50),     PinBarRatio(2.0),
        EngulfMultiplier(1.1), RequireConfirmation(true) {}
  };

//+------------------------------------------------------------------+
//| DisplayConfig — on-chart dashboard & notification parameters     |
//+------------------------------------------------------------------+
struct DisplayConfig
  {
   bool   ShowDashboard;        // render on-chart info panel
   bool   ShowSignalArrows;     // draw buy/sell arrows on chart
   bool   EnableAlerts;         // send MT5 native alert popup
   bool   EnablePushNotify;     // send push notification to mobile
   color  BullColor;            // buy signal arrow / label color
   color  BearColor;            // sell signal arrow / label color
   int    FontSize;             // dashboard text font size (points)

   DisplayConfig()
      : ShowDashboard(true),  ShowSignalArrows(true),
        EnableAlerts(false),  EnablePushNotify(false),
        BullColor(clrDodgerBlue), BearColor(clrOrangeRed),
        FontSize(9) {}
  };

//+------------------------------------------------------------------+
//| StrategyConfig — root configuration object                       |
//|                                                                  |
//| OWNERSHIP: Created once by CConfigManager in EA OnInit().        |
//| DISTRIBUTION: Sent to all managers via EventBus ConfigReloadEvent|
//|   Each manager caches it as m_cfg — NOT per-function copies.     |
//| VALIDATION: Always validated by CConfigValidator before dispatch. |
//| DEFAULTS: All sub-struct constructors provide production-safe     |
//|   defaults; never a zero-initialised struct in production.        |
//+------------------------------------------------------------------+
struct StrategyConfig
  {
   //--- Identity
   long   MagicNumber;   // unique EA instance identifier (> 0)
   string EAName;        // human-readable name for logs and chart objects
   string Version;       // semantic version string e.g. "2.14.0"

   //--- Domain sub-structs (each has safe constructor defaults)
   RiskConfig     Risk;
   MarketConfig   Market;
   AIConfig       AI;
   PatternConfig  Pattern;
   DisplayConfig  Display;

   StrategyConfig()
      : MagicNumber(123456),
        EAName("PASR"),
        Version("2.14.0") {}
  };

#endif // __CORE_CONFIG_TYPES_MQH__
