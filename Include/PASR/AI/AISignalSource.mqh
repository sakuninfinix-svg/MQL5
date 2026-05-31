//+------------------------------------------------------------------+
//| AI/AISignalSource.mqh — v1.10                                    |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_SIGNAL_SOURCE_MQH__
#define __AI_SIGNAL_SOURCE_MQH__

#include "AITypes.mqh"
#include "AIOrchestrator.mqh"
#include "../Signal/ISignalSource.mqh"

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
      m_lastDirection = out.direction;
      m_lastConfidence = out.confidence;
      m_lastScore = result.score;
      m_lastDrift = result.drift_score;
      m_lastVetoed = result.vetoed;
      m_lastReason = reason;
     }

public:
   CAISignalSource(CAIOrchestrator *ai)
      : m_ai(ai), m_name("AISignalSource"), m_lastEvaluated(0),
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

      if(m_ai == NULL)
        {
         StoreLast(out, result, "AI orchestrator NULL");
         return false;
        }
      if(!m_ai.IsReady())
        {
         StoreLast(out, result, "AI not ready");
         return false;
        }

      if(!m_ai.Predict(result))
        {
         out.direction  = SIGNAL_NONE;
         out.confidence = 0.0;
         out.reason     = result.vetoed ? result.veto_reason : "AI prediction unavailable";
         StoreLast(out, result, out.reason);
         return false;
        }

      if(result.vetoed || !result.valid)
        {
         out.direction  = SIGNAL_NONE;
         out.confidence = 0.0;
         out.reason     = result.veto_reason;
         StoreLast(out, result, out.reason);
         return false;
        }

      if(result.direction > 0) out.direction = SIGNAL_BUY;
      else if(result.direction < 0) out.direction = SIGNAL_SELL;
      else out.direction = SIGNAL_NONE;

      out.confidence = result.confidence;
      out.reason = StringFormat("%s score=%.3f drift=%.3f", m_name, result.score, result.drift_score);
      StoreLast(out, result, out.reason);
      return (out.direction != SIGNAL_NONE && out.confidence > 0.0);
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
