//+------------------------------------------------------------------+
//|                                            Data/ZoneStruct.mqh   |
//|  Shared SDZone structure for Supply/Demand zone detection        |
//|  Used by both Data/ZoneManager.mqh and Analysis/ZoneManager.mqh  |
//+------------------------------------------------------------------+
#property strict
#ifndef __DATA_ZONE_STRUCT_MQH__
#define __DATA_ZONE_STRUCT_MQH__

// Supply/Demand zone data structure with confidence scoring
struct SDZone
  {
   double   high;            // zone upper bound
   double   low;             // zone lower bound
   double   origin;          // candle that created the zone
   bool     isSupply;        // true = supply (resistance), false = demand (support)
   int      touchCount;      // how many times price entered zone
   datetime createdTime;     // time zone was created
   datetime consumedTime;    // time zone was consumed (if inactive)
   bool     isActive;        // false once zone is consumed
   double   freshnessPct;    // 1.0 = untouched, 0.0 = fully consumed
   double   confidence;      // 0.0-1.0 confidence score based on multiple factors

   void Init()
     {
      ZeroMemory(this);
      freshnessPct = 1.0;
      confidence   = 0.5;     // default neutral confidence
      isActive     = true;
     }
     
   // Get zone midpoint
   double Midpoint() const
     {
      return (high + low) * 0.5;
     }
     
   // Get zone height in points
   double Height() const
     {
      return high - low;
     }
     
   // Check if price is within zone
   bool Contains(double price) const
     {
      return (price >= low && price <= high);
     }
     
   // Calculate strength score (0-100)
   double Strength() const
     {
      if(!isActive) return 0.0;
      return (freshnessPct * 0.4 + confidence * 0.4 + 
              MathMin(1.0, touchCount / 5.0) * 0.2) * 100.0;
     }
  };

#endif // __DATA_ZONE_STRUCT_MQH__
