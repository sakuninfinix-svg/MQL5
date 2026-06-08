//+------------------------------------------------------------------+
//| Signal/SignalManagerIntegration.mqh — Integration Guide            |
//| Instructions for integrating DynamicWeightManager                 |
//+------------------------------------------------------------------+
#property strict

/*
INTEGRATION INSTRUCTIONS FOR DYNAMIC WEIGHT MANAGER:

Step 1: Add include to SignalManager.mqh (after line 17):
   #include "DynamicWeightManager.mqh"

Step 2: Add member variable to CSignalManager class (private section, after line 98):
   CDynamicWeightManager *m_dynamicWeights;

Step 3: Initialize in constructor (after line 157):
   m_dynamicWeights = NULL;

Step 4: Add to Init method (after line 171):
   m_dynamicWeights = new CDynamicWeightManager();
   if(m_dynamicWeights != NULL && m_dynamicWeights.Init(data, bus))
     {
      // Register signal sources with initial weights
      m_dynamicWeights.RegisterSource("Pattern", 1.0);
      m_dynamicWeights.RegisterSource("SR", 0.8);
      m_dynamicWeights.RegisterSource("Regime", 0.6);
      m_dynamicWeights.RegisterSource("AI", 1.2);
     }

Step 5: Add to Deinit method (after line 181):
   if(m_dynamicWeights != NULL) { delete m_dynamicWeights; m_dynamicWeights = NULL; }

Step 6: Modify RegisterSource method to update dynamic weights:
   bool RegisterSource(ISignalSource *src, double weight = 1.0)
     {
      EnsureConfigReady();
      bool ok = m_aggregator.RegisterSource(src, weight);
      if(ok && m_dynamicWeights != NULL)
        {
         // Extract source name from source object
         string sourceName = src.GetSourceName(); // Assuming this method exists
         m_dynamicWeights.RegisterSource(sourceName, weight);
        }
      RefreshSnapshot(ok ? "SourceRegistered" : "SourceRejected");
      return ok;
     }

Step 7: Modify AggregateSignals to use dynamic weights:
   SSignal AggregateSignals()
     {
      EnsureConfigReady();
      SSignal out;
      out.Clear();

      // Get dynamic weights if available
      if(m_dynamicWeights != NULL)
        {
          // Apply dynamic weights to aggregation
          // Implementation depends on SignalAggregator internals
        }

      m_lastDecisionResult = m_decisionEngine.Decide(m_aggregator);
      m_lastAggregated = m_decisionEngine.GetLastAggregated();
      // ... rest of method
     }

Step 8: Add event handler for trade results to update performance:
   Add to OnEvent method:
   if(ev.id == EVENT_ID_TRADE_CLOSE && m_dynamicWeights != NULL)
     {
      m_dynamicWeights.UpdatePerformance(ev.comment, ev.profit > 0);
     }

ALTERNATIVE SIMPLER INTEGRATION:
If full integration is too complex, you can use DynamicWeightManager as a standalone
component that periodically updates weights based on trade results, then manually
apply these weights to the signal aggregation process.
*/
