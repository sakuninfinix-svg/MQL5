//+------------------------------------------------------------------+
//| Core/IDataManager.mqh — v1.00                                    |
//| Canonical PASR data-provider interface                           |
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_IDATAMANAGER_MQH__
#define __CORE_IDATAMANAGER_MQH__

#include "Config/Types.mqh"
#include "Events.mqh"
#include "EventBus.mqh"

class IDataManager
  {
public:
   virtual bool Init(IDataManager *data, CEventBus *bus) = 0;
   virtual void Deinit() = 0;
   virtual void OnTick() = 0;
   virtual void OnBar(const MqlRates &bar) = 0;
   virtual void OnTrade(const MqlTradeTransaction &trans) = 0;

   virtual const StrategyConfig *GetConfig() const = 0;
   virtual void GetConfigCache(StrategyConfig &out) const = 0;
   virtual void SetConfig(const StrategyConfig &cfg) = 0;

   virtual double GetATRPoints() const = 0;
   virtual double GetDailyProfit() const = 0;
   virtual double GetStartBalance() const = 0;
   virtual int    GetConsecutiveLosses() const = 0;
  };

#endif
