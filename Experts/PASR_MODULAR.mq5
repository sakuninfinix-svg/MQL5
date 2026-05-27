//+------------------------------------------------------------------+
//|  PASR_MODULAR.mq5                                                |
//|  Expert Advisor: PASR (Price Action Support Resistance)          |
//|  Version: 13.01 — BUG-008 fix: QA macro consistency             |
//|  Refactored: Centralized includes, removed dual-core conflict    |
//+------------------------------------------------------------------+
#property copyright   "PASR EA © 2026"
#property link        "https://github.com/sakuninfinix-svg/MQL5"
#property version     "13.01"
#property description "PASR Model - Pure Pipeline Architecture (v13.01)"
#property strict

//--- Compilation Flags (controlled via master include)
// BUG-008 FIX: Renamed QA_BUILD -> PASR_QA_BUILD to match #ifdef guards
// in PASR.mqh, Orchestrator.mqh, PipelineEngine.mqh.
// QA modules (LatencySimulator, CQAStressTest, chaos engine) were previously
// silently excluded from every build despite the flag being set.
#define PASR_QA_BUILD     // Enable stress testing & chaos engineering
// Issue #181 FIX: PERF_METRICS removed — legacy flag no longer used.
// Performance metrics now handled via canonical TelemetryRecorder/PerformanceReport.

//--- SINGLE MASTER INCLUDE - All dependencies managed centrally
#include <PASR/Core/PASR.mqh>

//--- QA Module (standalone - not part of orchestrator pipeline)
#ifdef PASR_QA_BUILD
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
input bool     InpEnableChaos     = false;  // Randomly Inject Errors if PASR_QA_BUILD
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
//|  MODULE INSTANCES — PURE ORCHESTRATOR PIPELINE (v13.01)          |
//+------------------------------------------------------------------+
// ARCHITECTURE v13.01 IMPROVEMENTS (on top of v13.00):
// ✓ BUG-008: Renamed QA_BUILD → PASR_QA_BUILD (macro consistency)
// --- v13.00 ---
// ✓ Centralized includes via PASR.mqh master header
// ✓ Removed chaotic dependency includes from EA file
// ✓ Dual Execution Engine resolved: Single CExecutionManager in Orchestrator
// ✓ OnTimer() pipelined via CPipelineEngine with profiling
// ✓ Global Runtime State contained: Only g_ctx for EA-level state
// ✓ Event handlers are thin delegates (no business logic)
// ✓ Managers decoupled: Only communicate via EventBus + Orchestrator
// ✓ Dashboard isolated: Updated via events, not direct runtime access
// ✓ Logging centralized: CJournalManager via EventBus
// ✓ Indicator lifecycle managed: DataManager handles indicator handles
// ✓ Pipeline profiling-aware: CPipelineEngine with StageMetrics
// ✓ Position management async: RecoveryManager handles async operations

//--- PIPELINE CORE: Single orchestrator owns all modules
COrchestrator        g_orch;             // Main pipeline coordinator (SOLE owner of all managers)

//--- AI ORCHESTRATOR: Dynamic Strategy Brain (v14.01)
// Direct reference for low-latency strategy decisions
CAIOrchestrator     *g_aiOrch = NULL;    // Will be initialized from g_orch.GetAIOrchestrator()

//--- QA & Stress Test Module (standalone - not part of orchestrator)
#ifdef PASR_QA_BUILD
CQAStressTest        g_qa;               // Chaos engineering (external QA tool)
#endif

//--- Global Trading Context (Minimal EA-level state ONLY)
// CONSTRAINT: Manager state MUST be encapsulated within COrchestrator
// This struct is ONLY for EA-level bookkeeping (e.g., shutdown flags)
struct SEAState
  {
   bool              initialized;
   bool              shutdown_requested;
   datetime          last_tick;
   
   void Reset()
     {
      initialized = false;
      shutdown_requested = false;
      last_tick = 0;
     }
  };
SEAState             g_state;            // Minimal EA state (not manager state)

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

// FIX #2: Removed GetATR() helper - was creating/destroying indicator handles
// on every call, causing handle spam. Use m_data.GetATRPoints() instead which
// caches the ATR value per tick.

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

#ifdef PASR_QA_BUILD
//+------------------------------------------------------------------+
//|  QA Stress Test Helpers                                          |
//+------------------------------------------------------------------+

/// Force EventPool exhaustion test - triggers fallback path
void QATestEventPoolExhaustion()
  {
   Print("[PASR][QA] Testing EventPool exhaustion fallback...");
   
   const int POOL_CAPACITY = 256;
   const int EXHAUST_COUNT = POOL_CAPACITY + 50;
   
   int success_count = 0;
   for(int i = 0; i < EXHAUST_COUNT; i++)
     {
      if(g_orch.GetDataManager().GetEventBus().CreateEvent(EVENT_TICK))
         success_count++;
     }
   
   PrintFormat("[PASR][QA] Exhaustion test: created %d/%d events (pool should have fallen back to heap)",
               success_count, EXHAUST_COUNT);
   
   g_orch.GetDataManager().GetEventBus().ProcessPending();
   
   Print("[PASR][QA] EventPool exhaustion test complete - no crashes = PASS");
  }

/// Manually trigger a circuit breaker to validate RiskManager response
void QATestCircuitBreaker(ENUM_RISK_CB_TYPE cb_type)
  {
   Print("[PASR][QA] Manually triggering circuit breaker: ", EnumToString(cb_type));
   
   switch(cb_type)
     {
      case RISK_CB_DAILY_LOSS:
         g_orch.GetRiskManager().OnTradeClosed(-10000.0);
         break;
      case RISK_CB_MAX_DRAWDOWN:
         Print("[PASR][QA] Drawdown CB test requires state manipulation");
         break;
      case RISK_CB_SPREAD:
         Print("[PASR][QA] Spread CB already tested via chaos engine");
         break;
      default:
         Print("[PASR][QA] Unknown CB type");
     }
   
   bool allowed = g_orch.GetRiskManager().IsTradingAllowed();
   PrintFormat("[PASR][QA] After CB trigger - Trading allowed: %s", allowed ? "YES" : "NO");
  }
#endif

//+------------------------------------------------------------------+
//|  OnInit — PURE ORCHESTRATOR DELEGATION (<10 lines)               |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("[PASR] v13.01 Pure Pipeline Architecture booting...");
   
#ifdef PASR_QA_BUILD
   if(InpEnableChaos)
      Print("[PASR][QA] CHAOS ENGINE ENABLED - frequency=", InpChaosFrequency, 
            " spread_mult=", InpChaosSpreadMult);
#endif

   g_state.Reset();
   
   int result = g_orch.Init();
   
   if(result != INIT_SUCCEEDED)
     {
      Alert("[PASR] Initialization FAILED - check Experts log");
      return INIT_FAILED;
     }
   
   // AI ORCHESTRATOR INTEGRATION (v14.01): Get direct reference for low-latency decisions
   g_aiOrch = g_orch.GetAIOrchestrator();
   if(g_aiOrch == NULL)
     {
      Alert("[PASR] CRITICAL: AI Orchestrator not available");
      return INIT_FAILED;
     }
   
   // Configure AI with user parameters
   g_aiOrch->ConfigureParameters(InpUseAI, InpAIVetoThresh, InpDriftVeto, InpAIHighThresh);
   
   g_orch.SetDebugMode(InpDebugLog);
   g_orch.SetProfilingEnabled(true);
   
   EventSetTimer(1);
   
   g_state.initialized = true;
   
   Print("[PASR] Boot complete — Pure Pipeline Architecture ready");
   Print("[PASR] Pipeline profiling: ENABLED");
   Print("[PASR] All modules encapsulated in COrchestrator");
   Print("[PASR] Event handlers delegate exclusively to g_orch");
   Print("[PASR] AI Orchestrator v14.01: Dynamic Strategy Brain ACTIVE");
   
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//|  OnDeinit — PURE ORCHESTRATOR DELEGATION (<10 lines)             |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(!g_state.initialized) return;
   g_state.shutdown_requested = true;
   
   EventKillTimer();
   
#ifdef PASR_QA_BUILD
   g_qa.PrintReport();
#endif
   
   g_orch.OnDeinit(reason);
   
   g_state.Reset();
   
   if(InpShowDash && InpExportReport) 
      Print("[PASR] Final report exported");
   
   PrintFormat("[PASR] Shutdown — reason:%d", reason);
  }

//+------------------------------------------------------------------+
//|  OnTick — PURE ORCHESTRATOR DELEGATION (<10 lines)               |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!g_state.initialized) return;
   
   g_state.last_tick = TimeCurrent();
   
#ifdef PASR_QA_BUILD
   g_qa.OnTick(_Symbol, g_orch.GetDataManager().GetEventBus(), g_orch.GetRiskManager());
#endif
   
   g_orch.OnTick();
  }

//+------------------------------------------------------------------+
//|  OnTimer — PURE ORCHESTRATOR DELEGATION (<10 lines)              |
//+------------------------------------------------------------------+
void OnTimer()
  {
   if(!g_state.initialized) return;
   g_orch.OnTimer();
  }

//+------------------------------------------------------------------+
//|  OnTradeTransaction — PURE ORCHESTRATOR DELEGATION (<10 lines)   |
//+------------------------------------------------------------------+
void OnTradeTransaction(
      const MqlTradeTransaction &trans,
      const MqlTradeRequest     &req,
      const MqlTradeResult      &res)
  {
   if(!g_state.initialized) return;
   g_orch.OnTradeTransaction(trans, req, res);
  }

//+------------------------------------------------------------------+
//|  OnChartEvent — PURE ORCHESTRATOR DELEGATION                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int    id,
                  const long   &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   if(!g_state.initialized) return;
   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      CDashboardManager *dash = g_orch.GetDashboard();
      if(dash != NULL) dash.OnChartEvent(id, lparam, dparam, sparam);
     }
  }
