//+------------------------------------------------------------------+
//| Analysis/SRManager.mqh — v1.00  (Phase 3 — FULL IMPLEMENTATION) |
//| Swing pivot detection + zone clustering + strength scoring.      |
//|                                                                  |
//| ALGORITHM:                                                       |
//|  1. Scan lookback bars for swing highs/lows (fractal-based)     |
//|  2. Cluster nearby levels within ATR/2 tolerance                |
//|  3. Score each zone by: touch count, recency, respected bounces |
//|  4. Mark zones broken when price closes through midpoint        |
//+------------------------------------------------------------------+
#property strict
#ifndef __ANALYSIS_SR_MANAGER_MQH__
#define __ANALYSIS_SR_MANAGER_MQH__

#include "../Core/IManager.mqh"

// Re-use SRZone struct from Data/SRManager.mqh
// Include canonical stub which defines SRZone
#include "../Data/SRManager.mqh"

//+------------------------------------------------------------------+
//| CAnalysisSRManager — full swing-pivot SR detection              |
//+------------------------------------------------------------------+
#define ASR_MAX_ZONES   60
#define ASR_LOOKBACK   300   // bars to scan
#define ASR_LEFT_BARS    3   // pivot confirmation bars left
#define ASR_RIGHT_BARS   3   // pivot confirmation bars right

class CAnalysisSRManager : public IManager
  {
private:
   SRZone  m_zones[ASR_MAX_ZONES];
   int     m_zoneCount;
   double  m_clusterTol;   // ATR * 0.5 — recalculated each bar

   // ── Pivot detection: fractal high/low ─────────────────────────

   bool IsPivotHigh(int shift) const
     {
      double h = iHigh(_Symbol, _Period, shift);
      for(int i=1; i<=ASR_LEFT_BARS;  i++) if(iHigh(_Symbol,_Period,shift+i) >= h) return false;
      for(int i=1; i<=ASR_RIGHT_BARS; i++) if(iHigh(_Symbol,_Period,shift-i) >= h) return false;
      return true;
     }

   bool IsPivotLow(int shift) const
     {
      double l = iLow(_Symbol, _Period, shift);
      for(int i=1; i<=ASR_LEFT_BARS;  i++) if(iLow(_Symbol,_Period,shift+i) <= l) return false;
      for(int i=1; i<=ASR_RIGHT_BARS; i++) if(iLow(_Symbol,_Period,shift-i) <= l) return false;
      return true;
     }

   // ── Zone management ───────────────────────────────────────────

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

   void AddOrMerge(double price, bool isSupport, int barsAgo)
     {
      int idx = FindCluster(price);
      if(idx >= 0)
        {
         // Merge: update midpoint, increment touch count
         m_zones[idx].price     = (m_zones[idx].price * m_zones[idx].touchCount + price)
                                  / (double)(m_zones[idx].touchCount + 1);
         m_zones[idx].high      = m_zones[idx].price + m_clusterTol * 0.5;
         m_zones[idx].low       = m_zones[idx].price - m_clusterTol * 0.5;
         m_zones[idx].touchCount++;
         m_zones[idx].lastTouchAge  = barsAgo;
         m_zones[idx].lastTouchTime = iTime(_Symbol, _Period, barsAgo);
         // Recalculate strength
         m_zones[idx].strength  = CalcStrength(m_zones[idx]);
        }
      else if(m_zoneCount < ASR_MAX_ZONES)
        {
         SRZone &z = m_zones[m_zoneCount];
         z.Init();
         z.price        = price;
         z.high         = price + m_clusterTol * 0.5;
         z.low          = price - m_clusterTol * 0.5;
         z.touchCount   = 1;
         z.lastTouchAge = barsAgo;
         z.lastTouchTime= iTime(_Symbol, _Period, barsAgo);
         z.isSupport    = isSupport;
         z.isBroken     = false;
         z.strength     = 10.0;  // initial
         m_zoneCount++;
        }
     }

   double CalcStrength(const SRZone &z) const
     {
      // Components:
      //  touch count  — more touches = stronger (capped at 5)
      //  recency      — more recent = stronger
      //  age penalty  — old untouched zones decay
      double touchScore   = MathMin(5.0, (double)z.touchCount) / 5.0 * 50.0;
      double recencyScore = MathMax(0.0, 1.0 - z.lastTouchAge / 200.0) * 30.0;
      double freshness    = z.isBroken ? 0.0 : 20.0;
      return MathMin(100.0, touchScore + recencyScore + freshness);
     }

   void CheckBroken()
     {
      double closePrice = iClose(_Symbol, _Period, 1); // previous closed bar
      for(int i=0; i<m_zoneCount; i++)
        {
         if(m_zones[i].isBroken) continue;
         // Support broken: close below zone low
         if(m_zones[i].isSupport && closePrice < m_zones[i].low)
            m_zones[i].isBroken = true;
         // Resistance broken: close above zone high
         if(!m_zones[i].isSupport && closePrice > m_zones[i].high)
            m_zones[i].isBroken = true;
        }
     }

   void RemoveStaleZones()
     {
      int keep = 0;
      for(int i=0; i<m_zoneCount; i++)
        {
         // Remove broken zones older than 50 bars, or very weak zones older than 150 bars
         bool stale = (m_zones[i].isBroken && m_zones[i].lastTouchAge > 50) ||
                      (m_zones[i].strength < 15.0 && m_zones[i].lastTouchAge > 150);
         if(!stale)
           {
            if(keep != i) m_zones[keep] = m_zones[i];
            keep++;
           }
        }
      m_zoneCount = keep;
     }

public:
   CAnalysisSRManager() : IManager(), m_zoneCount(0), m_clusterTol(0) {}

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
     }

   virtual void OnNewBar() override
     {
      // Update cluster tolerance to ATR-based
      double atr = m_data.GetATRPoints() * _Point;
      m_clusterTol = (atr > 0) ? atr * 0.5 : _Point * 10;

      // Check if any existing zones are now broken
      CheckBroken();

      // Scan for new pivot highs/lows
      int scanBars = MathMin(ASR_LOOKBACK, (int)Bars(_Symbol, _Period) - ASR_RIGHT_BARS - 1);
      for(int shift = ASR_RIGHT_BARS + 1; shift < scanBars; shift++)
        {
         if(IsPivotHigh(shift))
            AddOrMerge(iHigh(_Symbol, _Period, shift), false, shift);
         if(IsPivotLow(shift))
            AddOrMerge(iLow(_Symbol, _Period, shift),  true,  shift);
        }

      // Update lastTouchAge for all zones (increment by 1 bar)
      for(int i=0; i<m_zoneCount; i++)
         if(!m_zones[i].isBroken) m_zones[i].lastTouchAge++;

      // Recalculate strength
      for(int i=0; i<m_zoneCount; i++)
         m_zones[i].strength = CalcStrength(m_zones[i]);

      RemoveStaleZones();

      if(m_debugMode)
         PrintFormat("[SR] Zones: %d active (%.1f ATR tol)",
                     GetActiveCount(), m_clusterTol/_Point);
     }

   // ── Accessors ───────────────────────────────────────────────────

   bool GetNearestSupport(double price, SRZone &out) const
     {
      double best = DBL_MAX; bool found=false;
      for(int i=0;i<m_zoneCount;i++)
        {
         if(!m_zones[i].isSupport || m_zones[i].isBroken) continue;
         if(m_zones[i].price >= price) continue;
         double d = price - m_zones[i].price;
         if(d < best) { best=d; out=m_zones[i]; found=true; }
        }
      return found;
     }

   bool GetNearestResistance(double price, SRZone &out) const
     {
      double best = DBL_MAX; bool found=false;
      for(int i=0;i<m_zoneCount;i++)
        {
         if(m_zones[i].isSupport || m_zones[i].isBroken) continue;
         if(m_zones[i].price <= price) continue;
         double d = m_zones[i].price - price;
         if(d < best) { best=d; out=m_zones[i]; found=true; }
        }
      return found;
     }

   // Returns true when price is within |proximityATR| ATRs of a valid zone
   bool IsNearZone(double price, double proximityATR, SRZone &out) const
     {
      double atr = m_data.GetATRPoints() * _Point;
      double tol = atr * proximityATR;
      double best = DBL_MAX; bool found=false;
      for(int i=0;i<m_zoneCount;i++)
        {
         if(m_zones[i].isBroken || m_zones[i].strength < 20.0) continue;
         double d = MathAbs(price - m_zones[i].price);
         if(d <= tol && d < best) { best=d; out=m_zones[i]; found=true; }
        }
      return found;
     }

   bool IsZoneValid(const SRZone &z) const
     {
      return (z.touchCount >= 2 && z.lastTouchAge <= 200 &&
              z.strength >= 20.0 && !z.isBroken);
     }

   int GetZoneCount()  const { return m_zoneCount; }
   int GetActiveCount()const
     {
      int n=0;
      for(int i=0;i<m_zoneCount;i++) if(!m_zones[i].isBroken) n++;
      return n;
     }

   const SRZone* GetZone(int i) const
     { return (i>=0 && i<m_zoneCount) ? &m_zones[i] : NULL; }
  };

typedef CAnalysisSRManager AnalysisSRManager;
#endif
