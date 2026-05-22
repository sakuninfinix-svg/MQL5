//+------------------------------------------------------------------+
//| Signal/SignalManager.mqh — v3.00                                 |
//| Weighted-vote + veto + confidence-multiplier signal aggregation. |
//|                                                                  |
//| SIGNAL SOURCE TYPES (determined by weight parameter):            |
//|   weight > 0  : VOTER   — direction + confidence contribute to   |
//|                           weighted score                         |
//|   weight = 0  : MULT    — direction==NONE, confidence is a       |
//|                           multiplier applied to total score      |
//|   weight < 0  : VETO    — direction==NONE from this source        |
//|                           SUPPRESSES the entire aggregation       |
//|                           (used by RegimeSignalSource VETO mode) |
//|                                                                  |
//| URGENCY TIERS:                                                   |
//|   HIGH   : score >= 0.75  (strong confluence, execute promptly)  |
//|   MEDIUM : score >= 0.55  (good signal, normal execution)        |
//|   LOW    : score <  0.55  (weak, filtered out by default)        |
//|                                                                  |
//| SIGNAL COOLDOWN:                                                 |
//|   After a signal fires in direction D, same direction is blocked |
//|   for N bars (configurable, default=3). Prevents double entries. |
//|                                                                  |
//| CHANGE LOG:                                                      |
//|  v3.00 (2026-05-21) — Phase 4 enhancements:                     |
//|    + Veto source support (weight < 0)                            |
//|    + Confidence multiplier sources (weight == 0)                 |
//|    + Urgency tier (HIGH/MEDIUM/LOW)                              |
//|    + Signal cooldown (N bars, configurable)                      |
//|    + Per-source vote table in debug mode                         |
//|    + SetCooldownBars() accessor                                  |
//|  v2.00 (2026-05-20) — ISignalSource plugin system               |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_SIGNAL_MANAGER_MQH__
#define __SIGNAL_SIGNAL_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "ISignalSource.mqh"
#include "SignalFilter.mqh"
#include "../Analysis/Pattern/PatternManager.mqh"
#include "../Data/SRStruct.mqh"
#include "../Data/MarketRegime.mqh"

#define SIGNAL_MAX_SOURCES 12   // raised from 8 to accommodate all Phase 3+4 sources

enum ENUM_SIGNAL_URGENCY
  {
   SIGNAL_URGENCY_HIGH   = 0,   // score >= 0.75
   SIGNAL_URGENCY_MEDIUM = 1,   // score >= 0.55
   SIGNAL_URGENCY_LOW    = 2    // score <  0.55 (filtered by default)
  };

// Final signal state emitted by SignalManager
struct FinalSignal
  {
   ENUM_SIGNAL_DIR     direction;
   double              score;        // 0.0-1.0 aggregate weighted score
   double              confidence;   // alias for score (backward-compat)
   int                 confluence;   // count of agreeing voter sources
   ENUM_SIGNAL_URGENCY urgency;      // HIGH / MEDIUM / LOW
   string              sources;      // names of agreeing sources
   datetime            time;

   void Clear()
     {
      direction=SIGNAL_NONE; score=0; confidence=0; confluence=0;
      urgency=SIGNAL_URGENCY_LOW; sources=""; time=0;
     }
  };

//+------------------------------------------------------------------+
//| CSignalManager — aggregates multiple ISignalSource votes         |
//+------------------------------------------------------------------+
class CSignalManager : public IManager
  {
private:
   ISignalSource   *m_sources[SIGNAL_MAX_SOURCES];
   int              m_sourceCount;
   double           m_weights[SIGNAL_MAX_SOURCES];  // >0=voter, 0=mult, <0=veto

   CPatternManager *m_pattern;
   CSRManager      *m_sr;
   CMarketRegime   *m_regime;
   CSignalFilter   *m_filter;

   FinalSignal      m_current;
   FinalSignal      m_previous;
   bool             m_signalReady;

   int              m_minConfluence;   // min voter sources that must agree
   double           m_minScore;        // min normalised weighted score (0-1)
   int              m_cooldownBars;    // bars before same direction repeatable
   int              m_barsSinceSignal; // counter: incremented each OnNewBar()
   ENUM_SIGNAL_DIR  m_lastDirection;  // direction of last emitted signal

   // ── Urgency helper ──────────────────────────────────────────────
   ENUM_SIGNAL_URGENCY ScoreToUrgency(double score) const
     {
      if(score >= 0.75) return SIGNAL_URGENCY_HIGH;
      if(score >= 0.55) return SIGNAL_URGENCY_MEDIUM;
      return SIGNAL_URGENCY_LOW;
     }

   // ── Core aggregation ─────────────────────────────────────────────
   FinalSignal AggregateVotes()
     {
      FinalSignal sig;
      sig.Clear();
      sig.time = TimeCurrent();

      double bullScore   = 0.0, bearScore  = 0.0;
      double totalVoterW = 0.0;
      double multFactor  = 1.0;   // product of all multiplier confidences
      int    bullCount   = 0,    bearCount  = 0;
      string bullSrc     = "",   bearSrc    = "";

      for(int i = 0; i < m_sourceCount; i++)
        {
         if(m_sources[i] == NULL) continue;

         SignalResult r; r.Clear();
         if(!m_sources[i].Evaluate(r)) continue;

         double w = m_weights[i];

         // ── VETO source (weight < 0): if it returns NONE, suppress all
         if(w < 0.0)
           {
            if(r.direction == SIGNAL_NONE)
              {
               if(m_debugMode)
                  PrintFormat("[Signal] VETO by %s: %s",
                              m_sources[i].Name(), r.reason);
               return sig;   // early return: fully suppressed
              }
            continue;   // veto source voted a direction = no veto, skip weight
           }

         // ── MULTIPLIER source (weight == 0): direction ignored, confidence scales total
         if(w == 0.0)
           {
            if(r.confidence > 0.0) multFactor *= r.confidence;
            if(m_debugMode)
               PrintFormat("[Signal]   MULT %s: x%.2f (%s)",
                           m_sources[i].Name(), r.confidence, r.reason);
            continue;
           }

         // ── VOTER source (weight > 0): normal weighted contribution
         totalVoterW += w;

         if(r.direction == SIGNAL_BUY)
           {
            bullScore += r.confidence * w;
            bullCount++;
            bullSrc += (bullSrc=="" ? "" : ",") + m_sources[i].Name();
           }
         else if(r.direction == SIGNAL_SELL)
           {
            bearScore += r.confidence * w;
            bearCount++;
            bearSrc += (bearSrc=="" ? "" : ",") + m_sources[i].Name();
           }

         if(m_debugMode)
            PrintFormat("[Signal]   VOTE %s(w=%.1f): %s conf=%.2f %s",
                        m_sources[i].Name(), w,
                        r.direction==SIGNAL_BUY ? "BUY" :
                        r.direction==SIGNAL_SELL? "SELL": "NONE",
                        r.confidence, r.reason);
        }

      if(totalVoterW <= 0.0) return sig;

      // Normalise + apply multiplier
      double normBull = (bullScore / totalVoterW) * multFactor;
      double normBear = (bearScore / totalVoterW) * multFactor;

      if(m_debugMode)
         PrintFormat("[Signal] Scores  BUY=%.3f SELL=%.3f (x%.2f mult)",
                     normBull, normBear, multFactor);

      // Determine winner
      if(normBull > normBear
         && bullCount  >= m_minConfluence
         && normBull   >= m_minScore)
        {
         sig.direction  = SIGNAL_BUY;
         sig.score      = normBull;
         sig.confidence = normBull;
         sig.confluence = bullCount;
         sig.sources    = bullSrc;
         sig.urgency    = ScoreToUrgency(normBull);
        }
      else if(normBear > normBull
              && bearCount  >= m_minConfluence
              && normBear   >= m_minScore)
        {
         sig.direction  = SIGNAL_SELL;
         sig.score      = normBear;
         sig.confidence = normBear;
         sig.confluence = bearCount;
         sig.sources    = bearSrc;
         sig.urgency    = ScoreToUrgency(normBear);
        }

      return sig;
     }

   // ── Cooldown check ───────────────────────────────────────────────
   bool IsCoolingDown(ENUM_SIGNAL_DIR dir) const
     {
      if(m_cooldownBars <= 0) return false;
      if(dir != m_lastDirection) return false;   // different direction = OK
      return (m_barsSinceSignal < m_cooldownBars);
     }

public:
   CSignalManager()
      : IManager(), m_sourceCount(0),
        m_pattern(NULL), m_sr(NULL), m_regime(NULL), m_filter(NULL),
        m_signalReady(false),
        m_minConfluence(2), m_minScore(0.45),
        m_cooldownBars(3), m_barsSinceSignal(999),
        m_lastDirection(SIGNAL_NONE)
     {
      ArrayInitialize(m_weights, 1.0);
      for(int i=0;i<SIGNAL_MAX_SOURCES;i++) m_sources[i]=NULL;
      m_current.Clear(); m_previous.Clear();
     }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      if(m_filter != NULL) { delete m_filter; m_filter=NULL; }
      m_filter = new CSignalFilter(&m_cfg, data);
      return true;
     }

   ~CSignalManager()
     { if(m_filter != NULL) { delete m_filter; m_filter=NULL; } }

   // ── Dependency injection
   void SetPatternManager(CPatternManager *p) { m_pattern = p; }
   void SetSRManager(CSRManager *sr)           { m_sr      = sr; }
   void SetRegimeManager(CMarketRegime *r)     { m_regime  = r; }

   // ── Register a signal source plugin
   // weight >0 = voter, =0 = multiplier, <0 = veto
   bool RegisterSource(ISignalSource *src, double weight=1.0)
     {
      if(m_sourceCount >= SIGNAL_MAX_SOURCES) return false;
      m_sources[m_sourceCount] = src;
      m_weights[m_sourceCount] = weight;
      m_sourceCount++;
      if(m_debugMode)
         PrintFormat("[Signal] Registered: %s (w=%.1f %s)",
                     src.Name(), weight,
                     weight<0 ? "VETO" : weight==0 ? "MULT" : "VOTER");
      return true;
     }

   // ── Configuration
   void SetMinConfluence(int v)    { m_minConfluence = MathMax(1, v); }
   void SetMinScore(double v)      { m_minScore      = MathMax(0.0, MathMin(1.0, v)); }
   void SetCooldownBars(int v)     { m_cooldownBars  = MathMax(0, v); }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
     }

   virtual void OnNewBar() override
     {
      m_barsSinceSignal++;
      m_signalReady = false;
      m_previous    = m_current;
      m_current.Clear();

      // 1) Pre-filter chain (session, spread, news, etc.)
      if(m_filter != NULL)
        {
         FilterResult fr = m_filter.Run();
         if(!fr.passed)
           {
            if(m_debugMode)
               PrintFormat("[Signal] PreFilter blocked: %s", fr.reason);
            return;
           }
        }

      if(m_debugMode)
         PrintFormat("[Signal] OnNewBar — evaluating %d sources:", m_sourceCount);

      // 2) Aggregate all registered sources (veto → mult → voters)
      m_current = AggregateVotes();

      if(m_current.direction == SIGNAL_NONE) return;

      // 3) Urgency filter: only emit MEDIUM+ by default
      if(m_current.urgency == SIGNAL_URGENCY_LOW)
        {
         if(m_debugMode)
            PrintFormat("[Signal] Score=%.2f below MEDIUM threshold (0.55) — suppressed",
                        m_current.score);
         m_current.Clear();
         return;
        }

      // 4) Cooldown: suppress same direction within N bars
      if(IsCoolingDown(m_current.direction))
        {
         if(m_debugMode)
            PrintFormat("[Signal] Cooldown: %s again in %d/%d bars — suppressed",
                        m_current.direction==SIGNAL_BUY?"BUY":"SELL",
                        m_barsSinceSignal, m_cooldownBars);
         m_current.Clear();
         return;
        }

      // 5) Signal is valid — emit
      m_signalReady         = true;
      m_lastDirection       = m_current.direction;
      m_barsSinceSignal     = 0;

      PrintFormat("[Signal] ★ %s score=%.2f urgency=%s confluence=%d src=[%s]",
                  m_current.direction==SIGNAL_BUY ? "BUY" : "SELL",
                  m_current.score,
                  m_current.urgency==SIGNAL_URGENCY_HIGH   ? "HIGH"   :
                  m_current.urgency==SIGNAL_URGENCY_MEDIUM ? "MEDIUM" : "LOW",
                  m_current.confluence, m_current.sources);

      PASREvent ev;
      ev.id       = EVENT_ID_SIGNAL_READY;
      ev.priority = 30;
      DispatchEvent(ev);
     }

   // ── Accessors
   FinalSignal GetCurrent()  const { return m_current;     }
   FinalSignal GetPrevious() const { return m_previous;    }
   bool        HasSignal()   const { return m_signalReady; }
   int         SourceCount() const { return m_sourceCount; }
  };

typedef CSignalManager SignalManager;
#endif // __SIGNAL_SIGNAL_MANAGER_MQH__
