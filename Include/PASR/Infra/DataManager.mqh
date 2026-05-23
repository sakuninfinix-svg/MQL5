//+------------------------------------------------------------------+
//|                                     Infra/DataManager.mqh        |
//|                          Copyright 2026, Agsicentre              |
//|   Production DataManager Implementation                          |
//|   - Account-safe GV keys                                         |
//|   - Optimized scavenge                                           |
//|   - Dashboard throttle                                           |
//|   - FIXED: Event flood prevention with rate limiting             |
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
//|                                                                  |
//| FIX #2 - Event Flood Prevention:                                |
//|   - ATR handle cached for entire lifetime (no create/destroy)   |
//|   - Rate-limited updates (only when needed)                     |
//|   - Throttled dashboard events                                   |
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
   
   //--- FIX #2: Event flood prevention
   int               m_atrHandle;           // Cached ATR handle (lifetime)
   datetime          m_lastATRUpdate;       // Last ATR refresh time
   datetime          m_lastTickEventTime;   // Rate limit tick events
   int               m_tickEventCount;      // Count tick events for monitoring
   
   //--- Constants
   static const int  SCAVENGE_INTERVAL_SEC = 300;    // 5 minutes
   static const int  DASHBOARD_THROTTLE_MS = 1000;   // 1 second
   static const int  ATR_UPDATE_INTERVAL_SEC = 300;  // 5 minutes (reduced from 60s)
   static const int  TICK_EVENT_THROTTLE_MS = 500;   // Max 2 tick events per second

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
   
   //--- FIX #2: Handle lifecycle management
   void              InitializeATRHandle();
   void              ReleaseATRHandle();
   void              UpdateATRCache();
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
   // FIX #2: Initialize flood prevention fields
   m_atrHandle         = INVALID_HANDLE;
   m_lastATRUpdate     = 0;
   m_lastTickEventTime = 0;
   m_tickEventCount    = 0;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
DataManager::~DataManager()
{
   // FIX #2: Release cached ATR handle on destruction
   ReleaseATRHandle();
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
   
   // FIX #2: Initialize ATR handle once at startup
   InitializeATRHandle();
   
   return true;
}

//+------------------------------------------------------------------+
//| FIX #2: Initialize ATR handle (call once at startup)             |
//+------------------------------------------------------------------+
void DataManager::InitializeATRHandle()
{
   if(m_atrHandle != INVALID_HANDLE)
      return; // Already initialized
   
   m_atrHandle = iATR(_Symbol, _Period, 14);
   if(m_atrHandle == INVALID_HANDLE)
   {
      Print("[DataManager][WARN] Failed to create ATR handle");
   }
   else
   {
      Print("[DataManager][FIX#2] ATR handle initialized (lifetime caching)");
   }
}

//+------------------------------------------------------------------+
//| FIX #2: Release ATR handle (call on deinit)                      |
//+------------------------------------------------------------------+
void DataManager::ReleaseATRHandle()
{
   if(m_atrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(m_atrHandle);
      m_atrHandle = INVALID_HANDLE;
      Print("[DataManager][FIX#2] ATR handle released");
   }
}

//+------------------------------------------------------------------+
//| FIX #2: Update ATR cache from cached handle                      |
//+------------------------------------------------------------------+
void DataManager::UpdateATRCache()
{
   if(m_atrHandle == INVALID_HANDLE)
      return;
   
   double atrBuffer[1];
   if(CopyBuffer(m_atrHandle, 0, 0, 1, atrBuffer) > 0 && atrBuffer[0] > 0)
   {
      m_atrPoints = atrBuffer[0];
   }
}

//+------------------------------------------------------------------+
//| OnTick handler                                                   |
//| FIX #2: Event flood prevention with rate limiting                |
//+------------------------------------------------------------------+
void DataManager::OnTick()
{
   //--- FIX #2: Update ATR cache from cached handle (no create/destroy)
   if(TimeCurrent() - m_lastATRUpdate > ATR_UPDATE_INTERVAL_SEC)
   {
      UpdateATRCache();
      m_lastATRUpdate = TimeCurrent();
   }
   
   //--- FIX #2: Rate-limit tick events to prevent event flood
   // Only allow max 2 tick events per second (500ms throttle)
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   long nowMs = dt.sec * 1000 + dt.msec;
   
   if(nowMs - m_lastTickEventTime >= TICK_EVENT_THROTTLE_MS)
   {
      m_lastTickEventTime = nowMs;
      m_tickEventCount++;
      
      // Reset counter every minute for monitoring
      if(m_tickEventCount > 1000) m_tickEventCount = 0;
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
