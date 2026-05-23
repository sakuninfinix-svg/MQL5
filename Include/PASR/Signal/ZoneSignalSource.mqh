//+------------------------------------------------------------------+
//| Signal/ZoneSignalSource.mqh — v1.00                              |
//| PASR 3rd Pillar: Supply & Demand Zone Signal Source              |
//|                                                                   |
//| PURPOSE:                                                          |
//|   Score signal strength based on price proximity to              |
//|   Supply/Demand (SD) zones from CAnalysisZoneManager.            |
//|   Implements ISignalSource interface.                            |
//|                                                                   |
//| SIGNAL LOGIC:                                                     |
//|   BUY signal  → price entering Demand zone from above           |
//|   SELL signal → price entering Supply zone from below           |
//|   Score 0..1 based on: zone freshness, proximity, zone strength  |
//|                                                                   |
//| INTEGRATION:                                                      |
//|   Register with SignalManager:                                   |
//|     m_signal->RegisterSource(new CZoneSignalSource(m_zone))      |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_ZONE_SIGNAL_SOURCE_MQH__
#define __SIGNAL_ZONE_SIGNAL_SOURCE_MQH__

#include "ISignalSource.mqh"
#include "../Analysis/ZoneManager.mqh"
#include "../Core/PASR.Types.mqh"

//--- Zone proximity scoring thresholds (in ATR multiples)
#define ZONE_ENTRY_THRESHOLD_ATR   0.3  // Price within 0.3 ATR of zone edge = "in zone"
#define ZONE_FRESH_BONUS           0.2  // Untouched zone gets +0.2 score bonus
#define ZONE_MAX_SCORE             1.0
#define ZONE_MIN_STRENGTH          0.4  // Ignore weak zones below this threshold

//+------------------------------------------------------------------+
//| CZoneSignalSource — Supply/Demand zone proximity scorer          |
//+------------------------------------------------------------------+
class CZoneSignalSource : public ISignalSource
  {
private:
   CAnalysisZoneManager *m_zone;      // Non-owning reference
   double                m_last_score;
   ENUM_SIGNAL_TYPE      m_last_signal;
   datetime              m_last_eval;

   //--- Score a single zone against current price
   double ScoreZone(const SDZone &z, double price, double atr)
     {
      if(!z.active || z.strength < ZONE_MIN_STRENGTH) return 0.0;

      double zone_mid   = (z.top + z.bottom) * 0.5;
      double zone_half  = (z.top - z.bottom) * 0.5;
      double threshold  = atr * ZONE_ENTRY_THRESHOLD_ATR;

      // Distance from zone boundaries
      double dist_top    = MathAbs(price - z.top);
      double dist_bottom = MathAbs(price - z.bottom);
      double dist_near   = MathMin(dist_top, dist_bottom);

      // Check if price is approaching or inside zone
      bool in_zone      = (price >= z.bottom - threshold &&
                           price <= z.top    + threshold);
      if(!in_zone) return 0.0;

      // Base score: proximity (closer = higher)
      double proximity_score = 1.0 - (dist_near / (zone_half + threshold));
      proximity_score = MathMax(0.0, MathMin(1.0, proximity_score));

      // Freshness bonus: untouched zones are more reliable
      double freshness = z.touch_count == 0 ? ZONE_FRESH_BONUS : 0.0;

      // Strength multiplier
      double score = (proximity_score + freshness) * z.strength;
      return MathMin(ZONE_MAX_SCORE, score);
     }

public:
              CZoneSignalSource(CAnalysisZoneManager *zone_mgr)
     : m_zone(zone_mgr), m_last_score(0.0),
       m_last_signal(SIGNAL_NONE), m_last_eval(0)
     {}

   //--- ISignalSource interface
   virtual string SourceName() const override
     { return "ZoneSignalSource"; }

   virtual double Weight() const override
     { return 0.35; } // Zone = 35% weight in confluence (SR=40%, Pattern=25%)

   virtual ENUM_SIGNAL_TYPE Evaluate(double bid, double ask,
                                      double atr,  datetime bar_time,
                                      double &score) override
     {
      score = 0.0;
      m_last_signal = SIGNAL_NONE;

      if(CheckPointer(m_zone) == POINTER_INVALID) return SIGNAL_NONE;

      double price = (bid + ask) * 0.5;
      if(atr <= 0.0) return SIGNAL_NONE;

      // Scan all active zones
      double best_demand = 0.0;
      double best_supply = 0.0;
      int    zone_count  = m_zone.GetZoneCount();

      for(int i = 0; i < zone_count; i++)
        {
         SDZone z;
         if(!m_zone.GetZone(i, z)) continue;

         double s = ScoreZone(z, price, atr);
         if(s <= 0.0) continue;

         if(z.type == ZONE_DEMAND && s > best_demand) best_demand = s;
         if(z.type == ZONE_SUPPLY && s > best_supply) best_supply = s;
        }

      // Resolve signal from best zone scores
      if(best_demand > best_supply && best_demand > 0.0)
        {
         score             = best_demand;
         m_last_signal     = SIGNAL_BUY;
         m_last_score      = score;
         m_last_eval       = bar_time;
         return SIGNAL_BUY;
        }
      else if(best_supply > best_demand && best_supply > 0.0)
        {
         score             = best_supply;
         m_last_signal     = SIGNAL_SELL;
         m_last_score      = score;
         m_last_eval       = bar_time;
         return SIGNAL_SELL;
        }

      m_last_score  = 0.0;
      m_last_eval   = bar_time;
      return SIGNAL_NONE;
     }

   //--- Accessors
   double            LastScore()  const { return m_last_score; }
   ENUM_SIGNAL_TYPE  LastSignal() const { return m_last_signal; }
  };

#endif // __SIGNAL_ZONE_SIGNAL_SOURCE_MQH__
