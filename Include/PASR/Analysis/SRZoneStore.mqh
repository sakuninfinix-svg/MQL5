//+------------------------------------------------------------------+
//| Analysis/SRZoneStore.mqh - v1.1.1                                |
//| SR zone storage with MQL5-safe sorted support/resistance indexes  |
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
                          price, isSupport ? "SUP" : "RES", strength, confidence,
                          touchCount, lastTouchAge, (int)htf_alignment,
                          age_decay_factor, merge_count);
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

   bool IsIndexableZone(const int idx) const
     {
      if(idx < 0 || idx >= m_count) return false;
      return (!m_zones[idx].isBroken && m_zones[idx].strength >= SRZ_MIN_STRENGTH);
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

   void InsertSupportIndex(int zoneIdx)
     {
      if(m_supportCount >= SRZ_MAX_ZONES || zoneIdx < 0 || zoneIdx >= m_count) return;
      double p = m_zones[zoneIdx].price;
      int pos = m_supportCount;
      while(pos > 0 && m_zones[m_supportIdx[pos-1]].price > p)
        {
         m_supportIdx[pos] = m_supportIdx[pos-1];
         pos--;
        }
      m_supportIdx[pos] = zoneIdx;
      m_supportCount++;
     }

   void InsertResistanceIndex(int zoneIdx)
     {
      if(m_resistanceCount >= SRZ_MAX_ZONES || zoneIdx < 0 || zoneIdx >= m_count) return;
      double p = m_zones[zoneIdx].price;
      int pos = m_resistanceCount;
      while(pos > 0 && m_zones[m_resistanceIdx[pos-1]].price > p)
        {
         m_resistanceIdx[pos] = m_resistanceIdx[pos-1];
         pos--;
        }
      m_resistanceIdx[pos] = zoneIdx;
      m_resistanceCount++;
     }

   void RebuildIndexes()
     {
      ClearIndexes();
      for(int i=0; i<m_count; i++)
        {
         if(!IsIndexableZone(i)) continue;
         if(m_zones[i].isSupport) InsertSupportIndex(i);
         else InsertResistanceIndex(i);
        }
     }

   int LowerBoundSupport(double price) const
     {
      int lo = 0, hi = m_supportCount;
      while(lo < hi)
        {
         int mid = (lo + hi) / 2;
         if(m_zones[m_supportIdx[mid]].price < price) lo = mid + 1;
         else hi = mid;
        }
      return lo;
     }

   int LowerBoundResistance(double price) const
     {
      int lo = 0, hi = m_resistanceCount;
      while(lo < hi)
        {
         int mid = (lo + hi) / 2;
         if(m_zones[m_resistanceIdx[mid]].price < price) lo = mid + 1;
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

   double CombinedBuffer(int touches) const { return VolAdjBuffer(TouchBufferMult(touches)); }

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

   double CalcStrengthAt(int idx) const
     {
      if(idx < 0 || idx >= m_count) return 0.0;
      double touchScore = MathMin(5.0, (double)m_zones[idx].touchCount) / 5.0 * 40.0;
      double recencyScore = MathExp(-m_zones[idx].lastTouchAge / 100.0) * 30.0;
      double freshness = m_zones[idx].isBroken ? 0.0 : 20.0;
      double reactionScore = MathMin(10.0, m_zones[idx].last_reaction * 2.0);
      double htfBonus = (m_zones[idx].htf_alignment == SR_HTF_ALIGNED) ? 10.0
                      : (m_zones[idx].htf_alignment == SR_HTF_CONTRA) ? -5.0 : 0.0;
      return MathMin(100.0, MathMax(0.0,
                     (touchScore + recencyScore + freshness + reactionScore + htfBonus) * m_zones[idx].age_decay_factor));
     }

   double CalcConfidenceAt(int idx) const
     {
      if(idx < 0 || idx >= m_count) return 0.0;
      double sf = m_zones[idx].strength / 100.0 * 35.0;
      double cf = MathMin(1.0, m_zones[idx].touchCount / 3.0) * 25.0;
      double af = (m_zones[idx].lastTouchAge < 50) ? 25.0 : MathMax(0.0, 25.0 - (m_zones[idx].lastTouchAge - 50) * 0.3);
      double hf = (m_zones[idx].htf_alignment == SR_HTF_ALIGNED) ? 15.0
                : (m_zones[idx].htf_alignment == SR_HTF_NEUTRAL) ? 7.5 : 0.0;
      return MathMin(100.0, MathMax(0.0, sf + cf + af + hf));
     }

   void RefreshBounds(int idx, int touches)
     {
      double bm = CombinedBuffer(touches);
      m_zones[idx].buffer_multiplier = bm;
      m_zones[idx].high = m_zones[idx].price + m_clusterTol * bm * 0.5;
      m_zones[idx].low  = m_zones[idx].price - m_clusterTol * bm * 0.5;
     }

public:
   CSRZoneStore() : m_count(0), m_atr(0.0), m_clusterTol(0.0), m_debug(false),
                    m_supportCount(0), m_resistanceCount(0)
     {
      for(int i = 0; i < SRZ_MAX_ZONES; i++) m_zones[i].Init();
      ClearIndexes();
     }

   void SetDebug(bool d) { m_debug = d; }
   void SetDataManager(IDataManager *data) {}

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
         double w = 1.0 / (double)(m_zones[idx].touchCount + 1);
         m_zones[idx].price = m_zones[idx].price * (1.0 - w) + price * w;
         m_zones[idx].touchCount++;
         m_zones[idx].lastTouchAge = barsAgo;
         m_zones[idx].lastTouchTime = iTime(_Symbol, _Period, barsAgo);
         m_zones[idx].last_reaction = MathAbs(iClose(_Symbol, _Period, 1) - price) / MathMax(m_atr, _Point);
         RefreshBounds(idx, m_zones[idx].touchCount);
         m_zones[idx].htf_alignment = CalcHTFAlignment(m_zones[idx].price, m_zones[idx].isSupport, htfPeriod);
         m_zones[idx].strength = CalcStrengthAt(idx);
         m_zones[idx].confidence = CalcConfidenceAt(idx);
        }
      else if(m_count < SRZ_MAX_ZONES)
        {
         idx = m_count;
         m_zones[idx].Init();
         m_zones[idx].price = price;
         m_zones[idx].touchCount = 1;
         m_zones[idx].lastTouchAge = barsAgo;
         m_zones[idx].lastTouchTime = iTime(_Symbol, _Period, barsAgo);
         m_zones[idx].isSupport = isSupport;
         m_zones[idx].isBroken = false;
         m_zones[idx].formation_bars = barsAgo;
         m_zones[idx].strength = 25.0;
         m_zones[idx].confidence = 50.0;
         RefreshBounds(idx, 1);
         m_zones[idx].htf_alignment = CalcHTFAlignment(price, isSupport, htfPeriod);
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
         m_zones[i].strength = CalcStrengthAt(i);
         m_zones[i].confidence = CalcConfidenceAt(i);
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
            RefreshBounds(i, m_zones[i].touchCount);
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
         bool stale = false;
         if(m_zones[i].isBroken && m_zones[i].lastTouchAge > 50) stale = true;
         if(m_zones[i].strength < SRZ_MIN_STRENGTH && m_zones[i].lastTouchAge > 150) stale = true;
         if(m_zones[i].formation_bars > 500 && m_zones[i].touchCount < 2) stale = true;
         if(m_zones[i].age_decay_factor < 0.5 && m_zones[i].strength < 30.0) stale = true;
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
      int pos = LowerBoundSupport(price) - 1;
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
      int pos = LowerBoundResistance(price);
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

      int sPos = LowerBoundSupport(price - tol);
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

      int rPos = LowerBoundResistance(price - tol);
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

   bool GetZone(int i, SRZoneExtended &out) const
     {
      if(i < 0 || i >= m_count) return false;
      out = m_zones[i];
      return true;
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