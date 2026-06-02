//+------------------------------------------------------------------+
//| Orchestration/Stages/RiskStage.mqh - v0.20                      |
//| Runtime RiskCheck pipeline stage                                 |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_ORCHESTRATION_RISK_STAGE_MQH__
#define __PASR_ORCHESTRATION_RISK_STAGE_MQH__

#include <PASR/Core/PipelineTypes.mqh>
#include <PASR/Core/Globals.mqh>
#include <PASR/Trade/RiskManager.mqh>
#include <PASR/Orchestration/PipelineStage.mqh>

class CRiskStage : public IPipelineStage
  {
private:
   CRiskManager *m_risk;
   bool          m_enabled;
   bool          m_debug;
   bool          m_profiling;
   CPerfTimer    m_timer;

public:
   CRiskStage() : m_risk(NULL), m_enabled(true), m_debug(false), m_profiling(true) {}

   void Bind(CRiskManager *risk)
     {
      m_risk = risk;
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

   virtual string Name() const override { return "RiskStage"; }
   virtual bool IsEnabled() const override { return m_enabled; }

   virtual ENUM_STAGE_RESULT Execute(PipelineContext &ctx) override
     {
      if(!m_enabled)
         return STAGE_SKIP;
      if(m_risk == NULL)
        {
         if(m_debug) Print("[Pipeline] RiskCheck SKIP: manager is NULL");
         return STAGE_SKIP;
        }
      if(ctx.signal.direction == SIGNAL_NONE) return STAGE_SKIP;
      m_timer.Start();
      if(ctx.positions.CapturedAt() == 0)
         ctx.positions.Scan(_Symbol, m_risk.MagicNumber());
      if(!ctx.account.valid)
         ctx.account.Capture();
      m_risk.SetCycleContext(ctx.account, ctx.positions);
      ctx.risk_result = m_risk.CheckRisk(ctx.signal);
      if(!ctx.risk_result.allowed)
        {
         if(m_debug) PrintFormat("[Pipeline] RiskCheck REJECTED: %s", ctx.risk_result.reason);
         ctx.exit_message = "RiskCheck: " + ctx.risk_result.reason;
         if(m_profiling) m_timer.Log("Stage8_RiskCheck");
         return STAGE_SKIP;
        }
      ctx.trading_allowed = true;
      if(m_profiling) m_timer.Log("Stage8_RiskCheck");
      return STAGE_OK;
     }
  };

#endif // __PASR_ORCHESTRATION_RISK_STAGE_MQH__
