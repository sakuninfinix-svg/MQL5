//+------------------------------------------------------------------+
//| Analysis/ZoneManager.mqh - v1.00                                 |
//| Compile-safe supply/demand zone manager                          |
//| Copyright @2026                                                  |
//| agsicentre.wordpress.com                                         |
//+------------------------------------------------------------------+
#property strict
#ifndef __ANALYSIS_ZONE_MANAGER_MQH__
#define __ANALYSIS_ZONE_MANAGER_MQH__

#include "../Core/IManager.mqh"

struct SDZone
  {
   double   high;
   double   low;
   bool     isSupply;
   datetime createdTime;
   datetime consumedTime;
   double   freshnessPct;
   int      touchCount;
   bool     isActive;
   double   confidence;

   void Init()
     {
      high = 0.0;
      low = 0.0;
      isSupply = false;
      createdTime = 0;
      consumedTime = 0;
      freshnessPct = 1.0;
      touchCount = 0;
      isActive = false;
      confidence = 0.0;
     }

   double Midpoint() const { return (high + low) * 0.5; }
   double Height() const { return high - low; }
   bool Contains(double price) const { return (price >= low && price <= high); }
   double Strength() const { return confidence * freshnessPct; }
  };

#define AZ_MAX_ZONES        30
#define AZ_LOOKBACK         200
#define AZ_IMPULSE_BARS     3
#define AZ_IMPULSE_ATR      1.5
#define AZ_BASE_MAX_BODY    0.5
#define AZ_FRESHNESS_DECAY  0.2
#define AZ_MIN_CONFIDENCE   0.3
#define AZ_CONSUME_BUFFER_POINTS 5

class CAnalysisZoneManager : public IManager
  {
private:
   SDZone  m_zones[AZ_MAX_ZONES];
   int     m_zoneCount;
   int     m_totalZonesCreated;
   int     m_totalZonesConsumed;
   ulong   m_lastScanBarTime;

   bool ZoneExists(double zHigh, double zLow) const
     {
      for(int i = 0; i < m_zoneCount; i++)
        {
         if(!m_zones[i].isActive) continue;
         if(MathAbs(m_zones[i].high - zHigh) < _Point * 5 &&
            MathAbs(m_zones[i].low  - zLow)  < _Point * 5)
            return true;
        }
      return false;
     }

   void MarkZoneConsumed(const int index)
     {
      if(index < 0 || index >= m_zoneCount) return;
      if(!m_zones[index].isActive) return;
      m_zones[index].isActive = false;
      m_zones[index].consumedTime = TimeCurrent();
      m_totalZonesConsumed++;
     }

   bool TryAddZone(double zHigh, double zLow, bool isSupply, datetime t, double impulseStrength)
     {
      if(ZoneExists(zHigh, zLow)) return false;
      if(m_zoneCount >= AZ_MAX_ZONES) return false;
      m_zones[m_zoneCount].Init();
      m_zones[m_zoneCount].high = NormalizeDouble(zHigh, _Digits);
      m_zones[m_zoneCount].low = NormalizeDouble(zLow, _Digits);
      m_zones[m_zoneCount].isSupply = isSupply;
      m_zones[m_zoneCount].createdTime = t;
      m_zones[m_zoneCount].freshnessPct = 1.0;
      m_zones[m_zoneCount].isActive = true;
      m_zones[m_zoneCount].confidence = MathMin(1.0, 0.5 + impulseStrength * 0.1);
      m_zones[m_zoneCount].touchCount = 0;
      m_zoneCount++;
      m_totalZonesCreated++;
      return true;
     }

   void ConsumeZonesRealtime(const double price)
     {
      if(price <= 0.0) return;
      double buffer = AZ_CONSUME_BUFFER_POINTS * _Point;
      for(int i = 0; i < m_zoneCount; i++)
        {
         if(!m_zones[i].isActive) continue;
         if(m_zones[i].isSupply && price > m_zones[i].high + buffer)
           { MarkZoneConsumed(i); continue; }
         if(!m_zones[i].isSupply && price < m_zones[i].low - buffer)
            MarkZoneConsumed(i);
        }
     }

   void UpdateFreshnessAndConsumed()
     {
      double curPrice = iClose(_Symbol, _Period, 1);
      if(curPrice <= 0.0) return;
      for(int i = 0; i < m_zoneCount; i++)
        {
         if(!m_zones[i].isActive) continue;
         if(m_zones[i].isSupply && curPrice > m_zones[i].high)
           { MarkZoneConsumed(i); continue; }
         if(!m_zones[i].isSupply && curPrice < m_zones[i].low)
           { MarkZoneConsumed(i); continue; }
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
            m_zones[i].confidence = MathMin(1.0, m_zones[i].confidence + 0.05);
           }
        }
     }

   void ScanImpulses(double atr)
     {
      double threshold = atr * AZ_IMPULSE_ATR;
      int scanEnd = MathMin(AZ_LOOKBACK, (int)Bars(_Symbol, _Period) - AZ_IMPULSE_BARS - 2);
      for(int shift = AZ_IMPULSE_BARS + 1; shift < scanEnd; shift++)
        {
         datetime barTime = iTime(_Symbol, _Period, shift);
         if(barTime <= (datetime)m_lastScanBarTime) continue;
         bool bullImpulse = true;
         double bullMove = 0.0;
         for(int j = 0; j < AZ_IMPULSE_BARS; j++)
           {
            double o = iOpen(_Symbol, _Period, shift-j);
            double c = iClose(_Symbol, _Period, shift-j);
            if(o <= 0.0 || c <= 0.0 || c <= o) { bullImpulse = false; break; }
            bullMove += (c - o);
           }
         if(bullImpulse && bullMove >= threshold)
           {
            int baseShift = shift + 1;
            double bO = iOpen(_Symbol, _Period, baseShift);
            double bC = iClose(_Symbol, _Period, baseShift);
            double bH = iHigh(_Symbol, _Period, baseShift);
            double bL = iLow(_Symbol, _Period, baseShift);
            double bRange = bH - bL;
            double bBody = MathAbs(bC - bO);
            if(bO > 0.0 && bC > 0.0 && bRange > 0.0 && bBody / bRange <= AZ_BASE_MAX_BODY)
              {
               double zH = MathMax(bO, bC);
               double zL = MathMin(bO, bC);
               TryAddZone(zH, zL, false, iTime(_Symbol, _Period, baseShift), bullMove / atr);
              }
           }
         bool bearImpulse = true;
         double bearMove = 0.0;
         for(int j = 0; j < AZ_IMPULSE_BARS; j++)
           {
            double o = iOpen(_Symbol, _Period, shift-j);
            double c = iClose(_Symbol, _Period, shift-j);
            if(o <= 0.0 || c <= 0.0 || c >= o) { bearImpulse = false; break; }
            bearMove += (o - c);
           }
         if(bearImpulse && bearMove >= threshold)
           {
            int baseShift = shift + 1;
            double bO = iOpen(_Symbol, _Period, baseShift);
            double bC = iClose(_Symbol, _Period, baseShift);
            double bH = iHigh(_Symbol, _Period, baseShift);
            double bL = iLow(_Symbol, _Period, baseShift);
            double bRange = bH - bL;
            double bBody = MathAbs(bC - bO);
            if(bO > 0.0 && bC > 0.0 && bRange > 0.0 && bBody / bRange <= AZ_BASE_MAX_BODY)
              {
               double zH = MathMax(bO, bC);
               double zL = MathMin(bO, bC);
               TryAddZone(zH, zL, true, iTime(_Symbol, _Period, baseShift), bearMove / atr);
              }
           }
        }
      if(scanEnd > AZ_IMPULSE_BARS + 1)
         m_lastScanBarTime = (ulong)iTime(_Symbol, _Period, AZ_IMPULSE_BARS + 1);
     }

   void CompactZones()
     {
      int keep = 0;
      for(int i = 0; i < m_zoneCount; i++)
        {
         if(!m_zones[i].isActive) continue;
         if(keep != i) m_zones[keep] = m_zones[i];
         keep++;
        }
      m_zoneCount = keep;
     }

public:
   CAnalysisZoneManager()
      : IManager(), m_zoneCount(0), m_totalZonesCreated(0),
        m_totalZonesConsumed(0), m_lastScanBarTime(0)
     {
      for(int i = 0; i < AZ_MAX_ZONES; i++) m_zones[i].Init();
     }

   virtual ~CAnalysisZoneManager() {}
   virtual string HandlerName() const override { return "ZoneManager"; }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_PRICE_UPDATE);
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
     }

   virtual void OnEvent(const PASREvent &ev) override
     {
      if(ev.id == EVENT_ID_PRICE_UPDATE) { OnPriceUpdate(); return; }
      if(ev.id == EVENT_ID_NEW_BAR) OnNewBar();
     }

   virtual void OnPriceUpdate() override
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      ConsumeZonesRealtime(bid);
     }

   virtual void OnNewBar() override
     {
      if(m_data == NULL) return;
      double atr = m_data.GetATRPoints() * _Point;
      if(atr <= 0.0) return;
      UpdateFreshnessAndConsumed();
      ScanImpulses(atr);
      CompactZones();
      if(m_debugMode)
         PrintFormat("[Zone v2.06] Active:%d Created:%d Consumed:%d", m_zoneCount, m_totalZonesCreated, m_totalZonesConsumed);
     }

   bool IsPriceInZone(double price, SDZone &out) const
     {
      for(int i = 0; i < m_zoneCount; i++)
        {
         if(!m_zones[i].isActive) continue;
         if(price >= m_zones[i].low && price <= m_zones[i].high)
           { out = m_zones[i]; return true; }
        }
      return false;
     }

   bool IsNearZone(double price, double atrMult, SDZone &out) const
     {
      if(m_data == NULL) return false;
      double atr = m_data.GetATRPoints() * _Point;
      double tol = atr * atrMult;
      double best = DBL_MAX;
      bool found = false;
      for(int i = 0; i < m_zoneCount; i++)
        {
         if(!m_zones[i].isActive) continue;
         double mid = (m_zones[i].high + m_zones[i].low) * 0.5;
         double d = MathAbs(price - mid);
         if(d <= tol && d < best)
           { best = d; out = m_zones[i]; found = true; }
        }
      return found;
     }

   int GetHighConfidenceZones(SDZone &out[], double minConfidence = 0.5) const
     {
      int count = 0;
      for(int i = 0; i < m_zoneCount; i++)
        {
         if(!m_zones[i].isActive) continue;
         if(m_zones[i].confidence >= minConfidence && count < ArraySize(out))
            out[count++] = m_zones[i];
        }
      return count;
     }

   bool ExportToCSV(const string filename) const
     {
      int handle = FileOpen(filename, FILE_WRITE|FILE_CSV|FILE_ANSI, ';');
      if(handle == INVALID_HANDLE) return false;
      FileWrite(handle, "Type;High;Low;Created;Freshness;Confidence;Touches;Active");
      for(int i = 0; i < m_zoneCount; i++)
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

   bool GetZone(int i, SDZone &out) const
     {
      if(i < 0 || i >= m_zoneCount) return false;
      out = m_zones[i];
      return true;
     }

   double GetAverageConfidence() const
     {
      if(m_zoneCount == 0) return 0.0;
      double sum = 0.0;
      int active = 0;
      for(int i = 0; i < m_zoneCount; i++)
        {
         if(m_zones[i].isActive)
           { sum += m_zones[i].confidence; active++; }
        }
      return active > 0 ? sum / active : 0.0;
     }
  };

class AnalysisZoneManager : public CAnalysisZoneManager {};

#endif // __ANALYSIS_ZONE_MANAGER_MQH__
