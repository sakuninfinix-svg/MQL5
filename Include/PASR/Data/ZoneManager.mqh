//+------------------------------------------------------------------+
//|                                        Data/ZoneManager.mqh      |
//|  FIX #9 (2026-05-21): removed stale forward to ../3.ZoneManager  |
//|  Self-contained stub with compilable CZoneManager definition.   |
//|  Full implementation pending in Analysis/ZoneManager.mqh Phase 2 |
//+------------------------------------------------------------------+
#property strict
#ifndef __DATA_ZONE_MANAGER_MQH__
#define __DATA_ZONE_MANAGER_MQH__

#include "../Core/IManager.mqh"

// Supply/Demand zone data structure
struct SDZone
  {
   double   high;           // zone upper bound
   double   low;            // zone lower bound
   double   origin;         // candle that created the zone
   bool     isSupply;       // true = supply (resistance), false = demand (support)
   int      touchCount;     // how many times price entered zone
   datetime createdTime;    // time zone was created
   bool     isActive;       // false once zone is consumed
   double   freshnessPct;   // 1.0 = untouched, 0.0 = fully consumed

   void Init()
     {
      ZeroMemory(this);
      freshnessPct = 1.0;
      isActive     = true;
     }
  };

//+------------------------------------------------------------------+
//| CZoneManager — Supply/Demand zone detection stub                 |
//| Provides compilable interface for Phase 1 compilation.           |
//| Full implementation (candle-body zone detection, freshness decay)|
//| is Phase 2 work.                                                 |
//+------------------------------------------------------------------+
#define ZONE_MAX_ZONES 30

class CZoneManager : public IManager
  {
private:
   SDZone  m_zones[ZONE_MAX_ZONES];
   int     m_zoneCount;

public:
   CZoneManager() : IManager(), m_zoneCount(0)
     {
      for(int i = 0; i < ZONE_MAX_ZONES; i++) m_zones[i].Init();
     }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
     }

   virtual void OnNewBar() override
     {
      // TODO Phase 2: detect impulse moves → identify base candles
      // → mark supply/demand zones from the base candle body range
      // → update freshness based on subsequent price action
     }

   // Returns true if price is currently inside any active zone
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

// Backward-compat alias
typedef CZoneManager ZoneManager;

#endif // __DATA_ZONE_MANAGER_MQH__
