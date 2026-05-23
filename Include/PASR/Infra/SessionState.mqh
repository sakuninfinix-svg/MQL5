//+------------------------------------------------------------------+
//| Infra/SessionState.mqh — v1.01                                   |
//| SINGLE SOURCE OF TRUTH untuk semua session/equity state          |
//|                                                                  |
//| STATE OWNERSHIP MAP (Sprint 7 contract):                         |
//|   OWNS  : peak_equity, daily_pnl, weekly_pnl, max_drawdown       |
//|            open_positions_count (session-level, NOT pipeline ctx)|
//|            last_trade_time, session_start_time                   |
//|   WRITES: GlobalVariables via GVSet (persistence layer)          |
//|   READS : AccountInfoDouble() untuk equity sync                  |
//|                                                                  |
//| MIGRATION (replace triple-write pattern):                        |
//|   SEBELUM: RiskManager::UpdateDailyLoss() + Telemetry::LogTrade()|
//|            + SnapshotManager::SaveState() semua tulis daily_pnl  |
//|   SESUDAH: Semua manager panggil m_session->RecordTrade() SAJA   |
//|            SessionState yang handle update + GV persistence      |
//|                                                                  |
//| CHANGELOG:                                                       |
//|   v1.01 (2026-05-24) Sprint 18 — SS-002 fix                     |
//|     SS-002: IsNewDay() sekarang bandingkan midnight-floor bukan  |
//|             session_start — fix daily_pnl reset saat EA restart  |
//|             dalam hari yang sama                                  |
//|   v1.00 (2026-05-23) Sprint 7 — Initial implementation           |
//+------------------------------------------------------------------+
#property strict
#ifndef __INFRA_SESSION_STATE_MQH__
#define __INFRA_SESSION_STATE_MQH__

#include "../Core/IManager.mqh"
#include "../Core/EventBus.mqh"
#include "../Core/Events.mqh"
#include "../Core/Globals.mqh"

//+------------------------------------------------------------------+
//| SSessionSnapshot — read-only view for other managers             |
//+------------------------------------------------------------------+
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
   // SS-002 FIX: track midnight floor separately from session_start
   datetime          today_midnight;   // floor(TimeCurrent() / 86400) * 86400
                     SSessionSnapshot() :
                        peak_equity(0), start_equity(0), current_equity(0),
                        daily_pnl(0), weekly_pnl(0),
                        max_drawdown(0), current_drawdown(0),
                        open_positions(0), trades_today(0),
                        session_start(0), last_trade_time(0),
                        today_midnight(0) {}
  };

//+------------------------------------------------------------------+
//| CSessionState — owns all session-level equity/trade state        |
//+------------------------------------------------------------------+
class CSessionState : public IManager
  {
private:
   SSessionSnapshot  m_snap;
   long              m_magic;
   bool              m_gv_enabled;
   bool              m_stale_cleaned;
   CEventBus        *m_bus;

   static const string GV_PEAK_EQUITY;
   static const string GV_DAILY_PNL;
   static const string GV_WEEKLY_PNL;
   static const string GV_MAX_DD;
   static const string GV_TRADES_TODAY;
   static const string GV_LAST_TRADE;
   static const string GV_TODAY_MIDNIGHT;

public:
                     CSessionState();
                    ~CSessionState() {}

   virtual bool      Initialize(CEventBus *bus) override;
   virtual void      Shutdown() override;
   virtual void      OnEvent(const PASREvent &ev) override;
   virtual string    Name() const override { return "CSessionState"; }

   void              SetMagic(long magic)       { m_magic = magic; }
   void              SetGVEnabled(bool enabled) { m_gv_enabled = enabled; }

   void              SyncEquity();
   void              RecordTrade(double realized_pnl, int direction);
   void              UpdateOpenPositions(int count);

   const SSessionSnapshot *GetSnapshot() const { return &m_snap; }

   double            PeakEquity()      const { return m_snap.peak_equity; }
   double            DailyPnL()        const { return m_snap.daily_pnl; }
   double            CurrentDrawdown() const { return m_snap.current_drawdown; }
   double            MaxDrawdown()     const { return m_snap.max_drawdown; }

   // SS-002 FIX: compare midnight-floor, not session_start
   bool              IsNewDay();

private:
   // SS-002 helper: compute UTC midnight floor for a given timestamp
   static datetime   MidnightFloor(datetime t) { return (datetime)((long)t - (long)t % 86400L); }

   void              CleanStaleGV();
   void              LoadFromGV();
   void              PersistToGV();
   void              RecalcDrawdown();
   void              BroadcastSnapshot();
  };

const string CSessionState::GV_PEAK_EQUITY   = "peak_equity";
const string CSessionState::GV_DAILY_PNL     = "daily_pnl";
const string CSessionState::GV_WEEKLY_PNL    = "weekly_pnl";
const string CSessionState::GV_MAX_DD        = "max_drawdown";
const string CSessionState::GV_TRADES_TODAY  = "trades_today";
const string CSessionState::GV_LAST_TRADE    = "last_trade_time";
const string CSessionState::GV_TODAY_MIDNIGHT= "today_midnight";

CSessionState::CSessionState()
  : m_magic(0), m_gv_enabled(true), m_stale_cleaned(false), m_bus(NULL) {}

bool CSessionState::Initialize(CEventBus *bus)
  {
   if(CheckPointer(bus) == POINTER_INVALID)
     { PASRLogError("SessionState", "NULL bus"); return false; }
   m_bus = bus;
   CleanStaleGV();
   m_snap.session_start  = TimeCurrent();
   m_snap.start_equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   m_snap.current_equity = m_snap.start_equity;
   m_snap.peak_equity    = m_snap.start_equity;
   // SS-002 FIX: set midnight floor on init
   m_snap.today_midnight = MidnightFloor(TimeCurrent());
   LoadFromGV();
   m_bus.Subscribe(GetPointer(this), EVENT_ID_TRADE_CLOSED);
   PASRLogInfo("SessionState", "Initialized. Start equity=" + DoubleToString(m_snap.start_equity, 2));
   return true;
  }

void CSessionState::Shutdown()      { PersistToGV(); PASRLogInfo("SessionState", "Shutdown — state persisted."); }

void CSessionState::OnEvent(const PASREvent &ev)
  {
   if(ev.id == EVENT_ID_TRADE_CLOSED)
      RecordTrade(ev.profit, (int)ev.data1);
  }

void CSessionState::SyncEquity()
  {
   m_snap.current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   RecalcDrawdown();
  }

void CSessionState::RecordTrade(double realized_pnl, int direction)
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

void CSessionState::UpdateOpenPositions(int count)
  { if(m_snap.open_positions != count) m_snap.open_positions = count; }

// SS-002 FIX: compare midnight-floor of now vs stored midnight-floor
// Even if EA restarts at 14:00 same day, today_midnight is still same value
bool CSessionState::IsNewDay()
  {
   datetime current_midnight = MidnightFloor(TimeCurrent());
   if(current_midnight != m_snap.today_midnight)
     {
      // new day detected — reset daily counters
      m_snap.daily_pnl     = 0;
      m_snap.trades_today  = 0;
      m_snap.today_midnight = current_midnight;
      GVDelete(GV_DAILY_PNL,    m_magic);
      GVDelete(GV_TRADES_TODAY, m_magic);
      PASRLogInfo("SessionState", "New day detected. Daily state reset.");
      return true;
     }
   return false;
  }

void CSessionState::CleanStaleGV()
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

void CSessionState::LoadFromGV()
  {
   if(!m_gv_enabled) return;
   m_snap.peak_equity    = GVGet(GV_PEAK_EQUITY,   m_snap.start_equity, m_magic);
   m_snap.daily_pnl      = GVGet(GV_DAILY_PNL,     0.0, m_magic);
   m_snap.weekly_pnl     = GVGet(GV_WEEKLY_PNL,    0.0, m_magic);
   m_snap.max_drawdown   = GVGet(GV_MAX_DD,         0.0, m_magic);
   m_snap.trades_today   = (int)GVGet(GV_TRADES_TODAY, 0.0, m_magic);
   m_snap.last_trade_time= (datetime)GVGet(GV_LAST_TRADE, 0.0, m_magic);
   // SS-002: load stored midnight floor
   double stored_mn = GVGet(GV_TODAY_MIDNIGHT, 0.0, m_magic);
   if(stored_mn > 0) m_snap.today_midnight = (datetime)stored_mn;
  }

void CSessionState::PersistToGV()
  {
   if(!m_gv_enabled) return;
   GVSet(GV_PEAK_EQUITY,    m_snap.peak_equity,   m_magic);
   GVSet(GV_DAILY_PNL,      m_snap.daily_pnl,     m_magic);
   GVSet(GV_WEEKLY_PNL,     m_snap.weekly_pnl,    m_magic);
   GVSet(GV_MAX_DD,         m_snap.max_drawdown,  m_magic);
   GVSet(GV_TRADES_TODAY,   m_snap.trades_today,  m_magic);
   GVSet(GV_LAST_TRADE,     (double)m_snap.last_trade_time, m_magic);
   // SS-002: persist midnight floor so restart on same day doesn't reset
   GVSet(GV_TODAY_MIDNIGHT, (double)m_snap.today_midnight, m_magic);
  }

void CSessionState::RecalcDrawdown()
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

void CSessionState::BroadcastSnapshot()
  {
   if(CheckPointer(m_bus) == POINTER_INVALID) return;
   PASREvent ev;
   ev.id      = EVENT_ID_SESSION_UPDATED;
   ev.data1   = m_snap.daily_pnl;
   ev.data2   = m_snap.current_drawdown;
   ev.priority = 50;
   m_bus.Push(ev);
  }

#endif // __INFRA_SESSION_STATE_MQH__
