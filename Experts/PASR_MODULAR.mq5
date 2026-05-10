//+------------------------------------------------------------------+
//|               Price Action & Support Ressistance V1              |
//|         Optimized by Agsicentre (agsicentre.wordpress.com)       |
//+------------------------------------------------------------------+
#property link "agsicentre.wordpress.com"
#property version "1.00"
#property strict

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
#include <PASR/11.DashboardManager.mqh>

// --- Global Pointers Declaration ---
EventRecorder *g_recorder = NULL;
DashboardManager *dashCtrl = NULL;
DataManager *IManager::s_dataCache = NULL;

MarketManager market;
SRManager sr;
SignalManager signal;
ExecutionManager exec;
RecoveryManager recovery;
DashboardUI dashboard;
DataManager dta;

// --- Internal Config Cache for the EA Script ---
struct EAConfigCache
{
   ulong magicNum;
   bool debugMode;
} eaCfg;

int OnInit()
{
   // 1. Initialize Event Bus first
   if (CheckPointer(EventBus::Instance()) == POINTER_INVALID)
   {
      Print("[ERROR] Failed to initialize EventBus");
      return INIT_FAILED;
   }

   // 2. Initialize config & cache
   SetCommonDefaults();
   eaCfg.magicNum = CFG.MagicNum;
   eaCfg.debugMode = CFG.DebugMode;

   if (eaCfg.debugMode)
   {
      g_recorder = new EventRecorder();
      g_recorder.Start();
   }

   PrintConfigSummary();

   if (!dta.Init())
      return (INIT_FAILED);

   IManager::SetGlobalDataManager(GetPointer(dta));

   if (!signal.Init())
      return (INIT_FAILED);
   if (!market.Init())
      return (INIT_FAILED);
   if (!sr.Init())
      return (INIT_FAILED);
   if (!exec.Init())
      return (INIT_FAILED);
   if (!recovery.Init())
      return (INIT_FAILED);

   dashCtrl = DashboardManagerFactory::Create(GetPointer(dashboard), GetPointer(dta));
   if (CheckPointer(dashCtrl) == POINTER_INVALID)
      return (INIT_FAILED);
   dashboard.SetController(dashCtrl);
   // 3. Initialize Dashboard UI
   if (!dashboard.CreateDashboard(0, "PASR_Dashboard", 0, 20, 20, 320, 420))
   {
      Print("[ERROR] Failed to create dashboard");
   }
   dashboard.Run();

   // 4. Start periodic timer (2 seconds) for system heartbeats
   EventSetTimer(2);

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if (PositionSelectByTicket(t) &&
          PositionGetInteger(POSITION_MAGIC) == eaCfg.magicNum &&
          PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         double currentATR = dta.GetATRPoints();
         RecoveryEngine *eng = recovery.GetEngine(t);

         if (eng == NULL)
         {
            recovery.Register(t, (ENUM_ORDER_TYPE)PositionGetInteger(POSITION_TYPE),
                              PositionGetDouble(POSITION_PRICE_OPEN), PositionGetDouble(POSITION_TP),
                              PositionGetDouble(POSITION_SL), currentATR, PositionGetDouble(POSITION_VOLUME), 0, 1.0);
            eng = recovery.GetEngine(t);
         }

         if (CheckPointer(eng) != POINTER_INVALID)
         {
            eng.LoadState(t, eaCfg.magicNum);

            // Dispatch event to notify listeners about current position state
            g_eventBus.Dispatch(new PositionUpdateEvent(t, PositionGetDouble(POSITION_PRICE_CURRENT),
                                                        PositionGetDouble(POSITION_PROFIT)));
         }
      }
   }

   // 7. Dispatch initial system ready event
   DispatchEvent(new HeartbeatEvent(0));

   return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   EventBus::Release();

   DashboardManagerFactory::Destroy(dashCtrl);
   if (CheckPointer(g_recorder) != POINTER_INVALID)
   {
      delete g_recorder;
      g_recorder = NULL;
   }

   dashboard.Destroy(reason);
   Comment("");
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   dashboard.ChartEvent(id, lparam, dparam, sparam);
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if (trans.type == TRADE_TRANSACTION_DEAL_ADD && HistoryDealSelect(trans.deal))
   {
      if (HistoryDealGetInteger(trans.deal, DEAL_MAGIC) == eaCfg.magicNum &&
          HistoryDealGetString(trans.deal, DEAL_SYMBOL) == _Symbol)
      {
         long entryType = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
         ulong positionID = trans.position;

         if (entryType == DEAL_ENTRY_IN)
         { // New position opened
            string comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
            int hashPos = StringFind(comment, "#");
            ulong tsID = 0;
            if (hashPos >= 0)
               tsID = (ulong)StringToInteger(StringSubstr(comment, hashPos + 1));

            ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
            double entry = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
            double volume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
            double sl = HistoryDealGetDouble(trans.deal, DEAL_SL);
            double tp = HistoryDealGetDouble(trans.deal, DEAL_TP);
            double slMult = 1.0;

            // Robust SL/TP lookup: HistoryDeal might hve 0 if orders were modified async
            if (PositionSelectByTicket(positionID))
            {
               if (sl <= 0)
                  sl = PositionGetDouble(POSITION_SL);
               if (tp <= 0)
                  tp = PositionGetDouble(POSITION_TP);
            }

            // Context from Global Variables (sent from ExecutionManager)
            if (tsID > 0)
            {
               string p = "PASR_PEND_" + (string)eaCfg.magicNum + "_" + _Symbol + "_" + (string)tsID + "_";
               if (GlobalVariableCheck(p + "ts"))
               {
                  if (tp <= 0)
                     tp = GlobalVariableGet(p + "tp");
                  if (GlobalVariableCheck(p + "sm"))
                     slMult = GlobalVariableGet(p + "sm");
                  // Clean up the pending GV after successful confirmation
                  GlobalVariablesDeleteAll("PASR_PEND_" + (string)eaCfg.magicNum + "_" + _Symbol + "_" + (string)tsID);
               }
            }

            // Dispatch final confirmation event for RecoveryManager to register the position
            OrderExecutionEvent *confirm = new OrderExecutionEvent(
                true, positionID, type, entry, sl, tp, volume, "Confirmed", comment);
            DispatchEvent(confirm);

            // Register with correct SLMult for Adaptive Recovery
            recovery.Register(positionID, type, entry, tp, sl, dta.GetATRPoints(), volume, 0, slMult);

            datetime times[];
            if (CopyTime(_Symbol, _Period, 0, 1, times) > 0)
               market.UpdateLastEntryBarTime(times[0]);
         }
         else if (entryType == DEAL_ENTRY_OUT || entryType == DEAL_ENTRY_INOUT)
         {
            // Refresh daily stats
            dta.RefreshDailyProfit();
            double netProfit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) +
                               HistoryDealGetDouble(trans.deal, DEAL_COMMISSION) +
                               HistoryDealGetDouble(trans.deal, DEAL_SWAP);
            dta.UpdateConsecutiveLosses(netProfit);

            string comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
            int recovPos = StringFind(comment, "RECOV_ORIG_");
            if (recovPos == 0)
            {
               int ticketStart = StringLen("RECOV_ORIG_");
               int ticketEnd = StringFind(comment, "_P_", ticketStart);
               if (ticketEnd > ticketStart)
               {
                  ulong originalTicket = (ulong)StringToInteger(StringSubstr(comment, ticketStart, ticketEnd - ticketStart));
                  recovery.NotifyRecoverySuccess(originalTicket);
               }
            }
         }
      }
   }
   // Other transaction handling (e.g., for pending orders, modifications) can go here
}

void OnTimer()
{
   // Dispatch heartbeat for periodic tasks (UI update, health checks, etc)
   DispatchEvent(new HeartbeatEvent(2));
}

void OnTick()
{
   MqlTick tick;
   if (!SymbolInfoTick(_Symbol, tick))
      return;

   // Dispatch price update event (lightweight)
   DispatchEvent(new PriceUpdateEvent(tick));

   // Check for new bar -> dispatch NewBarEvent dengan CopyTime (MQL5 Best Practice)
   static datetime lastBarTime = 0;

   datetime times[];
   if (CopyTime(_Symbol, _Period, 0, 1, times) <= 0)
      return;
   datetime currentBar = times[0];

   if (currentBar != lastBarTime)
   {
      lastBarTime = currentBar;
      market.SetLastBarTime(currentBar);

      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if (CopyRates(_Symbol, _Period, 0, 1, rates) > 0)
      {
         DispatchEvent(new NewBarEvent(
             currentBar,
             rates[0].open,
             rates[0].high,
             rates[0].low,
             rates[0].close,
             _Period));
      }
   }
}