//+------------------------------------------------------------------+
//|                                          11.DashboardManager.mqh |
//|                                       Copyright 2026, Agsicentre |
//|            On-Chart Dashboard for PASR EA                       |
//+------------------------------------------------------------------+
//| VERSION 1.00                                                     |
//| - DB-OPT-1: Render throttled to 1 Hz via m_lastRenderUs guard.  |
//|   Eliminates constant string allocation on every tick.           |
//|   OnPriceUpdate() only sets dirty flag — zero string work.       |
//| - DB-OPT-2: No concatenation chains in render path.             |
//| - All chart objects use per-chart prefix to support multiple     |
//|   EA instances on the same terminal without OBJ name collision.  |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "1.00"
#property strict

#ifndef __DASHBOARD_MANAGER_MQH__
#define __DASHBOARD_MANAGER_MQH__

#include "../Core/IManager.mqh"

//+------------------------------------------------------------------+
//| DashboardManager                                                 |
//| Renders a lightweight on-chart status panel.                     |
//| DB-OPT-1: All rendering is throttled to MAX 1 render/second.     |
//+------------------------------------------------------------------+
class DashboardManager : public IManager
{
private:
   // DB-OPT-1: throttle guard — stores last render timestamp in microseconds
   ulong  m_lastRenderUs;
   ulong  m_renderIntervalUs;   // default 1 000 000 µs = 1 Hz

   // Panel layout
   string m_prefix;       // unique object prefix per chart
   int    m_x;
   int    m_y;
   color  m_bgColor;
   color  m_textColor;
   color  m_accentColor;
   int    m_fontSize;
   int    m_lineHeight;

   // Cached display values (updated on event, rendered on throttle tick)
   string m_cachedSymbol;
   string m_cachedTF;
   string m_cachedRegime;
   string m_cachedSignal;
   int    m_cachedPositions;
   double m_cachedEquity;
   double m_cachedBalance;
   bool   m_dirtyFlag;    // true when cache updated since last render

   //--- Label helpers ---------------------------------------------------
   void LabelCreate(const string name, int x, int y, const string text,
                    color clr, int size = 0)
   {
      if(size == 0) size = m_fontSize;
      string obj = m_prefix + name;
      if(ObjectFind(0, obj) < 0)
         ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, obj, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
      ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, obj, OBJPROP_COLOR,     clr);
      ObjectSetInteger(0, obj, OBJPROP_FONTSIZE,  size);
      ObjectSetString( 0, obj, OBJPROP_TEXT,      text);
      ObjectSetString( 0, obj, OBJPROP_FONT,      "Consolas");
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, obj, OBJPROP_HIDDEN,    true);
   }

   void LabelSet(const string name, const string text, color clr = clrNONE)
   {
      string obj = m_prefix + name;
      if(ObjectFind(0, obj) >= 0)
      {
         ObjectSetString(0, obj, OBJPROP_TEXT, text);
         if(clr != clrNONE)
            ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
      }
      else
         LabelCreate(name, m_x, m_y, text, (clr != clrNONE ? clr : m_textColor));
   }

   void LabelDeleteAll() { ObjectsDeleteAll(0, m_prefix); }

   //--- Internal render — only called when throttle allows + dirty flag set
   void DoRender()
   {
      int y = m_y;

      LabelCreate("header",  m_x, y, "─── PASR EA ───", m_accentColor, m_fontSize + 2);
      y += m_lineHeight + 4;

      LabelCreate("sym_tf",  m_x, y, m_cachedSymbol + "  " + m_cachedTF, m_textColor);
      y += m_lineHeight;

      LabelCreate("regime",  m_x, y, "Regime  : " + m_cachedRegime, m_textColor);
      y += m_lineHeight;

      LabelCreate("signal",  m_x, y, "Signal  : " + m_cachedSignal, m_textColor);
      y += m_lineHeight;

      LabelCreate("pos",     m_x, y, "Positions: "
                  + IntegerToString(m_cachedPositions), m_textColor);
      y += m_lineHeight;

      LabelCreate("equity",  m_x, y, "Equity  : "
                  + DoubleToString(m_cachedEquity,  2), m_textColor);
      y += m_lineHeight;

      LabelCreate("balance", m_x, y, "Balance : "
                  + DoubleToString(m_cachedBalance, 2), m_textColor);

      ChartRedraw(0);
      m_dirtyFlag = false;
   }

public:
   DashboardManager()
      : IManager("DashboardManager", 200),
        m_lastRenderUs(0),
        m_renderIntervalUs(1000000),   // 1 Hz default
        m_x(10), m_y(20),
        m_bgColor(clrDarkSlateGray),
        m_textColor(clrWhiteSmoke),
        m_accentColor(clrGold),
        m_fontSize(9),
        m_lineHeight(16),
        m_cachedPositions(0),
        m_cachedEquity(0.0),
        m_cachedBalance(0.0),
        m_dirtyFlag(false)
   {
      m_prefix       = "PASR_DB_" + IntegerToString(ChartID()) + "_";
      m_cachedSymbol = _Symbol;
      m_cachedTF     = EnumToString(_Period);
      m_cachedRegime = "—";
      m_cachedSignal = "—";
   }

   virtual ~DashboardManager() { LabelDeleteAll(); }

   //--- Configure render rate (default 1 Hz = 1 000 000 µs)
   void SetRenderInterval(ulong intervalUs) { m_renderIntervalUs = intervalUs; }

   virtual void DeclareEvents() override
   {
      AddEvent(EVENT_ID_PRICE_UPDATE);
      AddEvent(EVENT_ID_SIGNAL_GENERATED);
      AddEvent(EVENT_ID_POSITION_UPDATE);
      AddEvent(EVENT_ID_MARKET_GATE);
      AddEvent(EVENT_ID_HEARTBEAT);
   }

   //--- DB-OPT-1: OnPriceUpdate only updates cache + dirty flag.
   //    NO string building, NO ChartRedraw here.
   virtual void OnPriceUpdate(PriceUpdateEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      m_cachedEquity  = AccountInfoDouble(ACCOUNT_EQUITY);
      m_cachedBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      m_dirtyFlag     = true;
   }

   virtual void OnSignalGenerated(SignalGeneratedEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      m_cachedSignal = (e.direction == 1 ? "▲ BUY" : "▼ SELL");
      m_dirtyFlag    = true;
   }

   virtual void OnPositionUpdate(PositionUpdateEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      m_cachedPositions = (int)PositionsTotal();
      m_dirtyFlag       = true;
   }

   //--- Heartbeat drives the throttled render check
   virtual void OnHeartbeat(HeartbeatEvent *e) override { Tick(); }

   //--- Call this from EA OnTick() for smooth update timing
   //    DB-OPT-1: The 1 Hz guard lives here, not in OnPriceUpdate.
   void Tick()
   {
      if(!m_dirtyFlag) return;   // nothing changed — skip entirely

      ulong now = GetMicrosecondCount();
      if(now - m_lastRenderUs < m_renderIntervalUs) return;

      m_lastRenderUs = now;
      DoRender();
   }

   void SetRegimeText(const string regime)
   {
      m_cachedRegime = regime;
      m_dirtyFlag    = true;
   }

   void SetPosition(int x, int y) { m_x = x; m_y = y; }
};

#endif // __DASHBOARD_MANAGER_MQH__
