//+------------------------------------------------------------------+
//| Signal/SignalAggregator.mqh — v1.20                              |
//| Signal aggregation with voting, veto, multiplier, diagnostics     |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_AGGREGATOR_MQH__
#define __SIGNAL_AGGREGATOR_MQH__

#include "ISignalSource.mqh"
#include "SignalConfig.mqh"
#include "SignalScorer.mqh"

#define PASR_MAX_SIGNAL_SOURCES 32

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

struct SignalAggregatorSnapshot
  {
   int     sourceCount;
   int     voterCount;
   int     multiplierCount;
   int     vetoCount;
   int     staleSourceCount;
   double  totalVoterWeight;
   double  bullScore;
   double  bearScore;
   double  conflictScore;
   double  dominanceGap;
   double  multiplierFactor;
   int     bullConfluence;
   int     bearConfluence;
   bool    vetoActive;
   bool    vetoBuy;
   bool    vetoSell;
   string  vetoReason;
   string  bullSources;
   string  bearSources;
   string  lastDecisionReason;

   void Clear()
     {
      sourceCount = 0;
      voterCount = 0;
      multiplierCount = 0;
      vetoCount = 0;
      staleSourceCount = 0;
      totalVoterWeight = 0.0;
      bullScore = 0.0;
      bearScore = 0.0;
      conflictScore = 0.0;
      dominanceGap = 0.0;
      multiplierFactor = 1.0;
      bullConfluence = 0;
      bearConfluence = 0;
      vetoActive = false;
      vetoBuy = false;
      vetoSell = false;
      vetoReason = "";
      bullSources = "";
      bearSources = "";
      lastDecisionReason = "";
     }
  };

class CRegisteredSource
  {
private:
   ISignalSource    *m_source;
   double            m_weight;
   ENUM_SOURCE_TYPE  m_type;

public:
   CRegisteredSource()
     {
      m_source = NULL;
      m_weight = 0.0;
      m_type = SOURCE_TYPE_MULT;
     }

   void Init(ISignalSource *src, double weight)
     {
      m_source = src;
      m_weight = weight;
      if(weight > 0.0)       m_type = SOURCE_TYPE_VOTER;
      else if(weight == 0.0) m_type = SOURCE_TYPE_MULT;
      else                  m_type = SOURCE_TYPE_VETO;
     }

   ISignalSource   *GetSource() const { return m_source; }
   double           GetWeight() const { return m_weight; }
   ENUM_SOURCE_TYPE GetType()   const { return m_type;   }

   string GetName() const
     {
      if(m_source == NULL) return "NULL";
      return m_source.Name();
     }

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
   CRegisteredSource  m_sources[PASR_MAX_SIGNAL_SOURCES];
   int                m_sourceCount;
   const CSignalConfig *m_config;
   CSignalScorer      m_scorer;
   SignalAggregatorSnapshot m_snapshot;

   double  m_totalVoterWeight;
   double  m_bullScore;
   double  m_bearScore;
   double  m_multiplierFactor;
   int     m_bullConfluence;
   int     m_bearConfluence;
   string  m_bullSources;
   string  m_bearSources;
   bool    m_vetoActive;
   bool    m_vetoBuy;
   bool    m_vetoSell;
   string  m_vetoReason;
   string  m_lastDecisionReason;
   int     m_staleSourceCount;

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
      m_vetoBuy          = false;
      m_vetoSell         = false;
      m_vetoReason       = "";
      m_lastDecisionReason = "";
      m_staleSourceCount = 0;
     }

   void RefreshSnapshot()
     {
      m_snapshot.Clear();
      m_snapshot.sourceCount = m_sourceCount;
      for(int i = 0; i < m_sourceCount; i++)
        {
         ENUM_SOURCE_TYPE t = m_sources[i].GetType();
         if(t == SOURCE_TYPE_VOTER) m_snapshot.voterCount++;
         else if(t == SOURCE_TYPE_MULT) m_snapshot.multiplierCount++;
         else if(t == SOURCE_TYPE_VETO) m_snapshot.vetoCount++;
        }
      m_snapshot.totalVoterWeight = m_totalVoterWeight;
      m_snapshot.staleSourceCount = m_staleSourceCount;
      m_snapshot.bullScore = m_bullScore;
      m_snapshot.bearScore = m_bearScore;
      m_snapshot.conflictScore = MathMin(m_bullScore, m_bearScore);
      m_snapshot.dominanceGap = MathAbs(m_bullScore - m_bearScore);
      m_snapshot.multiplierFactor = m_multiplierFactor;
      m_snapshot.bullConfluence = m_bullConfluence;
      m_snapshot.bearConfluence = m_bearConfluence;
      m_snapshot.vetoActive = m_vetoActive;
      m_snapshot.vetoBuy = m_vetoBuy;
      m_snapshot.vetoSell = m_vetoSell;
      m_snapshot.vetoReason = m_vetoReason;
      m_snapshot.bullSources = m_bullSources;
      m_snapshot.bearSources = m_bearSources;
      m_snapshot.lastDecisionReason = m_lastDecisionReason;
     }

   bool IsFresh(SignalResult &result, const string sourceName)
     {
      if(result.evaluatedAt == 0)
        {
         result.evaluatedAt = TimeCurrent();
         return true;
        }
      int maxAge = (m_config != NULL) ? m_config.GetMaxSourceAgeSeconds() : 120;
      if(maxAge <= 0) return true;
      int age = (int)(TimeCurrent() - result.evaluatedAt);
      if(age <= maxAge) return true;
      m_staleSourceCount++;
      if(m_lastDecisionReason == "")
         m_lastDecisionReason = StringFormat("Stale signal source ignored: %s age=%d max=%d",
                                             sourceName, age, maxAge);
      if(m_config != NULL && m_config.GetDebugMode())
         PrintFormat("[SignalAgg] STALE %s: age=%d max=%d", sourceName, age, maxAge);
      return false;
     }

   bool ProcessVetoSource(int idx, SignalResult &result)
     {
      if(idx < 0 || idx >= m_sourceCount) return true;
      ISignalSource *src = m_sources[idx].GetSource();
      string name = (src != NULL) ? src.Name() : "VETO";
      if(result.direction == SIGNAL_NONE)
        {
         m_vetoActive = true;
         m_vetoReason = StringFormat("%s:%s", name, result.reason);
         m_lastDecisionReason = "Hard veto: " + m_vetoReason;
         if(m_config != NULL && m_config.GetDebugMode())
            PrintFormat("[SignalAgg] VETO by %s: %s", name, result.reason);
         return false;
        }
      if(result.direction == SIGNAL_BUY)
        {
         m_vetoSell = true;
         if(m_vetoReason == "") m_vetoReason = StringFormat("%s:BUY", name);
        }
      else if(result.direction == SIGNAL_SELL)
        {
         m_vetoBuy = true;
         if(m_vetoReason == "") m_vetoReason = StringFormat("%s:SELL", name);
        }
      return true;
     }

   void ApplyContraVeto(AggregatedSignal &agg)
     {
      if(agg.direction == SIGNAL_BUY && m_vetoBuy)
        {
         agg.Clear();
         agg.time = TimeCurrent();
         agg.vetoed = true;
         m_vetoActive = true;
         m_lastDecisionReason = "Contra veto blocked BUY: " + m_vetoReason;
        }
      else if(agg.direction == SIGNAL_SELL && m_vetoSell)
        {
         agg.Clear();
         agg.time = TimeCurrent();
         agg.vetoed = true;
         m_vetoActive = true;
         m_lastDecisionReason = "Contra veto blocked SELL: " + m_vetoReason;
        }
     }

   void ProcessMultiplierSource(int idx, SignalResult &result)
     {
      if(result.confidence > 0.0)
         m_multiplierFactor *= result.confidence;
      ISignalSource *src = m_sources[idx].GetSource();
      if(m_config != NULL && m_config.GetDebugMode() && src != NULL)
         PrintFormat("[SignalAgg] MULT %s: x%.2f (%s)", src.Name(), result.confidence, result.reason);
     }

   void ProcessVoterSource(int idx, SignalResult &result)
     {
      ISignalSource *src = m_sources[idx].GetSource();
      if(src == NULL) return;
      double weight = m_sources[idx].GetWeight();
      m_totalVoterWeight += weight;
      if(result.direction == SIGNAL_BUY)
        {
         m_bullScore += result.confidence * weight;
         m_bullConfluence++;
         m_bullSources += (m_bullSources == "" ? "" : ",") + src.Name();
        }
      else if(result.direction == SIGNAL_SELL)
        {
         m_bearScore += result.confidence * weight;
         m_bearConfluence++;
         m_bearSources += (m_bearSources == "" ? "" : ",") + src.Name();
        }
     }

public:
   CSignalAggregator() : m_sourceCount(0), m_config(NULL), m_vetoActive(false), m_vetoBuy(false), m_vetoSell(false)
     {
      ResetState();
      m_snapshot.Clear();
     }

   void Init(const CSignalConfig &config)
     {
      m_config = &config;
      m_scorer.Init(config);
      RefreshSnapshot();
     }

   ~CSignalAggregator() { Clear(); }

   void Clear()
     {
      m_sourceCount = 0;
      ResetState();
      RefreshSnapshot();
     }

   bool RegisterSource(ISignalSource *source, double weight = 1.0)
     {
      if(source == NULL) return false;
      if(m_sourceCount >= PASR_MAX_SIGNAL_SOURCES) return false;
      m_sources[m_sourceCount].Init(source, weight);
      if(m_config != NULL && m_config.GetDebugMode())
         PrintFormat("[SignalAgg] Registered: %s (w=%.1f %s)", source.Name(), weight, m_sources[m_sourceCount].GetTypeString());
      m_sourceCount++;
      RefreshSnapshot();
      return true;
     }

   int SourceCount() const { return m_sourceCount; }

   AggregatedSignal Aggregate()
     {
      AggregatedSignal agg;
      agg.Clear();
      agg.time = TimeCurrent();
      ResetState();

      for(int i = 0; i < m_sourceCount; i++)
        {
         if(m_sources[i].GetType() != SOURCE_TYPE_VETO) continue;
         ISignalSource *src = m_sources[i].GetSource();
         if(src == NULL) continue;
         SignalResult result; result.Clear();
         if(!src.Evaluate(result)) continue;
         if(!IsFresh(result, src.Name())) continue;
         if(!ProcessVetoSource(i, result))
           {
            agg.vetoed = true;
            RefreshSnapshot();
            return agg;
           }
        }

      for(int i = 0; i < m_sourceCount; i++)
        {
         if(m_sources[i].GetType() != SOURCE_TYPE_MULT) continue;
         ISignalSource *src = m_sources[i].GetSource();
         if(src == NULL) continue;
         SignalResult result; result.Clear();
         if(!src.Evaluate(result)) continue;
         if(!IsFresh(result, src.Name())) continue;
         ProcessMultiplierSource(i, result);
        }

      for(int i = 0; i < m_sourceCount; i++)
        {
         if(m_sources[i].GetType() != SOURCE_TYPE_VOTER) continue;
         ISignalSource *src = m_sources[i].GetSource();
         if(src == NULL) continue;
         SignalResult result; result.Clear();
         if(!src.Evaluate(result)) continue;
         if(!IsFresh(result, src.Name())) continue;
         ProcessVoterSource(i, result);
        }

      if(m_totalVoterWeight <= 0.0)
        {
         m_lastDecisionReason = "No voter weight";
         RefreshSnapshot();
         return agg;
        }

      double normBull = (m_bullScore / m_totalVoterWeight) * m_multiplierFactor;
      double normBear = (m_bearScore / m_totalVoterWeight) * m_multiplierFactor;
      int    minConfluence = (m_config != NULL) ? m_config.GetMinConfluence() : 2;
      double minScore      = (m_config != NULL) ? m_config.GetMinScore()      : 0.45;
      double minGap        = (m_config != NULL) ? m_config.GetMinDominanceGap() : 0.12;
      double conflictScore = MathMin(normBull, normBear);
      double dominanceGap  = MathAbs(normBull - normBear);

      bool bullQualified = (m_bullConfluence >= minConfluence && normBull >= minScore);
      bool bearQualified = (m_bearConfluence >= minConfluence && normBear >= minScore);

      if(bullQualified && bearQualified && dominanceGap < minGap)
        {
         m_lastDecisionReason = StringFormat("Conflict no-trade bull=%.3f bear=%.3f gap=%.3f minGap=%.3f",
                                             normBull, normBear, dominanceGap, minGap);
         RefreshSnapshot();
         return agg;
        }

      if(normBull > normBear && bullQualified)
        {
         agg.direction           = SIGNAL_BUY;
         agg.rawScore            = m_bullScore;
         agg.normalizedScore     = normBull;
         agg.multiplierFactor    = m_multiplierFactor;
         agg.confluence          = m_bullConfluence;
         agg.contributingSources = m_bullSources;
         agg.urgency             = m_scorer.GetUrgencyLevel(normBull);
         m_lastDecisionReason    = "BUY accepted";
        }
      else if(normBear > normBull && bearQualified)
        {
         agg.direction           = SIGNAL_SELL;
         agg.rawScore            = m_bearScore;
         agg.normalizedScore     = normBear;
         agg.multiplierFactor    = m_multiplierFactor;
         agg.confluence          = m_bearConfluence;
         agg.contributingSources = m_bearSources;
         agg.urgency             = m_scorer.GetUrgencyLevel(normBear);
         m_lastDecisionReason    = "SELL accepted";
        }
      else
        {
         m_lastDecisionReason = StringFormat("No consensus bull=%.3f/%d bear=%.3f/%d conflict=%.3f gap=%.3f minScore=%.3f minConf=%d",
                                             normBull, m_bullConfluence, normBear, m_bearConfluence,
                                             conflictScore, dominanceGap, minScore, minConfluence);
        }

      ApplyContraVeto(agg);
      RefreshSnapshot();
      return agg;
     }

   bool   IsVetoActive()         const { return m_vetoActive;       }
   double GetTotalVoterWeight()  const { return m_totalVoterWeight; }
   double GetMultiplierFactor()  const { return m_multiplierFactor; }
   string GetVetoReason()        const { return m_vetoReason;       }
   string GetLastDecisionReason() const { return m_lastDecisionReason; }
   SignalAggregatorSnapshot GetSnapshot() const { return m_snapshot; }

   string DescribeSources() const
     {
      string text = "";
      for(int i = 0; i < m_sourceCount; i++)
        {
         if(text != "") text += ";";
         text += StringFormat("%s:%s:%.2f", m_sources[i].GetName(), m_sources[i].GetTypeString(), m_sources[i].GetWeight());
        }
      return text;
     }
  };

#endif // __SIGNAL_AGGREGATOR_MQH__
