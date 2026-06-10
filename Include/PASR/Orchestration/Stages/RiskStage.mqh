//+------------------------------------------------------------------+
//| Orchestration/Stages/RiskStage.mqh                               |
//| Pipeline stage: risk filter and position sizing                  |
//+------------------------------------------------------------------+
#property strict
#ifndef __ORCHESTRATION_RISK_STAGE_MQH__
#define __ORCHESTRATION_RISK_STAGE_MQH__

#include "PipelineStageBase.mqh"
#include "../../Risk/RiskManager.mqh"

class CRiskStage : public CPipelineStageBase
{
private:
   // REMOVED: bool m_enabled — inherited from CPipelineStageBase
   // REMOVED: bool m_debug   — inherited from CPipelineStageBase
   CRiskManager *m_risk_mgr;

public:
   CRiskStage() : CPipelineStageBase("Risk"), m_risk_mgr(NULL) {}

   virtual bool Init(IDataManager *data, CEventBus *bus) override
   {
      if(!CPipelineStageBase::Init(data, bus)) return false;
      return true;
   }

   void SetRiskManager(CRiskManager *mgr) { m_risk_mgr = mgr; }

   virtual bool Execute(SPipelineContext &ctx) override
   {
      if(!m_enabled) return true;
      if(!ctx.signal_ready) return true;

      if(m_risk_mgr == NULL)
      {
         if(m_debug) Print("[RiskStage] RiskManager is NULL");
         return false;
      }

      ctx.risk_approved = m_risk_mgr->EvaluateSignal(ctx.signal_out, ctx.risk_out);

      if(m_debug)
         PrintFormat("[RiskStage] Risk %s — lot=%.2f sl=%.5f tp=%.5f",
                     ctx.risk_approved ? "APPROVED" : "REJECTED",
                     ctx.risk_out.lot_size,
                     ctx.risk_out.sl_price,
                     ctx.risk_out.tp_price);

      return true;
   }

   virtual string StageName() const override { return "Risk"; }
};

#endif // __ORCHESTRATION_RISK_STAGE_MQH__
