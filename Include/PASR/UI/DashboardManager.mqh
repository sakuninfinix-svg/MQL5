//+------------------------------------------------------------------+
//| UI/DashboardManager.mqh  — CANONICAL v2.12                       |
//| 1Hz render throttle: no string rebuild on every tick             |
//+------------------------------------------------------------------+
#pragma once
#ifndef UI_DASHBOARD_MANAGER_MQH
#define UI_DASHBOARD_MANAGER_MQH

#include "../Core/IManager.mqh"

#define DASHBOARD_REFRESH_US 1000000  // 1 second in microseconds
#define DASH_OBJ_PREFIX      "PASR_DASH_"

//+------------------------------------------------------------------+
//| CDashboardManager — throttled, account-namespaced chart objects  |
//+------------------------------------------------------------------+
class CDashboardManager : public IManager
  {
private:
   ulong             m_lastRenderUs;    // GetMicrosecondCount() at last render
   string            m_objPrefix;       // account+magic namespaced
   bool              m_visible;

   //--- namespaced object names prevent collision across EA instances
   string            ObjName(string tag)
     {
      return m_objPrefix + tag;
     }

   void              DeleteAllObjects()
     {
      ObjectsDeleteAll(0, m_objPrefix);
     }

   void              DrawLabel(string tag, string text,
                               int x, int y,
                               color clr = clrWhite,
                               int  fontSize = 9)
     {
      string name = ObjName(tag);
      if(ObjectFind(0, name) < 0)
        {
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
         ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  fontSize);
         ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
        }
      ObjectSetString(0, name, OBJPROP_TEXT, text);
     }

   //--- full render — only called when throttle allows
   void              Render()
     {
      if(!m_visible) return;

      // Row 0: EA name + version
      DrawLabel("title", "PASR EA v2.12", 10, 20, clrDodgerBlue, 10);

      // Row 1: account info
      DrawLabel("acct",
                "Acct: " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) +
                "  Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2),
                10, 36, clrSilver);

      // Row 2: symbol + spread
      double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      DrawLabel("sym",
                _Symbol + "  Spread: " + DoubleToString(spread, _Digits),
                10, 52, clrSilver);

      // Row 3: open positions
      int posCount = PositionsTotal();
      DrawLabel("pos",
                "Open positions: " + IntegerToString(posCount),
                10, 68, posCount > 0 ? clrLimeGreen : clrGray);

      ChartRedraw(0);
     }

public:
   CDashboardManager() : m_lastRenderUs(0), m_visible(true) {}

   bool              Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      // namespace objects per account + magic to avoid cross-instance pollution
      m_objPrefix = DASH_OBJ_PREFIX +
                    IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_" +
                    IntegerToString(m_cfg.MagicNumber) + "_";
      DeleteAllObjects();
      Render();
      return true;
     }

   void              OnNewBar()      override { Render(); }

   //--- Throttle: render at most once per second regardless of tick rate
   void              OnPriceUpdate() override
     {
      ulong now = GetMicrosecondCount();
      if(now - m_lastRenderUs < DASHBOARD_REFRESH_US) return;
      m_lastRenderUs = now;
      Render();
     }

   void              SetVisible(bool v)
     {
      m_visible = v;
      if(!v) DeleteAllObjects();
      else   Render();
     }

   void              Deinit()
     {
      DeleteAllObjects();
     }

   bool              IsHealthy() const override { return true; }
  };

#endif // UI_DASHBOARD_MANAGER_MQH
