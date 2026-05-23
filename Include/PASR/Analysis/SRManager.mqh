//+------------------------------------------------------------------+
//| Analysis/SRManager.mqh — v2.01 (ENHANCED WITH GITHUB FEATURES)   |
//| Swing pivot detection + zone clustering + strength scoring.       |
//|                                                                   |
//| OPTIMIZATIONS v2.00:                                              |
//|  - Enhanced pivot detection with adaptive lookback               |
//|  - Improved zone clustering algorithm                            |
//|  - Added zone confidence scoring                                 |
//|  - Better memory management and performance                      |
//|  - Integrated with unified regime detection                      |
//|                                                                   |
//| ENHANCEMENTS v2.01 (from GitHub):                                 |
//|  - IsBroken() with 2-close confirmation                          |
//|  - FindNearestSwing() with CopyHigh/CopyLow                      |
//|  - Dynamic buffer multiplier by touch count                      |
//|  - HTF Alignment integration                                     |
//|  - Touch count detection with ATR tolerance                      |
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
#define ASR_BREAKOUT_BARS   5      // Bars to check for breakout confirmation
#define ASR_BREAKOUT_CLOSES 2      // Required closes beyond zone for breakout

//+------------------------------------------------------------------+
//| HTF Alignment enum                                               |
//+------------------------------------------------------------------+
enum ENUM_HTF_ALIGNMENT
  {
   HTF_CONTRA = -1,      // Zone contra to HTF direction
   HTF_NEUTRAL = 0,      // No HTF alignment signal
   HTF_ALIGNED = 1       // Zone aligned with HTF direction
  };

//+------------------------------------------------------------------+
//| Extended SRZone with confidence scoring                          |
//+------------------------------------------------------------------+
struct SRZoneExtended : public SRZone
  {
   double confidence;        // Zone confidence score (0-100)
   int    formation_bars;    // Bars since zone formation
   double last_reaction;     // Price reaction magnitude at last touch
   double buffer_multiplier; // Dynamic buffer based on touch count
   ENUM_HTF_ALIGNMENT htf_alignment; // HTF alignment status
   
   void InitExtended()
     {
      Init();
      confidence       = 0.0;
      formation_bars   = 0;
      last_reaction    = 0.0;
      buffer_multiplier= 1.0;
      htf_alignment    = HTF_NEUTRAL;
     }
     
   string ToString() const
     {
      return StringFormat("SRZone[%.5f|%.5f|%s|Str=%.1f|Conf=%.1f|Touches=%d|HTF=%d]",
                         low, high, isSupport ? "SUP" : "RES", 
                         strength, confidence, touchCount, (int)htf_alignment);
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
   
   // HTF data cache
   ENUM_TIMEFRAMES m_htfPeriod;
   double          m_htf_atr;

   //── Enhanced IsBroken with 2-close confirmation ──────────────────
   
   bool IsBroken(const SRZoneExtended &z, int barsCount = ASR_BREAKOUT_BARS) const
     {
      if(z.isBroken) return true;
      
      double zoneLevel = z.isSupport ? z.low : z.high;
      int closesBeyond = 0;
      
      // Check for required number of closes beyond zone
      for(int i = 1; i <= barsCount && i < Bars(_Symbol, _Period); i++)
        {
         double closePrice = iClose(_Symbol, _Period, i);
         
         if(z.isSupport)
           {
            // Support broken: close below zone
            if(closePrice < zoneLevel - m_atrCurrent * 0.1)
               closesBeyond++;
           }
         else
           {
            // Resistance broken: close above zone
            if(closePrice > zoneLevel + m_atrCurrent * 0.1)
               closesBeyond++;
           }
        }
      
      // Require at least 2 closes beyond zone for confirmed breakout
      return (closesBeyond >= ASR_BREAKOUT_CLOSES);
     }

   //── FindNearestSwing with CopyHigh/CopyLow (MQL5 Best Practice) ─
   
   int FindNearestSwing(bool findHigh, int startBar, int maxBars) const
     {
      if(startBar < 0 || maxBars <= 0) return -1;
      
      int totalBars = (int)Bars(_Symbol, _Period);
      if(startBar >= totalBars) return -1;
      
      int scanLimit = MathMin(maxBars, totalBars - startBar - 1);
      if(scanLimit <= 0) return -1;
      
      // Use CopyHigh/CopyLow for better performance
      double highs[], lows[];
      ArraySetAsSeries(highs, true);
      ArraySetAsSeries(lows, true);
      
      if(CopyHigh(_Symbol, _Period, startBar, scanLimit, highs) != scanLimit)
         return -1;
      if(CopyLow(_Symbol, _Period, startBar, scanLimit, lows) != scanLimit)
         return -1;
      
      int swingBar = -1;
      double bestValue = findHigh ? 0.0 : DBL_MAX;
      
      // Skip first and last bars (need confirmation on both sides)
      for(int i = 1; i < scanLimit - 1; i++)
        {
         double currentValue = findHigh ? highs[i] : lows[i];
         
         // Check left side
         bool isSwing = true;
         for(int j = 1; j <= ASR_LEFT_BARS && (i - j) >= 0; j++)
           {
            double compareValue = findHigh ? highs[i - j] : lows[i - j];
            if(findHigh)
              {
               if(compareValue >= currentValue) { isSwing = false; break; }
              }
            else
              {
               if(compareValue <= currentValue) { isSwing = false; break; }
              }
           }
         
         if(!isSwing) continue;
         
         // Check right side
         for(int j = 1; j <= ASR_RIGHT_BARS && (i + j) < scanLimit; j++)
           {
            double compareValue = findHigh ? highs[i + j] : lows[i + j];
            if(findHigh)
              {
               if(compareValue >= currentValue) { isSwing = false; break; }
              }
            else
              {
               if(compareValue <= currentValue) { isSwing = false; break; }
              }
           }
         
         if(isSwing)
           {
            if(findHigh)
              {
               if(currentValue > bestValue)
                 {
                  bestValue = currentValue;
                  swingBar = startBar + i;
                 }
              }
            else
              {
               if(currentValue < bestValue)
                 {
                  bestValue = currentValue;
                  swingBar = startBar + i;
                 }
              }
           }
        }
      
      return swingBar;
     }

   //── Dynamic Buffer Multiplier based on Touch Count ───────────────
   
   double GetDynamicBufferMultiplier(int touchCount) const
     {
      // Stronger zones (more touches) get tighter buffers
      // This makes high-touch zones more precise for entries
      
      if(touchCount >= 5) return 0.7;   // Very strong: tight buffer
      if(touchCount >= 3) return 0.85;  // Strong: moderate buffer
      if(touchCount >= 2) return 1.0;   // Normal: standard buffer
      return 1.3;                       // Weak: wider buffer
     }

   //── HTF Alignment Check ──────────────────────────────────────────
   
   ENUM_HTF_ALIGNMENT CheckHTFAlignment(double price, bool isSupport) const
     {
      if(m_htfPeriod == PERIOD_CURRENT) return HTF_NEUTRAL;
      
      // Get HTF ATR
      double htf_atr = iATR(_Symbol, m_htfPeriod, 14, 1);
      if(htf_atr <= 0) return HTF_NEUTRAL;
      
      // Simple HTF trend detection using price position vs MA
      double htf_close = iClose(_Symbol, m_htfPeriod, 1);
      double htf_ma20 = iMA(_Symbol, m_htfPeriod, 20, 0, MODE_SMA, PRICE_CLOSE, 1);
      
      bool htf_uptrend = (htf_close > htf_ma20);
      bool htf_downtrend = (htf_close < htf_ma20);
      
      // Support zones are more valuable in uptrends
      // Resistance zones are more valuable in downtrends
      if(isSupport)
        {
         if(htf_uptrend) return HTF_ALIGNED;
         if(htf_downtrend) return HTF_CONTRA;
        }
      else
        {
         if(htf_downtrend) return HTF_ALIGNED;
         if(htf_uptrend) return HTF_CONTRA;
        }
      
      return HTF_NEUTRAL;
     }

   //── Touch Count Detection with ATR Tolerance ─────────────────────
   
   int DetectTouchCount(double price, int maxBars = 200) const
     {
      if(maxBars <= 0) return 0;
      
      int totalBars = (int)Bars(_Symbol, _Period);
      int scanLimit = MathMin(maxBars, totalBars);
      
      double tolerance = m_atrCurrent * 0.3;  // 0.3 ATR tolerance
      int touchCount = 0;
      
      for(int i = 0; i < scanLimit; i++)
        {
         double high = iHigh(_Symbol, _Period, i);
         double low = iLow(_Symbol, _Period, i);
         
         // Check if price touched the zone
         if(MathAbs(price - high) <= tolerance || 
            MathAbs(price - low) <= tolerance ||
            (price >= low && price <= high))
           {
            touchCount++;
           }
        }
      
      return touchCount;
     }

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
         
         // Apply dynamic buffer multiplier based on touch count
         z.buffer_multiplier = GetDynamicBufferMultiplier(z.touchCount + 1);
         double adjustedTol = m_clusterTol * z.buffer_multiplier;
         
         z.high      = z.price + adjustedTol * 0.5;
         z.low       = z.price - adjustedTol * 0.5;
         z.touchCount++;
         z.lastTouchAge  = barsAgo;
         z.lastTouchTime = iTime(_Symbol, _Period, barsAgo);
         
         // Calculate price reaction
         double currentPrice = iClose(_Symbol, _Period, 0);
         z.last_reaction = MathAbs(currentPrice - price) / m_atrCurrent;
         
         // Check HTF alignment
         z.htf_alignment = CheckHTFAlignment(price, isSupport);
         
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
         z.touchCount    = 1;
         
         // Apply dynamic buffer for new zones
         z.buffer_multiplier = GetDynamicBufferMultiplier(1);
         double adjustedTol = m_clusterTol * z.buffer_multiplier;
         
         z.high          = price + adjustedTol * 0.5;
         z.low           = price - adjustedTol * 0.5;
         z.lastTouchAge  = barsAgo;
         z.lastTouchTime = iTime(_Symbol, _Period, barsAgo);
         z.isSupport     = isSupport;
         z.isBroken      = false;
         z.formation_bars= barsAgo;
         z.strength      = 25.0;  // Initial strength
         z.confidence    = 50.0;  // Initial confidence
         
         // Check HTF alignment for new zone
         z.htf_alignment = CheckHTFAlignment(price, isSupport);
         
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
      // 5. HTF Alignment bonus (max 10 points)
      
      double touchScore = MathMin(5.0, (double)z.touchCount);
      touchScore = touchScore / 5.0 * 40.0;
      
      double recencyScore = MathExp(-z.lastTouchAge / 100.0) * 30.0;
      
      double freshness = z.isBroken ? 0.0 : 20.0;
      
      double reactionScore = MathMin(10.0, z.last_reaction * 2.0);
      
      // HTF Alignment bonus
      double htfBonus = 0.0;
      if(z.htf_alignment == HTF_ALIGNED) htfBonus = 10.0;
      else if(z.htf_alignment == HTF_CONTRA) htfBonus = -5.0;
      
      return MathMin(100.0, touchScore + recencyScore + freshness + reactionScore + htfBonus);
     }
     
   double CalcConfidence(const SRZoneExtended &z) const
     {
      // Confidence based on:
      // 1. Strength (35% weight)
      // 2. Touch count consistency (25% weight)
      // 3. Recent activity (25% weight)
      // 4. HTF Alignment (15% weight)
      
      double strengthFactor = z.strength / 100.0 * 35.0;
      
      double consistencyFactor = MathMin(1.0, z.touchCount / 3.0) * 25.0;
      
      double activityFactor = (z.lastTouchAge < 50) ? 25.0 : 
                             MathMax(0.0, 25.0 - (z.lastTouchAge - 50) * 0.3);
      
      // HTF Alignment factor
      double htfFactor = 0.0;
      if(z.htf_alignment == HTF_ALIGNED) htfFactor = 15.0;
      else if(z.htf_alignment == HTF_NEUTRAL) htfFactor = 7.5;
      // HTF_CONTRA gets 0
      
      return strengthFactor + consistencyFactor + activityFactor + htfFactor;
     }

   void CheckBrokenZones()
     {
      for(int i=0; i<m_zoneCount; i++)
        {
         if(m_zones[i].isBroken) continue;
         
         // Use enhanced IsBroken with 2-close confirmation
         if(IsBroken(m_zones[i], ASR_BREAKOUT_BARS))
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
                          m_strengthDecay(ASR_TOUCH_DECAY),
                          m_htfPeriod(PERIOD_CURRENT),
                          m_htf_atr(0)
   {
      for(int i=0; i<ASR_MAX_ZONES; i++) 
         m_zones[i].InitExtended();
   }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
     }

   //── HTF Configuration ────────────────────────────────────────────
   
   void SetHTFPeriod(ENUM_TIMEFRAMES htfPeriod)
     {
      m_htfPeriod = htfPeriod;
     }
     
   ENUM_TIMEFRAMES GetHTFPeriod() const
     {
      return m_htfPeriod;
     }

   virtual void OnNewBar() override
     {
      // Update ATR-based cluster tolerance
      m_atrCurrent = m_data.GetATRPoints() * _Point;
      m_clusterTol = (m_atrCurrent > 0) ? m_atrCurrent * 0.5 : _Point * 10;
      
      // Update HTF ATR if configured
      if(m_htfPeriod != PERIOD_CURRENT)
        {
         m_htf_atr = iATR(_Symbol, m_htfPeriod, 14, 1);
        }
      
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

      // Recalculate metrics including HTF alignment
      for(int i=0; i<m_zoneCount; i++)
        {
         // Re-check HTF alignment on each bar (trend can change)
         m_zones[i].htf_alignment = CheckHTFAlignment(m_zones[i].price, m_zones[i].isSupport);
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
     
   //── Enhanced API with HTF Alignment filtering ────────────────────
   
   bool GetNearestAlignedSupport(double price, SRZoneExtended &out) const
     {
      double bestDist = DBL_MAX; 
      bool found = false;
      
      for(int i=0; i<m_zoneCount; i++)
        {
         if(!m_zones[i].isSupport || m_zones[i].isBroken) continue;
         if(m_zones[i].price >= price) continue;
         if(m_zones[i].htf_alignment != HTF_ALIGNED) continue;  // Only aligned zones
         
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
     
   bool GetNearestAlignedResistance(double price, SRZoneExtended &out) const
     {
      double bestDist = DBL_MAX; 
      bool found = false;
      
      for(int i=0; i<m_zoneCount; i++)
        {
         if(m_zones[i].isSupport || m_zones[i].isBroken) continue;
         if(m_zones[i].price <= price) continue;
         if(m_zones[i].htf_alignment != HTF_ALIGNED) continue;  // Only aligned zones
         
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
     
   //── Enhanced IsNearValidZone with HTF alignment requirement ──────
   
   bool IsNearValidAlignedZone(double price, double proximityATR, SRZoneExtended &out) const
     {
      double tol = m_atrCurrent * proximityATR;
      double bestDist = DBL_MAX; 
      bool found = false;
      
      for(int i=0; i<m_zoneCount; i++)
        {
         if(m_zones[i].isBroken) continue;
         if(m_zones[i].strength < ASR_MIN_STRENGTH) continue;
         if(m_zones[i].confidence < 40.0) continue;
         if(m_zones[i].htf_alignment != HTF_ALIGNED) continue;  // Require alignment
         
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
     
   //── Enhanced validity check with HTF alignment ───────────────────
   
   bool IsZoneValidAligned(const SRZoneExtended &z) const
     {
      return (IsZoneValid(z) && z.htf_alignment == HTF_ALIGNED);
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
      string csv = "Type,Price,Low,High,Strength,Confidence,Touches,Age,Broken,HTFAlign,BufferMult\n";
      
      for(int i=0; i<m_zoneCount; i++)
        {
         const SRZoneExtended &z = m_zones[i];
         csv += StringFormat("%s,%.5f,%.5f,%.5f,%.1f,%.1f,%d,%d,%s,%d,%.2f\n",
                            z.isSupport ? "S" : "R",
                            z.price, z.low, z.high,
                            z.strength, z.confidence,
                            z.touchCount, z.lastTouchAge,
                            z.isBroken ? "Y" : "N",
                            (int)z.htf_alignment,
                            z.buffer_multiplier);
        }
        
      return csv;
     }
     
   //── Enhanced API: Get zones with HTF alignment ───────────────────
   
   int GetAlignedZoneCount() const
     {
      int n = 0;
      for(int i=0; i<m_zoneCount; i++)
        {
         if(!m_zones[i].isBroken && m_zones[i].htf_alignment == HTF_ALIGNED)
            n++;
        }
      return n;
     }
     
   // Get strongest zone (by strength score)
   bool GetStrongestZone(bool support, SRZoneExtended &out) const
     {
      double bestStrength = -1.0;
      bool found = false;
      
      for(int i=0; i<m_zoneCount; i++)
        {
         if(m_zones[i].isBroken) continue;
         if(support && !m_zones[i].isSupport) continue;
         if(!support && m_zones[i].isSupport) continue;
         
         if(m_zones[i].strength > bestStrength)
           {
            bestStrength = m_zones[i].strength;
            out = m_zones[i];
            found = true;
           }
        }
      return found;
     }
     
   // Get zone with highest touch count
   bool GetMostTouchedZone(bool support, SRZoneExtended &out) const
     {
      int bestTouches = -1;
      bool found = false;
      
      for(int i=0; i<m_zoneCount; i++)
        {
         if(m_zones[i].isBroken) continue;
         if(support && !m_zones[i].isSupport) continue;
         if(!support && m_zones[i].isSupport) continue;
         
         if(m_zones[i].touchCount > bestTouches)
           {
            bestTouches = m_zones[i].touchCount;
            out = m_zones[i];
            found = true;
           }
        }
      return found;
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
