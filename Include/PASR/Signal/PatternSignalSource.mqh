//+------------------------------------------------------------------+
//| Signal/PatternSignalSource.mqh — v2.01                           |
//| ISignalSource plugin: CPatternManager result → directional vote. |
//| Updated for PASR v2.01 Architecture                              |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_PATTERN_SOURCE_MQH__
#define __SIGNAL_PATTERN_SOURCE_MQH__

#include "ISignalSource.mqh"
#include "../Analysis/Pattern/PatternManager.mqh"

class PatternSignalSource : public ISignalSource
  {
private:
   CPatternManager *m_pattern;
   double          m_minConfidence;
   
public:
   PatternSignalSource(CPatternManager *p, double minConfidence = 1.60) 
      : m_pattern(p), m_minConfidence(minConfidence) {}

   virtual string Name() override { return "PatternSignalSource"; }

   virtual bool Evaluate(SignalResult &out) override
     {
      if(m_pattern == NULL)
         return false;

      SPatternResult pr;
      if(!m_pattern.GetLastResult().found)
         return false;
      
      pr = m_pattern.GetLastResult();
      
      //--- Filter by minimum confluence score
      if(pr.confluenceScore < m_minConfidence)
         return false;
      
      out.confidence = pr.confluenceScore;
      out.reason     = pr.reason;
      out.barTime    = pr.barTime;

      if(pr.direction > 0)
      {
         out.direction = SIGNAL_BUY;
         return true;
      }
      else if(pr.direction < 0)
      {
         out.direction = SIGNAL_SELL;
         return true;
      }

      out.direction = SIGNAL_NONE;
      return false;
     }
     
   //--- Accessor for statistics
   int GetTotalPatternsDetected() const { return m_pattern != NULL ? m_pattern.GetTotalDetected() : 0; }
   int GetTotalValidSignals() const { return m_pattern != NULL ? m_pattern.GetTotalValidSignals() : 0; }
  };

#endif
