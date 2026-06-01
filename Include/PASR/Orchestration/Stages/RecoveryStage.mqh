//+------------------------------------------------------------------+
//| Orchestration/Stages/RecoveryStage.mqh - v0.10                  |
//| Runtime Recovery pipeline stage                                  |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_ORCHESTRATION_RECOVERY_STAGE_MQH__
#define __PASR_ORCHESTRATION_RECOVERY_STAGE_MQH__

#include <PASR/Core/PipelineTypes.mqh>
#include <PASR/Core/Globals.mqh>
#include <PASR/Trade/RecoveryManager.mqh>
#include <PASR/Orchestration/PipelineStage.mqh>

class CRecoveryStage : public IPipelineStage
  {
private:
   CRecoveryManager *m_recovery;
   bool              m_enabled;
   bool              m_debug;
   bool              m_profiling;
   CPerfTimer        m_timer;

public:
   CRecoveryStage()
      : m_recovery(NULL), m_enabled(true), m_debug(false), m_profiling(true)
     {}

   void Bind(CRecoveryManager *recovery)
     {
      m_recovery = recovery;
     }

   void SetEnabled(const bool enabled)
     {
      m_enabled = enabled;
     }

   void SetDebugMode(const bool enabled)
     {
      m_debug = enabled;
     }

   void EnableProfiling(const bool enabled)
     {
      m_profiling = enabled;
     }

   virtual string Name() const override { return "RecoveryStage"; }
   virtual bool IsEnabled() const override { return m_enabled; }

   virtual ENUM_STAGE_RESULT Execute(PipelineContext &ctx) override
     {
      if(!m_enabled)
         return STAGE_SKIP;
      if(m_recovery == NULL)
        {
         if(m_debug) Print("[Pipeline] Recovery SKIP: manager is NULL");
         return STAGE_SKIP;
        }

      m_timer.Start();
      m_recovery.OnPriceUpdate();
      if(ctx.new_bar) m_recovery.OnNewBar();
      if(m_profiling) m_timer.Log("Stage12_Recovery");
      return STAGE_OK;
     }
  };

#endif // __PASR_ORCHESTRATION_RECOVERY_STAGE_MQH__
