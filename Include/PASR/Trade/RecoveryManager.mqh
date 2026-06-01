//+------------------------------------------------------------------+
//| Trade/RecoveryManager.mqh — v2.30                                |
//| Compile-safe recovery manager compatibility wrapper + diagnostics |
//+------------------------------------------------------------------+
#property strict
#ifndef __TRADE_RECOVERY_MANAGER_MQH__
#define __TRADE_RECOVERY_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "RecoveryEngine.mqh"
#include <Trade/Trade.mqh>

struct RecoveryStats
  {
   int    attempts;
   int    successes;
   int    failures;
   double recoveredPnL;
   void Clear()
     {
      attempts = 0;
      successes = 0;
      failures = 0;
      recoveredPnL = 0.0;
     }
  };

struct RecoverySnapshot
  {
   bool      enabled;
   bool      active;
   int       activeEngineCount;
   ulong     mainTicket;
   int       direction;
   double    entryPrice;
   datetime  entryTime;
   int       state;
   int       attempts;
   int       successes;
   int       failures;
   double    recoveredPnL;
   datetime  lastUpdate;
   string    lastReason;

   void Clear()
     {
      enabled = false;
      active = false;
      activeEngineCount = 0;
      mainTicket = 0;
      direction = 0;
      entryPrice = 0.0;
      entryTime = 0;
      state = 0;
      attempts = 0;
      successes = 0;
      failures = 0;
      recoveredPnL = 0.0;
      lastUpdate = 0;
      lastReason = "";
     }
  };

class CRecoveryManager : public IManager
  {
private:
   CTrade          m_trade;
   RecoveryEngine  m_engine;
   RecoveryStats   m_stats;
   RecoverySnapshot m_snapshot;
   bool            m_enabled;

   void RefreshSnapshot(const string reason = "")
     {
      m_snapshot.enabled = m_enabled;
      m_snapshot.active = m_engine.active;
      m_snapshot.activeEngineCount = m_engine.active ? 1 : 0;
      m_snapshot.mainTicket = m_engine.mainTicket;
      m_snapshot.direction = m_engine.direction;
      m_snapshot.entryPrice = m_engine.entryPrice;
      m_snapshot.entryTime = m_engine.entryTime;
      m_snapshot.state = (int)m_engine.state;
      m_snapshot.attempts = m_stats.attempts;
      m_snapshot.successes = m_stats.successes;
      m_snapshot.failures = m_stats.failures;
      m_snapshot.recoveredPnL = m_stats.recoveredPnL;
      m_snapshot.lastUpdate = TimeCurrent();
      if(reason != "") m_snapshot.lastReason = reason;
     }

public:
   CRecoveryManager() : IManager(), m_enabled(true)
     {
      m_stats.Clear();
      m_engine.Reset();
      m_snapshot.Clear();
      RefreshSnapshot("Constructed");
     }

   virtual string HandlerName() const override { return "RecoveryManager"; }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_TRADE_OPEN);
      AddEvent(EVENT_ID_TRADE_CLOSE);
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
      AddEvent(EVENT_ID_EMERGENCY_STOP);
     }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      m_trade.SetExpertMagicNumber((ulong)m_cfg.MagicNumber);
      RefreshSnapshot("Init");
      return true;
     }

   virtual void Deinit() override
     {
      RefreshSnapshot("Deinit");
      IManager::Deinit();
     }

   virtual void OnEvent(const PASREvent &ev) override
     {
      if(ev.id == EVENT_ID_TRADE_OPEN)
        {
         int dir = (ev.data1 >= 0.0) ? 1 : -1;
         OnTradeOpen(ev.ticket, dir, 0.0);
        }
      else if(ev.id == EVENT_ID_TRADE_CLOSE)
        {
         if(ev.profit < 0.0)
           {
            m_stats.attempts++;
            m_stats.failures++;
            RefreshSnapshot("LossObserved");
           }
         else if(ev.profit > 0.0)
           {
            m_stats.successes++;
            m_stats.recoveredPnL += ev.profit;
            RefreshSnapshot("ProfitObserved");
           }
        }
      else if(ev.id == EVENT_ID_CONFIG_RELOAD)
        {
         OnConfigReload();
        }
      else if(ev.id == EVENT_ID_EMERGENCY_STOP)
        {
         m_engine.Reset();
         RefreshSnapshot("EmergencyStop");
        }
     }

   void OnTradeOpen(ulong ticket, int direction, double entryPrice)
     {
      if(!m_enabled)
        {
         RefreshSnapshot("TradeOpenIgnoredDisabled");
         return;
        }
      if(ticket == 0)
        {
         RefreshSnapshot("TradeOpenIgnoredNoTicket");
         return;
        }
      m_engine.active = true;
      m_engine.mainTicket = ticket;
      m_engine.direction = direction;
      m_engine.entryPrice = entryPrice;
      m_engine.entryTime = TimeCurrent();
      m_engine.state = TRADE_STATE_NORMAL;
      RefreshSnapshot("TradeOpenTracked");
     }

   virtual void OnPriceUpdate() override
     {
      RefreshSnapshot("PriceUpdate");
     }

   virtual void OnNewBar() override
     {
      RefreshSnapshot("NewBar");
     }

   virtual void OnConfigReload() override
     {
      IManager::OnConfigReload();
      m_trade.SetExpertMagicNumber((ulong)m_cfg.MagicNumber);
      RefreshSnapshot("ConfigReload");
     }

   void SetEnabled(bool enabled)
     {
      m_enabled = enabled;
      if(!m_enabled) m_engine.Reset();
      RefreshSnapshot(enabled ? "Enabled" : "Disabled");
     }

   bool IsEnabled() const { return m_enabled; }
   virtual bool IsHealthy() const override { return IManager::IsHealthy(); }
   RecoveryStats GetStats() const { return m_stats; }
   RecoverySnapshot GetSnapshot() const { return m_snapshot; }
   int GetActiveEngineCount() const { return m_engine.active ? 1 : 0; }

   void PrintDiagnostics() const
     {
      PrintFormat("[RecoveryDiag] enabled=%s active=%s ticket=%I64u dir=%d state=%d attempts=%d success=%d fail=%d pnl=%.2f reason=%s",
                  m_snapshot.enabled ? "true" : "false",
                  m_snapshot.active ? "true" : "false",
                  m_snapshot.mainTicket,
                  m_snapshot.direction,
                  m_snapshot.state,
                  m_snapshot.attempts,
                  m_snapshot.successes,
                  m_snapshot.failures,
                  m_snapshot.recoveredPnL,
                  m_snapshot.lastReason);
     }
  };

class RecoveryManager : public CRecoveryManager {};

#endif // __TRADE_RECOVERY_MANAGER_MQH__
