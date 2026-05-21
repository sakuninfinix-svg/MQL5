//+------------------------------------------------------------------+
//|                                                 PASR_MODULAR.mq5 |
//|                                       Copyright 2026, Agsicentre |
//|         Enhanced & Refactored for Performance & Efficiency       |
//+------------------------------------------------------------------+
//| CHANGELOG                                                        |
//|   v1.40 - Sync with Phase 4-9:                                   |
//|           + Validator gate (Phase 5) as first OnInit() guard     |
//|           + DashboardManager v3 setters wired (Phase 9)         |
//|           + AIManager backprop gating comment (Phase 7)         |
//|   v1.30 - Replaced 14 individual #include lines with single      |
//|           #include <PASR/PASR.mqh> master include.               |
//|           Dependency order is now enforced in PASR.mqh, not here.|
//|           PatternManager now sourced from Pattern/ subfolder.    |
//|   v1.20 - Performance & efficiency refactor                      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "1.40"
#property strict
#property description "Modular Price Action & SR Trading System"
#property description "Optimized for efficiency, reduced latency, and better resource management"

//--- Single master include — dependency order enforced in PASR.mqh
#include <PASR/PASR.mqh>

// Global helper untuk dispatch events ke EventBus
void DispatchEvent(PASREvent *ev)
{
   EventBus *bus = EventBus::Instance();
   if(CheckPointer(bus) != POINTER_INVALID)
      bus.Push(ev);
}

//--- Global Pointers Declaration
EventRecorder      *g_recorder = NULL;  // Defined here, declared extern in EventBus.mqh
DataManager        *IManager::s_dataCache = NULL;
MarketRegimeFilter *g_regimeFilter = NULL;  // Global pointer for managers to access regime filter

//--- Manager Instances (Stack-allocated for automatic cleanup)
MarketManager      market;
SRManager          sr;
SignalManager      signal;
AIManager          ai;
ExecutionManager   exec;
RecoveryManager    recovery;
CDashboardManager  dashboard;   // v3.00 — CDashboardManager (Phase 9)
DataManager        dta;
MarketRegimeFilter regimeFilter;

//--- Internal Config Cache for the EA Script
struct EAConfigCache
{
   ulong   magicNum;
   bool    debugMode;
   string  symbolName;
   int     symbolDigits;
   double  symbolPoint;
   ENUM_TIMEFRAMES timeframe;
   double  symbolSpread;
   
   void Initialize()
   {
      magicNum      = CFG.risk.magic;
      debugMode     = CFG.system.debug;
      symbolName    = _Symbol;
      timeframe     = _Period;
      symbolDigits  = (int)SymbolInfoInteger(symbolName, SYMBOL_DIGITS);
      symbolPoint   = SymbolInfoDouble(symbolName, SYMBOL_POINT);
      symbolSpread  = (double)SymbolInfoInteger(symbolName, SYMBOL_SPREAD);
   }
   
   bool IsValidSymbol() const
   {
      return (symbolName.Length() > 0 && symbolDigits > 0 && symbolPoint > 0);
   }
   
   void RefreshSpread()
   {
      long spread = SymbolInfoInteger(symbolName, SYMBOL_SPREAD);
      if(spread >= 0) symbolSpread = (double)spread;
   }
} eaCfg;

//--- Cached values for performance
static datetime g_lastBarTime       = 0;
static datetime g_lastClosedBarTime = 0;
static bool     g_isInitialized     = false;

//+------------------------------------------------------------------+
//| Global accessor function for spread cache                        |
//+------------------------------------------------------------------+
double GetGlobalSpread()
{
   return eaCfg.symbolSpread;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //=================================================================
   // STEP 0 — VALIDATOR GATE (Phase 5 / 33 rules)
   //   Must be the VERY FIRST check — before any manager allocation.
   //   On failure MT5 logs exact rule violations and blocks the EA.
   //=================================================================
   CPASRValidator validator;
   if(!validator.Validate(CFG))
   {
      validator.PrintErrors();
      Print("[ERROR] PASR_MODULAR: configuration validation failed — EA will not start.");
      return INIT_PARAMETERS_INCORRECT;
   }

   //--- Validate symbol information (fail-fast)
   if(!SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE))
   {
      Print("[ERROR] Invalid symbol or trading not allowed: ", _Symbol);
      return INIT_FAILED;
   }
   
   // 1. Initialize Event Bus first
   if(CheckPointer(EventBus::Instance()) == POINTER_INVALID)
   {
      Print("[ERROR] Failed to initialize EventBus");
      return INIT_FAILED;
   }

   // 2. Initialize config cache with symbol info
   eaCfg.Initialize();
   if(!eaCfg.IsValidSymbol())
   {
      Print("[ERROR] Failed to initialize symbol configuration");
      return INIT_FAILED;
   }
   
   // 3. Initialize debug recorder if enabled
   if(eaCfg.debugMode)
   {
      g_recorder = new EventRecorder();
      if(CheckPointer(g_recorder) == POINTER_INVALID)
      {
         Print("[ERROR] Failed to create EventRecorder");
         return INIT_FAILED;
      }
      g_recorder.Start();
   }

   // 4. Print configuration summary
   PrintConfigSummary();

   // 5. Initialize DataManager (required by all other managers)
   if(!dta.Init())
   {
      Print("[ERROR] Failed to initialize DataManager");
      return INIT_FAILED;
   }
   IManager::SetGlobalDataManager(GetPointer(dta));

   // 6. Initialize managers in dependency order
   if(!signal.Init())
   { Print("[ERROR] Failed to initialize SignalManager");  return INIT_FAILED; }
   
   // AIManager: forward pass runs OnPriceUpdate(), backprop deferred to OnNewBar() (Phase 7)
   if(!ai.Init())
   { Print("[ERROR] Failed to initialize AIManager");      return INIT_FAILED; }
   
   if(!market.Init())
   { Print("[ERROR] Failed to initialize MarketManager");  return INIT_FAILED; }
   
   if(!sr.Init())
   { Print("[ERROR] Failed to initialize SRManager");      return INIT_FAILED; }
   
   if(!exec.Init())
   { Print("[ERROR] Failed to initialize ExecutionManager"); return INIT_FAILED; }
   
   if(!recovery.Init())
   { Print("[ERROR] Failed to initialize RecoveryManager"); return INIT_FAILED; }

   // Initialize Market Regime Filter
   regimeFilter.SetDataManager(GetPointer(dta));
   if(!regimeFilter.CreateIndicators())
   {
      Print("[ERROR] Failed to create MarketRegime indicators");
      return INIT_FAILED;
   }
   g_regimeFilter = GetPointer(regimeFilter);
   ai.SetRegimeFilter(g_regimeFilter);

   // 7. Initialize DashboardManager v3 (Phase 9 — CDashboardManager)
   if(!dashboard.Init(GetPointer(dta), EventBus::Instance()))
   {
      Print("[ERROR] Failed to initialize DashboardManager v3");
      return INIT_FAILED;
   }

   // 8. Start periodic timer (2 seconds)
   EventSetTimer(2);

   // 9. Restore existing positions from previous session
   RestoreExistingPositions();

   // 10. Dispatch initial system ready event
   DispatchEvent(new HeartbeatEvent(0));
   
   g_isInitialized = true;
   Print("[INFO] PASR_MODULAR v1.40 initialized on ", eaCfg.symbolName);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Restore existing positions from previous session                 |
//+------------------------------------------------------------------+
void RestoreExistingPositions()
{
   int restoredCount = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC)  != eaCfg.magicNum)   continue;
      if(PositionGetString(POSITION_SYMBOL)  != eaCfg.symbolName) continue;
      
      ENUM_ORDER_TYPE posType  = (ENUM_ORDER_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double tp        = PositionGetDouble(POSITION_TP);
      double sl        = PositionGetDouble(POSITION_SL);
      double volume    = PositionGetDouble(POSITION_VOLUME);
      double currentATR = dta.GetATRPoints();
      
      RecoveryEngine *eng = recovery.GetEngine(ticket);
      if(eng == NULL)
         recovery.Register(ticket, posType, openPrice, tp, sl, currentATR, volume, 0, 1.0);
      eng = recovery.GetEngine(ticket);

      if(CheckPointer(eng) != POINTER_INVALID)
      {
         eng.LoadState(ticket);
         DispatchEvent(new PositionUpdateEvent(ticket,
                       PositionGetDouble(POSITION_PRICE_CURRENT),
                       PositionGetDouble(POSITION_PROFIT)));
         restoredCount++;
      }
   }
   
   if(restoredCount > 0)
      Print("[INFO] Restored ", restoredCount, " existing position(s)");
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   EventBus::Release();

   //--- DashboardManager v3 cleanup (Phase 9)
   dashboard.Destroy();
   
   if(CheckPointer(g_recorder) != POINTER_INVALID)
   {
      delete g_recorder;
      g_recorder = NULL;
   }
   
   Comment("");
   
   if(eaCfg.debugMode)
      Print("[INFO] PASR_MODULAR deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Chart event handler                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // Forward chart events to dashboard for toggle/button interactions
   dashboard.OnChartEvent(id, lparam, dparam, sparam);
}

//+------------------------------------------------------------------+
//| Trade transaction handler                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC)  != eaCfg.magicNum)   return;
   if(HistoryDealGetString(trans.deal,  DEAL_SYMBOL) != eaCfg.symbolName) return;
   
   long  entryType = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   ulong positionID = trans.position;

   if(entryType == DEAL_ENTRY_IN)
   {
      string comment  = HistoryDealGetString(trans.deal, DEAL_COMMENT);
      int    hashPos  = StringFind(comment, "#");
      ulong  tsID     = (hashPos >= 0) ? (ulong)StringToInteger(StringSubstr(comment, hashPos + 1)) : 0;

      ENUM_ORDER_TYPE type   = (ENUM_ORDER_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
      double entry   = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
      double volume  = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
      double sl      = HistoryDealGetDouble(trans.deal, DEAL_SL);
      double tp      = HistoryDealGetDouble(trans.deal, DEAL_TP);
      double slMult  = 1.0;

      if(PositionSelectByTicket(positionID))
      {
         if(sl <= 0) sl = PositionGetDouble(POSITION_SL);
         if(tp <= 0) tp = PositionGetDouble(POSITION_TP);
      }

      if(tsID > 0)
      {
         string prefix = "PASR_PEND_" + IntegerToString(eaCfg.magicNum) + "_"
                        + eaCfg.symbolName + "_" + IntegerToString(tsID) + "_";
         if(GlobalVariableCheck(prefix + "ts"))
         {
            if(tp <= 0) tp = GlobalVariableGet(prefix + "tp");
            if(GlobalVariableCheck(prefix + "sm")) slMult = GlobalVariableGet(prefix + "sm");
            GlobalVariablesDeleteAll("PASR_PEND_" + IntegerToString(eaCfg.magicNum)
                                    + "_" + eaCfg.symbolName + "_" + IntegerToString(tsID));
         }
      }

      DispatchEvent(new OrderExecutionEvent(true, positionID, type, entry, sl, tp, volume,
                                            "Confirmed", comment));
      recovery.Register(positionID, type, entry, tp, sl, dta.GetATRPoints(), volume, 0, slMult);

      datetime times[];
      if(CopyTime(eaCfg.symbolName, eaCfg.timeframe, 0, 1, times) > 0)
         market.UpdateLastEntryBarTime(times[0]);
   }
   else if(entryType == DEAL_ENTRY_OUT || entryType == DEAL_ENTRY_INOUT)
   {
      dta.RefreshDailyProfit();
      
      double netProfit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                       + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION)
                       + HistoryDealGetDouble(trans.deal, DEAL_SWAP);
      dta.UpdateConsecutiveLosses(netProfit);

      //--- Feed AI with trade result (Phase 7)
      ai.OnTradeResult(positionID, netProfit);

      string comment  = HistoryDealGetString(trans.deal, DEAL_COMMENT);
      int    recovPos = StringFind(comment, "RECOV_ORIG_");
      if(recovPos == 0)
      {
         int ticketStart = StringLen("RECOV_ORIG_");
         int ticketEnd   = StringFind(comment, "_P_", ticketStart);
         if(ticketEnd > ticketStart)
         {
            ulong origTicket = (ulong)StringToInteger(StringSubstr(comment, ticketStart,
                                                      ticketEnd - ticketStart));
            recovery.NotifyRecoverySuccess(origTicket);
         }
      }

      DispatchEvent(new PositionUpdateEvent(positionID,
                   HistoryDealGetDouble(trans.deal, DEAL_PRICE),
                   netProfit, true));

      //--- Update dashboard P&L row (Phase 9)
      double dd = (dta.GetStartBalance() > 0)
                  ? (dta.GetStartBalance() - AccountInfoDouble(ACCOUNT_EQUITY))
                    / dta.GetStartBalance() * 100.0
                  : 0.0;
      dashboard.SetPnL(dta.GetDailyProfit(), dd);
   }
}

//+------------------------------------------------------------------+
//| Timer handler                                                    |
//+------------------------------------------------------------------+
void OnTimer()
{
   EventBus *bus = EventBus::Instance();
   if(CheckPointer(bus) != POINTER_INVALID)
      bus.ProcessDeferredEvents();
   
   DispatchEvent(new HeartbeatEvent(2));
}

//+------------------------------------------------------------------+
//| Tick event handler                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   eaCfg.RefreshSpread();
   
   MqlTick tick;
   if(!SymbolInfoTick(eaCfg.symbolName, tick)) return;

   //--- Forward pass only — backprop deferred to OnNewBar() inside AIManager (Phase 7)
   ai.OnPriceUpdate();

   DispatchEvent(new PriceUpdateEvent(tick));

   if(CFG.market.useRegime)
      regimeFilter.Update();

   //--- Update dashboard at tick rate (throttled internally to 1Hz)
   dashboard.SetSignal(signal.GetLastDirection(), signal.GetLastScore());
   dashboard.SetAIScore(ai.GetConfidence(), ai.GetLastLoss(), ai.GetEpochCount());
   dashboard.SetRecoveryState(recovery.GetState(), recovery.GetAttemptCount());
   dashboard.OnPriceUpdate();

   //--- Bar detection using CopyTime (MQL5 best practice)
   datetime times[];
   if(CopyTime(eaCfg.symbolName, eaCfg.timeframe, 0, 2, times) <= 0) return;
      
   datetime lastClosedBar = times[1];
   if(lastClosedBar != g_lastClosedBarTime)
   {
      g_lastClosedBarTime = lastClosedBar;
      market.SetLastBarTime(lastClosedBar);

      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(eaCfg.symbolName, eaCfg.timeframe, 0, 2, rates) > 1)
      {
         if(rates[1].high >= rates[1].low && rates[1].open > 0 && rates[1].close > 0)
         {
            DispatchEvent(new NewBarEvent(
                lastClosedBar,
                rates[1].open, rates[1].high, rates[1].low, rates[1].close,
                eaCfg.timeframe));
         }
      }
   }
}
