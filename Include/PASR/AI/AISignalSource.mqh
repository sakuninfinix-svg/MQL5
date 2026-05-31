//+------------------------------------------------------------------+
//| AI/AISignalSource.mqh — v1.03                                    |
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

public:
   CAISignalSource(CAIOrchestrator *ai)
      : m_ai(ai), m_name("AISignalSource")
     {}

   virtual string Name() override
     {
      return m_name;
     }

   virtual bool Evaluate(SignalResult &out) override
     {
      out.Clear();
      if(m_ai == NULL) return false;
      if(!m_ai.IsReady()) return false;

      SAIInferenceResult result;
      if(!m_ai.Predict(result))
        {
         out.direction  = SIGNAL_NONE;
         out.confidence = 0.0;
         out.reason     = result.vetoed ? result.veto_reason : "AI prediction unavailable";
         return false;
        }

      if(result.vetoed || !result.valid)
        {
         out.direction  = SIGNAL_NONE;
         out.confidence = 0.0;
         out.reason     = result.veto_reason;
         return false;
        }

      if(result.direction > 0) out.direction = SIGNAL_BUY;
      else if(result.direction < 0) out.direction = SIGNAL_SELL;
      else out.direction = SIGNAL_NONE;

      out.confidence = result.confidence;
      out.reason = StringFormat("%s score=%.3f drift=%.3f", m_name, result.score, result.drift_score);
      return (out.direction != SIGNAL_NONE && out.confidence > 0.0);
     }

   void SetName(string name) { m_name = name; }
   CAIOrchestrator* GetOrchestrator() { return m_ai; }
  };

class AISignalSource : public CAISignalSource
  {
public:
   AISignalSource(CAIOrchestrator *ai) : CAISignalSource(ai) {}
  };

#endif // __AI_SIGNAL_SOURCE_MQH__
