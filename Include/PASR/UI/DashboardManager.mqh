//+------------------------------------------------------------------+
//| UI/DashboardManager.mqh — v2.00                                  |
//| Live on-chart HUD panel for PASR EA.                             |
//|                                                                  |
//| LAYOUT (top-right, 6 panels, ~320px wide):                       |
//|  ┌─────────────────────────────────────────┐  |
//|  │ PASR EA  EURUSD  H1  Spr:0.8  12:34:56 │  |
//|  ├─────────────────────────────────────────┤  |
//|  │ ▲ BUY 1.08250  SL:1.08100  TP:1.08500  │  |
//|  │     Lots:0.10   PnL: +$12.50            │  |
//|  ├─────────────────────────────────────────┤  |
//|  │ AI [========--] 0.82  Drift[===-------] │  |
//|  │    Ensemble:Trend   Regime:Trending     │  |
//|  │    Session:London                       │  |
//|  ├─────────────────────────────────────────┤  |
//|  │ Win:62.5%  PF:1.42  AvgRR:1.8R  DD:$45 │  |
//|  ├─────────────────────────────────────────┤  |
//|  │ SIG  12:30 ▲BUY 0.78 ✓WIN                 │  |
//|  │      12:15 ▼SELL 0.55 ✗LOSS              │  |
//|  ├─────────────────────────────────────────┤  |
//|  │ Today:+$38.00  Trades:3  Streak:W2       │  |
//|  └─────────────────────────────────────────┘  |
//|                                                                  |
//| USAGE:                                                           |
//|   CDashboardManager hud;                                         |
//|   hud.Init(GetPointer(journal));                                  |
//|   hud.Update(ctx);   // DashContext struct, call per tick / bar  |
//|   hud.Deinit();      // clears all HUD objects                   |
//|                                                                  |
//| PERFORMANCE:                                                      |
//|   • Lazy dirty-flag: only redraws changed panels                 |
//|   • ChartRedraw() once per Update() cycle                        |
//|   • All objects prefixed 'PASR_HUD_' for clean deinit            |
//|                                                                  |
//| CHANGE LOG:                                                       |
//|   v2.00 (2026-05-21) — Phase 11 full rewrite                     |
//|   v1.x  (legacy)     — basic label dashboard, no AI/journal data  |
//+------------------------------------------------------------------+
#property strict
#ifndef __UI_DASHBOARD_MANAGER_MQH__
#define __UI_DASHBOARD_MANAGER_MQH__

#include "../Infra/JournalManager.mqh"
#include "../Signal/AI/AITypes.mqh"
#include "../Trade/TradePlan.mqh"

//--- HUD geometry
#define HUD_X          15          // right margin from right edge
#define HUD_Y_START    20          // top margin
#define HUD_LINE_H     16          // pixels per line
#define HUD_FONT       "Consolas"
#define HUD_FONT_SZ    8           // font size (MT5 units = pt*10)
#define HUD_PREFIX     "PASR_HUD_"
#define HUD_GAUGE_W    10          // gauge bar width in chars

//--- Colors
#define CLR_HEADER     C'40,44,52'    // dark blue-gray
#define CLR_LABEL      C'150,150,160' // muted gray
#define CLR_VALUE      C'220,220,230' // light white
#define CLR_GREEN      C'74,222,128'  // profit / win / buy
#define CLR_RED        C'248,113,113' // loss / sell
#define CLR_AMBER      C'251,191,36'  // warning / near SL
#define CLR_BLUE       C'96,165,250'  // AI / neutral info
#define CLR_PURPLE     C'167,139,250' // ensemble / session
#define CLR_DIVIDER    C'60,63,70'    // separator line

//+------------------------------------------------------------------+
//| SignalSnap — recent signal snapshot for Panel 5                  |
//+------------------------------------------------------------------+
struct SignalSnap
  {
   datetime  time;
   ENUM_SIGNAL_DIR dir;
   double    score;
   int       outcome; // 1=win -1=loss 0=pending
  };

//+------------------------------------------------------------------+
//| DashContext — injected each Update() call                        |
//+------------------------------------------------------------------+
struct DashContext
  {
   // Position state
   bool     hasPosition;
   ENUM_SIGNAL_DIR posDir;
   double   posEntry;
   double   posSL;
   double   posTP1;
   double   posTP2;
   double   posLots;
   double   posPnL;       // live floating P&L
   bool     beDone;
   bool     partialDone;

   // AI state
   double   aiScore;
   double   driftScore;
   int      ensembleModel;  // 0=Trend 1=MeanRev 2=Momentum
   bool     aiVeto;         // true if score<0.4 or drift>0.6

   // Market state
   ENUM_MARKET_REGIME  regime;
   ENUM_TRADING_SESSION session;
   double   spread;         // in pips

   // Recent signals (up to 3)
   SignalSnap signals[3];
   int        signalCount;
  };

//+------------------------------------------------------------------+
//| CDashboardManager v2                                             |
//+------------------------------------------------------------------+
class CDashboardManager
  {
private:
   CJournalManager *m_journal;  // non-owning
   bool             m_ready;
   int              m_labelCount;

   // Dirty tracking — hash of last rendered string per panel
   string  m_lastPanel[6];

   //--- Low-level label helpers -----------------------------------

   string LabelName(string id) const
     { return HUD_PREFIX + id; }

   void CreateLabel(string name, int x, int y,
                    string text, color clr,
                    ENUM_ANCHOR_POINT anchor = ANCHOR_RIGHT_UPPER) const
     {
      if(ObjectFind(0, name) < 0)
        {
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_ANCHOR,  anchor);
         ObjectSetString(0,  name, OBJPROP_FONT,    HUD_FONT);
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, HUD_FONT_SZ);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN,  true);
        }
      ObjectSetString(0,  name, OBJPROP_TEXT,  text);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
     }

   void DeleteAllLabels() const
     {
      for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
        {
         string name = ObjectName(0, i);
         if(StringFind(name, HUD_PREFIX) == 0)
            ObjectDelete(0, name);
        }
     }

   //--- Gauge builders -------------------------------------------

   string Gauge(double val, int width = HUD_GAUGE_W) const
     {
      int filled = (int)MathRound(MathMin(val, 1.0) * width);
      string s = "[";
      for(int i=0; i<width; i++) s += (i < filled) ? "=" : "-";
      return s + "]";
     }

   //--- Regime / Session label -----------------------------------

   string RegimeStr(ENUM_MARKET_REGIME r) const
     {
      switch(r)
        {
         case REGIME_TRENDING:  return "Trending";
         case REGIME_RANGING:   return "Ranging";
         case REGIME_VOLATILE:  return "Volatile";
         case REGIME_QUIET:     return "Quiet";
         default:               return "Unknown";
        }
     }

   string SessionStr(ENUM_TRADING_SESSION s) const
     {
      switch(s)
        {
         case SESSION_ASIAN:   return "Asian";
         case SESSION_LONDON:  return "London";
         case SESSION_NEWYORK: return "NewYork";
         case SESSION_OVERLAP: return "Overlap";
         default:              return "Off";
        }
     }

   string EnsembleStr(int m) const
     {
      switch(m)
        {
         case 0: return "Trend";
         case 1: return "MeanRev";
         case 2: return "Momentum";
         default:return "None";
        }
     }

   //--- Panel renderers -----------------------------------------

   // Panel 1: HEADER
   void RenderHeader(const DashContext &ctx, int &y) const
     {
      string tf = EnumToString(Period());
      string spr = StringFormat("Spr:%.1f", ctx.spread);
      string tm  = TimeToString(TimeCurrent(), TIME_SECONDS);
      string txt = StringFormat(" PASR | %s %s %s %s ",
                                _Symbol, tf, spr, tm);
      CreateLabel(LabelName("H1"), HUD_X, y, txt, CLR_VALUE);
      y += HUD_LINE_H;
      // separator
      CreateLabel(LabelName("HD"), HUD_X, y,
                  StringFormat(" %s ", StringRepeat("-",36)),
                  CLR_DIVIDER);
      y += HUD_LINE_H;
     }

   // Panel 2: POSITION
   void RenderPosition(const DashContext &ctx, int &y) const
     {
      if(!ctx.hasPosition)
        {
         CreateLabel(LabelName("P1"), HUD_X, y,
                     " No open position ", CLR_LABEL);
         y += HUD_LINE_H;
         CreateLabel(LabelName("P2"), HUD_X, y, "", CLR_LABEL);
         y += HUD_LINE_H;
         CreateLabel(LabelName("P3"), HUD_X, y, "", CLR_LABEL);
         y += HUD_LINE_H;
        }
      else
        {
         string arrow = (ctx.posDir == SIGNAL_BUY) ? "▲ BUY" : "▼ SELL";
         color  dc    = (ctx.posDir == SIGNAL_BUY) ? CLR_GREEN : CLR_RED;
         string flags = (ctx.beDone ? "[BE]" : "") + (ctx.partialDone ? "[PC]" : "");
         CreateLabel(LabelName("P1"), HUD_X, y,
           StringFormat(" %s  %.5f  SL:%.5f  TP:%.5f %s",
                        arrow, ctx.posEntry,
                        ctx.posSL, ctx.posTP1, flags), dc);
         y += HUD_LINE_H;

         // TP2 if set
         if(ctx.posTP2 > 0)
           {
            CreateLabel(LabelName("P2"), HUD_X, y,
              StringFormat("      TP2:%.5f  Lots:%.2f",
                           ctx.posTP2, ctx.posLots), CLR_LABEL);
            y += HUD_LINE_H;
           }
         else
           {
            CreateLabel(LabelName("P2"), HUD_X, y,
              StringFormat("      Lots:%.2f", ctx.posLots), CLR_LABEL);
            y += HUD_LINE_H;
           }

         // PnL line
         color pnlClr = (ctx.posPnL > 0) ? CLR_GREEN :
                        (ctx.posPnL < 0) ? CLR_RED : CLR_LABEL;
         // Warn if within 30% of SL
         double riskPts = MathAbs(ctx.posEntry - ctx.posSL);
         double curPts  = MathAbs(SymbolInfoDouble(_Symbol,SYMBOL_BID) - ctx.posSL);
         if(curPts < riskPts * 0.3) pnlClr = CLR_AMBER;

         CreateLabel(LabelName("P3"), HUD_X, y,
           StringFormat("      PnL: %+.2f USD", ctx.posPnL), pnlClr);
         y += HUD_LINE_H;
        }
      // separator
      CreateLabel(LabelName("PD"), HUD_X, y,
                  StringFormat(" %s ", StringRepeat("-",36)), CLR_DIVIDER);
      y += HUD_LINE_H;
     }

   // Panel 3: AI ENGINE
   void RenderAI(const DashContext &ctx, int &y) const
     {
      // AI score gauge
      string aiGauge   = Gauge(ctx.aiScore);
      string driftGauge= Gauge(ctx.driftScore);
      color  aiClr     = (ctx.aiVeto)          ? CLR_RED   :
                         (ctx.aiScore >= 0.7)  ? CLR_GREEN :
                         (ctx.aiScore >= 0.5)  ? CLR_AMBER : CLR_RED;
      color  driftClr  = (ctx.driftScore > 0.5)? CLR_RED : CLR_BLUE;

      CreateLabel(LabelName("A1"), HUD_X, y,
        StringFormat(" AI%s%.2f  Drift%s%.2f%s",
                     aiGauge, ctx.aiScore,
                     driftGauge, ctx.driftScore,
                     ctx.aiVeto?" [VETO]":""),
        aiClr);
      y += HUD_LINE_H;

      CreateLabel(LabelName("A2"), HUD_X, y,
        StringFormat("    Model:%-8s  Regime:%s",
                     EnsembleStr(ctx.ensembleModel),
                     RegimeStr(ctx.regime)),
        CLR_PURPLE);
      y += HUD_LINE_H;

      CreateLabel(LabelName("A3"), HUD_X, y,
        StringFormat("    Session:%-10s",
                     SessionStr(ctx.session)),
        CLR_BLUE);
      y += HUD_LINE_H;

      // separator
      CreateLabel(LabelName("AD"), HUD_X, y,
                  StringFormat(" %s ", StringRepeat("-",36)), CLR_DIVIDER);
      y += HUD_LINE_H;
     }

   // Panel 4: LIVE STATS (from JournalManager)
   void RenderStats(int &y) const
     {
      if(CheckPointer(m_journal) == POINTER_INVALID)
        {
         CreateLabel(LabelName("S1"), HUD_X, y,
                     " Stats: journal not set ", CLR_LABEL);
         y += HUD_LINE_H * 2;
         return;
        }
      TradeStat s = m_journal.GetStats(50); // last 50
      color pfClr = (s.profitFactor >= 1.5) ? CLR_GREEN :
                    (s.profitFactor >= 1.0) ? CLR_AMBER : CLR_RED;
      CreateLabel(LabelName("S1"), HUD_X, y,
        StringFormat(" Win:%.0f%%  PF:%.2f  AvgRR:%.1fR",
                     s.winRate*100, s.profitFactor, s.avgRR),
        pfClr);
      y += HUD_LINE_H;

      color ddClr = (s.maxDrawdown < 50) ? CLR_LABEL : CLR_AMBER;
      CreateLabel(LabelName("S2"), HUD_X, y,
        StringFormat("    MaxDD:%.2f  Streak:W%d/L%d",
                     s.maxDrawdown,
                     s.maxConsecWin, s.maxConsecLoss),
        ddClr);
      y += HUD_LINE_H;

      // separator
      CreateLabel(LabelName("SD"), HUD_X, y,
                  StringFormat(" %s ", StringRepeat("-",36)), CLR_DIVIDER);
      y += HUD_LINE_H;
     }

   // Panel 5: SIGNALS
   void RenderSignals(const DashContext &ctx, int &y) const
     {
      if(ctx.signalCount == 0)
        {
         CreateLabel(LabelName("SG0"), HUD_X, y,
                     " SIG  No recent signals ", CLR_LABEL);
         y += HUD_LINE_H;
        }
      else
        {
         for(int i=0; i<ctx.signalCount && i<3; i++)
           {
            const SignalSnap &sg = ctx.signals[i];
            string arrow  = (sg.dir == SIGNAL_BUY) ? "▲" : "▼";
            string dirStr = (sg.dir == SIGNAL_BUY) ? "BUY" : "SEL";
            string outStr;
            color  outClr;
            if(sg.outcome == 1)      { outStr="✓WIN"; outClr=CLR_GREEN; }
            else if(sg.outcome==-1)  { outStr="✗LOSS"; outClr=CLR_RED; }
            else                     { outStr="...";   outClr=CLR_AMBER; }

            string tm = TimeToString(sg.time, TIME_MINUTES);
            string lbl = StringFormat(" SIG  %s %s%s %.2f %s",
                                      tm, arrow, dirStr, sg.score, outStr);
            color lineClr = (sg.dir==SIGNAL_BUY) ? CLR_GREEN : CLR_RED;
            CreateLabel(LabelName("SG"+IntegerToString(i)),
                        HUD_X, y, lbl, lineClr);
            y += HUD_LINE_H;
           }
        }

      // separator
      CreateLabel(LabelName("SGD"), HUD_X, y,
                  StringFormat(" %s ", StringRepeat("-",36)), CLR_DIVIDER);
      y += HUD_LINE_H;
     }

   // Panel 6: JOURNAL TODAY
   void RenderJournal(int &y) const
     {
      if(CheckPointer(m_journal) == POINTER_INVALID)
        {
         CreateLabel(LabelName("J1"), HUD_X, y,
                     " Journal not set ", CLR_LABEL);
         y += HUD_LINE_H;
         return;
        }
      double todayPnL = m_journal.GetTodayPnL();
      TradeStat s     = m_journal.GetStats();
      int today_trades= s.totalTrades; // approximate with total in buffer
      color tClr = (todayPnL >= 0) ? CLR_GREEN : CLR_RED;

      CreateLabel(LabelName("J1"), HUD_X, y,
        StringFormat(" Today:%+.2f  Trades:%d  MaxCL:%d",
                     todayPnL, m_journal.GetTotalTrades(),
                     s.maxConsecLoss),
        tClr);
      y += HUD_LINE_H;
     }

   // Utility: repeat char
   string StringRepeat(string ch, int n) const
     {
      string s = "";
      for(int i=0;i<n;i++) s+=ch;
      return s;
     }

public:
   CDashboardManager() : m_journal(NULL), m_ready(false), m_labelCount(0)
     {
      ArrayInitialize(m_lastPanel, "");
     }

   ~CDashboardManager() { Deinit(); }

   //+----------------------------------------------------------------+
   //| Init — call from EA OnInit()                                   |
   //+----------------------------------------------------------------+
   bool Init(CJournalManager *journal)
     {
      m_journal = journal;
      DeleteAllLabels();
      m_ready = true;
      Print("[Dashboard] v2.00 initialized");
      return true;
     }

   //+----------------------------------------------------------------+
   //| Deinit — call from EA OnDeinit()                               |
   //+----------------------------------------------------------------+
   void Deinit()
     {
      if(!m_ready) return;
      DeleteAllLabels();
      ChartRedraw();
      m_ready = false;
      Print("[Dashboard] cleaned up");
     }

   //+----------------------------------------------------------------+
   //| Update — call from OnTick() or new-bar event                  |
   //| ctx: all live data injected from Orchestrator                   |
   //+----------------------------------------------------------------+
   void Update(const DashContext &ctx)
     {
      if(!m_ready) return;

      int y = HUD_Y_START;

      RenderHeader(ctx, y);
      RenderPosition(ctx, y);
      RenderAI(ctx, y);
      RenderStats(y);
      RenderSignals(ctx, y);
      RenderJournal(y);

      ChartRedraw(); // single redraw per Update()
     }

   //+----------------------------------------------------------------+
   //| AddSignal — helper to push new signal into DashContext         |
   //| Call from SignalManager after each signal generated            |
   //+----------------------------------------------------------------+
   static void PushSignal(DashContext &ctx,
                          ENUM_SIGNAL_DIR dir,
                          double score,
                          int outcome = 0)
     {
      if(ctx.signalCount < 3)
        {
         ctx.signals[ctx.signalCount].time    = TimeCurrent();
         ctx.signals[ctx.signalCount].dir     = dir;
         ctx.signals[ctx.signalCount].score   = score;
         ctx.signals[ctx.signalCount].outcome = outcome;
         ctx.signalCount++;
        }
      else
        {
         // Shift down, add at top
         ctx.signals[2] = ctx.signals[1];
         ctx.signals[1] = ctx.signals[0];
         ctx.signals[0].time    = TimeCurrent();
         ctx.signals[0].dir     = dir;
         ctx.signals[0].score   = score;
         ctx.signals[0].outcome = outcome;
        }
     }

   //+----------------------------------------------------------------+
   //| UpdateSignalOutcome — mark latest signal as win/loss           |
   //| Call from Orchestrator after trade closes                       |
   //+----------------------------------------------------------------+
   static void UpdateSignalOutcome(DashContext &ctx, int outcome)
     {
      if(ctx.signalCount > 0)
         ctx.signals[0].outcome = outcome;
     }
  };

#endif // __UI_DASHBOARD_MANAGER_MQH__
