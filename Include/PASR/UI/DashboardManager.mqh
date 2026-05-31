//+------------------------------------------------------------------+
//| UI/DashboardManager.mqh — v2.03                                  |
//| Runtime dashboard manager.                                       |
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

   void PushSignal(DashContext &ctx, ENUM_SIGNAL_DIR dir, double confidence, int source)
     {
      string d = "NONE";
      if(dir == SIGNAL_BUY) d = "BUY";
      else if(dir == SIGNAL_SELL) d = "SELL";
      ctx.status = StringFormat("Signal=%s conf=%.2f src=%d", d, confidence, source);
     }

public:
   CDashboardManager()
      : IManager(), m_journal(NULL), m_lastUpdate(0), m_updateIntervalSec(1), m_prefix("PASR")
     {
      m_ctx.Clear();
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
        {
         ctx.dailyPnL = m_data.GetDailyProfit();
        }

      string text = m_prefix + " Dashboard\n";
      text += "Balance: " + DoubleToString(ctx.balance, 2) + "\n";
      text += "Equity : " + DoubleToString(ctx.equity, 2) + "\n";
      text += "Daily : " + DoubleToString(ctx.dailyPnL, 2) + "\n";
      text += "Open  : " + IntegerToString(ctx.openPositions) + "\n";
      text += "State : " + ctx.status;
      Comment(text);
     }
  };

#endif // __UI_DASHBOARD_MANAGER_MQH__
