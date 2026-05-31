//+------------------------------------------------------------------+
//| Signal/SignalManager.mqh — v4.07                                |
//| Compile-safe signal orchestration adapter                         |
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

public:
   CSignalManager()
      : IManager(), m_pattern(NULL), m_sr(NULL), m_regime(NULL),
        m_signalPending(false), m_lastProcessedBar(0), m_configReady(false)
     {}

   virtual string HandlerName() const override { return "SignalManager"; }

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
      IManager::Deinit();
     }

   void SetPatternManager(CPatternManager *p) { m_pattern = p; }
   void SetSRManager(CAnalysisSRManager *sr)  { m_sr      = sr; }
   void SetRegimeManager(CMarketRegime *r)    { m_regime  = r; }

   bool RegisterSource(ISignalSource *src, double weight = 1.0)
     { return m_aggregator.RegisterSource(src, weight); }

   int SourceCount() const { return m_aggregator.SourceCount(); }

   SSignal AggregateSignals()
     {
      EnsureConfigReady();
      SSignal out;
      out.Clear();
      AggregatedSignal agg = m_aggregator.Aggregate();
      if(agg.vetoed || agg.direction == SIGNAL_NONE) return out;
      out.direction     = agg.direction;
      out.confidence    = agg.normalizedScore;
      out.primarySource = agg.contributingSources;
      out.entryPrice    = (agg.direction == SIGNAL_BUY)
                          ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                          : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      out.slPoints      = 0.0;
      out.tpPoints      = 0.0;
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
            if(m_config.GetDebugMode()) Log("Emergency Stop: Clearing pending signals.");
            break;
         case EVENT_ID_HEARTBEAT:
            m_cooldownMgr.CleanupExpired();
            break;
         default:
            break;
        }
     }

   void NotifyPatternFailure(bool isBuy, double zonePrice)
     { m_cooldownMgr.RegisterFailure(isBuy, zonePrice); }

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

   const CSignalConfig GetConfig() const { return m_config; }
  };

#endif // __SIGNAL_SIGNAL_MANAGER_MQH__
