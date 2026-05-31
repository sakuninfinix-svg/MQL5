//+------------------------------------------------------------------+
//| Infra/DataManager.mqh                                            |
//+------------------------------------------------------------------+
#property strict
#ifndef __INFRA_DATAMANAGER_MQH__
#define __INFRA_DATAMANAGER_MQH__

#include "../Core/IManager.mqh"
#include "../Core/Globals.mqh"

#define PASR_DATA_SCAVENGE_INTERVAL_SEC    300
#define PASR_DATA_DASHBOARD_THROTTLE_SEC   1
#define PASR_DATA_ATR_UPDATE_INTERVAL_SEC  300
#define PASR_DATA_TICK_EVENT_THROTTLE_SEC  1

class CDataManager : public IManager
  {
private:
   StrategyConfig m_config;

   double    m_atrPoints;
   double    m_dailyProfit;
   double    m_startBalance;
   int       m_consecutiveLosses;
   datetime  m_lastScavengeTime;
   datetime  m_lastDashboardUpdate;

   int       m_atrHandle;
   datetime  m_lastATRUpdate;
   datetime  m_lastTickEventTime;
   int       m_tickEventCount;

   string    m_todayStr;

   double FloatingPnL() const
     {
      double floating = 0.0;
      int total = PositionsTotal();
      for(int i = total - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;
         floating += PositionGetDouble(POSITION_PROFIT);
        }
      return floating;
     }

public:
   CDataManager()
     : IManager(),
       m_atrPoints(0.0), m_dailyProfit(0.0),
       m_startBalance(AccountInfoDouble(ACCOUNT_BALANCE)),
       m_consecutiveLosses(0),
       m_lastScavengeTime(0), m_lastDashboardUpdate(0),
       m_atrHandle(INVALID_HANDLE), m_lastATRUpdate(0),
       m_lastTickEventTime(0), m_tickEventCount(0),
       m_todayStr("")
     {}

   ~CDataManager() { ReleaseATRHandle(); }

   virtual string HandlerName() const override { return "DataManager"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(this, bus)) return false;
      m_cfg = m_config;
      m_cfgDirty = false;
      m_startBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      m_todayStr = TimeToString(TimeCurrent(), TIME_DATE);
      RefreshDailyProfit();
      InitializeATRHandle();
      return true;
     }

   virtual void Deinit() override
     {
      ReleaseATRHandle();
      IManager::Deinit();
     }

   virtual void OnTick()
     {
      datetime now = TimeCurrent();
      if(now - m_lastATRUpdate > PASR_DATA_ATR_UPDATE_INTERVAL_SEC)
        { UpdateATRCache(); m_lastATRUpdate = now; }
      if(now - m_lastScavengeTime > PASR_DATA_SCAVENGE_INTERVAL_SEC)
        { ScavengeOldGVs(); m_lastScavengeTime = now; }
      RefreshDailyProfit();
     }

   void OnBar(const MqlRates &bar)
     {
      string barDate = TimeToString(bar.time, TIME_DATE);
      if(barDate != m_todayStr)
        {
         m_startBalance = AccountInfoDouble(ACCOUNT_BALANCE);
         m_dailyProfit  = 0.0;
         m_todayStr     = barDate;
         if(m_debugMode)
            PrintFormat("[DataManager] New day baseline reset: startBalance=%.2f", m_startBalance);
        }
      RefreshDailyProfit();
     }

   void OnTrade(const MqlTradeTransaction &trans)
     { RefreshDailyProfit(); }

   StrategyConfig GetConfig() const
     { return m_config; }

   void GetConfigCache(StrategyConfig &out) const
     { out = m_config; }

   void SetConfig(const StrategyConfig &cfg)
     {
      m_config = cfg;
      m_cfg    = cfg;
      m_cfgDirty = false;
     }

   double GetATRPoints() const         { return m_atrPoints;         }
   double GetDailyProfit() const       { return m_dailyProfit;       }
   double GetStartBalance() const      { return m_startBalance;      }
   int    GetConsecutiveLosses() const { return m_consecutiveLosses; }

   void UpdateConsecutiveLosses(double profit)
     { m_consecutiveLosses = (profit < 0) ? m_consecutiveLosses+1 : 0; }

   void RefreshDailyProfit()
     {
      m_dailyProfit = (AccountInfoDouble(ACCOUNT_BALANCE) - m_startBalance) + FloatingPnL();
     }

   bool ShouldUpdateDashboard()
     {
      datetime now = TimeCurrent();
      if(now - m_lastDashboardUpdate >= PASR_DATA_DASHBOARD_THROTTLE_SEC)
        { m_lastDashboardUpdate = now; return true; }
      return false;
     }

   void ScavengeOldGVs()
     {
      string prefix = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_PASR_";
      int count = GlobalVariablesTotal();
      for(int i = count-1; i >= 0; i--)
        {
         string name = GlobalVariableName(i);
         if(StringFind(name, prefix) != 0) continue;
         datetime varTime = GlobalVariableTime(name);
         if(varTime > 0 && TimeCurrent() - varTime > 7*24*3600)
            GlobalVariableDel(name);
        }
     }

   void InitializeATRHandle()
     {
      if(m_atrHandle != INVALID_HANDLE) return;
      m_atrHandle = iATR(_Symbol, _Period, 14);
      if(m_atrHandle == INVALID_HANDLE)
         PASRLogWarn("DataManager", "Failed to create ATR handle");
      else
         PASRLogInfo("DataManager", "ATR handle initialized cached");
     }

   void ReleaseATRHandle()
     {
      if(m_atrHandle != INVALID_HANDLE)
        { IndicatorRelease(m_atrHandle); m_atrHandle = INVALID_HANDLE; }
     }

   void UpdateATRCache()
     {
      if(m_atrHandle == INVALID_HANDLE) return;
      double buf[1];
      if(CopyBuffer(m_atrHandle, 0, 0, 1, buf) > 0 && buf[0] > 0)
         m_atrPoints = buf[0];
     }
  };

class DataManager : public CDataManager {};

#endif // __INFRA_DATAMANAGER_MQH__
