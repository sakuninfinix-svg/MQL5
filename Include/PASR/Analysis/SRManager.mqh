//+------------------------------------------------------------------+
//| Analysis/SRManager.mqh - v1.00                                   |
//| Responsibility: PIPELINE ORCHESTRATOR - IManager adapter         |
//| Copyright @2026                                                  |
//| agsicentre.wordpress.com                                         |
//+------------------------------------------------------------------+
#property strict
#ifndef __ANALYSIS_SR_MANAGER_MQH__
#define __ANALYSIS_SR_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "../Analysis/SRDetector.mqh"
#include "../Analysis/SRZoneStore.mqh"
#include "../Analysis/MarketRegimeDetector.mqh"

#define ASR_LOOKBACK_BASE      300
#define ASR_LOOKBACK_LOW_VOL   210
#define ASR_LOOKBACK_HIGH_VOL  450
#define ASR_LOOKBACK_TRENDING  270
#define ASR_LOOKBACK_RANGING   390

class CAnalysisSRManager : public IManager
  {
private:
   CSRDetector           m_detector;
   CSRZoneStore          m_store;
   CMarketRegimeDetector *m_regime;
   ENUM_TIMEFRAMES       m_htfPeriod;
   int                   m_adaptiveLookback;
   ulong                 m_scanCount;
   datetime              m_lastScanTime;
   int                   m_lastScanBar;

   int RegimeLookback() const
     {
      if(m_regime == NULL) return ASR_LOOKBACK_BASE;
      switch(m_regime.GetCurrentRegime())
        {
         case REGIME_RANGE:      return ASR_LOOKBACK_RANGING;
         case REGIME_VOLATILE:   return ASR_LOOKBACK_HIGH_VOL;
         case REGIME_TREND_UP:
         case REGIME_TREND_DOWN: return ASR_LOOKBACK_TRENDING;
         case REGIME_SQUEEZE:    return ASR_LOOKBACK_LOW_VOL;
         case REGIME_CRASH:      return ASR_LOOKBACK_LOW_VOL;
         default:                return ASR_LOOKBACK_BASE;
        }
     }

public:
   CAnalysisSRManager()
      : IManager(), m_regime(NULL), m_htfPeriod(PERIOD_CURRENT),
        m_adaptiveLookback(ASR_LOOKBACK_BASE), m_scanCount(0),
        m_lastScanTime(0), m_lastScanBar(-1)
     {}

   void SetRegimeDetector(CMarketRegimeDetector *regime) { m_regime = regime; }
   void SetHTFPeriod(ENUM_TIMEFRAMES period) { m_htfPeriod = period; }

   virtual string HandlerName() const override { return "SRManager"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      m_store.SetDataManager(data);
      return true;
     }

   virtual void Deinit() override
     {
      m_store.Clear();
      IManager::Deinit();
     }

   virtual bool IsHealthy() const override { return IManager::IsHealthy() && m_store.IsValid(); }
   virtual void OnPriceUpdate() override {}

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_PRICE_UPDATE);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
     }

   virtual void OnNewBar() override
     {
      double atr = m_data.GetATRPoints() * _Point;
      m_store.UpdateATR(atr);

      datetime barTime = iTime(_Symbol, _Period, 0);
      int barIdx = iBarShift(_Symbol, _Period, barTime);
      if(barIdx == m_lastScanBar && barTime == m_lastScanTime) return;
      m_lastScanBar = barIdx;
      m_lastScanTime = barTime;
      m_scanCount++;

      m_store.CheckBroken();

      int lookback = RegimeLookback();
      SRPivotResult pivots[];
      ArrayResize(pivots, 0);
      m_detector.Scan(lookback, pivots);

      int total = ArraySize(pivots);
      for(int i = 0; i < total; i++)
         m_store.AddOrUpdate(pivots[i].price, !pivots[i].isHigh,
                             pivots[i].barsAgo, m_htfPeriod);

      m_store.AgeAndRefresh(m_htfPeriod);
      m_store.MergeNearby();
      m_store.RemoveStale();

      if(m_debugMode)
         PrintFormat("[SR v6.0.4] Scan #%I64u | %d active | lookback=%d | ATR=%.5f",
                     m_scanCount, m_store.GetActiveCount(), lookback, atr);
     }

   virtual void OnEvent(const PASREvent &ev) override
     {
      if(ev.id == EVENT_ID_NEW_BAR) OnNewBar();
      if(ev.id == EVENT_ID_CONFIG_RELOAD) { }
     }

   bool GetNearestSupport(double price, SRZoneExtended &out) const { return m_store.GetNearestSupport(price, out); }
   bool GetNearestResistance(double price, SRZoneExtended &out) const { return m_store.GetNearestResistance(price, out); }
   bool IsNearValidZone(double price, double atrMult, SRZoneExtended &out) const { return m_store.IsNearValidZone(price, atrMult, out); }
   bool IsZoneValid(SRZoneExtended &z) const { return m_store.IsZoneValid(z); }
   bool GetZone(int i, SRZoneExtended &out) const { return m_store.GetZone(i, out); }
   int GetActiveCount() const { return m_store.GetActiveCount(); }
  };

class AnalysisSRManager : public CAnalysisSRManager {};

#endif // __ANALYSIS_SR_MANAGER_MQH__
