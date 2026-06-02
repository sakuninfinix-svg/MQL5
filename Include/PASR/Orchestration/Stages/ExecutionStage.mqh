//+------------------------------------------------------------------+
//| Orchestration/Stages/ExecutionStage.mqh - v0.10                 |
//| Runtime Execution pipeline stage                                 |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_ORCHESTRATION_EXECUTION_STAGE_MQH__
#define __PASR_ORCHESTRATION_EXECUTION_STAGE_MQH__

#include <PASR/Core/PipelineTypes.mqh>
#include <PASR/Core/Globals.mqh>
#include <PASR/Trade/TradePlan.mqh>
#include <PASR/Trade/ExecutionManager.mqh>
#include <PASR/Trade/RecoveryManager.mqh>
#include <PASR/Orchestration/PipelineStage.mqh>

class CExecutionStage : public IPipelineStage
  {
private:
   CExecutionManager *m_exec;
   CRecoveryManager  *m_recovery;
   bool               m_enabled;
   bool               m_debug;
   bool               m_profiling;
   CPerfTimer         m_timer;

public:
   CExecutionStage()
      : m_exec(NULL), m_recovery(NULL), m_enabled(true), m_debug(false), m_profiling(true)
     {}

   void Bind(CExecutionManager *exec, CRecoveryManager *recovery)
     {
      m_exec = exec;
      m_recovery = recovery;
     }

   void SetEnabled(const bool enabled) { m_enabled = enabled; }
   void SetDebugMode(const bool enabled) { m_debug = enabled; }
   void EnableProfiling(const bool enabled) { m_profiling = enabled; }

   virtual string Name() const override { return "ExecutionStage"; }
   virtual bool IsEnabled() const override { return m_enabled; }

   virtual ENUM_STAGE_RESULT Execute(PipelineContext &ctx) override
     {
      if(!m_enabled)
         return STAGE_SKIP;
      if(m_exec == NULL)
        {
         if(m_debug) Print("[Pipeline] Execution SKIP: manager is NULL");
         return STAGE_SKIP;
        }
      if(ctx.signal.direction == SIGNAL_NONE) return STAGE_SKIP;
      if(!ctx.risk_result.allowed) return STAGE_SKIP;
      if(ctx.trading_allowed == false) return STAGE_SKIP;
      m_timer.Start();

      TradePlan plan;
      plan.Clear();
      plan.direction = ctx.signal.direction;
      plan.entryPrice = ctx.risk_result.entryPrice;
      plan.sl = ctx.risk_result.stopLoss;
      plan.tp = ctx.risk_result.takeProfit;
      plan.lot = ctx.risk_result.lotSize;
      plan.slPoints = ctx.signal.slPoints;
      plan.comment = StringFormat("PASR|%s|%.0f", ctx.signal.primarySource, ctx.signal.confidence * 100.0);
      bool buyStopsOk = (plan.direction == SIGNAL_BUY && plan.sl < plan.entryPrice && plan.tp > plan.entryPrice);
      bool sellStopsOk = (plan.direction == SIGNAL_SELL && plan.sl > plan.entryPrice && plan.tp < plan.entryPrice);
      plan.valid = (plan.direction != SIGNAL_NONE && plan.lot > 0 && plan.entryPrice > 0 &&
                    plan.sl > 0 && plan.tp > 0 && (buyStopsOk || sellStopsOk));

      ctx.plan.direction = plan.direction;
      ctx.plan.entryPrice = plan.entryPrice;
      ctx.plan.sl = plan.sl;
      ctx.plan.tp = plan.tp;
      ctx.plan.slPoints = plan.slPoints;
      ctx.plan.tpPoints = ctx.signal.tpPoints;
      ctx.plan.lot = plan.lot;
      ctx.plan.valid = plan.valid;

      if(!plan.valid)
        {
         ctx.exit_message = "Execution skipped: invalid trade plan";
         if(m_profiling) m_timer.Log("Stage10_Execution");
         return STAGE_SKIP;
        }

      ctx.exec_result = m_exec.Execute(plan);

      if(ctx.exec_result.status == EXEC_FAIL)
        {
         if(m_debug) PrintFormat("[Pipeline] Execution FAILED: %s", ctx.exec_result.comment);
         ctx.exit_reason = STAGE_ABORT;
         ctx.exit_message = "Execution error: " + ctx.exec_result.comment;
         if(m_profiling) m_timer.Log("Stage10_Execution");
         return STAGE_ABORT;
        }

      if(m_debug)
         PrintFormat("[Pipeline] Execution status=%d ticket=%I64u price=%.5f lot=%.2f", (int)ctx.exec_result.status, ctx.exec_result.ticket, plan.entryPrice, plan.lot);
      if(m_profiling) m_timer.Log("Stage10_Execution");
      return STAGE_OK;
     }
  };

#endif // __PASR_ORCHESTRATION_EXECUTION_STAGE_MQH__
