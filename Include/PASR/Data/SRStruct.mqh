//+------------------------------------------------------------------+
//| Data/SRStruct.mqh — v1.00                                        |
//| Support & Resistance Zone Structure Definition                   |
//|                                                                  |
//| Defines the core SRZone struct used throughout the PASR system   |
//| for support/resistance zone detection, clustering, and scoring.  |
//+------------------------------------------------------------------+
#property strict
#ifndef __DATA_SR_STRUCT_MQH__
#define __DATA_SR_STRUCT_MQH__

//+------------------------------------------------------------------+
//| SRZone — Core Support/Resistance Zone Structure                  |
//+------------------------------------------------------------------+
struct SRZone
  {
   double   price;          // Central price level of the zone
   double   high;           // Upper boundary of the zone
   double   low;            // Lower boundary of the zone
   bool     isSupport;      // true = support, false = resistance
   bool     isBroken;       // Zone has been broken by price action
   int      touchCount;     // Number of times price touched/reacted at zone
   int      lastTouchAge;   // Bars since last touch
   datetime lastTouchTime;  // Time of last touch
   double   strength;       // Zone strength score (0-100)
   
   // Initialize zone with default values
   void Init()
     {
      price         = 0.0;
      high          = 0.0;
      low           = 0.0;
      isSupport     = true;
      isBroken      = false;
      touchCount    = 0;
      lastTouchAge  = 0;
      lastTouchTime = 0;
      strength      = 0.0;
     }
     
   // Get zone type as string
   string GetType() const
     {
      return isSupport ? "SUPPORT" : "RESISTANCE";
     }
     
   // Check if zone is currently valid for trading
   bool IsValid() const
     {
      return (!isBroken && touchCount >= 2 && strength > 0.0);
     }
     
   // Calculate distance from current price to zone
   double DistanceFrom(double currentPrice) const
     {
      if(currentPrice > price)
         return currentPrice - high;
      else
         return low - currentPrice;
     }
     
   // Check if price is within zone boundaries
   bool IsPriceInZone(double currentPrice) const
     {
      return (currentPrice >= low && currentPrice <= high);
     }
     
   // Format zone info as string
   string ToString() const
     {
      return StringFormat("SRZone[%.5f|%.5f-%.5f|%s|Str=%.1f|Touches=%d|Age=%d|Broken=%s]",
                         price, low, high, 
                         isSupport ? "SUP" : "RES",
                         strength, touchCount, lastTouchAge,
                         isBroken ? "Y" : "N");
     }
     
   // Compare zones by strength (for sorting)
   bool operator>(const SRZone &other) const
     {
      return strength > other.strength;
     }
     
   bool operator<(const SRZone &other) const
     {
      return strength < other.strength;
     }
  };

//+------------------------------------------------------------------+
//| SRZoneResult — Result structure for SR queries                   |
//+------------------------------------------------------------------+
struct SRZoneResult
  {
   bool     found;
   SRZone   zone;
   double   distance;
   string   reason;
   
   void Clear()
     {
      found    = false;
      zone.Init();
      distance = 0.0;
      reason   = "";
     }
  };

//+------------------------------------------------------------------+
//| SRCluster — Group of related SR zones                            |
//+------------------------------------------------------------------+
struct SRCluster
  {
   double   avgPrice;       // Average price of clustered zones
   double   maxHigh;        // Highest boundary in cluster
   double   minLow;         // Lowest boundary in cluster
   int      zoneCount;      // Number of zones in cluster
   double   totalStrength;  // Sum of all zone strengths
   bool     isSupportCluster; // Cluster type
   
   void Init()
     {
      avgPrice         = 0.0;
      maxHigh          = 0.0;
      minLow           = DBL_MAX;
      zoneCount        = 0;
      totalStrength    = 0.0;
      isSupportCluster = true;
     }
     
   void AddZone(const SRZone &z)
     {
      if(zoneCount == 0)
         isSupportCluster = z.isSupport;
         
      totalStrength += z.strength;
      zoneCount++;
      
      // Update boundaries
      maxHigh = MathMax(maxHigh, z.high);
      minLow  = MathMin(minLow, z.low);
      
      // Recalculate average price
      avgPrice = (avgPrice * (zoneCount - 1) + z.price) / zoneCount;
     }
     
   double GetAvgStrength() const
     {
      return zoneCount > 0 ? totalStrength / zoneCount : 0.0;
     }
  };

#endif // __DATA_SR_STRUCT_MQH__
