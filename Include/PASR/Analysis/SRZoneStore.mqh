//+------------------------------------------------------------------+
//| Analysis/SRZoneStore.mqh — v1.1.0                                |
//| Responsibility: ZONE STORAGE, CLUSTERING & LIFECYCLE             |
//| Optimized with sorted support/resistance price indexes.          |
//+------------------------------------------------------------------+
#property strict
#ifndef __ANALYSIS_SR_ZONE_STORE_MQH__
#define __ANALYSIS_SR_ZONE_STORE_MQH__

#include "../Data/SRStruct.mqh"

#define SRZ_MAX_ZONES       60
#define SRZ_MIN_STRENGTH    15.0
#define SRZ_BREAKOUT_BARS   5
#define SRZ_BREAKOUT_CLOSES 2
#define SRZ_AGE_DECAY_START 100
#define SRZ_AGE_DECAY_RATE  0.95
#define SRZ_MERGE_ATR_MULT  0.3

enum ENUM_SR_HTF_ALIGNMENT
  {
   SR_HTF_CONTRA   = -1,
   SR_HTF_NEUTRAL  =  0,
   SR_HTF_ALIGNED  =  1
  };

struct SRZoneExtended : public SRZone
  {
   double                confidence;
   int                   formation_bars;
   double                last_reaction;
   double                buffer_multiplier;
   ENUM_SR_HTF_ALIGNMENT htf_alignment;
   double                age_decay_factor;
   bool                  is_merged_zone;
   int                   merge_count;

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
      return StringFormat("SR[%.5f|%s|Str=%.1f|Conf=%.1f|T=%d|Age=%d|HTF=%d|Decay=%.2f|Merged=%d]",
                          price,
                          isSupport ? "SUP" : "RES",
                          strength, confidence,
                          touchCount, lastTouchAge,
                          (int)htf_alignment,
                          age_decay_factor,
                          merge_count);
     }
  };

class CSRZoneStore
  {
private:
   SRZoneExtended m_zones[SRZ_MAX_ZONES];
   int            m_count;
   double         m_atr;
   double         m_clusterTol;
   bool           m_debug;

   int            m_supportIdx[SRZ_MAX_ZONES];
   int            m_supportCount;
   int            m_resistanceIdx[SRZ_MAX_ZONES];
   int            m_resistanceCount;

   bool IsIndexableZone(const SRZoneExtended &z) const
     {
      return (!z.isBroken && z.strength >= SRZ_MIN_STRENGTH);
     }

   void ClearIndexes()
     {
      m_supportCount = 0;
      m_resistanceCount = 0;
      for(int i=0; i<SRZ_MAX_ZONES; i++)
        {
         m_supportIdx[i] = -1;
         m_resistanceIdx[i] = -1;
        }
     }

   void InsertSortedIndex(int &arr[], int &cnt, int zoneIdx)
     {
      if(cnt >= SRZ_MAX_ZONES || zoneIdx < 0 || zoneIdx >= m_count) return;
      double price = m_zones[zoneIdx].price;
      int pos = cnt;
      while(pos > 0 && m_zones[arr[pos-1]].price > price)
        {
         arr[pos] = arr[pos-1];
         pos--;
        }
      arr[pos] = zoneIdx;
      cnt++;
     }

   void RebuildIndexes()
     {
      ClearIndexes();
      for(int i=0; i<m_count; i++)
        {
         if(!IsIndexableZone(m_zones[i])) continue;
         if(m_zones[i].isSupport)
            InsertSortedIndex(m_supportIdx, m_supportCount, i);
         else
            InsertSortedIndex(m_resistanceIdx, m_resistanceCount, i);
        }
     }

   int LowerBoundByPrice(const int &arr[], int cnt, double price) const
     {
      int lo = 0, hi = cnt;
      while(lo < hi)
        {
         int mid = (lo + hi) / 2;
         if(m_zones[arr[mid]].price < price) lo = mid + 1;
         else hi = mid;
        }
      return lo;
     }

   double TouchBufferMult(int touches) const
     {
      if(touches >= 5) return 0.70;
      if(touches >= 3) return 0.85;
      if(touches >= 2) return 1.00;
      return 1.30;
     }

   double VolAdjBuffer(double base) const
     {
      if(m_atr <= 0.0) return base;
      double normalizedATR = m_atr / (_Point * 100.0);
      if(normalizedATR > 1.2) return base * (1.0 + (normalizedATR - 1.2) * 0.5);
      if(normalizedATR < 0.8) return base * MathMax(0.5, 1.0 - (0.8 - normalizedATR) * 0.3);
      return base;
     }

   double CombinedBuffer(int touches) const
     {
      return VolAdjBuffer(TouchBufferMult(touches));
     }

   int FindCluster(double price) const
     {
      for(int i = 0; i < m_count; i++)
         if(!m_zones[i].isBroken && MathAbs(m_zones[i].price - price) <= m_clusterTol)
            return i;
      return -1;
     }

   bool ReadMAValue(const string symbol, ENUM_TIMEFRAMES tf, int period, ENUM_MA_METHOD method,
                    ENUM_APPLIED_PRICE appliedPrice, int shift, double &value) const
     {
      value = 0.0;
      int handle = iMA(symbol, tf, period, 0, method, appliedPrice);
      if(handle == INVALID_HANDLE) return false;
      double buf[1];
      bool ok = (CopyBuffer(handle, 0, shift, 1, buf) == 1);
      IndicatorRelease(handle);
      if(!ok) return false;
      value = buf[0];
      return value > 0.0;
     }

   ENUM_SR_HTF_ALIGNMENT CalcHTFAlignment(double price, bool isSupport,
                                           ENUM_TIMEFRAMES htfPeriod) const
     {
      if(htfPeriod == PERIOD_CURRENT) return SR_HTF_NEUTRAL;
      double cl = iClose(_Symbol, htfPeriod, 1);
      double ma20 = 0.0;
      if(!ReadMAValue(_Symbol, htfPeriod, 20, MODE_SMA, PRICE_CLOSE, 1, ma20))
         return SR_HTF_NEUTRAL;
      if(cl <= 0.0 || ma20 <= 0.0) return SR_HTF_NEUTRAL;
      bool uptrend = cl > ma20;
      if(isSupport) return uptrend ? SR_HTF_ALIGNED : SR_HTF_CONTRA;
      return !uptrend ? SR_HTF_ALIGNED : SR_HTF_CONTRA;
     }

   double CalcStrength(const SRZoneExtended &z) const
     {
      double touchScore = MathMin(5.0, (double)z.touchCount) / 5.0 * 40.0;
      double recencyScore = MathExp(-z.lastTouchAge / 100.0) * 30.0;
      double freshness = z.isBroken ? 0.0 : 20.0;
      double reactionScore = MathMin(10.0, z.last_reaction * 2.0);
      double htfBonus = (z.htf_alignment == SR_HTF_ALIGNED) ? 10.0
                      : (z.htf_alignment == SR_HTF_CONTRA) ? -5.0 : 0.0;
      return MathMin(100.0, MathMax(0.0,
                     (touchScore + recencyScore + freshness + reactionScore + htfBonus) * z.age_decay_factor));
     }

   double CalcConfidence(const SRZoneExtended &z) const
     {
      double sf = z.strength / 100.0 * 35.0;
      double cf = MathMin(1.0, z.touchCount / 3.0) * 25.0;
      double af = (z.lastTouchAge < 50) ? 25.0 : MathMax(0.0, 25.0 - (z.lastTouchAge - 50) * 0.3);
      double hf = (z.htf_alignment == SR_HTF_ALIGNED) ? 15.0
                : (z.htf_alignment == SR_HTF_NEUTRAL) ? 7.5 : 0.0;
      return MathMin(100.0, MathMax(0.0, sf + cf + af + hf));
     }

public:
   CSRZoneStore() : m_count(0), m_atr(0.0), m_clusterTol(0.0), m_debug(false),
                    m_supportCount(0), m_resistanceCount(0)
     {
      for(int i = 0; i < SRZ_MAX_ZONES; i++) m_zones[i].Init();
      ClearIndexes();
     }

   void SetDebug(bool d) { m_debug = d; }

   void UpdateATR(double atr)
     {
      m_atr = atr;
      m_clusterTol = (atr > 0.0) ? atr * 0.5 : _Point * 10.0;
     }

   void AddOrUpdate(double price, bool isSupport, int barsAgo,
                    ENUM_TIMEFRAMES htfPeriod = PERIOD_CURRENT)
     {
      int idx = FindCluster(price);
      if(idx >= 0)
        {
         SRZoneExtended &z = m_zones[idx];
         double w = 1.0 / (double)(z.touchCount + 1);
         z.price = z.price * (1.0 - w) + price * w;
         z.touchCount++;
         z.lastTouchAge = barsAgo;
         z.lastTouchTime = iTime(_Symbol, _Period, barsAgo);
         z.last_reaction = MathAbs(iClose(_Symbol, _Period, 1) - price) / MathMax(m_atr, _Point);
         double bm = CombinedBuffer(z.touchCount);
         z.buffer_multiplier = bm;
         z.high = z.price + m_clusterTol * bm * 0.5;
         z.low  = z.price - m_clusterTol * bm * 0.5;
         z.htf_alignment = CalcHTFAlignment(z.price, z.isSupport, htfPeriod);
         z.strength = CalcStrength(z);
         z.confidence = CalcConfidence(z);
        }
      else if(m_count < SRZ_MAX_ZONES)
        {
         SRZoneExtended &z = m_zones[m_count];
         z.Init();
         z.price = price;
         z.touchCount = 1;
         z.lastTouchAge = barsAgo;
         z.lastTouchTime = iTime(_Symbol, _Period, barsAgo);
         z.isSupport = isSupport;
         z.isBroken = false;
         z.formation_bars = barsAgo;
         z.strength = 25.0;
         z.confidence = 50.0;
         double bm = CombinedBuffer(1);
         z.buffer_multiplier = bm;
         z.high = price + m_clusterTol * bm * 0.5;
         z.low  = price - m_clusterTol * bm * 0.5;
         z.htf_alignment = CalcHTFAlignment(price, isSupport, htfPeriod);
         m_count++;
        }
      RebuildIndexes();
     }

   void CheckBroken()
     {
      bool changed = false;
      int bars = Bars(_Symbol, _Period);
      for(int i = 0; i < m_count; i++)
        {
         if(m_zones[i].isBroken) continue;
         double level = m_zones[i].isSupport ? m_zones[i].low : m_zones[i].high;
         int closes = 0;
         for(int b = 1; b <= SRZ_BREAKOUT_BARS && b < bars; b++)
           {
            double cl = iClose(_Symbol, _Period, b);
            if(m_zones[i].isSupport)
              { if(cl < level - m_atr * 0.1) closes++; }
            else
              { if(cl > level + m_atr * 0.1) closes++; }
           }
         if(closes >= SRZ_BREAKOUT_CLOSES)
           {
            m_zones[i].isBroken = true;
            changed = true;
           }
        }
      if(changed) RebuildIndexes();
     }

   void AgeAndRefresh(ENUM_TIMEFRAMES htfPeriod = PERIOD_CURRENT)
     {
      bool changed = false;
      for(int i = 0; i < m_count; i++)
        {
         if(m_zones[i].isBroken) continue;
         double oldStrength = m_zones[i].strength;
         m_zones[i].formation_bars++;
         m_zones[i].lastTouchAge++;
         int excess = m_zones[i].formation_bars - SRZ_AGE_DECAY_START;
         m_zones[i].age_decay_factor = (excess > 0) ? MathPow(SRZ_AGE_DECAY_RATE, excess / 10.0) : 1.0;
         m_zones[i].htf_alignment = CalcHTFAlignment(m_zones[i].price, m_zones[i].isSupport, htfPeriod);
         m_zones[i].strength = CalcStrength(m_zones[i]);
         m_zones[i].confidence = CalcConfidence(m_zones[i]);
         if((oldStrength >= SRZ_MIN_STRENGTH) != (m_zones[i].strength >= SRZ_MIN_STRENGTH)) changed = true;
        }
      if(changed) RebuildIndexes();
     }

   void MergeNearby()
     {
      if(m_count < 2) return;
      double threshold = m_atr * SRZ_MERGE_ATR_MULT;
      int merged = 0;
      for(int i = 0; i < m_count; i++)
        {
         if(m_zones[i].isBroken) continue;
         for(int j = i + 1; j < m_count; j++)
           {
            if(m_zones[j].isBroken) continue;
            if(m_zones[i].isSupport != m_zones[j].isSupport) continue;
            if(MathAbs(m_zones[i].price - m_zones[j].price) > threshold) continue;
            double total = m_zones[i].strength + m_zones[j].strength;
            double wi = (total > 0.0) ? m_zones[i].strength / total : 0.5;
            m_zones[i].price = m_zones[i].price * wi + m_zones[j].price * (1.0 - wi);
            m_zones[i].touchCount += m_zones[j].touchCount;
            m_zones[i].formation_bars = MathMin(m_zones[i].formation_bars, m_zones[j].formation_bars);
            m_zones[i].lastTouchAge = MathMin(m_zones[i].lastTouchAge, m_zones[j].lastTouchAge);
            m_zones[i].lastTouchTime = MathMax(m_zones[i].lastTouchTime, m_zones[j].lastTouchTime);
            m_zones[i].is_merged_zone = true;
            m_zones[i].merge_count++;
            double bm = CombinedBuffer(m_zones[i].touchCount);
            m_zones[i].buffer_multiplier = bm;
            m_zones[i].high = m_zones[i].price + m_clusterTol * bm * 0.5;
            m_zones[i].low  = m_zones[i].price - m_clusterTol * bm * 0.5;
            m_zones[j].isBroken = true;
            merged++;
           }
        }
      if(merged > 0) RemoveStale();
      else RebuildIndexes();
      if(m_debug && merged > 0) PrintFormat("[SRStore] Merged %d zone pairs", merged);
     }

   void RemoveStale()
     {
      int keep = 0;
      for(int i = 0; i < m_count; i++)
        {
         const SRZoneExtended &z = m_zones[i];
         bool stale = false;
         if(z.isBroken && z.lastTouchAge > 50) stale = true;
         if(z.strength < SRZ_MIN_STRENGTH && z.lastTouchAge > 150) stale = true;
         if(z.formation_bars > 500 && z.touchCount < 2) stale = true;
         if(z.age_decay_factor < 0.5 && z.strength < 30.0) stale = true;
         if(!stale)
           {
            if(keep != i) m_zones[keep] = m_zones[i];
            keep++;
           }
        }
      m_count = keep;
      RebuildIndexes();
     }

   bool GetNearestSupport(double price, SRZoneExtended &out) const
     {
      int pos = LowerBoundByPrice(m_supportIdx, m_supportCount, price) - 1;
      while(pos >= 0)
        {
         int idx = m_supportIdx[pos];
         if(idx >= 0 && idx < m_count && m_zones[idx].isSupport && !m_zones[idx].isBroken && m_zones[idx].price < price)
           { out = m_zones[idx]; return true; }
         pos--;
        }
      return false;
     }

   bool GetNearestResistance(double price, SRZoneExtended &out) const
     {
      int pos = LowerBoundByPrice(m_resistanceIdx, m_resistanceCount, price);
      while(pos < m_resistanceCount)
        {
         int idx = m_resistanceIdx[pos];
         if(idx >= 0 && idx < m_count && !m_zones[idx].isSupport && !m_zones[idx].isBroken && m_zones[idx].price > price)
           { out = m_zones[idx]; return true; }
         pos++;
        }
      return false;
     }

   bool IsNearValidZone(double price, double atrMult, SRZoneExtended &out) const
     {
      double tol = m_atr * atrMult;
      double best = DBL_MAX;
      bool found = false;

      int sPos = LowerBoundByPrice(m_supportIdx, m_supportCount, price - tol);
      for(int p=sPos; p<m_supportCount; p++)
        {
         int idx = m_supportIdx[p];
         if(idx < 0 || idx >= m_count) continue;
         double zp = m_zones[idx].price;
         if(zp > price + tol) break;
         if(m_zones[idx].confidence < 40.0) continue;
         double d = MathAbs(price - zp);
         if(d <= tol && d < best) { best = d; out = m_zones[idx]; found = true; }
        }

      int rPos = LowerBoundByPrice(m_resistanceIdx, m_resistanceCount, price - tol);
      for(int p=rPos; p<m_resistanceCount; p++)
        {
         int idx = m_resistanceIdx[p];
         if(idx < 0 || idx >= m_count) continue;
         double zp = m_zones[idx].price;
         if(zp > price + tol) break;
         if(m_zones[idx].confidence < 40.0) continue;
         double d = MathAbs(price - zp);
         if(d <= tol && d < best) { best = d; out = m_zones[idx]; found = true; }
        }
      return found;
     }

   bool IsZoneValid(const SRZoneExtended &z) const
     {
      return (!z.isBroken && z.touchCount >= 2 && z.lastTouchAge <= 200 &&
              z.strength >= SRZ_MIN_STRENGTH && z.confidence >= 40.0);
     }

   const SRZoneExtended *GetZone(int i) const
     {
      return (i >= 0 && i < m_count) ? &m_zones[i] : NULL;
     }

   int GetCount() const { return m_count; }
   double GetATR() const { return m_atr; }
   double GetClusterTol() const { return m_clusterTol; }
   int GetSupportIndexCount() const { return m_supportCount; }
   int GetResistanceIndexCount() const { return m_resistanceCount; }

   int GetActiveCount() const
     {
      int n = 0;
      for(int i = 0; i < m_count; i++) if(!m_zones[i].isBroken) n++;
      return n;
     }

   int GetValidCount() const
     {
      int n = 0;
      for(int i = 0; i < m_count; i++) if(IsZoneValid(m_zones[i])) n++;
      return n;
     }

   void Clear()
     {
      m_count = 0;
      m_atr = 0.0;
      m_clusterTol = 0.0;
      for(int i = 0; i < SRZ_MAX_ZONES; i++) m_zones[i].Init();
      ClearIndexes();
     }

   bool IsValid() const
     {
      return (m_count >= 0 && m_count <= SRZ_MAX_ZONES &&
              m_supportCount >= 0 && m_supportCount <= SRZ_MAX_ZONES &&
              m_resistanceCount >= 0 && m_resistanceCount <= SRZ_MAX_ZONES);
     }
  };

#endif // __ANALYSIS_SR_ZONE_STORE_MQH__