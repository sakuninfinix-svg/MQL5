//+------------------------------------------------------------------+
//| Signal/AI/AISignalSource.mqh — CANONICAL v2.00                   |
//| ISignalSource plugin that bridges AI score into the              |
//| SignalManager weighted-vote aggregation pipeline.                |
//|                                                                  |
//| PURPOSE:                                                         |
//|   Wraps CAIOrchestrator inference score into an ISignalSource    |
//|   so CSignalManager can include AI confidence in its weighted-   |
//|   vote aggregation alongside SR/Pattern sources.                 |
//|                                                                  |
//| USAGE (in your EA or Orchestrator init):                         |
//|   AISignalSource *aiSrc = new AISignalSource(m_ai_orch);         |
//|   m_signal.RegisterSource(aiSrc);                                |
//|                                                                  |
//| CHANGE LOG v2.00 (2026-05-22):                                   |
//|   - MIGRATED from deprecated AIManager to CAIOrchestrator        |
//|   - Now uses 26-dim feature system via CAIOrchestrator           |
//|   - GetSignalScore() renamed to GetLastInferenceScore()          |
//|   - Backward compat shim removed (breaking change)               |
//+------------------------------------------------------------------+
#pragma once
#ifndef SIGNAL_AI_AISIGNALSOURCE_MQH
#define SIGNAL_AI_AISIGNALSOURCE_MQH

#include "../../Signal/SignalManager.mqh"
// Forward declare CAIOrchestrator (included upstream via PASR.mqh L5b)
class CAIOrchestrator;

//+------------------------------------------------------------------+
//| AISignalSource — wraps CAIOrchestrator as an ISignalSource       |
//+------------------------------------------------------------------+
class AISignalSource : public ISignalSource
  {
private:
   CAIOrchestrator *m_ai_orch;      // non-owning pointer (Orchestrator owns it)
   double           m_minScore;     // minimum AI score to emit a signal
   double           m_weight;       // weight in SignalManager aggregation

public:
   //--- Constructor: inject the CAIOrchestrator pointer
   //    minScore: threshold below which no signal is emitted (default 0.6)
   //    weight:   vote weight in SignalManager aggregation (default 0.8)
   AISignalSource(CAIOrchestrator *ai_orch, double minScore = 0.6, double weight = 0.8)
      : m_ai_orch(ai_orch), m_minScore(minScore), m_weight(weight)
     {}

   virtual string Name() override { return "AISignalSource"; }

   //--- Evaluate is called by CSignalManager::AggregateSignals() on each new bar.
   //    Returns true and fills |out| when AI has a confident directional signal.
   //    Direction is derived from score position relative to 0.5 midpoint:
   //       score >= minScore and score > 0.5  → BUY
   //       score <= (1 - minScore) and < 0.5  → SELL
   //       otherwise                          → NONE (returns false)
   virtual bool Evaluate(SignalResult &out) override
     {
      if(m_ai_orch == NULL) return false;

      double confidence = m_ai_orch.GetLastInferenceScore();

      // BUY side: confident bull signal
      if(confidence >= m_minScore && confidence > 0.5)
        {
         out.direction  = SIGNAL_BUY;
         out.confidence = confidence * m_weight;
         out.reason     = "AI_BULL score=" + DoubleToString(confidence, 3);
         return true;
        }

      // SELL side: confident bear signal (mirror threshold)
      double sellThreshold = 1.0 - m_minScore;
      if(confidence <= sellThreshold && confidence < 0.5)
        {
         out.direction  = SIGNAL_SELL;
         out.confidence = (1.0 - confidence) * m_weight;
         out.reason     = "AI_BEAR score=" + DoubleToString(confidence, 3);
         return true;
        }

      // Neutral / not confident
      out.direction  = SIGNAL_NONE;
      out.confidence = 0.0;
      return false;
     }

   void SetMinScore(double v) { if(v > 0.0 && v < 1.0) m_minScore = v; }
   void SetWeight(double v)   { if(v > 0.0 && v <= 1.0) m_weight  = v; }
  };

#endif // SIGNAL_AI_AISIGNALSOURCE_MQH
