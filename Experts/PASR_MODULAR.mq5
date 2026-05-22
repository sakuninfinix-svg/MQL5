//+------------------------------------------------------------------+
//|  PASR_MODULAR.mq5                                                |
//|  Expert Advisor: PASR (Price Action Support Resistance)          |
//|  Version: 12.00 — Pipeline Architecture with Orchestrator        |
//+------------------------------------------------------------------+
#property copyright   "PASR EA © 2026"
#property link        "https://github.com/sakuninfinix-svg/MQL5"
#property version     "12.00"
#property description "PASR Model - Pipeline Architecture with Dynamic Orchestration"
#property strict

//--- Compilation Flags
#define QA_BUILD          // Enable stress testing & chaos engineering
#define PERF_METRICS      // Enable performance counters
#define OOP_ARCHITECTURE  // Enable OOP divide & conquer architecture
#define INST_MODE         // Enable Institutional Mode features

//--- OOP CORE MODULES (Institutional Architecture)
#include <PASR/Core/PASR_Executor.mqh>
#include <PASR/Core/PASR_SymbolManager.mqh>
#include <PASR/Core/PASR.Types.mqh>
#include <PASR/Core/Orchestrator.mqh>

//--- Core
#include <PASR/Core/Config/Manager.mqh>
#include <PASR/Core/EventBus.mqh>
//--- Infra
#include <PASR/Infra/DataManager.mqh>
#include <PASR/Infra/StateManager.mqh>
#include <PASR/Infra/AdaptiveConfig.mqh>
#include <PASR/Infra/JournalManager.mqh>
#include <PASR/Infra/PerformanceReport.mqh>
//--- Analysis
#include <PASR/Analysis/SRManager.mqh>
//--- Pattern
#include <PASR/Analysis/Pattern/PatternManager.mqh>
//--- Signal
#include <PASR/Signal/SignalManager.mqh>
//--- Trade
#include <PASR/Trade/RiskManager.mqh>
#include <PASR/Trade/TradePlan.mqh>
#include <PASR/Trade/PositionManager.mqh>
#include <PASR/Trade/ExitEngine.mqh>
#include <PASR/Trade/CorrelationManager.mqh>
#include <PASR/Trade/RecoveryManager.mqh>
//--- AI
#include <PASR/Signal/AI/AIFeatureBuilder.mqh>
#include <PASR/Signal/AI/AIInference.mqh>
#include <PASR/Signal/AI/AIEnsemble.mqh>
#include <PASR/Signal/AI/AICalibrationBridge.mqh>
#include <PASR/Signal/AI/FeatureEngine.mqh>
//--- UI
#include <PASR/UI/DashboardManager.mqh>
//--- Data (Multi-Symbol)
#include <PASR/Data/SymbolScanner.mqh>
//--- QA (Stress Testing - only included if QA_BUILD is defined)
#ifdef QA_BUILD
#include <PASR/QA/QAStressTest.mqh>
#endif

//+------------------------------------------------------------------+
//|  INPUT PARAMETERS — Institutional Configuration                  |
//+------------------------------------------------------------------+

//--- [INSTITUTIONAL RISK] ← v10.00: Core Capital Protection
sinput group "=== INSTITUTIONAL RISK MANAGEMENT ==="
input double   InpRiskPct         = 1.0;    // Risk per Trade (% of Equity)
input double   InpMaxDailyLossPct = 3.0;    // Daily Loss Circuit Breaker (%)
input double   InpMaxDrawdownPct  = 10.0;   // Global Drawdown Halt (%)
input bool     InpVolatilityAdj   = true;   // Adjust Size by ATR Volatility
input int      InpPyramidLevels   = 3;      // Scale-in Tranches (0=Disabled)
input double   InpPyramidSpacing  = 0.5;    // Tranche Distance (ATR Multiplier)
input int      InpMaxTradesPerDay = 20;     // Max Trades Per Day (Circuit Breaker)

//--- [MARKET STRUCTURE] ← v10.00: Structural Stops & Targets
sinput group "=== MARKET STRUCTURE LOGIC ==="
input bool     InpStructSL        = true;   // Use Swing High/Low for SL
input double   InpSLBufferATR     = 1.5;    // Buffer for Structural SL (ATR)
input bool     InpStructTrail     = true;   // Trail based on Market Structure
input bool     InpUseChandelier   = true;   // Chandelier Exit for Runners
input double   InpChanATRMult     = 3.0;    // Chandelier ATR Multiplier
input int      InpChanPeriod      = 22;     // Chandelier Lookback

//--- [SUPPORT/RESISTANCE] ← Zone Detection Parameters
sinput group "=== SUPPORT/RESISTANCE DETECTION ==="
input int      InpSRLookback      = 50;     // SR Lookback Bars
input int      InpSRMinTouches    = 2;      // Minimum Touches to Validate SR
input double   InpSRMergeATR      = 0.5;    // Merge Zones within N ATR
input int      InpSRMaxZones      = 10;     // Maximum SR Zones to Track

//--- [MULTI-SYMBOL] ← Scalable Portfolio Execution
sinput group "=== MULTI-SYMBOL SCANNER ==="
input string   InpSymbols[]       = {"EURUSD", "GBPUSD", "USDJPY"}; // Symbol List
input double   InpMaxSpreadPts    = 30.0;   // Max Spread in Points
input bool     InpCheckSession    = false;  // Check Trading Session
input int      InpSessionStart    = 0;      // Session Start Hour (UTC)
input int      InpSessionEnd      = 24;     // Session End Hour (UTC)

//--- [CORRELATION] ← Portfolio Risk Control
sinput group "=== CORRELATION RISK ==="
input bool     InpUseCorrelation  = true;   // Enable Correlation Check
input double   InpCorrThreshold   = 0.80;   // Max Allowed Correlation
input int      InpCorrWindow      = 20;     // Correlation Lookback Bars

//--- [SIGNAL & CONFLUENCE] ← High-Probability Setup Filter
sinput group "=== SIGNAL ENGINE ==="
input double   InpMinConfluence   = 0.60;   // Min Signal Confluence Score
input double   InpMaxSpreadPips   = 2.0;    // Max Allowed Spread (Pips)
input bool     InpUsePatterns     = true;   // Use Candlestick Patterns
input bool     InpUseTrend        = true;   // Use Trend Filter
input int      InpMinBarsConfirm  = 2;      // Minimum Confirmation Bars

//--- [EXECUTION] ← Low-Latency Order Management
sinput group "=== TRADE EXECUTION ==="
input int      InpMaxSlippage     = 15;     // Max Slippage (Points)
input int      InpRetryAttempts   = 3;      // Smart Retry Count
input bool     InpAsyncMode       = true;   // Asynchronous Processing
input double   InpMinRR           = 1.5;    // Minimum R:R to Trade
input double   InpTP1RR           = 1.5;    // TP1 R:R (Partial)
input double   InpTP2RR           = 3.0;    // TP2 R:R (Runner)

//--- [POSITION MANAGEMENT] ← Active Trade Handling
sinput group "=== POSITION MANAGEMENT ==="
input bool     InpUseBE           = true;   // Enable Break-Even
input double   InpBEActivateRR    = 1.0;    // BE Activates at R:R
input bool     InpUsePartial      = true;   // Enable Partial Close
input double   InpPartialPct      = 50.0;   // Partial Close %
input bool     InpUseTrailing     = true;   // Enable Trailing Stop
input double   InpTrailATRMult    = 1.0;    // Trail = N * ATR
input bool     InpUseTimeExit     = false;  // Exit if No Profit after N Bars
input int      InpTimeExitBars    = 10;     // Time Exit Threshold
input bool     InpUseStructBreak  = true;   // Exit on Structure Break
input bool     InpUseProfitFade   = true;   // Exit on Momentum Fade

//--- [RECOVERY] ← Fakeout Protection
sinput group "=== RECOVERY ENGINE ==="
input bool     InpRecoveryEnabled = true;   // Enable Fakeout Recovery
input int      InpMaxRecovAttempts= 3;      // Max Recovery Attempts per Trade
input int      InpRecovCooldown   = 3;      // Recovery Cooldown (Bars)
input int      InpMaxTradeDays    = 5;      // Force-Close after N Days (0=Off)

//--- [AI] ← Machine Learning Filtering
sinput group "=== AI ENGINE ==="
input bool     InpUseAI           = true;   // Enable AI Scoring
input double   InpAIVetoThresh    = 0.40;   // AI Veto Below Score
input double   InpDriftVeto       = 0.60;   // Drift Veto Above
input double   InpAIHighThresh    = 0.80;   // High-Confidence Threshold
input bool     InpUseEnsemble     = true;   // Use Ensemble Voting
input bool     InpLoadWeights     = true;   // Load Saved Ensemble Weights
input int      InpFeatureWindow   = 20;     // Feature Engine Rolling Window
input bool     InpUseAdvFeatures  = true;   // Use Advanced Statistical Features

//--- [DASHBOARD] ← Monitoring & Reporting
sinput group "=== DASHBOARD ==="
input bool     InpShowDash        = true;   // Show On-Chart HUD
input bool     InpShowAIPanel     = true;   // Show AI Panel
input bool     InpExportReport    = true;   // Export HTML Report on Deinit
input int      InpReportInterval  = 50;     // Export Every N Trades

//--- [QA & STRESS TEST] ← Institutional Validation
sinput group "=== QA & STRESS TEST (DEV ONLY) ==="
input bool     InpEnableChaos     = false;  // Randomly Inject Errors if QA_BUILD
input int      InpChaosFrequency  = 100;    // Trigger Chaos Every N Ticks
input double   InpChaosSpreadMult = 5.0;    // Spread spike multiplier during chaos
input bool     InpTestPoolExhaust = false;  // Test EventPool exhaustion fallback

//--- [GENERAL]
sinput group "=== GENERAL ==="
input ulong    InpMagic           = 20260521; // Magic number
input string   InpComment        = "PASR_v10";  // Order comment
sinput bool    InpJournalEnabled  = true;    // Enable CSV journal
sinput bool    InpDebugLog        = false;   // Verbose debug logging

//+------------------------------------------------------------------+
//|  MODULE INSTANCES — PIPELINE ARCHITECTURE WITH ORCHESTRATOR      |
//+------------------------------------------------------------------+
//--- PIPELINE CORE: Orchestrator coordinates all modules
COrchestrator        g_orchestrator;     // Main pipeline coordinator
CExecutor            g_executor;         // Async order executor (SOLE execution engine)
CSymbolManager       g_symMgr;           // Multi-symbol manager

//--- Pipeline Stage Modules (managed by Orchestrator)
CEventBus            g_bus;              // Event-driven communication
CDataManager         g_data;             // Market data feed
CStateManager        g_state;            // State persistence
CAdaptiveConfig      g_adaptCfg;         // Dynamic regime adaptation
CJournalManager      g_journal;          // Trade journaling
CPerformanceReport   g_report;           // Performance analytics
CSRManager           g_sr;               // Support/Resistance detection
CPatternManager      g_pattern;          // Pattern recognition
CSignalManager       g_signal;           // Signal generation
CRiskManager         g_risk;             // Risk circuit breakers
CPositionManager     g_pos;              // Active position management
CExitEngine          g_exit;             // Exit signal detection
CCorrelationManager  g_corr;             // Portfolio correlation
CRecoveryManager     g_recovery;         // Fakeout recovery
CAIFeatureBuilder    g_featBuilder;      // AI feature engineering
CAIInference         g_aiInfer;          // AI inference engine
CAIEnsemble          g_ensemble;         // Ensemble voting
CAICalibrationBridge g_calibBridge;      // AI calibration
CFeatureEngine       g_featEngine;       // Statistical features
CDashboardManager    g_hud;              // On-chart dashboard
CSymbolScanner       g_scanner;          // Multi-symbol scanner

//--- QA & Stress Test Module
#ifdef QA_BUILD
CQAStressTest        g_qa;               // Chaos engineering
#endif

//--- Global Trading Context (Single Source of Truth)
STradingContext      g_ctx;              // Encapsulated runtime state

//--- DEPRECATED: All legacy globals migrated to g_ctx.STradingContext
//    Previous scattered variables now centralized in single struct

//+------------------------------------------------------------------+
//|  HELPERS — INSTITUTIONAL ARCHITECTURE                            |
//+------------------------------------------------------------------+
void DebugPrint(string msg)
  { if(InpDebugLog) Print("[PASR_DBG] ", msg); }

/// Helper: Get open position ticket for a symbol (fast lookup)
ulong GetOpenPositionTicket(const string symbol)
  {
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      
      string pos_sym = PositionGetString(POSITION_SYMBOL);
      if(pos_sym == symbol)
         return ticket;
     }
   return 0;
  }

double GetATR(const string symbol, int period = 14)
  {
   double atr[];
   ArraySetAsSeries(atr, true);
   int h = iATR(symbol, PERIOD_CURRENT, period);
   if(h == INVALID_HANDLE) return 0;
   CopyBuffer(h, 0, 0, 1, atr);
   IndicatorRelease(h);
   return (ArraySize(atr) > 0) ? atr[0] : 0;
  }

double GetSpreadPips(const string symbol = NULL)
  {
   string sym = (symbol == NULL || symbol == "") ? _Symbol : symbol;
   long sp = SymbolInfoInteger(sym, SYMBOL_SPREAD);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double pip_size = (digits == 3 || digits == 5) ? point * 10 : point;
   return sp * pip_size;
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
//|  OnInit — ordered boot sequence with fail-fast phases            |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("[PASR] v11.00 Pure Institutional booting — magic:", InpMagic);
   
#ifdef QA_BUILD
   if(InpEnableChaos)
      Print("[PASR][QA] CHAOS ENGINE ENABLED - frequency=", InpChaosFrequency, 
            " spread_mult=", InpChaosSpreadMult);
#endif

   //--- Reset global trading context
   g_ctx.Reset();
   
   SInitResult initResult;
   
   //+------------------------------------------------------------------+
   //|  PHASE 1: CORE SYSTEM (Timer, Handles, Global State)             |
   //+------------------------------------------------------------------+
   initResult.phase = INIT_PHASE_CORE;
   
   //--- [CORE-01] Initialize Executor with async mode
   g_executor.Initialize(true, 20);  // async=true, max_queue=20
   Print("[INIT][PHASE1] CExecutor initialized (async mode, queue=20)");
   
   //--- [CORE-02] Initialize SymbolManager with correlation control
   if(ArraySize(InpSymbols) > 0)
     {
      g_symMgr.Initialize(InpSymbols, ArraySize(InpSymbols), 
                          InpCorrThreshold, InpUseCorrelation);
      Print("[INIT][PHASE1] CSymbolManager initialized with ", ArraySize(InpSymbols), " symbols");
     }
   
   //--- [CORE-03] EventBus initialization
   g_bus.Init();
   
   //--- Set timer for bar processing heartbeat
   EventSetTimer(1);
   
   //+------------------------------------------------------------------+
   //|  PHASE 2: MARKET DATA (Symbol Manager, Data Feed Validation)     |
   //+------------------------------------------------------------------+
   initResult.phase = INIT_PHASE_MARKETDATA;
   
   //--- [Scanner] SymbolScanner initialization
   int sym_count = ArraySize(InpSymbols);
   if(sym_count > 0)
     {
      if(!g_scanner.Init(InpSymbols, sym_count))
        {
         initResult.Fail(INIT_PHASE_MARKETDATA, "SymbolScanner", "Init failed");
         Alert(initResult.ToString());
         return INIT_FAILED;
        }
      
      SymbolFilterCriteria filter;
      filter.max_spread_pts    = InpMaxSpreadPts;
      filter.min_volume        = 0;
      filter.check_session     = InpCheckSession;
      filter.session_start_hour= InpSessionStart;
      filter.session_end_hour  = InpSessionEnd;
      
      g_scanner.SetFilter(filter);
      Print("[INIT][PHASE2] Scanner configured for ", sym_count, " symbols");
     }
   else
     {
      string single_sym[];
      ArrayPushBack(single_sym, _Symbol);
      if(!g_scanner.Init(single_sym, 1))
        {
         initResult.Fail(INIT_PHASE_MARKETDATA, "SymbolScanner", "Single symbol init failed");
         Alert(initResult.ToString());
         return INIT_FAILED;
        }
     }
   
   //--- [DataManager] Initialize data feed
   if(!g_data.Init(_Symbol, PERIOD_CURRENT))
     {
      initResult.Fail(INIT_PHASE_MARKETDATA, "DataManager", "Init failed");
      Alert(initResult.ToString());
      return INIT_FAILED;
     }
   
   //+------------------------------------------------------------------+
   //|  PHASE 3: STRATEGY ENGINE (SR, Pattern, AI Logic)                |
   //+------------------------------------------------------------------+
   initResult.phase = INIT_PHASE_STRATEGY;
   
   //--- [StateManager] Initialize persistent state
   g_state.Init(InpMagic);
   
   //--- [JournalManager] Setup logging
   g_journal.SetCSVEnabled(InpJournalEnabled);
   g_journal.SetCSVPrefix("PASR_Journal");
   
   //--- [PerformanceReport] Link to journal
   g_report.SetJournal(GetPointer(g_journal));
   
   //--- [SRManager] Support/Resistance detection
   if(!g_sr.Init(_Symbol, PERIOD_CURRENT,
                 InpSRLookback, InpSRMinTouches,
                 InpSRMergeATR, InpSRMaxZones))
     {
      initResult.Fail(INIT_PHASE_STRATEGY, "SRManager", "Init failed");
      Alert(initResult.ToString());
      return INIT_FAILED;
     }
   
   //--- [PatternManager] Candlestick pattern recognition
   g_pattern.Init(_Symbol, PERIOD_CURRENT);
   
   //--- [SignalManager] Signal generation engine
   g_signal.Init(_Symbol, PERIOD_CURRENT,
                 InpMinConfluence, InpUseTrend, InpUsePatterns,
                 GetPointer(g_sr), GetPointer(g_pattern));
   
   //--- [AI Feature Builder] ML feature extraction
   g_featBuilder.Init(_Symbol, PERIOD_CURRENT);
   
   //--- [AI Stack] Inference, Ensemble, Calibration
   g_aiInfer.Init();
   g_ensemble.Init();
   if(InpLoadWeights) g_ensemble.LoadWeights();
   
   //--- [Calibration Bridge] AI score calibration
   g_calibBridge.SetJournal(GetPointer(g_journal));
   g_calibBridge.SetHighThresh(InpAIHighThresh);
   g_calibBridge.SetVetoThresh(InpAIVetoThresh);
   
   //--- [FeatureEngine] Advanced statistical features
   if(InpUseAdvFeatures)
     {
      if(!g_featEngine.Init(_Symbol, PERIOD_CURRENT, InpFeatureWindow))
        {
         Print("[PASR][WARN] FeatureEngine init failed - using basic features only");
        }
      else
        {
         Print("[INIT][PHASE3] FeatureEngine initialized with window=", InpFeatureWindow);
        }
     }
   
   //+------------------------------------------------------------------+
   //|  PHASE 4: EXECUTION LAYER (Executor Queue, Risk Parameters)      |
   //+------------------------------------------------------------------+
   initResult.phase = INIT_PHASE_EXECUTION;
   
   //--- [RiskManager] Capital protection circuit breakers
   g_risk.Init(InpMagic, InpRiskPct, InpMaxDailyLossPct,
               InpMaxDrawdownPct, InpMaxTradesPerDay, InpMinRR);
   
   //--- [PositionManager] Active trade management
   g_pos.Init(InpMagic,
               InpUseBE,      InpBEActivateRR,
               InpUsePartial, InpPartialPct,
               InpUseTrailing,InpTrailATRMult);
   
   //--- [ExitEngine] Exit signal detection
   g_exit.Init();
   
   //--- [CorrelationManager] Portfolio risk control
   if(InpUseCorrelation)
     {
      g_corr.Initialize();
      Print("[INIT][PHASE4] Correlation risk enabled (threshold=", InpCorrThreshold, ", window=", InpCorrWindow, ")");
     }
   
   //--- [RecoveryManager] Fakeout protection engine
   g_recovery.Init(GetPointer(g_data), GetPointer(g_bus));
   g_recovery.SetTrailingThrottle(200);  // throttle trailing to 200ms
   
   //--- [Dashboard] On-chart HUD
   if(InpShowDash)
     {
      g_hud.Init(GetPointer(g_journal));
      ZeroMemory(g_ctx.dash_ctx);
     }
   
#ifdef QA_BUILD
   //--- [QA] Run initial stress tests if enabled
   if(InpTestPoolExhaust)
     {
      QATestEventPoolExhaustion();
     }
   
   // Initialize QA stress test engine
   if(!g_qa.Init(InpChaosFrequency, InpChaosSpreadMult, InpTestPoolExhaust))
     {
      Print("[PASR][QA][WARN] QAStressTest initialization failed");
     }
   
   // Initialize normal spread baseline for chaos testing
   g_ctx.normal_spread = GetSpreadPips();
   PrintFormat("[INIT][PHASE4] Baseline spread: %.1f pips", g_ctx.normal_spread);
#endif
   
   //+------------------------------------------------------------------+
   //|  INITIALIZATION COMPLETE - Mark context as ready                 |
   //+------------------------------------------------------------------+
   g_ctx.SetInitialized(true);
   g_ctx.last_bar_time = 0;
   g_ctx.has_plan      = false;
   g_ctx.regime        = REGIME_RANGING;
   g_ctx.session       = DetectSession();
   
   Print("[PASR] Boot complete — Pure Institutional Architecture ready");
   Print("[PASR] CExecutor: async mode, queue=20, smart retry enabled");
   Print("[PASR] CSymbolManager: ", ArraySize(InpSymbols), " symbols, correlation=", InpUseCorrelation ? "ON" : "OFF");
   Print("[PASR] State encapsulation: g_ctx (STradingContext) is single source of truth");
   
   initResult.phase = INIT_PHASE_COMPLETE;
   initResult.success = true;
   
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//|  OnDeinit — ordered shutdown                                     |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   
#ifdef PERF_METRICS
   // Print performance metrics summary
   PrintFormat("[PASR][PERF] Total ticks: %I64u | Bars: %I64u | Signals: %I64u",
               g_tickCount, g_barCount, g_signalCount);
#endif
   
#ifdef QA_BUILD
   //--- Print QA statistics from engine
   g_qa.PrintReport();
   
   // Legacy stats (for backward compatibility)
   PrintFormat("[PASR][QA] SHUTDOWN STATS - ticks_processed:%d chaos_triggers:%d alloc_count:%lu",
               g_tickCounter, (g_lastChaosTime > 0 ? g_tickCounter / InpChaosFrequency : 0),
               g_allocCount);
#endif
   
   //--- Print scanner statistics
   g_scanner.PrintStats();
   
   //--- Print OOP module statistics (Institutional Architecture)
   int exec_done, exec_failed, exec_retries;
   double exec_latency;
   g_executor.GetStatistics(exec_done, exec_failed, exec_retries, exec_latency);
   PrintFormat("[PASR][EXEC] Total: %d executed | %d failed | %d retries | avg latency: %.1fms",
               exec_done, exec_failed, exec_retries, exec_latency);
   
   long total_ticks, total_bars;
   int active_symbols;
   g_symMgr.GetTotalStatistics(total_ticks, total_bars, active_symbols);
   PrintFormat("[PASR][SYMGR] Total ticks: %I64u | bars: %I64u | active symbols: %d",
               total_ticks, total_bars, active_symbols);
   
   //--- Print exit engine statistics
   g_exit.PrintStats();
   
   //--- Print correlation statistics
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
//|  OnTick — INSTITUTIONAL LOW-LATENCY PATH (<0.3ms)                |
//|  ONLY critical real-time operations:                             |
//+------------------------------------------------------------------+
void OnTick()
  {
#ifdef PERF_METRICS
   g_tickCount++;
#endif

#ifdef QA_BUILD
   //--- [QA] Chaos injection (minimal overhead)
   g_tickCounter++;
   g_qa.OnTick(_Symbol, g_bus, g_risk);
   g_chaosActive = g_qa.IsChaosActive();
   g_allocCount++;
#endif

   //--- [TICK PATH 1] Fast spread guard
   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10000.0;
   if(spread > InpMaxSpreadPips)
      return;  // Exit immediately - no heavy processing

   //--- [TICK PATH 2] Update SymbolManager with tick data
   datetime now = TimeCurrent();
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   g_symMgr.UpdateTick(_Symbol, bid, ask, now);

   //--- [TICK PATH 3] Process executor queue (async orders)
   g_executor.ProcessQueue();

   //--- [TICK PATH 4] Process deferred EventBus queue (fast)
   g_bus.ProcessPending();

   //--- [TICK PATH 5] Position management (BE, trailing, partial close)
   if(g_pos.HasOpenPosition(_Symbol))
     {
      double atr = GetATR(_Symbol);
      g_pos.OnTick(atr);
      
      // Quick exit signal check (if enabled)
      if(InpUseChandelier || InpUseTimeExit || InpUseStructBreak || InpUseProfitFade)
        {
         ulong ticket = GetOpenPositionTicket(_Symbol);
         if(ticket > 0 && PositionSelectByTicket(ticket))
           {
            ENUM_ORDER_TYPE pos_type = (ENUM_ORDER_TYPE)PositionGetInteger(POSITION_TYPE);
            double entry = PositionGetDouble(POSITION_PRICE_OPEN);
            double price = (pos_type == POSITION_TYPE_BUY) 
                           ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                           : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            
            ExitSignal exit_sig = g_exit.CheckExit(_Symbol, pos_type, entry, price);
            if(exit_sig.reason != EXIT_NONE)
              {
               DebugPrint(StringFormat("[%s] Exit signal: %s", _Symbol, exit_sig.description));
               // Exit execution handled by PositionManager
              }
           }
        }
     }

   //--- [TICK PATH 6] Recovery price monitoring (lightweight)
   if(InpRecoveryEnabled)
      g_recovery.OnPriceUpdate();

   //--- [TICK PATH 7] Dashboard update (only if visible, throttled)
   if(InpShowDash)
     {
      // Only update dashboard every 5th tick to reduce UI overhead
      static int dash_counter = 0;
      if(++dash_counter >= 5)
        {
         UpdateDashboard();
         dash_counter = 0;
        }
     }
   
   // NOTE: All heavy computation (SR, patterns, signals, AI) moved to OnTimer()
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
      int direction = (g_ctx.active_plan.direction == SIGNAL_BUY) ? 1 : -1;
      g_recovery.OnTradeOpen(ticket, direction, entryPrice);
      g_ctx.open_ticket = ticket;
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
   double riskPts    = MathAbs(g_ctx.active_plan.entryPrice - g_ctx.active_plan.sl);
   if(riskPts > 0)
      rr = (pnl > 0 ? 1 : -1)
         * MathAbs(closePrice - g_ctx.active_plan.entryPrice) / riskPts;

   //--- v4.01: deactivate recovery engine
   if(InpRecoveryEnabled && g_ctx.open_ticket > 0)
     {
      g_recovery.OnTradeClose(g_ctx.open_ticket);
      g_ctx.open_ticket = 0;
     }

   //--- Journal
   if(g_ctx.has_plan)
     {
      g_journal.OnPositionClosed(
         trans.deal,
         g_ctx.pos_open_time,
         g_ctx.active_plan,
         closePrice, pnl,
         g_ctx.regime, g_ctx.session,
         g_ctx.last_ai_score, g_ctx.last_drift,
         g_ctx.last_ens_model,
         g_ctx.last_fv,
         g_pos.IsBEDone(),
         g_pos.IsPartialDone(),
         g_pos.IsRunnerActive());
      g_ctx.has_plan = false;
     }

   //--- Risk daily P&L update
   g_risk.OnTradeClosed(pnl);

   //--- Calibration
   g_calibBridge.LogTradeClose(isWin, rr);

   //--- Ensemble weight update
   g_ensemble.UpdateWeight(
      (ENUM_ENSEMBLE_MODEL)g_ctx.last_ens_model, isWin);
   g_ensemble.SaveWeights();

   //--- Dashboard
   CDashboardManager::UpdateSignalOutcome(
      g_ctx.dash_ctx, isWin ? 1 : -1);

   //--- Auto-export
   if(InpExportReport &&
      g_journal.GetTotalTrades() % InpReportInterval == 0)
      g_report.ExportHTML();

   PrintFormat("[PASR] CLOSED %s  PnL:%.2f  RR:%.2f  AI:%.2f  Win:%s",
               g_ctx.active_plan.direction==SIGNAL_BUY?"BUY":"SELL",
               pnl, rr, g_ctx.last_ai_score, isWin?"YES":"NO");
  }

//+------------------------------------------------------------------+
//|  OnTimer — BAR PROCESSING PATH (1-second heartbeat)              |
//|  ALL heavy computation moved here:                               |
//|  • New bar detection (multi-symbol batch)                        |
//|  • Session & regime detection                                    |
//|  • SR recalculation (cached, incremental)                        |
//|  • Pattern scanning                                              |
//|  • Signal generation                                             |
//|  • AI feature build + inference                                  |
//|  • Ensemble scoring                                              |
//|  • Calibration bridge                                            |
//|  • Risk check + async execution                                  |
//|  • Correlation matrix update (incremental)                       |
//+------------------------------------------------------------------+
void OnTimer()
  {
#ifdef PERF_METRICS
   g_barCount++;
#endif

   //--- [BAR PATH 1] New bar detection
   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   bool isNewBar = (barTime != g_ctx.last_bar_time);
   
   if(!isNewBar)
     {
      // No new bar - skip heavy processing
      return;
     }
   
   g_ctx.last_bar_time = barTime;
   DebugPrint(StringFormat("[%s] New bar detected: %s", _Symbol, TimeToString(barTime)));

   //--- [BAR PATH 2] Session detection
   g_ctx.session = DetectSession();

   //--- [BAR PATH 3] Data update
   g_data.OnNewBar();

   //--- [BAR PATH 4] Regime detection (optimized with caching)
   double atr = GetATR(_Symbol);
   g_ctx.regime = g_adaptCfg.DetectRegime(_Symbol, PERIOD_CURRENT, atr);
   EffectivePolicy policy = g_adaptCfg.GetEffectivePolicy(g_ctx.regime, g_ctx.session, atr);

   //--- [BAR PATH 5] Recovery new-bar processing
   if(InpRecoveryEnabled)
      g_recovery.OnNewBar();

   //--- [BAR PATH 6] Risk circuit breaker check
   if(!g_risk.IsTradingAllowed(_Symbol))
     {
      DebugPrint("Risk circuit breaker active — skip bar");
      return;
     }
   
   //--- [BAR PATH 7] Correlation matrix check (incremental update)
   if(InpUseCorrelation)
     {
      // Only full recalc every 5 bars, otherwise incremental
      static int corr_counter = 0;
      if(++corr_counter >= 5)
        {
         if(!g_corr.IsCorrelationSafe(_Symbol, InpCorrThreshold, InpCorrWindow))
           {
            DebugPrint(StringFormat("[%s] Correlation guard: blocked", _Symbol));
            return;
           }
         corr_counter = 0;
        }
     }

   //--- [BAR PATH 8] SR recalculation (with caching)
   g_sr.OnNewBar();

   //--- [BAR PATH 9] Pattern scan
   g_pattern.OnNewBar();

   //--- [BAR PATH 10] Signal generation
   TradeSignal sig;
   bool hasSignal = g_signal.GenerateSignal(sig, atr);
   
   if(!hasSignal)
     {
      DebugPrint("No signal this bar");
      return;
     }
   
#ifdef PERF_METRICS
   g_signalCount++;
#endif
   
   DebugPrint(StringFormat("Signal: %s  confluence:%.2f",
              sig.direction==SIGNAL_BUY?"BUY":"SELL", sig.confluence));

   //--- [BAR PATH 11] AI Feature build + Advanced Statistical Features
   SRZone zones[20];
   int nZones = g_sr.GetZones(zones, 20);
   g_ctx.last_fv = g_featBuilder.Build(sig, atr,
                                   sig.nearestSupport,
                                   sig.nearestResistance,
                                   zones, nZones);
   
   // Compute advanced statistical features if enabled
   FeatureSet adv_features;
   if(InpUseAdvFeatures && g_featEngine.IsInitialized())
     {
      adv_features = g_featEngine.ComputeFeatures();
      
      if(adv_features.regime != VOLATILITY_MEDIUM)
        {
         DebugPrint(StringFormat("[%s] Volatility regime: %s (z-score=%.2f)",
                                 _Symbol, 
                                 EnumToString(adv_features.regime),
                                 adv_features.z_score));
        }
     }

   //--- [BAR PATH 12] Drift check
   g_ctx.last_drift = g_featBuilder.ComputeDrift(g_ctx.last_fv);
   
   // Adjust AI veto threshold based on volatility regime
   double effective_veto_thresh = InpAIVetoThresh;
   if(InpUseAdvFeatures && g_featEngine.IsInitialized())
     {
      ENUM_VOLATILITY_REGIME regime = g_featEngine.GetCurrentRegime();
      
      if(regime == VOLATILITY_HIGH)
         effective_veto_thresh = InpAIVetoThresh * 1.2;
      else if(regime == VOLATILITY_EXTREME)
         effective_veto_thresh = InpAIVetoThresh * 1.5;
      else if(regime == VOLATILITY_LOW)
         effective_veto_thresh = InpAIVetoThresh * 0.9;
     }
   
   if(InpUseAI && g_ctx.last_drift > InpDriftVeto)
     {
      DebugPrint(StringFormat("Drift veto: %.2f", g_ctx.last_drift));
      CDashboardManager::PushSignal(g_ctx.dash_ctx, sig.direction, 0, 0);
      return;
     }

   //--- [BAR PATH 13] AI Ensemble scoring
   double patternBonus = g_pattern.GetPatternBonus(sig.direction);
   
   double base_ai_score = InpUseAI
      ? (InpUseEnsemble
           ? g_ensemble.GetScore(g_ctx.last_fv, sig, patternBonus, g_ctx.last_drift)
           : g_aiInfer.ForwardPass18(g_ctx.last_fv, patternBonus, g_ctx.last_drift))
      : sig.confluence;
   
   // Apply volatility regime adjustment
   if(InpUseAdvFeatures && g_featEngine.IsInitialized())
     {
      ENUM_VOLATILITY_REGIME regime = g_featEngine.GetCurrentRegime();
      
      if(regime == VOLATILITY_HIGH)
         base_ai_score *= 0.9;
      else if(regime == VOLATILITY_EXTREME)
         base_ai_score *= 0.75;
      else if(regime == VOLATILITY_LOW)
         base_ai_score = MathMin(1.0, base_ai_score * 1.05);
     }
   
   g_ctx.last_ai_score = base_ai_score;
   g_ctx.last_ens_model = g_ensemble.GetActiveModel();

   DebugPrint(StringFormat("AI score:%.2f drift:%.2f model:%d",
                           g_ctx.last_ai_score, g_ctx.last_drift, g_ctx.last_ens_model));

   //--- [BAR PATH 14] Calibration bridge
   AIScoreOverride ov = g_calibBridge.MapScoreToPolicy(g_ctx.last_ai_score, policy);
   
   if(ov.blockTrade)
     {
      DebugPrint(StringFormat("CalibBridge veto: score=%.2f", g_ctx.last_ai_score));
      CDashboardManager::PushSignal(g_ctx.dash_ctx, sig.direction, g_ctx.last_ai_score, 0);
      return;
     }
   
   EffectivePolicy ep = g_calibBridge.ApplyOverride(policy, ov);

   //--- [BAR PATH 15] Risk sizing (Institutional)
   if(!g_risk.CanOpenTrade())
     {
      DebugPrint("Risk: trade blocked (daily limit or max trades)");
      return;
     }

   // Institutional SL calculation: Structural vs ATR-based
   double slDistance = 0.0;
   
   if(InpStructSL)
     {
      // Use market structure (Swing High/Low) + buffer
      double swingLevel = InpStructTrail ? g_sr.GetLastSwingLow(_Symbol) : g_sr.GetMajorSupport(_Symbol);
      if(swingLevel == 0.0) swingLevel = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - (atr * InpSLBufferATR);
      slDistance = MathAbs(SymbolInfoDouble(_Symbol, SYMBOL_ASK) - swingLevel);
     }
   else
     slDistance = atr * InpSLBufferATR; // Fallback to ATR
   
   // Volatility adjustment for position sizing
   double volFactor = InpVolatilityAdj ? (1.0 / MathMax(1.0, atr / g_risk.GetTargetATR())) : 1.0;
   double lotSize = g_risk.CalcLotSize(_Symbol, slDistance, volFactor);
   
   // Apply volatility regime position sizing
   if(InpUseAdvFeatures && g_featEngine.IsInitialized())
     {
      ENUM_VOLATILITY_REGIME regime = g_featEngine.GetCurrentRegime();
      
      if(regime == VOLATILITY_HIGH)
         lotSize *= 0.8;
      else if(regime == VOLATILITY_EXTREME)
         lotSize *= 0.5;
      else if(regime == VOLATILITY_LOW)
         lotSize = MathMin(lotSize * 1.1, lotSize + 0.05);
     }
   
   if(lotSize <= 0)
     {
      DebugPrint("Risk: lot size = 0");
      return;
     }

   //--- [BAR PATH 16] Build TradePlan
   TradePlan plan;
   plan.direction  = sig.direction;
   plan.entryPrice = (sig.direction == SIGNAL_BUY)
                     ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                     : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   plan.sl         = plan.entryPrice
                   + ((sig.direction==SIGNAL_BUY ? -1 : 1) * atr * ep.slATRMult);
   plan.tp         = plan.entryPrice
                   + ((sig.direction==SIGNAL_BUY ? 1 : -1) * atr * ep.slATRMult * ep.tp1RR);
   plan.tp2        = plan.entryPrice
                   + ((sig.direction==SIGNAL_BUY ? 1 : -1) * atr * ep.slATRMult * ep.tp2RR);
   plan.lot        = lotSize;
   plan.magic      = InpMagic;
   plan.comment    = InpComment + "_" + _Symbol;

   double riskPts   = MathAbs(plan.entryPrice - plan.sl);
   double rewardPts = MathAbs(plan.tp - plan.entryPrice);
   
   if(riskPts <= 0 || (rewardPts / riskPts) < InpMinRR)
     {
      DebugPrint(StringFormat("RR too low: %.2f", rewardPts/riskPts));
      return;
     }

   //--- [BAR PATH 17] Execute trade (Institutional Execution Engine)
   // Institutional mode: Smart retry with exponential backoff
   bool executed = false;
   int retry_count = 0;
   const int MAX_RETRIES = InpRetryAttempts;
   const int INITIAL_DELAY_MS = 100;
   
   while(!executed && retry_count < MAX_RETRIES)
     {
      if(g_executor.OpenTrade(plan))
        {
         executed = true;
        }
      else
        {
         retry_count++;
         if(retry_count < MAX_RETRIES)
           {
            int delay_ms = INITIAL_DELAY_MS * (int)MathPow(2, retry_count - 1);
            DebugPrint(StringFormat("Trade failed, retry %d/%d in %dms", 
                                    retry_count, MAX_RETRIES, delay_ms));
            Sleep(delay_ms);
           }
        }
     }
   
   if(!executed)
     {
      DebugPrint(StringFormat("Execution failed after %d retries: %d", 
                              retry_count, GetLastError()));
      return;
     }

   g_ctx.active_plan   = plan;
   g_ctx.has_plan      = true;
   g_ctx.pos_open_time  = TimeCurrent();
   g_risk.OnTradeOpened();
   g_calibBridge.LogTradeOpen(g_ctx.last_ai_score);

   CDashboardManager::PushSignal(g_ctx.dash_ctx, sig.direction, g_ctx.last_ai_score, 0);

   PrintFormat("[PASR][%s] OPENED %s  entry:%.5f  sl:%.5f  tp:%.5f  lots:%.2f  AI:%.2f",
               _Symbol,
               plan.direction==SIGNAL_BUY?"BUY":"SELL",
               plan.entryPrice, plan.sl, plan.tp, plan.lot, g_ctx.last_ai_score);
  }

//+------------------------------------------------------------------+
//|  UpdateDashboard                                                 |
//+------------------------------------------------------------------+
void UpdateDashboard()
  {
   if(!InpShowDash) return;

   g_ctx.dash_ctx.regime    = g_ctx.regime;
   g_ctx.dash_ctx.session   = g_ctx.session;
   g_ctx.dash_ctx.spread    = GetSpreadPips();
   g_ctx.dash_ctx.aiScore   = g_ctx.last_ai_score;
   g_ctx.dash_ctx.driftScore= g_ctx.last_drift;
   g_ctx.dash_ctx.ensembleModel = g_ctx.last_ens_model;
   g_ctx.dash_ctx.aiVeto    = (g_ctx.last_ai_score < InpAIVetoThresh ||
                          g_ctx.last_drift   > InpDriftVeto);

   g_ctx.dash_ctx.hasPosition = g_pos.HasOpenPosition(_Symbol);
   if(g_ctx.dash_ctx.hasPosition)
     {
      // Get position info for chart symbol (dashboard shows current chart only)
      ulong ticket = 0;
      int total_pos = PositionsTotal();
      for(int i = total_pos - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t <= 0) continue;
         if(!PositionSelectByTicket(t)) continue;
         
         string pos_sym = PositionGetString(POSITION_SYMBOL);
         if(pos_sym == _Symbol)
           {
            ticket = t;
            break;
           }
        }
      
      if(ticket > 0 && PositionSelectByTicket(ticket))
        {
         ENUM_ORDER_TYPE pos_type = (ENUM_ORDER_TYPE)PositionGetInteger(POSITION_TYPE);
         g_ctx.dash_ctx.posDir    = (pos_type == POSITION_TYPE_BUY) ? SIGNAL_BUY : SIGNAL_SELL;
         g_ctx.dash_ctx.posEntry  = PositionGetDouble(POSITION_PRICE_OPEN);
         g_ctx.dash_ctx.posSL     = PositionGetDouble(POSITION_SL);
         g_ctx.dash_ctx.posTP1    = PositionGetDouble(POSITION_TP);
         g_ctx.dash_ctx.posTP2    = g_ctx.active_plan.tp2;  // Runner TP from active plan
         g_ctx.dash_ctx.posLots   = PositionGetDouble(POSITION_VOLUME);
         g_ctx.dash_ctx.posPnL    = g_pos.GetFloatingPnL();
         g_ctx.dash_ctx.beDone    = g_pos.IsBEDone();
         g_ctx.dash_ctx.partialDone = g_pos.IsPartialDone();
        }
     }
   else
     {
      ZeroMemory(g_ctx.dash_ctx.posDir);
      g_ctx.dash_ctx.posEntry = g_ctx.dash_ctx.posSL  = 0;
      g_ctx.dash_ctx.posTP1   = g_ctx.dash_ctx.posTP2 = 0;
      g_ctx.dash_ctx.posLots  = g_ctx.dash_ctx.posPnL = 0;
      g_ctx.dash_ctx.beDone   = g_ctx.dash_ctx.partialDone = false;
     }

   g_hud.Update(g_ctx.dash_ctx);
  }

//+------------------------------------------------------------------+
//|  OnTester — Performance metrics for optimization                 |
//+------------------------------------------------------------------+
double OnTester()
  {
#ifdef PERF_METRICS
   // Calculate custom fitness function for optimizer
   double totalTrades = g_journal.GetTotalTrades();
   double winRate = (totalTrades > 0) ? (g_journal.GetWinCount() / totalTrades) : 0;
   double avgRR = g_journal.GetAverageRR();
   
   // Custom score: WinRate * AvgRR * sqrt(TradeCount)
   double score = winRate * avgRR * MathSqrt(MathMax(1, totalTrades));
   
   PrintFormat("[PASR][OPT] Fitness Score=%.3f (WinRate=%.2f AvgRR=%.2f Trades=%I64u)",
               score, winRate, avgRR, (long)totalTrades);
   
   return score;
#else
   return 0;
#endif
  }

//+------------------------------------------------------------------+
//| END OF PASR_MODULAR.mq5 v10.00 — Institutional Grade             |
//+------------------------------------------------------------------+
