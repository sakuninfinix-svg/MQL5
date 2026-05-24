//+------------------------------------------------------------------+
//| Analysis/SRManager.mqh — v6.0.0                                  |
//| Responsibility: PIPELINE ORCHESTRATOR — IManager adapter         |
//|                                                                   |
//| WHAT THIS FILE DOES:                                             |
//|   1. Extends IManager — registers with EventBus, receives events |
//|   2. Owns CSRDetector + CSRZoneStore (composition, not inheritance)|
//|   3. OnNewBar(): ATR update → Scan → CheckBroken → Age → Merge   |
//|   4. Exposes minimal public API to pipeline (6 methods only)     |
//|                                                                   |
//| WHAT THIS FILE DOES NOT DO:                                      |
//|   - AccountInfo, TimeCurrent, session/news/equity (wrong domain) |
//|   - ENUM_MARKET_REGIME (use MarketRegimeDetector.mqh)            |
//|   - Visual debug rendering (use Dashboard module)                |
//|   - Correlation/exposure filtering (use RiskManager)             |
//|                                                                   |
//| Pipeline Stage: Stage_AnalysisSR() → m_sr->OnNewBar()           |
//|                 Signal layer   → m_sr->GetNearestSupport()       |
//+------------------------------------------------------------------+
#property strict
#ifndef __ANALYSIS_SR_MANAGER_MQH__
#define __ANALYSIS_SR_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "../Analysis/SRDetector.mqh"
#include "../Analysis/SRZoneStore.mqh"
#include "../Analysis/MarketRegimeDetector.mqh"

//-- Lookback constants
#define ASR_LOOKBACK_BASE      300   // Default scan bars
#define ASR_LOOKBACK_LOW_VOL   210   // Regime: low volatility
#define ASR_LOOKBACK_HIGH_VOL  450   // Regime: high volatility
#define ASR_LOOKBACK_TRENDING  270   // Regime: trending
#define ASR_LOOKBACK_RANGING   390   // Regime: ranging

//+------------------------------------------------------------------+
//| CAnalysisSRManager : public IManager                            |
//|                                                                  |
//| THIN ORCHESTRATOR — all business logic lives in SRDetector       |
//| and SRZoneStore. This class only wires events to those workers.  |
//+------------------------------------------------------------------+
class CAnalysisSRManager : public IManager
  {
private:
   CSRDetector          m_detector;        // Stateless pivot scanner
   CSRZoneStore         m_store;           // Zone storage + lifecycle
   CMarketRegimeDetector *m_regime;        // Injected regime detector (not owned)

   ENUM_TIMEFRAMES      m_htfPeriod;       // HTF for alignment checks
   int                  m_adaptiveLookback;
   ulong                m_scanCount;

   // Lazy-eval cache
   datetime             m_lastScanTime;
   int                  m_lastScanBar;

   //-- Map regime → lookback
   int RegimeLookback() const
     {
      if(m_regime == NULL) return ASR_LOOKBACK_BASE;

      switch(m_regime.GetRegime())
        {
         case MARKET_REGIME_LOW_VOL:   return ASR_LOOKBACK_LOW_VOL;
         case MARKET_REGIME_HIGH_VOL:  return ASR_LOOKBACK_HIGH_VOL;
         case MARKET_REGIME_TRENDING:  return ASR_LOOKBACK_TRENDING;
         case MARKET_REGIME_RANGING:   return ASR_LOOKBACK_RANGING;
         default:                      return ASR_LOOKBACK_BASE;
        }
     }

public:
   CAnalysisSRManager()
      : IManager(),
        m_regime(NULL),
        m_htfPeriod(PERIOD_CURRENT),
        m_adaptiveLookback(ASR_LOOKBACK_BASE),
        m_scanCount(0),
        m_lastScanTime(0),
        m_lastScanBar(-1)
     {}

   //-- Inject regime detector (Orchestrator calls this after Phase 2 init)
   void SetRegimeDetector(CMarketRegimeDetector *regime)
     {
      m_regime = regime;
     }

   //-- Set HTF period for zone alignment scoring
   void SetHTFPeriod(ENUM_TIMEFRAMES period)
     {
      m_htfPeriod = period;
     }

   //== IManager overrides ==========================================+

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

   virtual bool IsHealthy() const override
     {
      return IManager::IsHealthy() && m_store.IsValid();
     }

   virtual void OnPriceUpdate() override
     {
      // Price update hook for intra-bar zone proximity checks
      // Can be used for real-time zone break detection
     }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_PRICE_UPDATE);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
     }

   //+---------------------------------------------------------------+
   //| OnNewBar() — full scan cycle                                  |
   //|                                                               |
   //| Called by PipelineEngine::Stage_AnalysisSR() via EventBus     |
   //| or directly when EVENT_ID_NEW_BAR is consumed.               |
   //|                                                               |
   //| Sequence:                                                     |
   //|   1. Update ATR in store                                     |
   //|   2. Lazy-eval guard (skip if same bar)                       |
   //|   3. CheckBroken                                              |
   //|   4. ScanForPivots → AddOrUpdate                              |
   //|   5. AgeAndRefresh                                            |
   //|   6. MergeNearby                                              |
   //|   7. RemoveStale                                              |
   //+---------------------------------------------------------------+
   virtual void OnNewBar() override
     {
      // 1. Refresh ATR
      double atr = m_data.GetATRPoints() * _Point;
      m_store.UpdateATR(atr);

      // 2. Lazy-eval guard
      datetime barTime = iTime(_Symbol, _Period, 0);
      int      barIdx  = (int)iBarShift(_Symbol, _Period, 0);
      if(barIdx == m_lastScanBar && barTime == m_lastScanTime) return;
      m_lastScanBar  = barIdx;
      m_lastScanTime = barTime;
      m_scanCount++;

      // 3. Mark broken zones
      m_store.CheckBroken();

      // 4. Detect pivots → feed into store
      int lookback = RegimeLookback();
      SRPivotResult pivots[];
      ArrayResize(pivots, 0);
      m_detector.Scan(lookback, pivots);

      int total = ArraySize(pivots);
      for(int i = 0; i < total; i++)
         m_store.AddOrUpdate(pivots[i].price,
                             !pivots[i].isHigh,   // isHigh=false → support
                             pivots[i].barsAgo,
                             m_htfPeriod);

      // 5. Age all zones + refresh scoring
      m_store.AgeAndRefresh(m_htfPeriod);

      // 6. Merge nearby zones
      m_store.MergeNearby();

      // 7. Drop stale zones
      m_store.RemoveStale();

      if(m_debugMode)
         PrintFormat("[SR v6] Scan #%llu | %d active | lookback=%d | ATR=%.5f",
                     m_scanCount, m_store.GetActiveCount(),
                     lookback, atr);
     }

   virtual void OnEvent(const PASREvent &ev) override
     {
      if(ev.id == EVENT_ID_NEW_BAR)    OnNewBar();
      if(ev.id == EVENT_ID_CONFIG_RELOAD) { /* hot-reload future hook */ }
     }

   //== PIPELINE PUBLIC API (6 methods — keep this minimal) =========+
   //
   //  Signal and Trade layers call these. Nothing else should.
   //

   //-- Nearest support BELOW current price
   bool GetNearestSupport(double price, SRZoneExtended &out) const
     {
      return m_store.GetNearestSupport(price, out);
     }

   //-- Nearest resistance ABOVE current price
   bool GetNearestResistance(double price, SRZoneExtended &out) const
     {
      return m_store.GetNearestResistance(price, out);
     }

   //-- Is price within [atrMult] ATR of any valid zone?
   bool IsNearValidZone(double price, double atrMult, SRZoneExtended &out) const
     {
      return m_store.IsNearValidZone(price, atrMult, out);
     }

   //-- Zone validity check (pipeline / signal filter)
   bool IsZoneValid(const SRZoneExtended &z) const
     {
      return m_store.IsZoneValid(z);
     }

   //-- Zone pointer by index (Dashboard, Journal)
   const SRZoneExtended *GetZone(int i) const
     {
      return m_store.GetZone(i);
     }

   //-- Zone count (Dashboard, Journal)
   int GetActiveCount() const
     {
      return m_store.GetActiveCount();
     }
  };

typedef CAnalysisSRManager AnalysisSRManager;

#endif // __ANALYSIS_SR_MANAGER_MQH__
