//+------------------------------------------------------------------+
//| Signal/SignalManager.mqh — v4.05                                |
//| Signal orchestration using canonical PASREvent model             |
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

class CPatternManager;
class CSRManager;
class CMarketRegime;

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
      atrPoints=0.0; support=0.0; resistance=0.0;
      htfSupport=0.0; htfResistance=0.0;
      isSupBroken=false; isResBroken=false;
      supBufferMult=1.0; resBufferMult=1.0;
      supHtfAlign=0; resHtfAlign=0;
     }
  };

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
   bool                    m_configReady;

   bool FetchCandleBatch(int shiftStart, int count, MqlRates &outRates[])
     {
      ArraySetAsSeries(outRates, true);
      int copied = CopyRates(_Symbol, _Period, shiftStart, count, outRates);
      return (copied >= count);
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
     }

   void DispatchSignalEvent(SignalDecision &decision, double atrPoints,
                            double support, double resistance)
     {
      if(m_bus == NULL)
        {
         if(m_debugMode) Print("[SignalManager] m_bus NULL, cannot dispatch signal");
         return;
        }

      PASREvent ev;
      ev.id       = EVENT_SIGNAL_GENERATED;
      ev.priority = 40;
      ev.data1    = decision.signalPrice;
      ev.data2    = atrPoints;
      ev.tag      = StringFormat("%s|support=%.5f|resistance=%.5f|pattern=%d|shift=%d|%s",
                    decision.orderType == ORDER_TYPE_BUY ? "BUY" : "SELL",
                    support, resistance, (int)decision.patternType,
                    decision.signalShift, decision.reason);
      ev.comment  = ev.tag;
      ev.ticket   = (ulong)decision.orderType;
      m_bus.DispatchImmediate(ev);
     }

   void ProcessSignalOnNewBar(datetime barOpenTime)
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
         DispatchSignalEvent(decision, atrPoints, support, resistance);
         ENUM_SIGNAL_DIR dir = (decision.orderType == ORDER_TYPE_BUY) ? SIGNAL_BUY : SIGNAL_SELL;
         m_cooldownMgr.RegisterSignalCooldown(decision.signalPrice, dir);
         m_pendingSignal = decision;
         m_signalPending = true;
        }
     }

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

         double zonePrice       = (dir == 1) ? support : resistance;
         double currentBufMult  = (dir == 1) ? supBufferMult : resBufferMult;
         int    currentHtfAlign = (dir == 1) ? supHtfAlign   : resHtfAlign;

         if(m_config.GetUseMTF() && currentHtfAlign < 0)
           { reason = (dir == 1) ? "HTF Contra-Support" : "HTF Contra-Resistance"; continue; }

         if((dir == 1 && isSupBroken) || (dir == -1 && isResBroken))
           { reason = "Zone broken"; continue; }

         FilterResult filterResult;
         if(!m_filterPipeline.RunCompletePipeline(
               shift, dir, zonePrice, signalPrice,
               atrPoints, htfSupport, htfResistance,
               currentBufMult, support, resistance,
               filterResult, rates))
           { reason = filterResult.reason; continue; }

         ENUM_SIGNAL_DIR signalDir = (dir == 1) ? SIGNAL_BUY : SIGNAL_SELL;

         if(m_cooldownMgr.IsZoneReuseBlocked(dir == 1, zonePrice, atrPoints))
           { reason = "Zone reuse blocked"; continue; }

         if(m_cooldownMgr.IsPatternFailureBlocked(dir == 1, zonePrice, atrPoints))
           { reason = "Level failure cooldown"; continue; }

         if(m_cooldownMgr.IsSignalCooldownActive(signalPrice, signalDir, atrPoints))
           { reason = "Signal cooldown active"; continue; }

         decision.valid       = true;
         decision.orderType   = (dir == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         decision.signalPrice = signalPrice;
         decision.patternType = pType;
         decision.zonePrice   = zonePrice;
         decision.signalShift = shift;
         decision.reason      = patternReason +
                                (filterResult.reason != "" ? " | " + filterResult.reason : "");

         m_cooldownMgr.RegisterZoneUse(dir == 1, zonePrice);

         if(m_config.GetDebugMode())
            PrintFormat("[PASR Signal] %s @ %.5f | Pattern: %s | %s",
                       (dir == 1 ? "BUY" : "SELL"), signalPrice,
                       EnumToString(pType), decision.reason);

         return true;
        }

      decision.reason = (reason == "") ? "No signal" : reason;
      return false;
     }

   void ApplyZoneUpdate(const PASREvent &ev)
     {
      if(ev.data1 > 0.0) m_marketData.atrPoints = ev.data1;
      if(ev.data2 > 0.0) m_marketData.support = ev.data2;
      double res = StringToDouble(ev.tag);
      if(res > 0.0) m_marketData.resistance = res;
     }

public:
   CSignalManager()
      : IManager(), m_pattern(NULL), m_sr(NULL), m_regime(NULL),
        m_signalPending(false), m_lastProcessedBar(0),
        m_hasNewTick(false), m_configReady(false)
     { m_marketData.Reset(); }

   virtual string HandlerName() const override { return "SignalManager"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      EnsureConfigReady();
      if(m_bus != NULL) m_bus.Subscribe(this);
      return true;
     }

   virtual void Deinit() override
     {
      m_signalPending = false;
      m_cooldownMgr.Clear();
      IManager::Deinit();
     }

   void SetPatternManager(CPatternManager *p) { m_pattern = p; }
   void SetSRManager(CSRManager *sr)           { m_sr      = sr; }
   void SetRegimeManager(CMarketRegime *r)     { m_regime  = r; }

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

   virtual void OnPriceUpdate() override
     {
      SymbolInfoTick(_Symbol, m_cachedTick);
      m_hasNewTick = true;
     }

   virtual void OnNewBar() override
     {
      if(!m_initialized) return;
      datetime barOpenTime = iTime(_Symbol, _Period, 0);
      if(barOpenTime == 0 || barOpenTime == m_lastProcessedBar) return;
      if(!m_hasNewTick) OnPriceUpdate();
      EnsureConfigReady();
      ProcessSignalOnNewBar(barOpenTime);
      m_lastProcessedBar = barOpenTime;
      m_hasNewTick = false;
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
         case EVENT_ID_ZONE_UPDATE:   ApplyZoneUpdate(ev); break;
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

   const CSignalConfig& GetConfig() const { return m_config; }
  };

typedef CSignalManager SignalManager;
#endif // __SIGNAL_SIGNAL_MANAGER_MQH__
