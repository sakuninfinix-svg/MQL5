//+------------------------------------------------------------------+
//| Orchestration/Stages/RiskStage.mqh                               |
//| Pipeline stage: risk filter and position sizing                  |
//+------------------------------------------------------------------+
#property strict
#ifndef __ORCHESTRATION_RISK_STAGE_MQH__
#define __ORCHESTRATION_RISK_STAGE_MQH__

#include "PipelineStageBase.mqh"
#include "../../Trade/RiskManager.mqh"

class CRiskStage : public CPipelineStageBase
  {
private:
   CRiskManager *m_risk_mgr;

public:
   CRiskStage() : CPipelineStageBase("Risk"), m_risk_mgr(NULL) {}

   void SetRiskManager(CRiskManager *mgr) { m_risk_mgr = mgr; }
   void Bind(CRiskManager *mgr)
  {
   m_risk_mgr = mgr;
  }

   // FIX: match IPipelineStage abstract signature exactly
   virtual ENUM_STAGE_RESULT Execute(PipelineContext &ctx) override
     {
      if(!m_enabled) return STAGE_SKIP;
      if(m_risk_mgr == NULL)
        {
         if(m_debug) Print("[RiskStage] RiskManager is NULL");
         return STAGE_SKIP;
        }

      SRiskResult rr = m_risk_mgr.CheckRisk(ctx.signal);
      ctx.risk_result = rr;
      ctx.trading_allowed = ctx.risk_result.allowed;

      if(m_debug)
         PrintFormat("[RiskStage] Risk %s — lot=%.2f sl=%.5f tp=%.5f",
                     ctx.risk_result.allowed ? "APPROVED" : "REJECTED",
                     ctx.risk_result.lot_size,
                     ctx.risk_result.sl_price,
                     ctx.risk_result.tp_price);

      return STAGE_OK;
     }

   // FIX: IPipelineStage pure virtual is Name() — override it here
   virtual string Name() const override { return "Risk"; }
  };

#endif // __ORCHESTRATION_RISK_STAGE_MQH__
