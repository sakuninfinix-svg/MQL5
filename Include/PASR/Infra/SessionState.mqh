//+------------------------------------------------------------------+
//| Infra/SessionState.mqh — v1.00 (Sprint 7 — NEW)                 |
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
                     SSessionSnapshot() :
                        peak_equity(0), start_equity(0), current_equity(0),
                        daily_pnl(0), weekly_pnl(0),
                        max_drawdown(0), current_drawdown(0),
                        open_positions(0), trades_today(0),
                        session_start(0), last_trade_time(0) {}
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
   bool              IsNewDay();

private:
   void              CleanStaleGV();
   void              LoadFromGV();
   void              PersistToGV();
   void              RecalcDrawdown();
   void              BroadcastSnapshot();
   void              Log(const string msg) const;
  };

const string CSessionState::GV_PEAK_EQUITY  = "peak_equity";
const string CSessionState::GV_DAILY_PNL    = "daily_pnl";
const string CSessionState::GV_WEEKLY_PNL   = "weekly_pnl";
const string CSessionState::GV_MAX_DD       = "max_drawdown";
const string CSessionState::GV_TRADES_TODAY = "trades_today";
const string CSessionState::GV_LAST_TRADE   = "last_trade_time";

CSessionState::CSessionState()
  : m_magic(0), m_gv_enabled(true), m_stale_cleaned(false), m_bus(NULL) {}

bool CSessionState::Initialize(CEventBus *bus)
  {
   if(CheckPointer(bus) == POINTER_INVALID) { Print("[SessionState][ERROR] NULL bus"); return false; }
   m_bus = bus;
   CleanStaleGV();
   m_snap.session_start  = TimeCurrent();
   m_snap.start_equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   m_snap.current_equity = m_snap.start_equity;
   m_snap.peak_equity    = m_snap.start_equity;
   LoadFromGV();
   PASREvent sub; sub.id = EVENT_ID_TRADE_CLOSED;
   m_bus.Subscribe(GetPointer(this), sub.id);
   Log("Initialized. Start equity=" + DoubleToString(m_snap.start_equity, 2));
   return true;
  }

void CSessionState::Shutdown()      { PersistToGV(); Log("Shutdown — state persisted."); }

void CSessionState::OnEvent(const PASREvent &ev)
  {
   if(ev.id == EVENT_ID_TRADE_CLOSED)
      RecordTrade(ev.value1, (int)ev.value2);
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
   Log("Trade: pnl=" + DoubleToString(realized_pnl, 2) +
       " daily=" + DoubleToString(m_snap.daily_pnl, 2) +
       " DD=" + DoubleToString(m_snap.current_drawdown, 2) + "%");
  }

void CSessionState::UpdateOpenPositions(int count)
  { if(m_snap.open_positions != count) m_snap.open_positions = count; }

bool CSessionState::IsNewDay()
  {
   MqlDateTime now, last;
   TimeToStruct(TimeCurrent(), now);
   TimeToStruct(m_snap.session_start, last);
   return (now.day != last.day || now.mon != last.mon);
  }

void CSessionState::CleanStaleGV()
  {
   if(m_stale_cleaned) return;
   double last_ts = GVGet(GV_LAST_TRADE, 0.0, m_magic);
   if(last_ts > 0)
     {
      MqlDateTime stored, now;
      TimeToStruct((datetime)last_ts, stored);
      TimeToStruct(TimeCurrent(), now);
      bool same_day = (stored.day == now.day && stored.mon == now.mon && stored.year == now.year);
      if(!same_day)
        {
         Log("Stale GV detected (prev day) — clearing daily state.");
         GVDelete(GV_DAILY_PNL, m_magic);
         GVDelete(GV_TRADES_TODAY, m_magic);
        }
     }
   m_stale_cleaned = true;
  }

void CSessionState::LoadFromGV()
  {
   if(!m_gv_enabled) return;
   m_snap.peak_equity    = GVGet(GV_PEAK_EQUITY,  m_snap.start_equity, m_magic);
   m_snap.daily_pnl      = GVGet(GV_DAILY_PNL,    0.0, m_magic);
   m_snap.weekly_pnl     = GVGet(GV_WEEKLY_PNL,   0.0, m_magic);
   m_snap.max_drawdown   = GVGet(GV_MAX_DD,        0.0, m_magic);
   m_snap.trades_today   = (int)GVGet(GV_TRADES_TODAY, 0.0, m_magic);
   m_snap.last_trade_time= (datetime)GVGet(GV_LAST_TRADE, 0.0, m_magic);
  }

void CSessionState::PersistToGV()
  {
   if(!m_gv_enabled) return;
   GVSet(GV_PEAK_EQUITY,  m_snap.peak_equity,  m_magic);
   GVSet(GV_DAILY_PNL,    m_snap.daily_pnl,    m_magic);
   GVSet(GV_WEEKLY_PNL,   m_snap.weekly_pnl,   m_magic);
   GVSet(GV_MAX_DD,       m_snap.max_drawdown, m_magic);
   GVSet(GV_TRADES_TODAY, m_snap.trades_today, m_magic);
   GVSet(GV_LAST_TRADE,   (double)m_snap.last_trade_time, m_magic);
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
   ev.value1  = m_snap.daily_pnl;
   ev.value2  = m_snap.current_drawdown;
   ev.priority = 50;
   m_bus.Push(ev);
  }

void CSessionState::Log(const string msg) const { PrintFormat("[SessionState] %s", msg); }

#endif // __INFRA_SESSION_STATE_MQH__
