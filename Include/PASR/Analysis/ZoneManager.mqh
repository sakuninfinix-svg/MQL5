//+------------------------------------------------------------------+
#include <PASR/MQL5Compatibility.mqh>
//| Analysis/ZoneManager.mqh — v2.02                                 |
//| Supply/Demand zone detection via impulse-base candle method.     |
//|                                                                  |
//| CHANGELOG:                                                       |
//|   v2.02 (2026-05-23) Sprint 7:                                   |
//|     BUG-013: Missing OnEvent() override — DeclareEvents()        |
//|              subscribed to EVENT_ID_NEW_BAR but EventBus         |
//|              dispatch was silent-failing. OnEvent() added.       |
//|   v2.01 — Optimized & Clean (confidence scoring, CSV export)     |
//+------------------------------------------------------------------+
#property strict
#ifndef __ANALYSIS_ZONE_MANAGER_MQH__
#define __ANALYSIS_ZONE_MANAGER_MQH__

#include "../Core/IManager.mqh"

//+------------------------------------------------------------------+
//| SDZone — Supply/Demand zone structure                            |
//+------------------------------------------------------------------+
struct SDZone
  {
   double   high;            // Zone high price
   double   low;             // Zone low price
   bool     isSupply;        // true=supply (resistance), false=demand (support)
   datetime createdTime;     // When zone was created
   datetime consumedTime;    // When zone was consumed/breached
   double   freshnessPct;    // 1.0 = fresh, decays on re-tests
   int      touchCount;      // Number of times price touched zone
   bool     isActive;        // Whether zone is still valid
   double   confidence;      // Confidence score 0.0-1.0

   void Init()
     {
      high = 0; low = 0; isSupply = false;
      createdTime = 0; consumedTime = 0;
      freshnessPct = 1.0; touchCount = 0;
      isActive = false; confidence = 0.0;
     }

   double Midpoint() const { return (high + low) * 0.5; }
   double Height()   const { return high - low; }
   bool Contains(double price) const { return (price >= low && price <= high); }
   double Strength()  const { return confidence * freshnessPct; }
  };

// ── Configuration Constants ───────────────────────────────────────
#define AZ_MAX_ZONES        30
#define AZ_LOOKBACK         200
#define AZ_IMPULSE_BARS     3     // consecutive bars to confirm impulse
#define AZ_IMPULSE_ATR      1.5   // ATR multiplier for impulse threshold
#define AZ_BASE_MAX_BODY    0.5   // base candle body/range <= this ratio
#define AZ_FRESHNESS_DECAY  0.2   // decay per re-test
#define AZ_MIN_CONFIDENCE   0.3   // minimum confidence to consider zone

//+------------------------------------------------------------------+
//| CAnalysisZoneManager — full S/D detection with confidence        |
//+------------------------------------------------------------------+
class CAnalysisZoneManager : public IManager
  {
private:
   SDZone  m_zones[AZ_MAX_ZONES];
   int     m_zoneCount;
   int     m_totalZonesCreated;    // lifetime counter for stats
   int     m_totalZonesConsumed;   // lifetime counter for stats
   ulong   m_lastScanBarTime;      // prevent duplicate scans

   // ── Helpers ────────────────────────────────────────────────

   bool ZoneExists(double zHigh, double zLow) const
     {
      for(int i=0; i<m_zoneCount; i++)
        {
         if(!m_zones[i].isActive) continue;
         if(MathAbs(m_zones[i].high - zHigh) < _Point * 5 &&
            MathAbs(m_zones[i].low  - zLow)  < _Point * 5) return true;
        }
      return false;
     }

   bool TryAddZone(double zHigh, double zLow, bool isSupply, datetime t, double impulseStrength)
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
      // Calculate initial confidence based on impulse strength
      z.confidence   = MathMin(1.0, 0.5 + impulseStrength * 0.1);
      z.touchCount   = 0;

      m_zoneCount++;
      m_totalZonesCreated++;
      return true;
     }

   void UpdateFreshnessAndConsumed()
     {
      double curPrice = GetClose(_Symbol, _Period, 1);
      for(int i=0; i<m_zoneCount; i++)
        {
         if(!m_zones[i].isActive) continue;

         // Consumed: close breaks through zone
         if(m_zones[i].isSupply && curPrice > m_zones[i].high)
           {
            m_zones[i].isActive    = false;
            m_zones[i].consumedTime = TimeCurrent();
            m_totalZonesConsumed++;
            continue;
           }
         if(!m_zones[i].isSupply && curPrice < m_zones[i].low)
           {
            m_zones[i].isActive    = false;
            m_zones[i].consumedTime = TimeCurrent();
            m_totalZonesConsumed++;
            continue;
           }

         // Re-test: price entered zone but didn't close through
         bool inZone = (curPrice >= m_zones[i].low && curPrice <= m_zones[i].high);
         if(inZone && m_zones[i].touchCount > 0)
           {
            m_zones[i].freshnessPct = MathMax(0.0, m_zones[i].freshnessPct - AZ_FRESHNESS_DECAY);
            if(m_zones[i].freshnessPct <= 0.0 || m_zones[i].confidence < AZ_MIN_CONFIDENCE)
               m_zones[i].isActive = false;
           }
         if(inZone)
           {
            m_zones[i].touchCount++;
            // Update confidence based on successful test
            m_zones[i].confidence = MathMin(1.0, m_zones[i].confidence + 0.05);
           }
        }
     }

   void ScanImpulses(double atr)
     {
      double threshold = atr * AZ_IMPULSE_ATR;
      int    scanEnd   = MathMin(AZ_LOOKBACK, (int)Bars(_Symbol,_Period) - AZ_IMPULSE_BARS - 2);

      for(int shift = AZ_IMPULSE_BARS + 1; shift < scanEnd; shift++)
        {
         // Prevent re-scanning already processed bars
         datetime barTime = GetTime(_Symbol, _Period, shift);
         if(barTime <= (datetime)m_lastScanBarTime) continue;

         // ── Bullish impulse: AZ_IMPULSE_BARS consecutive bull candles
         bool   bullImpulse = true;
         double bullMove    = 0;
         for(int j=0; j<AZ_IMPULSE_BARS; j++)
           {
            double o = GetOpen(_Symbol,_Period,shift-j);
            double c = GetClose(_Symbol,_Period,shift-j);
            if(c <= o) { bullImpulse=false; break; }
            bullMove += (c - o);
           }

         if(bullImpulse && bullMove >= threshold)
           {
            int    baseShift = shift + 1;
            double bO = GetOpen(_Symbol,_Period,baseShift);
            double bC = GetClose(_Symbol,_Period,baseShift);
            double bH = GetHigh(_Symbol,_Period,baseShift);
            double bL = GetLow(_Symbol,_Period,baseShift);
            double bRange = bH - bL;
            double bBody  = MathAbs(bC - bO);
            if(bRange > 0 && bBody/bRange <= AZ_BASE_MAX_BODY)
              {
               double zH       = MathMax(bO, bC);
               double zL       = MathMin(bO, bC);
               double strength = bullMove / atr;
               TryAddZone(zH, zL, false,   // demand zone (support)
                          GetTime(_Symbol, _Period, baseShift), strength);
              }
           }

         // ── Bearish impulse: AZ_IMPULSE_BARS consecutive bear candles
         bool   bearImpulse = true;
         double bearMove    = 0;
         for(int j=0; j<AZ_IMPULSE_BARS; j++)
           {
            double o = GetOpen(_Symbol,_Period,shift-j);
            double c = GetClose(_Symbol,_Period,shift-j);
            if(c >= o) { bearImpulse=false; break; }
            bearMove += (o - c);
           }

         if(bearImpulse && bearMove >= threshold)
           {
            int    baseShift = shift + 1;
            double bO = GetOpen(_Symbol,_Period,baseShift);
            double bC = GetClose(_Symbol,_Period,baseShift);
            double bH = GetHigh(_Symbol,_Period,baseShift);
            double bL = GetLow(_Symbol,_Period,baseShift);
            double bRange = bH - bL;
            double bBody  = MathAbs(bC - bO);
            if(bRange > 0 && bBody/bRange <= AZ_BASE_MAX_BODY)
              {
               double zH       = MathMax(bO, bC);
               double zL       = MathMin(bO, bC);
               double strength = bearMove / atr;
               TryAddZone(zH, zL, true,   // supply zone (resistance)
                          GetTime(_Symbol, _Period, baseShift), strength);
              }
           }
        }

      // Update last scan timestamp
      if(scanEnd > AZ_IMPULSE_BARS + 1)
         m_lastScanBarTime = (ulong)GetTime(_Symbol, _Period, AZ_IMPULSE_BARS + 1);
     }

   void CompactZones()
     {
      int keep=0;
      for(int i=0; i<m_zoneCount; i++)
         if(m_zones[i].isActive)
           {
            if(keep != i) m_zones[keep] = m_zones[i];
            keep++;
           }
      m_zoneCount = keep;
     }

public:
   CAnalysisZoneManager()
      : IManager(), m_zoneCount(0),
        m_totalZonesCreated(0), m_totalZonesConsumed(0),
        m_lastScanBarTime(0)
     {
      for(int i=0; i<AZ_MAX_ZONES; i++) m_zones[i].Init();
     }

   virtual ~CAnalysisZoneManager() {}

   //== IManager overrides ==========================================+

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
     }

   //+---------------------------------------------------------------+
   //| BUG-013 FIX (v2.02): OnEvent() was missing. EventBus calls    |
   //| Dispatch(ev) which iterates registered managers and calls     |
   //| their OnEvent(). Without this override, all EVENT_ID_NEW_BAR  |
   //| dispatches were no-ops — zone detection never ran from bus.   |
   //+---------------------------------------------------------------+
   virtual void OnEvent(const PASREvent &ev) override
     {
      if(ev.id == EVENT_ID_NEW_BAR) OnNewBar();
      // CONFIG_RELOAD: future hook for runtime parameter updates
     }

   virtual void OnNewBar() override
     {
      double atr = m_data.GetATRPoints() * _Point;
      if(atr <= 0) return;

      UpdateFreshnessAndConsumed();
      ScanImpulses(atr);
      CompactZones();

      if(m_debugMode)
         PrintFormat("[Zone v2.02] Active: %d | Created: %d | Consumed: %d",
                     m_zoneCount, m_totalZonesCreated, m_totalZonesConsumed);
     }

   //== PIPELINE PUBLIC API =========================================+

   bool IsPriceInZone(double price, SDZone &out) const
     {
      for(int i=0; i<m_zoneCount; i++)
        {
         if(!m_zones[i].isActive) continue;
         if(price >= m_zones[i].low && price <= m_zones[i].high)
           { out = m_zones[i]; return true; }
        }
      return false;
     }

   bool IsNearZone(double price, double atrMult, SDZone &out) const
     {
      double atr  = m_data.GetATRPoints() * _Point;
      double tol  = atr * atrMult;
      double best = DBL_MAX;
      bool   found = false;

      for(int i=0; i<m_zoneCount; i++)
        {
         if(!m_zones[i].isActive) continue;
         double mid = (m_zones[i].high + m_zones[i].low) * 0.5;
         double d   = MathAbs(price - mid);
         if(d <= tol && d < best)
           { best = d; out = m_zones[i]; found = true; }
        }
      return found;
     }

   int GetHighConfidenceZones(SDZone &out[], double minConfidence = 0.5) const
     {
      int count = 0;
      for(int i=0; i<m_zoneCount; i++)
        {
         if(!m_zones[i].isActive) continue;
         if(m_zones[i].confidence >= minConfidence)
           {
            if(count < ArraySize(out))
               out[count++] = m_zones[i];
           }
        }
      return count;
     }

   bool ExportToCSV(const string filename) const
     {
      int handle = FileOpen(filename, FILE_WRITE|FILE_CSV|FILE_ANSI, ';');
      if(handle == INVALID_HANDLE) return false;

      FileWrite(handle, "Type;High;Low;Created;Freshness;Confidence;Touches;Active");
      for(int i=0; i<m_zoneCount; i++)
        {
         if(!m_zones[i].isActive) continue;
         FileWrite(handle,
                   (m_zones[i].isSupply ? "Supply" : "Demand"),
                   DoubleToString(m_zones[i].high, _Digits),
                   DoubleToString(m_zones[i].low,  _Digits),
                   TimeToString(m_zones[i].createdTime),
                   DoubleToString(m_zones[i].freshnessPct, 2),
                   DoubleToString(m_zones[i].confidence, 2),
                   m_zones[i].touchCount,
                   (m_zones[i].isActive ? "Yes" : "No"));
        }

      FileClose(handle);
      return true;
     }

   int    GetZoneCount()       const { return m_zoneCount;          }
   int    GetTotalCreated()    const { return m_totalZonesCreated;  }
   int    GetTotalConsumed()   const { return m_totalZonesConsumed; }
   const  SDZone* GetZone(int i) const
     { return (i>=0 && i<m_zoneCount) ? &m_zones[i] : NULL; }

   double GetAverageConfidence() const
     {
      if(m_zoneCount == 0) return 0.0;
      double sum = 0.0;
      for(int i=0; i<m_zoneCount; i++)
         if(m_zones[i].isActive) sum += m_zones[i].confidence;
      return sum / m_zoneCount;
     }
  };

typedef CAnalysisZoneManager AnalysisZoneManager;
#endif // __ANALYSIS_ZONE_MANAGER_MQH__
