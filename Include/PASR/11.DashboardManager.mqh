//+------------------------------------------------------------------+
//|               Price Action & Support Resistance V1               |
//|         Optimized by Agsicentre (agsicentre.wordpress.com)       |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "1.00"

#ifndef __DASHBOARD_MANAGER_MQH__
#define __DASHBOARD_MANAGER_MQH__

#property strict
#include "mql5_vscode_fix.h"
#include "2.Config.mqh"
#include "IManager.mqh"
#include "10.DataManager.mqh"
#include <Controls/Dialog.mqh>
#include <Controls/Button.mqh>
#include <Controls/Label.mqh>
#include <Controls/Panel.mqh>
#include <Graphics/Graphic.mqh>
#include <Trade/Trade.mqh>

// Custom Event IDs for UI synchronization
#define DASHBOARD_REFRESH (CHARTEVENT_CUSTOM + 100)
#define DASHBOARD_EMERGENCY (CHARTEVENT_CUSTOM + 101)
#define DASHBOARD_PAUSE (CHARTEVENT_CUSTOM + 102)
#define DASHBOARD_STATS (CHARTEVENT_CUSTOM + 103)
#define DASHBOARD_CLOSEALL (CHARTEVENT_CUSTOM + 104)
#define DASHBOARD_RESET_STATS (CHARTEVENT_CUSTOM + 105)
#define DASHBOARD_RELOAD_CONFIG (CHARTEVENT_CUSTOM + 106)

// Color Scheme - Modern Dark Theme
#define CLR_BG_PRIMARY   0x201B19            // Dark background (C'25,27,32')
#define CLR_BG_SECONDARY 0x2C2623            // Panel background (C'35,38,44')
#define CLR_BG_ACCENT    0x38302D            // Highlight background (C'45,48,56')
#define CLR_TEXT_PRIMARY 0xDCDCDC            // Primary text (C'220,220,220')
#define CLR_TEXT_SECONDARY 0xA09696          // Secondary text (C'150,150,160')
#define CLR_SUCCESS      0x8EC748            // Green - Profit/Buy (C'72,199,142')
#define CLR_DANGER       0x5E59FF            // Red - Loss/Sell (C'255,89,94')
#define CLR_WARNING      0x00CCFF            // Yellow - Warning (C'255,204,0')
#define CLR_INFO         0xFF9C40            // Blue - Info (C'64,156,255')
#define CLR_ACCENT       0xDE52AF            // Purple - Accent (C'175,82,222')

// UI Layout Constants
#define DASHBOARD_HEADER_HEIGHT 50
#define DASHBOARD_SECTION_HEIGHT 80
#define DASHBOARD_CONTROLS_HEIGHT 70
#define DASHBOARD_MARGIN 10
#define DASHBOARD_PADDING 5
#define DASHBOARD_FONT_SIZE_TITLE 11
#define DASHBOARD_FONT_SIZE_LABEL 10
#define DASHBOARD_FONT_SIZE_INFO 9
#define DASHBOARD_BUTTON_HEIGHT 25

class DashboardUI;

/**
 * Cache structure for UI data - minimizes calls to data manager
 * Updates on heartbeat to ensure responsive dashboard
 */
struct DataCacheUI
{
   // --- Dynamic Market & Signal Data ---
   double atrPoints;
   double spread;
   bool gateOpen;
   bool allowed;
   string lastPattern;
   int lastDir;
   datetime nextNews;
   string newsStatus;
   PositionScanResult scanResult;
   PerformanceStats perfStats;
   datetime lastUpdate;

   // --- Real-time Account Info ---
   double equity;
   double balance;
   double dailyProfit;
   double floatingProfit;
   double drawdownPct;
   int totalTrades;
   int openPositions;

   // --- Strategy Configuration (Static Cache) ---
   ulong magicNum;
   double maxDailyLossPct;
   bool useNews;
};

/**
 * Manages dashboard data and event coordination
 * Synchronizes between data manager and UI components
 */
class DashboardManager : public IManager
{
private:
   DashboardUI *m_ui;    ///< Pointer to UI component
   long m_chart;         ///< Chart ID for custom events
   DataCacheUI m_cache;  ///< Cached data for UI updates
   CTrade m_trade;       ///< Trade helper for position operations

   void RefreshCache()
   {
      if (CheckPointer(m_data) == POINTER_INVALID)
         return;

      // 1. Ambil data mentah dari DataManager
      m_cache.scanResult = m_data.GetScanResult();
      m_cache.perfStats = m_data.GetPerformanceStats();
      m_cache.atrPoints = m_data.GetATRPoints();
      m_cache.spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);

      // 2. Kalkulasi variabel tampilan UI
      m_cache.equity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_cache.balance = AccountInfoDouble(ACCOUNT_BALANCE);
      m_cache.dailyProfit = m_cache.scanResult.dailyRealized;
      m_cache.floatingProfit = m_cache.scanResult.floatingPnL;
      m_cache.drawdownPct = m_cache.scanResult.dailyDrawdown;
      m_cache.totalTrades = m_cache.perfStats.safeTotal + m_cache.perfStats.aggTotal;
      m_cache.openPositions = m_cache.scanResult.normalCount;
      
      m_cache.lastUpdate = TimeCurrent();
   }

public:
   /**
    * Constructor
    */
   DashboardManager() : IManager("DashboardManager", 80), m_ui(NULL)
   {
      m_chart = ChartID();
      ZeroMemory(m_cache);
   }

   /**
    * Initialize Dashboard Manager
    * @return True if initialized successfully
    */
   virtual bool Init() override
   {
      if (!IManager::Init())
         return false;

      RefreshCache();
      return true;
   }

   /**
    * Set UI component reference
    * @param ui Pointer to DashboardUI instance
    */
   void SetUI(DashboardUI *ui) { m_ui = ui; }

   /**
    * Get current data cache
    * @return Reference to cached data
    */
   DataCacheUI GetCache() const { return m_cache; }

   /**
    * Refresh configuration cache - called on config reload
    * Synchronizes configuration values with UI cache
    */
   virtual void RefreshConfigCache() override
   {
      IManager::RefreshConfigCache(); 
      
      // Sinkronisasi config statis ke cache UI
      m_cache.magicNum = CFG.MagicNum;
      m_cache.maxDailyLossPct = CFG.MaxDailyLossPct;
      m_cache.useNews = (CFG.NewsLevel != NEWS_OFF);
   }

   /**
    * Handle configuration reload event
    * @param e Pointer to reload event
    */
   virtual void OnConfigReload(ConfigReloadEvent *e) override
   {
      if (e == NULL)
         return;
      IManager::OnConfigReload(e);
      if (m_chart > 0)
         EventChartCustom(m_chart, DASHBOARD_REFRESH, 0, 0, "");
   }

   /**
    * Declare which events this manager subscribes to
    */
   virtual void DeclareEvents() override
   {
      AddEvent(EVENT_ID_HEARTBEAT);
      AddEvent(EVENT_ID_EMERGENCY_STOP);
      AddEvent(EVENT_ID_PAUSE_TOGGLE);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
      AddEvent(EVENT_ID_MARKET_GATE);
      AddEvent(EVENT_ID_POSITION_UPDATE);
      AddEvent(EVENT_ID_SIGNAL_GENERATED);
      AddEvent(EVENT_ID_NEWS_ALERT);
   }

   /**
    * Handle heartbeat event - refresh UI cache
    * @param e Pointer to heartbeat event
    */
   virtual void OnHeartbeat(HeartbeatEvent *e) override
   {
      if (e == NULL)
         return;
      RefreshCache();
      if (m_chart > 0)
         EventChartCustom(m_chart, DASHBOARD_REFRESH, 0, 0, "");
   }

   /**
    * Handle emergency stop event - update UI status
    * @param e Pointer to emergency stop event
    */
   virtual void OnEmergencyStop(EmergencyStopEvent *e) override
   {
      if (e == NULL)
         return;
      EventChartCustom(m_chart, DASHBOARD_EMERGENCY, 0, 0, e.reason);
   }

   /**
    * Handle market gate status change
    * @param mg Pointer to market gate event
    */
   virtual void OnMarketGate(MarketGateEvent *mg) override
   {
      if (mg == NULL)
         return;
      m_cache.gateOpen = mg.gateOpen;
      m_cache.spread = mg.spread;
      m_cache.allowed = mg.entryAllowed;
      m_cache.atrPoints = mg.atrPoints;
      if (m_chart > 0)
         EventChartCustom(m_chart, DASHBOARD_REFRESH, 0, 0, "");
   }

   /**
    * Handle position update event - refresh UI to show real-time changes
    * @param e Pointer to position update event
    */
   virtual void OnPositionUpdate(PositionUpdateEvent *e) override
   {
      if (CheckPointer(e) == POINTER_INVALID)
         return;
      RefreshCache();
      if (m_chart > 0)
         EventChartCustom(m_chart, DASHBOARD_REFRESH, 0, 0, "");
   }

   /**
    * Handle news alert event - update news info on dashboard
    * @param e Pointer to news alert event
    */
   virtual void OnNewsAlert(NewsAlertEvent *e) override
   {
      if (CheckPointer(e) == POINTER_INVALID)
         return;
      m_cache.nextNews = e.eventTime;
      m_cache.newsStatus = e.newsTitle;
      if (m_chart > 0)
         EventChartCustom(m_chart, DASHBOARD_REFRESH, 0, 0, "");
   }

   /**
    * Handle signal generated event
    * @param sg Pointer to signal event
    */
   virtual void OnSignalGenerated(SignalGeneratedEvent *sg) override
   {
      if (sg == NULL)
         return;
      m_cache.lastPattern = EnumToString(sg.signal.patternType);
      m_cache.lastDir = (sg.signal.orderType == ORDER_TYPE_BUY) ? 1 : -1;
      if (m_chart > 0)
         EventChartCustom(m_chart, DASHBOARD_REFRESH, 0, 0, "");
   }

   /**
    * Handle pause toggle event
    * @param pt Pointer to pause toggle event
    */
   virtual void OnPauseToggle(PauseToggleEvent *pt) override
   {
      if (pt == NULL)
         return;
      if (m_chart > 0)
         EventChartCustom(m_chart, DASHBOARD_PAUSE, pt.isBuy ? 1 : 0, (long)pt.newState, "");
   }

   /**
    * Close all open positions for this EA
    * @return Number of positions closed
    */
   int CloseAllPositions()
   {
      if (m_cache.magicNum == 0)
      {
         Log("[Dashboard] Error: Invalid magic number");
         return 0;
      }

      m_trade.SetExpertMagicNumber(m_cache.magicNum);
      int closedCount = 0;

      for (int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if (ticket == 0)
            continue;

         if (PositionSelectByTicket(ticket))
         {
            ulong posMagic = PositionGetInteger(POSITION_MAGIC);
            string posSymbol = PositionGetString(POSITION_SYMBOL);

            if (posMagic == m_cache.magicNum && posSymbol == _Symbol)
            {
               if (m_trade.PositionClose(ticket))
               {
                  closedCount++;
               }
               else if (m_debugMode)
               {
                  PrintFormat("[Dashboard] Failed to close %d: %d", ticket, GetLastError());
               }
            }
         }
      }

      Log(StringFormat("[Dashboard] Close All executed - %d positions closed", closedCount));
      return closedCount;
   }

   /**
    * Handle generic custom events
    * @param e Pointer to generic event
    */
   virtual void OnCustomEvent(Event *e) override
   {
      if (e == NULL)
         return;
      // Override in subclasses for specific custom event handling
   }

   /**
    * Handle UI-triggered actions via Chart Events
    * @param id Event ID
    * @param lparam Long parameter
    * @param dparam Double parameter
    * @param sparam String parameter
    */
   void HandleUIEvent(int id, long lparam, double dparam, string sparam)
   {
      switch (id)
      {
      case DASHBOARD_CLOSEALL:
         CloseAllPositions();
         break;

      case DASHBOARD_RESET_STATS:
         if (CheckPointer(m_data) != POINTER_INVALID)
         {
            m_data.ResetDailyAnchor();
            m_data.UpdateConsecutiveLosses(0);
            Log("User triggered performance statistics reset.");
            RefreshCache();
            if (m_chart > 0)
               EventChartCustom(m_chart, DASHBOARD_REFRESH, 0, 0, "");
         }
         break;

      case DASHBOARD_RELOAD_CONFIG:
         Log("User triggered manual configuration reload.");
         EventBus::Instance().Dispatch(new ConfigReloadEvent());
         break;
      }
   }
};

/**
 * Factory for creating and managing DashboardManager instances
 * Handles initialization validation and lifecycle management
 */
class DashboardManagerFactory
{
public:
   /**
    * Create a new DashboardManager instance
    * @param dataManager Pointer to DataManager
    * @return Pointer to created manager, or NULL on failure
    */
   static DashboardManager *Create(DashboardUI *ui, DataManager *dataManager)
   {
      if (CheckPointer(ui) == POINTER_INVALID || CheckPointer(dataManager) == POINTER_INVALID)
      {
         Print("[DashboardManagerFactory] Error: Invalid UI or DataManager pointer");
         return NULL;
      }

      DashboardManager *ctrl = new DashboardManager();
      if (CheckPointer(ctrl) != POINTER_INVALID)
      {
         ctrl.SetUI(ui);
         ctrl.SetDataManager(dataManager);
         if (!ctrl.Init())
         {
            Print("[DashboardManagerFactory] Error: Failed to initialize DashboardManager");
            delete ctrl;
            return NULL;
         }
      }
      else
      {
         Print("[DashboardManagerFactory] Error: Failed to allocate DashboardManager");
         return NULL;
      }
      return ctrl;
   }

   static void Destroy(DashboardManager *&ctrl)
   {
      if (CheckPointer(ctrl) != POINTER_INVALID)
      {
         delete ctrl;
         ctrl = NULL;
      }
   }
};

/**
 * Professional Dashboard UI - Real-time Trading Analytics
 * Displays account metrics, market conditions, signals, and performance stats
 */
class DashboardUI : public CAppDialog
{
private:
   DashboardManager *m_ctrl; ///< Controller reference
   long m_chart_id;          ///< Chart ID (stored separately for reliability)
   int m_subwin;             ///< Subwindow index

   // Background panels
   CPanel m_pnlHeader, m_pnlAccount, m_pnlMarket, m_pnlSignal, m_pnlStats, m_pnlControls;

   // Labels - Header Section
   CLabel m_lblTitle, m_lblStatus, m_lblMode;

   // Labels - Account Section
   CLabel m_lblBalance, m_lblEquity, m_lblProfitDaily, m_lblProfitFloat, m_lblDrawdown;
   CLabel m_lblSecAccount;

   // Labels - Market Section
   CLabel m_lblSpread, m_lblATR, m_lblGate, m_lblPositions;
   CLabel m_lblSecMarket; ///< Section title

   // Labels - Signal Section
   CLabel m_lblPattern, m_lblDirection, m_lblNews;
   CLabel m_lblSecSignal; ///< Section title

   // Labels - Stats Section
   CLabel m_lblWinRate, m_lblTotalTrades, m_lblNetProfit;
   CLabel m_lblSecStats; ///< Section title

   // Buttons - Controls
   CButton m_btnPause, m_btnCloseAll, m_btnEmergency;
   ulong m_magic; ///< EA magic number

public:
   /**
    * Constructor
    */
   DashboardUI() : m_ctrl(NULL), m_magic(0), m_chart_id(0), m_subwin(0) {}

   /**
    * Set controller reference
    * @param ctrl Pointer to DashboardManager
    */
   void SetController(DashboardManager *ctrl) { m_ctrl = ctrl; }

   /**
    * Create dashboard UI with professional layout
    * @param chart Chart ID
    * @param name Dialog name
    * @param subwin Subwindow index
    * @param x1 Left coordinate
    * @param y1 Top coordinate
    * @param x2 Right coordinate
    * @param y2 Bottom coordinate
    * @return True if successfully created
    */
   virtual bool CreateDashboard(long chart, string name, int subwin, int x1, int y1, int x2, int y2)
   {
      // Validate dimensions
      if (x2 <= x1 || y2 <= y1)
      {
         Print("[Dashboard] Error: Invalid dimensions");
         return false;
      }

      // Store chart and subwindow references
      m_chart_id = chart;
      m_subwin = subwin;

      if (CheckPointer(m_ctrl) != POINTER_INVALID)
      {
         m_ctrl.RefreshConfigCache();
         m_magic = m_ctrl.GetCache().magicNum;
      }
      else
         m_magic = 0;

      // Calculate dimensions
      int width = x2 - x1;
      int height = y2 - y1;
      int sectionHeight = (height - DASHBOARD_HEADER_HEIGHT - DASHBOARD_CONTROLS_HEIGHT - (DASHBOARD_MARGIN * 6)) / 4;

      if (sectionHeight <= 0)
      {
         Print("[Dashboard] Error: Dashboard height too small for layout");
         return false;
      }

      if (!CAppDialog::Create(chart, name, subwin, x1, y1, x2, y2))
         return false;

      int yPos = DASHBOARD_MARGIN;

      // === HEADER SECTION ===
      CreatePanel(m_pnlHeader,"header",DASHBOARD_MARGIN,yPos,width-DASHBOARD_MARGIN*2,DASHBOARD_HEADER_HEIGHT,CLR_BG_SECONDARY);
      Add(m_pnlHeader);

      // Title
      m_lblTitle.Create(m_chart_id, m_name + "_title", m_subwin, DASHBOARD_MARGIN + 5, yPos + DASHBOARD_PADDING, width - DASHBOARD_MARGIN, yPos + 25);
      m_lblTitle.Text("PASR MODULAR TRADING SYSTEM");
      m_lblTitle.FontSize(DASHBOARD_FONT_SIZE_TITLE);
      m_lblTitle.Color(CLR_TEXT_PRIMARY);
      Add(m_lblTitle);

      m_lblStatus.Create(m_chart_id, m_name + "_status", m_subwin, DASHBOARD_MARGIN + 5, yPos + 28, width / 2, yPos + 43);
      m_lblStatus.Text("● System Ready");
      m_lblStatus.FontSize(DASHBOARD_FONT_SIZE_INFO);
      m_lblStatus.Color(CLR_SUCCESS);
      Add(m_lblStatus);

      m_lblMode.Create(m_chart_id, m_name + "_mode", m_subwin, width / 2 + 5, yPos + 28, width - DASHBOARD_MARGIN, yPos + 43);
      m_lblMode.Text(MQLInfoInteger(MQL_TESTER) ? "◉ BACKTEST" : "◉ LIVE");
      m_lblMode.FontSize(DASHBOARD_FONT_SIZE_INFO);
      m_lblMode.Color(CLR_INFO);
      Add(m_lblMode);

      yPos += DASHBOARD_HEADER_HEIGHT + DASHBOARD_MARGIN;
      // === ACCOUNT SECTION ===
      CreatePanel(m_pnlAccount, "pnl_acc", DASHBOARD_MARGIN, yPos, width - DASHBOARD_MARGIN * 2, sectionHeight, CLR_BG_SECONDARY);
      Add(m_pnlAccount);

      // Section title
      m_lblSecAccount.Create(m_chart_id, m_name + "_sec_account", m_subwin, DASHBOARD_MARGIN + 5, yPos + DASHBOARD_PADDING, width - DASHBOARD_MARGIN, yPos + 20);
      m_lblSecAccount.Text("ACCOUNT OVERVIEW");
      m_lblSecAccount.FontSize(DASHBOARD_FONT_SIZE_INFO);
      m_lblSecAccount.Color(CLR_TEXT_SECONDARY);
      Add(m_lblSecAccount);

      // Balance & Equity
      m_lblBalance.Create(m_chart_id, m_name + "_bal", m_subwin, DASHBOARD_MARGIN + 5, yPos + 25, width / 2, yPos + 45);
      m_lblBalance.Text("Balance: $0.00");
      m_lblBalance.FontSize(DASHBOARD_FONT_SIZE_LABEL);
      m_lblBalance.Color(CLR_TEXT_PRIMARY);
      Add(m_lblBalance);

      m_lblEquity.Create(m_chart_id, m_name + "_eq", m_subwin, width / 2 + 10, yPos + 25, width - DASHBOARD_MARGIN, yPos + 45);
      m_lblEquity.Text("Equity: $0.00");
      m_lblEquity.FontSize(DASHBOARD_FONT_SIZE_LABEL);
      m_lblEquity.Color(CLR_TEXT_PRIMARY);
      Add(m_lblEquity);

      // Daily P&L
      m_lblProfitDaily.Create(m_chart_id, m_name + "_pnl_d", m_subwin, DASHBOARD_MARGIN + 5, yPos + 50, width / 2, yPos + 70);
      m_lblProfitDaily.Text("Daily P&L: $0.00");
      m_lblProfitDaily.FontSize(DASHBOARD_FONT_SIZE_INFO);
      m_lblProfitDaily.Color(CLR_TEXT_SECONDARY);
      Add(m_lblProfitDaily);

      // Floating P&L
      m_lblProfitFloat.Create(m_chart_id, m_name + "_pnl_f", m_subwin, width / 2 + 10, yPos + 50, width - DASHBOARD_MARGIN, yPos + 70);
      m_lblProfitFloat.Text("Floating: $0.00");
      m_lblProfitFloat.FontSize(DASHBOARD_FONT_SIZE_INFO);
      m_lblProfitFloat.Color(CLR_TEXT_SECONDARY);
      Add(m_lblProfitFloat);

      // Drawdown
      m_lblDrawdown.Create(m_chart_id, m_name + "_dd", m_subwin, DASHBOARD_MARGIN + 5, yPos + 75, width - DASHBOARD_MARGIN, yPos + 95);
      m_lblDrawdown.Text("Drawdown: 0.00%");
      m_lblDrawdown.FontSize(DASHBOARD_FONT_SIZE_INFO);
      m_lblDrawdown.Color(CLR_WARNING);
      Add(m_lblDrawdown);

      yPos += sectionHeight + DASHBOARD_MARGIN;

      // === MARKET SECTION ===
      CreatePanel(m_pnlMarket, "pnl_mkt", DASHBOARD_MARGIN, yPos, width - DASHBOARD_MARGIN * 2, sectionHeight, CLR_BG_SECONDARY);
      Add(m_pnlMarket);

      m_lblSecMarket.Create(m_chart_id, m_name + "_sec_market", m_subwin, DASHBOARD_MARGIN + 5, yPos + DASHBOARD_PADDING, width - DASHBOARD_MARGIN, yPos + 20);
      m_lblSecMarket.Text("MARKET CONDITIONS");
      m_lblSecMarket.FontSize(DASHBOARD_FONT_SIZE_INFO);
      m_lblSecMarket.Color(CLR_TEXT_SECONDARY);
      Add(m_lblSecMarket);

      m_lblSpread.Create(m_chart_id, m_name + "_spr", m_subwin, DASHBOARD_MARGIN + 5, yPos + 25, width / 2, yPos + 45);
      m_lblSpread.Text("Spread: 0.0 pts");
      m_lblSpread.FontSize(DASHBOARD_FONT_SIZE_LABEL);
      m_lblSpread.Color(CLR_TEXT_PRIMARY);
      Add(m_lblSpread);

      m_lblATR.Create(m_chart_id, m_name + "_atr", m_subwin, width / 2 + 10, yPos + 25, width - DASHBOARD_MARGIN, yPos + 45);
      m_lblATR.Text("ATR: 0.0 pts");
      m_lblATR.FontSize(DASHBOARD_FONT_SIZE_LABEL);
      m_lblATR.Color(CLR_TEXT_PRIMARY);
      Add(m_lblATR);

      m_lblGate.Create(m_chart_id, m_name + "_gate", m_subwin, DASHBOARD_MARGIN + 5, yPos + 50, width / 2, yPos + 70);
      m_lblGate.Text("Gate: CLOSED");
      m_lblGate.FontSize(DASHBOARD_FONT_SIZE_LABEL);
      m_lblGate.Color(CLR_DANGER);
      Add(m_lblGate);

      m_lblPositions.Create(m_chart_id, m_name + "_pos", m_subwin, width / 2 + 10, yPos + 50, width - DASHBOARD_MARGIN, yPos + 70);
      m_lblPositions.Text("Open: 0");
      m_lblPositions.FontSize(DASHBOARD_FONT_SIZE_LABEL);
      m_lblPositions.Color(CLR_INFO);
      Add(m_lblPositions);

      yPos += sectionHeight + DASHBOARD_MARGIN;
      // === SIGNAL SECTION ===
      CreatePanel(m_pnlSignal, "pnl_sig", DASHBOARD_MARGIN, yPos, width - DASHBOARD_MARGIN * 2, sectionHeight, CLR_BG_SECONDARY);
      Add(m_pnlSignal);

      m_lblSecSignal.Create(m_chart_id, m_name + "_sec_signal", m_subwin, DASHBOARD_MARGIN + 5, yPos + DASHBOARD_PADDING, width - DASHBOARD_MARGIN, yPos + 20);
      m_lblSecSignal.Text("SIGNAL STATUS");
      m_lblSecSignal.FontSize(DASHBOARD_FONT_SIZE_INFO);
      m_lblSecSignal.Color(CLR_TEXT_SECONDARY);
      Add(m_lblSecSignal);

      m_lblPattern.Create(m_chart_id, m_name + "_pat", m_subwin, DASHBOARD_MARGIN + 5, yPos + 25, width - DASHBOARD_MARGIN, yPos + 50);
      m_lblPattern.Text("Pattern: WAITING");
      m_lblPattern.FontSize(DASHBOARD_FONT_SIZE_TITLE);
      m_lblPattern.Color(CLR_TEXT_PRIMARY);
      Add(m_lblPattern);

      m_lblDirection.Create(m_chart_id, m_name + "_dir", m_subwin, DASHBOARD_MARGIN + 5, yPos + 55, width / 2, yPos + 75);
      m_lblDirection.Text("Direction: NEUTRAL");
      m_lblDirection.FontSize(DASHBOARD_FONT_SIZE_LABEL);
      m_lblDirection.Color(CLR_TEXT_SECONDARY);
      Add(m_lblDirection);

      m_lblNews.Create(m_chart_id, m_name + "_news", m_subwin, width / 2 + 10, yPos + 55, width - DASHBOARD_MARGIN, yPos + 75);
      m_lblNews.Text("News: CLEAR");
      m_lblNews.FontSize(DASHBOARD_FONT_SIZE_LABEL);
      m_lblNews.Color(CLR_SUCCESS);
      Add(m_lblNews);

      yPos += sectionHeight + DASHBOARD_MARGIN;

      // === STATS SECTION ===
      CreatePanel(m_pnlStats, "pnl_stats", DASHBOARD_MARGIN, yPos, width - DASHBOARD_MARGIN * 2, sectionHeight, CLR_BG_SECONDARY);
      Add(m_pnlStats);

      m_lblSecStats.Create(m_chart_id, m_name + "_sec_stats", m_subwin, DASHBOARD_MARGIN + 5, yPos + DASHBOARD_PADDING, width - DASHBOARD_MARGIN, yPos + 20);
      m_lblSecStats.Text("PERFORMANCE");
      m_lblSecStats.FontSize(DASHBOARD_FONT_SIZE_INFO);
      m_lblSecStats.Color(CLR_TEXT_SECONDARY);
      Add(m_lblSecStats);

      m_lblWinRate.Create(m_chart_id, m_name + "_wr", m_subwin, DASHBOARD_MARGIN + 5, yPos + 25, width / 2, yPos + 45);
      m_lblWinRate.Text("Win Rate: 0%");
      m_lblWinRate.FontSize(DASHBOARD_FONT_SIZE_LABEL);
      m_lblWinRate.Color(CLR_ACCENT);
      Add(m_lblWinRate);

      m_lblTotalTrades.Create(m_chart_id, m_name + "_trd", m_subwin, width / 2 + 10, yPos + 25, width - DASHBOARD_MARGIN, yPos + 45);
      m_lblTotalTrades.Text("Trades: 0");
      m_lblTotalTrades.FontSize(DASHBOARD_FONT_SIZE_LABEL);
      m_lblTotalTrades.Color(CLR_TEXT_PRIMARY);
      Add(m_lblTotalTrades);

      m_lblNetProfit.Create(m_chart_id, m_name + "_net", m_subwin, DASHBOARD_MARGIN + 5, yPos + 50, width - DASHBOARD_MARGIN, yPos + 70);
      m_lblNetProfit.Text("Net Profit: $0.00");
      m_lblNetProfit.FontSize(DASHBOARD_FONT_SIZE_LABEL);
      m_lblNetProfit.Color(CLR_TEXT_PRIMARY);
      Add(m_lblNetProfit);

      yPos += sectionHeight + DASHBOARD_MARGIN;

      // === CONTROLS SECTION ===
      CreatePanel(m_pnlControls, "pnl_ctrl", DASHBOARD_MARGIN, yPos, width - DASHBOARD_MARGIN * 2, DASHBOARD_CONTROLS_HEIGHT, CLR_BG_ACCENT);
      Add(m_pnlControls);

      // Calculate button dimensions
      int btnWidth = (width - DASHBOARD_MARGIN * 4) / 3;
      int btnX1 = DASHBOARD_MARGIN + 5;
      int btnX2 = btnX1 + btnWidth;
      int btnX3 = btnX2 + DASHBOARD_MARGIN + btnWidth;
      int btnTop = yPos + 10;
      int btnBottom = yPos + DASHBOARD_CONTROLS_HEIGHT - 10;

      // Pause Button
      m_btnPause.Create(m_chart_id, m_name + "_pause", m_subwin, btnX1, btnTop, btnX1 + btnWidth - 5, btnBottom);

      bool isPaused = GlobalVariableCheck("PASR_PAUSE_" + (string)m_magic);
      if (isPaused)
      {
         m_btnPause.Text("▶ RESUME");
         m_btnPause.ColorBackground(CLR_SUCCESS);
      }
      else
      {
         m_btnPause.Text("⏸ PAUSE");
         m_btnPause.ColorBackground(CLR_WARNING);
      }

      m_btnPause.Color(clrBlack);
      Add(m_btnPause);

      // Close All Button
      m_btnCloseAll.Create(m_chart_id, m_name + "_close", m_subwin, btnX2, btnTop, btnX2 + btnWidth - DASHBOARD_MARGIN, btnBottom);
      m_btnCloseAll.Text("✕ CLOSE ALL");
      m_btnCloseAll.ColorBackground(CLR_BG_SECONDARY);
      m_btnCloseAll.Color(CLR_TEXT_PRIMARY);
      Add(m_btnCloseAll);

      // Emergency Stop Button
      m_btnEmergency.Create(m_chart_id, m_name + "_emerg", m_subwin, btnX3, btnTop, width - DASHBOARD_MARGIN - 5, btnBottom);
      m_btnEmergency.Text("⚠ EMERGENCY");
      m_btnEmergency.ColorBackground(CLR_DANGER);
      m_btnEmergency.Color(clrWhite);
      Add(m_btnEmergency);

      return true;
   }

   /**
    * Helper function to create panel with standard styling
    * @param panel Reference to panel to create
    * @param name Panel name
    * @param x1 Left coordinate
    * @param y1 Top coordinate
    * @param x2 Right coordinate
    * @param y2 Bottom coordinate
    * @param bg Background color
    */
   void CreatePanel(CPanel &panel, string name, int x1, int y1, int x2, int y2, color bg)
   {
      if (x2 <= x1 || y2 <= y1)
         return;

      panel.Create(m_chart_id, m_name + "_" + name, m_subwin, x1, y1, x2, y2);
      panel.BackgroundColor(bg);
      panel.BorderType(BORDER_FLAT);
      panel.ColorBorder(CLR_BG_ACCENT);
   }

   virtual bool OnEvent(const int id, const long &lparam, const double &dparam, const string &sparam) override
   {
      if (id == CHARTEVENT_OBJECT_CLICK)
      {
         if (sparam == m_btnPause.Name())
         {
            OnPauseClick();
            return true;
         }
         if (sparam == m_btnCloseAll.Name())
         {
            OnCloseAllClick();
            return true;
         }
         if (sparam == m_btnEmergency.Name())
         {
            OnEmergencyClick();
            return true;
         }
      }

      if (id >= CHARTEVENT_CUSTOM)
      {
         if (id == DASHBOARD_REFRESH)
         {
            UpdateUI();
            return true;
         }
         if (id == DASHBOARD_EMERGENCY)
         {
            m_lblStatus.Text("● EMERGENCY STOP");
            m_lblStatus.Color(CLR_DANGER);
            return true;
         }
         if (id == DASHBOARD_PAUSE)
         {
            SyncPauseButton((bool)lparam, (bool)dparam);
            return true;
         }

         if (CheckPointer(m_ctrl) != POINTER_INVALID)
            m_ctrl.HandleUIEvent(id, lparam, dparam, sparam);

         return true;
      }
      return CAppDialog::OnEvent(id, lparam, dparam, sparam);
   }

   void UpdateUI()
   {
      if (CheckPointer(m_ctrl) == POINTER_INVALID)
         return;

      const DataCacheUI cache = m_ctrl.GetCache();

      // === UPDATE HEADER ===
      string mode = MQLInfoInteger(MQL_TESTER) ? "◉ BACKTEST" : "◉ LIVE";
      m_lblMode.Text(mode);
         m_lblStatus.Text("● EMERGENCY STOP");
         m_lblStatus.Color(CLR_DANGER);
         
         m_btnEmergency.Text("🔓 RESET STOP");
         m_btnEmergency.ColorBackground(CLR_SUCCESS);
      }
      else
      {
         m_lblStatus.Text("● System Active");
         m_lblStatus.Color(CLR_SUCCESS);
         
         m_btnEmergency.Text("⚠ EMERGENCY");
         m_btnEmergency.ColorBackground(CLR_DANGER);
      }

      // === UPDATE ACCOUNT SECTION ===
      m_lblBalance.Text(StringFormat("Balance: $%.2f", cache.balance));
      m_lblEquity.Text(StringFormat("Equity: $%.2f", cache.equity));

      // Daily P&L with color coding
      double daily = cache.dailyProfit;
      m_lblProfitDaily.Text(StringFormat("Daily P&L: $%.2f", daily));
      m_lblProfitDaily.Color(daily >= 0 ? CLR_SUCCESS : CLR_DANGER);

      // Floating P&L with color coding
      double floating = cache.floatingProfit;
      m_lblProfitFloat.Text(StringFormat("Floating: $%.2f", floating));
      m_lblProfitFloat.Color(floating >= 0 ? CLR_SUCCESS : CLR_DANGER);

      // Drawdown with warning levels
      double dd = cache.drawdownPct;
      m_lblDrawdown.Text(StringFormat("Drawdown: %.2f%%", dd));
      if (dd > cache.maxDailyLossPct * 0.8)
         m_lblDrawdown.Color(CLR_DANGER);
      else if (dd > cache.maxDailyLossPct * 0.5)
         m_lblDrawdown.Color(CLR_WARNING);
      else
         m_lblDrawdown.Color(CLR_TEXT_SECONDARY);

      // === UPDATE MARKET SECTION ===
      m_lblSpread.Text(StringFormat("Spread: %.1f pts", cache.spread));
      m_lblATR.Text(StringFormat("ATR: %.1f pts", cache.atrPoints));

      // Gate status
      string gateStr = cache.gateOpen ? "OPEN ✓" : "CLOSED ✗";
      if (cache.gateOpen && !cache.allowed) gateStr = "COOLDOWN ⏳";
      m_lblGate.Text(StringFormat("Gate: %s", gateStr));
      m_lblGate.Color(cache.gateOpen ? CLR_SUCCESS : CLR_DANGER);

      m_lblPositions.Text(StringFormat("Open Positions: %d", cache.openPositions));

      // === UPDATE SIGNAL SECTION ===
      string pattern = cache.lastPattern;
      StringReplace(pattern, "PATTERN_", "");
      pattern = (pattern != "" && pattern != "NONE") ? pattern : "WAITING FOR SIGNAL";
      m_lblPattern.Text(StringFormat("Pattern: %s", pattern));

      // Direction with color
      string direction = "NEUTRAL";
      color dirColor = CLR_TEXT_SECONDARY;
      if (cache.lastDir == 1)
      {
         direction = "BUY ↑";
         dirColor = CLR_SUCCESS;
      }
      else if (cache.lastDir == -1)
      {
         direction = "SELL ↓";
         dirColor = CLR_DANGER;
      }
      m_lblDirection.Text(StringFormat("Direction: %s", direction));
      m_lblDirection.Color(dirColor);

      // News status
      if (cache.useNews)
      {
         string title = (cache.newsStatus != "" && cache.newsStatus != "Market Clear") ? cache.newsStatus : "CLEAR";
         long secondsToNews = (long)cache.nextNews - (long)TimeGMT();
         if (secondsToNews > 0 && secondsToNews < 3600)
         {
            m_lblNews.Text(StringFormat("News: %s (IN %dM)", title, (int)(secondsToNews / 60)));
            m_lblNews.Color(CLR_WARNING);
         }
         else if (secondsToNews <= 0 && secondsToNews > -1800 && cache.nextNews > 0)
         {
            m_lblNews.Text("News: ACTIVE ⛔");
            m_lblNews.Color(CLR_DANGER);
         }
         else
         {
            m_lblNews.Text("News: CLEAR ✓");
            m_lblNews.Color(CLR_SUCCESS);
         }
      }
      else
      {
         m_lblNews.Text("News: OFF");
         m_lblNews.Color(CLR_TEXT_SECONDARY);
      }

      // === UPDATE STATS SECTION ===
      int totalTrades = cache.perfStats.safeTotal + cache.perfStats.aggTotal;
      double winRate = 0.0;
      if (totalTrades > 0)
         winRate = (double)(cache.perfStats.safeWins + cache.perfStats.aggWins) / totalTrades * 100.0;

      m_lblWinRate.Text(StringFormat("Win Rate: %.1f%%", winRate));
      m_lblWinRate.Color(winRate >= 50 ? CLR_SUCCESS : CLR_WARNING);
      m_lblTotalTrades.Text(StringFormat("Total Trades: %d", totalTrades));
      m_lblNetProfit.Text(StringFormat("Daily Realized: $%.2f", cache.dailyProfit));
      m_lblNetProfit.Color(cache.dailyProfit >= 0 ? CLR_SUCCESS : CLR_DANGER);

   }

   // Button click handlers
   void OnPauseClick()
   {
      bool isPaused = GlobalVariableCheck("PASR_PAUSE_" + (string)m_magic);
      if (isPaused)
      {
         GlobalVariableDelete("PASR_PAUSE_" + (string)m_magic);
         DispatchEvent(new PauseToggleEvent(true, false));
         EventBus::Instance().Dispatch(new PauseToggleEvent(true, false));
      }
      else
         GlobalVariableSet("PASR_PAUSE_" + (string)m_magic, 1.0);
         DispatchEvent(new PauseToggleEvent(true, true));
         EventBus::Instance().Dispatch(new PauseToggleEvent(true, true));
      }
   }
    void SyncPauseButton(bool isBuy, bool state)

   void SyncPauseButton(bool isBuy, bool state)
   {
      if (state)
      {
         m_btnPause.Text("▶ RESUME");
         m_btnPause.ColorBackground(CLR_SUCCESS);
         m_btnPause.BackgroundColor(CLR_SUCCESS);
      }
      else
         m_btnPause.Text("⏸ PAUSE");
         m_btnPause.ColorBackground(CLR_WARNING);
         m_btnPause.BackgroundColor(CLR_WARNING);
      }
   }

   {
      if (MessageBox("Close all open positions?", "Confirm", MB_YESNO | MB_ICONQUESTION) == IDYES)
      {
         EventChartCustom(m_chart_id, DASHBOARD_CLOSEALL, 0, 0, "");
         Print("[Dashboard] Close All Positions triggered");
      }
   }

   void OnEmergencyClick()
   {
      string gvName = "PASR_EMERGENCY_" + (string)m_magic;
      if (GlobalVariableCheck(gvName))
      if (MessageBox("EMERGENCY STOP will close ALL positions and disable trading!", "WARNING", MB_YESNO | MB_ICONWARNING) == IDYES)
      {
         if (MessageBox("Emergency Stop sedang AKTIF. Apakah Anda ingin me-reset sistem dan mengizinkan trading kembali?", 
                        "Reset Emergency Stop", MB_YESNO | MB_ICONQUESTION) == IDYES)
            GlobalVariableDelete(gvName);
            Print("[Dashboard] Manual Emergency Stop di-reset oleh user. Sistem kembali normal.");
            UpdateUI();
         }
         GlobalVariableSet("PASR_EMERGENCY_" + (string)m_magic, 1);
         EventBus::Instance().Dispatch(new EmergencyStopEvent("Manual Emergency Stop from Dashboard"));
         Print("[Dashboard] EMERGENCY STOP ACTIVATED");
      }
         if (MessageBox("EMERGENCY STOP akan menutup SEMUA posisi dan menghentikan seluruh logika trading segera!\n\nApakah Anda yakin?", 
                        "⚠ PERINGATAN: EMERGENCY STOP", MB_YESNO | MB_ICONWARNING) == IDYES)
         {
            GlobalVariableSet(gvName, 1.0);
            EventBus::Instance().Dispatch(new EmergencyStopEvent("Manual Emergency Stop from Dashboard"));
            Print("[Dashboard] Manual Emergency Stop DIPICU. Semua posisi akan ditutup.");
         }
      }
   }
};

#endif
