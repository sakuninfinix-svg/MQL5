//+------------------------------------------------------------------+
//| Trade/RecoveryManager.mqh — v2.20                                |
//| Compile-safe recovery manager compatibility wrapper               |
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

class CRecoveryManager : public IManager
  {
private:
   CTrade         m_trade;
   RecoveryEngine m_engine;
   RecoveryStats  m_stats;
   bool           m_enabled;

public:
   CRecoveryManager() : IManager(), m_enabled(true)
     {
      m_stats.Clear();
      m_engine.Reset();
     }

   virtual string HandlerName() const override { return "RecoveryManager"; }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_TRADE_OPEN);
      AddEvent(EVENT_ID_TRADE_CLOSE);
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
     }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      m_trade.SetExpertMagicNumber((ulong)m_cfg.MagicNumber);
      return true;
     }

   virtual void Deinit() override
     {
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
           }
        }
      else if(ev.id == EVENT_ID_CONFIG_RELOAD)
        {
         OnConfigReload();
        }
     }

   void OnTradeOpen(ulong ticket, int direction, double entryPrice)
     {
      if(!m_enabled || ticket == 0) return;
      m_engine.active = true;
      m_engine.mainTicket = ticket;
      m_engine.direction = direction;
      m_engine.entryPrice = entryPrice;
      m_engine.entryTime = TimeCurrent();
      m_engine.state = TRADE_STATE_NORMAL;
     }

   virtual void OnPriceUpdate() override
     {
      // Compatibility hook for CPipelineEngine.
     }

   virtual void OnNewBar() override
     {
      // Compatibility hook for CPipelineEngine.
     }

   virtual void OnConfigReload() override
     {
      IManager::OnConfigReload();
      m_trade.SetExpertMagicNumber((ulong)m_cfg.MagicNumber);
     }

   void SetEnabled(bool enabled) { m_enabled = enabled; }
   bool IsEnabled() const { return m_enabled; }
   virtual bool IsHealthy() const override { return IManager::IsHealthy(); }
   RecoveryStats GetStats() const { return m_stats; }
   int GetActiveEngineCount() const { return m_engine.active ? 1 : 0; }
  };

class RecoveryManager : public CRecoveryManager {};

#endif // __TRADE_RECOVERY_MANAGER_MQH__
