//+------------------------------------------------------------------+
//| UI/DashboardManager.mqh — v2.00                                  |
//| MT5 canvas-less object-based dashboard with render throttle.     |
//| Replaces root ../11.DashboardManager.mqh stub.                   |
//+------------------------------------------------------------------+
#property strict
#ifndef __UI_DASHBOARD_MANAGER_MQH__
#define __UI_DASHBOARD_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "../Trade/RiskManager.mqh"
#include "../Signal/SignalManager.mqh"

//+------------------------------------------------------------------+
//| CDashboardManager — lightweight text-label dashboard             |
//+------------------------------------------------------------------+
class CDashboardManager : public IManager
  {
private:
   CRiskManager    *m_risk;
   CSignalManager  *m_signal;

   ulong            m_lastRenderMs;
   int              m_throttleMs;    // min ms between redraws
   int              m_corner;
   int              m_baseX, m_baseY;
   int              m_lineH;         // pixels between rows
   string           m_prefix;        // object name prefix

   // ── Object helpers ─────────────────────────────────────────────

   void SetLabel(const string name, int row, const string text,
                 color clr=clrSilver, int fontSize=9)
     {
      string obj = m_prefix + name;
      if(ObjectFind(0, obj) < 0)
        {
         ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, obj, OBJPROP_CORNER, m_corner);
         ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, m_baseX);
         ObjectSetInteger(0, obj, OBJPROP_BACK, false);
         ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, fontSize);
         ObjectSetString(0, obj, OBJPROP_FONT, "Consolas");
        }
      ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, m_baseY + row * m_lineH);
      ObjectSetString(0, obj, OBJPROP_TEXT, text);
      ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
     }

   void Redraw()
     {
      int row = 0;

      // ── Header ────────────────────────────────────────────────
      SetLabel("hdr", row++, "═══ PASR v2 ══════════════", clrGold, 9);

      // ── Symbol + Spread ───────────────────────────────────────
      double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      SetLabel("sym", row++,
               StringFormat("%-8s  Spread: %.0f", _Symbol, spread),
               clrWhite, 9);

      // ── ATR ───────────────────────────────────────────────────
      double atr = (m_data != NULL) ? m_data.GetATRPoints() : 0;
      SetLabel("atr", row++,
               StringFormat("ATR: %.1f pts", atr),
               clrSilver, 9);

      // ── Signal ────────────────────────────────────────────────
      if(m_signal != NULL)
        {
         FinalSignal sig = m_signal.GetCurrent();
         string dirStr   = (sig.direction==SIGNAL_BUY)  ? "BUY " :
                           (sig.direction==SIGNAL_SELL) ? "SELL" : "----";
         color sigClr    = (sig.direction==SIGNAL_BUY)  ? clrLime :
                           (sig.direction==SIGNAL_SELL) ? clrOrangeRed : clrSilver;
         SetLabel("sig", row++,
                  StringFormat("Signal: %s  Scr:%.2f Cnf:%d",
                               dirStr, sig.score, sig.confluence),
                  sigClr, 9);
        }

      // ── Risk ──────────────────────────────────────────────────
      if(m_risk != NULL)
        {
         double dd   = m_risk.GetDrawdownPct();
         double dpnl = m_risk.GetDailyPnLPct();
         color  ddClr = (dd > m_cfg.Risk.MaxDrawdownPct * 0.8) ? clrOrangeRed : clrSilver;
         SetLabel("dd", row++,
                  StringFormat("DD:%.1f%%  Daily PnL:%.1f%%", dd, dpnl),
                  ddClr, 9);
         SetLabel("trade", row++,
                  StringFormat("Trades today: %d", m_risk.GetTodayCount()),
                  clrSilver, 9);
        }

      // ── Open positions ────────────────────────────────────────
      int    openCnt = 0;
      double floatPnl = 0.0;
      for(int i=0; i<PositionsTotal(); i++)
         if(PositionGetSymbol(i)==_Symbol &&
            (int)PositionGetInteger(POSITION_MAGIC)==m_cfg.MagicNumber)
           { openCnt++; floatPnl += PositionGetDouble(POSITION_PROFIT); }

      color  posClr = (floatPnl >= 0) ? clrLime : clrOrangeRed;
      SetLabel("pos", row++,
               StringFormat("Pos: %d  Float: %.2f", openCnt, floatPnl),
               posClr, 9);

      // ── Separator ────────────────────────────────────────────
      SetLabel("sep", row++, "─────────────────────────", clrDimGray, 8);

      // ── Time ─────────────────────────────────────────────────
      SetLabel("time", row++,
               "Updated: " + TimeToString(TimeCurrent(), TIME_MINUTES),
               clrDimGray, 8);

      ChartRedraw(0);
     }

public:
   CDashboardManager()
      : IManager(), m_risk(NULL), m_signal(NULL),
        m_lastRenderMs(0), m_throttleMs(1000),
        m_corner(CORNER_RIGHT_UPPER), m_baseX(10), m_baseY(20),
        m_lineH(14), m_prefix("PASR_DB_") {}

   ~CDashboardManager()
     {
      // Remove all our objects on destruction
      for(int i=ObjectsTotal(0)-1; i>=0; i--)
        {
         string name = ObjectName(0, i);
         if(StringFind(name, m_prefix) == 0)
            ObjectDelete(0, name);
        }
     }

   void SetRiskManager(CRiskManager *r)   { m_risk   = r; }
   void SetSignalManager(CSignalManager *s) { m_signal = s; }
   void SetThrottleMs(int ms) { m_throttleMs = MathMax(100, ms); }
   void SetCorner(int c)      { m_corner = c; }
   void SetPosition(int x, int y) { m_baseX=x; m_baseY=y; }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_PRICE_UPDATE);
      AddEvent(EVENT_ID_POSITION_UPDATE);
      AddEvent(EVENT_ID_SIGNAL_READY);
      AddEvent(EVENT_ID_NEW_BAR);
     }

   virtual void OnPriceUpdate() override
     {
      ulong now = GetTickCount64();
      if(now - m_lastRenderMs < (ulong)m_throttleMs) return;
      m_lastRenderMs = now;
      Redraw();
     }

   virtual void OnNewBar() override { Redraw(); }
  };

typedef CDashboardManager DashboardManager;
#endif
