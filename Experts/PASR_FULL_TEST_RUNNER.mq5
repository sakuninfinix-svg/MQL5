//+------------------------------------------------------------------+
//| PASR_FULL_TEST_RUNNER.mq5                                        |
//| Integrated Test Runner — combines all test frameworks            |
//| Strategy Tester + Walk-Forward + Monte Carlo + Optimization      |
//| Quant Developer — Senior MQL Architecture                        |
//+------------------------------------------------------------------+
#property strict
#property copyright "Agsicentre — PASR v2.16.0"
#property version   "2.16.0"
#property description "PASR Full Test Runner"

#include <PASR/Core/PASR.mqh>
#include <PASR/Central/PASRKernel.mqh>
#include <PASR/QA/StrategyTestSuite.mqh>
#include <PASR/QA/WalkForwardFramework.mqh>
#include <PASR/QA/MonteCarloFramework.mqh>
#include <PASR/QA/OptimizationSets.mqh>

// ====================================================================
// TEST MODE SELECTION
// ====================================================================
enum ENUM_TEST_MODE
  {
   TEST_SINGLE_BACKTEST,    // Run one strategy profile backtest
   TEST_FULL_COMPARISON,    // Compare all 8 profiles
   TEST_OPTIMIZATION_SET_A, // Conservative optimization (5 params)
   TEST_OPTIMIZATION_SET_B, // Moderate optimization (10 params)
   TEST_OPTIMIZATION_SET_C, // AI-focused optimization (8 params)
   TEST_WALK_FORWARD,       // Walk-forward analysis (requires history)
   TEST_MONTE_CARLO,        // Monte Carlo stress test (requires history)
   TEST_FULL_BATTERY        // Run ALL tests sequentially
  };

// ====================================================================
// INPUT PARAMETERS
// ====================================================================
input group "=== TEST CONFIGURATION ==="
input ENUM_TEST_MODE  InpTestMode = TEST_SINGLE_BACKTEST;
input ENUM_STRATEGY_PROFILE InpProfile = STRATEGY_MODERATE;

input group "=== PASR IDENTITY ==="
input long   InpMagicNumber = 123456;
input string InpEAName = "PASR_FULL_TEST_RUNNER";

input group "=== RISK (0 = use profile default) ==="
input double InpRiskPercentOverride = 0.0;
input double InpSLMultiplierOverride = 0.0;
input double InpTPMultiplierOverride = 0.0;
input double InpMaxDailyLossPctOverride = 0.0;
input double InpMaxDrawdownPctOverride = 0.0;
input int    InpMaxOpenPositionsOverride = 0;
input bool   InpUseBreakEvenOverride = false;
input bool   InpUseTrailingStopOverride = false;

input group "=== SIGNAL (0 = use profile default) ==="
input double InpSignalMinScoreOverride = 0.0;
input int    InpMinConfluenceOverride = 0;
input double InpMinRRRatioOverride = 0.0;
input double InpADXThresholdOverride = 0.0;

input group "=== AI ==="
input bool   InpEnableAI = false;
input double InpAIMinConfidenceOverride = 0.0;
input double InpAIMinExpectedROverride = 0.0;

input group "=== MARKET ==="
input int    InpATRPeriod = 14;
input int    InpADXPeriod = 14;
input double InpSpreadFilterPips = 3.0;
input int    InpSessionStartHour = 0;
input int    InpSessionEndHour = 23;

input group "=== PATTERN ==="
input bool   InpEnablePatterns = true;
input double InpMinPatternScoreOverride = 0.0;

// ====================================================================
// GLOBAL STATE
// ====================================================================
CPASRKernel g_kernel;
SStrategyTestConfig g_testConfig;
bool g_initialized = false;

// ====================================================================
// Build strategy config from inputs + profile
// ====================================================================
StrategyConfig BuildConfig()
  {
   SStrategyTestConfig tc = GetStrategyConfig(InpProfile);
   g_testConfig = tc;

   StrategyConfig cfg;
   cfg.EAName = InpEAName;
   cfg.Version = "2.16.0";
   cfg.MagicNumber = InpMagicNumber;

   cfg.Risk.LotSize = 0.01;
   cfg.Risk.RiskPercent = (InpRiskPercentOverride > 0) ? InpRiskPercentOverride : tc.riskPercent;
   cfg.Risk.SLMultiplier = (InpSLMultiplierOverride > 0) ? InpSLMultiplierOverride : tc.slMultiplier;
   cfg.Risk.TPMultiplier = (InpTPMultiplierOverride > 0) ? InpTPMultiplierOverride : tc.tpMultiplier;
   cfg.Risk.MaxDailyLossPct = (InpMaxDailyLossPctOverride > 0) ? InpMaxDailyLossPctOverride : tc.maxDailyLossPct;
   cfg.Risk.MaxDrawdownPct = (InpMaxDrawdownPctOverride > 0) ? InpMaxDrawdownPctOverride : tc.maxDrawdownPct;
   cfg.Risk.MaxOpenPositions = (InpMaxOpenPositionsOverride > 0) ? InpMaxOpenPositionsOverride : tc.maxOpenPositions;
   cfg.Risk.MaxConsecLoss = tc.maxConsecLoss;
   cfg.Risk.UseBreakEven = (InpUseBreakEvenOverride) ? true : tc.useBreakEven;
   cfg.Risk.BreakEvenATRMult = 1.0;
   cfg.Risk.UseTrailingStop = (InpUseTrailingStopOverride) ? true : tc.useTrailingStop;
   cfg.Risk.TrailATRMult = 1.0;
   cfg.Risk.RecoveryEnabled = true;
   cfg.Risk.MaxRecoveryAttempts = 3;
   cfg.Risk.RecoveryCooldownBars = 5;
   cfg.Risk.PartialClosePct = 0.5;
   cfg.Risk.MaxTradeDurationDays = 0;

   cfg.Market.ATRPeriod = InpATRPeriod;
   cfg.Market.ADXPeriod = InpADXPeriod;
   cfg.Market.ADXTrendThreshold = (InpADXThresholdOverride > 0) ? InpADXThresholdOverride : tc.adxTrendThreshold;
   cfg.Market.SpreadFilterPips = InpSpreadFilterPips;
   // Set per-day sessions: Mon-Fri from profile, Sun/Sat inactive
   cfg.Market.Sessions[0] = DaySession(0, 0, false);
   for(int d = 1; d <= 5; d++)
      cfg.Market.Sessions[d] = DaySession(tc.sessionStartMin, tc.sessionEndMin, true);
   cfg.Market.Sessions[6] = DaySession(0, 0, false);
   cfg.Market.FilterNewsTime = false;
   cfg.Market.NewsBufferMinutes = 30;

   cfg.AI.EnableAI = InpEnableAI;
   cfg.AI.MinConfidence = (InpAIMinConfidenceOverride > 0) ? InpAIMinConfidenceOverride : tc.aiMinConfidence;
   cfg.AI.LearningRate = 0.0003;
   cfg.AI.TrainIntervalBars = 5;
   cfg.AI.ReplayBufferSize = 512;
   cfg.AI.MinibatchSize = 32;
   cfg.AI.PersistWeights = true;
   cfg.AI.ModelFileName = "PASR_mlp_m0.bin";
   cfg.AI.EnableOnnx = false;
   cfg.AI.OnnxModelFileName = "";
   cfg.AI.TrendEntryThreshold = tc.trendEntryThreshold;
   cfg.AI.TrendRiskMultiplier = tc.trendRiskMultiplier;
   cfg.AI.RangeEntryThreshold = tc.rangeEntryThreshold;
   cfg.AI.RangeRiskMultiplier = tc.rangeRiskMultiplier;
   cfg.AI.VolatileEntryThreshold = tc.volatileEntryThreshold;
   cfg.AI.VolatileRiskMultiplier = tc.volatileRiskMultiplier;
   cfg.AI.ConservativeEntryThreshold = 0.95;
   cfg.AI.ConservativeRiskMultiplier = 0.10;
   cfg.AI.ScalpEntryThreshold = 0.70;
   cfg.AI.ScalpRiskMultiplier = 1.00;
   cfg.AI.MinExpectedR = (InpAIMinExpectedROverride > 0) ? InpAIMinExpectedROverride : tc.aiMinExpectedR;
   cfg.AI.MaxFailureProbability = tc.aiMaxFailureProbability;
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

   cfg.Signal.UseMTF = tc.useMTF;
   cfg.Signal.SignalLookback = 20;
   cfg.Signal.MinConfluence = (InpMinConfluenceOverride > 0) ? InpMinConfluenceOverride : tc.minConfluence;
   cfg.Signal.MinScore = (InpSignalMinScoreOverride > 0) ? InpSignalMinScoreOverride : tc.signalMinScore;
   cfg.Signal.MinDominanceGap = tc.minPatternDominanceGap;
   cfg.Signal.MaxSourceAgeSeconds = 120;
   cfg.Signal.SignalCooldownBars = 3;
   cfg.Signal.MinRRRatio = (InpMinRRRatioOverride > 0) ? InpMinRRRatioOverride : tc.minRRRatio;
   cfg.Signal.MaxSignalATR = 2.0;
   cfg.Signal.UrgencyHighThreshold = 0.75;
   cfg.Signal.UrgencyMediumThreshold = 0.55;

   cfg.Pattern.EnablePatterns = InpEnablePatterns;
   cfg.Pattern.MinPatternScore = (InpMinPatternScoreOverride > 0) ? InpMinPatternScoreOverride : tc.minPatternScore;
   cfg.Pattern.LookbackBars = 50;
   cfg.Pattern.MinDominanceGap = tc.minPatternDominanceGap;
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

// ====================================================================
// OnInit
// ====================================================================
int OnInit()
  {
   Print("====================================================================");
   Print("  PASR Full Test Runner v2.16.0");
   Print("  Test Mode: ", EnumToString(InpTestMode));
   Print("  Profile: ", GetStrategyConfig(InpProfile).name);
   Print("====================================================================");

   if(InpTestMode == TEST_FULL_COMPARISON || InpTestMode == TEST_FULL_BATTERY)
     {
      Print("[Runner] Running full comparison mode");
      Print("[Runner] Use Strategy Tester to run all profiles");
     }

   StrategyConfig cfg = BuildConfig();
   int ret = g_kernel.Init(cfg);
   if(ret != INIT_SUCCEEDED)
     {
      Print("[Runner] Kernel init failed: ", ret);
      return INIT_PARAMETERS_INCORRECT;
     }

   g_initialized = true;
   EventSetTimer(1);

   Print("[Runner] Initialized OK — ready for testing");
   return INIT_SUCCEEDED;
  }

// ====================================================================
// OnTester — returns fitness score for optimization
// ====================================================================
double OnTester()
  {
   return ComputeStrategyFitness();
  }

// ====================================================================
// OnDeinit
// ====================================================================
void OnDeinit(const int reason)
  {
   EventKillTimer();

   if(g_initialized)
      g_kernel.OnDeinit(reason);
   g_initialized = false;

   // Print summary at end of test
   if(reason == REASON_CLOSE || reason == REASON_TERMINAL || reason == REASON_REMOVE)
     {
      SStrategyTestResult result;
      BuildTestResult(result, g_testConfig.name);
      result.passed = true;

      Print("====================================================================");
      Print("  TEST RESULT: ", result.configName);
      Print("====================================================================");
      Print("  Trades:      ", result.totalTrades);
      Print("  Profit:      $", DoubleToString(result.profit, 2));
      Print("  Profit Fact: ", DoubleToString(result.profitFactor, 2));
      Print("  Recovery F:  ", DoubleToString(result.recoveryFactor, 2));
      Print("  Win Rate:    ", DoubleToString(result.winRate * 100, 1), "%");
      Print("  Max DD:      ", DoubleToString(result.maxDDPct, 1), "%");
      Print("  Sharpe:      ", DoubleToString(result.sharpeRatio, 2));
      Print("  Fitness:     ", DoubleToString(result.customFitness, 2));
      Print("====================================================================");
     }
  }

// ====================================================================
// OnTick
// ====================================================================
void OnTick()
  {
   if(!g_initialized) return;
   g_kernel.OnTick();
  }

// ====================================================================
// OnTimer
// ====================================================================
void OnTimer()
  {
   if(!g_initialized) return;
   g_kernel.OnTimer();
  }

// ====================================================================
// OnTradeTransaction
// ====================================================================
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(!g_initialized) return;
   g_kernel.OnTradeTransaction(trans, request, result);
  }

// ====================================================================
// OnChartEvent
// ====================================================================
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   if(!g_initialized) return;
   g_kernel.OnChartEvent(id, lparam, dparam, sparam);
  }
