//+------------------------------------------------------------------+
//| Orchestration/Stages/SignalStage.mqh - v0.10                    |
//| Compatibility adapter scaffold for future split pipeline stages   |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_ORCHESTRATION_SIGNAL_STAGE_MQH__
#define __PASR_ORCHESTRATION_SIGNAL_STAGE_MQH__

#include <PASR/Core/PipelineTypes.mqh>
#include <PASR/Core/IManager.mqh>
#include <PASR/Orchestration/PipelineStage.mqh>

class CSignalStage : public IPipelineStage
  {
private:
   IManager *m_manager;
   bool      m_enabled;

public:
   CSignalStage() : m_manager(NULL), m_enabled(false) {}

   void Bind(IManager *manager)
     {
      m_manager = manager;
     }

   void SetEnabled(const bool enabled)
     {
      m_enabled = enabled;
     }

   virtual string Name() const override { return "SignalStage"; }
   virtual bool IsEnabled() const override { return m_enabled; }

   virtual ENUM_STAGE_RESULT Execute(PipelineContext &ctx) override
     {
      if(!m_enabled)
         return STAGE_SKIP;
      if(m_manager == NULL)
        {
         ctx.exit_message = "SignalStage manager not bound";
         return STAGE_FAIL;
        }
      return STAGE_OK;
     }
  };

#endif // __PASR_ORCHESTRATION_SIGNAL_STAGE_MQH__
