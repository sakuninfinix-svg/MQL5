//+------------------------------------------------------------------+
//| PASR_MODULAR.mq5                                                 |
//| Centralized Modular PASR Expert Advisor                          |
//+------------------------------------------------------------------+
#property strict
#include <PASR/Core/PASR.mqh>

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
input double InpAILearningRate = 0.001;
input int    InpAITrainIntervalBars = 5;
input int    InpAIReplayBufferSize = 512;
input int    InpAIMinibatchSize = 32;
input bool   InpAIPersistWeights = true;
input string InpAIModelFileName = "PASR_weights.bin";
input bool   InpAIEnableOnnx = false;
input string InpAIModelOnnxFileName = "PASR_transformer.onnx";

input group "Pattern"
input bool   InpEnablePatterns = true;
input double InpMinPatternScore = 45.0;
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
   cfg.Version = "2.15.0";
   cfg.MagicNumber = InpMagicNumber;

   cfg.Risk.LotSize = InpLotSize;
   cfg.Risk.RiskPercent = InpRiskPercent;
   cfg.Risk.SLMultiplier = InpSLMultiplier;
   cfg.Risk.TPMultiplier = InpTPMultiplier;
   cfg.Risk.MaxDailyLossPct = InpMaxDailyLossPct;
   cfg.Risk.MaxDrawdownPct = InpMaxDrawdownPct;
   cfg.Risk.MaxOpenPositions = InpMaxOpenPositions;
   cfg.Risk.MaxConsecLoss = InpMaxConsecLoss;
   cfg.Risk.UseBreakEven = InpUseBreakEven;
   cfg.Risk.BreakEvenATRMult = InpBreakEvenATRMult;
   cfg.Risk.UseTrailingStop = InpUseTrailingStop;
   cfg.Risk.TrailATRMult = InpTrailATRMult;
   cfg.Risk.RecoveryEnabled = InpRecoveryEnabled;
   cfg.Risk.MaxRecoveryAttempts = InpMaxRecoveryAttempts;
   cfg.Risk.RecoveryCooldownBars = InpRecoveryCooldownBars;
   cfg.Risk.PartialClosePct = InpPartialClosePct;
   cfg.Risk.MaxTradeDurationDays = InpMaxTradeDurationDays;

   cfg.Market.ATRPeriod = InpATRPeriod;
   cfg.Market.ADXPeriod = InpADXPeriod;
   cfg.Market.ADXTrendThreshold = InpADXTrendThreshold;
   cfg.Market.SpreadFilterPips = InpSpreadFilterPips;
   cfg.Market.SessionStartHour = InpSessionStartHour;
   cfg.Market.SessionEndHour = InpSessionEndHour;
   cfg.Market.FilterNewsTime = InpFilterNewsTime;
   cfg.Market.NewsBufferMinutes = InpNewsBufferMinutes;

   cfg.AI.EnableAI = InpEnableAI;
   cfg.AI.MinConfidence = InpAIMinConfidence;
   cfg.AI.LearningRate = InpAILearningRate;
   cfg.AI.TrainIntervalBars = InpAITrainIntervalBars;
   cfg.AI.ReplayBufferSize = InpAIReplayBufferSize;
   cfg.AI.MinibatchSize = InpAIMinibatchSize;
   cfg.AI.PersistWeights = InpAIPersistWeights;
   cfg.AI.ModelFileName = InpAIModelFileName;
   cfg.AI.EnableOnnx = InpAIEnableOnnx;
   cfg.AI.OnnxModelFileName = InpAIModelOnnxFileName;

   cfg.Pattern.EnablePatterns = InpEnablePatterns;
   cfg.Pattern.MinPatternScore = InpMinPatternScore;
   cfg.Pattern.LookbackBars = InpPatternLookbackBars;
   cfg.Pattern.PinBarRatio = InpPinBarRatio;
   cfg.Pattern.EngulfMultiplier = InpEngulfMultiplier;
   cfg.Pattern.RequireConfirmation = InpRequireConfirmation;

   cfg.Display.ShowDashboard = InpShowDashboard;
   cfg.Display.ShowSignalArrows = InpShowSignalArrows;
   cfg.Display.EnableAlerts = InpEnableAlerts;
   cfg.Display.EnablePushNotify = InpEnablePushNotify;
   cfg.Display.FontSize = InpFontSize;

   return cfg;
  }

bool ValidateConfig(const StrategyConfig &cfg)
  {
   string errors[];
   if(!CConfigValidator::Validate(cfg, errors))
     {
      Print("[PASR_MODULAR] Strategy config invalid:");
      CConfigValidator::PrintErrors(errors);
      return false;
     }
   return true;
  }

double BuildTesterFitness()
  {
   const int minTrades = 20;
   int trades = (int)TesterStatistics(STAT_TRADES);
   double profit = TesterStatistics(STAT_PROFIT);
   double profitFactor = TesterStatistics(STAT_PROFIT_FACTOR);
   double recoveryFactor = TesterStatistics(STAT_RECOVERY_FACTOR);
   double expectedPayoff = TesterStatistics(STAT_EXPECTED_PAYOFF);
   double equityDrawdownPct = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double sharpeRatio = TesterStatistics(STAT_SHARPE_RATIO);

   if(trades < minTrades)
      return -1000.0 + (double)trades;

   if(profit <= 0.0)
      return -1000.0 - MathAbs(profit) - equityDrawdownPct;

   profit = MathMin(1000000.0, profit);
   profitFactor = MathMin(100.0, MathMax(0.0, profitFactor));
   recoveryFactor = MathMin(100.0, MathMax(0.0, recoveryFactor));
   expectedPayoff = MathMin(1000.0, MathMax(0.0, expectedPayoff));
   equityDrawdownPct = MathMin(100.0, MathMax(0.0, equityDrawdownPct));
   sharpeRatio = MathMax(-5.0, MathMin(5.0, sharpeRatio));

   double score = 0.0;
   score += MathLog(1.0 + profit);
   score += 2.0 * MathLog(1.0 + profitFactor);
   score += 1.5 * MathLog(1.0 + recoveryFactor);
   score += MathLog(1.0 + expectedPayoff);
   score += 0.25 * sharpeRatio;
   score += MathMin(2.0, (double)trades / 50.0);
   score -= 0.15 * equityDrawdownPct;
   return score;
  }

int OnInit()
  {
   g_state.Reset();
   StrategyConfig cfg = BuildConfigFromInputs();
   if(!ValidateConfig(cfg))
      return INIT_PARAMETERS_INCORRECT;

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
   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      CDashboardManager *dash = g_kernel.GetDashboard();
      if(dash != NULL) dash.OnChartEvent(id, lparam, dparam, sparam);
     }
  }
