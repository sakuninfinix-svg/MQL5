//+------------------------------------------------------------------+
//| AI/AISignalSource.mqh — v1.01                                    |
//| Copyright @2026                                                  |
//| agsicentre.wordpress.com                                         |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_SIGNAL_SOURCE_MQH__
#define __AI_SIGNAL_SOURCE_MQH__

#include "AITypes.mqh"
#include "AIOrchestrator.mqh"
#include "../Signal/ISignalSource.mqh"

// AI is intentionally kept as a post-signal gate in AIInferStage.
// This source remains as a compatibility shell for older PASRKernel wiring,
// but it no longer calls CAIOrchestrator::Predict() during SignalStage.
class CAISignalSource : public ISignalSource
  {
private:
   CAIOrchestrator *m_ai;
   string           m_name;
   datetime         m_lastEvaluated;
   ENUM_SIGNAL_DIR  m_lastDirection;
   double           m_lastConfidence;
   double           m_lastScore;
   double           m_lastDrift;
   bool             m_lastVetoed;
   string           m_lastReason;

   void StoreLast(SignalResult &out, SAIInferenceResult &result, const string reason)
     {
      m_lastEvaluated = TimeCurrent();
      out.evaluatedAt = m_lastEvaluated;
      m_lastDirection = out.direction;
      m_lastConfidence = out.confidence;
      m_lastScore = result.score;
      m_lastDrift = result.drift_score;
      m_lastVetoed = result.vetoed;
      m_lastReason = reason;
     }

public:
   CAISignalSource(CAIOrchestrator *ai)
      : m_ai(ai), m_name("AISignalSource(DISABLED_GATE_ONLY)"), m_lastEvaluated(0),
        m_lastDirection(SIGNAL_NONE), m_lastConfidence(0.0), m_lastScore(0.0),
        m_lastDrift(0.0), m_lastVetoed(false), m_lastReason("")
     {}

   virtual string Name() override
     {
      return m_name;
     }

   virtual bool Evaluate(SignalResult &out) override
     {
      out.Clear();
      SAIInferenceResult result;
      result.Clear();

      out.direction  = SIGNAL_NONE;
      out.confidence = 0.0;
      out.reason     = "AI signal source disabled: AI is evaluated once in AIInferStage";
      StoreLast(out, result, out.reason);
      return false;
     }

   void SetName(string name) { m_name = name; }
   CAIOrchestrator* GetOrchestrator() { return m_ai; }
   datetime GetLastEvaluated() const { return m_lastEvaluated; }
   ENUM_SIGNAL_DIR GetLastDirection() const { return m_lastDirection; }
   double GetLastConfidence() const { return m_lastConfidence; }
   double GetLastScore() const { return m_lastScore; }
   double GetLastDrift() const { return m_lastDrift; }
   bool WasLastVetoed() const { return m_lastVetoed; }
   string GetLastReason() const { return m_lastReason; }
  };

class AISignalSource : public CAISignalSource
  {
public:
   AISignalSource(CAIOrchestrator *ai) : CAISignalSource(ai) {}
  };

#endif // __AI_SIGNAL_SOURCE_MQH__
