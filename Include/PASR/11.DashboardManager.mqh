//+------------------------------------------------------------------+
//|                                          11.DashboardManager.mqh  |
//|                                       Copyright 2026, Agsicentre |
//|                    Dashboard / Chart Object UI - v2.11           |
//|                                                                   |
//| v2.11 FIXES:                                                      |
//| - [BUG-PERF-01] Throttle dashboard render to max 1 Hz            |
//|   BEFORE: full string rebuild + ObjectSet* on EVERY tick          |
//|   AFTER : skip render if < 1000ms since last render              |
//|   IMPACT: ~90% reduction in CPU on busy tick streams             |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "2.11"
#property strict

#ifndef __DASHBOARD_MANAGER_MQH__
#define __DASHBOARD_MANAGER_MQH__

#include "IManager.mqh"
#include "2.Config.Types.mqh"

// Render throttle: 1 render per DASHBOARD_MIN_INTERVAL_MS milliseconds
#define DASHBOARD_MIN_INTERVAL_MS 1000

class CDashboardManager : public IManager
{
private:
   bool   m_initialized;
   string m_prefix;       // unique object name prefix per EA instance

   // [v2.11] Throttle guard — track last successful render timestamp
   ulong  m_lastRenderMs; // GetTickCount64() at last render

   //--- Internal render helpers (only called when throttle allows)
   void   RenderStats(const PositionScanResult &scan);
   void   RenderRegime(const string regimeName);
   void   RenderSignal(const SignalDecision &sig);
   void   RenderConfig();
   void   CreateLabel(const string name, int x, int y, const string text, color clr);

public:
   CDashboardManager() : m_initialized(false), m_lastRenderMs(0)
   {
      m_prefix = "PASR_DB_" + IntegerToString(ChartID()) + "_";
   }

   ~CDashboardManager() { Deinit(); }

   bool Init(CDataManager *data) override
   {
      if(!IManager::Init(data)) return false;
      m_initialized = true;
      m_lastRenderMs = 0; // force first render immediately
      return true;
   }

   void Deinit() override
   {
      if(!m_initialized) return;
      // Remove all chart objects with our prefix
      int total = ObjectsTotal(0);
      for(int i = total - 1; i >= 0; i--)
      {
         string name = ObjectName(0, i);
         if(StringFind(name, m_prefix) == 0)
            ObjectDelete(0, name);
      }
      m_initialized = false;
   }

   //--- Main update entry point — call from OnTick / OnPriceUpdate
   //    [v2.11] Throttled: renders at most once per DASHBOARD_MIN_INTERVAL_MS
   void Update(const PositionScanResult &scan,
               const string            regimeName,
               const SignalDecision    &lastSig)
   {
      if(!m_initialized) return;

      // ── THROTTLE GUARD ─────────────────────────────────────────────
      // BEFORE (v2.10): no guard — full rebuild every tick
      // AFTER  (v2.11): bail out if last render was < 1 second ago
      ulong nowMs = GetTickCount64();
      if(nowMs - m_lastRenderMs < DASHBOARD_MIN_INTERVAL_MS) return;
      m_lastRenderMs = nowMs;
      // ───────────────────────────────────────────────────────────────

      RenderStats(scan);
      RenderRegime(regimeName);
      RenderSignal(lastSig);
      RenderConfig();
      ChartRedraw();
   }

   bool IsReady() const override { return m_initialized && IManager::IsReady(); }
};

//--- Implementation -------------------------------------------------------

void CDashboardManager::CreateLabel(const string name, int x, int y,
                                     const string text, color clr)
{
   string fullName = m_prefix + name;
   if(ObjectFind(0, fullName) < 0)
   {
      ObjectCreate(0, fullName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, fullName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   }
   ObjectSetInteger(0, fullName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, fullName, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, fullName, OBJPROP_TEXT, text);
   ObjectSetInteger(0, fullName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, fullName, OBJPROP_FONTSIZE, 9);
}

void CDashboardManager::RenderStats(const PositionScanResult &scan)
{
   CreateLabel("stats_pos",  10, 20,
               StringFormat("Positions: %d (B:%d S:%d)",
                            scan.normalCount, scan.buyCount, scan.sellCount),
               clrWhite);
   CreateLabel("stats_pnl",  10, 36,
               StringFormat("Float P/L: %.2f | Daily: %.2f",
                            scan.floatingPnL, scan.dailyRealized),
               scan.floatingPnL >= 0 ? clrLimeGreen : clrOrangeRed);
   CreateLabel("stats_dd",   10, 52,
               StringFormat("Daily DD:  %.2f%%", scan.dailyDrawdown),
               scan.dailyDrawdown > 2.0 ? clrOrangeRed : clrYellow);
}

void CDashboardManager::RenderRegime(const string regimeName)
{
   CreateLabel("regime", 10, 74,
               StringFormat("Regime: %s", regimeName),
               clrDodgerBlue);
}

void CDashboardManager::RenderSignal(const SignalDecision &sig)
{
   string sigText = sig.valid
      ? StringFormat("Signal: %s @ %.5f",
                     EnumToString(sig.patternType), sig.signalPrice)
      : "Signal: none";
   CreateLabel("signal", 10, 90, sigText,
               sig.valid ? clrLimeGreen : clrGray);
}

void CDashboardManager::RenderConfig()
{
   // Only show key config values — avoid rebuilding the entire struct string
   CreateLabel("cfg_magic", 10, 110,
               StringFormat("Magic: %I64u | %s",
                            m_cfg.risk.magic,
                            m_cfg.system.safe ? "[SAFE]" : "[LIVE]"),
               clrLightGray);
}

#endif // __DASHBOARD_MANAGER_MQH__
