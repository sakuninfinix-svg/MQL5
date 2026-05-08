//+------------------------------------------------------------------+
//|               Price Action & Support Ressistance V1              |
//|         Optimized by Agsicentre (agsicentre.wordpress.com)       |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "1.00"

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

// Custom Event IDs for UI synchronization
#define DASHBOARD_REFRESH (CHARTEVENT_CUSTOM + 100)
#define DASHBOARD_EMERGENCY (CHARTEVENT_CUSTOM + 101)
#define DASHBOARD_PAUSE (CHARTEVENT_CUSTOM + 102)
#define DASHBOARD_STATS (CHARTEVENT_CUSTOM + 103)

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
      m_cache.scanResult = m_data.GetScanResult();
      m_cache.perfStats = m_data.GetPerformanceStats();
      m_cache.lastUpdate = TimeCurrent();
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
   CLabel m_lblState, m_lblPnL, m_lblStats, m_lblAccount, m_lblMarket, m_lblSignal, m_lblNews, m_lblRiskBar;
   CButton m_btnBuy, m_btnSell, m_btnStop;
   ulong m_magic;

public:
   DashboardUI() : m_ctrl(NULL), m_magic(0) {}
   void SetController(DashboardManager *ctrl) { m_ctrl = ctrl; }

   virtual bool CreateDashboard(long chart, string name, int subwin, int x1, int y1, int x2, int y2)
   {
      m_magic = CFG.MagicNum;
      if (!CAppDialog::Create(chart, name, subwin, x1, y1, x2, y2))
         return false;

      int localWidth = x2 - x1; // Hitung lebar relatif dialog
      int x = 10, y = 10;

      // --- HEADER SECTION ---
      m_lblState.Create(m_chart_id, m_name + "_st", m_subwin, x, y, localWidth - 20, y + 20);
      m_lblState.Text("System: Initializing...");
      m_lblState.FontSize(10);
      m_lblState.Color(clrGold);
      Add(m_lblState);

      y += 30;
      // Market Info (ATR & Spread)
      m_lblMarket.Create(m_chart_id, m_name + "_mkt", m_subwin, x, y, localWidth - 20, y + 20);
      m_lblMarket.Text("Market: Fetching...");
      Add(m_lblMarket);

      y += 25;
      // News Info
      m_lblNews.Create(m_chart_id, m_name + "_news", m_subwin, x, y, localWidth - 20, y + 20);
      m_lblNews.Text("News: Monitoring...");
      Add(m_lblNews);

      y += 30;
      // Account Info (Balance & Equity)
      m_lblAccount.Create(m_chart_id, m_name + "_acc", m_subwin, x, y, localWidth - 20, y + 20);
      m_lblAccount.Text("EQUITY: Loading...");
      Add(m_lblAccount);

      y += 25;
      // PnL Info (Daily & Floating)
      m_lblPnL.Create(m_chart_id, m_name + "_pnl", m_subwin, x, y, localWidth - 20, y + 20);
      m_lblPnL.Text("PNL: Calculating...");
      Add(m_lblPnL);

      y += 25;
      // Risk Meter
      m_lblRiskBar.Create(m_chart_id, m_name + "_risk", m_subwin, x, y, localWidth - 20, y + 20);
      m_lblRiskBar.Text("RISK: [----------]");
      Add(m_lblRiskBar);

      y += 30;
      // Last Signal Section
      m_lblSignal.Create(m_chart_id, m_name + "_sig", m_subwin, x, y, localWidth - 20, y + 20);
      m_lblSignal.Text("Signal: Watching...");
      Add(m_lblSignal);

      y += 30;
      // Statistics (Win Rates)
      m_lblStats.Create(m_chart_id, m_name + "_stats", m_subwin, x, y, localWidth - 20, y + 20);
      m_lblStats.Text("Stats: No History");
      Add(m_lblStats);

      y += 45;
      m_btnStop.Create(m_chart_id, m_name + "_stop", m_subwin, x, y, x + 160, y + 25);
      m_btnStop.Text("EMERGENCY STOP");
      m_btnStop.ColorBackground(clrFireBrick);
      m_btnStop.Color(clrWhite);
      Add(m_btnStop);

      return true;
   }

   virtual bool OnEvent(const int id, const long &lparam, const double &dparam, const string &sparam) override
   {
      if (id == CHARTEVENT_OBJECT_CLICK && sparam == m_btnStop.Name())
      {
         OnStopClick();
         return true;
      }
      if (id >= CHARTEVENT_CUSTOM)
      {
         if (id == DASHBOARD_REFRESH)
            UpdateUI();
         return true;
      }
      return CAppDialog::OnEvent(id, lparam, dparam, sparam);
   }

   void UpdateUI()
   {
      if (CheckPointer(m_ctrl) == POINTER_INVALID)
         return;
      const DataCacheUI cache = m_ctrl.GetCache();

      // --- UPDATE HEADER & MARKET ---
      string mode = MQLInfoInteger(MQL_TESTER) ? "BACKTEST" : "LIVE";
      m_lblState.Text(StringFormat("PASR MODULAR [%s] | ID: %d", mode, (int)m_magic));

      string gateStr = cache.gateOpen ? "READY" : "WAIT";
      color gateClr = cache.gateOpen ? clrForestGreen : clrFireBrick;
      m_lblMarket.Text(StringFormat("MARKET: [%s] | Spr: %.1f | ATR: %.1f", gateStr, cache.spread, cache.atrPoints));
      m_lblMarket.Color(gateClr);

      // --- UPDATE NEWS COUNTDOWN ---
      if (CFG.UseNews)
      {
         long secondsToNews = (long)cache.nextNews - (long)TimeGMT();
         if (secondsToNews > 0 && secondsToNews < 3600) // Jika kurang dari 1 jam
            m_lblNews.Text(StringFormat("NEWS: IN %d MIN", secondsToNews / 60));
         else if (secondsToNews <= 0 && secondsToNews > -3600)
            m_lblNews.Text("NEWS: ACTIVE / RECENT");
         else
            m_lblNews.Text("NEWS: CLEAR");
      }
      else
      {
         m_lblNews.Text("NEWS: FILTER OFF");
      }

      // --- UPDATE ACCOUNT ---
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double dd = cache.scanResult.dailyDrawdown;
      m_lblAccount.Text(StringFormat("EQUITY: %.2f | DD: %.2f%%", equity, dd));

      // --- UPDATE RISK METER ---
      int barCount = (int)MathMin(10, MathMax(0, (dd / CFG.MaxDailyLossPct) * 10));
      string riskMeter = "[";
      for (int i = 0; i < 10; i++)
         riskMeter += (i < barCount) ? "|" : "-";
      riskMeter += "]";
      m_lblRiskBar.Text("RISK: " + riskMeter);
      m_lblRiskBar.Color(dd > CFG.MaxDailyLossPct * 0.7 ? clrOrangeRed : clrDarkSlateGray);

      double daily = cache.scanResult.dailyRealized;
      double floating = cache.scanResult.floatingPnL;
      m_lblPnL.Text(StringFormat("PNL: Daily %.2f | Float %.2f", daily, floating));
      m_lblPnL.Color((daily + floating >= 0) ? clrForestGreen : clrCrimson);

      // --- UPDATE SIGNAL ---
      string pat = (cache.lastPattern != "" && cache.lastPattern != "NONE") ? cache.lastPattern : "WAITING";
      color patClr = (cache.lastDir == 1) ? clrCornflowerBlue : (cache.lastDir == -1 ? clrLightCoral : clrGray);
      m_lblSignal.Text(StringFormat("SIGNAL: %s [%s]", pat, (cache.lastDir == 1 ? "BUY" : (cache.lastDir == -1 ? "SELL" : "IDLE"))));
      m_lblSignal.Color(patClr);

      // --- UPDATE STATS ---
      string safeRate = (cache.perfStats.safeTotal > 0) ? DoubleToString((double)cache.perfStats.safeWins / cache.perfStats.safeTotal * 100.0, 1) + "%" : "0%";
      m_lblStats.Text(StringFormat("PERFORMANCE: Safe WR %s | Trades: %d",
                                   safeRate, cache.perfStats.safeTotal + cache.perfStats.aggTotal));
      m_lblStats.Color(clrDarkSlateGray);

      // Crucial for Backtest visualization
      ChartRedraw(m_chart_id);
   }

   void OnStopClick()
   {
      GlobalVariableSet("PASR_EMERGENCY_" + (string)m_magic, 1);
      EventBus::Instance().Dispatch(new EmergencyStopEvent("Manual UI Trigger"));
   }
};

#endif
