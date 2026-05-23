//+------------------------------------------------------------------+
//| AI/AISignalSource.mqh                                            |
//| Bridge: CAIOrchestrator inference score -> ISignalSource         |
//| Sprint 10: Path fix ../../Signal/ -> ../Signal/                  |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_SIGNAL_SOURCE_MQH__
#define __AI_SIGNAL_SOURCE_MQH__

#include "AITypes.mqh"
#include "AIOrchestrator.mqh"
#include "../Signal/SignalManager.mqh"

//+------------------------------------------------------------------+
//| CAISignalSource : ISignalSource                                  |
//| Wraps CAIOrchestrator::Predict() as an ISignalSource plugin      |
//| so SignalManager can aggregate AI output alongside SR, Pattern   |
//+------------------------------------------------------------------+
class CAISignalSource : public ISignalSource
{
private:
   CAIOrchestrator *m_ai;          // non-owning reference
   double           m_weight;      // weight in SignalManager aggregation
   bool             m_enabled;
   string           m_name;
   
public:
   CAISignalSource(CAIOrchestrator *ai, double weight = 1.0)
      : m_ai(ai), m_weight(weight), m_enabled(true), m_name("AISignalSource")
   {}
   
   //--- ISignalSource interface
   virtual string GetName() const override { return m_name; }
   
   virtual bool Evaluate(SSignal &out) override
   {
      out.Reset();
      if(!m_enabled) return false;
      if(CheckPointer(m_ai) == POINTER_INVALID) return false;
      if(!m_ai->IsReady()) return false;
      
      SAIInferenceResult result;
      bool ok = m_ai->Predict(result);
      
      if(!ok || result.vetoed)
      {
         out.direction  = SIGNAL_NONE;
         out.confidence = 0.0;
         out.valid      = false;
         return false;
      }
      
      out.direction  = (result.direction > 0) ? SIGNAL_BUY
                     : (result.direction < 0) ? SIGNAL_SELL
                     : SIGNAL_NONE;
      out.confidence = result.confidence;
      out.score      = result.score;
      out.source     = m_name;
      out.valid      = result.valid;
      return out.valid;
   }
   
   virtual double GetWeight() const override { return m_weight; }
   virtual bool   IsEnabled() const override { return m_enabled; }
   
   void SetEnabled(bool v)     { m_enabled = v; }
   void SetWeight(double w)    { m_weight  = MathMax(0.0, w); }
   void SetName(string name)   { m_name    = name; }
   
   CAIOrchestrator* GetOrchestrator() { return m_ai; }
};

#endif // __AI_SIGNAL_SOURCE_MQH__
