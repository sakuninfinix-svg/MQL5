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
//|  MODULE INSTANCES — PURE ORCHESTRATOR PIPELINE (v12.00)          |
//+------------------------------------------------------------------+
// ARCHITECTURE CHANGE: All modules now owned and coordinated by g_orchestrator
// - COrchestrator encapsulates ALL managers (Data, SR, Pattern, Signal, AI, Risk, Exec, etc.)
// - EA event handlers delegate to g_orchestrator exclusively
// - Zero direct module calls from EA = clean separation of concerns
// - Single execution engine: CExecutionManager inside Orchestrator
// - No dual-core conflict, no spaghetti code, true pipeline architecture

//--- PIPELINE CORE: Single orchestrator owns all modules
COrchestrator        g_orch;             // Main pipeline coordinator (SOLE owner of all managers)

//--- DEPRECATED: Direct module instances REMOVED (now private members of COrchestrator)
// Previous instances caused dual-core conflict and spaghetti dependencies:
//   CExecutor, CSymbolManager, CEventBus, CDataManager, CStateManager,
//   CAdaptiveConfig, CJournalManager, CPerformanceReport, CSRManager,
//   CPatternManager, CSignalManager, CRiskManager, CPositionManager,
//   CExitEngine, CCorrelationManager, CRecoveryManager, CAIFeatureBuilder,
//   CAIInference, CAIEnsemble, CAICalibrationBridge, CFeatureEngine,
//   CDashboardManager, CSymbolScanner
// 
// Migration mapping (orchestrator methods):
//   g_executor.OpenTrade()     → g_orch.OnTimer() [internal exec.Execute()]
//   g_symMgr.Update()          → g_orch.OnTick() [internal data.OnTick()]
//   g_signal.GenerateSignal()  → g_orch.ProcessNewBar() [internal signal.GetCurrent()]
//   g_risk.IsTradingAllowed()  → g_orch.ProcessNewBar() [internal risk.Check()]
//   g_pos.OnTick()             → g_orch.OnTick() [internal recovery.OnTick()]
//   ... all other modules ...  → Delegated internally by COrchestrator

//--- QA & Stress Test Module (standalone - not part of orchestrator)
#ifdef QA_BUILD
CQAStressTest        g_qa;               // Chaos engineering (external QA tool)
#endif

//--- Global Trading Context (Single Source of Truth for EA state only)
// NOTE: Manager state is encapsulated within COrchestrator
STradingContext      g_ctx;              // EA-level runtime state (minimal)

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
      // Try to create events directly via Orchestrator's EventBus
      // If pool is exhausted, should fall back to heap allocation
      if(g_orch.GetDataManager().GetEventBus().CreateEvent(EVENT_TICK))
         success_count++;
     }
   
   PrintFormat("[PASR][QA] Exhaustion test: created %d/%d events (pool should have fallen back to heap)",
               success_count, EXHAUST_COUNT);
   
   // Process all pending events to clean up
   g_orch.GetDataManager().GetEventBus().ProcessPending();
   
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
         g_orch.GetRiskManager().OnTradeClosed(-10000.0); // Large fake loss
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
   bool allowed = g_orch.GetRiskManager().IsTradingAllowed();
   PrintFormat("[PASR][QA] After CB trigger - Trading allowed: %s", allowed ? "YES" : "NO");
  }
#endif

//+------------------------------------------------------------------+
//|  OnInit — PURE ORCHESTRATOR DELEGATION (<10 lines)               |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("[PASR] v12.00 Pure Orchestrator Pipeline booting...");
   
#ifdef QA_BUILD
   if(InpEnableChaos)
      Print("[PASR][QA] CHAOS ENGINE ENABLED - frequency=", InpChaosFrequency, 
            " spread_mult=", InpChaosSpreadMult);
#endif

   //--- Reset global trading context (EA-level state only)
   g_ctx.Reset();
   
   //--- Delegate ALL initialization to Orchestrator
   int result = g_orch.Init();
   
   if(result != INIT_SUCCEEDED)
     {
      Alert("[PASR] Initialization FAILED - check Experts log");
      return INIT_FAILED;
     }
   
   //--- Set Orchestrator debug mode if enabled
   g_orch.SetDebugMode(InpDebugLog);
   
   Print("[PASR] Boot complete — Pure Orchestrator Architecture ready");
   Print("[PASR] All modules encapsulated in COrchestrator");
   Print("[PASR] Event handlers delegate exclusively to g_orch");
   
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//|  OnDeinit — PURE ORCHESTRATOR DELEGATION (<10 lines)             |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   
#ifdef QA_BUILD
   //--- Print QA statistics from engine
   g_qa.PrintReport();
#endif
   
   //--- Delegate ALL deinitialization to Orchestrator
   g_orch.OnDeinit(reason);
   
   //--- EA-level cleanup only
   if(InpShowDash && InpExportReport) 
      Print("[PASR] Final report exported");
   
   PrintFormat("[PASR] Shutdown — reason:%d", reason);
  }

//+------------------------------------------------------------------+
//|  OnTick — PURE ORCHESTRATOR DELEGATION (<10 lines)               |
//+------------------------------------------------------------------+
void OnTick()
  {
#ifdef QA_BUILD
   //--- [QA] Chaos injection (minimal overhead)
   g_qa.OnTick(_Symbol, g_orch.GetDataManager().GetEventBus(), g_orch.GetRiskManager());
#endif
   
   //--- Delegate ALL tick processing to Orchestrator
   g_orch.OnTick();
   
   // NOTE: All position management, recovery, dashboard updates handled internally by COrchestrator
  }

//+------------------------------------------------------------------+
//|  OnTradeTransaction — PURE ORCHESTRATOR DELEGATION (<10 lines)   |
//+------------------------------------------------------------------+
void OnTradeTransaction(
      const MqlTradeTransaction &trans,
      const MqlTradeRequest     &req,
      const MqlTradeResult      &res)
  {
   //--- Delegate ALL trade transaction processing to Orchestrator
   g_orch.OnTradeTransaction(trans, req, res);
   
   // NOTE: Journal, recovery, calibration, ensemble updates handled internally by COrchestrator
  }

//+------------------------------------------------------------------+
//|  OnTimer — PURE ORCHESTRATOR DELEGATION (<10 lines)              |
//+------------------------------------------------------------------+
void OnTimer()
  {
   //--- Delegate ALL bar processing to Orchestrator (ProcessNewBar internally)
   g_orch.OnTimer();
   
   // NOTE: SR, patterns, signals, AI, risk check, execution all handled internally by COrchestrator
  }

//+------------------------------------------------------------------+
//|  UpdateDashboard — DEPRECATED (moved to Orchestrator)            |
//+------------------------------------------------------------------+
// void UpdateDashboard() - REMOVED: Dashboard updates now handled internally by COrchestrator.OnTick()
// All legacy helper functions using direct module calls have been eliminated.
// Migration: Dashboard logic moved to COrchestrator::OnTick() → m_dash.Update()

//+------------------------------------------------------------------+
//|  END OF FILE — Pure Orchestrator Architecture Complete           |
//+------------------------------------------------------------------+
   
