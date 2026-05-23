//+------------------------------------------------------------------+
//| Signal/SignalAggregator.mqh — v1.00                              |
//| Signal aggregation with voting, veto, and multiplier logic       |
//|                                                                  |
//| PURPOSE:                                                         |
//|   - Aggregate signals from multiple ISignalSource providers      |
//|   - Support three source types: VOTER, MULT (multiplier), VETO   |
//|   - Calculate weighted scores and confluence                     |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_AGGREGATOR_MQH__
#define __SIGNAL_AGGREGATOR_MQH__

#include <Arrays\ArrayObj.mqh>
#include "ISignalSource.mqh"
#include "SignalConfig.mqh"
#include "SignalScorer.mqh"

//+------------------------------------------------------------------+
//| Source Weight Type                                               |
//+------------------------------------------------------------------+
enum ENUM_SOURCE_TYPE
  {
   SOURCE_TYPE_VOTER   = 1,   // weight > 0 : contributes to direction + score
   SOURCE_TYPE_MULT    = 0,   // weight = 0 : confidence is multiplier
   SOURCE_TYPE_VETO    = -1   // weight < 0 : can suppress entire aggregation
  };

//+------------------------------------------------------------------+
//| AggregatedSignal - Result of signal aggregation                  |
//+------------------------------------------------------------------+
struct AggregatedSignal
  {
   ENUM_SIGNAL_DIR     direction;
   double              rawScore;         // Raw weighted score
   double              normalizedScore;  // Normalized 0.0-1.0
   double              multiplierFactor; // Applied multiplier product
   int                 confluence;       // Count of agreeing voter sources
   ENUM_SIGNAL_URGENCY urgency;
   string              contributingSources; // Comma-separated source names
   datetime            time;
   bool                vetoed;           // True if vetoed by any source
   
   void Clear()
     {
      direction = SIGNAL_NONE;
      rawScore = 0.0;
      normalizedScore = 0.0;
      multiplierFactor = 1.0;
      confluence = 0;
      urgency = SIGNAL_URGENCY_LOW;
      contributingSources = "";
      time = 0;
      vetoed = false;
     }
  };

//+------------------------------------------------------------------+
//| RegisteredSource - A signal source with its weight               |
//+------------------------------------------------------------------+
class CRegisteredSource
  {
private:
   ISignalSource *m_source;
   double        m_weight;
   ENUM_SOURCE_TYPE m_type;
   
public:
   CRegisteredSource(ISignalSource *src, double weight)
     {
      m_source = src;
      m_weight = weight;
      
      if(weight > 0.0) 
        m_type = SOURCE_TYPE_VOTER;
      else if(weight == 0.0) 
        m_type = SOURCE_TYPE_MULT;
      else 
        m_type = SOURCE_TYPE_VETO;
     }
   
   ISignalSource* GetSource() const { return m_source; }
   double GetWeight() const { return m_weight; }
   ENUM_SOURCE_TYPE GetType() const { return m_type; }
   
   string GetTypeString() const
     {
      switch(m_type)
        {
         case SOURCE_TYPE_VOTER:  return "VOTER";
         case SOURCE_TYPE_MULT:   return "MULT";
         case SOURCE_TYPE_VETO:   return "VETO";
         default:                 return "UNKNOWN";
        }
     }
  };

//+------------------------------------------------------------------+
//| CSignalAggregator - Main aggregation engine                      |
//+------------------------------------------------------------------+
class CSignalAggregator
  {
private:
   CArrayObj m_sources;              // Registered signal sources
   const CSignalConfig *m_config;
   CSignalScorer m_scorer;
   
   // Aggregation state
   double m_totalVoterWeight;
   double m_bullScore;
   double m_bearScore;
   double m_multiplierFactor;
   int    m_bullConfluence;
   int    m_bearConfluence;
   string m_bullSources;
   string m_bearSources;
   bool   m_vetoActive;
   
   //+------------------------------------------------------------------+
   //| Reset aggregation state                                          |
   //+------------------------------------------------------------------+
   void ResetState()
     {
      m_totalVoterWeight = 0.0;
      m_bullScore = 0.0;
      m_bearScore = 0.0;
      m_multiplierFactor = 1.0;
      m_bullConfluence = 0;
      m_bearConfluence = 0;
      m_bullSources = "";
      m_bearSources = "";
      m_vetoActive = false;
     }
   
   //+------------------------------------------------------------------+
   //| Process a VETO source                                            |
   //+------------------------------------------------------------------+
   bool ProcessVetoSource(CRegisteredSource *regSource, const SignalResult &result)
     {
      // VETO source: if it returns NONE, suppress all
      if(result.direction == SIGNAL_NONE)
        {
         m_vetoActive = true;
         
         if(m_config != NULL && m_config->GetDebugMode())
           {
            PrintFormat("[SignalAgg] ★ VETO by %s: %s", 
                       regSource->GetSource().Name(), result.reason);
           }
         
         return false; // Stop processing
        }
      
      // Veto source voted a direction = no veto, skip weight contribution
      return true; // Continue processing
     }
   
   //+------------------------------------------------------------------+
   //| Process a MULTIPLIER source                                      |
   //+------------------------------------------------------------------+
   void ProcessMultiplierSource(CRegisteredSource *regSource, const SignalResult &result)
     {
      if(result.confidence > 0.0)
        {
         m_multiplierFactor *= result.confidence;
        }
      
      if(m_config != NULL && m_config->GetDebugMode())
        {
         PrintFormat("[SignalAgg]   MULT %s: x%.2f (%s)",
                    regSource->GetSource().Name(), result.confidence, result.reason);
        }
     }
   
   //+------------------------------------------------------------------+
   //| Process a VOTER source                                           |
   //+------------------------------------------------------------------+
   void ProcessVoterSource(CRegisteredSource *regSource, const SignalResult &result)
     {
      double weight = regSource->GetWeight();
      m_totalVoterWeight += weight;
      
      if(result.direction == SIGNAL_BUY)
        {
         m_bullScore += result.confidence * weight;
         m_bullConfluence++;
         
         if(m_bullSources == "")
           m_bullSources = regSource->GetSource().Name();
         else
           m_bullSources += "," + regSource->GetSource().Name();
        }
      else if(result.direction == SIGNAL_SELL)
        {
         m_bearScore += result.confidence * weight;
         m_bearConfluence++;
         
         if(m_bearSources == "")
           m_bearSources = regSource->GetSource().Name();
         else
           m_bearSources += "," + regSource->GetSource().Name();
        }
      
      if(m_config != NULL && m_config->GetDebugMode())
        {
         string dirStr = (result.direction == SIGNAL_BUY) ? "BUY" : 
                        (result.direction == SIGNAL_SELL) ? "SELL" : "NONE";
         PrintFormat("[SignalAgg]   VOTE %s(w=%.1f): %s conf=%.2f %s",
                    regSource->GetSource().Name(), weight, dirStr,
                    result.confidence, result.reason);
        }
     }
   
public:
   //+------------------------------------------------------------------+
   //| Constructor                                                      |
   //+------------------------------------------------------------------+
   CSignalAggregator() : m_config(NULL), m_vetoActive(false)
     {
      ResetState();
     }
   
   //+------------------------------------------------------------------+
   //| Initialize with config                                           |
   //+------------------------------------------------------------------+
   void Init(const CSignalConfig &config)
     {
      m_config = &config;
      m_scorer.Init(config);
     }
   
   //+------------------------------------------------------------------+
   //| Destructor                                                       |
   //+------------------------------------------------------------------+
   ~CSignalAggregator()
     {
      Clear();
     }
   
   //+------------------------------------------------------------------+
   //| Clear all registered sources                                     |
   //+------------------------------------------------------------------+
   void Clear()
     {
      m_sources.Clear();
      ResetState();
     }
   
   //+------------------------------------------------------------------+
   //| Register a signal source                                         |
   //| weight >0 = voter, =0 = multiplier, <0 = veto                   |
   //+------------------------------------------------------------------+
   bool RegisterSource(ISignalSource *source, double weight = 1.0)
     {
      if(source == NULL) return false;
      
      CRegisteredSource *regSource = new CRegisteredSource(source, weight);
      if(regSource == NULL) return false;
      
      m_sources.Add(regSource);
      
      if(m_config != NULL && m_config->GetDebugMode())
        {
         PrintFormat("[SignalAgg] Registered: %s (w=%.1f %s)",
                    source.Name(), weight, regSource->GetTypeString());
        }
      
      return true;
     }
   
   //+------------------------------------------------------------------+
   //| Get count of registered sources                                  |
   //+------------------------------------------------------------------+
   int SourceCount() const
     {
      return m_sources.Total();
     }
   
   //+------------------------------------------------------------------+
   //| Aggregate all registered sources                                 |
   //+------------------------------------------------------------------+
   AggregatedSignal Aggregate()
     {
      AggregatedSignal agg;
      agg.Clear();
      agg.time = TimeCurrent();
      
      ResetState();
      
      // Process all sources in order: VETO → MULT → VOTER
      for(int i = 0; i < m_sources.Total(); i++)
        {
         CRegisteredSource *regSource = (CRegisteredSource*)m_sources.At(i);
         if(regSource == NULL || regSource->GetSource() == NULL) continue;
         
         SignalResult result;
         result.Clear();
         
         if(!regSource->GetSource().Evaluate(result)) continue;
         
         ENUM_SOURCE_TYPE type = regSource->GetType();
         
         // Process based on source type
         if(type == SOURCE_TYPE_VETO)
           {
            if(!ProcessVetoSource(regSource, result))
              {
               // Veto active - return immediately
               agg.vetoed = true;
               return agg;
              }
           }
         else if(type == SOURCE_TYPE_MULT)
           {
            ProcessMultiplierSource(regSource, result);
           }
         else // SOURCE_TYPE_VOTER
           {
            ProcessVoterSource(regSource, result);
           }
        }
      
      // Check if we have any voter weight
      if(m_totalVoterWeight <= 0.0)
        {
         return agg;
        }
      
      // Normalize scores and apply multiplier
      double normBull = (m_bullScore / m_totalVoterWeight) * m_multiplierFactor;
      double normBear = (m_bearScore / m_totalVoterWeight) * m_multiplierFactor;
      
      if(m_config != NULL && m_config->GetDebugMode())
        {
         PrintFormat("[SignalAgg] Scores  BUY=%.3f SELL=%.3f (x%.2f mult)",
                    normBull, normBear, m_multiplierFactor);
        }
      
      // Determine winner based on configuration thresholds
      int minConfluence = (m_config != NULL) ? m_config->GetMinConfluence() : 2;
      double minScore = (m_config != NULL) ? m_config->GetMinScore() : 0.45;
      
      // Check BUY signal
      if(normBull > normBear && 
         m_bullConfluence >= minConfluence && 
         normBull >= minScore)
        {
         agg.direction = SIGNAL_BUY;
         agg.rawScore = m_bullScore;
         agg.normalizedScore = normBull;
         agg.multiplierFactor = m_multiplierFactor;
         agg.confluence = m_bullConfluence;
         agg.contributingSources = m_bullSources;
         agg.urgency = m_scorer.GetUrgencyLevel(normBull);
        }
      // Check SELL signal
      else if(normBear > normBull && 
              m_bearConfluence >= minConfluence && 
              normBear >= minScore)
        {
         agg.direction = SIGNAL_SELL;
         agg.rawScore = m_bearScore;
         agg.normalizedScore = normBear;
         agg.multiplierFactor = m_multiplierFactor;
         agg.confluence = m_bearConfluence;
         agg.contributingSources = m_bearSources;
         agg.urgency = m_scorer.GetUrgencyLevel(normBear);
        }
      
      return agg;
     }
   
   //+------------------------------------------------------------------+
   //| Quick check: Is there a veto active?                             |
   //+------------------------------------------------------------------+
   bool IsVetoActive() const
     {
      return m_vetoActive;
     }
   
   //+------------------------------------------------------------------+
   //| Get total voter weight                                           |
   //+------------------------------------------------------------------+
   double GetTotalVoterWeight() const
     {
      return m_totalVoterWeight;
     }
   
   //+------------------------------------------------------------------+
   //| Get multiplier factor                                            |
   //+------------------------------------------------------------------+
   double GetMultiplierFactor() const
     {
      return m_multiplierFactor;
     }
  };

#endif // __SIGNAL_AGGREGATOR_MQH__
