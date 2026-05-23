//+------------------------------------------------------------------+
//| Signal/SignalAggregator.mqh — v1.01 (BUG-024 FIXED)             |
//| Signal aggregation with voting, veto, and multiplier logic       |
//|                                                                  |
//| FIX v1.01:                                                       |
//|  BUG-024 — Aggregate() processed sources in raw iteration order. |
//|    A VETO source registered after a VOTER was silently ignored.  |
//|    Fixed: explicit two-pass algorithm:                           |
//|      Pass 1: all VETO sources first (can short-circuit immediately)|
//|      Pass 2: MULT + VOTER sources in registration order          |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_AGGREGATOR_MQH__
#define __SIGNAL_AGGREGATOR_MQH__

#include <Arrays\ArrayObj.mqh>
#include "ISignalSource.mqh"
#include "SignalConfig.mqh"
#include "SignalScorer.mqh"

enum ENUM_SOURCE_TYPE
  {
   SOURCE_TYPE_VOTER  =  1,
   SOURCE_TYPE_MULT   =  0,
   SOURCE_TYPE_VETO   = -1
  };

struct AggregatedSignal
  {
   ENUM_SIGNAL_DIR     direction;
   double              rawScore;
   double              normalizedScore;
   double              multiplierFactor;
   int                 confluence;
   ENUM_SIGNAL_URGENCY urgency;
   string              contributingSources;
   datetime            time;
   bool                vetoed;

   void Clear()
     {
      direction            = SIGNAL_NONE;
      rawScore             = 0.0;
      normalizedScore      = 0.0;
      multiplierFactor     = 1.0;
      confluence           = 0;
      urgency              = SIGNAL_URGENCY_LOW;
      contributingSources  = "";
      time                 = 0;
      vetoed               = false;
     }
  };

class CRegisteredSource
  {
private:
   ISignalSource    *m_source;
   double            m_weight;
   ENUM_SOURCE_TYPE  m_type;

public:
   CRegisteredSource(ISignalSource *src, double weight)
     {
      m_source = src;
      m_weight = weight;
      if(weight > 0.0)      m_type = SOURCE_TYPE_VOTER;
      else if(weight == 0.0) m_type = SOURCE_TYPE_MULT;
      else                   m_type = SOURCE_TYPE_VETO;
     }

   ISignalSource   *GetSource() const { return m_source; }
   double           GetWeight() const { return m_weight; }
   ENUM_SOURCE_TYPE GetType()   const { return m_type;   }

   string GetTypeString() const
     {
      switch(m_type)
        {
         case SOURCE_TYPE_VOTER: return "VOTER";
         case SOURCE_TYPE_MULT:  return "MULT";
         case SOURCE_TYPE_VETO:  return "VETO";
         default:                return "UNKNOWN";
        }
     }
  };

class CSignalAggregator
  {
private:
   CArrayObj              m_sources;
   const CSignalConfig   *m_config;
   CSignalScorer          m_scorer;

   double  m_totalVoterWeight;
   double  m_bullScore;
   double  m_bearScore;
   double  m_multiplierFactor;
   int     m_bullConfluence;
   int     m_bearConfluence;
   string  m_bullSources;
   string  m_bearSources;
   bool    m_vetoActive;

   void ResetState()
     {
      m_totalVoterWeight = 0.0;
      m_bullScore        = 0.0;
      m_bearScore        = 0.0;
      m_multiplierFactor = 1.0;
      m_bullConfluence   = 0;
      m_bearConfluence   = 0;
      m_bullSources      = "";
      m_bearSources      = "";
      m_vetoActive       = false;
     }

   bool ProcessVetoSource(CRegisteredSource *reg, const SignalResult &result)
     {
      if(result.direction == SIGNAL_NONE)
        {
         m_vetoActive = true;
         if(m_config != NULL && m_config.GetDebugMode())
            PrintFormat("[SignalAgg] VETO by %s: %s",
                       reg.GetSource().Name(), result.reason);
         return false;
        }
      return true;
     }

   void ProcessMultiplierSource(CRegisteredSource *reg, const SignalResult &result)
     {
      if(result.confidence > 0.0)
         m_multiplierFactor *= result.confidence;
      if(m_config != NULL && m_config.GetDebugMode())
         PrintFormat("[SignalAgg] MULT %s: x%.2f (%s)",
                    reg.GetSource().Name(), result.confidence, result.reason);
     }

   void ProcessVoterSource(CRegisteredSource *reg, const SignalResult &result)
     {
      double weight = reg.GetWeight();
      m_totalVoterWeight += weight;
      if(result.direction == SIGNAL_BUY)
        {
         m_bullScore += result.confidence * weight;
         m_bullConfluence++;
         m_bullSources += (m_bullSources == "" ? "" : ",") + reg.GetSource().Name();
        }
      else if(result.direction == SIGNAL_SELL)
        {
         m_bearScore += result.confidence * weight;
         m_bearConfluence++;
         m_bearSources += (m_bearSources == "" ? "" : ",") + reg.GetSource().Name();
        }
     }

public:
   CSignalAggregator() : m_config(NULL), m_vetoActive(false) { ResetState(); }

   void Init(const CSignalConfig &config)
     {
      m_config = &config;
      m_scorer.Init(config);
     }

   ~CSignalAggregator() { Clear(); }

   void Clear() { m_sources.Clear(); ResetState(); }

   bool RegisterSource(ISignalSource *source, double weight = 1.0)
     {
      if(source == NULL) return false;
      CRegisteredSource *reg = new CRegisteredSource(source, weight);
      if(reg == NULL) return false;
      m_sources.Add(reg);
      if(m_config != NULL && m_config.GetDebugMode())
         PrintFormat("[SignalAgg] Registered: %s (w=%.1f %s)",
                    source.Name(), weight, reg.GetTypeString());
      return true;
     }

   int SourceCount() const { return m_sources.Total(); }

   // BUG-024 FIX: explicit two-pass aggregation — VETO first, then MULT+VOTER
   AggregatedSignal Aggregate()
     {
      AggregatedSignal agg;
      agg.Clear();
      agg.time = TimeCurrent();
      ResetState();

      // ── Pass 1: VETO sources (can short-circuit immediately) ──────────
      for(int i = 0; i < m_sources.Total(); i++)
        {
         CRegisteredSource *reg = (CRegisteredSource*)m_sources.At(i);
         if(reg == NULL || reg.GetType() != SOURCE_TYPE_VETO) continue;
         if(reg.GetSource() == NULL) continue;

         SignalResult result; result.Clear();
         if(!reg.GetSource().Evaluate(result)) continue;

         if(!ProcessVetoSource(reg, result))
           {
            agg.vetoed = true;
            return agg;  // short-circuit on first veto
           }
        }

      // ── Pass 2: MULT sources (weight the confidence) ──────────────────
      for(int i = 0; i < m_sources.Total(); i++)
        {
         CRegisteredSource *reg = (CRegisteredSource*)m_sources.At(i);
         if(reg == NULL || reg.GetType() != SOURCE_TYPE_MULT) continue;
         if(reg.GetSource() == NULL) continue;

         SignalResult result; result.Clear();
         if(!reg.GetSource().Evaluate(result)) continue;
         ProcessMultiplierSource(reg, result);
        }

      // ── Pass 3: VOTER sources ─────────────────────────────────────────
      for(int i = 0; i < m_sources.Total(); i++)
        {
         CRegisteredSource *reg = (CRegisteredSource*)m_sources.At(i);
         if(reg == NULL || reg.GetType() != SOURCE_TYPE_VOTER) continue;
         if(reg.GetSource() == NULL) continue;

         SignalResult result; result.Clear();
         if(!reg.GetSource().Evaluate(result)) continue;
         ProcessVoterSource(reg, result);
        }

      if(m_totalVoterWeight <= 0.0) return agg;

      double normBull = (m_bullScore / m_totalVoterWeight) * m_multiplierFactor;
      double normBear = (m_bearScore / m_totalVoterWeight) * m_multiplierFactor;

      if(m_config != NULL && m_config.GetDebugMode())
         PrintFormat("[SignalAgg] Scores BUY=%.3f SELL=%.3f (x%.2f mult)",
                    normBull, normBear, m_multiplierFactor);

      int    minConfluence = (m_config != NULL) ? m_config.GetMinConfluence() : 2;
      double minScore      = (m_config != NULL) ? m_config.GetMinScore()      : 0.45;

      if(normBull > normBear && m_bullConfluence >= minConfluence && normBull >= minScore)
        {
         agg.direction           = SIGNAL_BUY;
         agg.rawScore            = m_bullScore;
         agg.normalizedScore     = normBull;
         agg.multiplierFactor    = m_multiplierFactor;
         agg.confluence          = m_bullConfluence;
         agg.contributingSources = m_bullSources;
         agg.urgency             = m_scorer.GetUrgencyLevel(normBull);
        }
      else if(normBear > normBull && m_bearConfluence >= minConfluence && normBear >= minScore)
        {
         agg.direction           = SIGNAL_SELL;
         agg.rawScore            = m_bearScore;
         agg.normalizedScore     = normBear;
         agg.multiplierFactor    = m_multiplierFactor;
         agg.confluence          = m_bearConfluence;
         agg.contributingSources = m_bearSources;
         agg.urgency             = m_scorer.GetUrgencyLevel(normBear);
        }

      return agg;
     }

   bool   IsVetoActive()         const { return m_vetoActive;       }
   double GetTotalVoterWeight()  const { return m_totalVoterWeight; }
   double GetMultiplierFactor()  const { return m_multiplierFactor; }
  };

#endif // __SIGNAL_AGGREGATOR_MQH__
