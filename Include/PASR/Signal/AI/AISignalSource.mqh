//+------------------------------------------------------------------+
//| Signal/AI/AISignalSource.mqh — CANONICAL v2.01                   |
//| Bridges CAIOrchestrator score into SignalManager aggregation.     |
//+------------------------------------------------------------------+
#pragma once
#ifndef SIGNAL_AI_AISIGNALSOURCE_MQH
#define SIGNAL_AI_AISIGNALSOURCE_MQH

#include "../../Signal/SignalManager.mqh"
#include "AIInference.mqh"

class CAIOrchestrator;

class AISignalSource : public ISignalSource
  {
private:
   CAIOrchestrator *m_ai_orch;
   double           m_minScore;
   double           m_weight;

public:
   AISignalSource(CAIOrchestrator *ai_orch, double minScore = 0.6, double weight = 0.8)
      : m_ai_orch(ai_orch), m_minScore(minScore), m_weight(weight)
     {}

   virtual string Name() override { return "AISignalSource"; }

   virtual bool Evaluate(SignalResult &out) override
     {
      out.Clear();
      if(m_ai_orch == NULL) return false;

      double score = m_ai_orch.GetLastInferenceScore();
      if(score < 0.0)
        {
         out.direction  = SIGNAL_NONE;
         out.confidence = 0.0;
         out.reason     = "AI_NO_SIGNAL";
         return false;
        }

      if(score >= m_minScore && score > 0.5)
        {
         out.direction  = SIGNAL_BUY;
         out.confidence = score * m_weight;
         out.reason     = "AI_BULL score=" + DoubleToString(score, 3);
         return true;
        }

      double sellThreshold = 1.0 - m_minScore;
      if(score <= sellThreshold && score < 0.5)
        {
         out.direction  = SIGNAL_SELL;
         out.confidence = (1.0 - score) * m_weight;
         out.reason     = "AI_BEAR score=" + DoubleToString(score, 3);
         return true;
        }

      out.reason = "AI_NEUTRAL score=" + DoubleToString(score, 3);
      return false;
     }

   void SetMinScore(double v) { if(v > 0.0 && v < 1.0) m_minScore = v; }
   void SetWeight(double v)   { if(v > 0.0 && v <= 1.0) m_weight  = v; }
  };

#endif // SIGNAL_AI_AISIGNALSOURCE_MQH
