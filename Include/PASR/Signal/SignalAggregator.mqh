//+------------------------------------------------------------------+
//| Signal/SignalAggregator.mqh — v1.03                              |
//| Signal aggregation with voting, veto, and multiplier logic       |
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
     }

   bool ProcessVetoSource(CRegisteredSource &reg, SignalResult &result)
     {
      string name = (reg.GetSource() != NULL) ? reg.GetSource().Name() : "VETO";

      if(result.direction == SIGNAL_NONE)
        {
         m_vetoActive = true;
         m_vetoReason = StringFormat("%s:%s", name, result.reason);
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
         if(m_config != NULL && m_config.GetDebugMode())
            PrintFormat("[SignalAgg] CONTRA-VETO BUY: %s", m_vetoReason);
        }
      else if(agg.direction == SIGNAL_SELL && m_vetoSell)
        {
         agg.Clear();
         agg.time = TimeCurrent();
         agg.vetoed = true;
         m_vetoActive = true;
         if(m_config != NULL && m_config.GetDebugMode())
            PrintFormat("[SignalAgg] CONTRA-VETO SELL: %s", m_vetoReason);
        }
     }

   void ProcessMultiplierSource(CRegisteredSource &reg, SignalResult &result)
     {
      if(result.confidence > 0.0)
         m_multiplierFactor *= result.confidence;
      if(m_config != NULL && m_config.GetDebugMode() && reg.GetSource() != NULL)
         PrintFormat("[SignalAgg] MULT %s: x%.2f (%s)", reg.GetSource().Name(), result.confidence, result.reason);
     }

   void ProcessVoterSource(CRegisteredSource &reg, SignalResult &result)
     {
      if(reg.GetSource() == NULL) return;
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
   CSignalAggregator() : m_sourceCount(0), m_config(NULL), m_vetoActive(false), m_vetoBuy(false), m_vetoSell(false)
     {
      ResetState();
     }

   void Init(const CSignalConfig &config)
     {
      m_config = &config;
      m_scorer.Init(config);
     }

   ~CSignalAggregator() { Clear(); }

   void Clear()
     {
      m_sourceCount = 0;
      ResetState();
     }

   bool RegisterSource(ISignalSource *source, double weight = 1.0)
     {
      if(source == NULL) return false;
      if(m_sourceCount >= PASR_MAX_SIGNAL_SOURCES) return false;
      m_sources[m_sourceCount].Init(source, weight);
      if(m_config != NULL && m_config.GetDebugMode())
         PrintFormat("[SignalAgg] Registered: %s (w=%.1f %s)", source.Name(), weight, m_sources[m_sourceCount].GetTypeString());
      m_sourceCount++;
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
         CRegisteredSource &reg = m_sources[i];
         if(reg.GetType() != SOURCE_TYPE_VETO) continue;
         if(reg.GetSource() == NULL) continue;
         SignalResult result; result.Clear();
         if(!reg.GetSource().Evaluate(result)) continue;
         if(!ProcessVetoSource(reg, result))
           {
            agg.vetoed = true;
            return agg;
           }
        }

      for(int i = 0; i < m_sourceCount; i++)
        {
         CRegisteredSource &reg = m_sources[i];
         if(reg.GetType() != SOURCE_TYPE_MULT) continue;
         if(reg.GetSource() == NULL) continue;
         SignalResult result; result.Clear();
         if(!reg.GetSource().Evaluate(result)) continue;
         ProcessMultiplierSource(reg, result);
        }

      for(int i = 0; i < m_sourceCount; i++)
        {
         CRegisteredSource &reg = m_sources[i];
         if(reg.GetType() != SOURCE_TYPE_VOTER) continue;
         if(reg.GetSource() == NULL) continue;
         SignalResult result; result.Clear();
         if(!reg.GetSource().Evaluate(result)) continue;
         ProcessVoterSource(reg, result);
        }

      if(m_totalVoterWeight <= 0.0) return agg;

      double normBull = (m_bullScore / m_totalVoterWeight) * m_multiplierFactor;
      double normBear = (m_bearScore / m_totalVoterWeight) * m_multiplierFactor;

      if(m_config != NULL && m_config.GetDebugMode())
         PrintFormat("[SignalAgg] Scores BUY=%.3f SELL=%.3f (x%.2f mult)", normBull, normBear, m_multiplierFactor);

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

      ApplyContraVeto(agg);
      return agg;
     }

   bool   IsVetoActive()         const { return m_vetoActive;       }
   double GetTotalVoterWeight()  const { return m_totalVoterWeight; }
   double GetMultiplierFactor()  const { return m_multiplierFactor; }
   string GetVetoReason()        const { return m_vetoReason;       }
  };

#endif // __SIGNAL_AGGREGATOR_MQH__
