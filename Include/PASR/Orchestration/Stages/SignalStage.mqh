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
   // REMOVED: bool m_enabled — inherited from CPipelineStageBase
   // REMOVED: bool m_debug   — inherited from CPipelineStageBase
   CSignalManager *m_signal_mgr;

public:
   CSignalStage() : CPipelineStageBase("Signal"), m_signal_mgr(NULL) {}

   virtual bool Init(IDataManager *data, CEventBus *bus) override
   {
      if(!CPipelineStageBase::Init(data, bus)) return false;
      return true;
   }

   void SetSignalManager(CSignalManager *mgr) { m_signal_mgr = mgr; }

   virtual bool Execute(SPipelineContext &ctx) override
   {
      if(!m_enabled) return true;
      if(!ctx.data_ready) return false;

      if(m_signal_mgr == NULL)
      {
         if(m_debug) Print("[SignalStage] SignalManager is NULL");
         return false;
      }

      ctx.signal_ready = m_signal_mgr->Evaluate(ctx.signal_out);

      if(m_debug && ctx.signal_ready)
         PrintFormat("[SignalStage] Signal: dir=%d score=%.3f confidence=%.3f",
                     ctx.signal_out.direction,
                     ctx.signal_out.score,
                     ctx.signal_out.confidence);

      return true;
   }

   virtual string StageName() const override { return "Signal"; }
};

#endif // __ORCHESTRATION_SIGNAL_STAGE_MQH__
