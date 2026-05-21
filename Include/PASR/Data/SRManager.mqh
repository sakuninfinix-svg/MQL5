//+------------------------------------------------------------------+
//|                                          Data/SRManager.mqh      |
//|  FIX #9 (2026-05-21): removed stale forward to ../4.SRManager.mqh |
//|  The root-level numbered files are legacy and may not exist in  |
//|  clean installs. This stub now self-contains a minimal           |
//|  compilable CSRManager definition that forwards to the           |
//|  canonical implementation once Analysis/SRManager.mqh is full.  |
//|                                                                  |
//|  MIGRATION STATUS: stub → full implementation pending in        |
//|  Analysis/SRManager.mqh (Issue #5 — Phase 2 work)               |
//+------------------------------------------------------------------+
#property strict
#ifndef __DATA_SR_MANAGER_MQH__
#define __DATA_SR_MANAGER_MQH__

#include "../Core/IManager.mqh"

// SR Zone data structure
struct SRZone
  {
   double   price;         // zone midpoint price
   double   high;          // zone upper bound
   double   low;           // zone lower bound
   int      touchCount;    // number of price touches
   datetime lastTouchTime; // time of most recent touch
   int      lastTouchAge;  // bars since last touch
   double   strength;      // zone strength score 0-100
   bool     isBroken;      // true if price closed through zone
   bool     isSupport;     // true = support, false = resistance

   void Init()
     {
      price        = 0.0;
      high         = 0.0;
      low          = 0.0;
      touchCount   = 0;
      lastTouchTime = 0;
      lastTouchAge = 0;
      strength     = 0.0;
      isBroken     = false;
      isSupport    = false;
     }
  };

//+------------------------------------------------------------------+
//| CSRManager — stub awaiting full implementation in Phase 2        |
//| Provides compilable interface so Orchestrator + RecoveryManager  |
//| can compile without the legacy ../4.SRManager.mqh root file.     |
//+------------------------------------------------------------------+
#define SR_MAX_ZONES 50

class CSRManager : public IManager
  {
private:
   SRZone  m_zones[SR_MAX_ZONES];
   int     m_zoneCount;

public:
   CSRManager() : IManager(), m_zoneCount(0)
     {
      for(int i = 0; i < SR_MAX_ZONES; i++) m_zones[i].Init();
     }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
     }

   virtual void OnNewBar() override
     {
      // TODO Phase 2: implement swing high/low detection + zone clustering
      // Algorithm: scan lookback bars for pivot highs/lows,
      // cluster nearby levels within ATR/2, score by touch count.
     }

   // Returns nearest support zone below |price|, or false if none.
   bool GetNearestSupport(double price, SRZone &out) const
     {
      double bestDist = DBL_MAX;
      bool   found    = false;
      for(int i = 0; i < m_zoneCount; i++)
        {
         if(!m_zones[i].isSupport) continue;
         if(m_zones[i].isBroken)   continue;
         if(m_zones[i].price >= price) continue;
         double d = price - m_zones[i].price;
         if(d < bestDist) { bestDist = d; out = m_zones[i]; found = true; }
        }
      return found;
     }

   // Returns nearest resistance zone above |price|, or false if none.
   bool GetNearestResistance(double price, SRZone &out) const
     {
      double bestDist = DBL_MAX;
      bool   found    = false;
      for(int i = 0; i < m_zoneCount; i++)
        {
         if(m_zones[i].isSupport) continue;
         if(m_zones[i].isBroken)  continue;
         if(m_zones[i].price <= price) continue;
         double d = m_zones[i].price - price;
         if(d < bestDist) { bestDist = d; out = m_zones[i]; found = true; }
        }
      return found;
     }

   // Zone validation — called before using a zone for trading decisions
   bool IsZoneValid(const SRZone &zone) const
     {
      int  minTouches  = (m_cfg.MagicNumber > 0) ? 2 : 2; // placeholder until cfg exposed
      int  maxZoneAge  = 200;  // bars
      double minStrength = 20.0;
      return (zone.touchCount >= minTouches &&
              zone.lastTouchAge <= maxZoneAge &&
              zone.strength >= minStrength &&
              !zone.isBroken);
     }

   int GetZoneCount() const { return m_zoneCount; }
  };

// Backward-compat alias (some files may use SRManager without C prefix)
typedef CSRManager SRManager;

#endif // __DATA_SR_MANAGER_MQH__
