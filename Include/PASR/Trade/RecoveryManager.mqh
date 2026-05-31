//+------------------------------------------------------------------+
//| Trade/RecoveryManager.mqh — v2.19                                |
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
   CTrade        m_trade;
   CRecoveryEngine m_engine;
   RecoveryStats m_stats;
   bool          m_enabled;

   double NormalizeVolumeSafe(double volume, string symbol)
     {
      double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double step   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      if(minLot <= 0.0) minLot = 0.01;
      if(maxLot <= 0.0) maxLot = 100.0;
      if(step <= 0.0) step = 0.01;
      double v = MathMax(minLot, MathMin(maxLot, volume));
      v = MathFloor(v / step) * step;
      return NormalizeDouble(v, 2);
     }

public:
   CRecoveryManager() : IManager(), m_enabled(true)
     {
      m_stats.Clear();
     }

   virtual string HandlerName() const override { return "RecoveryManager"; }

   virtual void DeclareEvents() override
     {
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
      if(ev.id == EVENT_ID_TRADE_CLOSE)
        {
         // Recovery is intentionally conservative during compile-stabilization.
         // The detailed legacy engine remains available for later re-integration.
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

   virtual void OnConfigReload() override
     {
      IManager::OnConfigReload();
      m_trade.SetExpertMagicNumber((ulong)m_cfg.MagicNumber);
     }

   void SetEnabled(bool enabled) { m_enabled = enabled; }
   bool IsEnabled() const { return m_enabled; }
   virtual bool IsHealthy() const override { return IManager::IsHealthy(); }
   RecoveryStats GetStats() const { return m_stats; }
   int GetActiveEngineCount() const { return 0; }
  };

class RecoveryManager : public CRecoveryManager {};

#endif // __TRADE_RECOVERY_MANAGER_MQH__
