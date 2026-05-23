//+------------------------------------------------------------------+
//| Analysis/SRZoneStore.mqh — v1.0.0                                |
//| Responsibility: ZONE STORAGE, CLUSTERING & LIFECYCLE             |
//|                                                                   |
//| Owns the canonical SRZoneExtended array and all mutating logic:  |
//|   - AddOrUpdate (cluster tolerance, weighted avg)                |
//|   - CheckBroken (2-close confirmation)                           |
//|   - MergeNearby (ATR-based deduplication)                        |
//|   - RemoveStale (age/strength cleanup)                            |
//|   - CalcStrength / CalcConfidence                                 |
//|   - Read API: GetNearest*, IsNearValid, GetZone                  |
//|                                                                   |
//| WHAT THIS FILE DOES NOT DO:                                       |
//|   - Does NOT extend IManager                                     |
//|   - Does NOT call AccountInfoDouble / TimeCurrent (wrong domain) |
//|   - Does NOT duplicate ENUM_MARKET_REGIME (use MarketRegimeDetector) |
//|   - Does NOT manage news, sessions, or equity (wrong domain)     |
//|                                                                   |
//| Owned by:  CAnalysisSRManager (SRManager.mqh)                    |
//+------------------------------------------------------------------+
#property strict
#ifndef __ANALYSIS_SR_ZONE_STORE_MQH__
#define __ANALYSIS_SR_ZONE_STORE_MQH__

#include "../Data/SRStruct.mqh"

//--- Storage limits & thresholds
#define SRZ_MAX_ZONES       60
#define SRZ_MIN_STRENGTH    15.0   // Minimum strength to keep a zone
#define SRZ_BREAKOUT_BARS   5      // Bars to scan for breakout confirmation
#define SRZ_BREAKOUT_CLOSES 2      // Required closes beyond zone level
#define SRZ_AGE_DECAY_START 100    // Bars before age decay kicks in
#define SRZ_AGE_DECAY_RATE  0.95   // Decay factor per 10 bars over start
#define SRZ_MERGE_ATR_MULT  0.3    // ATR multiplier for merge threshold

//+------------------------------------------------------------------+
//| HTF alignment tag — per zone                                     |
//+------------------------------------------------------------------+
enum ENUM_SR_HTF_ALIGNMENT
  {
   SR_HTF_CONTRA   = -1,
   SR_HTF_NEUTRAL  =  0,
   SR_HTF_ALIGNED  =  1
  };

//+------------------------------------------------------------------+
//| Extended zone with scoring metadata                              |
//+------------------------------------------------------------------+
struct SRZoneExtended : public SRZone
  {
   double               confidence;        // Composite confidence 0-100
   int                  formation_bars;    // Bars since first touch
   double               last_reaction;     // ATR-normalised reaction at last touch
   double               buffer_multiplier; // Touch-count adaptive buffer
   ENUM_SR_HTF_ALIGNMENT htf_alignment;    // HTF trend alignment tag
   double               age_decay_factor;  // Running decay multiplier
   bool                 is_merged_zone;    // Merged from 2+ nearby zones
   int                  merge_count;       // How many zones merged here

   void Init()
     {
      SRZone::Init();
      confidence        = 0.0;
      formation_bars    = 0;
      last_reaction     = 0.0;
      buffer_multiplier = 1.0;
      htf_alignment     = SR_HTF_NEUTRAL;
      age_decay_factor  = 1.0;
      is_merged_zone    = false;
      merge_count       = 1;
     }

   string ToString() const
     {
      return StringFormat(
         "SR[%.5f|%s|Str=%.1f|Conf=%.1f|T=%d|Age=%d|HTF=%d|Decay=%.2f|Merged=%d]",
         price,
         isSupport ? "SUP" : "RES",
         strength, confidence,
         touchCount, lastTouchAge,
         (int)htf_alignment,
         age_decay_factor,
         merge_count);
     }
  };

//+------------------------------------------------------------------+
//| CSRZoneStore — mutable zone container                            |
//+------------------------------------------------------------------+
class CSRZoneStore
  {
private:
   SRZoneExtended m_zones[SRZ_MAX_ZONES];
   int            m_count;
   double         m_atr;          // Current ATR (injected by SRManager)
   double         m_clusterTol;   // Cluster tolerance = atr * 0.5
   bool           m_debug;

   //-- Touch-count adaptive buffer multiplier
   double TouchBufferMult(int touches) const
     {
      if(touches >= 5) return 0.70;  // Very strong → tight buffer
      if(touches >= 3) return 0.85;  // Strong       → moderate
      if(touches >= 2) return 1.00;  // Normal
      return 1.30;                   // Weak          → wide buffer
     }

   //-- Volatility-adjusted buffer (uses injected ATR, no handle spam)
   double VolAdjBuffer(double base) const
     {
      // Use the injected m_atr directly instead of calling iATR repeatedly
      // This assumes m_atr is updated regularly by SRManager via UpdateATR()
      if(m_atr <= 0.0) return base;
      
      // Simple volatility adjustment based on current ATR level
      // In production, you might inject multiple ATR periods from manager
      double normalizedATR = m_atr / (_Point * 100); // Normalize to typical range
      if(normalizedATR > 1.2) return base * (1.0 + (normalizedATR - 1.2) * 0.5);
      if(normalizedATR < 0.8) return base * MathMax(0.5, 1.0 - (0.8 - normalizedATR) * 0.3);
      return base;
     }

   //-- Combined buffer multiplier
   double CombinedBuffer(int touches) const
     {
      return VolAdjBuffer(TouchBufferMult(touches));
     }

   //-- Find cluster index for price, -1 if no match
   int FindCluster(double price) const
     {
      for(int i = 0; i < m_count; i++)
         if(!m_zones[i].isBroken &&
            MathAbs(m_zones[i].price - price) <= m_clusterTol)
            return i;
      return -1;
     }

   //-- HTF trend alignment (simple MA20 position)
   ENUM_SR_HTF_ALIGNMENT CalcHTFAlignment(double price, bool isSupport,
                                           ENUM_TIMEFRAMES htfPeriod) const
     {
      if(htfPeriod == PERIOD_CURRENT) return SR_HTF_NEUTRAL;
      double cl   = iClose(_Symbol, htfPeriod, 1);
      double ma20 = iMA(_Symbol, htfPeriod, 20, 0, MODE_SMA, PRICE_CLOSE, 1);
      if(cl <= 0.0 || ma20 <= 0.0) return SR_HTF_NEUTRAL;
      bool uptrend = cl > ma20;
      if(isSupport)  return uptrend   ? SR_HTF_ALIGNED : SR_HTF_CONTRA;
      else           return !uptrend  ? SR_HTF_ALIGNED : SR_HTF_CONTRA;
     }

   //-- Compute zone strength (100-point composite)
   double CalcStrength(const SRZoneExtended &z) const
     {
      // Touch score    — 40 pts max, diminishing returns >5
      double touchScore   = MathMin(5.0, (double)z.touchCount) / 5.0 * 40.0;
      // Recency score  — 30 pts, exponential decay over 100 bars
      double recencyScore = MathExp(-z.lastTouchAge / 100.0) * 30.0;
      // Freshness      — 20 pts, zero if broken
      double freshness    = z.isBroken ? 0.0 : 20.0;
      // Reaction score — 10 pts
      double reactionScore= MathMin(10.0, z.last_reaction * 2.0);
      // HTF bonus
      double htfBonus = (z.htf_alignment == SR_HTF_ALIGNED) ?  10.0
                      : (z.htf_alignment == SR_HTF_CONTRA)  ?  -5.0
                      : 0.0;
      // Age decay
      double base = touchScore + recencyScore + freshness + reactionScore + htfBonus;
      return MathMin(100.0, MathMax(0.0, base * z.age_decay_factor));
     }

   //-- Compute confidence (100-point composite)
   double CalcConfidence(const SRZoneExtended &z) const
     {
      double sf = z.strength / 100.0 * 35.0;
      double cf = MathMin(1.0, z.touchCount / 3.0) * 25.0;
      double af = (z.lastTouchAge < 50)
                  ? 25.0
                  : MathMax(0.0, 25.0 - (z.lastTouchAge - 50) * 0.3);
      double hf = (z.htf_alignment == SR_HTF_ALIGNED) ? 15.0
                : (z.htf_alignment == SR_HTF_NEUTRAL)  ?  7.5
                : 0.0;
      return MathMin(100.0, MathMax(0.0, sf + cf + af + hf));
     }

public:
   CSRZoneStore()
      : m_count(0), m_atr(0.0), m_clusterTol(0.0), m_debug(false)
     {
      for(int i = 0; i < SRZ_MAX_ZONES; i++)
         m_zones[i].Init();
     }

   void SetDebug(bool d) { m_debug = d; }

   //-- MUST be called by SRManager before each scan cycle
   void UpdateATR(double atr)
     {
      m_atr        = atr;
      m_clusterTol = (atr > 0.0) ? atr * 0.5 : _Point * 10;
     }

   //+---------------------------------------------------------------+
   //| AddOrUpdate() — upsert pivot into zone array                  |
   //+---------------------------------------------------------------+
   void AddOrUpdate(double price, bool isSupport, int barsAgo,
                    ENUM_TIMEFRAMES htfPeriod = PERIOD_CURRENT)
     {
      int idx = FindCluster(price);

      if(idx >= 0)
        {
         // Weighted-average price update
         SRZoneExtended &z = m_zones[idx];
         double w = 1.0 / (double)(z.touchCount + 1);
         z.price      = z.price * (1.0 - w) + price * w;

         z.touchCount++;
         z.lastTouchAge  = barsAgo;
         z.lastTouchTime = iTime(_Symbol, _Period, barsAgo);
         z.last_reaction = MathAbs(iClose(_Symbol, _Period, 0) - price) / MathMax(m_atr, _Point);

         double bm = CombinedBuffer(z.touchCount);
         z.buffer_multiplier = bm;
         z.high = z.price + m_clusterTol * bm * 0.5;
         z.low  = z.price - m_clusterTol * bm * 0.5;

         z.htf_alignment = CalcHTFAlignment(z.price, z.isSupport, htfPeriod);
         z.strength   = CalcStrength(z);
         z.confidence = CalcConfidence(z);
        }
      else if(m_count < SRZ_MAX_ZONES)
        {
         SRZoneExtended &z = m_zones[m_count];
         z.Init();
         z.price          = price;
         z.touchCount     = 1;
         z.lastTouchAge   = barsAgo;
         z.lastTouchTime  = iTime(_Symbol, _Period, barsAgo);
         z.isSupport      = isSupport;
         z.isBroken       = false;
         z.formation_bars = barsAgo;
         z.strength       = 25.0;
         z.confidence     = 50.0;

         double bm = CombinedBuffer(1);
         z.buffer_multiplier = bm;
         z.high = price + m_clusterTol * bm * 0.5;
         z.low  = price - m_clusterTol * bm * 0.5;

         z.htf_alignment = CalcHTFAlignment(price, isSupport, htfPeriod);
         m_count++;
        }
     }

   //+---------------------------------------------------------------+
   //| CheckBroken() — mark zones with 2-close confirmation broken   |
   //+---------------------------------------------------------------+
   void CheckBroken()
     {
      for(int i = 0; i < m_count; i++)
        {
         if(m_zones[i].isBroken) continue;
         double level = m_zones[i].isSupport ? m_zones[i].low : m_zones[i].high;
         int    closes = 0;

         for(int b = 1; b <= SRZ_BREAKOUT_BARS && b < Bars(_Symbol, _Period); b++)
           {
            double cl = iClose(_Symbol, _Period, b);
            if(m_zones[i].isSupport)
              { if(cl < level - m_atr * 0.1) closes++; }
            else
              { if(cl > level + m_atr * 0.1) closes++; }
           }

         if(closes >= SRZ_BREAKOUT_CLOSES)
            m_zones[i].isBroken = true;
        }
     }

   //+---------------------------------------------------------------+
   //| AgeAndRefresh() — increment age, refresh decay + scoring      |
   //+---------------------------------------------------------------+
   void AgeAndRefresh(ENUM_TIMEFRAMES htfPeriod = PERIOD_CURRENT)
     {
      for(int i = 0; i < m_count; i++)
        {
         if(m_zones[i].isBroken) continue;

         m_zones[i].formation_bars++;
         m_zones[i].lastTouchAge++;

         // Age decay factor
         int excess = m_zones[i].formation_bars - SRZ_AGE_DECAY_START;
         m_zones[i].age_decay_factor = (excess > 0)
            ? MathPow(SRZ_AGE_DECAY_RATE, excess / 10.0)
            : 1.0;

         // Refresh HTF alignment (trend can change)
         m_zones[i].htf_alignment = CalcHTFAlignment(
            m_zones[i].price, m_zones[i].isSupport, htfPeriod);

         m_zones[i].strength   = CalcStrength(m_zones[i]);
         m_zones[i].confidence = CalcConfidence(m_zones[i]);
        }
     }

   //+---------------------------------------------------------------+
   //| MergeNearby() — collapse zones within ATR*MERGE_ATR_MULT      |
   //+---------------------------------------------------------------+
   void MergeNearby()
     {
      if(m_count < 2) return;
      double threshold = m_atr * SRZ_MERGE_ATR_MULT;
      int    merged    = 0;

      for(int i = 0; i < m_count; i++)
        {
         if(m_zones[i].isBroken) continue;

         for(int j = i + 1; j < m_count; j++)
           {
            if(m_zones[j].isBroken) continue;
            if(m_zones[i].isSupport != m_zones[j].isSupport) continue;
            if(MathAbs(m_zones[i].price - m_zones[j].price) > threshold) continue;

            // Strength-weighted merge i ← j
            double total = m_zones[i].strength + m_zones[j].strength;
            double wi    = (total > 0) ? m_zones[i].strength / total : 0.5;

            m_zones[i].price        = m_zones[i].price * wi + m_zones[j].price * (1.0 - wi);
            m_zones[i].touchCount  += m_zones[j].touchCount;
            m_zones[i].formation_bars = MathMin(m_zones[i].formation_bars, m_zones[j].formation_bars);
            m_zones[i].lastTouchAge   = MathMin(m_zones[i].lastTouchAge,   m_zones[j].lastTouchAge);
            m_zones[i].lastTouchTime  = MathMax(m_zones[i].lastTouchTime,  m_zones[j].lastTouchTime);
            m_zones[i].is_merged_zone = true;
            m_zones[i].merge_count++;

            double bm = CombinedBuffer(m_zones[i].touchCount);
            m_zones[i].buffer_multiplier = bm;
            m_zones[i].high = m_zones[i].price + m_clusterTol * bm * 0.5;
            m_zones[i].low  = m_zones[i].price - m_clusterTol * bm * 0.5;

            m_zones[j].isBroken = true;  // Mark j for removal
            merged++;
           }
        }

      if(merged > 0) RemoveStale();

      if(m_debug && merged > 0)
         PrintFormat("[SRStore] Merged %d zone pairs", merged);
     }

   //+---------------------------------------------------------------+
   //| RemoveStale() — compact array, drop dead zones                |
   //+---------------------------------------------------------------+
   void RemoveStale()
     {
      int keep = 0;

      for(int i = 0; i < m_count; i++)
        {
         const SRZoneExtended &z = m_zones[i];
         bool stale = false;

         if(z.isBroken && z.lastTouchAge > 50)                         stale = true;
         if(z.strength < SRZ_MIN_STRENGTH && z.lastTouchAge > 150)     stale = true;
         if(z.formation_bars > 500 && z.touchCount < 2)                stale = true;
         if(z.age_decay_factor < 0.5 && z.strength < 30.0)             stale = true;

         if(!stale)
           {
            if(keep != i) m_zones[keep] = m_zones[i];
            keep++;
           }
        }

      m_count = keep;
     }

   //== READ API ====================================================+

   bool GetNearestSupport(double price, SRZoneExtended &out) const
     {
      double best = DBL_MAX; bool found = false;
      for(int i = 0; i < m_count; i++)
        {
         if(!m_zones[i].isSupport || m_zones[i].isBroken) continue;
         if(m_zones[i].price >= price) continue;
         double d = price - m_zones[i].price;
         if(d < best) { best = d; out = m_zones[i]; found = true; }
        }
      return found;
     }

   bool GetNearestResistance(double price, SRZoneExtended &out) const
     {
      double best = DBL_MAX; bool found = false;
      for(int i = 0; i < m_count; i++)
        {
         if(m_zones[i].isSupport || m_zones[i].isBroken) continue;
         if(m_zones[i].price <= price) continue;
         double d = m_zones[i].price - price;
         if(d < best) { best = d; out = m_zones[i]; found = true; }
        }
      return found;
     }

   bool IsNearValidZone(double price, double atrMult, SRZoneExtended &out) const
     {
      double tol  = m_atr * atrMult;
      double best = DBL_MAX; bool found = false;

      for(int i = 0; i < m_count; i++)
        {
         if(m_zones[i].isBroken) continue;
         if(m_zones[i].strength   < SRZ_MIN_STRENGTH) continue;
         if(m_zones[i].confidence < 40.0)             continue;
         double d = MathAbs(price - m_zones[i].price);
         if(d <= tol && d < best) { best = d; out = m_zones[i]; found = true; }
        }
      return found;
     }

   bool IsZoneValid(const SRZoneExtended &z) const
     {
      return (!z.isBroken
              && z.touchCount   >= 2
              && z.lastTouchAge <= 200
              && z.strength     >= SRZ_MIN_STRENGTH
              && z.confidence   >= 40.0);
     }

   const SRZoneExtended *GetZone(int i) const
     {
      return (i >= 0 && i < m_count) ? &m_zones[i] : NULL;
     }

   int  GetCount()      const { return m_count; }
   double GetATR()      const { return m_atr; }
   double GetClusterTol() const { return m_clusterTol; }

   int GetActiveCount() const
     {
      int n = 0;
      for(int i = 0; i < m_count; i++)
         if(!m_zones[i].isBroken) n++;
      return n;
     }

   int GetValidCount() const
     {
      int n = 0;
      for(int i = 0; i < m_count; i++)
         if(IsZoneValid(m_zones[i])) n++;
      return n;
     }
  };

#endif // __ANALYSIS_SR_ZONE_STORE_MQH__
