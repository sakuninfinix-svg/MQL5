//+------------------------------------------------------------------+
//|                                        Data/ZoneManager.mqh      |
//|  Legacy stub for backward compatibility                          |
//|  SDZone struct moved to ZoneStruct.mqh for reusability           |
//|  Full implementation in Analysis/ZoneManager.mqh v2.00           |
//+------------------------------------------------------------------+
#property strict
#ifndef __DATA_ZONE_MANAGER_MQH__
#define __DATA_ZONE_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "ZoneStruct.mqh"  // Shared SDZone struct

// Backward-compat alias - use CAnalysisZoneManager from Analysis folder instead
class CZoneManager : public IManager
  {
private:
   SDZone  m_zones[30];
   int     m_zoneCount;

public:
   CZoneManager() : IManager(), m_zoneCount(0)
     {
      for(int i = 0; i < 30; i++) m_zones[i].Init();
     }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
     }

   virtual void OnNewBar() override
     {
      // Deprecated: Use CAnalysisZoneManager from Analysis folder
      // This is a stub for backward compatibility only
     }

   bool IsPriceInZone(double price, SDZone &out) const
     {
      for(int i = 0; i < m_zoneCount; i++)
        {
         if(!m_zones[i].isActive) continue;
         if(price >= m_zones[i].low && price <= m_zones[i].high)
           {
            out = m_zones[i];
            return true;
           }
        }
      return false;
     }

   int  GetZoneCount() const { return m_zoneCount; }
  };

typedef CZoneManager ZoneManager;

#endif // __DATA_ZONE_MANAGER_MQH__
