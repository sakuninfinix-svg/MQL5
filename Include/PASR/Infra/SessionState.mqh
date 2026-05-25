//+------------------------------------------------------------------+
//| Infra/SessionState.mqh — v1.03                                   |
//| SINGLE SOURCE OF TRUTH untuk semua session/equity state          |
//+------------------------------------------------------------------+
#property strict
#ifndef __INFRA_SESSION_STATE_MQH__
#define __INFRA_SESSION_STATE_MQH__

#include "../Core/IManager.mqh"
#include "../Core/EventBus.mqh"
#include "../Core/Events.mqh"
#include "../Core/Globals.mqh"

struct SSessionSnapshot
  {
   double            peak_equity;
   double            start_equity;
   double            current_equity;
   double            daily_pnl;
   double            weekly_pnl;
   double            max_drawdown;
   double            current_drawdown;
   int               open_positions;
   int               trades_today;
   datetime          session_start;
   datetime          last_trade_time;
   datetime          today_midnight;
                     SSessionSnapshot() :
                        peak_equity(0), start_equity(0), current_equity(0),
                        daily_pnl(0), weekly_pnl(0),
                        max_drawdown(0), current_drawdown(0),
                        open_positions(0), trades_today(0),
                        session_start(0), last_trade_time(0),
                        today_midnight(0) {}
  };

class CSessionState : public IManager
  {
private:
   SSessionSnapshot  m_snap;
   long              m_magic;
   bool              m_gv_enabled;
   bool              m_stale_cleaned;

   static const string GV_PEAK_EQUITY;
   static const string GV_DAILY_PNL;
   static const string GV_WEEKLY_PNL;
   static const string GV_MAX_DD;
   static const string GV_TRADES_TODAY;
   static const string GV_LAST_TRADE;
   static const string GV_TODAY_MIDNIGHT;

public:
   CSessionState() : IManager(), m_magic(0), m_gv_enabled(true), m_stale_cleaned(false) {}
   ~CSessionState() { Deinit(); }

   virtual string HandlerName() const override { return "SessionState"; }

   virtual void DeclareEvents() override
     { AddEvent(EVENT_ID_TRADE_CLOSE); }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      CleanStaleGV();
      m_snap.session_start  = TimeCurrent();
      m_snap.start_equity   = AccountInfoDouble(ACCOUNT_EQUITY);
      m_snap.current_equity = m_snap.start_equity;
      m_snap.peak_equity    = m_snap.start_equity;
      m_snap.today_midnight = MidnightFloor(TimeCurrent());
      LoadFromGV();
      if(m_bus != NULL) m_bus.Subscribe(this);
      PASRLogInfo("SessionState", "Initialized. Start equity=" + DoubleToString(m_snap.start_equity, 2));
      return true;
     }

   virtual void Deinit() override
     {
      if(!m_initialized) return;
      PersistToGV();
      PASRLogInfo("SessionState", "Deinit — state persisted.");
      IManager::Deinit();
     }

   bool Initialize(IDataManager *data, CEventBus *bus) { return Init(data, bus); }
   void Shutdown() { Deinit(); }

   virtual void OnEvent(const PASREvent &ev) override
     {
      if(ev.id == EVENT_ID_TRADE_CLOSE)
         RecordTrade(ev.profit, (int)ev.data1);
     }

   void SetMagic(long magic)       { m_magic = magic; }
   void SetGVEnabled(bool enabled) { m_gv_enabled = enabled; }

   void SyncEquity()
     {
      m_snap.current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      RecalcDrawdown();
     }

   void RecordTrade(double realized_pnl, int direction)
     {
      m_snap.daily_pnl       += realized_pnl;
      m_snap.weekly_pnl      += realized_pnl;
      m_snap.trades_today++;
      m_snap.last_trade_time  = TimeCurrent();
      SyncEquity();
      PersistToGV();
      BroadcastSnapshot();
      PASRLogInfo("SessionState", "Trade: pnl=" + DoubleToString(realized_pnl, 2) +
          " daily=" + DoubleToString(m_snap.daily_pnl, 2) +
          " DD=" + DoubleToString(m_snap.current_drawdown, 2) + "%");
     }

   void UpdateOpenPositions(int count)
     { if(m_snap.open_positions != count) m_snap.open_positions = count; }

   const SSessionSnapshot *GetSnapshot() const { return &m_snap; }
   double PeakEquity() const { return m_snap.peak_equity; }
   double DailyPnL() const { return m_snap.daily_pnl; }
   double GetDailyPnL() const { return m_snap.daily_pnl; }
   double CurrentDrawdown() const { return m_snap.current_drawdown; }
   double GetDrawdownPct() const { return m_snap.current_drawdown; }
   double MaxDrawdown() const { return m_snap.max_drawdown; }

   bool IsNewDay()
     {
      datetime current_midnight = MidnightFloor(TimeCurrent());
      if(current_midnight != m_snap.today_midnight)
        {
         m_snap.daily_pnl      = 0;
         m_snap.trades_today   = 0;
         m_snap.today_midnight = current_midnight;
         GVDelete(GV_DAILY_PNL,    m_magic);
         GVDelete(GV_TRADES_TODAY, m_magic);
         PASRLogInfo("SessionState", "New day detected. Daily state reset.");
         return true;
        }
      return false;
     }

private:
   static datetime MidnightFloor(datetime t) { return (datetime)((long)t - (long)t % 86400L); }

   void CleanStaleGV()
     {
      if(m_stale_cleaned) return;
      double stored_midnight = GVGet(GV_TODAY_MIDNIGHT, 0.0, m_magic);
      if(stored_midnight > 0)
        {
         datetime stored = (datetime)stored_midnight;
         datetime current = MidnightFloor(TimeCurrent());
         if(stored != current)
           {
            PASRLogInfo("SessionState", "Stale GV detected (prev day) — clearing daily state.");
            GVDelete(GV_DAILY_PNL,    m_magic);
            GVDelete(GV_TRADES_TODAY, m_magic);
           }
        }
      m_stale_cleaned = true;
     }

   void LoadFromGV()
     {
      if(!m_gv_enabled) return;
      m_snap.peak_equity     = GVGet(GV_PEAK_EQUITY,   m_snap.start_equity, m_magic);
      m_snap.daily_pnl       = GVGet(GV_DAILY_PNL,     0.0, m_magic);
      m_snap.weekly_pnl      = GVGet(GV_WEEKLY_PNL,    0.0, m_magic);
      m_snap.max_drawdown    = GVGet(GV_MAX_DD,        0.0, m_magic);
      m_snap.trades_today    = (int)GVGet(GV_TRADES_TODAY, 0.0, m_magic);
      m_snap.last_trade_time = (datetime)GVGet(GV_LAST_TRADE, 0.0, m_magic);
      double stored_mn = GVGet(GV_TODAY_MIDNIGHT, 0.0, m_magic);
      if(stored_mn > 0) m_snap.today_midnight = (datetime)stored_mn;
     }

   void PersistToGV()
     {
      if(!m_gv_enabled) return;
      GVSet(GV_PEAK_EQUITY,    m_snap.peak_equity,   m_magic);
      GVSet(GV_DAILY_PNL,      m_snap.daily_pnl,     m_magic);
      GVSet(GV_WEEKLY_PNL,     m_snap.weekly_pnl,    m_magic);
      GVSet(GV_MAX_DD,         m_snap.max_drawdown,  m_magic);
      GVSet(GV_TRADES_TODAY,   m_snap.trades_today,  m_magic);
      GVSet(GV_LAST_TRADE,     (double)m_snap.last_trade_time, m_magic);
      GVSet(GV_TODAY_MIDNIGHT, (double)m_snap.today_midnight, m_magic);
     }

   void RecalcDrawdown()
     {
      if(m_snap.current_equity > m_snap.peak_equity)
         m_snap.peak_equity = m_snap.current_equity;
      if(m_snap.peak_equity > 0)
        {
         m_snap.current_drawdown = (m_snap.peak_equity - m_snap.current_equity) / m_snap.peak_equity * 100.0;
         if(m_snap.current_drawdown > m_snap.max_drawdown)
            m_snap.max_drawdown = m_snap.current_drawdown;
        }
     }

   void BroadcastSnapshot()
     {
      if(m_bus == NULL) return;
      PASREvent ev;
      ev.id       = EVENT_ID_SESSION_UPDATED;
      ev.data1    = m_snap.daily_pnl;
      ev.data2    = m_snap.current_drawdown;
      ev.priority = 50;
      m_bus.Push(ev);
     }
  };

const string CSessionState::GV_PEAK_EQUITY    = "peak_equity";
const string CSessionState::GV_DAILY_PNL      = "daily_pnl";
const string CSessionState::GV_WEEKLY_PNL     = "weekly_pnl";
const string CSessionState::GV_MAX_DD         = "max_drawdown";
const string CSessionState::GV_TRADES_TODAY   = "trades_today";
const string CSessionState::GV_LAST_TRADE     = "last_trade_time";
const string CSessionState::GV_TODAY_MIDNIGHT = "today_midnight";

#endif // __INFRA_SESSION_STATE_MQH__
