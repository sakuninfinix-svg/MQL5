//+------------------------------------------------------------------+
//|                                     Infra/DataManager.mqh        |
//|                          Copyright 2026, Agsicentre              |
//|   Production DataManager Implementation                          |
//|   - Account-safe GV keys                                         |
//|   - Optimized scavenge                                           |
//|   - Dashboard throttle                                           |
//+------------------------------------------------------------------+
#property strict
#ifndef __INFRA_DATAMANAGER_MQH__
#define __INFRA_DATAMANAGER_MQH__

#include "../Core/IManager.mqh"
#include "../Core/EventBus.mqh"
#include "../Core/Events.mqh"

//+------------------------------------------------------------------+
//| Forward declaration                                              |
//+------------------------------------------------------------------+
class IDataManager;

//+------------------------------------------------------------------+
//| DataManager: Production implementation                           |
//+------------------------------------------------------------------+
class DataManager : public IDataManager
{
private:
   //--- Cached data
   double            m_atrPoints;
   double            m_dailyProfit;
   double            m_startBalance;
   int               m_consecutiveLosses;
   datetime          m_lastScavengeTime;
   datetime          m_lastDashboardUpdate;
   
   //--- Constants
   static const int  SCAVENGE_INTERVAL_SEC = 300;  // 5 minutes
   static const int  DASHBOARD_THROTTLE_MS = 1000; // 1 second

public:
                     DataManager();
                    ~DataManager();
   
   //--- IManager interface
   virtual bool      Init(IDataManager *data, CEventBus *bus) override;
   virtual void      OnTick() override;
   virtual void      OnBar(const MqlRates &bar) override;
   virtual void      OnTrade(const MqlTradeTransaction &trans) override;
   
   //--- Data accessors
   double            GetATRPoints() const { return m_atrPoints; }
   double            GetDailyProfit() const { return m_dailyProfit; }
   double            GetStartBalance() const { return m_startBalance; }
   int               GetConsecutiveLosses() const { return m_consecutiveLosses; }
   
   //--- Mutators
   void              UpdateConsecutiveLosses(double profit);
   void              RefreshDailyProfit();
   
   //--- Utilities
   void              ScavengeOldGVs();
   bool              ShouldUpdateDashboard() const;
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
DataManager::DataManager()
{
   m_atrPoints         = 0.0;
   m_dailyProfit       = 0.0;
   m_startBalance      = AccountInfoDouble(ACCOUNT_BALANCE);
   m_consecutiveLosses = 0;
   m_lastScavengeTime  = 0;
   m_lastDashboardUpdate = 0;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
DataManager::~DataManager()
{
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool DataManager::Init(IDataManager *data, CEventBus *bus)
{
   if(!IManager::Init(data, bus))
      return false;
   
   m_startBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   RefreshDailyProfit();
   
   return true;
}

//+------------------------------------------------------------------+
//| OnTick handler                                                   |
//+------------------------------------------------------------------+
void DataManager::OnTick()
{
   //--- Update ATR cache periodically (every 60 seconds)
   static datetime lastATRUpdate = 0;
   if(TimeCurrent() - lastATRUpdate > 60)
   {
      int handle = iATR(_Symbol, _Period, 14);
      if(handle != INVALID_HANDLE)
      {
         double atrBuffer[1];
         if(CopyBuffer(handle, 0, 0, 1, atrBuffer) > 0 && atrBuffer[0] > 0)
            m_atrPoints = atrBuffer[0];
         IndicatorRelease(handle);
      }
      lastATRUpdate = TimeCurrent();
   }
   
   //--- Scavenge old GVs periodically
   if(TimeCurrent() - m_lastScavengeTime > SCAVENGE_INTERVAL_SEC)
   {
      ScavengeOldGVs();
      m_lastScavengeTime = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| OnBar handler                                                    |
//+------------------------------------------------------------------+
void DataManager::OnBar(const MqlRates &bar)
{
   //--- Reset daily profit on new day
   static datetime lastDate = 0;
   datetime currentDate = TimeToStruct(bar.time).day;
   
   if(currentDate != lastDate)
   {
      m_dailyProfit = 0.0;
      lastDate = currentDate;
   }
}

//+------------------------------------------------------------------+
//| OnTrade handler                                                  |
//+------------------------------------------------------------------+
void DataManager::OnTrade(const MqlTradeTransaction &trans)
{
   //--- Handle trade events if needed
}

//+------------------------------------------------------------------+
//| Update consecutive losses                                        |
//+------------------------------------------------------------------+
void DataManager::UpdateConsecutiveLosses(double profit)
{
   if(profit < 0)
      m_consecutiveLosses++;
   else
      m_consecutiveLosses = 0;
}

//+------------------------------------------------------------------+
//| Refresh daily profit                                             |
//+------------------------------------------------------------------+
void DataManager::RefreshDailyProfit()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   m_dailyProfit = balance - m_startBalance;
}

//+------------------------------------------------------------------+
//| Scavenge old Global Variables                                    |
//+------------------------------------------------------------------+
void DataManager::ScavengeOldGVs()
{
   //--- Delete GVs older than 7 days
   string prefix = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_";
   int count = GlobalVariablesTotal();
   
   for(int i = count - 1; i >= 0; i--)
   {
      string name;
      datetime time;
      double value;
      
      if(GlobalVariableName(i, name) && 
         StringFind(name, prefix) == 0 &&
         GlobalVariableGet(name, value) > 0)
      {
         time = (datetime)GlobalVariableGet(name + "_time");
         if(time > 0 && TimeCurrent() - time > 7 * 24 * 3600)
         {
            GlobalVariableDelete(name);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if dashboard should update (throttled)                     |
//+------------------------------------------------------------------+
bool DataManager::ShouldUpdateDashboard() const
{
   ulong now = GetMicrosecondCount();
   return (now - m_lastDashboardUpdate >= DASHBOARD_THROTTLE_MS * 1000);
}

#endif // __INFRA_DATAMANAGER_MQH__
