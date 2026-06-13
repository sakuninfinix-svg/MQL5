//+------------------------------------------------------------------+
//|                                       Core/Config/Types.mqh     |
//|                                       Copyright 2026, Agsicentre|
//|                                                                  |
//|  PURPOSE: Canonical StrategyConfig + domain sub-structs.         |
//|    - Pure data: NO methods, NO includes, NO EventBus            |
//|    - DO NOT add #include here — keep this a pure data header     |
//|    - Consumed by: IManager, CConfigManager, CConfigValidator    |
//|    - Sub-structs enforce SRP at the config data level            |
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_CONFIG_TYPES_MQH__
#define __CORE_CONFIG_TYPES_MQH__

//+------------------------------------------------------------------+
//| RiskConfig — all risk management parameters                      |
//+------------------------------------------------------------------+
struct RiskConfig
  {
   double LotSize;
   double RiskPercent;
   double SLMultiplier;
   double TPMultiplier;
   double MaxDailyLossPct;
   double MaxDrawdownPct;
   int    MaxOpenPositions;
   int    MaxConsecLoss;
   bool   UseBreakEven;
   double BreakEvenATRMult;
   bool   UseTrailingStop;
   double TrailATRMult;
   bool   RecoveryEnabled;
   int    MaxRecoveryAttempts;
   int    RecoveryCooldownBars;
   double PartialClosePct;
   int    MaxTradeDurationDays;

   RiskConfig()
      : LotSize(0.01),          RiskPercent(1.0),
        SLMultiplier(1.5),      TPMultiplier(2.5),
        MaxDailyLossPct(3.0),   MaxDrawdownPct(10.0),
        MaxOpenPositions(3),    MaxConsecLoss(5),
        UseBreakEven(true),     BreakEvenATRMult(1.0),
        UseTrailingStop(false), TrailATRMult(1.0),
        RecoveryEnabled(true),  MaxRecoveryAttempts(3),
        RecoveryCooldownBars(5),
        PartialClosePct(0.5),   MaxTradeDurationDays(0) {}
  };

//+------------------------------------------------------------------+
//| MarketConfig — indicator & session parameters                    |
//+------------------------------------------------------------------+
struct MarketConfig
  {
   int    ATRPeriod;
   int    ADXPeriod;
   double ADXTrendThreshold;
   double SpreadFilterPips;
   int    SessionStartHour;
   int    SessionEndHour;
   bool   FilterNewsTime;
   int    NewsBufferMinutes;

   MarketConfig()
      : ATRPeriod(14), ADXPeriod(14), ADXTrendThreshold(25.0),
        SpreadFilterPips(3.0),
        SessionStartHour(0), SessionEndHour(23),
        FilterNewsTime(false), NewsBufferMinutes(30) {}
  };

//+------------------------------------------------------------------+
//| AIConfig — AI/ML subsystem and risk-decision parameters          |
//+------------------------------------------------------------------+
struct AIConfig
  {
   bool   EnableAI;
   double MinConfidence;
   double LearningRate;
   int    TrainIntervalBars;
   int    ReplayBufferSize;
   int    MinibatchSize;
   bool   PersistWeights;
   string ModelFileName;
   string OnnxModelFileName;
   bool   EnableOnnx;

   //--- Regime strategy thresholds / risk multipliers
   double TrendEntryThreshold;
   double TrendRiskMultiplier;
   double TrendStrategyConfidence;
   double RangeEntryThreshold;
   double RangeRiskMultiplier;
   double RangeStrategyConfidence;
   double VolatileEntryThreshold;
   double VolatileRiskMultiplier;
   double VolatileStrategyConfidence;
   double ConservativeEntryThreshold;
   double ConservativeRiskMultiplier;
   double ConservativeStrategyConfidence;
   double ScalpEntryThreshold;
   double ScalpRiskMultiplier;
   double ScalpStrategyConfidence;

   //--- Regime detection normalization thresholds
   double StrongTrendLevel;
   double RangeTrendMax;
   double RangeVolatilityMax;
   double VolatileLevel;
   double TrendLevel;
   int    RegimeConfirmBars;
   int    RegimeATRPeriod;
   int    RegimeADXPeriod;

   //--- Risk-aware AI decision coefficients
   double DriftFailureWeight;
   double RegimeFailureWeight;
   double ConfidenceRewardWeight;
   double EdgeRewardWeight;
   double RegimeRewardWeight;
   double FailurePenaltyWeight;
   double NoTradeDriftWeight;
   double ConservativeNoTradePenalty;
   double MinExpectedR;
   double MaxFailureProbability;
   double StrongConfidenceBuffer;
   double StrongConfidenceMin;
   double StrongExpectedR;
   double StrongMaxFailureProbability;
   double VolatileSLBoost;
   double RangeSLTighten;
   double MinSL_ATR;
   double MaxSL_ATR;
   double MinTP_ATR;
   double MaxTP_ATR;
   double MinTPExpectedR;
   double RiskFailureWeight;
   double MinRiskMultiplier;
   double MaxRiskMultiplier;
   double ConservativeSignalThreshold;
   double LowStrategyConfidence;
   int    LowStrategySignalThreshold;
   int    RangeSignalThreshold;
   int    MeanRevertSignalThreshold;

   //--- Advanced internal model blending
   double LSTMBlendWeight;
   double EnsembleBlendWeight;

   AIConfig()
      : EnableAI(false),        MinConfidence(0.60),
        LearningRate(0.001),    TrainIntervalBars(5),
        ReplayBufferSize(512),  MinibatchSize(32),
        PersistWeights(true),   ModelFileName("PASR_mlp_m0.bin"),
        OnnxModelFileName("PASR_sequence.onnx"), EnableOnnx(false),
        TrendEntryThreshold(0.60), TrendRiskMultiplier(1.20), TrendStrategyConfidence(0.85),
        RangeEntryThreshold(0.65), RangeRiskMultiplier(1.30), RangeStrategyConfidence(0.85),
        VolatileEntryThreshold(0.85), VolatileRiskMultiplier(0.90), VolatileStrategyConfidence(0.70),
        ConservativeEntryThreshold(0.95), ConservativeRiskMultiplier(0.10), ConservativeStrategyConfidence(0.00),
        ScalpEntryThreshold(0.70), ScalpRiskMultiplier(1.00), ScalpStrategyConfidence(0.75),
        StrongTrendLevel(0.80), RangeTrendMax(0.30), RangeVolatilityMax(0.30),
        VolatileLevel(0.80), TrendLevel(0.50), RegimeConfirmBars(3),
        RegimeATRPeriod(20), RegimeADXPeriod(50),
        DriftFailureWeight(0.35), RegimeFailureWeight(0.15),
        ConfidenceRewardWeight(2.00), EdgeRewardWeight(1.25), RegimeRewardWeight(0.75), FailurePenaltyWeight(1.40),
        NoTradeDriftWeight(0.50), ConservativeNoTradePenalty(0.25),
        MinExpectedR(0.35), MaxFailureProbability(0.72),
        StrongConfidenceBuffer(0.10), StrongConfidenceMin(0.75), StrongExpectedR(1.20), StrongMaxFailureProbability(0.45),
        VolatileSLBoost(1.25), RangeSLTighten(0.90),
        MinSL_ATR(0.60), MaxSL_ATR(3.00), MinTP_ATR(1.00), MaxTP_ATR(5.00), MinTPExpectedR(1.15),
        RiskFailureWeight(0.45), MinRiskMultiplier(0.05), MaxRiskMultiplier(1.50),
        ConservativeSignalThreshold(90.0), LowStrategyConfidence(0.40),
        LowStrategySignalThreshold(70), RangeSignalThreshold(60), MeanRevertSignalThreshold(50),
        LSTMBlendWeight(0.60), EnsembleBlendWeight(0.40) {}
  };

//+------------------------------------------------------------------+
//| PatternConfig — pattern recognition parameters                   |
//+------------------------------------------------------------------+
struct PatternConfig
  {
   bool   EnablePatterns;
   double MinPatternScore;
   double MinDominanceGap;
   int    LookbackBars;
   double PinBarRatio;
   double EngulfMultiplier;
   bool   RequireConfirmation;

   PatternConfig()
      : EnablePatterns(true), MinPatternScore(60.0), MinDominanceGap(0.05),
        LookbackBars(50),     PinBarRatio(2.0),
        EngulfMultiplier(1.1), RequireConfirmation(true) {}
  };

//+------------------------------------------------------------------+
//| SignalTuningConfig — signal/MTF constants exposed for testing    |
//+------------------------------------------------------------------+
struct SignalTuningConfig
  {
   bool   UseMTF;
   int    SignalLookback;
   int    MinConfluence;
   double MinScore;
   double MinDominanceGap;
   int    MaxSourceAgeSeconds;
   int    SignalCooldownBars;
   bool   ExitOnOpposite;
   double ZoneReuseATR;
   int    PatternFailureCooldownBars;
   int    EntryMode;
   double MaxSignalATR;
   double AntiBreakoutPct;
   double MomentumThresholdATR;
   double MinTPDistanceATR;
   double MinRRRatio;
   double ATRBufferMult;
   double MaxSpreadPoints;
   double MinATRPoints;
   bool   UseSessionFilter;
   double UrgencyHighThreshold;
   double UrgencyMediumThreshold;

   SignalTuningConfig()
      : UseMTF(true), SignalLookback(20), MinConfluence(1), MinScore(0.40), MinDominanceGap(0.05),
        MaxSourceAgeSeconds(120), SignalCooldownBars(3), ExitOnOpposite(false),
        ZoneReuseATR(0.5), PatternFailureCooldownBars(5), EntryMode(0), MaxSignalATR(2.0),
        AntiBreakoutPct(0.85), MomentumThresholdATR(0.3), MinTPDistanceATR(1.5), MinRRRatio(1.5),
        ATRBufferMult(1.0), MaxSpreadPoints(30), MinATRPoints(0.0), UseSessionFilter(false),
        UrgencyHighThreshold(0.75), UrgencyMediumThreshold(0.55) {}
  };

//+------------------------------------------------------------------+
//| DisplayConfig — on-chart dashboard & notification parameters     |
//+------------------------------------------------------------------+
struct DisplayConfig
  {
   bool   ShowDashboard;
   bool   ShowSignalArrows;
   bool   EnableAlerts;
   bool   EnablePushNotify;
   color  BullColor;
   color  BearColor;
   int    FontSize;

   DisplayConfig()
      : ShowDashboard(true),  ShowSignalArrows(true),
        EnableAlerts(false),  EnablePushNotify(false),
        BullColor(clrDodgerBlue), BearColor(clrOrangeRed),
        FontSize(9) {}
  };

//+------------------------------------------------------------------+
//| StrategyConfig — root configuration object                       |
//+------------------------------------------------------------------+
struct StrategyConfig
  {
   long   MagicNumber;
   string EAName;
   string Version;

   RiskConfig         Risk;
   MarketConfig       Market;
   AIConfig           AI;
   PatternConfig      Pattern;
   SignalTuningConfig Signal;
   DisplayConfig      Display;

   StrategyConfig()
      : MagicNumber(123456),
        EAName("PASR"),
        Version("2.16.0") {}
  };

#endif // __CORE_CONFIG_TYPES_MQH__