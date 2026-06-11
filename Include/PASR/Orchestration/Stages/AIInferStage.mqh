#property strict
#ifndef __PASR_ORCHESTRATION_AI_INFER_STAGE_MQH__
#define __PASR_ORCHESTRATION_AI_INFER_STAGE_MQH__

#include "PipelineStageBase.mqh"
#include "../../AI/AIOrchestrator.mqh"

class CAIInferStage : public CPipelineStageBase
  {
private:
   CAIOrchestrator *m_ai_orch;
public:
   CAIInferStage() : CPipelineStageBase("AIInfer"), m_ai_orch(NULL) {}
   void SetAIOrchestrator(CAIOrchestrator *orch) { m_ai_orch = orch;