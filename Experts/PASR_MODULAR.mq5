//+------------------------------------------------------------------+
//|  PASR_MODULAR.mq5 — v5.00 (Multi-Symbol Ready)                   |
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
//|   [14] RecoveryManager — Trade/RecoveryManager.mqh               |
//|   [15] AIFeatureBuilder — AI/AIFeatureBuilder.mqh                |
//|   [16] AIInference     — AI/AIInference.mqh                      |
//|   [17] AIEnsemble      — AI/AIEnsemble.mqh                       |
//|   [18] AICalibrationBridge — AI/AICalibrationBridge.mqh          |
//|   [19] DashboardManager — UI/DashboardManager.mqh                |
//|   [20] SymbolScanner   — Data/SymbolScanner.mqh (NEW v5.00)      |
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
//|  Magic: 20260521  Version: v5.00-multi-symbol                    |
//|  Build: 2026-05-21                                               |
//+------------------------------------------------------------------+
#property copyright   "PASR EA © 2026"
#property link        "https://github.com/sakuninfinix-svg/MQL5"
#property version     "5.00"
#property description "Price Action SR — Modular Orchestrator v5.00 (Multi-Symbol)"
#property strict

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
#include <PASR/Trade/RecoveryManager.mqh>   // [14] v4.01: wired
//--- AI
#include <PASR/Signal/AI/AIFeatureBuilder.mqh>
#include <PASR/Signal/AI/AIInference.mqh>
#include <PASR/Signal/AI/AIEnsemble.mqh>
#include <PASR/Signal/AI/AICalibrationBridge.mqh>
//--- UI
#include <PASR/UI/DashboardManager.mqh>
//--- Data (Multi-Symbol)
#include <PASR/Data/SymbolScanner.mqh>

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

//--- [DASHBOARD]
sinput group "=== DASHBOARD ==="
input bool     InpShowDash        = true;   // Show on-chart HUD
input bool     InpShowAIPanel     = true;   // Show AI panel
input bool     InpExportReport    = true;   // Export HTML report on deinit
input int      InpReportInterval  = 50;     // Export every N trades

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
CRecoveryManager     g_recovery;   // [14] v4.01
CAIFeatureBuilder    g_featBuilder;
CAIInference         g_aiInfer;
CAIEnsemble          g_ensemble;
CAICalibrationBridge g_calibBridge;
CDashboardManager    g_hud;
//--- Multi-Symbol Scanner (NEW v5.00)
CSymbolScanner       g_scanner;

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

//+------------------------------------------------------------------+
//|  OnInit — ordered boot sequence                                  |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("[PASR] v5.00-multi-symbol booting — magic:", InpMagic);

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

   //--- [14] Recovery Manager  ← v4.01
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
   
   //--- Print scanner statistics (NEW v5.00)
   g_scanner.PrintStats();
   
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

      //--- [D] Position management (BE, partial, trailing)
      //        + recovery price-tick monitoring
      double atrC = GetATR();
      if(g_pos.HasOpenPosition())
         g_pos.OnTick(atrC);
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

      //--- [I] Risk daily reset check
      if(!g_risk.IsTradingAllowed())
        {
         DebugPrint("Risk circuit breaker active — skip bar");
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

      //--- [M] AI Feature build
      SRZone zones[20];
      int nZones = g_sr.GetZones(zones, 20);
      g_lastFV = g_featBuilder.Build(sig, atr,
                                      sig.nearestSupport,
                                      sig.nearestResistance,
                                      zones, nZones);

      //--- [N] Drift check
      g_lastDrift = g_featBuilder.ComputeDrift(g_lastFV);
      if(InpUseAI && g_lastDrift > InpDriftVeto)
        {
         DebugPrint(StringFormat("Drift veto: %.2f", g_lastDrift));
         CDashboardManager::PushSignal(g_dashCtx, sig.direction, 0, 0);
         if(InpShowDash) UpdateDashboard();
         continue;
        }

      //--- [O] AI Ensemble scoring
      double patternBonus = g_pattern.GetPatternBonus(sig.direction);
      g_lastAIScore = InpUseAI
         ? (InpUseEnsemble
              ? g_ensemble.GetScore(g_lastFV, sig, patternBonus, g_lastDrift)
              : g_aiInfer.ForwardPass18(g_lastFV, patternBonus, g_lastDrift))
         : sig.confluence;
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

      //--- [Q] Risk sizing
      if(!g_risk.CanOpenTrade())
        {
         DebugPrint("Risk: trade blocked (daily limit or max trades)");
         if(InpShowDash) UpdateDashboard();
         continue;
        }

      double lotSize = g_risk.CalcLotSize(
                         current_symbol, atr * InpSLATRMult, ep.lotMultiplier);
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
