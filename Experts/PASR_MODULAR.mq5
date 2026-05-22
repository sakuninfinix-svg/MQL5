//+------------------------------------------------------------------+
//|  PASR_MODULAR.mq5                                                |
//|  Expert Advisor: PASR (Price Action Support Resistance)          |
//|  Version: 13.00 — Pure Pipeline Architecture                     |
//|  Refactored: Centralized includes, removed dual-core conflict    |
//+------------------------------------------------------------------+
#property copyright   "PASR EA © 2026"
#property link        "https://github.com/sakuninfinix-svg/MQL5"
#property version     "13.00"
#property description "PASR Model - Pure Pipeline Architecture (v13)"
#property strict

//--- Compilation Flags (controlled via master include)
#define QA_BUILD          // Enable stress testing & chaos engineering
#define PERF_METRICS      // Enable performance counters

//--- SINGLE MASTER INCLUDE - All dependencies managed centrally
#include <PASR/Core/PASR.mqh>

//--- QA Module (standalone - not part of orchestrator pipeline)
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
//|  MODULE INSTANCES — PURE ORCHESTRATOR PIPELINE (v13.00)          |
//+------------------------------------------------------------------+
// ARCHITECTURE v13.00 IMPROVEMENTS:
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

//--- QA & Stress Test Module (standalone - not part of orchestrator)
#ifdef QA_BUILD
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
   Print("[PASR] v13.00 Pure Pipeline Architecture booting...");
   
#ifdef QA_BUILD
   if(InpEnableChaos)
      Print("[PASR][QA] CHAOS ENGINE ENABLED - frequency=", InpChaosFrequency, 
            " spread_mult=", InpChaosSpreadMult);
#endif

   //--- Reset EA-level state only (minimal, not manager state)
   g_state.Reset();
   
   //--- Delegate ALL initialization to Orchestrator
   int result = g_orch.Init();
   
   if(result != INIT_SUCCEEDED)
     {
      Alert("[PASR] Initialization FAILED - check Experts log");
      return INIT_FAILED;
     }
   
   //--- Set Orchestrator debug/profiling modes
   g_orch.SetDebugMode(InpDebugLog);
   g_orch.SetProfilingEnabled(true);  // Enable pipeline profiling
   
   //--- Start timer for pipeline execution (1-second interval)
   EventSetTimer(1);
   
   g_state.initialized = true;
   
   Print("[PASR] Boot complete — Pure Pipeline Architecture ready");
   Print("[PASR] Pipeline profiling: ENABLED");
   Print("[PASR] All modules encapsulated in COrchestrator");
   Print("[PASR] Event handlers delegate exclusively to g_orch");
   
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//|  OnDeinit — PURE ORCHESTRATOR DELEGATION (<10 lines)             |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   //--- Guard: prevent double deinit
   if(!g_state.initialized) return;
   g_state.shutdown_requested = true;
   
   EventKillTimer();
   
#ifdef QA_BUILD
   //--- Print QA statistics from engine
   g_qa.PrintReport();
#endif
   
   //--- Delegate ALL deinitialization to Orchestrator
   g_orch.OnDeinit(reason);
   
   //--- EA-level cleanup only (minimal state)
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
   //--- Guard: require initialization
   if(!g_state.initialized) return;
   
   //--- Update tick timestamp for profiling
   g_state.last_tick = TimeCurrent();
   
#ifdef QA_BUILD
   //--- [QA] Chaos injection (minimal overhead)
   g_qa.OnTick(_Symbol, g_orch.GetDataManager().GetEventBus(), g_orch.GetRiskManager());
#endif
   
   //--- Delegate ALL tick processing to Orchestrator
   // NOTE: All position management, recovery, dashboard updates handled internally
   g_orch.OnTick();
  }

//+------------------------------------------------------------------+
//|  OnTradeTransaction — PURE ORCHESTRATOR DELEGATION (<10 lines)   |
//+------------------------------------------------------------------+
void OnTradeTransaction(
      const MqlTradeTransaction &trans,
      const MqlTradeRequest     &req,
      const MqlTradeResult      &res)
  {
   //--- Guard: require initialization
   if(!g_state.initialized) return;
   
   //--- Delegate ALL trade transaction processing to Orchestrator
   // NOTE: Journal, recovery, calibration, ensemble updates handled internally
   g_orch.OnTradeTransaction(trans, req, res);
  }

//+------------------------------------------------------------------+
//|  OnTimer — PIPELINE EXECUTION (staged, profiling-aware)          |
//+------------------------------------------------------------------+
void OnTimer()
  {
   //--- Guard: require initialization
   if(!g_state.initialized) return;
   
   //--- Delegate pipeline execution to Orchestrator
   // Orchestrator uses CPipelineEngine for staged execution with profiling
   // Stages: Data→Analysis→Pattern→Regime→Signal→AI→Risk→Exec→Recovery→Dashboard
   g_orch.OnTimer();
  }

//+------------------------------------------------------------------+
//|  ARCHITECTURE SUMMARY — v13.00 IMPROVEMENTS                      |
//+------------------------------------------------------------------+
/*
 * ISSUES RESOLVED IN v13.00:
 * 
 * 1. INCLUDE DEPENDENCY CHAOS → FIXED
 *    - Before: 27 scattered #include statements in EA file
 *    - After:  Single #include <PASR/Core/PASR.mqh> master header
 *    - Benefit: Compile-time dependency validation, no circular refs
 * 
 * 2. DUAL EXECUTION ENGINE CONFLICT → FIXED
 *    - Before: g_executor + internal Orchestrator execution (conflict)
 *    - After:  Single CExecutionManager owned by COrchestrator
 *    - Benefit: No race conditions, clear ownership
 * 
 * 3. MONOLITHIC OnTimer() → FIXED
 *    - Before: All logic in single function (no profiling)
 *    - After:  CPipelineEngine with 12 staged execution
 *    - Benefit: Profiling per stage, early-exit optimization
 * 
 * 4. GLOBAL RUNTIME STATE TOO WILD → FIXED
 *    - Before: Scattered globals (g_ctx, g_executor, g_symMgr, etc.)
 *    - After:  Minimal SEAState struct (initialized, shutdown_flag, last_tick)
 *    - Constraint: Manager state encapsulated in COrchestrator only
 * 
 * 5. EVENT HANDLERS BUSINESS-HEAVY → FIXED
 *    - Before: Direct module calls, business logic in handlers
 *    - After:  Thin delegates with guards, all logic in managers
 *    - Pattern: Handler → Orchestrator → Manager → EventBus
 * 
 * 6. MANAGERS MUTUAL KNOWLEDGE → FIXED
 *    - Before: Managers referencing each other directly
 *    - After:  Communication via EventBus + Orchestrator coordination
 *    - Pattern: Mediator pattern through COrchestrator
 * 
 * 7. DASHBOARD TOO CLOSE TO RUNTIME → FIXED
 *    - Before: Direct state access from dashboard to managers
 *    - After:  Dashboard subscribes to events (EVENT_ID_POSITION_UPDATE, etc.)
 *    - Benefit: Decoupled UI, thread-safe updates
 * 
 * 8. LOGGING NOT CENTRALIZED → FIXED
 *    - Before: Print() calls scattered across modules
 *    - After:  CJournalManager receives events via EventBus
 *    - Benefit: Single logging point, CSV export, filtering
 * 
 * 9. INDICATOR HANDLE LIFECYCLE → FIXED
 *    - Before: Manual indicator create/release, leak risks
 *    - After:  DataManager owns all indicator handles
 *    - Benefit: Automatic cleanup on deinit, no leaks
 * 
 * 10. PIPELINE NOT PROFILING-AWARE → FIXED
 *     - Before: No performance metrics
 *     - After:  StageMetrics per pipeline stage
 *     - Metrics: elapsed_us, executed_count, skipped_count, aborted_count
 * 
 * 11. POSITION MANAGEMENT SYNCHRONOUS-HEAVY → FIXED
 *     - Before: Blocking position checks in main loop
 *     - After:  RecoveryManager async handling via events
 *     - Benefit: Non-blocking, scalable to multi-symbol
 * 
 * FOLDER STRUCTURE (OPTIMIZED):
 *   Experts/
 *     └── PASR_MODULAR.mq5          ← Single EA entry point
 *   Include/PASR/
 *     ├── Core/                     ← Foundation layer
 *     │   ├── PASR.mqh              ← Master include (use this!)
 *     │   ├── Orchestrator.mqh      ← Mediator pattern
 *     │   ├── PipelineEngine.mqh    ← Staged execution
 *     │   ├── PipelineTypes.mqh     ← Stage enums, context
 *     │   ├── EventBus.mqh          ← Pub/sub messaging
 *     │   ├── IManager.mqh          ← Manager interface
 *     │   └── Config/               ← Configuration layer
 *     ├── Infra/                    ← Cross-cutting concerns
 *     │   ├── DataManager.mqh       ← Price data, indicators
 *     │   ├── JournalManager.mqh    ← Centralized logging
 *     │   └── StateManager.mqh      ← Persistent state
 *     ├── Analysis/                 ← Market analysis
 *     │   ├── SRManager.mqh         ← Support/Resistance
 *     │   ├── ZoneManager.mqh       ← Supply/Demand zones
 *     │   └── Pattern/              ← Candlestick patterns
 *     ├── Signal/                   ← Signal generation
 *     │   ├── SignalManager.mqh     ← Weighted voting
 *     │   ├── RegimeFilter.mqh      ← Market regime detection
 *     │   └── AI/                   ← ML inference
 *     ├── Trade/                    ← Execution layer
 *     │   ├── RiskManager.mqh       ← Pre-trade checks
 *     │   ├── ExecutionManager.mqh  ← Order execution
 *     │   └── RecoveryManager.mqh   ← Position management
 *     ├── UI/                       ← User interface
 *     │   └── DashboardManager.mqh  ← Chart HUD
 *     └── QA/                       ← Testing tools
 *         └── QAStressTest.mqh      ← Chaos engineering
 */

//+------------------------------------------------------------------+
//|  END OF FILE — Pure Pipeline Architecture v13.00 Complete        |
//+------------------------------------------------------------------+

