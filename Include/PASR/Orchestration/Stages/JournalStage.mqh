//+------------------------------------------------------------------+
//| Orchestration/Stages/JournalStage.mqh - v0.10                   |
//| Runtime Journal pipeline stage                                   |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_ORCHESTRATION_JOURNAL_STAGE_MQH__
#define __PASR_ORCHESTRATION_JOURNAL_STAGE_MQH__

#include <PASR/Core/PipelineTypes.mqh>
#include <PASR/Core/Globals.mqh>
#include <PASR/Infra/JournalManager.mqh>
#include <PASR/Orchestration/PipelineStage.mqh>

class CJournalStage : public IPipelineStage
  {
private:
   CJournalManager *m_journal;
   bool             m_enabled;
   bool             m_debug;
   bool             m_profiling;
   string           m_observability;
   CPerfTimer       m_timer;

public:
   CJournalStage()
      : m_journal(NULL), m_enabled(true), m_debug(false), m_profiling(true),
        m_observability("")
     {}

   void Bind(CJournalManager *journal)
     {
      m_journal = journal;
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

   void SetObservabilityText(const string text)
     {
      m_observability = text;
     }

   virtual string Name() const override { return "JournalStage"; }
   virtual bool IsEnabled() const override { return m_enabled; }

   virtual ENUM_STAGE_RESULT Execute(PipelineContext &ctx) override
     {
      if(!m_enabled)
         return STAGE_SKIP;
      if(m_journal == NULL)
        {
         if(m_debug) Print("[Pipeline] Journal SKIP: manager is NULL");
         return STAGE_SKIP;
        }
      if(!ctx.new_bar)
         return STAGE_SKIP;

      m_timer.Start();
      m_journal.LogEntry(ctx);
      if(m_debug && m_observability != "")
         Print("[JournalObs] ", m_observability);
      if(m_profiling) m_timer.Log("Stage14_Journal");
      return STAGE_OK;
     }
  };

#endif // __PASR_ORCHESTRATION_JOURNAL_STAGE_MQH__
