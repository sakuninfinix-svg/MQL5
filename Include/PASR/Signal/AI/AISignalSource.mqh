//+------------------------------------------------------------------+
//| Signal/AI/AISignalSource.mqh — CANONICAL v1.00                   |
//| ISignalSource plugin that bridges AIManager score into the       |
//| SignalManager weighted-vote aggregation pipeline.                |
//|                                                                  |
//| PURPOSE:                                                         |
//|   Wraps AIManager.IsSignalConfident() + GetSignalScore() as an  |
//|   ISignalSource so CSignalManager can include AI confidence in  |
//|   its weighted-vote aggregation alongside SR/Pattern sources.   |
//|                                                                  |
//| USAGE (in your EA or Orchestrator init):                         |
//|   AISignalSource *aiSrc = new AISignalSource(m_ai);             |
//|   m_signal.RegisterSource(aiSrc);                               |
//|                                                                  |
//| ISSUE FIX #7 (2026-05-21):                                       |
//|   Signal/AI/ folder was empty — this file fills it.             |
//|   AIManager and SignalManager had no bridge connecting them.     |
//+------------------------------------------------------------------+
#pragma once
#ifndef SIGNAL_AI_AISIGNALSOURCE_MQH
#define SIGNAL_AI_AISIGNALSOURCE_MQH

#include "../../Signal/SignalManager.mqh"
// AIManager included upstream via PASR.mqh L5b — forward declare only here
class AIManager;

//+------------------------------------------------------------------+
//| AISignalSource — wraps AIManager as an ISignalSource plugin      |
//+------------------------------------------------------------------+
class AISignalSource : public ISignalSource
  {
private:
   AIManager   *m_ai;           // non-owning pointer (Orchestrator owns it)
   double       m_minScore;     // minimum AI score to emit a signal
   double       m_weight;       // weight in SignalManager aggregation

public:
   //--- Constructor: inject the AIManager pointer
   //    minScore: threshold below which no signal is emitted (default 0.6)
   //    weight:   vote weight in SignalManager aggregation (default 0.8)
   AISignalSource(AIManager *ai, double minScore = 0.6, double weight = 0.8)
      : m_ai(ai), m_minScore(minScore), m_weight(weight)
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
      if(m_ai == NULL) return false;

      float  score     = m_ai.GetSignalScore();
      double confidence = (double)score;

      // BUY side: confident bull signal
      if(score >= (float)m_minScore && score > 0.5f)
        {
         out.direction  = SIGNAL_BUY;
         out.confidence = confidence * m_weight;
         out.reason     = "AI_BULL score=" + DoubleToString(score, 3);
         return true;
        }

      // SELL side: confident bear signal (mirror threshold)
      double sellThreshold = 1.0 - m_minScore;
      if(score <= (float)sellThreshold && score < 0.5f)
        {
         out.direction  = SIGNAL_SELL;
         out.confidence = (1.0 - confidence) * m_weight;
         out.reason     = "AI_BEAR score=" + DoubleToString(score, 3);
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
