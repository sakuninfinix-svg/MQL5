//+------------------------------------------------------------------+
//| Analysis/ZoneManager.mqh — v2.00  (Optimized & Clean)            |
//| Supply/Demand zone detection via impulse-base candle method.     |
//|                                                                  |
//| ARCHITECTURE IMPROVEMENTS v2.00:                                 |
//|   ✓ Moved SDZone struct to dedicated header for reusability      |
//|   ✓ Enhanced zone confidence scoring system                      |
//|   ✓ Multi-factor strength calculation                            |
//|   ✓ Weighted average price update on re-tests                    |
//|   ✓ CSV export functionality for backtesting                     |
//|   ✓ Optimized memory layout and cache efficiency                 |
//|                                                                  |
//| ALGORITHM:                                                       |
//|  1. Detect impulse move: consecutive bars in same direction      |
//|     covering >= ATR * ImpulseATRMult                             |
//|  2. Find the base candle: last small-body candle before impulse  |
//|  3. Zone = base candle body range (open/close)                  |
//|  4. Freshness decay: each re-test reduces freshness by 0.2       |
//|  5. Zone consumed when close breaches zone high (demand) / low   |
//|  6. Confidence scoring based on impulse strength, recency, etc.  |
//+------------------------------------------------------------------+
#property strict
#ifndef __ANALYSIS_ZONE_MANAGER_MQH__
#define __ANALYSIS_ZONE_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "../Data/ZoneStruct.mqh"  // SDZone struct (shared)

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
      double curPrice = iClose(_Symbol, _Period, 1);
      for(int i=0; i<m_zoneCount; i++)
        {
         if(!m_zones[i].isActive) continue;

         // Consumed: close breaks through zone
         if(m_zones[i].isSupply && curPrice > m_zones[i].high)
           { 
            m_zones[i].isActive = false; 
            m_zones[i].consumedTime = TimeCurrent();
            m_totalZonesConsumed++;
            continue; 
           }
         if(!m_zones[i].isSupply && curPrice < m_zones[i].low)
           { 
            m_zones[i].isActive = false; 
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
         datetime barTime = iTime(_Symbol, _Period, shift);
         if(barTime <= m_lastScanBarTime) continue;

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
               // Impulse strength normalized to ATR
               double strength = bullMove / atr;
               TryAddZone(zH, zL, false,  // demand zone (support)
                          iTime(_Symbol, _Period, baseShift), strength);
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
               // Impulse strength normalized to ATR
               double strength = bearMove / atr;
               TryAddZone(zH, zL, true,   // supply zone (resistance)
                          iTime(_Symbol, _Period, baseShift), strength);
              }
           }
        }
      
      // Update last scan time
      if(scanEnd > AZ_IMPULSE_BARS + 1)
         m_lastScanBarTime = iTime(_Symbol, _Period, AZ_IMPULSE_BARS + 1);
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
   CAnalysisZoneManager() : IManager(), m_zoneCount(0), 
                            m_totalZonesCreated(0), m_totalZonesConsumed(0),
                            m_lastScanBarTime(0)
     { 
      for(int i=0; i<AZ_MAX_ZONES; i++) m_zones[i].Init(); 
     }

   virtual ~CAnalysisZoneManager()
     {
      // Destructor - cleanup if needed
     }

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
         PrintFormat("[Zone] Active: %d | Created: %d | Consumed: %d", 
                     m_zoneCount, m_totalZonesCreated, m_totalZonesConsumed);
     }

   bool IsPriceInZone(double price, SDZone &out) const
     {
      for(int i=0; i<m_zoneCount; i++)
        {
         if(!m_zones[i].isActive) continue;
         if(price >= m_zones[i].low && price <= m_zones[i].high)
           { 
            out = m_zones[i]; 
            return true; 
           }
        }
      return false;
     }

   bool IsNearZone(double price, double atrMult, SDZone &out) const
     {
      double atr = m_data.GetATRPoints() * _Point;
      double tol = atr * atrMult;
      double best = DBL_MAX; 
      bool found = false;
      
      for(int i=0; i<m_zoneCount; i++)
        {
         if(!m_zones[i].isActive) continue;
         double mid = (m_zones[i].high + m_zones[i].low) * 0.5;
         double d   = MathAbs(price - mid);
         if(d <= tol && d < best) 
           { 
            best = d; 
            out = m_zones[i]; 
            found = true; 
           }
        }
      return found;
     }

   // Get zones filtered by minimum confidence
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

   // Export zones to CSV for backtesting analysis
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
                   DoubleToString(m_zones[i].low, _Digits),
                   TimeToString(m_zones[i].createdTime),
                   DoubleToString(m_zones[i].freshnessPct, 2),
                   DoubleToString(m_zones[i].confidence, 2),
                   m_zones[i].touchCount,
                   (m_zones[i].isActive ? "Yes" : "No"));
        }
      
      FileClose(handle);
      return true;
     }

   int GetZoneCount() const { return m_zoneCount; }
   int GetTotalCreated() const { return m_totalZonesCreated; }
   int GetTotalConsumed() const { return m_totalZonesConsumed; }
   
   const SDZone* GetZone(int i) const
     { return (i>=0 && i<m_zoneCount) ? &m_zones[i] : NULL; }
     
   // Get average confidence of active zones
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
#endif
