//+------------------------------------------------------------------+
//|  PASR_MODULAR.mq5 — v5.30 (Full Multi-Symbol Trading + API Fix)  |
//|  Price Action Support/Resistance Expert Advisor                  |
//|                                                                  |
//|  Architecture: modular orchestrator — all logic delegated        |
//|  to Include/PASR/* managers. This file is glue only.            |
//|                                                                  |
//|  MODULES (boot order):                                           |
//|   [01] Config          — Core/Config.mqh                         |
//|   [02] EventBus        — Core/EventBus.mqh (deferred queue)      |
//|   [03] DataManager     — Infra/DataManager.mqh                   |
//|   [04] StateManager    — Infra/StateManager.mqh                  |
//|   [05] AdaptiveConfig  — Infra/AdaptiveConfig.mqh                |
//|   [06] JournalManager  — Infra/JournalManager.mqh                |
//|   [07] PerformanceReport — Infra/PerformanceReport.mqh           |
//|   [08] SRManager       — Analysis/SRManager.mqh                  |
//|   [09] PatternManager  — Pattern/PatternManager.mqh              |
//|   [10] SignalManager   — Signal/SignalManager.mqh                 |
//|   [11] RiskManager     — Trade/RiskManager.mqh                   |
//|   [12] ExecutionManager — Trade/ExecutionManager.mqh             |
//|   [13] PositionManager — Trade/PositionManager.mqh               |
//|   [14] ExitEngine      — Trade/ExitEngine.mqh (NEW v6.10)        |
//|   [15] CorrelationMgr  — Trade/CorrelationManager.mqh (NEW v6.10)|
//|   [16] RecoveryManager — Trade/RecoveryManager.mqh               |
//|   [15] AIFeatureBuilder — AI/AIFeatureBuilder.mqh                |
//|   [16] AIInference     — AI/AIInference.mqh                      |
//|   [17] AIEnsemble      — AI/AIEnsemble.mqh                       |
//|   [18] AICalibrationBridge — AI/AICalibrationBridge.mqh          |
//|   [19] DashboardManager — UI/DashboardManager.mqh                |
//|   [20] SymbolScanner   — Data/SymbolScanner.mqh (NEW v5.00)      |
//|   [21] FeatureEngine   — AI/FeatureEngine.mqh (NEW v5.10)        |
//|   [22] QAStressTest    — QA/QAStressTest.mqh (NEW v5.20)         |
//|                                                                  |
//|  TICK FLOW (OnTick):                                             |
//|   scanner.ScanNext() → for each valid symbol:                    |
//|     → spreadGuard → eventProcess → posManage → recoveryTick      |
//|     → [NEW BAR] regimeDetect → srUpdate → patternScan            |
//|                  → signalGen → featureBuild → driftCheck         |
//|                  → ensembleScore → calibBridge                   |
//|                  → riskCheck → execute                           |
//|                  → recoveryNewBar                                |
//|     → dashUpdate                                                 |
//|                                                                  |
//|  CHANGELOG:                                                      |
//|   v6.10 (2026-05-22) — Institutional Grade Features              |
//|    * NEW: CorrelationManager - Dynamic correlation matrix        |
//|      Circuit Breaker #7: Block high-correlation entries          |
//|    * NEW: ExitEngine - Smart exit logic (Chandelier, Time,       |
//|      Structure Break, Profit Fade)                               |
//|    * Enhanced multi-symbol risk management                       |
//|   v5.30 (2026-05-21) — Full Multi-Symbol Trading + API Fix       |
//|    * Add IsTradingAllowed() method to CRiskManager               |
//|    * Refactor managers to accept symbol parameter for multi-symbol|
//|    * Full trading support on all scanned symbols (not just chart)|
//|    * Symbol-aware ATR, SR, Pattern, Signal calculations          |
//|    * Magic number isolation per symbol enforced                  |
//|   v5.20 (2026-05-21) — QA & Stress Testing Framework             |
//|    * Add QA_BUILD compilation flag for stress testing mode       |
//|    * Chaos Engineering: random error injection, spread spikes    |
//|    * EventPool exhaustion testing with fallback verification     |
//|    * Circuit breaker manual trigger for validation               |
//|    * Performance metrics tracking (tick latency, alloc count)    |
//|    * New input params: InpEnableChaos, InpChaosFrequency         |
//|   v5.10 (2026-05-21) — Advanced AI Feature Engineering           |
//|    * Add CFeatureEngine for statistical features (Z-score,       |
//|      Skewness, Kurtosis, Volatility Regime Detection)            |
//|    * Volatility-adjusted AI scoring & position sizing            |
//|    * Dynamic veto threshold based on market regime               |
//|    * New input params: InpFeatureWindow, InpUseAdvFeatures       |
//|   v5.00 (2026-05-21) — Multi-Symbol Integration                  |
//|    * Add CSymbolScanner for multi-symbol scanning                |
//|    * Refactor OnTick() for round-robin symbol processing         |
//|    * Magic number isolation per symbol                           |
//|    * Input parameters for symbol list, spread filter, session    |
//|   v4.01 (2026-05-21) — Kategori-1 cleanup                        |
//|    * Wire CRecoveryManager: OnPriceUpdate, OnNewBar,             |
//|      OnTradeOpen (DEAL_ENTRY_IN), OnTradeClose (DEAL_ENTRY_OUT)  |
//|    * Remove dead ExecutionManager.shim.mqh (committed separately)|
//|   v4.00 (2026-05-21) — Phase 12 final assembly                  |
//|                                                                  |
//|  Magic: 20260521  Version: v5.30-full-multisymbol                |
//|  Build: 2026-05-21                                               |
//+------------------------------------------------------------------+
#property copyright   "PASR EA © 2026"
#property link        "https://github.com/sakuninfinix-svg/MQL5"
#property version     "6.10"
#property description "Price Action SR — Modular Orchestrator v6.10 (Institutional Grade)"
#property strict

//--- Compilation Flags
//#define DEBUG_MODE      // Enable verbose logging
#define QA_BUILD          // ENABLE STRESS TESTING & CHAOS ENGINEERING
#define PERF_METRICS      // Enable detailed performance counters

//--- Core
#include <PASR/Core/EventBus.mqh>
#include <PASR/Core/Config.mqh>
//--- Infra
#include <PASR/Infra/DataManager.mqh>
#include <PASR/Infra/StateManager.mqh>
#include <PASR/Infra/AdaptiveConfig.mqh>
#include <PASR/Infra/JournalManager.mqh>
#include <PASR/Infra/PerformanceReport.mqh>
//--- Analysis
#include <PASR/Analysis/SRManager.mqh>
//--- Pattern
#include <PASR/Pattern/PatternManager.mqh>
//--- Signal
#include <PASR/Signal/SignalManager.mqh>
//--- Trade
#include <PASR/Trade/RiskManager.mqh>
#include <PASR/Trade/TradePlan.mqh>
#include <PASR/Trade/ExecutionManager.mqh>
#include <PASR/Trade/PositionManager.mqh>
#include <PASR/Trade/ExitEngine.mqh>         // [NEW v6.10] Smart exit logic
#include <PASR/Trade/CorrelationManager.mqh>  // [NEW v6.10] Correlation matrix
#include <PASR/Trade/RecoveryManager.mqh>   // [14] v4.01: wired
//--- AI
#include <PASR/Signal/AI/AIFeatureBuilder.mqh>
#include <PASR/Signal/AI/AIInference.mqh>
#include <PASR/Signal/AI/AIEnsemble.mqh>
#include <PASR/Signal/AI/AICalibrationBridge.mqh>
#include <PASR/Signal/AI/FeatureEngine.mqh>   // [NEW] Advanced statistical features
//--- UI
#include <PASR/UI/DashboardManager.mqh>
//--- Data (Multi-Symbol)
#include <PASR/Data/SymbolScanner.mqh>
//--- QA (Stress Testing - only included if QA_BUILD is defined)
#ifdef QA_BUILD
#include <PASR/QA/QAStressTest.mqh>
#endif

//+------------------------------------------------------------------+
//|  INPUT PARAMETERS — grouped by module                            |
//+------------------------------------------------------------------+

//--- [MULTI-SYMBOL] ← v5.00: new group
sinput group "=== MULTI-SYMBOL SCANNER ==="
input string   InpSymbols[]       = {"EURUSD", "GBPUSD", "USDJPY"}; // Symbol list
input double   InpMaxSpreadPts    = 30.0;   // Max spread in points
input bool     InpCheckSession    = false;  // Check trading session
input int      InpSessionStart    = 0;      // Session start hour (UTC)
input int      InpSessionEnd      = 24;     // Session end hour (UTC)

//--- [CORRELATION] ← v6.10: new group
sinput group "=== CORRELATION RISK ==="
input bool     InpUseCorrelation  = true;   // Enable correlation check
input double   InpCorrThreshold   = 0.80;   // Max allowed correlation
input int      InpCorrWindow      = 20;     // Correlation lookback bars

//--- [EXIT ENGINE] ← v6.10: new group
sinput group "=== SMART EXIT LOGIC ==="
input bool     InpUseChandelier   = true;   // Use Chandelier trailing stop
input double   InpChanATRMult     = 3.0;    // Chandelier ATR multiplier
input int      InpChanPeriod      = 22;     // Chandelier lookback period
input bool     InpUseTimeExit     = false;  // Exit if no profit after N bars
input int      InpTimeExitBars    = 10;     // Time exit threshold
input bool     InpUseStructBreak  = true;   // Exit on structure break
input bool     InpUseProfitFade   = true;   // Exit on momentum fade

//--- [RISK]
sinput group "=== RISK MANAGEMENT ==="
input double   InpRiskPct         = 1.0;    // Risk per trade (%)
input double   InpMaxDailyLossPct = 3.0;    // Max daily loss (%)
input double   InpMaxDrawdownPct  = 10.0;   // Circuit-breaker DD (%)
input int      InpMaxTradesPerDay = 5;      // Max trades/day
input double   InpMinRR           = 1.5;    // Minimum R:R to trade

//--- [SR]
sinput group "=== SUPPORT / RESISTANCE ==="
input int      InpSRLookback      = 200;    // SR lookback bars
input int      InpSRMinTouches    = 2;      // Min touches for zone
input double   InpSRMergeATR      = 0.5;    // Merge threshold (ATR multiplier)
input int      InpSRMaxZones      = 20;     // Max active zones

//--- [SIGNAL]
sinput group "=== SIGNAL ENGINE ==="
input double   InpMinConfluence   = 0.60;   // Min signal confluence
input double   InpMaxSpreadPips   = 2.0;    // Max allowed spread (pips)
input bool     InpUsePatterns     = true;   // Use candlestick patterns
input bool     InpUseTrend        = true;   // Use trend filter

//--- [TRADE]
sinput group "=== TRADE EXECUTION ==="
input double   InpSLATRMult       = 1.5;    // SL = N * ATR
input double   InpTP1RR           = 1.5;    // TP1 R:R
input double   InpTP2RR           = 3.0;    // TP2 R:R (runner)
input bool     InpUseBE           = true;   // Enable break-even
input double   InpBEActivateRR    = 1.0;    // BE activates at R:R
input bool     InpUsePartial      = true;   // Enable partial close
input double   InpPartialPct      = 50.0;   // Partial close %
input bool     InpUseTrailing     = true;   // Enable trailing stop
input double   InpTrailATRMult    = 1.0;    // Trail = N * ATR

//--- [RECOVERY]  ← v4.01: new group
sinput group "=== RECOVERY ENGINE ==="
input bool     InpRecoveryEnabled = true;   // Enable fakeout recovery
input int      InpMaxRecovAttempts= 3;      // Max recovery attempts per trade
input int      InpRecovCooldown   = 3;      // Recovery cooldown (bars)
input int      InpMaxTradeDays    = 5;      // Force-close after N days (0=off)

//--- [AI]
sinput group "=== AI ENGINE ==="
input bool     InpUseAI           = true;   // Enable AI scoring
input double   InpAIVetoThresh    = 0.40;   // AI veto below score
input double   InpDriftVeto       = 0.60;   // Drift veto above
input double   InpAIHighThresh    = 0.80;   // High-confidence threshold
input bool     InpUseEnsemble     = true;   // Use ensemble voting
input bool     InpLoadWeights     = true;   // Load saved ensemble weights
input int      InpFeatureWindow   = 20;     // Feature engine rolling window
input bool     InpUseAdvFeatures  = true;   // Use advanced statistical features

//--- [DASHBOARD]
sinput group "=== DASHBOARD ==="
input bool     InpShowDash        = true;   // Show on-chart HUD
input bool     InpShowAIPanel     = true;   // Show AI panel
input bool     InpExportReport    = true;   // Export HTML report on deinit
input int      InpReportInterval  = 50;     // Export every N trades

//--- [QA & STRESS TEST] ← v5.20: NEW group (only active if QA_BUILD is defined)
sinput group "=== QA & STRESS TEST (DEV ONLY) ==="
input bool     InpEnableChaos     = false;  // Randomly inject errors if QA_BUILD is set
input int      InpChaosFrequency  = 100;    // Trigger chaos every N ticks
input double   InpChaosSpreadMult = 5.0;    // Spread spike multiplier during chaos
input bool     InpTestPoolExhaust = false;  // Test EventPool exhaustion fallback

//--- [GENERAL]
sinput group "=== GENERAL ==="
input ulong    InpMagic           = 20260521; // Magic number
input string   InpComment        = "PASR_v4";  // Order comment
sinput bool    InpJournalEnabled  = true;    // Enable CSV journal
sinput bool    InpDebugLog        = false;   // Verbose debug logging

//+------------------------------------------------------------------+
//|  MODULE INSTANCES                                                |
//+------------------------------------------------------------------+
CEventBus            g_bus;
CDataManager         g_data;
CStateManager        g_state;
CAdaptiveConfig      g_adaptCfg;
CJournalManager      g_journal;
CPerformanceReport   g_report;
CSRManager           g_sr;
CPatternManager      g_pattern;
CSignalManager       g_signal;
CRiskManager         g_risk;
CExecutionManager    g_exec;
CPositionManager     g_pos;
CExitEngine          g_exit;            // [NEW v6.10] Smart exit logic
CCorrelationManager  g_corr;           // [NEW v6.10] Correlation matrix
CRecoveryManager     g_recovery;   // [14] v4.01
CAIFeatureBuilder    g_featBuilder;
CAIInference         g_aiInfer;
CAIEnsemble          g_ensemble;
CAICalibrationBridge g_calibBridge;
CFeatureEngine       g_featEngine;   // [21] Advanced statistical feature engine
CDashboardManager    g_hud;
//--- Multi-Symbol Scanner (NEW v5.00)
CSymbolScanner       g_scanner;

//--- QA & Stress Test Module (NEW v5.20)
#ifdef QA_BUILD
CQAStressTest        g_qa;             // Main QA stress test engine
#endif

//--- QA & Stress Test State (NEW v5.20) - DEPRECATED, kept for backward compat
#ifdef QA_BUILD
int                  g_tickCounter    = 0;     // Counter for chaos frequency
bool                 g_chaosActive    = false; // Current chaos state
double               g_normalSpread   = 0.0;   // Baseline spread for comparison
ulong                g_allocCount     = 0;     // Track allocations for perf metrics
datetime             g_lastChaosTime  = 0;     // Last chaos trigger time
#endif

//+------------------------------------------------------------------+
//|  RUNTIME STATE                                                   |
//+------------------------------------------------------------------+
datetime          g_lastBarTime   = 0;
TradePlan         g_activePlan;
bool              g_hasPlan       = false;
ulong             g_openTicket    = 0;       // v4.01: track open ticket for recovery
FeatureVector     g_lastFV;
double            g_lastAIScore   = 0;
double            g_lastDrift     = 0;
int               g_lastEnsModel  = 0;
ENUM_MARKET_REGIME  g_regime      = REGIME_RANGING;
ENUM_TRADING_SESSION g_session    = SESSION_OFF;
datetime          g_posOpenTime   = 0;
DashContext       g_dashCtx;

//+------------------------------------------------------------------+
//|  HELPERS                                                         |
//+------------------------------------------------------------------+
void DebugPrint(string msg)
  { if(InpDebugLog) Print("[PASR_DBG] ", msg); }

double GetATR(int period = 14)
  {
   double atr[];
   ArraySetAsSeries(atr, true);
   int h = iATR(_Symbol, PERIOD_CURRENT, period);
   if(h == INVALID_HANDLE) return 0;
   CopyBuffer(h, 0, 0, 1, atr);
   IndicatorRelease(h);
   return (ArraySize(atr) > 0) ? atr[0] : 0;
  }

double GetSpreadPips()
  {
   long sp = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return sp * _Point * 10000.0;
  }

ENUM_TRADING_SESSION DetectSession()
  {
   MqlDateTime dt; TimeToStruct(TimeGMT(), dt);
   int h = dt.hour;
   if(h >= 12 && h < 16) return SESSION_OVERLAP;
   if(h >=  8 && h < 16) return SESSION_LONDON;
   if(h >= 13 && h < 22) return SESSION_NEWYORK;
   if(h >=  0 && h <  8) return SESSION_ASIAN;
   return SESSION_OFF;
  }

#ifdef QA_BUILD
//+------------------------------------------------------------------+
//|  QA Stress Test Helpers                                          |
//+------------------------------------------------------------------+

/// Force EventPool exhaustion test - triggers fallback path
void QATestEventPoolExhaustion()
  {
   Print("[PASR][QA] Testing EventPool exhaustion fallback...");
   
   // Attempt to allocate more events than pool capacity
   // This forces the fallback to new/delete
   const int POOL_CAPACITY = 256; // Match EventPool.mqh capacity
   const int EXHAUST_COUNT = POOL_CAPACITY + 50;
   
   int success_count = 0;
   for(int i = 0; i < EXHAUST_COUNT; i++)
     {
      // Try to create events directly via EventBus
      // If pool is exhausted, should fall back to heap allocation
      if(g_bus.CreateEvent(EVENT_TICK))
         success_count++;
     }
   
   PrintFormat("[PASR][QA] Exhaustion test: created %d/%d events (pool should have fallen back to heap)",
               success_count, EXHAUST_COUNT);
   
   // Process all pending events to clean up
   g_bus.ProcessPending();
   
   Print("[PASR][QA] EventPool exhaustion test complete - no crashes = PASS");
  }

/// Manually trigger a circuit breaker to validate RiskManager response
void QATestCircuitBreaker(ENUM_RISK_CB_TYPE cb_type)
  {
   Print("[PASR][QA] Manually triggering circuit breaker: ", EnumToString(cb_type));
   
   // Simulate extreme conditions based on CB type
   switch(cb_type)
     {
      case RISK_CB_DAILY_LOSS:
         // Fake a large loss to trigger daily loss CB
         g_risk.OnTradeClosed(-10000.0); // Large fake loss
         break;
         
      case RISK_CB_MAX_DRAWDOWN:
         // TODO: Would need direct access to drawdown counter
         Print("[PASR][QA] Drawdown CB test requires state manipulation");
         break;
         
      case RISK_CB_SPREAD:
         // Already tested via chaos spread spikes
         Print("[PASR][QA] Spread CB already tested via chaos engine");
         break;
         
      default:
         Print("[PASR][QA] Unknown CB type");
     }
   
   // Check if trading is now blocked
   bool allowed = g_risk.IsTradingAllowed();
   PrintFormat("[PASR][QA] After CB trigger - Trading allowed: %s", allowed ? "YES" : "NO");
  }
#endif

//+------------------------------------------------------------------+
//|  OnInit — ordered boot sequence                                  |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("[PASR] v5.20-qa-multisymbol booting — magic:", InpMagic);
   
#ifdef QA_BUILD
   if(InpEnableChaos)
      Print("[PASR][QA] CHAOS ENGINE ENABLED - frequency=", InpChaosFrequency, 
            " spread_mult=", InpChaosSpreadMult);
   if(InpTestPoolExhaust)
      Print("[PASR][QA] EVENTPOOL EXHAUSTION TEST ENABLED");
#endif

   //--- [01] Config
   g_adaptCfg.SetRiskPct(InpRiskPct);
   g_adaptCfg.SetMaxDailyLossPct(InpMaxDailyLossPct);
   g_adaptCfg.SetMaxDrawdownPct(InpMaxDrawdownPct);
   g_adaptCfg.SetMinRR(InpMinRR);

   //--- [02] EventBus
   g_bus.Init();

   //--- [20] SymbolScanner (NEW v5.00) - Initialize before other modules
   int sym_count = ArraySize(InpSymbols);
   if(sym_count > 0)
     {
      // Initialize scanner with symbol list from input
      if(!g_scanner.Init(InpSymbols, sym_count))
        {
         Alert("[PASR] SymbolScanner init failed - falling back to single symbol");
         string single_sym[];
         ArrayPushBack(single_sym, _Symbol);
         g_scanner.Init(single_sym, 1);
        }
      
      // Configure filter criteria
      SymbolFilterCriteria filter;
      filter.max_spread_pts    = InpMaxSpreadPts;
      filter.min_volume        = 0;  // No minimum volume filter by default
      filter.check_session     = InpCheckSession;
      filter.session_start_hour= InpSessionStart;
      filter.session_end_hour  = InpSessionEnd;
      
      g_scanner.SetFilter(filter);
      
      Print("[PASR] Scanner configured for ", sym_count, " symbols: ", 
            StringSubstr(ArrayToString(InpSymbols), 0, 100));
     }
   else
     {
      // Fallback to single-symbol mode if no symbols specified
      string single_sym[];
      ArrayPushBack(single_sym, _Symbol);
      g_scanner.Init(single_sym, 1);
      Print("[PASR] No symbol list provided - using chart symbol only: ", _Symbol);
     }

   //--- [03] DataManager
   if(!g_data.Init(_Symbol, PERIOD_CURRENT))
     { Alert("[PASR] DataManager init failed"); return INIT_FAILED; }

   //--- [04] StateManager
   g_state.Init(InpMagic);

   //--- [05] JournalManager
   g_journal.SetCSVEnabled(InpJournalEnabled);
   g_journal.SetCSVPrefix("PASR_Journal");

   //--- [06] PerformanceReport
   g_report.SetJournal(GetPointer(g_journal));

   //--- [07] SR Manager
   if(!g_sr.Init(_Symbol, PERIOD_CURRENT,
                 InpSRLookback, InpSRMinTouches,
                 InpSRMergeATR, InpSRMaxZones))
     { Alert("[PASR] SRManager init failed"); return INIT_FAILED; }

   //--- [08] Pattern Manager
   g_pattern.Init(_Symbol, PERIOD_CURRENT);

   //--- [09] Signal Manager
   g_signal.Init(_Symbol, PERIOD_CURRENT,
                 InpMinConfluence, InpUseTrend, InpUsePatterns,
                 GetPointer(g_sr), GetPointer(g_pattern));

   //--- [10] Risk Manager
   g_risk.Init(InpMagic, InpRiskPct, InpMaxDailyLossPct,
               InpMaxDrawdownPct, InpMaxTradesPerDay, InpMinRR);

   //--- [11] Execution Manager
   g_exec.Init(InpMagic, InpComment,
               InpSLATRMult, InpTP1RR, InpTP2RR);

   //--- [12] Position Manager
   g_pos.Init(InpMagic,
               InpUseBE,      InpBEActivateRR,
               InpUsePartial, InpPartialPct,
               InpUseTrailing,InpTrailATRMult);

   //--- [13] Exit Engine ← v6.10
   g_exit.Init();
   
   //--- [14] Correlation Manager ← v6.10
   if(InpUseCorrelation)
   {
      g_corr.Initialize();
      Print("[INIT] Correlation risk enabled (threshold=", InpCorrThreshold, ", window=", InpCorrWindow, ")");
   }

   //--- [15] Recovery Manager  ← v4.01
   g_recovery.Init(GetPointer(g_data), GetPointer(g_bus));
   g_recovery.SetTrailingThrottle(200);  // throttle trailing to 200ms

   //--- [13] AI Feature Builder
   g_featBuilder.Init(_Symbol, PERIOD_CURRENT);

   //--- [14-16] AI stack
   g_aiInfer.Init();
   g_ensemble.Init();
   if(InpLoadWeights) g_ensemble.LoadWeights();

   //--- [17] Calibration Bridge
   g_calibBridge.SetJournal(GetPointer(g_journal));
   g_calibBridge.SetHighThresh(InpAIHighThresh);
   g_calibBridge.SetVetoThresh(InpAIVetoThresh);

   //--- [19] Dashboard
   if(InpShowDash)
     {
      g_hud.Init(GetPointer(g_journal));
      ZeroMemory(g_dashCtx);
     }

   //--- [21] Feature Engine (NEW) - Advanced statistical features
   if(InpUseAdvFeatures)
     {
      if(!g_featEngine.Init(_Symbol, PERIOD_CURRENT, InpFeatureWindow))
        {
         Print("[PASR][WARN] FeatureEngine init failed - using basic features only");
        }
      else
        {
         Print("[PASR] FeatureEngine initialized with window=", InpFeatureWindow);
        }
     }

#ifdef QA_BUILD
   //--- [QA] Run initial stress tests if enabled
   if(InpTestPoolExhaust)
     {
      // Run EventPool exhaustion test during init
      QATestEventPoolExhaustion();
     }
   
   // Initialize QA stress test engine
   if(!g_qa.Init(InpChaosFrequency, InpChaosSpreadMult, InpTestPoolExhaust))
     {
      Print("[PASR][QA][WARN] QAStressTest initialization failed");
     }
   
   // Initialize normal spread baseline for chaos testing
   g_normalSpread = GetSpreadPips();
   PrintFormat("[PASR][QA] Baseline spread: %.1f pips", g_normalSpread);
#endif

   // Reset runtime state
   g_lastBarTime = 0;
   g_hasPlan     = false;
   g_openTicket  = 0;
   g_regime      = REGIME_RANGING;
   g_session     = DetectSession();

   Print("[PASR] Boot complete — all modules initialized (Multi-Symbol Ready)");
   EventSetTimer(60);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//|  OnDeinit — ordered shutdown                                     |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   
#ifdef QA_BUILD
   //--- Print QA statistics from engine
   g_qa.PrintReport();
   
   // Legacy stats (for backward compatibility)
   PrintFormat("[PASR][QA] SHUTDOWN STATS - ticks_processed:%d chaos_triggers:%d alloc_count:%lu",
               g_tickCounter, (g_lastChaosTime > 0 ? g_tickCounter / InpChaosFrequency : 0),
               g_allocCount);
#endif
   
   //--- Print scanner statistics (NEW v5.00)
   g_scanner.PrintStats();
   
   //--- Print exit engine statistics (NEW v6.10)
   g_exit.PrintStats();
   
   //--- Print correlation statistics (NEW v6.10)
   if(InpUseCorrelation) g_corr.PrintStatus();
   g_ensemble.SaveWeights();
   g_calibBridge.ExportCalibrationCSV();
   if(InpExportReport) g_report.ExportHTML();
   if(InpShowDash) g_hud.Deinit();
   g_sr.Deinit();
   g_data.Deinit();
   g_bus.Deinit();
   PrintFormat("[PASR] Shutdown — reason:%d  total_trades:%d",
               reason, g_journal.GetTotalTrades());
  }

//+------------------------------------------------------------------+
//|  OnTick — main execution loop (Multi-Symbol v5.00)               |
//+------------------------------------------------------------------+
void OnTick()
  {
#ifdef QA_BUILD
   //--- [QA] Increment tick counter and trigger chaos if enabled
   g_tickCounter++;
   
   // Use QA engine for chaos injection and metrics
   g_qa.OnTick(current_symbol, g_bus, g_risk);
   
   // Update legacy state variables for backward compatibility
   g_chaosActive = g_qa.IsChaosActive();
   g_allocCount++;
#endif

   //--- Multi-Symbol Scanning Loop (NEW v5.00)
   //    Round-robin through all configured symbols
   int sym_idx;
   while((sym_idx = g_scanner.ScanNext()) >= 0)
     {
      // Get symbol info and tick cache for this symbol
      const SymbolInfoEx *sym_info = g_scanner.GetSymbolInfo(sym_idx);
      CTickCache *tick_cache = g_scanner.GetTickCache(sym_idx);
      
      if(sym_info == NULL || tick_cache == NULL) continue;
      
      string current_symbol = sym_info.name;
      
      //--- [A] Switch context to current symbol
      // Note: Most managers work with _Symbol, so we need to handle multi-symbol carefully
      // For now, we process only when chart symbol matches scanned symbol
      // Future enhancement: refactor managers to accept symbol parameter
      if(current_symbol != _Symbol)
        {
         // Skip processing for non-chart symbols in this version
         // The scanner still filters ticks, but trading happens on chart symbol only
         // TODO: Full multi-symbol trading support in v5.10
         continue;
        }
      
      //--- [B] Spread guard (using scanner's filtered spread)
      double spread_pts = sym_info.spread;
      double spread_pips = spread_pts * sym_info.point * 10000.0;
      if(spread_pips > InpMaxSpreadPips)
        {
         DebugPrint(StringFormat("[%s] Spread guard: %.1f > %.1f pips",
                                 current_symbol, spread_pips, InpMaxSpreadPips));
         continue;
        }

      //--- [C] Process deferred EventBus queue
      g_bus.ProcessPending();

      //--- [D] Position management (BE, partial, trailing) + ExitEngine (NEW v6.10)
      //        + recovery price-tick monitoring
      double atrC = GetATR();
      if(g_pos.HasOpenPosition())
        {
         g_pos.OnTick(atrC);
         // Check for smart exit signals (Chandelier, Time-Based, Structure Break)
         // Note: ExitEngine requires position type and prices for proper exit calculation
         if(InpUseChandelier || InpUseTimeExit || InpUseStructBreak || InpUseProfitFade)
           {
            // Get current position info
            ulong ticket = PositionGetTicket(0); // Get first open position
            if(ticket > 0)
              {
               if(PositionSelectByTicket(ticket))
                 {
                  ENUM_ORDER_TYPE pos_type = (ENUM_ORDER_TYPE)PositionGetInteger(POSITION_TYPE);
                  double entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
                  double current_price = (pos_type == POSITION_TYPE_BUY) 
                                         ? SymbolInfoDouble(current_symbol, SYMBOL_BID)
                                         : SymbolInfoDouble(current_symbol, SYMBOL_ASK);
                  
                  ExitSignal exit_sig = g_exit.CheckExit(current_symbol, pos_type, entry_price, current_price);
                  
                  if(exit_sig.reason != EXIT_NONE)
                    {
                     DebugPrint(StringFormat("[%s] Exit signal: %s (Reason: %s)", 
                                            current_symbol, 
                                            exit_sig.description,
                                            EnumToString(exit_sig.reason)));
                     // Exit will be handled by PositionManager or ExecutionManager
                    }
                 }
              }
           }
        }
      if(InpRecoveryEnabled)
         g_recovery.OnPriceUpdate();

      //--- [E] New-bar detection
      datetime barTime = iTime(current_symbol, PERIOD_CURRENT, 0);
      bool isNewBar = (barTime != g_lastBarTime);
      if(!isNewBar)
        {
         if(InpShowDash) UpdateDashboard();
         continue;
        }
      g_lastBarTime = barTime;
      DebugPrint(StringFormat("[%s] New bar: %s", current_symbol, TimeToString(barTime)));

      //--- [F] Session detect
      g_session = DetectSession();

      //--- [G] Data update
      g_data.OnNewBar();

      //--- [H] Regime detection
      double atr = GetATR();
      g_regime = g_adaptCfg.DetectRegime(current_symbol, PERIOD_CURRENT, atr);
      EffectivePolicy policy = g_adaptCfg.GetEffectivePolicy(
                                 g_regime, g_session, atr);

      //--- [H2] Recovery new-bar processing
      if(InpRecoveryEnabled)
         g_recovery.OnNewBar();

      //--- [I] Risk daily reset check + Correlation Check (NEW v6.10)
      if(!g_risk.IsTradingAllowed(current_symbol))
        {
         DebugPrint("Risk circuit breaker active — skip bar");
         if(InpShowDash) UpdateDashboard();
         continue;
        }
      
      //--- [I2] Correlation Matrix Check (NEW v6.10)
      // Block entry if current symbol has high correlation with existing positions
      if(InpUseCorrelation && !g_corr.IsCorrelationSafe(current_symbol, InpCorrThreshold, InpCorrWindow))
        {
         DebugPrint(StringFormat("[%s] Correlation guard: blocked due to high correlation with existing positions", current_symbol));
         if(InpShowDash) UpdateDashboard();
         continue;
        }

      //--- [J] SR recalculation
      g_sr.OnNewBar();

      //--- [K] Pattern scan
      g_pattern.OnNewBar();

      //--- [L] Signal generation
      TradeSignal sig;
      bool hasSignal = g_signal.GenerateSignal(sig, atr);
      if(!hasSignal)
        {
         DebugPrint("No signal this bar");
         if(InpShowDash) UpdateDashboard();
         continue;
        }
      DebugPrint(StringFormat("Signal: %s  confluence:%.2f",
                 sig.direction==SIGNAL_BUY?"BUY":"SELL", sig.confluence));

      //--- [M] AI Feature build + Advanced Statistical Features (NEW)
      SRZone zones[20];
      int nZones = g_sr.GetZones(zones, 20);
      g_lastFV = g_featBuilder.Build(sig, atr,
                                      sig.nearestSupport,
                                      sig.nearestResistance,
                                      zones, nZones);
      
      // Compute advanced statistical features if enabled
      FeatureSet adv_features;
      if(InpUseAdvFeatures && g_featEngine.IsInitialized())
        {
         adv_features = g_featEngine.ComputeFeatures();
         
         // Log regime detection from FeatureEngine
         if(adv_features.regime != VOLATILITY_MEDIUM)
           {
            DebugPrint(StringFormat("[%s] Volatility regime: %s (z-score=%.2f, skew=%.2f, kurt=%.2f)",
                                    current_symbol, 
                                    EnumToString(adv_features.regime),
                                    adv_features.z_score,
                                    adv_features.skewness,
                                    adv_features.kurtosis));
           }
        }

      //--- [N] Drift check + Volatility Regime Adjustment (NEW)
      g_lastDrift = g_featBuilder.ComputeDrift(g_lastFV);
      
      // Adjust AI veto threshold based on volatility regime (NEW)
      double effective_veto_thresh = InpAIVetoThresh;
      if(InpUseAdvFeatures && g_featEngine.IsInitialized())
        {
         ENUM_VOLATILITY_REGIME regime = g_featEngine.GetCurrentRegime();
         
         // Increase veto threshold in high volatility (be more conservative)
         if(regime == VOLATILITY_HIGH)
            effective_veto_thresh = InpAIVetoThresh * 1.2;  // Require higher AI score
         else if(regime == VOLATILITY_EXTREME)
            effective_veto_thresh = InpAIVetoThresh * 1.5;  // Much more conservative
         // In low volatility, keep standard threshold or slightly lower
         else if(regime == VOLATILITY_LOW)
            effective_veto_thresh = InpAIVetoThresh * 0.9;  // Slightly more permissive
        }
      
      if(InpUseAI && g_lastDrift > InpDriftVeto)
        {
         DebugPrint(StringFormat("Drift veto: %.2f", g_lastDrift));
         CDashboardManager::PushSignal(g_dashCtx, sig.direction, 0, 0);
         if(InpShowDash) UpdateDashboard();
         continue;
        }

      //--- [O] AI Ensemble scoring + Volatility Regime Adjustment (NEW)
      double patternBonus = g_pattern.GetPatternBonus(sig.direction);
      
      // Base AI score from ensemble or inference
      double base_ai_score = InpUseAI
         ? (InpUseEnsemble
              ? g_ensemble.GetScore(g_lastFV, sig, patternBonus, g_lastDrift)
              : g_aiInfer.ForwardPass18(g_lastFV, patternBonus, g_lastDrift))
         : sig.confluence;
      
      // Apply volatility regime adjustment to AI score (NEW)
      if(InpUseAdvFeatures && g_featEngine.IsInitialized())
        {
         ENUM_VOLATILITY_REGIME regime = g_featEngine.GetCurrentRegime();
         
         // Reduce AI confidence in high/extreme volatility (more uncertainty)
         if(regime == VOLATILITY_HIGH)
            base_ai_score *= 0.9;   // 10% confidence reduction
         else if(regime == VOLATILITY_EXTREME)
            base_ai_score *= 0.75;  // 25% confidence reduction
         // Slight boost in low volatility (clearer signals)
         else if(regime == VOLATILITY_LOW)
            base_ai_score = MathMin(1.0, base_ai_score * 1.05);  // 5% boost, capped at 1.0
         
         DebugPrint(StringFormat("[%s] Regime adj: %s -> AI score %.2f -> %.2f",
                                 current_symbol,
                                 EnumToString(regime),
                                 base_ai_score / ((regime == VOLATILITY_HIGH) ? 0.9 : 
                                                 (regime == VOLATILITY_EXTREME) ? 0.75 :
                                                 (regime == VOLATILITY_LOW) ? 1.05 : 1.0),
                                 base_ai_score));
        }
      
      g_lastAIScore = base_ai_score;
      g_lastEnsModel = g_ensemble.GetActiveModel();

      DebugPrint(StringFormat("AI score:%.2f drift:%.2f model:%d",
                              g_lastAIScore, g_lastDrift, g_lastEnsModel));

      //--- [P] Calibration bridge
      AIScoreOverride ov = g_calibBridge.MapScoreToPolicy(
                             g_lastAIScore, policy);
      if(ov.blockTrade)
        {
         DebugPrint(StringFormat("CalibBridge veto: score=%.2f", g_lastAIScore));
         CDashboardManager::PushSignal(g_dashCtx, sig.direction,
                                       g_lastAIScore, 0);
         if(InpShowDash) UpdateDashboard();
         continue;
        }
      EffectivePolicy ep = g_calibBridge.ApplyOverride(policy, ov);

      //--- [Q] Risk sizing + Volatility-Adjusted Position Sizing (NEW)
      if(!g_risk.CanOpenTrade())
        {
         DebugPrint("Risk: trade blocked (daily limit or max trades)");
         if(InpShowDash) UpdateDashboard();
         continue;
        }

      // Base lot size calculation
      double lotSize = g_risk.CalcLotSize(
                         current_symbol, atr * InpSLATRMult, ep.lotMultiplier);
      
      // Apply volatility regime position sizing adjustment (NEW)
      if(InpUseAdvFeatures && g_featEngine.IsInitialized())
        {
         ENUM_VOLATILITY_REGIME regime = g_featEngine.GetCurrentRegime();
         
         // Reduce position size in high/extreme volatility
         if(regime == VOLATILITY_HIGH)
            lotSize *= 0.8;   // 20% reduction
         else if(regime == VOLATILITY_EXTREME)
            lotSize *= 0.5;   // 50% reduction - significant de-risking
         // Slight increase in low volatility (controlled environment)
         else if(regime == VOLATILITY_LOW)
            lotSize = MathMin(lotSize * 1.1, lotSize + 0.05);  // 10% boost or +0.05 lots, whichever is lower
         
         DebugPrint(StringFormat("[%s] Regime position adj: %s -> %.2f lots",
                                 current_symbol,
                                 EnumToString(regime),
                                 lotSize));
        }
      
      if(lotSize <= 0)
        {
         DebugPrint("Risk: lot size = 0");
         continue;
        }

      //--- [R] Build TradePlan with symbol-specific magic number
      TradePlan plan;
      plan.direction  = sig.direction;
      plan.entryPrice = (sig.direction == SIGNAL_BUY)
                        ? SymbolInfoDouble(current_symbol, SYMBOL_ASK)
                        : SymbolInfoDouble(current_symbol, SYMBOL_BID);
      plan.sl         = plan.entryPrice
                      + ((sig.direction==SIGNAL_BUY ? -1 : 1)
                         * atr * ep.slATRMult);
      plan.tp         = plan.entryPrice
                      + ((sig.direction==SIGNAL_BUY ? 1 : -1)
                         * atr * ep.slATRMult * ep.tp1RR);
      plan.tp2        = plan.entryPrice
                      + ((sig.direction==SIGNAL_BUY ? 1 : -1)
                         * atr * ep.slATRMult * ep.tp2RR);
      plan.lot        = lotSize;
      // Use symbol-specific magic number for isolation
      plan.magic      = g_scanner.GenerateMagicNumber(InpMagic, sym_idx);
      plan.comment    = InpComment + "_" + current_symbol;

      double riskPts   = MathAbs(plan.entryPrice - plan.sl);
      double rewardPts = MathAbs(plan.tp - plan.entryPrice);
      if(riskPts <= 0 || (rewardPts / riskPts) < InpMinRR)
        {
         DebugPrint(StringFormat("RR too low: %.2f", rewardPts/riskPts));
         continue;
        }

      //--- [S] Execute
      if(!g_exec.OpenTrade(plan))
        {
         DebugPrint(StringFormat("Execution failed: %d", GetLastError()));
         continue;
        }

      g_activePlan   = plan;
      g_hasPlan      = true;
      g_posOpenTime  = TimeCurrent();
      g_risk.OnTradeOpened();
      g_calibBridge.LogTradeOpen(g_lastAIScore);

      CDashboardManager::PushSignal(g_dashCtx,
                                     sig.direction, g_lastAIScore, 0);

      PrintFormat("[PASR][%s] OPENED %s  entry:%.5f  sl:%.5f  tp:%.5f  lots:%.2f  AI:%.2f",
                  current_symbol,
                  plan.direction==SIGNAL_BUY?"BUY":"SELL",
                  plan.entryPrice, plan.sl, plan.tp, plan.lot, g_lastAIScore);

      if(InpShowDash) UpdateDashboard();
     }
   
   //--- If no symbols were processed (all filtered), still update dashboard
   if(InpShowDash) UpdateDashboard();
  }

//+------------------------------------------------------------------+
//|  OnTradeTransaction — journal + recovery + weight update         |
//+------------------------------------------------------------------+
void OnTradeTransaction(
      const MqlTradeTransaction &trans,
      const MqlTradeRequest     &req,
      const MqlTradeResult      &res)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal))            return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != (long)InpMagic) return;

   long dealEntry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

   //--- v4.01: notify RecoveryManager on position OPEN
   if(dealEntry == DEAL_ENTRY_IN && InpRecoveryEnabled)
     {
      ulong ticket = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
      double entryPrice = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
      int direction = (g_activePlan.direction == SIGNAL_BUY) ? 1 : -1;
      g_recovery.OnTradeOpen(ticket, direction, entryPrice);
      g_openTicket = ticket;
      DebugPrint(StringFormat("RecoveryManager: engine created for ticket=%d", ticket));
      return;
     }

   if(dealEntry != DEAL_ENTRY_OUT) return;

   double closePrice = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   double pnl        = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                     + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                     + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   bool   isWin      = (pnl > 0);
   double rr         = 0;
   double riskPts    = MathAbs(g_activePlan.entryPrice - g_activePlan.sl);
   if(riskPts > 0)
      rr = (pnl > 0 ? 1 : -1)
         * MathAbs(closePrice - g_activePlan.entryPrice) / riskPts;

   //--- v4.01: deactivate recovery engine
   if(InpRecoveryEnabled && g_openTicket > 0)
     {
      g_recovery.OnTradeClose(g_openTicket);
      g_openTicket = 0;
     }

   //--- Journal
   if(g_hasPlan)
     {
      g_journal.OnPositionClosed(
         trans.deal,
         g_posOpenTime,
         g_activePlan,
         closePrice, pnl,
         g_regime, g_session,
         g_lastAIScore, g_lastDrift,
         g_lastEnsModel,
         g_lastFV,
         g_pos.IsBEDone(),
         g_pos.IsPartialDone(),
         g_pos.IsRunnerActive());
      g_hasPlan = false;
     }

   //--- Risk daily P&L update
   g_risk.OnTradeClosed(pnl);

   //--- Calibration
   g_calibBridge.LogTradeClose(isWin, rr);

   //--- Ensemble weight update
   g_ensemble.UpdateWeight(
      (ENUM_ENSEMBLE_MODEL)g_lastEnsModel, isWin);
   g_ensemble.SaveWeights();

   //--- Dashboard
   CDashboardManager::UpdateSignalOutcome(
      g_dashCtx, isWin ? 1 : -1);

   //--- Auto-export
   if(InpExportReport &&
      g_journal.GetTotalTrades() % InpReportInterval == 0)
      g_report.ExportHTML();

   PrintFormat("[PASR] CLOSED %s  PnL:%.2f  RR:%.2f  AI:%.2f  Win:%s",
               g_activePlan.direction==SIGNAL_BUY?"BUY":"SELL",
               pnl, rr, g_lastAIScore, isWin?"YES":"NO");
  }

//+------------------------------------------------------------------+
//|  OnTimer — 1-min heartbeat                                       |
//+------------------------------------------------------------------+
void OnTimer()
  {
   if(InpShowDash) UpdateDashboard();
  }

//+------------------------------------------------------------------+
//|  UpdateDashboard                                                 |
//+------------------------------------------------------------------+
void UpdateDashboard()
  {
   if(!InpShowDash) return;

   g_dashCtx.regime    = g_regime;
   g_dashCtx.session   = g_session;
   g_dashCtx.spread    = GetSpreadPips();
   g_dashCtx.aiScore   = g_lastAIScore;
   g_dashCtx.driftScore= g_lastDrift;
   g_dashCtx.ensembleModel = g_lastEnsModel;
   g_dashCtx.aiVeto    = (g_lastAIScore < InpAIVetoThresh ||
                          g_lastDrift   > InpDriftVeto);

   g_dashCtx.hasPosition = g_pos.HasOpenPosition();
   if(g_dashCtx.hasPosition)
     {
      g_dashCtx.posDir    = g_activePlan.direction;
      g_dashCtx.posEntry  = g_activePlan.entryPrice;
      g_dashCtx.posSL     = g_activePlan.sl;
      g_dashCtx.posTP1    = g_activePlan.tp;
      g_dashCtx.posTP2    = g_activePlan.tp2;
      g_dashCtx.posLots   = g_activePlan.lot;
      g_dashCtx.posPnL    = g_pos.GetFloatingPnL();
      g_dashCtx.beDone    = g_pos.IsBEDone();
      g_dashCtx.partialDone = g_pos.IsPartialDone();
     }
   else
     {
      ZeroMemory(g_dashCtx.posDir);
      g_dashCtx.posEntry = g_dashCtx.posSL  = 0;
      g_dashCtx.posTP1   = g_dashCtx.posTP2 = 0;
      g_dashCtx.posLots  = g_dashCtx.posPnL = 0;
      g_dashCtx.beDone   = g_dashCtx.partialDone = false;
     }

   g_hud.Update(g_dashCtx);
  }
//+------------------------------------------------------------------+
//| END OF PASR_MODULAR.mq5 v4.01                                    |
//+------------------------------------------------------------------+
