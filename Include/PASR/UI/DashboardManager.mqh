//+------------------------------------------------------------------+
//| UI/DashboardManager.mqh — v2.20                                  |
//| Runtime dashboard manager with observability overlay.             |
//+------------------------------------------------------------------+
#property strict
#ifndef __UI_DASHBOARD_MANAGER_MQH__
#define __UI_DASHBOARD_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "../Core/PipelineTypes.mqh"
#include "../Infra/JournalManager.mqh"

struct DashContext
  {
   double equity;
   double balance;
   double dailyPnL;
   double drawdownPct;
   int    openPositions;
   string status;

   void Clear()
     {
      equity = 0.0;
      balance = 0.0;
      dailyPnL = 0.0;
      drawdownPct = 0.0;
      openPositions = 0;
      status = "OK";
     }
  };

class CDashboardManager : public IManager
  {
private:
   DashContext      m_ctx;
   CJournalManager *m_journal;
   datetime         m_lastUpdate;
   int              m_updateIntervalSec;
   string           m_prefix;
   SSignal          m_lastSignal;
   double           m_aiScore;
   EMarketRegime    m_regime;
   double           m_sessionDD;
   string           m_observabilityText;

   void PushSignal(DashContext &ctx, ENUM_SIGNAL_DIR dir, double confidence, int source)
     {
      string d = "NONE";
      if(dir == SIGNAL_BUY) d = "BUY";
      else if(dir == SIGNAL_SELL) d = "SELL";
      ctx.status = StringFormat("Signal=%s conf=%.2f src=%d", d, confidence, source);
     }

public:
   CDashboardManager()
      : IManager(), m_journal(NULL), m_lastUpdate(0), m_updateIntervalSec(1), m_prefix("PASR"),
        m_aiScore(0.0), m_regime(REGIME_UNKNOWN), m_sessionDD(0.0), m_observabilityText("")
     {
      m_ctx.Clear();
      m_lastSignal.Clear();
     }

   virtual string HandlerName() const override { return "DashboardManager"; }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_TIMER);
      AddEvent(EVENT_SIGNAL_GENERATED);
     }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      m_lastUpdate = 0;
      return true;
     }

   virtual void Deinit() override
     {
      Comment("");
      IManager::Deinit();
     }

   virtual void OnEvent(const PASREvent &ev) override
     {
      if(ev.id == EVENT_SIGNAL_GENERATED)
        {
         ENUM_SIGNAL_DIR dir = ((ENUM_ORDER_TYPE)ev.ticket == ORDER_TYPE_SELL) ? SIGNAL_SELL : SIGNAL_BUY;
         PushSignal(m_ctx, dir, ev.data2, 0);
        }
      else if(ev.id == EVENT_ID_TIMER)
         OnTimerEvent();
     }

   void OnTimerEvent()
     {
      Update(m_ctx);
     }

   void OnTimer()
     {
      OnTimerEvent();
     }

   void OnChartEvent(const int id, const long lparam, const double dparam, const string sparam)
     {
      if(id == CHARTEVENT_OBJECT_CLICK)
         m_ctx.status = "Chart click: " + sparam;
     }

   void SetPipelineSignal(SSignal &signal)
     {
      m_lastSignal = signal;
      PushSignal(m_ctx, signal.direction, signal.confidence, 0);
     }

   void SetAIScore(double aiScore)
     {
      m_aiScore = aiScore;
     }

   void SetRegime(EMarketRegime regime)
     {
      m_regime = regime;
     }

   void SetSessionDD(double dd)
     {
      m_sessionDD = dd;
      m_ctx.drawdownPct = dd;
     }

   void SetObservabilityText(const string text)
     {
      m_observabilityText = text;
     }

   string GetObservabilityText() const
     {
      return m_observabilityText;
     }

   void SetJournal(CJournalManager *journal) { m_journal = journal; }
   void SetPrefix(string prefix) { if(prefix != "") m_prefix = prefix; }
   void SetUpdateInterval(int seconds) { m_updateIntervalSec = MathMax(1, seconds); }

   void Update(DashContext &ctx)
     {
      datetime now = TimeCurrent();
      if(now - m_lastUpdate < m_updateIntervalSec) return;
      m_lastUpdate = now;

      ctx.balance = AccountInfoDouble(ACCOUNT_BALANCE);
      ctx.equity  = AccountInfoDouble(ACCOUNT_EQUITY);
      ctx.openPositions = PositionsTotal();

      if(m_data != NULL)
         ctx.dailyPnL = m_data.GetDailyProfit();

      // Read headroom values from config if data manager is available
      double slHeadPips = 0.0, tpHeadPips = 0.0;
      if(m_data != NULL)
        {
         StrategyConfig cfg = m_data.GetConfig();
         slHeadPips = cfg.Risk.SLHeadroomPips;
         tpHeadPips = cfg.Risk.TPHeadroomPips;
        }
      string headroomStr = "";
      if(slHeadPips > 0.0 || tpHeadPips > 0.0)
         headroomStr = StringFormat(" SLbuf=%.1f TPbuf=%.1f", slHeadPips, tpHeadPips);

      string text = m_prefix + " Dashboard\n";
      text += "Balance: " + DoubleToString(ctx.balance, 2) + "\n";
      text += "Equity : " + DoubleToString(ctx.equity, 2) + "\n";
      text += "Daily : " + DoubleToString(ctx.dailyPnL, 2) + "\n";
      text += "DD    : " + DoubleToString(m_sessionDD, 2) + "%\n";
      text += "AI    : " + DoubleToString(m_aiScore, 3) + "\n";
      text += "Regime: " + MarketRegimeName(m_regime) + "\n";
      text += "Open  : " + IntegerToString(ctx.openPositions) + "\n";
      text += "State : " + ctx.status + headroomStr;
      if(m_observabilityText != "")
         text += "\nObs   : " + m_observabilityText;
      Comment(text);
     }
  };

#endif // __UI_DASHBOARD_MANAGER_MQH__
