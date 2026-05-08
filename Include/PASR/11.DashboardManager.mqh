//+------------------------------------------------------------------+
//|               Price Action & Support Resistance V1               |
//|         Optimized by Agsicentre (agsicentre.wordpress.com)       |
//|         Modern Dashboard UI - Professional Trading Interface     |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "2.00"
#property description "Modern Professional Dashboard with Real-time Analytics"

#ifndef __DASHBOARD_MANAGER_MQH__
#define __DASHBOARD_MANAGER_MQH__

#property strict
#include "0.EventBus.mqh"
#include "1.Events.mqh"
#include "2.Config.mqh"
#include "IManager.mqh"
#include "10.DataManager.mqh"
#include <Controls/Dialog.mqh>
#include <Controls/Button.mqh>
#include <Controls/Label.mqh>
#include <Controls/RectLabel.mqh>
#include <Graphics/Graphic.mqh>

// Custom Event IDs for UI synchronization
#define DASHBOARD_REFRESH   (CHARTEVENT_CUSTOM + 100)
#define DASHBOARD_EMERGENCY (CHARTEVENT_CUSTOM + 101)
#define DASHBOARD_PAUSE     (CHARTEVENT_CUSTOM + 102)
#define DASHBOARD_STATS     (CHARTEVENT_CUSTOM + 103)
#define DASHBOARD_CLOSEALL  (CHARTEVENT_CUSTOM + 104)

// Color Scheme - Modern Dark Theme
#define CLR_BG_PRIMARY      (C'25,27,32')        // Dark background
#define CLR_BG_SECONDARY    (C'35,38,44')        // Panel background
#define CLR_BG_ACCENT       (C'45,48,56')        // Highlight background
#define CLR_TEXT_PRIMARY    (C'220,220,220')     // Primary text
#define CLR_TEXT_SECONDARY  (C'150,150,160')     // Secondary text
#define CLR_SUCCESS         (C'72,199,142')      // Green - Profit/Buy
#define CLR_DANGER          (C'255,89,94')       // Red - Loss/Sell
#define CLR_WARNING         (C'255,204,0')       // Yellow - Warning
#define CLR_INFO            (C'64,156,255')      // Blue - Info
#define CLR_ACCENT          (C'175,82,222')      // Purple - Accent

class DashboardUI;

struct DataCacheUI
{
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
   double equity;
   double balance;
   double dailyProfit;
   double floatingProfit;
   double drawdownPct;
   int totalTrades;
   int openPositions;
};

class DashboardManager : public IManager
{
private:
   DashboardUI *m_ui;
   long m_chart;
   DataCacheUI m_cache;

   void RefreshCache()
   {
      if (CheckPointer(m_data) == POINTER_INVALID)
         return;
      
      m_cache.atrPoints = m_data.GetATRPoints();
      m_cache.spread = MarketInfoInteger(_Symbol, SYMBOL_SPREAD);
      m_cache.scanResult = m_data.GetScanResult();
      m_cache.perfStats = m_data.GetPerformanceStats();
      m_cache.lastUpdate = TimeCurrent();
      
      // Update account info
      m_cache.equity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_cache.balance = AccountInfoDouble(ACCOUNT_BALANCE);
      m_cache.dailyProfit = m_cache.scanResult.dailyRealized;
      m_cache.floatingProfit = m_cache.scanResult.floatingPnL;
      m_cache.drawdownPct = m_cache.scanResult.dailyDrawdown;
      m_cache.totalTrades = m_cache.perfStats.safeTotal + m_cache.perfStats.aggTotal;
      m_cache.openPositions = PositionsTotal();
   }

public:
   DashboardManager() : IManager("DashboardManager", 90), m_ui(NULL), m_chart(0)
   {
      m_chart = ChartID();
      m_cache.lastPattern = "NONE";
      m_cache.lastDir = 0;
      ZeroMemory(m_cache);
   }

   void SetUI(DashboardUI *ui) { m_ui = ui; }
   DataCacheUI GetCache() const { return m_cache; }

   virtual void DeclareEvents() override
   {
      AddEvent("Heartbeat");
      AddEvent("EmergencyStop");
      AddEvent("PauseToggle");
      AddEvent("ConfigReload");
      AddEvent("MarketGate");
      AddEvent("SignalGenerated");
   }

   virtual void OnHeartbeat(HeartbeatEvent *e) override
   {
      RefreshCache();
      EventChartCustom(m_chart, DASHBOARD_REFRESH, 0, 0, "");
   }

   virtual void OnEmergencyStop(EmergencyStopEvent *e) override
   {
      EventChartCustom(m_chart, DASHBOARD_EMERGENCY, 0, 0, e.reason);
   }

   virtual void OnCustomEvent(Event *e) override
   {
      if (e.Type() == "PauseToggle")
      {
         PauseToggleEvent *pt = dynamic_cast<PauseToggleEvent *>(e);
         if (CheckPointer(pt) != POINTER_INVALID)
            EventChartCustom(m_chart, DASHBOARD_PAUSE, pt.isBuy ? 1 : 0, (long)pt.newState, "");
      }
      else if (e.Type() == "MarketGate")
      {
         MarketGateEvent *mg = dynamic_cast<MarketGateEvent *>(e);
         if (CheckPointer(mg) != POINTER_INVALID)
         {
            m_cache.gateOpen = mg.gateOpen;
            m_cache.spread = mg.spread;
            m_cache.allowed = mg.entryAllowed;
            m_cache.atrPoints = mg.atrPoints;
         }
      }
      else if (e.Type() == "SignalGenerated")
      {
         SignalGeneratedEvent *sg = dynamic_cast<SignalGeneratedEvent *>(e);
         if (CheckPointer(sg) != POINTER_INVALID)
         {
            m_cache.lastPattern = EnumToString(sg.signal.patternType);
            m_cache.lastDir = (sg.signal.orderType == ORDER_TYPE_BUY) ? 1 : -1;
         }
      }
   }
};

class DashboardManagerFactory
{
public:
   static DashboardManager *Create(DashboardUI *ui, DataManager *dataManager)
   {
      DashboardManager *ctrl = new DashboardManager();
      if (CheckPointer(ctrl) != POINTER_INVALID)
      {
         ctrl.SetUI(ui);
         ctrl.SetDataManager(dataManager);
         if (!ctrl.Init())
         {
            delete ctrl;
            return NULL;
         }
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

class DashboardUI : public CAppDialog
{
private:
   DashboardManager *m_ctrl;
   
   // Background panels
   CRectLabel m_pnlHeader, m_pnlAccount, m_pnlMarket, m_pnlSignal, m_pnlStats, m_pnlControls;
   
   // Labels - Header Section
   CLabel m_lblTitle, m_lblStatus, m_lblMode;
   
   // Labels - Account Section
   CLabel m_lblBalance, m_lblEquity, m_lblProfitDaily, m_lblProfitFloat, m_lblDrawdown;
   
   // Labels - Market Section
   CLabel m_lblSpread, m_lblATR, m_lblGate, m_lblPositions;
   
   // Labels - Signal Section
   CLabel m_lblPattern, m_lblDirection, m_lblNews;
   
   // Labels - Stats Section
   CLabel m_lblWinRate, m_lblTotalTrades, m_lblNetProfit;
   
   // Buttons - Controls
   CButton m_btnPause, m_btnCloseAll, m_btnEmergency;
   
   ulong m_magic;

public:
   DashboardUI() : m_ctrl(NULL), m_magic(0) {}
   void SetController(DashboardManager *ctrl) { m_ctrl = ctrl; }

   virtual bool CreateDashboard(long chart, string name, int subwin, int x1, int y1, int x2, int y2)
   {
      m_magic = CFG.MagicNum;
      
      // Calculate dimensions
      int width = x2 - x1;
      int height = y2 - y1;
      int sectionHeight = (height - 60) / 5; // 5 sections
      
      if (!CAppDialog::Create(chart, name, subwin, x1, y1, x2, y2))
         return false;
      
      // Set dialog background
      ColorBackground(CLR_BG_PRIMARY);
      BorderType(BORDER_FLAT);
      BorderColor(CLR_BG_ACCENT);
      
      int yPos = 15;
      
      // === HEADER SECTION ===
      CreatePanel(m_pnlHeader, "header", 10, yPos, width-20, 50, CLR_BG_SECONDARY);
      Add(m_pnlHeader);
      
      // Title
      m_lblTitle.Create(m_chart_id, m_name+"_title", m_subwin, 15, yPos+5, width-30, yPos+25);
      m_lblTitle.Text("PASR MODULAR TRADING SYSTEM");
      m_lblTitle.FontSize(11);
      m_lblTitle.FontFlags(FONT_BOLD);
      m_lblTitle.Color(CLR_TEXT_PRIMARY);
      m_lblTitle.Align(ALIGN_CENTER);
      Add(m_lblTitle);
      
      // Status and Mode
      m_lblStatus.Create(m_chart_id, m_name+"_status", m_subwin, 15, yPos+28, width/2-10, yPos+45);
      m_lblStatus.Text("● System Ready");
      m_lblStatus.FontSize(9);
      m_lblStatus.Color(CLR_SUCCESS);
      Add(m_lblStatus);
      
      m_lblMode.Create(m_chart_id, m_name+"_mode", m_subwin, width/2+5, yPos+28, width-15, yPos+45);
      m_lblMode.Text(MQLInfoInteger(MQL_TESTER) ? "◉ BACKTEST" : "◉ LIVE");
      m_lblMode.FontSize(9);
      m_lblMode.Color(CLR_INFO);
      Add(m_lblMode);
      
      yPos += 60;
      
      // === ACCOUNT SECTION ===
      CreatePanel(m_pnlAccount, "pnl_acc", 10, yPos, width-20, sectionHeight, CLR_BG_SECONDARY);
      Add(m_pnlAccount);
      
      // Section title
      CreateSectionTitle("ACCOUNT OVERVIEW", 15, yPos+5, width/2, yPos+20);
      
      // Balance & Equity
      m_lblBalance.Create(m_chart_id, m_name+"_bal", m_subwin, 20, yPos+25, width/2-10, yPos+45);
      m_lblBalance.Text("Balance: $0.00");
      m_lblBalance.FontSize(10);
      m_lblBalance.Color(CLR_TEXT_PRIMARY);
      Add(m_lblBalance);
      
      m_lblEquity.Create(m_chart_id, m_name+"_eq", m_subwin, width/2+10, yPos+25, width-20, yPos+45);
      m_lblEquity.Text("Equity: $0.00");
      m_lblEquity.FontSize(10);
      m_lblEquity.Color(CLR_TEXT_PRIMARY);
      Add(m_lblEquity);
      
      // Daily P&L
      m_lblProfitDaily.Create(m_chart_id, m_name+"_pnl_d", m_subwin, 20, yPos+50, width/2-10, yPos+70);
      m_lblProfitDaily.Text("Daily P&L: $0.00");
      m_lblProfitDaily.FontSize(9);
      m_lblProfitDaily.Color(CLR_TEXT_SECONDARY);
      Add(m_lblProfitDaily);
      
      // Floating P&L
      m_lblProfitFloat.Create(m_chart_id, m_name+"_pnl_f", m_subwin, width/2+10, yPos+50, width-20, yPos+70);
      m_lblProfitFloat.Text("Floating: $0.00");
      m_lblProfitFloat.FontSize(9);
      m_lblProfitFloat.Color(CLR_TEXT_SECONDARY);
      Add(m_lblProfitFloat);
      
      // Drawdown
      m_lblDrawdown.Create(m_chart_id, m_name+"_dd", m_subwin, 20, yPos+75, width-40, yPos+95);
      m_lblDrawdown.Text("Drawdown: 0.00%");
      m_lblDrawdown.FontSize(9);
      m_lblDrawdown.Color(CLR_WARNING);
      Add(m_lblDrawdown);
      
      yPos += sectionHeight + 10;
      
      // === MARKET SECTION ===
      CreatePanel(m_pnlMarket, "pnl_mkt", 10, yPos, width-20, sectionHeight, CLR_BG_SECONDARY);
      Add(m_pnlMarket);
      
      CreateSectionTitle("MARKET CONDITIONS", 15, yPos+5, width/2, yPos+20);
      
      m_lblSpread.Create(m_chart_id, m_name+"_spr", m_subwin, 20, yPos+25, width/2-10, yPos+45);
      m_lblSpread.Text("Spread: 0.0 pts");
      m_lblSpread.FontSize(10);
      m_lblSpread.Color(CLR_TEXT_PRIMARY);
      Add(m_lblSpread);
      
      m_lblATR.Create(m_chart_id, m_name+"_atr", m_subwin, width/2+10, yPos+25, width-20, yPos+45);
      m_lblATR.Text("ATR: 0.0 pts");
      m_lblATR.FontSize(10);
      m_lblATR.Color(CLR_TEXT_PRIMARY);
      Add(m_lblATR);
      
      m_lblGate.Create(m_chart_id, m_name+"_gate", m_subwin, 20, yPos+50, width/2-10, yPos+70);
      m_lblGate.Text("Gate: CLOSED");
      m_lblGate.FontSize(10);
      m_lblGate.Color(CLR_DANGER);
      Add(m_lblGate);
      
      m_lblPositions.Create(m_chart_id, m_name+"_pos", m_subwin, width/2+10, yPos+50, width-20, yPos+70);
      m_lblPositions.Text("Open: 0");
      m_lblPositions.FontSize(10);
      m_lblPositions.Color(CLR_INFO);
      Add(m_lblPositions);
      
      yPos += sectionHeight + 10;
      
      // === SIGNAL SECTION ===
      CreatePanel(m_pnlSignal, "pnl_sig", 10, yPos, width-20, sectionHeight, CLR_BG_SECONDARY);
      Add(m_pnlSignal);
      
      CreateSectionTitle("SIGNAL STATUS", 15, yPos+5, width/2, yPos+20);
      
      m_lblPattern.Create(m_chart_id, m_name+"_pat", m_subwin, 20, yPos+25, width-40, yPos+50);
      m_lblPattern.Text("Pattern: WAITING");
      m_lblPattern.FontSize(11);
      m_lblPattern.FontFlags(FONT_BOLD);
      m_lblPattern.Color(CLR_TEXT_PRIMARY);
      Add(m_lblPattern);
      
      m_lblDirection.Create(m_chart_id, m_name+"_dir", m_subwin, 20, yPos+55, width/2-10, yPos+75);
      m_lblDirection.Text("Direction: NEUTRAL");
      m_lblDirection.FontSize(10);
      m_lblDirection.Color(CLR_TEXT_SECONDARY);
      Add(m_lblDirection);
      
      m_lblNews.Create(m_chart_id, m_name+"_news", m_subwin, width/2+10, yPos+55, width-20, yPos+75);
      m_lblNews.Text("News: CLEAR");
      m_lblNews.FontSize(10);
      m_lblNews.Color(CLR_SUCCESS);
      Add(m_lblNews);
      
      yPos += sectionHeight + 10;
      
      // === STATS SECTION ===
      CreatePanel(m_pnlStats, "pnl_stats", 10, yPos, width-20, sectionHeight, CLR_BG_SECONDARY);
      Add(m_pnlStats);
      
      CreateSectionTitle("PERFORMANCE", 15, yPos+5, width/2, yPos+20);
      
      m_lblWinRate.Create(m_chart_id, m_name+"_wr", m_subwin, 20, yPos+25, width/2-10, yPos+45);
      m_lblWinRate.Text("Win Rate: 0%");
      m_lblWinRate.FontSize(10);
      m_lblWinRate.Color(CLR_ACCENT);
      Add(m_lblWinRate);
      
      m_lblTotalTrades.Create(m_chart_id, m_name+"_trd", m_subwin, width/2+10, yPos+25, width-20, yPos+45);
      m_lblTotalTrades.Text("Trades: 0");
      m_lblTotalTrades.FontSize(10);
      m_lblTotalTrades.Color(CLR_TEXT_PRIMARY);
      Add(m_lblTotalTrades);
      
      m_lblNetProfit.Create(m_chart_id, m_name"_net", m_subwin, 20, yPos+50, width-40, yPos+70);
      m_lblNetProfit.Text("Net Profit: $0.00");
      m_lblNetProfit.FontSize(10);
      m_lblNetProfit.Color(CLR_TEXT_PRIMARY);
      Add(m_lblNetProfit);
      
      yPos += sectionHeight + 10;
      
      // === CONTROLS SECTION ===
      CreatePanel(m_pnlControls, "pnl_ctrl", 10, yPos, width-20, 70, CLR_BG_ACCENT);
      Add(m_pnlControls);
      
      // Pause Button
      m_btnPause.Create(m_chart_id, m_name+"_pause", m_subwin, 15, yPos+10, (width/3)-5, yPos+35);
      m_btnPause.Text("⏸ PAUSE");
      m_btnPause.ColorBackground(CLR_WARNING);
      m_btnPause.Color(clrBlack);
      m_btnPause.FontFlags(FONT_BOLD);
      Add(m_btnPause);
      
      // Close All Button
      m_btnCloseAll.Create(m_chart_id, m_name+"_close", m_subwin, (width/3)+5, yPos+10, (2*width/3)-5, yPos+35);
      m_btnCloseAll.Text("✕ CLOSE ALL");
      m_btnCloseAll.ColorBackground(CLR_INFO);
      m_btnCloseAll.Color(clrWhite);
      m_btnCloseAll.FontFlags(FONT_BOLD);
      Add(m_btnCloseAll);
      
      // Emergency Stop Button
      m_btnEmergency.Create(m_chart_id, m_name+"_emerg", m_subwin, (2*width/3)+5, yPos+10, width-15, yPos+35);
      m_btnEmergency.Text("⚠ EMERGENCY");
      m_btnEmergency.ColorBackground(CLR_DANGER);
      m_btnEmergency.Color(clrWhite);
      m_btnEmergency.FontFlags(FONT_BOLD);
      Add(m_btnEmergency);
      
      return true;
   }
   
   // Helper function to create rounded panel
   void CreatePanel(CRectLabel &panel, string name, int x1, int y1, int x2, int y2, color bg)
   {
      panel.Create(m_chart_id, m_name+"_"+name, m_subwin, x1, y1, x2, y2);
      panel.ColorBackground(bg);
      panel.BorderType(BORDER_FLAT);
      panel.BorderColor(CLR_BG_ACCENT);
      panel.Corner(0); // Rounded corners
   }
   
   // Helper function to create section title
   void CreateSectionTitle(string text, int x1, int y1, int x2, int y2)
   {
      CLabel *lbl = new CLabel();
      if (CheckPointer(lbl) != POINTER_INVALID)
      {
         lbl.Create(m_chart_id, m_name+"_sec_"+text, m_subwin, x1, y1, x2, y2);
         lbl.Text(text);
         lbl.FontSize(9);
         lbl.FontFlags(FONT_BOLD);
         lbl.Color(CLR_TEXT_SECONDARY);
         lbl.Align(ALIGN_CENTER);
         Add(*lbl);
      }
   }

   virtual bool OnEvent(const int id, const long &lparam, const double &dparam, const string &sparam) override
   {
      // Handle button clicks
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
      
      // Handle custom events
      if (id >= CHARTEVENT_CUSTOM)
      {
         if (id == DASHBOARD_REFRESH)
         {
            UpdateUI();
            return true;
         }
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
      m_lblStatus.Text("● System Active");
      
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
      if (dd > CFG.MaxDailyLossPct * 0.8)
         m_lblDrawdown.Color(CLR_DANGER);
      else if (dd > CFG.MaxDailyLossPct * 0.5)
         m_lblDrawdown.Color(CLR_WARNING);
      else
         m_lblDrawdown.Color(CLR_TEXT_SECONDARY);
      
      // === UPDATE MARKET SECTION ===
      m_lblSpread.Text(StringFormat("Spread: %.1f pts", cache.spread));
      m_lblATR.Text(StringFormat("ATR: %.1f pts", cache.atrPoints));
      
      // Gate status
      string gateStr = cache.gateOpen ? "OPEN ✓" : "CLOSED ✗";
      m_lblGate.Text(StringFormat("Gate: %s", gateStr));
      m_lblGate.Color(cache.gateOpen ? CLR_SUCCESS : CLR_DANGER);
      
      // Open positions count
      m_lblPositions.Text(StringFormat("Open Positions: %d", cache.openPositions));
      
      // === UPDATE SIGNAL SECTION ===
      string pattern = (cache.lastPattern != "" && cache.lastPattern != "NONE") ? cache.lastPattern : "WAITING FOR SIGNAL";
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
      if (CFG.UseNews)
      {
         long secondsToNews = (long)cache.nextNews - (long)TimeGMT();
         if (secondsToNews > 0 && secondsToNews < 3600)
         {
            m_lblNews.Text(StringFormat("News: IN %d MIN ⚠", (int)(secondsToNews / 60)));
            m_lblNews.Color(CLR_WARNING);
         }
         else if (secondsToNews <= 0 && secondsToNews > -1800)
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
      double winRate = 0;
      if (cache.perfStats.safeTotal > 0)
         winRate = (double)cache.perfStats.safeWins / cache.perfStats.safeTotal * 100.0;
      
      m_lblWinRate.Text(StringFormat("Win Rate: %.1f%%", winRate));
      m_lblWinRate.Color(winRate >= 50 ? CLR_SUCCESS : CLR_WARNING);
      
      m_lblTotalTrades.Text(StringFormat("Total Trades: %d", totalTrades));
      
      // Net profit calculation
      double netProfit = cache.perfStats.safeWins - (cache.perfStats.safeTotal - cache.perfStats.safeWins);
      m_lblNetProfit.Text(StringFormat("Net Profit: $%.2f", netProfit));
      m_lblNetProfit.Color(netProfit >= 0 ? CLR_SUCCESS : CLR_DANGER);
      
      // Force chart redraw for backtest visualization
      ChartRedraw(m_chart_id);
   }
   
   // Button click handlers
   void OnPauseClick()
   {
      GlobalVariableSet("PASR_PAUSE_" + (string)m_magic, 1);
      EventBus::Instance().Dispatch(new PauseToggleEvent(true, true));
      m_btnPause.Text("▶ RESUME");
      m_btnPause.ColorBackground(CLR_SUCCESS);
   }
   
   void OnCloseAllClick()
   {
      if (MessageBox("Close all open positions?", "Confirm", MB_YESNO | MB_ICONQUESTION) == IDYES)
      {
         EventChartCustom(m_chart_id, DASHBOARD_CLOSEALL, 0, 0, "");
         Print("[Dashboard] Close All Positions triggered");
      }
   }
   
   void OnEmergencyClick()
   {
      if (MessageBox("EMERGENCY STOP will close ALL positions and disable trading!", "WARNING", MB_YESNO | MB_ICONWARNING) == IDYES)
      {
         GlobalVariableSet("PASR_EMERGENCY_" + (string)m_magic, 1);
         EventBus::Instance().Dispatch(new EmergencyStopEvent("Manual Emergency Stop from Dashboard"));
         Print("[Dashboard] EMERGENCY STOP ACTIVATED");
      }
   }
};

#endif
