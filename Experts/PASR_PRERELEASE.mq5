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
#include <PASR/AI/AIRetrainTrigger.mqh>
#include <PASR/AI/GBRInference.mqh>
#include <PASR/Analysis/MTFBiasEngine.mqh>
#include <PASR/Signal/MTFHTFBiasSource.mqh>

input bool InpDebugMode = true; //Mode Debug
input bool InpEnableProfiling = true;
input int  InpTimerSeconds = 1;

input group "PASR Identity"
input long   InpMagicNumber = 123456; //Magic Number
input string InpEAName = "PASR_MODULAR";

input group "Risk"
input double InpLotSize = 0.01; //Lot Size
input bool   InpUseAutoLot = false; // Gunakan Auto Lot (aktifkan untuk menghitung lot otomatis berdasarkan risiko)
input double InpAutoLotMin = 0.01; // Minimal Lot Size (untuk akun kecil)
input double InpAutoLotMax = 10.0; // Maksimal Lot Size (untuk akun besar)
input double InpRiskPercent = 1.0; //Resiko per Trade (%)
input double InpSLMultiplier = 1.5; // SL x ATR
input double InpTPMultiplier = 2.5; //TP x ATR
input double InpMaxDailyLossPct = 3.0; // Max Loss perhari (%)
input double InpMaxDrawdownPct = 10.0; // Max Drawdown perhari (%)
input int    InpMaxOpenPositions = 3; // Max Open Posisi
input int    InpMaxConsecLoss = 5;
input bool   InpUseBreakEven = true;
input double InpBreakEvenATRMult = 1.0;
input bool   InpUseTrailingStop = false; //Trailing Stop
input double InpTrailATRMult = 1.0; // Jarak Trailing xATR
input double InpSLHeadroomPips = 0.0; // Headroom tambahan untuk Stop Loss (pips)
input double InpTPHeadroomPips = 0.0; // Headroom tambahan untuk Take Profit (pips)
input double InpSLHeadroomATRMult = 0.0; // Dynamic SL headroom (x ATR, 0=off)
input double InpTPHeadroomATRMult = 0.0; // Dynamic TP headroom (x ATR, 0=off)
input bool   InpRecoveryEnabled = true; // Recovery Mode
input int    InpMaxRecoveryAttempts = 3;
input int    InpRecoveryCooldownBars = 5;
input double InpPartialClosePct = 0.5; //Parsial Close (%)
input int    InpMaxTradeDurationDays = 0; //Lama Durasi Maksimal (Hari)

input group "Market"
input int    InpATRPeriod = 14; //Periode ATR
input int    InpADXPeriod = 14; // Periode ADX
input double InpADXTrendThreshold = 25.0;
input double InpSpreadFilterPips = 3.0;
input string InpSessionSunday    = "00:00-00:00";   // Minggu (HH:MM-HH:MM)
input string InpSessionMonday    = "00:00-23:00";   // Senin
input string InpSessionTuesday   = "00:00-23:00";   // Selasa
input string InpSessionWednesday = "00:00-23:00";   // Rabu
input string InpSessionThursday  = "00:00-23:00";   // Kamis
input string InpSessionFriday    = "00:00-15:00";   // Jumat
input string InpSessionSaturday  = "00:00-00:00";   // Sabtu
input bool   InpFilterNewsTime = true; //New Filter
input int    InpNewsBufferMinutes = 30; // Lama Filter News (Menit)

input group "AI"
input bool   InpEnableAI = false; // Artificial Intelligence (ENABLED BY DEFAULT IS RISKY: model must be present + validated first)
input double InpAIMinConfidence = 0.60; // AI Min Confidence
input double InpAILearningRate = 0.0003;       // AI Learning Rate
input int    InpAITrainIntervalBars = 5;
input int    InpAIReplayBufferSize = 512;
input int    InpAIMinibatchSize = 32;
input bool   InpAIPersistWeights = false;
input string InpAIModelFileName = "PASR_mlp_m0.bin";
input bool   InpAIEnableOnnx = false; // AI ONNX model
input string InpAIModelOnnxFileName = "PASR_sequence.onnx";

input group "GBR Configuration"
input bool   InpEnableGBR = false;             // Enable GBR for MTF (keep OFF for live; experimental)
input int    InpGBRN_estimators = 100;         // Number of trees (reduced from 150: less overfit risk)
input double InpGBRLearning_rate = 0.05;       // Learning rate (0.01-0.1 optimal)
input int    InpGBRMax_depth = 3;              // Tree depth (REDUCED from 4: anti-overfit)
input double InpGBRMin_samples_split = 0.05;   // Min samples split (raised from 3% to 5%: more conservative)
input double InpGBRMin_samples_leaf = 0.025;   // Min samples leaf (raised from 1.5% to 2.5%)
input double InpGBRSubsample = 0.8;           // Stochastic sampling (0.7-0.9)
input double InpGBRColsample_bytree = 0.7;     // Feature sampling (0.6-0.8)
input double InpGBRReg_alpha = 0.10;           // L1 regularization (raised from 0.05: more regularization)
input double InpGBRReg_lambda = 1.0;          // L2 regularization (raised from 0.8)
input double InpGBRGamma = 0.10;               // Min loss reduction (raised from 0.05)
input string InpGBRModelPath = "PASR_gbr_m0.onnx"; // GBR ONNX model path

input group "AI Regime Thresholds"
input double InpAITrendEntryThreshold = 0.65;     // RAISED from 0.60 (more selective)
input double InpAITrendRiskMultiplier = 1.10;     // LOWERED from 1.20 (less risk on AI-driven trend)
input double InpAIRangeEntryThreshold = 0.70;     // RAISED from 0.65
input double InpAIRangeRiskMultiplier = 1.00;     // LOWERED from 1.10
input double InpAIVolatileEntryThreshold = 0.90;  // RAISED from 0.85 (more selective)
input double InpAIVolatileRiskMultiplier = 0.80;
input double InpAIConservativeEntryThreshold = 0.95;
input double InpAIConservativeRiskMultiplier = 0.10;
input double InpAIScalpEntryThreshold = 0.75;     // RAISED from 0.70
input double InpAIScalpRiskMultiplier = 0.90;     // LOWERED from 1.00

input group "AI Decision Rules"
input double InpAIMinExpectedR = 0.60;
input double InpAIMaxFailureProbability = 0.45;
input double InpAIStrongConfidenceBuffer = 0.15;
input double InpAIStrongConfidenceMin = 0.80;
input double InpAIStrongExpectedR = 1.40;
input double InpAIStrongMaxFailureProbability = 0.35;
input double InpAIDriftFailureWeight = 0.50;
input double InpAIRegimeFailureWeight = 0.40;
input double InpAIConfidenceRewardWeight = 1.20;
input double InpAIEdgeRewardWeight = 1.00;
input double InpAIRegimeRewardWeight = 0.50;
input double InpAIFailurePenaltyWeight = 2.00;
input double InpAIRiskFailureWeight = 0.65;

input group "Signal / MTF"
input bool   InpUseMTF = true; //Multi Time Frame
input int    InpSignalLookback = 20;
input int    InpMinConfluence = 1;
input double InpSignalMinScore = 0.40; //Minimal Skor Sinyal
input double InpSignalMinDominanceGap = 0.05; //
input int    InpMaxSourceAgeSeconds = 120;
input int    InpSignalCooldownBars = 3;
input double InpMinRRRatio = 1.5;
input double InpMaxSignalATR = 2.0;
input double InpUrgencyHighThreshold = 0.75;
input double InpUrgencyMediumThreshold = 0.55;

input group "MTF Hard Filter"
input bool             InpMTFHTFEnabled     = true;                  // HTF bias gate aktif
input ENUM_TIMEFRAMES  InpMTFHTFPeriod      = PERIOD_H4;             // HTF time-frame
input ENUM_TIMEFRAMES  InpMTFMidPeriod      = PERIOD_H1;             // Mid time-frame
input int              InpMTFSequenceBars   = 3;                     // Bars for higher-high/lower-low scan
input int              InpMTFBodyBars       = 3;                     // Bars for body persistence
input int              InpMTFATRPeriod      = 14;                    // ATR period (HTF+Mid handles)
input double           InpMTFStrengthMin    = 0.20;                  // Min body/ATR ratio (di bawah = skip veto)
input double           InpMTFVetoConfidence = 0.40;                  // Confidence veto source
input bool             InpMTFLogOnly        = false;                 // Log-only, tidak veto
input double           InpMTFBlockThreshold = 0.20;                  // |composite| min untuk block

input group "Pattern"
input bool   InpEnablePatterns = true; //Enable Pattern
input double InpMinPatternScore = 45.0; // Min Pattern Score
input double InpMinPatternDominanceGap = 0.05; //Min Pattern Dominance Gap
input int    InpPatternLookbackBars = 50; //Pattern Lookback Bars
input double InpPinBarRatio = 2.0; // Pinbar Multiplier
input double InpEngulfMultiplier = 1.1; // Engulfing Multiplier
input bool   InpRequireConfirmation = false; //Require Confirmation

input group "Auto-Retrain"
input bool   InpAutoRetrainEnabled = false; // KEEP OFF for live: online retraining causes concept drift
input int    InpAutoRetrainTradeThreshold = 500; // Online Learning Threshold (raised from 200 to retrain less frequently)
input string InpAutoRetrainWeightsFile = "PASR_mlp_m0.bin"; //Online Learning Otomatis

input group "Display"
input bool   InpShowDashboard = true; // Lihat DashBoard
input bool   InpShowSignalArrows = true;
input bool   InpEnableAlerts = false; //Alerts
input bool   InpEnablePushNotify = false; //Notifikasi
input int    InpFontSize = 9; //Ukuran Font

CPASRKernel g_kernel;
CPerformanceReport g_report;
CAIRetrainTrigger g_retrain;
CGBRInference g_gbr;
CMTFBiasEngine   g_mtfEngine;
CMTFHTFBiasSource g_mtfSource;

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

//+------------------------------------------------------------------+
//| Parse "HH:MM-HH:MM" into a DaySession.                           |
//| Empty string or invalid format → Active=false                    |
//+------------------------------------------------------------------+
DaySession ParseSessionString(const string s)
  {
   DaySession ds;
   ds.Active = false;
   ds.StartMinutes = 0;
   ds.EndMinutes = 0;
   if(StringLen(s) < 11) return ds;
   int dashPos = StringFind(s, "-");
   if(dashPos < 0) return ds;
   string startStr = StringSubstr(s, 0, dashPos);
   string endStr   = StringSubstr(s, dashPos + 1);
   int sColon = StringFind(startStr, ":");
   int eColon = StringFind(endStr, ":");
   if(sColon < 0 || eColon < 0) return ds;
   int sH = (int)StringToInteger(StringSubstr(startStr, 0, sColon));
   int sM = (int)StringToInteger(StringSubstr(startStr, sColon + 1));
   int eH = (int)StringToInteger(StringSubstr(endStr, 0, eColon));
   int eM = (int)StringToInteger(StringSubstr(endStr, eColon + 1));
   if(sH < 0 || sH > 23 || sM < 0 || sM > 59) return ds;
   if(eH < 0 || eH > 23 || eM < 0 || eM > 59) return ds;
   ds.StartMinutes = sH * 60 + sM;
   ds.EndMinutes   = eH * 60 + eM;
   ds.Active       = true;
   return ds;
  }

StrategyConfig BuildConfigFromInputs()
  {
   StrategyConfig cfg;

   cfg.EAName = InpEAName;
   cfg.Version = "2.16.0";
   cfg.MagicNumber = InpMagicNumber;

   cfg.Risk.LotSize             = InpLotSize;
   cfg.Risk.UseAutoLot          = InpUseAutoLot;
   cfg.Risk.AutoLotMin          = InpAutoLotMin;
   cfg.Risk.AutoLotMax          = InpAutoLotMax;
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
   cfg.Risk.SLHeadroomPips      = InpSLHeadroomPips;
   cfg.Risk.TPHeadroomPips      = InpTPHeadroomPips;
   cfg.Risk.SLHeadroomATRMult   = InpSLHeadroomATRMult;
   cfg.Risk.TPHeadroomATRMult   = InpTPHeadroomATRMult;
   cfg.Risk.RecoveryEnabled     = InpRecoveryEnabled;
   cfg.Risk.MaxRecoveryAttempts = InpMaxRecoveryAttempts;
   cfg.Risk.RecoveryCooldownBars= InpRecoveryCooldownBars;
   cfg.Risk.PartialClosePct     = InpPartialClosePct;
   cfg.Risk.MaxTradeDurationDays= InpMaxTradeDurationDays;

   cfg.Market.ATRPeriod            = InpATRPeriod;
   cfg.Market.ADXPeriod            = InpADXPeriod;
   cfg.Market.ADXTrendThreshold    = InpADXTrendThreshold;
   cfg.Market.SpreadFilterPips     = InpSpreadFilterPips;
   cfg.Market.Sessions[0]          = ParseSessionString(InpSessionSunday);
   cfg.Market.Sessions[1]          = ParseSessionString(InpSessionMonday);
   cfg.Market.Sessions[2]          = ParseSessionString(InpSessionTuesday);
   cfg.Market.Sessions[3]          = ParseSessionString(InpSessionWednesday);
   cfg.Market.Sessions[4]          = ParseSessionString(InpSessionThursday);
   cfg.Market.Sessions[5]          = ParseSessionString(InpSessionFriday);
   cfg.Market.Sessions[6]          = ParseSessionString(InpSessionSaturday);
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

   // GBR Configuration
   cfg.AI.EnableGBR                    = InpEnableGBR;
   cfg.AI.GBRN_estimators               = InpGBRN_estimators;
   cfg.AI.GBRLearning_rate             = InpGBRLearning_rate;
   cfg.AI.GBRMax_depth                 = InpGBRMax_depth;
   cfg.AI.GBRMin_samples_split         = InpGBRMin_samples_split;
   cfg.AI.GBRMin_samples_leaf          = InpGBRMin_samples_leaf;
   cfg.AI.GBRSubsample                 = InpGBRSubsample;
   cfg.AI.GBRColsample_bytree          = InpGBRColsample_bytree;
   cfg.AI.GBRReg_alpha                 = InpGBRReg_alpha;
   cfg.AI.GBRReg_lambda                = InpGBRReg_lambda;
   cfg.AI.GBRGamma                     = InpGBRGamma;
   cfg.AI.GBRModelPath                 = InpGBRModelPath;

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
   CServiceLocator *services = g_kernel.Services();
   if(services == NULL) return;
   CJournalManager *journal = services.Journal();
   if(journal == NULL) return;

   g_report.SetJournal(journal);
   g_report.SetFilePrefix(InpEAName);
   g_report.ExportHTML();
  }

#ifdef PASR_ENABLE_TESTER_FITNESS
double BuildTesterFitness()
  {
   // DEAD CODE: kept for compatibility with old OptimizationCriterion references.
   // Live OnTester() handles fitness computation inline (TesterStatistics is valid there only).
   // Returning a fixed value avoids the runtime error 511 pointer-cast that occurred when this
   // function was called by the genetic optimizer from a thread that did not own the tester
   // state. See OnTester() above for the actual fitness computation.
   return 0.0;
  }
#endif

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

   if(InpAutoRetrainEnabled)
     {
      g_retrain.Init(InpAutoRetrainWeightsFile, InpAutoRetrainTradeThreshold);
      Print("[PASR] Auto-retrain trigger enabled");
     }

   // Initialize GBR if enabled
   if(InpEnableGBR)
     {
      SGBRConfig gbr_cfg;
      gbr_cfg.n_estimators        = InpGBRN_estimators;
      gbr_cfg.learning_rate       = InpGBRLearning_rate;
      gbr_cfg.max_depth           = InpGBRMax_depth;
      gbr_cfg.min_samples_split   = InpGBRMin_samples_split;
      gbr_cfg.min_samples_leaf    = InpGBRMin_samples_leaf;
      gbr_cfg.subsample           = InpGBRSubsample;
      gbr_cfg.colsample_bytree    = InpGBRColsample_bytree;
      gbr_cfg.reg_alpha           = InpGBRReg_alpha;
      gbr_cfg.reg_lambda          = InpGBRReg_lambda;
      gbr_cfg.gamma               = InpGBRGamma;

      g_gbr.SetConfig(gbr_cfg);

      // Try to load GBR model from ONNX file
      if(InpGBRModelPath != "")
        {
         if(g_gbr.LoadModel(InpGBRModelPath))
           {
            PrintFormat("[PASR] GBR model loaded successfully from %s", InpGBRModelPath);
           }
         else
           {
            PrintFormat("[PASR] GBR model load failed from %s, using random initialization", InpGBRModelPath);
           }
        }
      else
        {
         Print("[PASR] GBR enabled but no model path specified, using random initialization");
        }
     }

  // Init MTF HTF bias engine and register as VETO source
  if(InpUseMTF && InpMTFHTFEnabled)
    {
     SMTFBiasConfig mtf_cfg;
     mtf_cfg.enabled         = true;
     mtf_cfg.htfPeriod       = InpMTFHTFPeriod;
     mtf_cfg.midPeriod       = InpMTFMidPeriod;
     mtf_cfg.sequenceBars    = InpMTFSequenceBars;
     mtf_cfg.bodyBars        = InpMTFBodyBars;
     mtf_cfg.atrPeriod       = InpMTFATRPeriod;
     mtf_cfg.atrStrengthMin  = InpMTFStrengthMin;
     mtf_cfg.vetoConfidence  = InpMTFVetoConfidence;
     mtf_cfg.logOnly         = InpMTFLogOnly;
     if(g_mtfEngine.Init(mtf_cfg))
       {
        g_mtfSource.Bind(GetPointer(g_mtfEngine));
        CServiceLocator *svc = g_kernel.Services();
        if(svc != NULL)
          {
           CSignalManager *sig = svc.Signal();
           if(sig != NULL)
             {
              double w = -InpMTFVetoConfidence;
              if(w > 0.0) w = -w;
              if(sig.RegisterSource(GetPointer(g_mtfSource), w))
                 PrintFormat("[PASR] MTF HTF bias source registered (VETO w=%.2f thresh=%.2f)",
                             w, InpMTFBlockThreshold);
              else
                 Print("[PASR] MTF HTF bias source registration failed");
             }
          }
       }
     else
        Print("[PASR] MTF engine init failed; HTF filter disabled");
    }

   return INIT_SUCCEEDED;
  }

double PASRTesterFitness()
{
   // SAME DEAD-CODE: do not call BuildTesterFitness here either. Both functions
   // would crash TesterStatistics() when invoked from a non-tester thread.
   // OnTester() below is the canonical entrypoint used by the tester.
   return 0.0;
}

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(MQLInfoInteger(MQL_TESTER) != 0)
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
   if(InpAutoRetrainEnabled)
      g_retrain.Check();
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(!g_state.initialized) return;
   g_kernel.OnTradeTransaction(trans, request, result);
   if(InpAutoRetrainEnabled && trans.type == TRADE_TRANSACTION_DEAL_ADD)
      g_retrain.OnTradeClosed();
  }

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   if(!g_state.initialized) return;
   g_kernel.OnChartEvent(id, lparam, dparam, sparam);
  }
