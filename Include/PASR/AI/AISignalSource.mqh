//+------------------------------------------------------------------+
//| AI/AISignalSource.mqh — v1.01                                    |
//| Bridge: CAIOrchestrator inference score -> ISignalSource         |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_SIGNAL_SOURCE_MQH__
#define __AI_SIGNAL_SOURCE_MQH__

#include "AITypes.mqh"
#include "AIOrchestrator.mqh"
#include "../Signal/ISignalSource.mqh"

//+------------------------------------------------------------------+
//| CAISignalSource : ISignalSource                                  |
//| Wraps CAIOrchestrator::Predict() as an ISignalSource plugin      |
//+------------------------------------------------------------------+
class CAISignalSource : public ISignalSource
  {
private:
   CAIOrchestrator *m_ai;          // non-owning reference
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

      out.direction  = (result.direction > 0) ? SIGNAL_BUY
                     : (result.direction < 0) ? SIGNAL_SELL
                     : SIGNAL_NONE;
      out.confidence = result.confidence;
      out.reason     = StringFormat("%s score=%.3f drift=%.3f", m_name, result.score, result.drift_score);
      return (out.direction != SIGNAL_NONE && out.confidence > 0.0);
     }

   void SetName(string name) { m_name = name; }
   CAIOrchestrator* GetOrchestrator() { return m_ai; }
  };

#endif // __AI_SIGNAL_SOURCE_MQH__