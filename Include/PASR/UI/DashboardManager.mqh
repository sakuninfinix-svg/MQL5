//+------------------------------------------------------------------+
//|                              UI/DashboardManager.mqh             |
//|                         Copyright 2026, Agsicentre              |
//|                                                                  |
//|  PURPOSE: On-chart information panel for PASR EA.               |
//|    - 8 sections: Header, Account, Market, Signal, AI, Trade,    |
//|      Recovery, Footer                                            |
//|    - 1 Hz render throttle (unchanged from v2.12)                |
//|    - Color-coded status rows                                     |
//|    - All chart objects namespaced per account + magic            |
//|                                                                  |
//|  CHANGE LOG:                                                     |
//|  v3.00 (2026-05-21) Phase 9:                                     |
//|    + Full 8-section panel (was 4 plain labels)                   |
//|    + AI score bar, signal arrow, recovery state, P&L row        |
//|    + Background rect, Destroy(), OnConfigReload() override      |
//|    + Public setters: SetSignal / SetAIScore / SetRecoveryState   |
//|  v2.12 (prior): basic 4-label panel, 1Hz throttle               |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property strict

#ifndef __UI_DASHBOARD_MANAGER_MQH__
#define __UI_DASHBOARD_MANAGER_MQH__

#include "../Core/IManager.mqh"

//--- Render throttle: 1 second (unchanged from v2.12)
#define DASHBOARD_REFRESH_US 1000000
//--- Object name prefix (account+magic-namespaced at Init time)
#define DASH_OBJ_PREFIX      "PASR_D_"

//--- Panel layout constants (pixels, CORNER_LEFT_UPPER)
#define DASH_X          10    // panel left edge
#define DASH_Y          18    // panel top edge
#define DASH_W          260   // panel width
#define DASH_ROW        16    // row height
#define DASH_FONT_SZ    9     // default font size
#define DASH_FONT       "Courier New"

//--- Section row offsets from DASH_Y (0-indexed)
// Row  0: Header title
// Row  1: separator
// Row  2: Account balance
// Row  3: Account equity + margin
// Row  4: separator
// Row  5: Market spread + ATR
// Row  6: Market regime
// Row  7: separator
// Row  8: Signal direction + score
// Row  9: separator
// Row 10: AI enabled + confidence
// Row 11: AI loss + epochs
// Row 12: separator
// Row 13: Open positions + daily P&L
// Row 14: Drawdown %
// Row 15: separator
// Row 16: Recovery state
// Row 17: Recovery attempts
// Row 18: separator
// Row 19: Footer (last update)
// Total height = 20 * DASH_ROW + 8 (padding)
#define DASH_ROWS_TOTAL  20

//+------------------------------------------------------------------+
//| CDashboardManager — full 8-section on-chart panel               |
//+------------------------------------------------------------------+
class CDashboardManager : public IManager
  {
private:
   //--- Render throttle
   ulong  m_lastRenderUs;

   //--- Object namespace
   string m_objPrefix;
   bool   m_visible;

   //--- External data fed by Orchestrator via public setters
   int    m_signalDir;        // +1 BUY, -1 SELL, 0 NONE
   double m_signalScore;      // [0, 100]
   double m_aiScore;          // [0.0, 1.0]
   bool   m_aiEnabled;
   double m_aiLastLoss;
   int    m_aiEpochs;
   int    m_recoveryState;    // 0=NORMAL, 1=RECOVERY, 2=DONE
   int    m_recoveryAttempts;
   int    m_recoveryMaxAttempts;
   double m_dailyPnL;
   double m_drawdownPct;

   // ── Object helpers ──────────────────────────────────────────────

   string ObjName(const string tag) const
     { return m_objPrefix + tag; }

   void DeleteAllObjects()
     { ObjectsDeleteAll(0, m_objPrefix); }

   //--- Create or update a text label
   void Label(const string tag, const string text,
              int row, color clr = clrSilver, int sz = DASH_FONT_SZ)
     {
      string name = ObjName(tag);
      int y = DASH_Y + row * DASH_ROW;
      if(ObjectFind(0, name) < 0)
        {
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  DASH_X + 6);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
         ObjectSetString(0,  name, OBJPROP_FONT,       DASH_FONT);
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   sz);
        }
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
      ObjectSetString(0,  name, OBJPROP_TEXT,      text);
     }

   //--- Background panel rectangle
   void DrawBackground()
     {
      string name = ObjName("bg");
      int panelH   = DASH_ROWS_TOTAL * DASH_ROW + 8;
      if(ObjectFind(0, name) < 0)
        {
         ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  DASH_X);
         ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  DASH_Y - 4);
         ObjectSetInteger(0, name, OBJPROP_XSIZE,      DASH_W);
         ObjectSetInteger(0, name, OBJPROP_YSIZE,      panelH);
         ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    C'20,20,28');
         ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
         ObjectSetInteger(0, name, OBJPROP_COLOR,      C'50,60,80');
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
         ObjectSetInteger(0, name, OBJPROP_BACK,       true);
        }
     }

   //--- Separator line (drawn as dashes in text)
   void Sep(const string tag, int row)
     { Label(tag, StringFormat("%.*s", 38, "----------------------------------------"), row, C'50,60,80', 8); }

   //--- AI score bar: filled blocks proportional to score [0,1]
   string ScoreBar(double score, int width = 12)
     {
      int filled = (int)MathRound(score * width);
      filled = MathMax(0, MathMin(width, filled));
      string bar = "[";
      for(int i = 0; i < width; i++)
         bar += (i < filled) ? "█" : "·";
      bar += "]";
      return bar;
     }

   // ── Full render ────────────────────────────────────────────────

   void Render()
     {
      if(!m_visible) return;
      DrawBackground();

      //--- Row 0: Header
      string tfStr = EnumToString(_Period);
      Label("hdr", "PASR EA v3.00  " + _Symbol + "  " + tfStr,
            0, clrDodgerBlue, 10);

      //--- Row 1: sep
      Sep("s1", 1);

      //--- Row 2: Balance
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
      Label("bal",
            StringFormat("Bal: %s  Eq: %s",
                         DoubleToString(balance, 2),
                         DoubleToString(equity, 2)),
            2, clrSilver);

      //--- Row 3: Margin level
      double marginLvl = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
      color  marginClr = (marginLvl < 150.0 && marginLvl > 0) ? clrOrangeRed : clrSilver;
      Label("margin",
            StringFormat("Margin Lvl: %.1f%%  Acct: %I64d",
                         marginLvl,
                         AccountInfoInteger(ACCOUNT_LOGIN)),
            3, marginClr);

      //--- Row 4: sep
      Sep("s2", 4);

      //--- Row 5: Spread + ATR
      double spreadPts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
      double spreadPips = spreadPts / (10 * _Point);
      double atr = (m_data != NULL) ? m_data.GetATRPoints() : 0.0;
      Label("mkt",
            StringFormat("Spread: %.1f pip  ATR: %s pts",
                         spreadPips,
                         DoubleToString(atr, 1)),
            5, clrSilver);

      //--- Row 6: Market regime
      string regimeStr = "--";
      if(m_data != NULL)
        {
         int regime = m_data.GetMarketRegime();
         if(regime == 1)       regimeStr = "TREND  UP";
         else if(regime == -1) regimeStr = "TREND  DOWN";
         else if(regime == 2)  regimeStr = "RANGING";
         else                  regimeStr = "UNKNOWN";
        }
      Label("regime", "Regime: " + regimeStr, 6, clrLightBlue);

      //--- Row 7: sep
      Sep("s3", 7);

      //--- Row 8: Signal
      string sigArrow = (m_signalDir > 0) ? "▲ BUY" :
                        (m_signalDir < 0) ? "▼ SELL" : "— NONE";
      color  sigClr   = (m_signalDir > 0) ? clrLimeGreen :
                        (m_signalDir < 0) ? clrTomato : clrGray;
      Label("sig",
            StringFormat("Signal: %-8s  Score: %.1f",
                         sigArrow, m_signalScore),
            8, sigClr);

      //--- Row 9: sep
      Sep("s4", 9);

      //--- Row 10: AI status
      string aiState = m_aiEnabled ? "ON " : "OFF";
      color  aiClr   = m_aiEnabled ? clrAqua : clrGray;
      Label("ai0",
            StringFormat("AI: %s  Conf: %.2f  %s",
                         aiState,
                         m_aiScore,
                         ScoreBar(m_aiScore)),
            10, aiClr);

      //--- Row 11: AI loss + epochs
      Label("ai1",
            StringFormat("Loss: %.6f  Epochs: %d",
                         m_aiLastLoss, m_aiEpochs),
            11, clrDarkGray);

      //--- Row 12: sep
      Sep("s5", 12);

      //--- Row 13: Positions + daily P&L
      int   posCount = PositionsTotal();
      color pnlClr   = (m_dailyPnL >= 0) ? clrLimeGreen : clrTomato;
      Label("trade0",
            StringFormat("Pos: %d  Daily P&L: %+.2f",
                         posCount, m_dailyPnL),
            13, pnlClr);

      //--- Row 14: Drawdown
      color ddClr = (m_drawdownPct > 5.0) ? clrOrangeRed :
                    (m_drawdownPct > 2.0) ? clrOrange : clrGray;
      Label("trade1",
            StringFormat("Drawdown: %.2f%%", m_drawdownPct),
            14, ddClr);

      //--- Row 15: sep
      Sep("s6", 15);

      //--- Row 16: Recovery state
      string recState = (m_recoveryState == 0) ? "NORMAL" :
                        (m_recoveryState == 1) ? "RECOVERY" : "DONE";
      color  recClr   = (m_recoveryState == 1) ? clrOrange :
                        (m_recoveryState == 2) ? clrLimeGreen : clrGray;
      Label("rec0", "Recovery: " + recState, 16, recClr);

      //--- Row 17: Attempts
      Label("rec1",
            StringFormat("Attempts: %d / %d",
                         m_recoveryAttempts, m_recoveryMaxAttempts),
            17, clrDarkGray);

      //--- Row 18: sep
      Sep("s7", 18);

      //--- Row 19: Footer
      Label("foot",
            "Updated: " + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
            19, C'70,80,100', 8);

      ChartRedraw(0);
     }

public:
   CDashboardManager()
      : m_lastRenderUs(0), m_visible(true),
        m_signalDir(0), m_signalScore(0.0),
        m_aiScore(0.0), m_aiEnabled(false),
        m_aiLastLoss(0.0), m_aiEpochs(0),
        m_recoveryState(0), m_recoveryAttempts(0), m_recoveryMaxAttempts(3),
        m_dailyPnL(0.0), m_drawdownPct(0.0)
     {}

   bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      m_objPrefix = DASH_OBJ_PREFIX +
                    IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_" +
                    IntegerToString(m_cfg.MagicNumber) + "_";
      m_aiEnabled         = m_cfg.AI.EnableAI;
      m_recoveryMaxAttempts = m_cfg.Risk.MaxRecoveryAttempts;
      DeleteAllObjects();
      Render();
      return true;
     }

   void OnNewBar()      override { Render(); }

   //--- Throttle: render at most once per second
   void OnPriceUpdate() override
     {
      ulong now = GetMicrosecondCount();
      if(now - m_lastRenderUs < DASHBOARD_REFRESH_US) return;
      m_lastRenderUs = now;
      Render();
     }

   void OnConfigReload() override
     {
      IManager::OnConfigReload();
      m_aiEnabled           = m_cfg.AI.EnableAI;
      m_recoveryMaxAttempts = m_cfg.Risk.MaxRecoveryAttempts;
      // Re-namespace in case magic number changed
      m_objPrefix = DASH_OBJ_PREFIX +
                    IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_" +
                    IntegerToString(m_cfg.MagicNumber) + "_";
     }

   void Destroy()
     {
      DeleteAllObjects();
      ChartRedraw(0);
     }

   void SetVisible(bool v)
     {
      m_visible = v;
      if(!v) DeleteAllObjects();
      else   Render();
     }

   bool IsHealthy() const override { return true; }
   ulong GetLastRenderUs() const   { return m_lastRenderUs; }

   // ── Public setters (called by Orchestrator each bar/tick) ─────────

   void SetSignal(int dir, double score)
     { m_signalDir = dir; m_signalScore = score; }

   void SetAIScore(double score, double lastLoss, int epochs)
     { m_aiScore = score; m_aiLastLoss = lastLoss; m_aiEpochs = epochs; }

   void SetRecoveryState(int state, int attempts)
     { m_recoveryState = state; m_recoveryAttempts = attempts; }

   void SetPnL(double dailyPnL, double drawdownPct)
     { m_dailyPnL = dailyPnL; m_drawdownPct = drawdownPct; }
  };

#endif // __UI_DASHBOARD_MANAGER_MQH__
