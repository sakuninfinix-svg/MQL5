//+------------------------------------------------------------------+
//| Orchestration/Stages/AIInferStage.mqh - v0.11                   |
//| Runtime AIInfer pipeline stage                                   |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_ORCHESTRATION_AI_INFER_STAGE_MQH__
#define __PASR_ORCHESTRATION_AI_INFER_STAGE_MQH__

#include <PASR/Core/PipelineTypes.mqh>
#include <PASR/AI/AIOrchestrator.mqh>
#include <PASR/Orchestration/PipelineStage.mqh>

class CAIInferStage : public IPipelineStage
  {
private:
   CAIOrchestrator *m_ai_orch;
   bool             m_enabled;

public:
   CAIInferStage() : m_ai_orch(NULL), m_enabled(true) {}

   void Bind(CAIOrchestrator *ai_or