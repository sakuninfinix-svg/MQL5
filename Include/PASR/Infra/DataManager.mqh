//+------------------------------------------------------------------+
//|                                     Infra/DataManager.mqh        |
//|                          Copyright 2026, Agsicentre              |
//+------------------------------------------------------------------+
//| v2.00 (2026-05-24) — Sprint 20                                    |
//|   DM-001: OnBar() datetime cast from TimeToStruct() is wrong —   |
//|           TimeToStruct() returns bool not datetime. Fixed to use  |
//|           direct date string comparison via TimeToString()        |
//|   DM-002: ShouldUpdateDashboard() — m_lastDashboardUpdate is     |
//|           datetime (seconds) but compared to GetMicrosecondCount  |
//|           (microseconds). Fixed to use TimeCurrent() comparison.  |
//|   DM-003: ScavengeOldGVs() — GlobalVariableGet(name+"_time")     |
//|           reads a GV named "MYVAR_time" which does not exist;     |
//|           time is NOT stored per-variable this way in MQL5.       |
//|           Fixed: use GlobalVariableTime() built-in instead.       |
//+------------------------------------------------------------------+
#property strict
#ifndef __INFRA_DATAMANAGER_MQH__
#define __INFRA_DATAMANAGER_MQH__

#include "../Core/IManager.mqh"
#include "../Core/EventBus.mqh"
#include "../Core/Events.mqh"
#include "../Core/Globals.mqh"

class IDataManager;

class DataManager : public IDataManager
  {
private:
   double    m_atrPoints;
   double    m_dailyProfit;
   double    m_startBalance;
   int       m_consecutiveLosses;
   datetime  m_lastScavengeTime;
   datetime  m_lastDashboardUpdate;  // DM-002 FIX: keep as datetime (seconds)

   int       m_atrHandle;
   datetime  m_lastATRUpdate;
   datetime  m_lastTickEventTime;
   int       m_tickEventCount;

   string    m_todayStr;  // DM-001 FIX: cache today's date string

   static const int  SCAVENGE_INTERVAL_SEC    = 300;
   static const int  DASHBOARD_THROTTLE_SEC   = 1;    // DM-002: seconds, not ms
   static const int  ATR_UPDATE_INTERVAL_SEC  = 300;
   static const int  TICK_EVENT_THROTTLE_SEC  = 1;    // simplified: 1 tick-event/sec max

public:
   DataManager()
     : m_atrPoints(0.0), m_dailyProfit(0.0),
       m_consecutiveLosses(0),
       m_lastScavengeTime(0), m_lastDashboardUpdate(0),
       m_atrHandle(INVALID_HANDLE), m_lastATRUpdate(0),
       m_lastTickEventTime(0), m_tickEventCount(0),
       m_todayStr("")
     { m_startBalance = AccountInfoDouble(ACCOUNT_BALANCE); }

   ~DataManager() { ReleaseATRHandle(); }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      m_startBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      m_todayStr     = TimeToString(TimeCurrent(), TIME_DATE);  // DM-001
      RefreshDailyProfit();
      InitializeATRHandle();
      return true;
     }

   virtual void OnTick() override
     {
      datetime now = TimeCurrent();

      if(now - m_lastATRUpdate > ATR_UPDATE_INTERVAL_SEC)
        { UpdateATRCache(); m_lastATRUpdate = now; }

      if(now - m_lastScavengeTime > SCAVENGE_INTERVAL_SEC)
        { ScavengeOldGVs(); m_lastScavengeTime = now; }
     }

   // DM-001 FIX: compare date strings, not cast bool→datetime
   virtual void OnBar(const MqlRates &bar) override
     {
      string barDate = TimeToString(bar.time, TIME_DATE);
      if(barDate != m_todayStr)
        {
         m_dailyProfit = 0.0;
         m_todayStr    = barDate;  // DM-001: update cached date
        }
     }

   virtual void OnTrade(const MqlTradeTransaction &trans) override {}

   double   GetATRPoints()         const { return m_atrPoints;         }
   double   GetDailyProfit()       const { return m_dailyProfit;       }
   double   GetStartBalance()      const { return m_startBalance;      }
   int      GetConsecutiveLosses() const { return m_consecutiveLosses; }

   void UpdateConsecutiveLosses(double profit)
     { m_consecutiveLosses = (profit < 0) ? m_consecutiveLosses+1 : 0; }

   void RefreshDailyProfit()
     { m_dailyProfit = AccountInfoDouble(ACCOUNT_BALANCE) - m_startBalance; }

   // DM-002 FIX: compare datetime seconds only
   bool ShouldUpdateDashboard()
     {
      datetime now = TimeCurrent();
      if(now - m_lastDashboardUpdate >= DASHBOARD_THROTTLE_SEC)
        { m_lastDashboardUpdate = now; return true; }
      return false;
     }

   // DM-003 FIX: use GlobalVariableTime() which returns actual creation/modify time
   void ScavengeOldGVs()
     {
      string prefix = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_PASR_";
      int count = GlobalVariablesTotal();
      for(int i = count-1; i >= 0; i--)
        {
         string name = GlobalVariableName(i);
         if(StringFind(name, prefix) != 0) continue;
         // DM-003 FIX: GlobalVariableTime() returns last set time of the variable
         datetime varTime = GlobalVariableTime(name);
         if(varTime > 0 && TimeCurrent() - varTime > 7*24*3600)
            GlobalVariableDelete(name);
        }
     }

   void InitializeATRHandle()
     {
      if(m_atrHandle != INVALID_HANDLE) return;
      m_atrHandle = iATR(_Symbol, _Period, 14);
      if(m_atrHandle == INVALID_HANDLE)
         PASRLogWarn("[DataManager] Failed to create ATR handle");
      else
         PASRLogInfo("[DataManager] ATR handle initialized (cached)");
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

#endif // __INFRA_DATAMANAGER_MQH__
//+------------------------------------------------------------------+
