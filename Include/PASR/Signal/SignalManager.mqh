//+------------------------------------------------------------------+
//| Signal/SignalManager.mqh — v2.00                                 |
//| Weighted-vote signal aggregation with pluggable ISignalSource.   |
//| Replaces root ../5.SignalManager.mqh stub.                       |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_SIGNAL_MANAGER_MQH__
#define __SIGNAL_SIGNAL_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "ISignalSource.mqh"
#include "SignalFilter.mqh"
#include "../Pattern/PatternManager.mqh"
#include "../Data/SRManager.mqh"
#include "../Data/MarketRegime.mqh"

#define SIGNAL_MAX_SOURCES 8

// Final signal state emitted by SignalManager
struct FinalSignal
  {
   ENUM_SIGNAL_DIR direction;
   double          score;        // 0.0-1.0 aggregate weighted score
   double          confidence;   // same as score (alias for downstream)
   int             confluence;   // count of agreeing sources
   string          sources;      // names of agreeing sources
   datetime        time;

   void Clear()
     { direction=SIGNAL_NONE; score=0; confidence=0; confluence=0; sources=""; time=0; }
  };

//+------------------------------------------------------------------+
//| CSignalManager — aggregates multiple ISignalSource votes         |
//+------------------------------------------------------------------+
class CSignalManager : public IManager
  {
private:
   ISignalSource   *m_sources[SIGNAL_MAX_SOURCES];
   int              m_sourceCount;
   double           m_weights[SIGNAL_MAX_SOURCES];

   CPatternManager *m_pattern;
   CSRManager      *m_sr;
   CMarketRegime   *m_regime;
   CSignalFilter   *m_filter;

   FinalSignal      m_current;
   FinalSignal      m_previous;
   bool             m_signalReady;

   // Minimum confluence count required to emit a signal
   int              m_minConfluence;
   // Minimum aggregate score required
   double           m_minScore;

   FinalSignal AggregateVotes()
     {
      FinalSignal sig;
      sig.Clear();
      sig.time = TimeCurrent();

      double bullScore = 0.0, bearScore = 0.0;
      double totalWeight = 0.0;
      int    bullCount   = 0, bearCount = 0;
      string bullSrc="", bearSrc="";

      for(int i = 0; i < m_sourceCount; i++)
        {
         if(m_sources[i] == NULL) continue;
         SignalResult r; r.Clear();
         if(!m_sources[i].Evaluate(r)) continue;

         double w = m_weights[i];
         totalWeight += w;

         if(r.direction == SIGNAL_BUY)
           { bullScore += r.confidence * w; bullCount++;
             bullSrc += (bullSrc=="" ? "" : ",") + m_sources[i].Name(); }
         else if(r.direction == SIGNAL_SELL)
           { bearScore += r.confidence * w; bearCount++;
             bearSrc += (bearSrc=="" ? "" : ",") + m_sources[i].Name(); }
        }

      if(totalWeight <= 0) return sig;

      double normBull = bullScore / totalWeight;
      double normBear = bearScore / totalWeight;

      if(normBull > normBear && bullCount >= m_minConfluence && normBull >= m_minScore)
        { sig.direction=SIGNAL_BUY;  sig.score=normBull; sig.confidence=normBull;
          sig.confluence=bullCount;  sig.sources=bullSrc; }
      else if(normBear > normBull && bearCount >= m_minConfluence && normBear >= m_minScore)
        { sig.direction=SIGNAL_SELL; sig.score=normBear; sig.confidence=normBear;
          sig.confluence=bearCount;  sig.sources=bearSrc; }

      return sig;
     }

public:
   CSignalManager()
      : IManager(), m_sourceCount(0), m_pattern(NULL),
        m_sr(NULL), m_regime(NULL), m_filter(NULL),
        m_signalReady(false), m_minConfluence(2), m_minScore(0.45)
     {
      ArrayInitialize(m_weights, 1.0);
      for(int i=0;i<SIGNAL_MAX_SOURCES;i++) m_sources[i]=NULL;
      m_current.Clear(); m_previous.Clear();
     }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      if(m_filter != NULL) delete m_filter;
      m_filter = new CSignalFilter(&m_cfg, data);
      return true;
     }

   ~CSignalManager()
     { if(m_filter != NULL) { delete m_filter; m_filter=NULL; } }

   // Inject manager dependencies (called from Orchestrator)
   void SetPatternManager(CPatternManager *p) { m_pattern = p; }
   void SetSRManager(CSRManager *sr)           { m_sr      = sr; }
   void SetRegimeManager(CMarketRegime *r)     { m_regime  = r; }

   // Register a signal source plugin
   bool RegisterSource(ISignalSource *src, double weight=1.0)
     {
      if(m_sourceCount >= SIGNAL_MAX_SOURCES) return false;
      m_sources[m_sourceCount] = src;
      m_weights[m_sourceCount] = weight;
      m_sourceCount++;
      return true;
     }

   void SetMinConfluence(int v) { m_minConfluence = MathMax(1, v); }
   void SetMinScore(double v)   { m_minScore      = MathMax(0.0, MathMin(1.0, v)); }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
     }

   virtual void OnNewBar() override
     {
      m_signalReady = false;
      m_previous    = m_current;
      m_current.Clear();

      // 1) Run filter chain
      if(m_filter != NULL)
        {
         FilterResult fr = m_filter.Run();
         if(!fr.passed)
           {
            if(m_debugMode) PrintFormat("[Signal] Filtered: %s", fr.reason);
            return;
           }
        }

      // 2) Aggregate all registered sources
      m_current = AggregateVotes();

      if(m_current.direction != SIGNAL_NONE)
        {
         m_signalReady = true;
         if(m_debugMode)
            PrintFormat("[Signal] %s score=%.2f confluence=%d sources=%s",
                        (m_current.direction==SIGNAL_BUY?"BUY":"SELL"),
                        m_current.score, m_current.confluence, m_current.sources);

         PASREvent ev;
         ev.id       = EVENT_ID_SIGNAL_READY;
         ev.priority = 30;
         DispatchEvent(ev);
        }
     }

   FinalSignal GetCurrent()  const { return m_current; }
   FinalSignal GetPrevious() const { return m_previous; }
   bool        HasSignal()   const { return m_signalReady; }
  };

typedef CSignalManager SignalManager;
#endif
