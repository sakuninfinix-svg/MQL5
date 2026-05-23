//+------------------------------------------------------------------+
//| Signal/SignalManager.mqh — v4.00 (REFACTORED + MODULAR)          |
//| Signal orchestration using modular components                    |
//|                                                                  |
//| ARCHITECTURE:                                                    |
//|   - SignalAggregator: voting + veto + multiplier logic           |
//|   - SignalFilterPipeline: sequential filter validation           |
//|   - SignalCooldownManager: cooldown & failed zone tracking       |
//|   - SignalScorer: quality scoring & urgency determination        |
//|   - SignalConfig: centralized configuration cache                |
//|                                                                  |
//| MEMORY MANAGEMENT:                                               |
//|   - Uses CArrayObj for dynamic collections (safe memory)         |
//|   - No manual array resizing                                     |
//|                                                                  |
//| DEPENDENCIES:                                                    |
//|   - Only depends on Analysis/ and Core/ folders                  |
//|   - NO dependencies on Trade/ or Execution/                      |
//|                                                                  |
//| CHANGE LOG:                                                      |
//|  v4.00 (Refactored) — Modular architecture:                      |
//|    + Delegated aggregation to SignalAggregator                   |
//|    + Delegated filtering to SignalFilterPipeline                 |
//|    + Delegated cooldowns to SignalCooldownManager                |
//|    + Delegated scoring to SignalScorer                           |
//|    + Centralized config via SignalConfig                         |
//|    + Safe memory with CArrayObj                                  |
//|    + Removed all hardcoded values                                |
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

// Forward declarations for dependency injection
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
//| CSignalManager — Orchestrator for signal detection               |
//| Delegates to modular components for maintainability              |
//+------------------------------------------------------------------+
class CSignalManager : public IManager
  {
private:
   // Modular components (delegated responsibilities)
   CSignalAggregator       m_aggregator;        // Voting + veto + multiplier
   CSignalFilterPipeline   m_filterPipeline;    // Sequential filter validation
   CSignalCooldownManager  m_cooldownMgr;       // Cooldown & failed zone tracking
   CSignalScorer           m_scorer;            // Quality scoring & urgency
   CSignalConfig           m_config;            // Centralized configuration
   
   // Dependencies (injected)
   CPatternManager        *m_pattern;
   CSRManager             *m_sr;
   CMarketRegime          *m_regime;

   // State
   SignalMarketData        m_marketData;        // Cached market data from events
   SignalDecision          m_pendingSignal;     // Pending signal for polling
   bool                    m_signalPending;     // Has pending signal flag
   datetime                m_lastProcessedBar;  // Last processed bar time
   bool                    m_hasNewTick;        // New tick flag
   MqlTick                 m_cachedTick;        // Cached tick data

   //+------------------------------------------------------------------+\n   //| Batch fetch candles - single CopyRates call                      |\n   //+------------------------------------------------------------------+
   bool FetchCandleBatch(int shiftStart, int count, MqlRates &outRates[])
     {
      ArraySetAsSeries(outRates, true);
      int copied = CopyRates(_Symbol, _Period, shiftStart, count, outRates);
      return (copied > 0);
     }

   //+------------------------------------------------------------------+\n   //| Process signal detection on new bar                              |\n   //+------------------------------------------------------------------+
   void ProcessSignalOnNewBar(NewBarEvent* e)
     {
      // Use cached data from ZoneUpdateEvent
      double atrPoints      = m_marketData.atrPoints;
      double support        = m_marketData.support;
      double resistance     = m_marketData.resistance;
      double htfSupport     = m_marketData.htfSupport;
      double htfResistance  = m_marketData.htfResistance;
      bool   isSupBroken    = m_marketData.isSupBroken;
      bool   isResBroken    = m_marketData.isResBroken;
      double supBufferMult  = m_marketData.supBufferMult;
      double resBufferMult  = m_marketData.resBufferMult;
      int    supHtfAlign    = m_marketData.supHtfAlign;
      int    resHtfAlign    = m_marketData.resHtfAlign;

      if(atrPoints <= 0 || support <= 0 || resistance <= 0) {
         if(m_config.GetDebugMode()) 
            Print("[SignalManager] Missing data for signal detection");
         return;
      }

      // Run core detection
      SignalDecision decision;
      if(DetectSignalCore(decision, atrPoints, support, resistance,
                         htfSupport, htfResistance, isSupBroken, isResBroken,
                         supBufferMult, resBufferMult, supHtfAlign, resHtfAlign))
        {
         // Signal found! Dispatch to ExecutionManager via event
         SignalGeneratedEvent* sigEvent = new SignalGeneratedEvent(
            decision, atrPoints, support, resistance
         );
         EventBus::Instance().Dispatch(sigEvent);

         // Register cooldown
         ENUM_SIGNAL_DIR dir = (decision.orderType == ORDER_TYPE_BUY) ? SIGNAL_BUY : SIGNAL_SELL;
         m_cooldownMgr.RegisterSignalCooldown(decision.signalPrice, dir);
         
         // Also buffer for polling-style access (backward compat)
         m_pendingSignal = decision;
         m_signalPending = true;
        }
     }

   //+------------------------------------------------------------------+\n   //| Core Signal Detection Engine with Filter Pipeline                |\n   //+------------------------------------------------------------------+
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

      // Validate data availability
      int lookback = m_config.GetSignalLookback();
      if(iBars(_Symbol, _Period) < lookback + 5) {
         decision.reason = "Insufficient history data";
         return false;
      }

      // === OPTIMIZATION: Batch fetch candles once ===
      MqlRates rates[];
      if(!FetchCandleBatch(1, lookback + 3, rates)) {
         decision.reason = "Failed to fetch candle data";
         return false;
      }

      // Scan patterns in lookback window
      for(int shift = 1; shift <= lookback; shift++)
        {
         int dir = 0;
         double signalPrice = 0;
         ENUM_PATTERN_TYPE pType = PATTERN_NONE;
         string patternReason = "";

         // Pattern detection via PatternManager
         if(m_pattern == NULL || !m_pattern.Detect(rates, shift, atrPoints, pType, dir, signalPrice, patternReason))
            continue;

         double zonePrice = (dir == 1) ? support : resistance;
         double currentBufferMult = (dir == 1) ? supBufferMult : resBufferMult;
         int currentHtfAlign = (dir == 1) ? supHtfAlign : resHtfAlign;

         // === PRE-FILTER CHECKS ===
         // 1. HTF Alignment Filter
         if(m_config.GetUseMTF() && currentHtfAlign < 0) {
            reason = (dir == 1) ? "HTF Contra-Support" : "HTF Contra-Resistance";
            continue;
         }

         // 2. Zone Broken Filter
         if((dir == 1 && isSupBroken) || (dir == -1 && isResBroken)) {
            reason = "Zone broken (Price closed outside)";
            continue;
         }

         // === FILTER PIPELINE ===
         FilterResult filterResult;
         if(!m_filterPipeline.RunCompletePipeline(shift, dir, zonePrice, signalPrice, 
                                                  atrPoints, htfSupport, htfResistance,
                                                  currentBufferMult, filterResult, rates)) {
            reason = filterResult.reason;
            continue;
         }

         // === COOLDOWN CHECKS ===
         ENUM_SIGNAL_DIR signalDir = (dir == 1) ? SIGNAL_BUY : SIGNAL_SELL;
         
         // 7. Zone Reuse Filter
         if(m_cooldownMgr.IsZoneReuseBlocked(dir == 1, zonePrice, atrPoints)) {
            reason = "Zone reuse blocked"; 
            continue;
         }

         // 8. Pattern Failure Cooldown
         if(m_cooldownMgr.IsPatternFailureBlocked(dir == 1, zonePrice, atrPoints)) {
            reason = "Level failure cooldown"; 
            continue;
         }

         // 9. Signal Cooldown Filter
         if(m_cooldownMgr.IsSignalCooldownActive(signalPrice, signalDir, atrPoints)) {
            reason = "Signal cooldown active"; 
            continue;
         }

         // === SIGNAL FOUND: Populate decision struct ===
         decision.valid = true;
         decision.orderType = (dir == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         decision.signalPrice = signalPrice;
         decision.patternType = pType;
         decision.zonePrice = zonePrice;
         decision.signalShift = shift;
         decision.reason = patternReason + (filterResult.reason != "" ? " | " + filterResult.reason : "");

         // Register zone usage to prevent duplicate signals
         m_cooldownMgr.RegisterZoneUse(dir == 1, zonePrice);

         if(m_config.GetDebugMode())
            PrintFormat("[PASR Signal] ✓ %s @ %.5f | Pattern: %s | %s",
                       (dir==1?"BUY":"SELL"), signalPrice, EnumToString(pType), decision.reason);

         return true; // Early return on first valid signal
        }

      // No signal found
      decision.reason = (reason == "") ? "No signal" : reason;
      return false;
     }

public:
   //+------------------------------------------------------------------+\n   //| Constructor                                                      |\n   //+------------------------------------------------------------------+
   CSignalManager()
      : IManager(),
        m_pattern(NULL), m_sr(NULL), m_regime(NULL),
        m_signalPending(false),
        m_lastProcessedBar(0), 
        m_hasNewTick(false)
     {
      m_config.Init();
      m_aggregator.Init(m_config);
      m_filterPipeline.Init(m_config);
      m_cooldownMgr.Init(m_config);
      m_scorer.Init(m_config);
      m_marketData.Reset();
     }

   //+------------------------------------------------------------------+\n   //| Destructor                                                       |\n   //+------------------------------------------------------------------+
   virtual void Deinit() override 
     { 
      m_signalPending = false;
      m_cooldownMgr.Clear();
     }

   //+------------------------------------------------------------------+\n   //| Dependency injection                                             |\n   //+------------------------------------------------------------------+
   void SetPatternManager(CPatternManager *p) { m_pattern = p; }
   void SetSRManager(CSRManager *sr)           { m_sr      = sr; }
   void SetRegimeManager(CMarketRegime *r)     { m_regime  = r; }

   //+------------------------------------------------------------------+\n   //| Register a signal source plugin                                  |\n   //| weight >0 = voter, =0 = multiplier, <0 = veto                   |\n   //+------------------------------------------------------------------+
   bool RegisterSource(ISignalSource *src, double weight=1.0)
     {
      return m_aggregator.RegisterSource(src, weight);
     }

   //+------------------------------------------------------------------+\n   //| Get count of registered sources                                  |\n   //+------------------------------------------------------------------+
   int SourceCount() const { return m_aggregator.SourceCount(); }

   //+------------------------------------------------------------------+\n   //| Configuration setters                                            |\n   //+------------------------------------------------------------------+
   void SetMinConfluence(int v)    { /* Config handled by CSignalConfig */ }
   void SetMinScore(double v)      { /* Config handled by CSignalConfig */ }
   void SetCooldownBars(int v)     { /* Config handled by CSignalConfig */ }

   //+------------------------------------------------------------------+\n   //| Event declarations                                               |\n   //+------------------------------------------------------------------+
   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
      AddEvent("PriceUpdate");
      AddEvent("NewBar");
      AddEvent("ZoneUpdate");
      AddEvent("EmergencyStop");
      AddEvent("Heartbeat");
     }

   //+------------------------------------------------------------------+\n   //| Event Handler: PriceUpdate                                       |\n   //+------------------------------------------------------------------+
   virtual void OnPriceUpdate(PriceUpdateEvent* e) override
     {
      if(CheckPointer(e) == POINTER_INVALID) return;
      m_cachedTick = e.tick;
      m_hasNewTick = true;
     }

   //+------------------------------------------------------------------+\n   //| Event Handler: NewBar - MAIN SIGNAL DETECTION TRIGGER            |\n   //+------------------------------------------------------------------+
   virtual void OnNewBar(NewBarEvent* e) override
     {
      if(CheckPointer(e) == POINTER_INVALID || !m_initialized) return;
      if(e.barOpenTime == m_lastProcessedBar) return;
      if(!m_hasNewTick) return;

      ProcessSignalOnNewBar(e);
      m_lastProcessedBar = e.barOpenTime;
      m_hasNewTick = false;
     }

   //+------------------------------------------------------------------+\n   //| Event Handler: ConfigReload                                      |\n   //+------------------------------------------------------------------+
   virtual void OnConfigReload(ConfigReloadEvent* e) override
     {
      m_config.Init(); // Re-init config from globals
      m_aggregator.Init(m_config);
      m_filterPipeline.Init(m_config);
      m_cooldownMgr.Init(m_config);
      m_scorer.Init(m_config);
     }

   //+------------------------------------------------------------------+\n   //| Event Handler: EmergencyStop                                     |\n   //+------------------------------------------------------------------+
   virtual void OnEmergencyStop(EmergencyStopEvent* e) override
     {
      m_signalPending = false;
      if(m_config.GetDebugMode()) 
         Log("Emergency Stop: Clearing pending signals.");
     }

   //+------------------------------------------------------------------+\n   //| Event Handler: Heartbeat - Cleanup expired cooldowns             |\n   //+------------------------------------------------------------------+
   virtual void OnHeartbeat(HeartbeatEvent* e) override
     {
      m_cooldownMgr.CleanupExpired();
     }

   //+------------------------------------------------------------------+\n   //| Event Handler: Custom ZoneUpdate event                           |\n   //+------------------------------------------------------------------+
   virtual void OnCustomEvent(Event* e) override 
     {
      if(e.Type() == "ZoneUpdate") 
        {
         ZoneUpdateEvent* ze = (ZoneUpdateEvent*)e;
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

   //+------------------------------------------------------------------+\n   //| Register a failed zone externally (e.g., from TradeManager)      |\n   //+------------------------------------------------------------------+
   void NotifyPatternFailure(bool isBuy, double zonePrice)
     {
      m_cooldownMgr.RegisterFailure(isBuy, zonePrice);
     }

   //+------------------------------------------------------------------+\n   //| Get pending signal (if any) - for polling-style integration      |\n   //+------------------------------------------------------------------+
   bool HasPendingSignal(SignalDecision &outSignal)
     {
      if(m_signalPending) {
         outSignal = m_pendingSignal;
         m_signalPending = false;
         return true;
      }
      return false;
     }

   //+------------------------------------------------------------------+\n   //| Get config reference                                             |\n   //+------------------------------------------------------------------+
   const CSignalConfig& GetConfig() const { return m_config; }
  };

typedef CSignalManager SignalManager;
#endif // __SIGNAL_SIGNAL_MANAGER_MQH__
