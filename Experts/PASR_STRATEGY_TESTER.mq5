//+------------------------------------------------------------------+
//| PASR_STRATEGY_TESTER.mq5                                         |
//| Strategy Tester Runner — evaluates all 8 strategy profiles       |
//| Quant Developer — Senior MQL Architecture                        |
//+------------------------------------------------------------------+
#property strict
#include <PASR/Core/PASR.mqh>
#include <PASR/Central/PASRKernel.mqh>
#include <PASR/QA/StrategyTestSuite.mqh>

input group "Test Configuration"
input ENUM_STRATEGY_PROFILE InpTestProfile = STRATEGY_MODERATE;
input bool   InpRunComparison = false;  // Run all profiles and compare

input group "PASR Identity"
input long   InpMagicNumber = 123456;
input string InpEAName = "PASR_STRATEGY_TESTER";

input group "Risk Overrides (0 = use profile defaults)"
input double InpLotSizeOverride = 0.0;
input double InpRiskPercentOverride = 0.0;
input double InpSLMultiplierOverride = 0.0;
input double InpTPMultiplierOverride = 0.0;
input double InpMaxDailyLossPctOverride = 0.0;
input double InpMaxDrawdownPctOverride = 0.0;
input int    InpMaxOpenPositionsOverride = 0;
input int    InpMaxConsecLossOverride = 0;
input bool   InpUseBreakEvenOverride = false;
input bool   InpUseTrailingStopOverride = false;

input group "Market Overrides"
input int    InpATRPeriod = 14;
input int    InpADXPeriod = 14;
input double InpADXTrendThresholdOverride = 0.0;
input double InpSpreadFilterPipsOverride = 0.0;
input int    InpSessionStartHour = 0;
input int    InpSessionEndHour = 23;

input group "Signal Overrides"
input bool   InpUseMTFOverride = false;
input int    InpMinConfluenceOverride = 0;
input double InpSignalMinScoreOverride = 0.0;
input double InpMinRRRatioOverride = 0.0;

input group "Pattern Overrides"
input bool   InpEnablePatternsOverride = false;
input double InpMinPatternScoreOverride = 0.0;

input group "AI Overrides"
input bool   InpEnableAIOverride = false;
input double InpAIMinConfidenceOverride = 0.0;
input double InpAIMinExpectedROverride = 0.0;
input double InpAIMaxFailureProbabilityOverride = 0.0;

CPASRKernel g_kernel;
SStrategyTestConfig g_testConfig;
bool g_stateInitialized = false;

StrategyConfig BuildConfigFromTestProfile(const SStrategyTestConfig &testCfg)
  {
   StrategyConfig cfg;
   cfg.EAName = InpEAName;
   cfg.Version = "2.16.0";
   cfg.MagicNumber = InpMagicNumber;

   cfg.Risk.LotSize = (InpLotSizeOverride > 0) ? InpLotSizeOverride : testCfg.lotSize;
   cfg.Risk.RiskPercent = (InpRiskPercentOverride > 0) ? InpRiskPercentOverride : testCfg.riskPercent;
   cfg.Risk.SLMultiplier = (InpSLMultiplierOverride > 0) ? InpSLMultiplierOverride : testCfg.slMultiplier;
   cfg.Risk.TPMultiplier = (InpTPMultiplierOverride > 0) ? InpTPMultiplierOverride : testCfg.tpMultiplier;
   cfg.Risk.MaxDailyLossPct = (InpMaxDailyLossPctOverride > 0) ? InpMaxDailyLossPctOverride : testCfg.maxDailyLossPct;
   cfg.Risk.MaxDrawdownPct = (InpMaxDrawdownPctOverride > 0) ? InpMaxDrawdownPctOverride : testCfg.maxDrawdownPct;
   cfg.Risk.MaxOpenPositions = (InpMaxOpenPositionsOverride > 0) ? InpMaxOpenPositionsOverride : testCfg.maxOpenPositions;
   cfg.Risk.MaxConsecLoss = (InpMaxConsecLossOverride > 0) ? InpMaxConsecLossOverride : testCfg.maxConsecLoss;
   cfg.Risk.UseBreakEven = (InpUseBreakEvenOverride) ? true : testCfg.useBreakEven;
   cfg.Risk.BreakEvenATRMult = 1.0;
   cfg.Risk.UseTrailingStop = (InpUseTrailingStopOverride) ? true : testCfg.useTrailingStop;
   cfg.Risk.TrailATRMult = 1.0;
   cfg.Risk.RecoveryEnabled = true;
   cfg.Risk.MaxRecoveryAttempts = 3;
   cfg.Risk.RecoveryCooldownBars = 5;
   cfg.Risk.PartialClosePct = 0.5;
   cfg.Risk.MaxTradeDurationDays = 0;

   cfg.Market.ATRPeriod = InpATRPeriod;
   cfg.Market.ADXPeriod = InpADXPeriod;
   cfg.Market.ADXTrendThreshold = (InpADXTrendThresholdOverride > 0) ? InpADXTrendThresholdOverride : testCfg.adxTrendThreshold;
   cfg.Market.SpreadFilterPips = (InpSpreadFilterPipsOverride > 0) ? InpSpreadFilterPipsOverride : testCfg.spreadFilterPips;
   // Set per-day sessions: Mon-Fri from profile, Sun/Sat inactive
   cfg.Market.Sessions[0] = DaySession(0, 0, false);
   for(int d = 1; d <= 5; d++)
      cfg.Market.Sessions[d] = DaySession(testCfg.sessionStartMin, testCfg.sessionEndMin, true);
   cfg.Market.Sessions[6] = DaySession(0, 0, false);
   cfg.Market.FilterNewsTime = false;
   cfg.Market.NewsBufferMinutes = 30;

   cfg.AI.EnableAI = (InpEnableAIOverride) ? true : testCfg.enableAI;
   cfg.AI.MinConfidence = (InpAIMinConfidenceOverride > 0) ? InpAIMinConfidenceOverride : testCfg.aiMinConfidence;
   cfg.AI.LearningRate = 0.0003;
   cfg.AI.TrainIntervalBars = 5;
   cfg.AI.ReplayBufferSize = 512;
   cfg.AI.MinibatchSize = 32;
   cfg.AI.PersistWeights = true;
   cfg.AI.ModelFileName = "PASR_mlp_m0.bin";
   cfg.AI.EnableOnnx = false;
   cfg.AI.OnnxModelFileName = "";
   cfg.AI.TrendEntryThreshold = testCfg.trendEntryThreshold;
   cfg.AI.TrendRiskMultiplier = testCfg.trendRiskMultiplier;
   cfg.AI.RangeEntryThreshold = testCfg.rangeEntryThreshold;
   cfg.AI.RangeRiskMultiplier = testCfg.rangeRiskMultiplier;
   cfg.AI.VolatileEntryThreshold = testCfg.volatileEntryThreshold;
   cfg.AI.VolatileRiskMultiplier = testCfg.volatileRiskMultiplier;
   cfg.AI.ConservativeEntryThreshold = 0.95;
   cfg.AI.ConservativeRiskMultiplier = 0.10;
   cfg.AI.ScalpEntryThreshold = 0.70;
   cfg.AI.ScalpRiskMultiplier = 1.00;
   cfg.AI.MinExpectedR = (InpAIMinExpectedROverride > 0) ? InpAIMinExpectedROverride : testCfg.aiMinExpectedR;
   cfg.AI.MaxFailureProbability = (InpAIMaxFailureProbabilityOverride > 0) ? InpAIMaxFailureProbabilityOverride : testCfg.aiMaxFailureProbability;
   cfg.AI.StrongConfidenceBuffer = 0.10;
   cfg.AI.StrongConfidenceMin = 0.75;
   cfg.AI.StrongExpectedR = 1.20;
   cfg.AI.StrongMaxFailureProbability = 0.40;
   cfg.AI.DriftFailureWeight = 0.35;
   cfg.AI.RegimeFailureWeight = 0.25;
   cfg.AI.ConfidenceRewardWeight = 2.00;
   cfg.AI.EdgeRewardWeight = 1.25;
   cfg.AI.RegimeRewardWeight = 0.75;
   cfg.AI.FailurePenaltyWeight = 1.40;
   cfg.AI.RiskFailureWeight = 0.45;

   cfg.Signal.UseMTF = (InpUseMTFOverride) ? true : testCfg.useMTF;
   cfg.Signal.SignalLookback = 20;
   cfg.Signal.MinConfluence = (InpMinConfluenceOverride > 0) ? InpMinConfluenceOverride : testCfg.minConfluence;
   cfg.Signal.MinScore = (InpSignalMinScoreOverride > 0) ? InpSignalMinScoreOverride : testCfg.signalMinScore;
   cfg.Signal.MinDominanceGap = 0.05;
   cfg.Signal.MaxSourceAgeSeconds = 120;
   cfg.Signal.SignalCooldownBars = 3;
   cfg.Signal.MinRRRatio = (InpMinRRRatioOverride > 0) ? InpMinRRRatioOverride : testCfg.minRRRatio;
   cfg.Signal.MaxSignalATR = 2.0;
   cfg.Signal.UrgencyHighThreshold = 0.75;
   cfg.Signal.UrgencyMediumThreshold = 0.55;

   cfg.Pattern.EnablePatterns = (InpEnablePatternsOverride) ? true : testCfg.enablePatterns;
   cfg.Pattern.MinPatternScore = (InpMinPatternScoreOverride > 0) ? InpMinPatternScoreOverride : testCfg.minPatternScore;
   cfg.Pattern.PatternLookbackBars = 50;
   cfg.Pattern.MinPatternDominanceGap = testCfg.minPatternDominanceGap;
   cfg.Pattern.PinBarRatio = 2.0;
   cfg.Pattern.EngulfMultiplier = 1.1;
   cfg.Pattern.RequireConfirmation = false;

   cfg.Display.ShowDashboard = false;
   cfg.Display.ShowSignalArrows = false;
   cfg.Display.EnableAlerts = false;
   cfg.Display.EnablePushNotify = false;
   cfg.Display.FontSize = 9;

   return cfg;
  }

int OnInit()
  {
   g_testConfig = GetStrategyConfig(InpTestProfile);

   // If running comparison, skip individual init
   if(InpRunComparison)
      return INIT_SUCCEEDED;

   StrategyConfig cfg = BuildConfigFromTestProfile(g_testConfig);
   if(g_kernel.Init(cfg) != INIT_SUCCEEDED)
      return INIT_PARAMETERS_INCORRECT;

   g_stateInitialized = true;
   EventSetTimer(1);
   Print("[StrategyTester] Initialized profile: ", g_testConfig.name);
   return INIT_SUCCEEDED;
  }

double OnTester()
  {
   return ComputeStrategyFitness();
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(g_stateInitialized)
      g_kernel.OnDeinit(reason);
   g_stateInitialized = false;
  }

void OnTick()
  {
   if(!g_stateInitialized) return;
   g_kernel.OnTick();
  }

void OnTimer()
  {
   if(!g_stateInitialized) return;
   g_kernel.OnTimer();
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(!g_stateInitialized) return;
   g_kernel.OnTradeTransaction(trans, request, result);
  }

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   if(!g_stateInitialized) return;
   g_kernel.OnChartEvent(id, lparam, dparam, sparam);
  }
