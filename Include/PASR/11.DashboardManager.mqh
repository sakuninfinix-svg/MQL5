//+------------------------------------------------------------------+
//|               Price Action & Support Ressistance V1              |
//|         Optimized by Agsicentre (agsicentre.wordpress.com)       |
//+------------------------------------------------------------------+

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
   }
};

class DashboardManagerFactory
{
public:
   static DashboardManager *Create(DashboardUI *ui, DataManager *dta)
   {
      DashboardManager *ctrl = new DashboardManager();
      if (CheckPointer(ctrl) != POINTER_INVALID)
      {
         ctrl.SetUI(ui);
         ctrl.SetDataManager(dta);
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
   CLabel m_lblState, m_lblPnL, m_lblStats;
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

      int x = 10, y = 10;
      m_lblState.Create(m_chart_id, m_name + "_st", m_subwin, x, y, x2 - 20, y + 15);
      m_lblState.Text("System Initializing...");
      Add(m_lblState);

      y += 25;
      m_lblPnL.Create(m_chart_id, m_name + "_pnl", m_subwin, x, y, x2 - 20, y + 15);
      Add(m_lblPnL);

      y += 50;
      m_btnStop.Create(m_chart_id, m_name + "_stop", m_subwin, x, y, x + 100, y + 25);
      m_btnStop.Text("EMERGENCY STOP");
      m_btnStop.ColorBackground(clrFireBrick);
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
      m_lblState.Text(StringFormat("STATE: ACTIVE | ATR: %.1f", cache.atrPoints));
      m_lblPnL.Text(StringFormat("Daily: %.2f | Floating: %.2f", cache.scanResult.dailyRealized, cache.scanResult.floatingPnL));
      ChartRedraw();
   }

   void OnStopClick()
   {
      GlobalVariableSet("PASR_EMERGENCY_" + (string)m_magic, 1);
      EventBus::Instance().Dispatch(new EmergencyStopEvent("Manual UI Trigger"));
   }
};

#endif
