//+------------------------------------------------------------------+
//| Signal/SignalManager.mqh — v4.01 (BUG-021 BUG-023 BUG-026 FIXED)|
//| Signal orchestration using modular components                    |
//|                                                                  |
//| FIX v4.01:                                                       |
//|  BUG-021 — EventBus::Instance() removed → use m_bus via          |
//|            DispatchToBus() protected helper in IManager          |
//|  BUG-023 — DeclareEvents() now uses EVENT_ID_* constants only    |
//|  BUG-026 — CSignalConfig::Init() deferred to PostInit()          |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_SIGNAL_MANAGER_MQH__
#define __SIGNAL_SIGNAL_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "ISignalSource.mqh"
#include "SignalConfig.mqh"
#include "SignalAggregator.mqh"
#include "SignalFilterPipeline.mqh"
#include "SignalCooldownManager.mqh"
#include "SignalScorer.mqh"
#include "../Analysis/Pattern/PatternManager.mqh"
#include "../Data/SRStruct.mqh"
#include "../Data/RegimeTypes.mqh"

// Forward declarations
class CPatternManager;
class CSRManager;
class CMarketRegime;

//+------------------------------------------------------------------+
//| Market Data Cache (from ZoneUpdate events)                       |
//+------------------------------------------------------------------+
struct SignalMarketData
  {
   double atrPoints;
   double support, resistance;
   double htfSupport, htfResistance;
   bool   isSupBroken, isResBroken;
   double supBufferMult, resBufferMult;
   int    supHtfAlign, resHtfAlign;

   void Reset()
     {
      ZeroMemory(this);
     }
  };

//+------------------------------------------------------------------+
//| CSignalManager — v4.01                                           |
//+------------------------------------------------------------------+
class CSignalManager : public IManager
  {
private:
   CSignalAggregator       m_aggregator;
   CSignalFilterPipeline   m_filterPipeline;
   CSignalCooldownManager  m_cooldownMgr;
   CSignalScorer           m_scorer;
   CSignalConfig           m_config;

   CPatternManager        *m_pattern;
   CSRManager             *m_sr;
   CMarketRegime          *m_regime;

   SignalMarketData        m_marketData;
   SignalDecision          m_pendingSignal;
   bool                    m_signalPending;
   datetime                m_lastProcessedBar;
   bool                    m_hasNewTick;
   MqlTick                 m_cachedTick;
   bool                    m_configReady;   // BUG-026: lazy init flag

   //--- Batch fetch candles
   bool FetchCandleBatch(int shiftStart, int count, MqlRates &outRates[])
     {
      ArraySetAsSeries(outRates, true);
      int copied = CopyRates(_Symbol, _Period, shiftStart, count, outRates);
      return (copied > 0);
     }

   //--- BUG-026: Lazy config init — called after IManager::Init() completes
   void EnsureConfigReady()
     {
      if(m_configReady) return;
      m_config.Init();
      m_aggregator.Init(m_config);
      m_filterPipeline.Init(m_config);
      m_cooldownMgr.Init(m_config);
      m_scorer.Init(m_config);
      m_configReady = true;
     }

   //--- BUG-021 FIX: dispatch via m_bus (IManager protected member), not static singleton
   void DispatchSignalEvent(SignalDecision &decision, double atrPoints,
                            double support, double resistance)
     {
      // Guard: m_bus is set by IManager::Init()
      if(CheckPointer(m_bus) == POINTER_INVALID)
        {
         if(m_debugMode)
            Print("[SignalManager] BUG-021-guard: m_bus NULL, cannot dispatch signal");
         return;
        }

      SignalGeneratedEvent *sigEvent = new SignalGeneratedEvent(
         decision, atrPoints, support, resistance
      );
      if(CheckPointer(sigEvent) == POINTER_INVALID) return;

      // Use IManager::m_bus directly (protected) — no static singleton
      m_bus.Push(sigEvent);
     }

   //--- Signal detection on new bar
   void ProcessSignalOnNewBar(NewBarEvent *e)
     {
      double atrPoints     = m_marketData.atrPoints;
      double support       = m_marketData.support;
      double resistance    = m_marketData.resistance;
      double htfSupport    = m_marketData.htfSupport;
      double htfResistance = m_marketData.htfResistance;
      bool   isSupBroken   = m_marketData.isSupBroken;
      bool   isResBroken   = m_marketData.isResBroken;
      double supBufMult    = m_marketData.supBufferMult;
      double resBufMult    = m_marketData.resBufferMult;
      int    supHtfAlign   = m_marketData.supHtfAlign;
      int    resHtfAlign   = m_marketData.resHtfAlign;

      if(atrPoints <= 0 || support <= 0 || resistance <= 0)
        {
         if(m_config.GetDebugMode())
            Print("[SignalManager] Missing zone data for signal detection");
         return;
        }

      SignalDecision decision;
      if(DetectSignalCore(decision, atrPoints, support, resistance,
                         htfSupport, htfResistance, isSupBroken, isResBroken,
                         supBufMult, resBufMult, supHtfAlign, resHtfAlign))
        {
         // BUG-021 FIX: use m_bus not static EventBus::Instance()
         DispatchSignalEvent(decision, atrPoints, support, resistance);

         ENUM_SIGNAL_DIR dir = (decision.orderType == ORDER_TYPE_BUY)
                               ? SIGNAL_BUY : SIGNAL_SELL;
         m_cooldownMgr.RegisterSignalCooldown(decision.signalPrice, dir);

         m_pendingSignal  = decision;
         m_signalPending  = true;
        }
     }

   //--- Core detection engine
   bool DetectSignalCore(SignalDecision &decision,
                        double atrPoints,
                        double support, double resistance,
                        double htfSupport, double htfResistance,
                        bool isSupBroken, bool isResBroken,
                        double supBufferMult, double resBufferMult,
                        int supHtfAlign, int resHtfAlign)
     {
      ZeroMemory(decision);
      string reason = "No pattern detected";

      int lookback = m_config.GetSignalLookback();
      if(iBars(_Symbol, _Period) < lookback + 5)
        {
         decision.reason = "Insufficient history data";
         return false;
        }

      MqlRates rates[];
      if(!FetchCandleBatch(1, lookback + 3, rates))
        {
         decision.reason = "Failed to fetch candle data";
         return false;
        }

      for(int shift = 1; shift <= lookback; shift++)
        {
         int    dir         = 0;
         double signalPrice = 0;
         ENUM_PATTERN_TYPE pType = PATTERN_NONE;
         string patternReason = "";

         if(m_pattern == NULL ||
            !m_pattern.Detect(rates, shift, atrPoints, pType, dir, signalPrice, patternReason))
            continue;

         double zonePrice        = (dir == 1) ? support : resistance;
         double currentBufMult   = (dir == 1) ? supBufferMult : resBufferMult;
         int    currentHtfAlign  = (dir == 1) ? supHtfAlign   : resHtfAlign;

         if(m_config.GetUseMTF() && currentHtfAlign < 0)
           {
            reason = (dir == 1) ? "HTF Contra-Support" : "HTF Contra-Resistance";
            continue;
           }

         if((dir == 1 && isSupBroken) || (dir == -1 && isResBroken))
           {
            reason = "Zone broken";
            continue;
           }

         FilterResult filterResult;
         if(!m_filterPipeline.RunCompletePipeline(shift, dir, zonePrice, signalPrice,
                                                  atrPoints, htfSupport, htfResistance,
                                                  currentBufMult, filterResult, rates))
           {
            reason = filterResult.reason;
            continue;
           }

         ENUM_SIGNAL_DIR signalDir = (dir == 1) ? SIGNAL_BUY : SIGNAL_SELL;

         if(m_cooldownMgr.IsZoneReuseBlocked(dir == 1, zonePrice, atrPoints))
           { reason = "Zone reuse blocked"; continue; }

         if(m_cooldownMgr.IsPatternFailureBlocked(dir == 1, zonePrice, atrPoints))
           { reason = "Level failure cooldown"; continue; }

         if(m_cooldownMgr.IsSignalCooldownActive(signalPrice, signalDir, atrPoints))
           { reason = "Signal cooldown active"; continue; }

         decision.valid      = true;
         decision.orderType  = (dir == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         decision.signalPrice = signalPrice;
         decision.patternType = pType;
         decision.zonePrice   = zonePrice;
         decision.signalShift = shift;
         decision.reason      = patternReason +
                                (filterResult.reason != "" ? " | " + filterResult.reason : "");

         m_cooldownMgr.RegisterZoneUse(dir == 1, zonePrice);

         if(m_config.GetDebugMode())
            PrintFormat("[PASR Signal] v %s @ %.5f | Pattern: %s | %s",
                       (dir == 1 ? "BUY" : "SELL"), signalPrice,
                       EnumToString(pType), decision.reason);

         return true;
        }

      decision.reason = (reason == "") ? "No signal" : reason;
      return false;
     }

public:
   CSignalManager()
      : IManager(),
        m_pattern(NULL), m_sr(NULL), m_regime(NULL),
        m_signalPending(false),
        m_lastProcessedBar(0),
        m_hasNewTick(false),
        m_configReady(false)   // BUG-026: config not ready until PostInit()
     {
      // BUG-026 FIX: do NOT call m_config.Init() here
      // It will be called lazily in EnsureConfigReady() after IManager::Init()
      m_marketData.Reset();
     }

   // BUG-026 FIX: PostInit called after IManager::Init() completes
   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      EnsureConfigReady();
      return true;
     }

   virtual void Deinit() override
     {
      m_signalPending = false;
      m_cooldownMgr.Clear();
     }

   void SetPatternManager(CPatternManager *p)  { m_pattern = p; }
   void SetSRManager(CSRManager *sr)            { m_sr      = sr; }
   void SetRegimeManager(CMarketRegime *r)      { m_regime  = r; }

   bool RegisterSource(ISignalSource *src, double weight = 1.0)
     {
      return m_aggregator.RegisterSource(src, weight);
     }

   int SourceCount() const { return m_aggregator.SourceCount(); }

   // BUG-023 FIX: all event IDs use EVENT_ID_* constants (no raw strings)
   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_NEW_BAR);         // was also "NewBar" (duplicate, raw)
      AddEvent(EVENT_ID_CONFIG_RELOAD);
      AddEvent(EVENT_ID_PRICE_UPDATE);    // was "PriceUpdate" raw string
      AddEvent(EVENT_ID_ZONE_UPDATE);     // was "ZoneUpdate" raw string
      AddEvent(EVENT_ID_EMERGENCY_STOP);  // was "EmergencyStop" raw string
      AddEvent(EVENT_ID_HEARTBEAT);       // was "Heartbeat" raw string
     }

   virtual void OnPriceUpdate(PriceUpdateEvent *e) override
     {
      if(CheckPointer(e) == POINTER_INVALID) return;
      m_cachedTick  = e.tick;
      m_hasNewTick  = true;
     }

   virtual void OnNewBar(NewBarEvent *e) override
     {
      if(CheckPointer(e) == POINTER_INVALID || !m_initialized) return;
      if(e.barOpenTime == m_lastProcessedBar) return;
      if(!m_hasNewTick) return;

      EnsureConfigReady();
      ProcessSignalOnNewBar(e);
      m_lastProcessedBar = e.barOpenTime;
      m_hasNewTick = false;
     }

   virtual void OnConfigReload(ConfigReloadEvent *e) override
     {
      m_config.Init();
      m_aggregator.Init(m_config);
      m_filterPipeline.Init(m_config);
      m_cooldownMgr.Init(m_config);
      m_scorer.Init(m_config);
      m_configReady = true;
     }

   virtual void OnEmergencyStop(EmergencyStopEvent *e) override
     {
      m_signalPending = false;
      if(m_config.GetDebugMode())
         Log("Emergency Stop: Clearing pending signals.");
     }

   virtual void OnHeartbeat(HeartbeatEvent *e) override
     {
      m_cooldownMgr.CleanupExpired();
     }

   virtual void OnCustomEvent(Event *e) override
     {
      if(e == NULL) return;
      // BUG-023 FIX: compare against EVENT_ID_ZONE_UPDATE constant
      if(e.Id() == EVENT_ID_ZONE_UPDATE)
        {
         ZoneUpdateEvent *ze = (ZoneUpdateEvent*)e;
         m_marketData.atrPoints      = ze.atrPoints;
         m_marketData.support        = ze.support;
         m_marketData.resistance     = ze.resistance;
         m_marketData.htfSupport     = ze.htfSupport;
         m_marketData.htfResistance  = ze.htfResistance;
         m_marketData.isSupBroken    = ze.isSupBroken;
         m_marketData.isResBroken    = ze.isResBroken;
         m_marketData.supBufferMult  = ze.supBufferMult;
         m_marketData.resBufferMult  = ze.resBufferMult;
         m_marketData.supHtfAlign    = ze.supHtfAlign;
         m_marketData.resHtfAlign    = ze.resHtfAlign;
        }
     }

   void NotifyPatternFailure(bool isBuy, double zonePrice)
     {
      m_cooldownMgr.RegisterFailure(isBuy, zonePrice);
     }

   bool HasPendingSignal(SignalDecision &outSignal)
     {
      if(m_signalPending)
        {
         outSignal       = m_pendingSignal;
         m_signalPending = false;
         return true;
        }
      return false;
     }

   const CSignalConfig& GetConfig() const { return m_config; }
  };

typedef CSignalManager SignalManager;
#endif // __SIGNAL_SIGNAL_MANAGER_MQH__
