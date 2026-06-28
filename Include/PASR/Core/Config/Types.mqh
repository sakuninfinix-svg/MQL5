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
   bool   UseAutoLot;       // Use risk-based auto lot sizing
   double AutoLotMin;       // Minimum lot when auto lot is active
   double AutoLotMax;       // Maximum lot when auto lot is active
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
   double SLHeadroomPips;       // Flat buffer added to Stop Loss (pips)
   double TPHeadroomPips;       // Flat buffer added to Take Profit (pips)
   double SLHeadroomATRMult;    // Dynamic buffer: SL += ATR * this multiplier (0 = off)
   double TPHeadroomATRMult;    // Dynamic buffer: TP += ATR * this multiplier (0 = off)

   RiskConfig()
      : LotSize(0.01),          UseAutoLot(false),
        AutoLotMin(0.01),       AutoLotMax(10.0),
        RiskPercent(1.0),
        SLMultiplier(1.5),      TPMultiplier(2.5),
        MaxDailyLossPct(3.0),   MaxDrawdownPct(10.0),
        MaxOpenPositions(3),    MaxConsecLoss(5),
        UseBreakEven(true),     BreakEvenATRMult(1.0),
        UseTrailingStop(false), TrailATRMult(1.0),
        RecoveryEnabled(true),  MaxRecoveryAttempts(3),
        RecoveryCooldownBars(5),
        PartialClosePct(0.5),   MaxTradeDurationDays(0),
        SLHeadroomPips(0.0),    TPHeadroomPips(0.0),
        SLHeadroomATRMult(0.0), TPHeadroomATRMult(0.0) {}
  };

//+------------------------------------------------------------------+
//| DaySession — trading session for a single day of the week        |
//|   StartMinutes / EndMinutes = minutes from midnight (0-1439)    |
//|   Active = false means no trading on this day                    |
//|   Index convention (MQL5 day_of_week):                           |
//|     0=Sunday 1=Monday 2=Tuesday 3=Wednesday                     |
//|     4=Thursday 5=Friday 6=Saturday                              |
//+------------------------------------------------------------------+
struct DaySession
  {
   int  StartMinutes;
   int  EndMinutes;
   bool Active;

   DaySession() : StartMinutes(0), EndMinutes(1380), Active(true) {}
   DaySession(int startMin, int endMin, bool active)
      : StartMinutes(startMin), EndMinutes(endMin), Active(active) {}
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
   DaySession Sessions[7];   // Per-day session: [0]=Sun .. [6]=Sat
   bool   FilterNewsTime;
   int    NewsBufferMinutes;

   MarketConfig()
      : ATRPeriod(14), ADXPeriod(14), ADXTrendThreshold(25.0),
        SpreadFilterPips(3.0),
        FilterNewsTime(false), NewsBufferMinutes(30)
     {
      // Default: all 7 days active 00:00-23:00 (= no session filter)
      for(int i = 0; i < 7; i++)
         Sessions[i] = DaySession(0, 1380, true);
     }
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

    //--- GBR (Gradient Boosting Regressor) configuration
    bool   EnableGBR;
    int    GBRN_estimators;
    double GBRLearning_rate;
    int    GBRMax_depth;
    double GBRMin_samples_split;
    double GBRMin_samples_leaf;
    double GBRSubsample;
    double GBRColsample_bytree;
    double GBRReg_alpha;
    double GBRReg_lambda;
    double GBRGamma;
    string GBRModelPath;
    double GBRBlendWeight;  // Blend weight for GBR in ensemble

    //--- MTF Hard Gate thresholds (per AI_Development.md)
    double MTFMinConfidence;
    double MTFMinScore;
    double VolatilityDriftThreshold;
    double MaxConfidenceThreshold;

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
         LSTMBlendWeight(0.60), EnsembleBlendWeight(0.40),
         EnableGBR(true), GBRN_estimators(150), GBRLearning_rate(0.05),
         GBRMax_depth(4), GBRMin_samples_split(0.03), GBRMin_samples_leaf(0.015),
         GBRSubsample(0.8), GBRColsample_bytree(0.7), GBRReg_alpha(0.05),
         GBRReg_lambda(0.8), GBRGamma(0.05), GBRModelPath("PASR_gbr_m0.onnx"),
         GBRBlendWeight(0.30),
         MTFMinConfidence(0.55), MTFMinScore(0.15), VolatilityDriftThreshold(0.70), MaxConfidenceThreshold(0.95) {}
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
