//+------------------------------------------------------------------+
//|  PASR_MODULAR.mq5                                                |
//|  Expert Advisor: PASR (Price Action Support Resistance)          |
//|  Version: 13.02 — canonical QA/EventBus cleanup                  |
//|  Refactored: Centralized includes, removed dual-core conflict    |
//+------------------------------------------------------------------+
#property copyright   "PASR EA © 2026"
#property link        "https://github.com/sakuninfinix-svg/MQL5"
#property version     "13.02"
#property description "PASR Model - Pure Pipeline Architecture (v13.02)"
#property strict

//--- Compilation Flags (controlled via master include)
// BUG-008 FIX: Renamed QA_BUILD -> PASR_QA_BUILD to match #ifdef guards.
#define PASR_QA_BUILD     // Enable stress testing & chaos engineering

//--- SINGLE MASTER INCLUDE - All dependencies managed centrally
#include <PASR/Core/PASR.mqh>

//--- QA Module (standalone - not part of orchestrator pipeline)
#ifdef PASR_QA_BUILD
#include <PASR/QA/QAStressTest.mqh>
#endif

//+------------------------------------------------------------------+
//|  INPUT PARAMETERS — Institutional Configuration                  |
//+------------------------------------------------------------------+

//--- [INSTITUTIONAL RISK]
sinput group "=== INSTITUTIONAL RISK MANAGEMENT ==="
input double   InpRiskPct         = 1.0;    // Risk per Trade (% of Equity)
input double   InpMaxDailyLossPct = 3.0;    // Daily Loss Circuit Breaker (%)
input double   InpMaxDrawdownPct  = 10.0;   // Global Drawdown Halt (%)
input bool     InpVolatilityAdj   = true;   // Adjust Size by ATR Volatility
input int      InpPyramidLevels   = 3;      // Scale-in Tranches (0=Disabled)
input double   InpPyramidSpacing  = 0.5;    // Tranche Distance (ATR Multiplier)
input int      InpMaxTradesPerDay = 20;     // Max Trades Per Day (Circuit Breaker)

//--- [MARKET STRUCTURE]
sinput group "=== MARKET STRUCTURE LOGIC ==="
input bool     InpStructSL        = true;   // Use Swing High/Low for SL
input double   InpSLBufferATR     = 1.5;    // Buffer for Structural SL (ATR)
input bool     InpStructTrail     = true;   // Trail based on Market Structure
input bool     InpUseChandelier   = true;   // Chandelier Exit for Runners
input double   InpChanATRMult     = 3.0;    // Chandelier ATR Multiplier
input int      InpChanPeriod      = 22;     // Chandelier Lookback

//--- [SUPPORT/RESISTANCE]
sinput group "=== SUPPORT/RESISTANCE DETECTION ==="
input int      InpSRLookback      = 50;     // SR Lookback Bars
input int      InpSRMinTouches    = 2;      // Minimum Touches to Validate SR
input double   InpSRMergeATR      = 0.5;    // Merge Zones within N ATR
input int      InpSRMaxZones      = 10;     // Maximum SR Zones to Track

//--- [MULTI-SYMBOL]
sinput group "=== MULTI-SYMBOL SCANNER ==="
input double   InpMaxSpreadPts    = 30.0;   // Max Spread in Points
input bool     InpCheckSession    = false;  // Check Trading Session
input int      InpSessionStart    = 0;      // Session Start Hour (UTC)
input int      InpSessionEnd      = 24;     // Session End Hour (UTC)

//--- [CORRELATION]
sinput group "=== CORRELATION RISK ==="
input bool     InpUseCorrelation  = true;   // Enable Correlation Check
input double   InpCorrThreshold   = 0.80;   // Max Allowed Correlation
input int      InpCorrWindow      = 20;     // Correlation Lookback Bars

//--- [SIGNAL & CONFLUENCE]
sinput group "=== SIGNAL ENGINE ==="
input double   InpMinConfluence   = 0.60;   // Min Signal Confluence Score
input double   InpMaxSpreadPips   = 2.0;    // Max Allowed Spread (Pips)
input bool     InpUsePatterns     = true;   // Use Candlestick Patterns
input bool     InpUseTrend        = true;   // Use Trend Filter
input int      InpMinBarsConfirm  = 2;      // Minimum Confirmation Bars

//--- [EXECUTION]
sinput group "=== TRADE EXECUTION ==="
input int      InpMaxSlippage     = 15;     // Max Slippage (Points)
input int      InpRetryAttempts   = 3;      // Smart Retry Count
input bool     InpAsyncMode       = true;   // Asynchronous Processing
input double   InpMinRR           = 1.5;    // Minimum R:R to Trade
input double   InpTP1RR           = 1.5;    // TP1 R:R (Partial)
input double   InpTP2RR           = 3.0;    // TP2 R:R (Runner)

//--- [POSITION MANAGEMENT]
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

//--- [RECOVERY]
sinput group "=== RECOVERY ENGINE ==="
input bool     InpRecoveryEnabled = true;   // Enable Fakeout Recovery
input int      InpMaxRecovAttempts= 3;      // Max Recovery Attempts per Trade
input int      InpRecovCooldown   = 3;      // Recovery Cooldown (Bars)
input int      InpMaxTradeDays    = 5;      // Force-Close after N Days (0=Off)

//--- [AI]
sinput group "=== AI ENGINE ==="
input bool     InpUseAI           = true;   // Enable AI Scoring
input double   InpAIVetoThresh    = 0.40;   // AI Veto Below Score
input double   InpDriftVeto       = 0.60;   // Drift Veto Above
input double   InpAIHighThresh    = 0.80;   // High-Confidence Threshold
input bool     InpUseEnsemble     = true;   // Use Ensemble Voting
input bool     InpLoadWeights     = true;   // Load Saved Ensemble Weights
input int      InpFeatureWindow   = 20;     // Feature Engine Rolling Window
input bool     InpUseAdvFeatures  = true;   // Use Advanced Statistical Features

//--- [DASHBOARD]
sinput group "=== DASHBOARD ==="
input bool     InpShowDash        = true;   // Show On-Chart HUD
input bool     InpShowAIPanel     = true;   // Show AI Panel
input bool     InpExportReport    = true;   // Export HTML Report on Deinit
input int      InpReportInterval  = 50;     // Export Every N Trades

//--- [QA & STRESS TEST]
sinput group "=== QA & STRESS TEST (DEV ONLY) ==="
input bool     InpEnableChaos     = false;  // Randomly Inject Errors if PASR_QA_BUILD
input int      InpChaosFrequency  = 100;    // Trigger Chaos Every N Ticks
input double   InpChaosSpreadMult = 5.0;    // Spread spike multiplier during chaos
input bool     InpTestPoolExhaust = false;  // Test EventBus exhaustion fallback

//--- [GENERAL]
sinput group "=== GENERAL ==="
input ulong    InpMagic           = 20260521; // Magic number
input string   InpComment         = "PASR_v13";  // Order comment
sinput bool    InpJournalEnabled  = true;    // Enable CSV journal
sinput bool    InpDebugLog        = false;   // Verbose debug logging

//+------------------------------------------------------------------+
//|  MODULE INSTANCES — PURE ORCHESTRATOR PIPELINE                   |
//+------------------------------------------------------------------+
COrchestrator        g_orch;             // Main pipeline coordinator

#ifdef PASR_QA_BUILD
CQAStressTest        g_qa;               // Chaos engineering external QA tool
#endif

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
SEAState             g_state;

//+------------------------------------------------------------------+
//|  HELPERS                                                         |
//+------------------------------------------------------------------+
void DebugPrint(string msg)
  { if(InpDebugLog) Print("[PASR_DBG] ", msg); }

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
   if(h >= 8  && h < 16) return SESSION_LONDON;
   if(h >= 13 && h < 22) return SESSION_NEW_YORK;
   if(h >= 0  && h < 8 ) return SESSION_TOKYO;
   return SESSION_UNKNOWN;
  }

#ifdef PASR_QA_BUILD
//+------------------------------------------------------------------+
//|  QA Stress Test Helpers                                          |
//+------------------------------------------------------------------+
void QATestEventPoolExhaustion()
  {
   Print("[PASR][QA] Testing EventBus saturation fallback...");

   CEventBus *bus = g_orch.GetEventBus();
   if(bus == NULL)
     {
      Print("[PASR][QA] EventBus unavailable");
      return;
     }

   const int POOL_CAPACITY = 256;
   const int EXHAUST_COUNT = POOL_CAPACITY + 50;

   int success_count = 0;
   for(int i = 0; i < EXHAUST_COUNT; i++)
     {
      PASREvent ev(EVENT_ID_TICK, 90, 0.0, 0.0, "EA_QA_SATURATION");
      if(bus.Push(ev))
         success_count++;
     }

   PrintFormat("[PASR][QA] Saturation test: pushed %d/%d events", success_count, EXHAUST_COUNT);
   bus.Drain();
   Print("[PASR][QA] EventBus saturation test complete - no crashes = PASS");
  }

void QATestCircuitBreaker(ENUM_RISK_CB_TYPE cb_type)
  {
   CRiskManager *risk = g_orch.GetRiskManager();
   if(risk == NULL)
     {
      Print("[PASR][QA] RiskManager unavailable");
      return;
     }

   Print("[PASR][QA] Manually triggering circuit breaker: ", EnumToString(cb_type));

   switch(cb_type)
     {
      case RISK_CB_DAILY_LOSS:
         risk.OnTradeClosed(-10000.0);
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

   bool allowed = risk.IsTradingAllowed();
   PrintFormat("[PASR][QA] After CB trigger - Trading allowed: %s", allowed ? "YES" : "NO");
  }
#endif

//+------------------------------------------------------------------+
//|  OnInit                                                          |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("[PASR] v13.02 Pure Pipeline Architecture booting...");

#ifdef PASR_QA_BUILD
   if(InpEnableChaos)
      Print("[PASR][QA] CHAOS ENGINE ENABLED - frequency=", InpChaosFrequency,
            " spread_mult=", InpChaosSpreadMult);
#endif

   g_state.Reset();

   StrategyConfig cfg;
   cfg.MagicNumber = (long)InpMagic;
   cfg.Risk.RiskPercent = InpRiskPct;
   cfg.Risk.MaxDailyLossPct = InpMaxDailyLossPct;
   cfg.Risk.MaxDrawdownPct = InpMaxDrawdownPct;
   cfg.Risk.UseBreakEven = InpUseBE;
   cfg.Risk.UseTrailingStop = InpUseTrailing;
   cfg.Risk.TrailATRMult = InpTrailATRMult;
   cfg.Risk.RecoveryEnabled = InpRecoveryEnabled;
   cfg.Risk.MaxRecoveryAttempts = InpMaxRecovAttempts;
   cfg.Risk.RecoveryCooldownBars = InpRecovCooldown;
   cfg.Risk.PartialClosePct = InpUsePartial ? MathMax(0.0, MathMin(0.9, InpPartialPct / 100.0)) : 0.0;
   cfg.Risk.MaxTradeDurationDays = InpMaxTradeDays;
   cfg.Market.SpreadFilterPips = InpMaxSpreadPips;
   cfg.Market.SessionStartHour = InpSessionStart;
   cfg.Market.SessionEndHour = InpSessionEnd;
   cfg.AI.EnableAI = InpUseAI;
   cfg.Pattern.EnablePatterns = InpUsePatterns;
   cfg.Display.ShowDashboard = InpShowDash;

   int result = g_orch.Init(cfg);

   if(result != INIT_SUCCEEDED)
     {
      Alert("[PASR] Initialization FAILED - check Experts log");
      return INIT_FAILED;
     }

   g_orch.SetDebugMode(InpDebugLog);
   g_orch.SetProfilingEnabled(true);

#ifdef PASR_QA_BUILD
   if(!g_qa.Init(InpChaosFrequency, InpChaosSpreadMult, InpTestPoolExhaust))
      Print("[PASR][QA] QA init failed; continuing without QA guarantees");
   if(InpTestPoolExhaust)
      QATestEventPoolExhaustion();
#endif

   EventSetTimer(1);
   g_state.initialized = true;

   Print("[PASR] Boot complete — Pure Pipeline Architecture ready");
   Print("[PASR] Pipeline profiling: ENABLED");
   Print("[PASR] All modules encapsulated in COrchestrator");
   Print("[PASR] Event handlers delegate exclusively to g_orch");

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//|  OnDeinit                                                        |
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
//|  OnTick                                                          |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!g_state.initialized) return;

   g_state.last_tick = TimeCurrent();

#ifdef PASR_QA_BUILD
   CEventBus *bus = g_orch.GetEventBus();
   CRiskManager *risk = g_orch.GetRiskManager();
   if(bus != NULL && risk != NULL)
      g_qa.OnTick(_Symbol, *bus, *risk);
#endif

   g_orch.OnTick();
  }

//+------------------------------------------------------------------+
//|  OnTimer                                                         |
//+------------------------------------------------------------------+
void OnTimer()
  {
   if(!g_state.initialized) return;
   g_orch.OnTimer();
  }

//+------------------------------------------------------------------+
//|  OnTradeTransaction                                              |
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
//|  OnChartEvent                                                    |
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
