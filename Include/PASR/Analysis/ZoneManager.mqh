//+------------------------------------------------------------------+
//| Analysis/ZoneManager.mqh — v1.00  (Phase 3 — FULL IMPLEMENTATION)|
//| Supply/Demand zone detection via impulse-base candle method.     |
//|                                                                  |
//| ALGORITHM:                                                       |
//|  1. Detect impulse move: consecutive bars in same direction      |
//|     covering >= ATR * ImpulseATRMult                             |
//|  2. Find the base candle: last small-body candle before impulse  |
//|  3. Zone = base candle body range (open/close)                  |
//|  4. Freshness decay: each re-test reduces freshness by 0.2       |
//|  5. Zone consumed when close breaches zone high (demand) / low   |
//+------------------------------------------------------------------+
#property strict
#ifndef __ANALYSIS_ZONE_MANAGER_MQH__
#define __ANALYSIS_ZONE_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "../Data/ZoneManager.mqh"   // SDZone struct

//+------------------------------------------------------------------+
//| CAnalysisZoneManager — full S/D detection                       |
//+------------------------------------------------------------------+
#define AZ_MAX_ZONES    30
#define AZ_LOOKBACK    200
#define AZ_IMPULSE_BARS  3   // consecutive bars to confirm impulse
#define AZ_IMPULSE_ATR   1.5 // ATR multiplier for impulse threshold
#define AZ_BASE_MAX_BODY 0.5 // base candle body/range <= this ratio

class CAnalysisZoneManager : public IManager
  {
private:
   SDZone  m_zones[AZ_MAX_ZONES];
   int     m_zoneCount;

   // ── Helpers ────────────────────────────────────────────────

   bool ZoneExists(double zHigh, double zLow) const
     {
      for(int i=0;i<m_zoneCount;i++)
        {
         if(!m_zones[i].isActive) continue;
         if(MathAbs(m_zones[i].high - zHigh) < _Point * 5 &&
            MathAbs(m_zones[i].low  - zLow)  < _Point * 5) return true;
        }
      return false;
     }

   bool TryAddZone(double zHigh, double zLow, bool isSupply, datetime t)
     {
      if(ZoneExists(zHigh, zLow)) return false;
      if(m_zoneCount >= AZ_MAX_ZONES) return false;

      SDZone &z = m_zones[m_zoneCount];
      z.Init();
      z.high         = NormalizeDouble(zHigh, _Digits);
      z.low          = NormalizeDouble(zLow,  _Digits);
      z.isSupply     = isSupply;
      z.createdTime  = t;
      z.freshnessPct = 1.0;
      z.isActive     = true;
      m_zoneCount++;
      return true;
     }

   void UpdateFreshnessAndConsumed()
     {
      double curPrice = iClose(_Symbol, _Period, 1);
      for(int i=0;i<m_zoneCount;i++)
        {
         if(!m_zones[i].isActive) continue;

         // Consumed: close breaks through zone
         if(m_zones[i].isSupply && curPrice > m_zones[i].high)
           { m_zones[i].isActive = false; continue; }
         if(!m_zones[i].isSupply && curPrice < m_zones[i].low)
           { m_zones[i].isActive = false; continue; }

         // Re-test: price entered zone but didn't close through
         bool inZone = (curPrice >= m_zones[i].low && curPrice <= m_zones[i].high);
         if(inZone && m_zones[i].touchCount > 0)
           {
            m_zones[i].freshnessPct = MathMax(0.0, m_zones[i].freshnessPct - 0.2);
            if(m_zones[i].freshnessPct <= 0.0)
               m_zones[i].isActive = false;
           }
         if(inZone) m_zones[i].touchCount++;
        }
     }

   void ScanImpulses(double atr)
     {
      double threshold = atr * AZ_IMPULSE_ATR;
      int    scanEnd   = MathMin(AZ_LOOKBACK, (int)Bars(_Symbol,_Period) - AZ_IMPULSE_BARS - 2);

      for(int shift = AZ_IMPULSE_BARS + 1; shift < scanEnd; shift++)
        {
         // ── Bullish impulse: AZ_IMPULSE_BARS consecutive bull candles
         bool bullImpulse = true;
         double bullMove = 0;
         for(int j=0; j<AZ_IMPULSE_BARS; j++)
           {
            double o = iOpen(_Symbol,_Period,shift-j);
            double c = iClose(_Symbol,_Period,shift-j);
            if(c <= o) { bullImpulse=false; break; }
            bullMove += (c - o);
           }

         if(bullImpulse && bullMove >= threshold)
           {
            // Base candle: last small-body candle just before impulse
            int baseShift = shift + 1;
            double bO = iOpen(_Symbol,_Period,baseShift);
            double bC = iClose(_Symbol,_Period,baseShift);
            double bH = iHigh(_Symbol,_Period,baseShift);
            double bL = iLow(_Symbol,_Period,baseShift);
            double bRange = bH - bL;
            double bBody  = MathAbs(bC - bO);
            if(bRange > 0 && bBody/bRange <= AZ_BASE_MAX_BODY)
              {
               double zH = MathMax(bO, bC);
               double zL = MathMin(bO, bC);
               TryAddZone(zH, zL, false,  // demand zone (support)
                          iTime(_Symbol, _Period, baseShift));
              }
           }

         // ── Bearish impulse: AZ_IMPULSE_BARS consecutive bear candles
         bool bearImpulse = true;
         double bearMove = 0;
         for(int j=0; j<AZ_IMPULSE_BARS; j++)
           {
            double o = iOpen(_Symbol,_Period,shift-j);
            double c = iClose(_Symbol,_Period,shift-j);
            if(c >= o) { bearImpulse=false; break; }
            bearMove += (o - c);
           }

         if(bearImpulse && bearMove >= threshold)
           {
            int baseShift = shift + 1;
            double bO = iOpen(_Symbol,_Period,baseShift);
            double bC = iClose(_Symbol,_Period,baseShift);
            double bH = iHigh(_Symbol,_Period,baseShift);
            double bL = iLow(_Symbol,_Period,baseShift);
            double bRange = bH - bL;
            double bBody  = MathAbs(bC - bO);
            if(bRange > 0 && bBody/bRange <= AZ_BASE_MAX_BODY)
              {
               double zH = MathMax(bO, bC);
               double zL = MathMin(bO, bC);
               TryAddZone(zH, zL, true,   // supply zone (resistance)
                          iTime(_Symbol, _Period, baseShift));
              }
           }
        }
     }

   void CompactZones()
     {
      int keep=0;
      for(int i=0;i<m_zoneCount;i++)
         if(m_zones[i].isActive)
           { if(keep!=i) m_zones[keep]=m_zones[i]; keep++; }
      m_zoneCount = keep;
     }

public:
   CAnalysisZoneManager() : IManager(), m_zoneCount(0)
     { for(int i=0;i<AZ_MAX_ZONES;i++) m_zones[i].Init(); }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
     }

   virtual void OnNewBar() override
     {
      double atr = m_data.GetATRPoints() * _Point;
      if(atr <= 0) return;

      UpdateFreshnessAndConsumed();
      ScanImpulses(atr);
      CompactZones();

      if(m_debugMode)
         PrintFormat("[Zone] Active zones: %d", m_zoneCount);
     }

   bool IsPriceInZone(double price, SDZone &out) const
     {
      for(int i=0;i<m_zoneCount;i++)
        {
         if(!m_zones[i].isActive) continue;
         if(price >= m_zones[i].low && price <= m_zones[i].high)
           { out = m_zones[i]; return true; }
        }
      return false;
     }

   bool IsNearZone(double price, double atrMult, SDZone &out) const
     {
      double atr = m_data.GetATRPoints() * _Point;
      double tol = atr * atrMult;
      double best = DBL_MAX; bool found=false;
      for(int i=0;i<m_zoneCount;i++)
        {
         if(!m_zones[i].isActive) continue;
         double mid = (m_zones[i].high + m_zones[i].low) * 0.5;
         double d   = MathAbs(price - mid);
         if(d <= tol && d < best) { best=d; out=m_zones[i]; found=true; }
        }
      return found;
     }

   int GetZoneCount() const { return m_zoneCount; }
   const SDZone* GetZone(int i) const
     { return (i>=0&&i<m_zoneCount)?&m_zones[i]:NULL; }
  };

typedef CAnalysisZoneManager AnalysisZoneManager;
#endif
