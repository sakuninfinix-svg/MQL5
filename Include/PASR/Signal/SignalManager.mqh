//+------------------------------------------------------------------+
//| Signal/SignalManager.mqh — v4.20                                |
//| Signal layer orchestration with diagnostics snapshot              |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_SIGNAL_MANAGER_MQH__
#define __SIGNAL_SIGNAL_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "../Core/PipelineTypes.mqh"
#include "ISignalSource.mqh"
#include "SignalConfig.mqh"
#include "SignalAggregator.mqh"
#include "SignalFilterPipeline.mqh"
#include "SignalCooldownManager.mqh"
#include "SignalScorer.mqh"
#include "../Analysis/Pattern/PatternManager.mqh"
#include "../Analysis/SRManager.mqh"
#include "../Data/SRStruct.mqh"
#include "../Data/RegimeTypes.mqh"

struct SignalDecision
  {
   bool   valid;
   int    orderType;
   double signalPrice;
   int    patternType;
   double zonePrice;
   int    signalShift;
   string reason;

   SignalDecision() { Clear(); }

   void Clear()
     {
      valid       = false;
      orderType   = ORDER_TYPE_BUY;
      signalPrice = 0.0;
      patternType = PATTERN_NONE;
      zonePrice   = 0.0;
      signalShift = 0;
      reason      = "";
     }
  };

struct SignalLayerSnapshot
  {
   bool            ready;
   datetime        lastBarTime;
   int             sourceCount;
   int             cooldownCount;
   int             failedZoneCount;
   ENUM_SIGNAL_DIR lastDirection;
   double          lastConfidence;
   double          lastRawScore;
   double          lastConflictScore;
   double          lastDominanceGap;
   double          lastMultiplier;
   int             lastConfluence;
   bool            lastVetoed;
   string          lastSources;
   string          lastVetoReason;
   string          lastReason;

   void Clear()
     {
      ready = false;
      lastBarTime = 0;
      sourceCount = 0;
      cooldownCount = 0;
      failedZoneCount = 0;
      lastDirection = SIGNAL_NONE;
      lastConfidence = 0.0;
      lastRawScore = 0.0;
      lastConflictScore = 0.0;
      lastDominanceGap = 0.0;
      lastMultiplier = 1.0;
      lastConfluence = 0;
      lastVetoed = false;
      lastSources = "";
      lastVetoReason = "";
      lastReason = "";
     }
  };

class CMarketRegime;

class CSignalManager : public IManager
  {
private:
   CSignalAggregator       m_aggregator;
   CSignalFilterPipeline   m_filterPipeline;
   CSignalCooldownManager  m_cooldownMgr;
   CSignalScorer           m_scorer;
   CSignalConfig           m_config;

   CPatternManager        *m_pattern;
   CAnalysisSRManager     *m_sr;
   CMarketRegime          *m_regime;

   SignalDecision          m_pendingSignal;
   bool                    m_signalPending;
   datetime                m_lastProcessedBar;
   bool                    m_configReady;
   AggregatedSignal        m_lastAggregated;
   SignalLayerSnapshot     m_snapshot;

   void RefreshSnapshot(const string reason = "")
     {
      m_snapshot.ready = m_configReady;
      m_snapshot.lastBarTime = m_lastProcessedBar;
      m_snapshot.sourceCount = m_aggregator.SourceCount();
      m_snapshot.cooldownCount = m_cooldownMgr.GetActiveCooldownCount();
      m_snapshot.failedZoneCount = m_cooldownMgr.GetActiveFailedZoneCount();
      m_snapshot.lastDirection = m_lastAggregated.direction;
      m_snapshot.lastConfidence = m_lastAggregated.normalizedScore;
      m_snapshot.lastRawScore = m_lastAggregated.rawScore;
      SignalAggregatorSnapshot aggSnap = m_aggregator.GetSnapshot();
      m_snapshot.lastConflictScore = aggSnap.conflictScore;
      m_snapshot.lastDominanceGap = aggSnap.dominanceGap;
      m_snapshot.lastMultiplier = m_lastAggregated.multiplierFactor;
      m_snapshot.lastConfluence = m_lastAggregated.confluence;
      m_snapshot.lastVetoed = m_lastAggregated.vetoed;
      m_snapshot.lastSources = m_lastAggregated.contributingSources;
      m_snapshot.lastVetoReason = m_aggregator.GetVetoReason();
      m_snapshot.lastReason = reason;
     }

   void EnsureConfigReady()
     {
      if(m_configReady) return;
      m_config.Init();
      m_aggregator.Init(m_config);
      m_filterPipeline.Init(m_config);
      m_cooldownMgr.Init(m_config);
      m_scorer.Init(m_config);
      m_configReady = true;
      RefreshSnapshot("ConfigReady");
     }

public:
   CSignalManager()
      : IManager(), m_pattern(NULL), m_sr(NULL), m_regime(NULL),
        m_signalPending(false), m_lastProcessedBar(0), m_configReady(false)
     {
      m_lastAggregated.Clear();
      m_snapshot.Clear();
     }

   virtual string HandlerName() const override { return "SignalManager"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      EnsureConfigReady();
      RefreshSnapshot("Init");
      return true;
     }

   virtual void Deinit() override
     {
      m_signalPending = false;
      m_cooldownMgr.Clear();
      m_lastAggregated.Clear();
      m_snapshot.Clear();
      IManager::Deinit();
     }

   void SetPatternManager(CPatternManager *p) { m_pattern = p; RefreshSnapshot("PatternManagerBound"); }
   void SetSRManager(CAnalysisSRManager *sr)  { m_sr      = sr; RefreshSnapshot("SRManagerBound"); }
   void SetRegimeManager(CMarketRegime *r)    { m_regime  = r; RefreshSnapshot("RegimeManagerBound"); }

   bool RegisterSource(ISignalSource *src, double weight = 1.0)
     {
      EnsureConfigReady();
      bool ok = m_aggregator.RegisterSource(src, weight);
      RefreshSnapshot(ok ? "SourceRegistered" : "SourceRejected");
      return ok;
     }

   int SourceCount() const { return m_aggregator.SourceCount(); }

   SSignal AggregateSignals()
     {
      EnsureConfigReady();
      SSignal out;
      out.Clear();

      m_lastAggregated = m_aggregator.Aggregate();
      if(m_lastAggregated.vetoed || m_lastAggregated.direction == SIGNAL_NONE)
        {
         RefreshSnapshot(m_lastAggregated.vetoed ? "Vetoed" : "NoSignal");
         return out;
        }

      out.direction     = m_lastAggregated.direction;
      out.confidence    = m_lastAggregated.normalizedScore;
      out.primarySource = m_lastAggregated.contributingSources;
      out.entryPrice    = (m_lastAggregated.direction == SIGNAL_BUY)
                          ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                          : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      out.slPoints      = 0.0;
      out.tpPoints      = 0.0;
      RefreshSnapshot("Aggregated");
      return out;
     }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
      AddEvent(EVENT_ID_PRICE_UPDATE);
      AddEvent(EVENT_ID_ZONE_UPDATE);
      AddEvent(EVENT_ID_EMERGENCY_STOP);
      AddEvent(EVENT_ID_HEARTBEAT);
     }

   virtual void OnPriceUpdate() override {}

   virtual void OnNewBar() override
     {
      if(!m_initialized) return;
      datetime barOpenTime = iTime(_Symbol, _Period, 0);
      if(barOpenTime == 0 || barOpenTime == m_lastProcessedBar) return;
      EnsureConfigReady();
      m_lastProcessedBar = barOpenTime;
      m_cooldownMgr.TickFailedZones();
      RefreshSnapshot("NewBar");
     }

   virtual void OnConfigReload() override
     {
      IManager::OnConfigReload();
      m_config.Init();
      m_aggregator.Init(m_config);
      m_filterPipeline.Init(m_config);
      m_cooldownMgr.Init(m_config);
      m_scorer.Init(m_config);
      m_configReady = true;
      RefreshSnapshot("ConfigReload");
     }

   virtual void OnEvent(const PASREvent &ev) override
     {
      switch(ev.id)
        {
         case EVENT_ID_PRICE_UPDATE:  OnPriceUpdate(); break;
         case EVENT_ID_NEW_BAR:       OnNewBar(); break;
         case EVENT_ID_CONFIG_RELOAD: OnConfigReload(); break;
         case EVENT_ID_EMERGENCY_STOP:
            m_signalPending = false;
            m_lastAggregated.Clear();
            RefreshSnapshot("EmergencyStop");
            if(m_config.GetDebugMode()) Log("Emergency Stop: Clearing pending signals.");
            break;
         case EVENT_ID_HEARTBEAT:
            m_cooldownMgr.CleanupExpired();
            RefreshSnapshot("Heartbeat");
            break;
         default:
            break;
        }
     }

   void NotifyPatternFailure(bool isBuy, double zonePrice)
     {
      m_cooldownMgr.RegisterFailure(isBuy, zonePrice);
      RefreshSnapshot("PatternFailure");
     }

   bool HasPendingSignal(SignalDecision &outSignal)
     {
      if(m_signalPending)
        {
         outSignal       = m_pendingSignal;
         m_signalPending = false;
         RefreshSnapshot("PendingSignalConsumed");
         return true;
        }
      return false;
     }

   const CSignalConfig GetConfig() const { return m_config; }
   AggregatedSignal GetLastAggregated() const { return m_lastAggregated; }
   SignalLayerSnapshot GetSnapshot() const { return m_snapshot; }
   string GetLastVetoReason() const { return m_aggregator.GetVetoReason(); }

   bool IsSignalLayerReady() const
     {
      return (m_configReady && m_aggregator.SourceCount() > 0);
     }

   void PrintDiagnostics() const
     {
      PrintFormat("[SignalManager] ready=%s sources=%d cooldown=%d failedZones=%d lastDir=%d conf=%.3f veto=%s reason=%s",
                  IsSignalLayerReady() ? "true" : "false",
                  m_snapshot.sourceCount,
                  m_snapshot.cooldownCount,
                  m_snapshot.failedZoneCount,
                  (int)m_snapshot.lastDirection,
                  m_snapshot.lastConfidence,
                  m_snapshot.lastVetoed ? "true" : "false",
                  m_snapshot.lastReason);
     }
  };

#endif // __SIGNAL_SIGNAL_MANAGER_MQH__
