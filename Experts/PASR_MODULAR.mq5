//+------------------------------------------------------------------+
//|               Price Action & Support Resistance V1               |
//|         Optimized by Agsicentre (agsicentre.wordpress.com)       |
//|         Enhanced & Refactored for Performance & Efficiency       |
//+------------------------------------------------------------------+
#property link      "agsicentre.wordpress.com"
#property version   "1.20"
#property strict
#property description "Modular Price Action & SR Trading System"
#property description "Optimized for efficiency, reduced latency, and better resource management"

//--- Include Dependencies (Ordered by initialization priority)
#include <PASR/0.EventBus.mqh>
#include <PASR/1.Events.mqh>
#include <PASR/IManager.mqh>
#include <PASR/2.Config.mqh>
#include <PASR/3.MarketManager.mqh>
#include <PASR/4.SRManager.mqh>
#include <PASR/5.SignalManager.mqh>
#include <PASR/6.ExecutionManager.mqh>
#include <PASR/8.RecoveryManager.mqh>
#include <PASR/9.PatternManager.mqh>
#include <PASR/10.DataManager.mqh>
#include <PASR/AIManager.mqh>
#include <PASR/11.DashboardManager.mqh>

//--- Global Pointers Declaration
EventRecorder      *g_recorder = NULL;  // Defined here, declared extern in EventBus.mqh
DashboardManager   *dashCtrl   = NULL;
DataManager        *IManager::s_dataCache = NULL;

//--- Manager Instances (Stack-allocated for automatic cleanup)
MarketManager      market;
SRManager          sr;
SignalManager      signal;
AIManager          ai;
ExecutionManager   exec;
RecoveryManager    recovery;
DashboardUI        dashboard;
DataManager        dta;

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
static datetime g_lastBarTime = 0;
static bool     g_isInitialized = false;

int OnInit()
{
   //--- Validate symbol information first (fail-fast)
   if(!SymbolInfoInteger(eaCfg.symbolName, SYMBOL_TRADE_MODE))
   {
      Print("[ERROR] Invalid symbol or trading not allowed: ", eaCfg.symbolName);
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
   // SignalManager depends on DataManager
   if(!signal.Init())
   {
      Print("[ERROR] Failed to initialize SignalManager");
      return INIT_FAILED;
   }
   
   // AIManager depends on SignalManager and DataManager
   if(!ai.Init())
   {
      Print("[ERROR] Failed to initialize AIManager");
      return INIT_FAILED;
   }
   
   // MarketManager depends on DataManager
   if(!market.Init())
   {
      Print("[ERROR] Failed to initialize MarketManager");
      return INIT_FAILED;
   }
   
   // SRManager depends on DataManager and MarketManager
   if(!sr.Init())
   {
      Print("[ERROR] Failed to initialize SRManager");
      return INIT_FAILED;
   }
   
   // ExecutionManager depends on SignalManager and MarketManager
   if(!exec.Init())
   {
      Print("[ERROR] Failed to initialize ExecutionManager");
      return INIT_FAILED;
   }
   
   // RecoveryManager depends on ExecutionManager and DataManager
   if(!recovery.Init())
   {
      Print("[ERROR] Failed to initialize RecoveryManager");
      return INIT_FAILED;
   }

   // 7. Initialize Dashboard
   dashCtrl = DashboardManagerFactory::Create(GetPointer(dashboard), GetPointer(dta));
   if(CheckPointer(dashCtrl) == POINTER_INVALID)
   {
      Print("[ERROR] Failed to create DashboardManager");
      return INIT_FAILED;
   }
   dashboard.SetController(dashCtrl);
   
   if(!dashboard.CreateDashboard(0, "PASR_Dashboard", 0, 20, 20, 320, 420))
   {
      Print("[ERROR] Failed to create dashboard UI");
      return INIT_FAILED;
   }
   dashboard.Run();

   // 8. Start periodic timer (2 seconds) for system heartbeats
   EventSetTimer(2);

   // 9. Restore existing positions for this EA
   RestoreExistingPositions();

   // 10. Dispatch initial system ready event
   DispatchEvent(new HeartbeatEvent(0));
   
   g_isInitialized = true;
   Print("[INFO] PASR_MODULAR initialized successfully on ", eaCfg.symbolName);

   return(INIT_SUCCEEDED);
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
      
      // Filter by magic number and symbol
      if(PositionGetInteger(POSITION_MAGIC) != eaCfg.magicNum) continue;
      if(PositionGetString(POSITION_SYMBOL) != eaCfg.symbolName) continue;
      
      // Get position details
      ENUM_ORDER_TYPE posType = (ENUM_ORDER_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double tp = PositionGetDouble(POSITION_TP);
      double sl = PositionGetDouble(POSITION_SL);
      double volume = PositionGetDouble(POSITION_VOLUME);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      
      // Get current ATR for recovery calculations
      double currentATR = dta.GetATRPoints();
      
      // Check if recovery engine already exists
      RecoveryEngine *eng = recovery.GetEngine(ticket);
      if(eng == NULL)
      {
         // Register new recovery engine for this position
         // Default SL multiplier to 1.0 if not found
         recovery.Register(ticket, posType, openPrice, tp, sl, currentATR, volume, 0, 1.0);
         eng = recovery.GetEngine(ticket);
      }

      if(CheckPointer(eng) != POINTER_INVALID)
      {
         eng.LoadState(ticket);

         // Dispatch event to notify listeners about current position state
         double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
         double profit = PositionGetDouble(POSITION_PROFIT);
         DispatchEvent(new PositionUpdateEvent(ticket, currentPrice, profit));
         
         restoredCount++;
      }
   }
   
   if(restoredCount > 0)
      Print("[INFO] Restored ", restoredCount, " existing position(s)");
}

void OnDeinit(const int reason)
{
   //--- Kill timer first to prevent any pending events
   EventKillTimer();
   
   //--- Release EventBus singleton
   EventBus::Release();

   //--- Destroy DashboardManager
   if(CheckPointer(dashCtrl) != POINTER_INVALID)
   {
      DashboardManagerFactory::Destroy(dashCtrl);
      dashCtrl = NULL;
   }
   
   //--- Clean up event recorder
   if(CheckPointer(g_recorder) != POINTER_INVALID)
   {
      delete g_recorder;
      g_recorder = NULL;
   }

   //--- Destroy dashboard UI
   dashboard.Destroy(reason);
   
   //--- Clear chart comment
   Comment("");
   
   if(eaCfg.debugMode)
      Print("[INFO] PASR_MODULAR deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Chart event handler                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // Forward chart events to dashboard for button clicks, etc.
   dashboard.ChartEvent(id, lparam, dparam, sparam);
}

//+------------------------------------------------------------------+
//| Trade transaction handler                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   // Filter: Only process DEAL_ADD transactions for our magic number and symbol
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(trans.deal))
      return;
      
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != eaCfg.magicNum)
      return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != eaCfg.symbolName)
      return;
   
   long entryType = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   ulong positionID = trans.position;

   //--- Handle new position opened (DEAL_ENTRY_IN)
   if(entryType == DEAL_ENTRY_IN)
   {
      string comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
      int hashPos = StringFind(comment, "#");
      ulong tsID = 0;
      
      if(hashPos >= 0)
         tsID = (ulong)StringToInteger(StringSubstr(comment, hashPos + 1));

      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
      double entry = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
      double volume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
      double sl = HistoryDealGetDouble(trans.deal, DEAL_SL);
      double tp = HistoryDealGetDouble(trans.deal, DEAL_TP);
      double slMult = 1.0;

      // Robust SL/TP lookup: HistoryDeal might have 0 if orders were modified async
      if(PositionSelectByTicket(positionID))
      {
         if(sl <= 0) sl = PositionGetDouble(POSITION_SL);
         if(tp <= 0) tp = PositionGetDouble(POSITION_TP);
      }

      // Context from Global Variables (sent from ExecutionManager)
      if(tsID > 0)
      {
         string prefix = "PASR_PEND_" + IntegerToString(eaCfg.magicNum) + "_" + eaCfg.symbolName + "_" + IntegerToString(tsID) + "_";
         
         if(GlobalVariableCheck(prefix + "ts"))
         {
            if(tp <= 0)
               tp = GlobalVariableGet(prefix + "tp");
            if(GlobalVariableCheck(prefix + "sm"))
               slMult = GlobalVariableGet(prefix + "sm");
               
            // Clean up the pending GV after successful confirmation
            GlobalVariablesDeleteAll("PASR_PEND_" + IntegerToString(eaCfg.magicNum) + "_" + eaCfg.symbolName + "_" + IntegerToString(tsID));
         }
      }

      // Dispatch final confirmation event for RecoveryManager to register the position
      OrderExecutionEvent *confirm = new OrderExecutionEvent(
          true, positionID, type, entry, sl, tp, volume, "Confirmed", comment);
      DispatchEvent(confirm);

      // Register with correct SLMult for Adaptive Recovery
      recovery.Register(positionID, type, entry, tp, sl, dta.GetATRPoints(), volume, 0, slMult);

      // Update last entry bar time
      datetime times[];
      if(CopyTime(eaCfg.symbolName, eaCfg.timeframe, 0, 1, times) > 0)
         market.UpdateLastEntryBarTime(times[0]);
   }
   //--- Handle position closed (DEAL_ENTRY_OUT or DEAL_ENTRY_INOUT)
   else if(entryType == DEAL_ENTRY_OUT || entryType == DEAL_ENTRY_INOUT)
   {
      // Refresh daily stats
      dta.RefreshDailyProfit();
      
      double netProfit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) +
                         HistoryDealGetDouble(trans.deal, DEAL_COMMISSION) +
                         HistoryDealGetDouble(trans.deal, DEAL_SWAP);
      dta.UpdateConsecutiveLosses(netProfit);

      string comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
      int recovPos = StringFind(comment, "RECOV_ORIG_");
      
      if(recovPos == 0)
      {
         int ticketStart = StringLen("RECOV_ORIG_");
         int ticketEnd = StringFind(comment, "_P_", ticketStart);
         
         if(ticketEnd > ticketStart)
         {
            ulong originalTicket = (ulong)StringToInteger(StringSubstr(comment, ticketStart, ticketEnd - ticketStart));
            recovery.NotifyRecoverySuccess(originalTicket);
         }
      }

      // Notify AI and other listeners that a position has closed
      DispatchEvent(new PositionUpdateEvent(positionID,
                                            HistoryDealGetDouble(trans.deal, DEAL_PRICE),
                                            netProfit,
                                            true));
   }
}

//+------------------------------------------------------------------+
//| Timer handler                                                    |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Dispatch heartbeat for periodic tasks (UI update, health checks, etc)
   DispatchEvent(new HeartbeatEvent(2));
}

//+------------------------------------------------------------------+
//| Tick event handler                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Refresh spread cache (lightweight, called every tick)
   eaCfg.RefreshSpread();
   
   //--- Get current tick data
   MqlTick tick;
   if(!SymbolInfoTick(eaCfg.symbolName, tick))
      return;

   //--- Dispatch price update event (lightweight)
   DispatchEvent(new PriceUpdateEvent(tick));

   //--- Check for new bar using CopyTime (MQL5 Best Practice)
   datetime times[];
   if(CopyTime(eaCfg.symbolName, eaCfg.timeframe, 0, 1, times) <= 0)
      return;
      
   datetime currentBar = times[0];

   if(currentBar != g_lastBarTime)
   {
      g_lastBarTime = currentBar;
      market.SetLastBarTime(currentBar);

      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      
      if(CopyRates(eaCfg.symbolName, eaCfg.timeframe, 0, 1, rates) > 0)
      {
         DispatchEvent(new NewBarEvent(
             currentBar,
             rates[0].open,
             rates[0].high,
             rates[0].low,
             rates[0].close,
             eaCfg.timeframe));
      }
   }
}