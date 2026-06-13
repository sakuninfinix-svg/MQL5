//+------------------------------------------------------------------+
//| PASR_MODULAR.mq5                                                 |
//| Centralized Modular PASR Expert Advisor                          |
//+------------------------------------------------------------------+
#property strict
#include <PASR/Core/PASR.mqh>
#include <PASR/Central/PASRKernel.mqh>
#include <PASR/Central/ModuleNames.mqh>
#include <PASR/Central/ModuleRegistry.mqh>
#include <PASR/Central/ServiceLocator.mqh>

input bool InpDebugMode = true;
input bool InpEnableProfiling = true;
input int  InpTimerSeconds = 1;

input group "PASR Identity"
input long   InpMagicNumber = 123456;
input string InpEAName = "PASR_MODULAR";

input group "Risk"
input double InpLotSize = 0.01;
input double InpRiskPercent = 1.0;
input double InpSLMultiplier = 1.5;
input double InpTPMultiplier = 2.5;
input double InpMaxDailyLossPct = 3.0;
input double InpMaxDrawdownPct = 10.0;
input int    InpMaxOpenPositions = 3;
input int    InpMaxConsecLoss = 5;
input bool   InpUseBreakEven = true;
input double InpBreakEvenATRMult = 1.0;
input bool   InpUseTrailingStop = false;
input double InpTrailATRMult = 1.0;
input bool   InpRecoveryEnabled = true;
input int    InpMaxRecoveryAttempts = 3;
input int    InpRecoveryCooldownBars = 5;
input double InpPartialClosePct = 0.5;
input int    InpMaxTradeDurationDays = 0;

input group "Market"
input int    InpATRPeriod = 14;
input int    InpADXPeriod = 14;
input double InpADXTrendThreshold = 25.0;
input double InpSpreadFilterPips = 3.0;
input int    InpSessionStartHour = 0;
input int    InpSessionEndHour = 23;
input bool   InpFilterNewsTime = false;
input int    InpNewsBufferMinutes = 30;

input group "AI"
input bool   InpEnableAI = false;
input double InpAIMinConfidence = 0.60;
input double InpAILearningRate = 0.0003;       // was 0.001 — reduced to prevent online overfitting
input int    InpAITrainIntervalBars = 5;
input int    InpAIReplayBufferSize = 512;
input int    InpAIMinibatchSize = 32;
input bool   InpAIPersistWeights = true;
input string InpAIModelFileName = "PASR_gbr_m0.bin";
input bool   InpAIEnableOnnx = false;
input string InpAIModelOnnxFileName = "PASR_sequence.onnx";

input group "AI Regime Thresholds"
input double InpAITrendEntryThreshold = 0.60;
input double InpAITrendRiskMultiplier = 1.20;
input double InpAIRangeEntryThreshold = 0.65;
input double InpAIRangeRiskMultiplier = 1.10;  // was 1.30 — ranging market is noisy, reduce risk
input double InpAIVolatileEntryThreshold = 0.85;
input double InpAIVolatileRiskMultiplier = 0.90;
input double InpAIConservativeEntryThreshold = 0.95;
input double InpAIConservativeRiskMultiplier = 0.10;
input double InpAIScalpEntryThreshold = 0.70;
input double InpAIScalpRiskMultiplier = 1.00;

input group "AI Decision Rules"
input double InpAIMinExpectedR = 0.50;                  // was 0.35 — below 0.50 is net-negative after spread
input double InpAIMaxFailureProbability = 0.55;         // was 0.72 — 72% fail rate made AI gate useless
input double InpAIStrongConfidenceBuffer = 0.10;
input double InpAIStrongConfidenceMin = 0.75;
input double InpAIStrongExpectedR = 1.20;
input double InpAIStrongMaxFailureProbability = 0.40;   // was 0.45 — tighter for "strong" signals
input double InpAIDriftFailureWeight = 0.35;
input double InpAIRegimeFailureWeight = 0.25;           // was 0.15 — regime mismatch is a primary loss cause
input double InpAIConfidenceRewardWeight = 2.00;
input double InpAIEdgeRewardWeight = 1.25;
input double InpAIRegimeRewardWeight = 0.75;
input double InpAIFailurePenaltyWeight = 1.40;
input double InpAIRiskFailureWeight = 0.45;

input group "Signal / MTF"
input bool   InpUseMTF = true;
input int    InpSignalLookback = 20;
input int    InpMinConfluence = 1;
input double InpSignalMinScore = 0.40;
input double InpSignalMinDominanceGap = 0.05;
input int    InpMaxSourceAgeSeconds = 120;
input int    InpSignalCooldownBars = 3;
input double InpMinRRRatio = 1.5;
input double InpMaxSignalATR = 2.0;
input double InpUrgencyHighThreshold = 0.75;
input double InpUrgencyMediumThreshold = 0.55;

input group "Pattern"
input bool   InpEnablePatterns = true;
input double InpMinPatternScore = 45.0;
input double InpMinPatternDominanceGap = 0.05;
input int    InpPatternLookbackBars = 50;
input double InpPinBarRatio = 2.0;
input double InpEngulfMultiplier = 1.1;
input bool   InpRequireConfirmation = false;

input group "Display"
input bool   InpShowDashboard = true;
input bool   InpShowSignalArrows = true;
input bool   InpEnableAlerts = false;
input bool   InpEnablePushNotify = false;
input int    InpFontSize = 9;

CPASRKernel g_kernel;
CPerformanceReport g_report;

struct EAState
  {
   bool     initialized;
   datetime last_tick;
   void Reset()
     {
      initialized = false;
      last_tick = 0;
     }
  };

EAState g_state;

#ifdef PASR_QA_BUILD
#include <PASR/QA/QAStressTest.mqh>
CQAStressTest g_qa;
#endif

StrategyConfig BuildConfigFromInputs()
  {
   StrategyConfig cfg;

   cfg.EAName = InpEAName;
   cfg.Version = "2.16.0";
   cfg.MagicNumber = InpMagicNumber;

   cfg.Risk.LotSize             = InpLotSize;
   cfg.Risk.RiskPercent         = InpRiskPercent;
   cfg.Risk.SLMultiplier        = InpSLMultiplier;
   cfg.Risk.TPMultiplier        = InpTPMultiplier;
   cfg.Risk.MaxDailyLossPct     = InpMaxDailyLossPct;
   cfg.Risk.MaxDrawdownPct      = InpMaxDrawdownPct;
   cfg.Risk.MaxOpenPositions    = InpMaxOpenPositions;
   cfg.Risk.MaxConsecLoss       = InpMaxConsecLoss;
   cfg.Risk.UseBreakEven        = InpUseBreakEven;
   cfg.Risk.BreakEvenATRMult    = InpBreakEvenATRMult;
   cfg.Risk.UseTrailingStop     = InpUseTrailingStop;
   cfg.Risk.TrailATRMult        = InpTrailATRMult;
   cfg.Risk.RecoveryEnabled     = InpRecoveryEnabled;
   cfg.Risk.MaxRecoveryAttempts = InpMaxRecoveryAttempts;
   cfg.Risk.RecoveryCooldownBars= InpRecoveryCooldownBars;
   cfg.Risk.PartialClosePct     = InpPartialClosePct;
   cfg.Risk.MaxTradeDurationDays= InpMaxTradeDurationDays;

   cfg.Market.ATRPeriod            = InpATRPeriod;
   cfg.Market.ADXPeriod            = InpADXPeriod;
   cfg.Market.ADXTrendThreshold    = InpADXTrendThreshold;
   cfg.Market.SpreadFilterPips     = InpSpreadFilterPips;
   cfg.Market.SessionStartHour     = InpSessionStartHour;
   cfg.Market.SessionEndHour       = InpSessionEndHour;
   cfg.Market.FilterNewsTime       = InpFilterNewsTime;
   cfg.Market.NewsBufferMinutes    = InpNewsBufferMinutes;

   cfg.AI.EnableAI           = InpEnableAI;
   cfg.AI.MinConfidence      = InpAIMinConfidence;
   cfg.AI.LearningRate       = InpAILearningRate;
   cfg.AI.TrainIntervalBars  = InpAITrainIntervalBars;
   cfg.AI.ReplayBufferSize   = InpAIReplayBufferSize;
   cfg.AI.MinibatchSize      = InpAIMinibatchSize;
   cfg.AI.PersistWeights     = InpAIPersistWeights;
   cfg.AI.ModelFileName      = InpAIModelFileName;
   cfg.AI.EnableOnnx         = InpAIEnableOnnx;
   cfg.AI.OnnxModelFileName  = InpAIModelOnnxFileName;

   cfg.AI.TrendEntryThreshold        = InpAITrendEntryThreshold;
   cfg.AI.TrendRiskMultiplier        = InpAITrendRiskMultiplier;
   cfg.AI.RangeEntryThreshold        = InpAIRangeEntryThreshold;
   cfg.AI.RangeRiskMultiplier        = InpAIRangeRiskMultiplier;
   cfg.AI.VolatileEntryThreshold     = InpAIVolatileEntryThreshold;
   cfg.AI.VolatileRiskMultiplier     = InpAIVolatileRiskMultiplier;
   cfg.AI.ConservativeEntryThreshold = InpAIConservativeEntryThreshold;
   cfg.AI.ConservativeRiskMultiplier = InpAIConservativeRiskMultiplier;
   cfg.AI.ScalpEntryThreshold        = InpAIScalpEntryThreshold;
   cfg.AI.ScalpRiskMultiplier        = InpAIScalpRiskMultiplier;

   cfg.AI.MinExpectedR                  = InpAIMinExpectedR;
   cfg.AI.MaxFailureProbability         = InpAIMaxFailureProbability;
   cfg.AI.StrongConfidenceBuffer        = InpAIStrongConfidenceBuffer;
   cfg.AI.StrongConfidenceMin           = InpAIStrongConfidenceMin;
   cfg.AI.StrongExpectedR               = InpAIStrongExpectedR;
   cfg.AI.StrongMaxFailureProbability   = InpAIStrongMaxFailureProbability;
   cfg.AI.DriftFailureWeight            = InpAIDriftFailureWeight;
   cfg.AI.RegimeFailureWeight           = InpAIRegimeFailureWeight;
   cfg.AI.ConfidenceRewardWeight        = InpAIConfidenceRewardWeight;
   cfg.AI.EdgeRewardWeight              = InpAIEdgeRewardWeight;
   cfg.AI.RegimeRewardWeight            = InpAIRegimeRewardWeight;
   cfg.AI.FailurePenaltyWeight          = InpAIFailurePenaltyWeight;
   cfg.AI.RiskFailureWeight             = InpAIRiskFailureWeight;

   cfg.Signal.UseMTF              = InpUseMTF;
   cfg.Signal.SignalLookback      = InpSignalLookback;
   cfg.Signal.MinConfluence       = InpMinConfluence;
   cfg.Signal.MinScore            = InpSignalMinScore;
   cfg.Signal.MinDominanceGap     = InpSignalMinDominanceGap;
   cfg.Signal.MaxSourceAgeSeconds = InpMaxSourceAgeSeconds;
   cfg.Signal.SignalCooldownBars  = InpSignalCooldownBars;
   cfg.Signal.MinRRRatio          = InpMinRRRatio;
   cfg.Signal.MaxSignalATR        = InpMaxSignalATR;
   cfg.Signal.UrgencyHighThreshold= InpUrgencyHighThreshold;
   cfg.Signal.UrgencyMediumThreshold = InpUrgencyMediumThreshold;

   cfg.Pattern.EnablePatterns = InpEnablePatterns;
   cfg.Pattern.MinPatternScore = InpMinPatternScore;
   cfg.Pattern.LookbackBars = InpPatternLookbackBars;

   cfg.Pattern.MinDominanceGap  = InpMinPatternDominanceGap;
   cfg.Pattern.PinBarRatio      = InpPinBarRatio;
   cfg.Pattern.EngulfMultiplier = InpEngulfMultiplier;
   cfg.Pattern.RequireConfirmation = InpRequireConfirmation;

   cfg.Display.ShowDashboard    = InpShowDashboard;
   cfg.Display.ShowSignalArrows = InpShowSignalArrows;
   cfg.Display.EnableAlerts     = InpEnableAlerts;
   cfg.Display.EnablePushNotify = InpEnablePushNotify;
   cfg.Display.FontSize         = InpFontSize;

   return cfg;
  }

bool ValidateConfig(const StrategyConfig &cfg)
  {
   if(cfg.Risk.LotSize <= 0.0)
     { Print("[Config] Invalid LotSize"); return false; }
   if(cfg.Risk.MaxDailyLossPct <= 0.0 || cfg.Risk.MaxDailyLossPct > 100.0)
     { Print("[Config] Invalid MaxDailyLossPct"); return false; }
   if(cfg.Risk.MaxDrawdownPct <= 0.0 || cfg.Risk.MaxDrawdownPct > 100.0)
     { Print("[Config] Invalid MaxDrawdownPct"); return false; }
   return true;
  }

void ExportBacktestReport()
  {
   CPipelineEngine *pipeline = g_kernel.Pipeline();
   if(pipeline == NULL) return;
   CJournalManager *journal = g_kernel.Services().Journal();
   if(journal == NULL) return;

   g_report.SetJournal(journal);
   g_report.SetFilePrefix(InpEAName);
   g_report.ExportHTML();
  }

double BuildTesterFitness()
  {
    double profit           = TesterStatistics(STAT_PROFIT);
    double profitFactor     = TesterStatistics(STAT_PROFIT_FACTOR);
    double recoveryFactor   = TesterStatistics(STAT_RECOVERY_FACTOR);
    double expectedPayoff   = TesterStatistics(STAT_EXPECTED_PAYOFF);
    int    trades           = (int)TesterStatistics(STAT_TRADES);
    double winTrades        = TesterStatistics(STAT_PROFIT_TRADES);
    double winRate          = (trades > 0) ? (winTrades / trades) : 0.0;
    double equityDrawdownPct= TesterStatistics(STAT_EQUITY_DD_RELATIVE);
    double sharpeRatio      = TesterStatistics(STAT_SHARPE_RATIO);

   if(trades < 10)
      return -1000.0;
   if(profit < 0.0)
      return -1000.0 - MathAbs(profit) - equityDrawdownPct;

   profit = MathMin(1000000.0, profit);
   profitFactor     = MathMin(100.0, MathMax(0.0, profitFactor));
   recoveryFactor   = MathMin(100.0, MathMax(0.0, recoveryFactor));
   expectedPayoff   = MathMin(1000.0, MathMax(0.0, expectedPayoff));
   equityDrawdownPct= MathMin(100.0, MathMax(0.0, equityDrawdownPct));
   sharpeRatio      = MathMax(-5.0, MathMin(5.0, sharpeRatio));

   double score = 0.0;
   score += MathLog(1.0 + profit);
   score += 2.0 * MathLog(1.0 + profitFactor);
   score += 1.5 * MathLog(1.0 + recoveryFactor);
   score += MathLog(1.0 + expectedPayoff);
   score += 0.5 * winRate;
   score += 0.25 * sharpeRatio;
   score += MathMin(2.0, (double)trades / 50.0);
   score -= 0.15 * equityDrawdownPct;

   PrintFormat("[Tester] trades=%d winRate=%.2f pf=%.2f rf=%.2f exp=%.2f dd=%.2f sharpe=%.2f score=%.3f",
               trades, winRate, profitFactor, recoveryFactor, expectedPayoff, equityDrawdownPct, sharpeRatio, score);
   return score;
  }

int OnInit()
  {
   g_state.Reset();
   StrategyConfig cfg = BuildConfigFromInputs();
   if(!ValidateConfig(cfg))
      return INIT_FAILED;

   g_kernel.SetDebugMode(InpDebugMode);
   g_kernel.SetProfilingEnabled(InpEnableProfiling);
   int init = g_kernel.Init(cfg);
   if(init != INIT_SUCCEEDED) return init;
   EventSetTimer(MathMax(1, InpTimerSeconds));
#ifdef PASR_QA_BUILD
   g_qa.Init();
#endif
   g_state.initialized = true;
   return INIT_SUCCEEDED;
  }

double OnTester()
  {
   return BuildTesterFitness();
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(MQLInfoInteger(MQL_TESTER))
      ExportBacktestReport();
   g_kernel.OnDeinit(reason);
   g_state.Reset();
  }

void OnTick()
  {
   if(!g_state.initialized) return;
   g_state.last_tick = TimeCurrent();
#ifdef PASR_QA_BUILD
   CEventBus *bus = g_kernel.GetEventBus();
   CRiskManager *risk = g_kernel.GetRiskManager();
   if(bus != NULL && risk != NULL)
      g_qa.OnTick(_Symbol, bus, risk);
#endif
   g_kernel.OnTick();
  }

void OnTimer()
  {
   if(!g_state.initialized) return;
   g_kernel.OnTimer();
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(!g_state.initialized) return;
   g_kernel.OnTradeTransaction(trans, request, result);
  }

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   if(!g_state.initialized) return;
   g_kernel.OnChartEvent(id, lparam, dparam, sparam);
  }