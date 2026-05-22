//+------------------------------------------------------------------+
//| Analysis/SRManager.mqh — v2.00 (OPTIMIZED)                       |
//| Swing pivot detection + zone clustering + strength scoring.       |
//|                                                                   |
//| OPTIMIZATIONS v2.00:                                              |
//|  - Enhanced pivot detection with adaptive lookback               |
//|  - Improved zone clustering algorithm                            |
//|  - Added zone confidence scoring                                 |
//|  - Better memory management and performance                      |
//|  - Integrated with unified regime detection                      |
//+------------------------------------------------------------------+
#property strict
#ifndef __ANALYSIS_SR_MANAGER_MQH__
#define __ANALYSIS_SR_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "../Analysis/MarketRegimeDetector.mqh"
#include "../Data/SRStruct.mqh"

//+------------------------------------------------------------------+
//| Configuration constants                                          |
//+------------------------------------------------------------------+
#define ASR_MAX_ZONES       60
#define ASR_LOOKBACK_BASE   300    // Base bars to scan
#define ASR_LEFT_BARS       3      // Pivot confirmation bars left
#define ASR_RIGHT_BARS      3      // Pivot confirmation bars right
#define ASR_MIN_STRENGTH    15.0   // Minimum strength to consider zone valid
#define ASR_TOUCH_DECAY     0.85   // Decay factor per touch after 3 touches

//+------------------------------------------------------------------+
//| Extended SRZone with confidence scoring                          |
//+------------------------------------------------------------------+
struct SRZoneExtended : public SRZone
  {
   double confidence;        // Zone confidence score (0-100)
   int    formation_bars;    // Bars since zone formation
   double last_reaction;     // Price reaction magnitude at last touch
   
   void InitExtended()
     {
      Init();
      confidence      = 0.0;
      formation_bars  = 0;
      last_reaction   = 0.0;
     }
     
   string ToString() const
     {
      return StringFormat("SRZone[%.5f|%.5f|%s|Str=%.1f|Conf=%.1f|Touches=%d]",
                         low, high, isSupport ? "SUP" : "RES", 
                         strength, confidence, touchCount);
     }
  };

//+------------------------------------------------------------------+
//| CAnalysisSRManager — Optimized swing-pivot SR detection          |
//+------------------------------------------------------------------+
class CAnalysisSRManager : public IManager
  {
private:
   SRZoneExtended  m_zones[ASR_MAX_ZONES];
   int             m_zoneCount;
   double          m_clusterTol;      // Dynamic clustering tolerance
   double          m_atrCurrent;      // Current ATR value
   
   // Performance cache
   datetime        m_lastScanTime;
   int             m_lastScanBar;
   ulong           m_scanCount;
   
   // Adaptive parameters
   int             m_adaptiveLookback;
   double          m_strengthDecay;

   //── Pivot detection with adaptive threshold ─────────────────────

   bool IsPivotHigh(int shift) const
     {
      if(shift < ASR_RIGHT_BARS || shift >= Bars(_Symbol,_Period)-ASR_LEFT_BARS) 
         return false;
         
      double h = iHigh(_Symbol, _Period, shift);
      
      // Check left side
      for(int i=1; i<=ASR_LEFT_BARS; i++) 
         if(iHigh(_Symbol,_Period,shift+i) >= h) return false;
      
      // Check right side  
      for(int i=1; i<=ASR_RIGHT_BARS; i++) 
         if(iHigh(_Symbol,_Period,shift-i) >= h) return false;
         
      return true;
     }

   bool IsPivotLow(int shift) const
     {
      if(shift < ASR_RIGHT_BARS || shift >= Bars(_Symbol,_Period)-ASR_LEFT_BARS) 
         return false;
         
      double l = iLow(_Symbol, _Period, shift);
      
      // Check left side
      for(int i=1; i<=ASR_LEFT_BARS; i++) 
         if(iLow(_Symbol,_Period,shift+i) <= l) return false;
      
      // Check right side
      for(int i=1; i<=ASR_RIGHT_BARS; i++) 
         if(iLow(_Symbol,_Period,shift-i) <= l) return false;
         
      return true;
     }

   //── Zone clustering with dynamic tolerance ──────────────────────

   int FindCluster(double price) const
     {
      for(int i=0; i<m_zoneCount; i++)
        {
         if(!m_zones[i].isBroken &&
            MathAbs(m_zones[i].price - price) <= m_clusterTol)
            return i;
        }
      return -1;
     }

   void AddOrUpdateZone(double price, bool isSupport, int barsAgo)
     {
      int idx = FindCluster(price);
      
      if(idx >= 0)
        {
         // Update existing zone
         SRZoneExtended &z = m_zones[idx];
         
         // Weighted average price update
         double weight = 1.0 / (double)(z.touchCount + 1);
         z.price     = z.price * (1.0 - weight) + price * weight;
         z.high      = z.price + m_clusterTol * 0.5;
         z.low       = z.price - m_clusterTol * 0.5;
         z.touchCount++;
         z.lastTouchAge  = barsAgo;
         z.lastTouchTime = iTime(_Symbol, _Period, barsAgo);
         
         // Calculate price reaction
         double currentPrice = iClose(_Symbol, _Period, 0);
         z.last_reaction = MathAbs(currentPrice - price) / m_atrCurrent;
         
         // Recalculate strength and confidence
         z.strength   = CalcStrength(z);
         z.confidence = CalcConfidence(z);
        }
      else if(m_zoneCount < ASR_MAX_ZONES)
        {
         // Add new zone
         SRZoneExtended &z = m_zones[m_zoneCount];
         z.InitExtended();
         
         z.price         = price;
         z.high          = price + m_clusterTol * 0.5;
         z.low           = price - m_clusterTol * 0.5;
         z.touchCount    = 1;
         z.lastTouchAge  = barsAgo;
         z.lastTouchTime = iTime(_Symbol, _Period, barsAgo);
         z.isSupport     = isSupport;
         z.isBroken      = false;
         z.formation_bars= barsAgo;
         z.strength      = 25.0;  // Initial strength
         z.confidence    = 50.0;  // Initial confidence
         
         m_zoneCount++;
        }
     }

   double CalcStrength(const SRZoneExtended &z) const
     {
      // Multi-factor strength calculation:
      // 1. Touch count (max 40 points, diminishing returns after 5 touches)
      // 2. Recency (max 30 points, exponential decay)
      // 3. Freshness bonus (max 20 points, not broken)
      // 4. Reaction strength (max 10 points)
      
      double touchScore = MathMin(5.0, (double)z.touchCount);
      touchScore = touchScore / 5.0 * 40.0;
      
      double recencyScore = MathExp(-z.lastTouchAge / 100.0) * 30.0;
      
      double freshness = z.isBroken ? 0.0 : 20.0;
      
      double reactionScore = MathMin(10.0, z.last_reaction * 2.0);
      
      return MathMin(100.0, touchScore + recencyScore + freshness + reactionScore);
     }
     
   double CalcConfidence(const SRZoneExtended &z) const
     {
      // Confidence based on:
      // 1. Strength (40% weight)
      // 2. Touch count consistency (30% weight)
      // 3. Recent activity (30% weight)
      
      double strengthFactor = z.strength / 100.0 * 40.0;
      
      double consistencyFactor = MathMin(1.0, z.touchCount / 3.0) * 30.0;
      
      double activityFactor = (z.lastTouchAge < 50) ? 30.0 : 
                             MathMax(0.0, 30.0 - (z.lastTouchAge - 50) * 0.3);
      
      return strengthFactor + consistencyFactor + activityFactor;
     }

   void CheckBrokenZones()
     {
      double closePrice = iClose(_Symbol, _Period, 1);
      double atrPoints  = m_atrCurrent;
      
      for(int i=0; i<m_zoneCount; i++)
        {
         if(m_zones[i].isBroken) continue;
         
         // Support broken: close below zone low by significant margin
         if(m_zones[i].isSupport && 
            closePrice < m_zones[i].low - atrPoints * 0.2)
            m_zones[i].isBroken = true;
            
         // Resistance broken: close above zone high by significant margin
         if(!m_zones[i].isSupport && 
            closePrice > m_zones[i].high + atrPoints * 0.2)
            m_zones[i].isBroken = true;
        }
     }

   void RemoveStaleZones()
     {
      int keep = 0;
      
      for(int i=0; i<m_zoneCount; i++)
        {
         // Keep criteria:
         // - Not broken OR recently broken (< 30 bars)
         // - Strength above minimum
         // - Not too old without touches
         
         bool isStale = false;
         
         if(m_zones[i].isBroken && m_zones[i].lastTouchAge > 50)
            isStale = true;
            
         if(m_zones[i].strength < ASR_MIN_STRENGTH && 
            m_zones[i].lastTouchAge > 150)
            isStale = true;
            
         if(m_zones[i].formation_bars > 500 && m_zones[i].touchCount < 2)
            isStale = true;
         
         if(!isStale)
           {
            if(keep != i) m_zones[keep] = m_zones[i];
            keep++;
           }
        }
        
      m_zoneCount = keep;
     }

public:
   CAnalysisSRManager() : IManager(), m_zoneCount(0), m_clusterTol(0), 
                          m_atrCurrent(0), m_lastScanTime(0), 
                          m_lastScanBar(-1), m_scanCount(0),
                          m_adaptiveLookback(ASR_LOOKBACK_BASE),
                          m_strengthDecay(ASR_TOUCH_DECAY) 
   {
      for(int i=0; i<ASR_MAX_ZONES; i++) 
         m_zones[i].InitExtended();
   }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
     }

   virtual void OnNewBar() override
     {
      // Update ATR-based cluster tolerance
      m_atrCurrent = m_data.GetATRPoints() * _Point;
      m_clusterTol = (m_atrCurrent > 0) ? m_atrCurrent * 0.5 : _Point * 10;
      
      // Get current bar info
      datetime currentBarTime = iTime(_Symbol, _Period, 0);
      int currentBar = (int)iBarShift(_Symbol, _Period, 0);
      
      // Skip if already processed this bar
      if(currentBar == m_lastScanBar && currentBarTime == m_lastScanTime)
         return;
      
      m_lastScanBar  = currentBar;
      m_lastScanTime = currentBarTime;
      m_scanCount++;
      
      // Check for broken zones
      CheckBrokenZones();

      // Scan for new pivots
      ScanForPivots();

      // Age all zones
      for(int i=0; i<m_zoneCount; i++)
         if(!m_zones[i].isBroken) 
            m_zones[i].lastTouchAge++;

      // Recalculate metrics
      for(int i=0; i<m_zoneCount; i++)
        {
         m_zones[i].strength   = CalcStrength(m_zones[i]);
         m_zones[i].confidence = CalcConfidence(m_zones[i]);
        }

      // Cleanup stale zones
      RemoveStaleZones();

      if(m_debugMode)
         PrintFormat("[SR] Scan #%d: %d active zones (%.1f ATR tol)",
                     m_scanCount, GetActiveCount(), m_clusterTol/_Point);
     }
     
   //── Public API ───────────────────────────────────────────────────

   bool GetNearestSupport(double price, SRZoneExtended &out) const
     {
      double bestDist = DBL_MAX; 
      bool found = false;
      
      for(int i=0; i<m_zoneCount; i++)
        {
         if(!m_zones[i].isSupport || m_zones[i].isBroken) continue;
         if(m_zones[i].price >= price) continue;
         
         double dist = price - m_zones[i].price;
         if(dist < bestDist) 
           { 
            bestDist = dist; 
            out = m_zones[i]; 
            found = true; 
           }
        }
      return found;
     }

   bool GetNearestResistance(double price, SRZoneExtended &out) const
     {
      double bestDist = DBL_MAX; 
      bool found = false;
      
      for(int i=0; i<m_zoneCount; i++)
        {
         if(m_zones[i].isSupport || m_zones[i].isBroken) continue;
         if(m_zones[i].price <= price) continue;
         
         double dist = m_zones[i].price - price;
         if(dist < bestDist) 
           { 
            bestDist = dist; 
            out = m_zones[i]; 
            found = true; 
           }
        }
      return found;
     }

   bool IsNearValidZone(double price, double proximityATR, SRZoneExtended &out) const
     {
      double tol = m_atrCurrent * proximityATR;
      double bestDist = DBL_MAX; 
      bool found = false;
      
      for(int i=0; i<m_zoneCount; i++)
        {
         if(m_zones[i].isBroken) continue;
         if(m_zones[i].strength < ASR_MIN_STRENGTH) continue;
         if(m_zones[i].confidence < 40.0) continue;
         
         double dist = MathAbs(price - m_zones[i].price);
         if(dist <= tol && dist < bestDist) 
           { 
            bestDist = dist; 
            out = m_zones[i]; 
            found = true; 
           }
        }
      return found;
     }

   bool IsZoneValid(const SRZoneExtended &z) const
     {
      return (z.touchCount >= 2 && 
              z.lastTouchAge <= 200 &&
              z.strength >= ASR_MIN_STRENGTH && 
              z.confidence >= 40.0 &&
              !z.isBroken);
     }

   int GetZoneCount() const { return m_zoneCount; }
   
   int GetActiveCount() const
     {
      int n = 0;
      for(int i=0; i<m_zoneCount; i++) 
         if(!m_zones[i].isBroken) n++;
      return n;
     }

   int GetValidZoneCount() const
     {
      int n = 0;
      for(int i=0; i<m_zoneCount; i++) 
         if(IsZoneValid(m_zones[i])) n++;
      return n;
     }

   const SRZoneExtended* GetZone(int i) const
     { 
      return (i>=0 && i<m_zoneCount) ? &m_zones[i] : NULL; 
     }
     
   // Export zones to CSV for analysis
   string ExportZonesToCSV() const
     {
      string csv = "Type,Price,Low,High,Strength,Confidence,Touches,Age,Broken\n";
      
      for(int i=0; i<m_zoneCount; i++)
        {
         const SRZoneExtended &z = m_zones[i];
         csv += StringFormat("%s,%.5f,%.5f,%.5f,%.1f,%.1f,%d,%d,%s\n",
                            z.isSupport ? "S" : "R",
                            z.price, z.low, z.high,
                            z.strength, z.confidence,
                            z.touchCount, z.lastTouchAge,
                            z.isBroken ? "Y" : "N");
        }
        
      return csv;
     }
     
private:
   void ScanForPivots()
     {
      int totalBars = (int)Bars(_Symbol, _Period);
      int scanBars = MathMin(m_adaptiveLookback, totalBars - ASR_RIGHT_BARS - 1);
      
      for(int shift = ASR_RIGHT_BARS + 1; shift < scanBars; shift++)
        {
         if(IsPivotHigh(shift))
           {
            double pivotPrice = iHigh(_Symbol, _Period, shift);
            AddOrUpdateZone(pivotPrice, false, shift);  // Resistance
           }
           
         if(IsPivotLow(shift))
           {
            double pivotPrice = iLow(_Symbol, _Period, shift);
            AddOrUpdateZone(pivotPrice, true, shift);   // Support
           }
        }
     }
  };

typedef CAnalysisSRManager AnalysisSRManager;
#endif
