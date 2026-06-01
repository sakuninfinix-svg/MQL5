//+------------------------------------------------------------------+
//| Orchestration/Stages/SignalStage.mqh - v0.20                     |
//| Compatibility adapter scaffold for future split pipeline stages   |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_ORCHESTRATION_SIGNAL_STAGE_MQH__
#define __PASR_ORCHESTRATION_SIGNAL_STAGE_MQH__

#include <PASR/Core/PipelineTypes.mqh>
#include <PASR/Core/IManager.mqh>
#include <PASR/Orchestration/Stages/PipelineStageBase.mqh>

class CSignalStage : public CPipelineStageBase
  {
private:
   IManager *m_manager;

public:
   CSignalStage() : CPipelineStageBase("SignalStage"), m_manager(NULL)
     {
      m_enabled = false;
     }

   void Bind(IManager *manager)
     {
      m_manager = manager;
     }

   virtual ENUM_STAGE_RESULT Execute(PipelineContext &ctx) override
     {
      if(!m_enabled)
         return STAGE_SKIP;
      if(m_manager == NULL)
         return Abort(ctx, "SignalStage manager not bound");
      return STAGE_OK;
     }
  };

#endif // __PASR_ORCHESTRATION_SIGNAL_STAGE_MQH__