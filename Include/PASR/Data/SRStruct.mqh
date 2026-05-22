//+------------------------------------------------------------------+
//| Data/SRStruct.mqh — Shared SRZone structure                      |
//| Support/Resistance zone data structure for PASR v2.0             |
//+------------------------------------------------------------------+
#property strict
#ifndef __DATA_SR_STRUCT_MQH__
#define __DATA_SR_STRUCT_MQH__

//+------------------------------------------------------------------+
//| SRZone — Basic support/resistance zone structure                 |
//+------------------------------------------------------------------+
struct SRZone
  {
   double low;           // Zone lower price
   double high;          // Zone upper price  
   bool   isSupport;     // True if support zone, false if resistance
   double strength;      // Zone strength score (0-100)
   int    touchCount;    // Number of times price touched this zone
   datetime lastTouch;   // Time of last touch
   int    pivotBar;      // Bar index where zone was formed
   
   // Initialize with default values
   void Init()
     {
      low         = 0.0;
      high        = 0.0;
      isSupport   = true;
      strength    = 0.0;
      touchCount  = 0;
      lastTouch   = 0;
      pivotBar    = -1;
     }
   
   // Check if price is within zone
   bool Contains(double price) const
     {
      return (price >= low && price <= high);
     }
   
   // Get zone midpoint
   double Midpoint() const
     {
      return (low + high) / 2.0;
     }
   
   // Get zone height in points
   double Height() const
     {
      return high - low;
     }
   
   // String representation
   string ToString() const
     {
      return StringFormat("SRZone[%.5f|%.5f|%s|Str=%.1f|Touches=%d]",
                         low, high, isSupport ? "SUP" : "RES", 
                         strength, touchCount);
     }
  };

#endif // __DATA_SR_STRUCT_MQH__
