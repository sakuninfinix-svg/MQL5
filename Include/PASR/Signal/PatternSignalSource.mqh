//+------------------------------------------------------------------+
//| Signal/PatternSignalSource.mqh — v1.00                           |
//| ISignalSource plugin: PatternManager result → directional vote. |
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

public:
   PatternSignalSource(CPatternManager *p) : m_pattern(p) {}

   virtual string Name() override { return "PatternSignalSource"; }

   virtual bool Evaluate(SignalResult &out) override
     {
      if(m_pattern==NULL || !m_pattern.HasPattern()) return false;

      PatternResult pr = m_pattern.GetLastPattern();
      out.confidence   = pr.confidence;
      out.reason       = pr.name;

      if(pr.direction > 0)       { out.direction=SIGNAL_BUY;  return true; }
      else if(pr.direction < 0)  { out.direction=SIGNAL_SELL; return true; }

      out.direction=SIGNAL_NONE;
      return false;
     }
  };

#endif
