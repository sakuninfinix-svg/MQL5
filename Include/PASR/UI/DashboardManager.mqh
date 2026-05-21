//+------------------------------------------------------------------+
//| UI/DashboardManager.mqh — v3.00                                  |
//| MT5 object-based dashboard: signal + risk + regime + circuit.    |
//|                                                                  |
//| CHANGE LOG:                                                      |
//| v3.00 (2026-05-21) —                                             |
//|   + SetRegimeFilter(): regime row (TRENDING/RANGING/VOLATILE)    |
//|   + Circuit breaker alert row (flashing RED when tripped)        |
//|   + Signal urgency tier color (HIGH=lime, MEDIUM=yellow)         |
//|   + Consecutive loss counter with escalating color               |
//|   + Daily loss % bar with color gradient                         |
//|   + Drawdown % ASCII progress bar                                |
//|   + Destroy() public method (called by Orchestrator.OnDeinit)   |
//|   + DrawRow*() private helpers (maintainable sections)           |
//| v2.00 (2026-05-20) — Initial object-label dashboard             |
//+------------------------------------------------------------------+
#property strict
#ifndef __UI_DASHBOARD_MANAGER_MQH__
#define __UI_DASHBOARD_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "../Trade/RiskManager.mqh"
#include "../Signal/SignalManager.mqh"
#include "../Signal/RegimeFilter.mqh"

//+------------------------------------------------------------------+
//| CDashboardManager — full-feature text-label dashboard            |
//+------------------------------------------------------------------+
class CDashboardManager : public IManager
  {
private:
   CRiskManager    *m_risk;
   CSignalManager  *m_signal;
   CRegimeFilter   *m_regime;

   ulong            m_lastRenderMs;
   int              m_throttleMs;
   int              m_corner;
   int              m_baseX, m_baseY;
   int              m_lineH;
   string           m_prefix;
   bool             m_destroyed;

   // ── Low-level label helper ────────────────────────────────────────
   void SetLabel(const string key, int row, const string text,
                 color clr=clrSilver, int fs=9)
     {
      string obj = m_prefix + key;
      if(ObjectFind(0, obj) < 0)
        {
         ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, obj, OBJPROP_CORNER,     m_corner);
         ObjectSetInteger(0, obj, OBJPROP_XDISTANCE,  m_baseX);
         ObjectSetInteger(0, obj, OBJPROP_BACK,       false);
         ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, obj, OBJPROP_FONTSIZE,   fs);
         ObjectSetString (0, obj, OBJPROP_FONT,       "Consolas");
        }
      ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, m_baseY + row * m_lineH);
      ObjectSetString (0, obj, OBJPROP_TEXT,      text);
      ObjectSetInteger(0, obj, OBJPROP_COLOR,     clr);
     }

   // ── ASCII progress bar helper (e.g. "[█████░░░░░] 52%") ────────────
   string ProgressBar(double pct, int width=10) const
     {
      pct = MathMax(0, MathMin(100, pct));
      int filled = (int)MathRound(pct / 100.0 * width);
      string bar = "[";
      for(int i=0; i<width; i++) bar += (i < filled) ? "█" : "░";
      bar += StringFormat("] %.1f%%", pct);
      return bar;
     }

   // ── Color ramp: 0-50%=silver, 50-70%=yellow, 70-85%=orange, 85%+=red
   color PctColor(double pct) const
     {
      if(pct >= 85.0) return clrRed;
      if(pct >= 70.0) return clrOrangeRed;
      if(pct >= 50.0) return clrGold;
      return clrSilver;
     }

   // ──────────── Row draw methods ──────────────────────────────────────────

   void DrawHeader(int &row)
     {
      SetLabel("hdr", row++,
               "╔══ PASR EA v3 ═════════════╗",
               clrGold, 9);
     }

   void DrawSymbolSpread(int &row)
     {
      double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      double atr    = (m_data != NULL) ? m_data.GetATRPoints() : 0;
      SetLabel("sym", row++,
               StringFormat("║ %-8s  Sprd:%.0f  ATR:%.0f", _Symbol, spread, atr),
               clrWhite, 9);
     }

   void DrawRegime(int &row)
     {
      if(m_regime == NULL) return;

      ENUM_MARKET_REGIME r = m_regime.GetRegime();
      string rName = RegimeName(r);
      color  rClr;
      string icon;
      switch(r)
        {
         case REGIME_TRENDING:  rClr=clrDeepSkyBlue; icon="▲"; break;
         case REGIME_RANGING:   rClr=clrSilver;      icon="◆"; break;
         case REGIME_VOLATILE:  rClr=clrRed;         icon="!"; break;
         case REGIME_SQUEEZE:   rClr=clrGold;        icon="■"; break;
         default:               rClr=clrDimGray;     icon="?"; break;
        }

      SetLabel("regime", row++,
               StringFormat("║ Regime: %s %s  ADX:%.1f",
                            icon, rName, m_regime.GetADX()),
               rClr, 9);
     }

   void DrawSignal(int &row)
     {
      if(m_signal == NULL) return;

      FinalSignal sig = m_signal.GetCurrent();
      string dirStr   = (sig.direction==SIGNAL_BUY)  ? "▲ BUY " :
                        (sig.direction==SIGNAL_SELL) ? "▼ SELL" : "■ ----";

      // Urgency-based color
      color sigClr = clrSilver;
      if(sig.direction != SIGNAL_NONE)
        {
         if(sig.urgency == SIGNAL_URGENCY_HIGH)
            sigClr = (sig.direction==SIGNAL_BUY) ? clrLime       : clrOrangeRed;
         else if(sig.urgency == SIGNAL_URGENCY_MEDIUM)
            sigClr = (sig.direction==SIGNAL_BUY) ? clrYellow     : clrOrange;
         else
            sigClr = clrSilver;
        }

      string urgStr = (sig.urgency==SIGNAL_URGENCY_HIGH)   ? "HIGH"   :
                      (sig.urgency==SIGNAL_URGENCY_MEDIUM) ? "MED"    : "";

      SetLabel("sig", row++,
               StringFormat("║ Sig: %s  %.2f %s [%d src]",
                            dirStr, sig.score, urgStr, sig.confluence),
               sigClr, 9);
     }

   void DrawRisk(int &row)
     {
      if(m_risk == NULL) return;

      // ── Circuit breaker row (flashes red)
      if(m_risk.IsCircuitBroken())
        {
         // Toggle color each render for flash effect
         bool flash = ((GetTickCount64() / 500) % 2 == 0);
         SetLabel("circuit", row++,
                  "║ ⚠ CIRCUIT BREAKER TRIPPED ⚠",
                  flash ? clrRed : clrOrangeRed, 10);
        }
      else
        {
         SetLabel("circuit", row++, "║ Circuit: OK", clrSilver, 9);
        }

      // ── Drawdown progress bar
      double dd    = m_risk.GetDrawdownPct();
      double ddMax = (m_cfg.Risk.MaxDrawdownPct > 0) ? m_cfg.Risk.MaxDrawdownPct : 10.0;
      double ddPct = (ddMax > 0) ? MathMin(100.0, dd / ddMax * 100.0) : 0;
      SetLabel("dd", row++,
               StringFormat("║ DD: %s", ProgressBar(ddPct, 8)),
               PctColor(ddPct), 9);

      // ── Daily loss progress bar
      double dloss    = m_risk.GetDailyLossPct();
      double dlossMax = (m_cfg.Risk.DailyLossPct > 0) ? m_cfg.Risk.DailyLossPct : 3.0;
      double dlossPct = (dlossMax > 0) ? MathMin(100.0, dloss / dlossMax * 100.0) : 0;
      SetLabel("daily", row++,
               StringFormat("║ DayLoss: %s", ProgressBar(dlossPct, 8)),
               PctColor(dlossPct), 9);

      // ── Consecutive loss + open trades
      int  consec = m_risk.GetConsecLoss();
      int  maxCL  = m_cfg.Risk.MaxConsecLoss;
      color clClr = (consec >= maxCL - 1) ? clrOrangeRed :
                    (consec >= maxCL / 2)  ? clrGold : clrSilver;
      SetLabel("consec", row++,
               StringFormat("║ ConsecLoss:%d/%d  Open:%d",
                            consec, maxCL, m_risk.GetOpenTrades()),
               clClr, 9);
     }

   void DrawPositions(int &row)
     {
      int    openCnt  = 0;
      double floatPnl = 0.0;
      for(int i=0; i<PositionsTotal(); i++)
         if(PositionGetSymbol(i)==_Symbol &&
            (int)PositionGetInteger(POSITION_MAGIC)==m_cfg.MagicNumber)
           { openCnt++; floatPnl += PositionGetDouble(POSITION_PROFIT); }

      color posClr = (floatPnl > 0) ? clrLime :
                     (floatPnl < 0) ? clrOrangeRed : clrSilver;
      SetLabel("pos", row++,
               StringFormat("║ Pos:%d  Float: %.2f", openCnt, floatPnl),
               posClr, 9);
     }

   void DrawFooter(int &row)
     {
      SetLabel("sep",  row++,
               "╚════════════════════════╗",
               clrDimGray, 8);
      SetLabel("time", row++,
               " " + TimeToString(TimeCurrent(), TIME_MINUTES),
               clrDimGray, 8);
     }

   // ── Full redraw ──────────────────────────────────────────────────
   void Redraw()
     {
      if(m_destroyed) return;
      int row = 0;
      DrawHeader(row);
      DrawSymbolSpread(row);
      DrawRegime(row);
      DrawSignal(row);
      DrawRisk(row);
      DrawPositions(row);
      DrawFooter(row);
      ChartRedraw(0);
     }

   void DeleteAllObjects()
     {
      for(int i = ObjectsTotal(0)-1; i >= 0; i--)
        {
         string name = ObjectName(0, i);
         if(StringFind(name, m_prefix) == 0)
            ObjectDelete(0, name);
        }
      ChartRedraw(0);
     }

public:
   CDashboardManager()
      : IManager(), m_risk(NULL), m_signal(NULL), m_regime(NULL),
        m_lastRenderMs(0), m_throttleMs(1000),
        m_corner(CORNER_RIGHT_UPPER), m_baseX(10), m_baseY(20),
        m_lineH(14), m_prefix("PASR_DB_"), m_destroyed(false)
     {}

   ~CDashboardManager() { Destroy(); }

   // ── Dependency injection
   void SetRiskManager  (CRiskManager   *r) { m_risk   = r; }
   void SetSignalManager(CSignalManager *s) { m_signal = s; }
   void SetRegimeFilter (CRegimeFilter  *rf){ m_regime = rf; }

   // ── Configuration
   void SetThrottleMs  (int ms)     { m_throttleMs = MathMax(100, ms); }
   void SetCorner      (int c)      { m_corner = c; }
   void SetPosition    (int x, int y){ m_baseX=x; m_baseY=y; }
   void SetPrefix      (string p)   { m_prefix = p; }
   void SetLineHeight  (int h)      { m_lineH = MathMax(10, h); }

   // ── Public destroy (called by Orchestrator.OnDeinit)
   void Destroy()
     {
      if(m_destroyed) return;
      m_destroyed = true;
      DeleteAllObjects();
     }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_PRICE_UPDATE);
      AddEvent(EVENT_ID_POSITION_UPDATE);
      AddEvent(EVENT_ID_SIGNAL_READY);
      AddEvent(EVENT_ID_NEW_BAR);
     }

   virtual void OnPriceUpdate() override
     {
      if(m_destroyed) return;
      ulong now = GetTickCount64();
      if(now - m_lastRenderMs < (ulong)m_throttleMs) return;
      m_lastRenderMs = now;
      Redraw();
     }

   virtual void OnNewBar() override
     {
      if(m_destroyed) return;
      Redraw();
     }

   virtual void OnEvent(const PASREvent &ev) override
     {
      if(m_destroyed) return;
      // Immediate redraw on signal ready or position update
      if(ev.id == EVENT_ID_SIGNAL_READY || ev.id == EVENT_ID_POSITION_UPDATE)
         Redraw();
     }
  };

typedef CDashboardManager DashboardManager;
#endif // __UI_DASHBOARD_MANAGER_MQH__
