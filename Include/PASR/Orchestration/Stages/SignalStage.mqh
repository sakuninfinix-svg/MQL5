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
   CSignalManager    *m_signal_mgr;
   CAIOrchestrator   *m_ai;
   CAnalysisSRManager *m_sr;
   CPatternManager   *m_pattern;

public:
   CSignalStage() : CPipelineStageBase("Signal"), m_signal_mgr(NULL),
                    m_ai(NULL), m_sr(NULL), m_pattern(NULL) {}

   void SetSignalManager(CSignalManager *mgr) { m_signal_mgr = mgr; }
   void Bind(CSignalManager *mgr, CAIOrchestrator *ai, CAnalysisSRManager *sr, CPatternManager *pattern)
     {
      m_signal_mgr = mgr;
      m_ai = ai;
      m_sr = sr;
      m_pattern = pattern;
     }

   // FIX: match IPipelineStage abstract signature exactly
   virtual ENUM_STAGE_RESULT Execute(PipelineContext &ctx) override
     {
      if(!m_enabled) return STAGE_SKIP;
      if(m_signal_mgr == NULL)
        {
         if(m_debug) Print("[SignalStage] SignalManager is NULL");
         return STAGE_SKIP;
        }

      ctx.signal = m_signal_mgr.AggregateSignals();
      bool ok = (ctx.signal.direction != SIGNAL_NONE);
      if(m_debug && ok)
         PrintFormat("[SignalStage] Signal: dir=%d confidence=%.3f",
                     ctx.signal.direction, ctx.signal.confidence);

      return ok ? STAGE_OK : STAGE_SKIP;
     }

   // FIX: IPipelineStage pure virtual is Name() — override it here
   virtual string Name() const override { return "Signal"; }
  };

#endif // __ORCHESTRATION_SIGNAL_STAGE_MQH__
