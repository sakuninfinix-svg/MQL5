//+------------------------------------------------------------------+
//| Orchestration/Stages/SignalStage.mqh                             |
//| Pipeline stage: signal evaluation and scoring                    |
//+------------------------------------------------------------------+
#property strict
#ifndef __ORCHESTRATION_SIGNAL_STAGE_MQH__
#define __ORCHESTRATION_SIGNAL_STAGE_MQH__

#include "PipelineStageBase.mqh"
#include "../../Signal/SignalManager.mqh"

class CSignalStage : public CPipelineStageBase
  {
private:
   CSignalManager *m_signal_mgr;

public:
   CSignalStage() : CPipelineStageBase("Signal"), m_signal_mgr(NULL) {}

   void SetSignalManager(CSignalManager *mgr) { m_signal_mgr = mgr; }

   // FIX: match IPipelineStage abstract signature exactly
   virtual ENUM_STAGE_RESULT Execute(PipelineContext &ctx) override
     {
      if(!m_enabled) return STAGE_SKIP;
      if(m_signal_mgr == NULL)
        {
         if(m_debug) Print("[SignalStage] SignalManager is NULL");
         return STAGE_SKIP;
        }

      bool ok = m_signal_mgr.Evaluate(ctx.signal);

      if(m_debug && ok)
         PrintFormat("[SignalStage] Signal: dir=%d score=%.3f confidence=%.3f",
                     ctx.signal.direction, ctx.signal.score, ctx.signal.confidence);

      return ok ? STAGE_OK : STAGE_SKIP;
     }

   // FIX: IPipelineStage pure virtual is Name() — override it here
   virtual string Name() const override { return "Signal"; }
  };

#endif // __ORCHESTRATION_SIGNAL_STAGE_MQH__
