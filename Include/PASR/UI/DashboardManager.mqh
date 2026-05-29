//+------------------------------------------------------------------+
//| UI/DashboardManager.mqh — v2.01                                  |
//| Live on-chart HUD panel for PASR EA.                             |
//+------------------------------------------------------------------+
#property strict
#ifndef __UI_DASHBOARD_MANAGER_MQH__
#define __UI_DASHBOARD_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "../Core/PipelineTypes.mqh"
#include "../Infra/JournalManager.mqh"
#include "../AI/AITypes.mqh"
#include "../Trade/TradePlan.mqh"

#define HUD_X          15
#define HUD_Y_START    20
#define HUD_LINE_H     16
#define HUD_FONT       "Consolas"
#define HUD_FONT_SZ    8
#define HUD_PREFIX     "PASR_HUD_"
#define HUD_GAUGE_W    10

#define CLR_HEADER     C'40,44,52'
#define CLR_LABEL      C'150,150,160'
#define CLR_VALUE      C'220,220,230'
#define CLR_GREEN      C'74,222,128'
#define CLR_RED        C'248,113,113'
#define CLR_AMBER      C'251,191,36'
#define CLR_BLUE       C'96,165,250'
#define CLR_PURPLE     C'167,139,250'
#define CLR_DIVIDER    C'60,63,70'

struct SignalSnap
  {
   datetime  time;
   ENUM_SIGNAL_DIR dir;
   double    score;
   int       outcome;
  };

struct DashContext
  {
   bool     hasPosition;
   ENUM_SIGNAL_DIR posDir;
   double   posEntry;
   double   posSL;
   double   posTP1;
   double   posTP2;
   double   posLots;
   double   posPnL;
   bool     beDone;
   bool     partialDone;

   double   aiScore;
   double   driftScore;
   int      ensembleModel;
   bool     aiVeto;

   EMarketRegime regime;
   ENUM_TRADING_SESSION session;
   double   spread;

   SignalSnap signals[3];
   int        signalCount;

   void Clear()
     {
      hasPosition=false; posDir=SIGNAL_NONE; posEntry=0; posSL=0; posTP1=0; posTP2=0;
      posLots=0; posPnL=0; beDone=false; partialDone=false;
      aiScore=0; driftScore=0; ensembleModel=-1; aiVeto=false;
      regime=REGIME_UNKNOWN; session=SESSION_UNKNOWN; spread=0;
      signalCount=0;
      for(int i=0; i<3; i++)
        {
         signals[i].time=0;
         signals[i].dir=SIGNAL_NONE;
         signals[i].score=0;
         signals[i].outcome=0;
        }
     }
  };

class CDashboardManager : public IManager
  {
private:
   CJournalManager *m_journal;
   bool             m_ready;
   int              m_labelCount;
   string           m_lastPanel[6];
   DashContext      m_ctx;

   string LabelName(string id) const { return HUD_PREFIX + id; }

   string RepeatText(string ch, int n) const
     {
      string s = "";
      for(int i=0; i<n; i++) s += ch;
      return s;
     }

   void CreateLabel(string name, int x, int y, string text, color clr,
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

   string Gauge(double val, int width = HUD_GAUGE_W) const
     {
      int filled = (int)MathRound(MathMin(MathMax(val, 0.0), 1.0) * width);
      string s = "[";
      for(int i=0; i<width; i++) s += (i < filled) ? "=" : "-";
      return s + "]";
     }

   string RegimeStr(EMarketRegime r) const
     {
      switch(r)
        {
         case REGIME_TREND_UP:    return "TrendUp";
         case REGIME_TREND_DOWN:  return "TrendDn";
         case REGIME_RANGE:       return "Range";
         case REGIME_VOLATILE:    return "Volatile";
         case REGIME_SQUEEZE:     return "Squeeze";
         case REGIME_TRANSITION:  return "Transition";
         case REGIME_CRASH:       return "Crash";
         default:                 return "Unknown";
        }
     }

   string SessionStr(ENUM_TRADING_SESSION s) const
     {
      switch(s)
        {
         case SESSION_SYDNEY:   return "Sydney";
         case SESSION_TOKYO:    return "Tokyo";
         case SESSION_LONDON:   return "London";
         case SESSION_NEW_YORK: return "NewYork";
         case SESSION_OVERLAP:  return "Overlap";
         default:               return "Unknown";
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

   void RenderHeader(const DashContext &ctx, int &y) const
     {
      string tf = EnumToString(Period());
      string spr = StringFormat("Spr:%.1f", ctx.spread);
      string tm  = TimeToString(TimeCurrent(), TIME_SECONDS);
      CreateLabel(LabelName("H1"), HUD_X, y,
                  StringFormat(" PASR | %s %s %s %s ", _Symbol, tf, spr, tm), CLR_VALUE);
      y += HUD_LINE_H;
      CreateLabel(LabelName("HD"), HUD_X, y, StringFormat(" %s ", RepeatText("-",36)), CLR_DIVIDER);
      y += HUD_LINE_H;
     }

   void RenderPosition(const DashContext &ctx, int &y) const
     {
      if(!ctx.hasPosition)
        {
         CreateLabel(LabelName("P1"), HUD_X, y, " No open position ", CLR_LABEL); y += HUD_LINE_H;
         CreateLabel(LabelName("P2"), HUD_X, y, "", CLR_LABEL); y += HUD_LINE_H;
         CreateLabel(LabelName("P3"), HUD_X, y, "", CLR_LABEL); y += HUD_LINE_H;
        }
      else
        {
         string arrow = (ctx.posDir == SIGNAL_BUY) ? "BUY" : "SELL";
         color  dc    = (ctx.posDir == SIGNAL_BUY) ? CLR_GREEN : CLR_RED;
         string flags = (ctx.beDone ? "[BE]" : "") + (ctx.partialDone ? "[PC]" : "");
         CreateLabel(LabelName("P1"), HUD_X, y,
           StringFormat(" %s %.5f SL:%.5f TP:%.5f %s", arrow, ctx.posEntry, ctx.posSL, ctx.posTP1, flags), dc);
         y += HUD_LINE_H;
         CreateLabel(LabelName("P2"), HUD_X, y,
           (ctx.posTP2 > 0.0) ? StringFormat(" TP2:%.5f Lots:%.2f", ctx.posTP2, ctx.posLots)
                              : StringFormat(" Lots:%.2f", ctx.posLots), CLR_LABEL);
         y += HUD_LINE_H;
         color pnlClr = (ctx.posPnL > 0) ? CLR_GREEN : (ctx.posPnL < 0) ? CLR_RED : CLR_LABEL;
         CreateLabel(LabelName("P3"), HUD_X, y, StringFormat(" PnL: %+.2f USD", ctx.posPnL), pnlClr);
         y += HUD_LINE_H;
        }
      CreateLabel(LabelName("PD"), HUD_X, y, StringFormat(" %s ", RepeatText("-",36)), CLR_DIVIDER);
      y += HUD_LINE_H;
     }

   void RenderAI(const DashContext &ctx, int &y) const
     {
      string aiGauge    = Gauge(ctx.aiScore);
      string driftGauge = Gauge(ctx.driftScore);
      color aiClr       = (ctx.aiVeto) ? CLR_RED : (ctx.aiScore >= 0.7) ? CLR_GREEN : (ctx.aiScore >= 0.5) ? CLR_AMBER : CLR_RED;
      color driftClr    = (ctx.driftScore > 0.5) ? CLR_RED : CLR_BLUE;

      CreateLabel(LabelName("A1"), HUD_X, y,
        StringFormat(" AI%s%.2f Drift%s%.2f%s", aiGauge, ctx.aiScore, driftGauge, ctx.driftScore, ctx.aiVeto ? " [VETO]" : ""), aiClr);
      y += HUD_LINE_H;
      CreateLabel(LabelName("A2"), HUD_X, y,
        StringFormat(" Model:%-8s Regime:%s", EnsembleStr(ctx.ensembleModel), RegimeStr(ctx.regime)), CLR_PURPLE);
      y += HUD_LINE_H;
      CreateLabel(LabelName("A3"), HUD_X, y,
        StringFormat(" Session:%-10s", SessionStr(ctx.session)), driftClr);
      y += HUD_LINE_H;
      CreateLabel(LabelName("AD"), HUD_X, y, StringFormat(" %s ", RepeatText("-",36)), CLR_DIVIDER);
      y += HUD_LINE_H;
     }

   void RenderStats(int &y) const
     {
      if(CheckPointer(m_journal) == POINTER_INVALID)
        {
         CreateLabel(LabelName("S1"), HUD_X, y, " Stats: journal not set ", CLR_LABEL);
         y += HUD_LINE_H * 2;
         return;
        }
      TradeStat s = m_journal.GetStats(50);
      color pfClr = (s.profitFactor >= 1.5) ? CLR_GREEN : (s.profitFactor >= 1.0) ? CLR_AMBER : CLR_RED;
      CreateLabel(LabelName("S1"), HUD_X, y,
        StringFormat(" Win:%.0f%% PF:%.2f AvgRR:%.1fR", s.winRate*100, s.profitFactor, s.avgRR), pfClr);
      y += HUD_LINE_H;
      CreateLabel(LabelName("S2"), HUD_X, y,
        StringFormat(" MaxDD:%.2f Streak:W%d/L%d", s.maxDrawdown, s.maxConsecWin, s.maxConsecLoss), CLR_LABEL);
      y += HUD_LINE_H;
      CreateLabel(LabelName("SD"), HUD_X, y, StringFormat(" %s ", RepeatText("-",36)), CLR_DIVIDER);
      y += HUD_LINE_H;
     }

   void RenderSignals(const DashContext &ctx, int &y) const
     {
      if(ctx.signalCount == 0)
        {
         CreateLabel(LabelName("SG0"), HUD_X, y, " SIG No recent signals ", CLR_LABEL);
         y += HUD_LINE_H;
        }
      else
        {
         for(int i=0; i<ctx.signalCount && i<3; i++)
           {
            const SignalSnap &sg = ctx.signals[i];
            string dirStr = (sg.dir == SIGNAL_BUY) ? "BUY" : "SEL";
            string outStr = (sg.outcome == 1) ? "WIN" : (sg.outcome == -1) ? "LOSS" : "...";
            color lineClr = (sg.dir==SIGNAL_BUY) ? CLR_GREEN : CLR_RED;
            CreateLabel(LabelName("SG"+IntegerToString(i)), HUD_X, y,
                        StringFormat(" SIG %s %s %.2f %s", TimeToString(sg.time, TIME_MINUTES), dirStr, sg.score, outStr), lineClr);
            y += HUD_LINE_H;
           }
        }
      CreateLabel(LabelName("SGD"), HUD_X, y, StringFormat(" %s ", RepeatText("-",36)), CLR_DIVIDER);
      y += HUD_LINE_H;
     }

   void RenderJournal(int &y) const
     {
      if(CheckPointer(m_journal) == POINTER_INVALID)
        {
         CreateLabel(LabelName("J1"), HUD_X, y, " Journal not set ", CLR_LABEL);
         y += HUD_LINE_H;
         return;
        }
      double todayPnL = m_journal.GetTodayPnL();
      TradeStat s     = m_journal.GetStats();
      color tClr = (todayPnL >= 0) ? CLR_GREEN : CLR_RED;
      CreateLabel(LabelName("J1"), HUD_X, y,
        StringFormat(" Today:%+.2f Trades:%d MaxCL:%d", todayPnL, m_journal.GetTotalTrades(), s.maxConsecLoss), tClr);
      y += HUD_LINE_H;
     }

public:
   CDashboardManager() : IManager(), m_journal(NULL), m_ready(false), m_labelCount(0)
     {
      ArrayInitialize(m_lastPanel, "");
      m_ctx.Clear();
     }

   ~CDashboardManager() { Deinit(); }

   virtual string HandlerName() const override { return "DashboardManager"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      DeleteAllLabels();
      m_ready = true;
      Print("[Dashboard] v2.01 initialized");
      return true;
     }

   bool Init(CJournalManager *journal)
     {
      m_journal = journal;
      DeleteAllLabels();
      m_ready = true;
      Print("[Dashboard] v2.01 initialized");
      return true;
     }

   virtual void Deinit() override
     {
      if(!m_ready)
        {
         IManager::Deinit();
         return;
        }
      DeleteAllLabels();
      ChartRedraw();
      m_ready = false;
      Print("[Dashboard] cleaned up");
      IManager::Deinit();
     }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_TIMER);
      AddEvent(EVENT_SIGNAL_GENERATED);
     }

   virtual void OnEvent(const PASREvent &ev) override
     {
      if(ev.id == EVENT_SIGNAL_GENERATED)
        {
         ENUM_SIGNAL_DIR dir = ((ENUM_ORDER_TYPE)ev.ticket == ORDER_TYPE_SELL) ? SIGNAL_SELL : SIGNAL_BUY;
         PushSignal(m_ctx, dir, ev.data2, 0);
        }
      else if(ev.id == EVENT_ID_TIMER)
         OnTimer();
     }

   virtual void OnTimer() override
     {
      Update(m_ctx);
     }

   void SetJournal(CJournalManager *journal) { m_journal = journal; }

   void Update(const DashContext &ctx)
     {
      if(!m_ready) return;
      m_ctx = ctx;
      int y = HUD_Y_START;
      RenderHeader(ctx, y);
      RenderPosition(ctx, y);
      RenderAI(ctx, y);
      RenderStats(y);
      RenderSignals(ctx, y);
      RenderJournal(y);
      ChartRedraw();
     }

   void SetPipelineSignal(const SSignal &sig)
     {
      if(sig.direction != SIGNAL_NONE)
         PushSignal(m_ctx, sig.direction, sig.confidence, 0);
     }

   void SetAIScore(double score) { m_ctx.aiScore = score; }
   void SetRegime(EMarketRegime regime) { m_ctx.regime = regime; }
   void SetSessionDD(double dd) { m_ctx.posPnL = dd; }

   void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
     {
      // Reserved for future HUD buttons.
     }

   static void PushSignal(DashContext &ctx, ENUM_SIGNAL_DIR dir, double score, int outcome = 0)
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
         ctx.signals[2] = ctx.signals[1];
         ctx.signals[1] = ctx.signals[0];
         ctx.signals[0].time    = TimeCurrent();
         ctx.signals[0].dir     = dir;
         ctx.signals[0].score   = score;
         ctx.signals[0].outcome = outcome;
        }
     }

   static void UpdateSignalOutcome(DashContext &ctx, int outcome)
     {
      if(ctx.signalCount > 0)
         ctx.signals[0].outcome = outcome;
     }
  };

#endif // __UI_DASHBOARD_MANAGER_MQH__