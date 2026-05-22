//+------------------------------------------------------------------+
//| Core/PipelineEngine.mqh — v2.00 (Profiling-Aware)                |
//| Staged pipeline execution engine with metrics                    |
//|                                                                  |
//| PURPOSE: Replace monolithic OnTimer() with pipelined stages      |
//|                                                                  |
//| ARCHITECTURE v2.00 IMPROVEMENTS:                                 |
//|   ✓ Each stage is independent and testable                       |
//|   ✓ Profiling at each stage (elapsed_us, executed, skipped)      |
//|   ✓ Early-exit short-circuiting via PipelineContext              |
//|   ✓ Context passing between stages (data, signal, risk_result)   |
//|   ✓ Non-blocking design (async position management)              |
//|                                                                  |
//| STAGES (12 total):                                               |
//|   1. Data Sync → 2. Analysis (SR/Zone) → 3. Pattern Rec          |
//|   4. Regime Detection → 5. Signal Generation → 6. AI Inference   |
//|   7. Risk Check → 8. Execution → 9. Position Management          |
//|   10. Recovery → 11. Dashboard → 12. Journal                     |
//|                                                                  |
//| USAGE:                                                           |
//|   Call ExecutePipeline(PipelineContext&) from OnTimer/OnTick     |
//|                                                                  |
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_PIPELINE_ENGINE_MQH__
#define __CORE_PIPELINE_ENGINE_MQH__

#include "PipelineTypes.mqh"
// Note: JournalManager included via forward declaration to avoid circular deps

// Forward declarations for manager classes (avoid circular dependencies)
class CDataManager;
class CAnalysisSRManager;
class CAnalysisZoneManager;
class CPatternManager;
class CSignalManager;
class AIManager;
class CRegimeFilter;
class CRiskManager;
class CExecutionManager;
class CRecoveryManager;
class CDashboardManager;
class CEventBus;
class CJournalManager;  // Forward declared (no include needed)

//+------------------------------------------------------------------+
//| CPipelineEngine — Staged execution with profiling                |
//+------------------------------------------------------------------+
class CPipelineEngine
  {
private:
   // Manager references (non-owning, injected by Orchestrator)
   CDataManager           *m_data;
   CAnalysisSRManager     *m_sr;
   CAnalysisZoneManager   *m_zone;
   CPatternManager        *m_pattern;
   CSignalManager         *m_signal;
   AIManager              *m_ai;
   CRegimeFilter          *m_regime;
   CRiskManager           *m_risk;
   CExecutionManager      *m_exec;
   CRecoveryManager       *m_recovery;
   CDashboardManager      *m_dash;
   CJournalManager        *m_journal;
   CEventBus              *m_bus;
   
   // Profiling state
   PipelineReport         m_report;
   StageMetrics           m_current_stage;
   bool                   m_profiling_enabled;
   
   // Debug mode
   bool                   m_debug_mode;
   
   // ── Individual Stage Implementations ───────────────────────────
   
   ENUM_STAGE_RESULT Stage_DataSync(PipelineContext &ctx)
     {
      m_current_stage.Start();
      
      // Get current prices
      MqlTick tick;
      if(!SymbolInfoTick(_Symbol, tick))
        {
         ctx.Abort("Failed to get tick data");
         m_current_stage.Stop();
         m_current_stage.aborted = true;
         return STAGE_ABORT;
        }
      
      ctx.bid = tick.bid;
      ctx.ask = tick.ask;
      ctx.bar_time = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
      ctx.market_open = ((TimeCurrent() - tick.time) < 60);
      
      // Update DataManager (publishes PRICE_UPDATE event)
      if(CheckPointer(m_data) != POINTER_INVALID)
         m_data->OnTick();
      
      // Get ATR
      ctx.atr_points = m_data != NULL ? m_data->GetATRPoints() : 0;
      
      m_current_stage.Stop();
      return STAGE_OK;
     }
   
   ENUM_STAGE_RESULT Stage_AnalysisSR(PipelineContext &ctx)
     {
      m_current_stage.Start();
      
      if(CheckPointer(m_sr) == POINTER_INVALID)
        {
         m_current_stage.Stop();
         m_current_stage.skipped = true;
         return STAGE_SKIP;
        }
      
      // Update SR zones on new bar
      if(ctx.new_bar && CheckPointer(m_bus) != POINTER_INVALID)
        {
         PASREvent ev;
         ev.id = EVENT_ID_NEW_BAR;
         ev.priority = 10;
         m_bus->Push(ev);
         
         // Drain queue to process SR update immediately
         PASREvent drain_ev;
         while(m_bus->Pop(drain_ev))
            m_bus->Dispatch(drain_ev);
        }
      
      m_current_stage.Stop();
      return STAGE_OK;
     }
   
   ENUM_STAGE_RESULT Stage_AnalysisZone(PipelineContext &ctx)
     {
      m_current_stage.Start();
      
      if(CheckPointer(m_zone) == POINTER_INVALID)
        {
         m_current_stage.Stop();
         m_current_stage.skipped = true;
         return STAGE_SKIP;
        }
      
      // Zone updates happen via event bus (already drained in SR stage)
      
      m_current_stage.Stop();
      return STAGE_OK;
     }
   
   ENUM_STAGE_RESULT Stage_PatternRec(PipelineContext &ctx)
     {
      m_current_stage.Start();
      
      if(CheckPointer(m_pattern) == POINTER_INVALID)
        {
         m_current_stage.Stop();
         m_current_stage.skipped = true;
         return STAGE_SKIP;
        }
      
      // Pattern recognition happens via event bus
      
      m_current_stage.Stop();
      return STAGE_OK;
     }
   
   ENUM_STAGE_RESULT Stage_RegimeDet(PipelineContext &ctx)
     {
      m_current_stage.Start();
      
      if(CheckPointer(m_regime) == POINTER_INVALID)
        {
         m_current_stage.Stop();
         m_current_stage.skipped = true;
         return STAGE_SKIP;
        }
      
      // Detect regime
      ctx.regime = m_regime->GetCurrentRegime();
      ctx.session = DetectSession();
      
      m_current_stage.Stop();
      return STAGE_OK;
     }
   
   ENUM_STAGE_RESULT Stage_SignalGen(PipelineContext &ctx)
     {
      m_current_stage.Start();
      
      if(CheckPointer(m_signal) == POINTER_INVALID)
        {
         m_current_stage.Stop();
         m_current_stage.skipped = true;
         return STAGE_SKIP;
        }
      
      // Generate signal
      if(m_signal->HasSignal())
        {
         ctx.signal = m_signal->GetCurrent();
        }
      else
        {
         ctx.signal.direction = SIGNAL_NONE;
         ctx.Skip("No signal generated");
         m_current_stage.Stop();
         return STAGE_SKIP;
        }
      
      m_current_stage.Stop();
      return STAGE_OK;
     }
   
   ENUM_STAGE_RESULT Stage_AIInference(PipelineContext &ctx)
     {
      m_current_stage.Start();
      
      if(CheckPointer(m_ai) == POINTER_INVALID)
        {
         m_current_stage.Stop();
         m_current_stage.skipped = true;
         return STAGE_SKIP;
        }
      
      // Get AI score
      float features[AI_INPUT_DIM];
      if(m_ai->BuildFeaturesPublic(features))
        {
         ctx.ai_score = m_ai->Predict(features);
         ctx.drift_score = m_ai->GetDriftScore();
         ctx.ai_veto = (ctx.ai_score < 0.4 || ctx.drift_score > 0.6);
         
         if(ctx.ai_veto)
           {
            ctx.Skip("AI veto triggered");
            m_current_stage.Stop();
            return STAGE_SKIP;
           }
        }
      else
        {
         ctx.ai_score = 0.5;  // Neutral
         ctx.drift_score = 0.0;
         ctx.ai_veto = false;
        }
      
      m_current_stage.Stop();
      return STAGE_OK;
     }
   
   ENUM_STAGE_RESULT Stage_RiskCheck(PipelineContext &ctx)
     {
      m_current_stage.Start();
      
      if(CheckPointer(m_risk) == POINTER_INVALID)
        {
         m_current_stage.Stop();
         m_current_stage.skipped = true;
         return STAGE_SKIP;
        }
      
      // Pre-trade risk gate
      ctx.risk_result = m_risk->Check(ctx.plan.slPoints);
      
      if(!ctx.risk_result.allowed)
        {
         if(m_debug_mode)
            PrintFormat("[Pipeline] RiskBlock: %s", ctx.risk_result.reason);
         ctx.Skip(ctx.risk_result.reason);
         m_current_stage.Stop();
         return STAGE_SKIP;
        }
      
      ctx.plan.lot = ctx.risk_result.suggestedLot;
      ctx.trading_allowed = true;
      
      m_current_stage.Stop();
      return STAGE_OK;
     }
   
   ENUM_STAGE_RESULT Stage_Execution(PipelineContext &ctx)
     {
      m_current_stage.Start();
      
      if(CheckPointer(m_exec) == POINTER_INVALID || !ctx.plan.valid)
        {
         m_current_stage.Stop();
         m_current_stage.skipped = true;
         return STAGE_SKIP;
        }
      
      // Execute trade
      ctx.exec_result = m_exec->Execute(ctx.plan);
      
      if(ctx.exec_result.status == EXEC_OK)
        {
         if(CheckPointer(m_risk) != POINTER_INVALID)
            m_risk->OnTradeOpened();
         if(CheckPointer(m_recovery) != POINTER_INVALID)
            m_recovery->OnTradeOpen(0, 
                                    ctx.plan.direction == SIGNAL_BUY ? 1 : -1,
                                    ctx.plan.entryPrice);
        }
      
      m_current_stage.Stop();
      return STAGE_OK;
     }
   
   ENUM_STAGE_RESULT Stage_PositionMgmt(PipelineContext &ctx)
     {
      m_current_stage.Start();
      
      // Position management is handled asynchronously via OnTick
      // This stage just checks position state
      
      ctx.has_position = (PositionsTotal() > 0);
      if(ctx.has_position)
        {
         // Get first position for this symbol
         for(int i = PositionsTotal() - 1; i >= 0; i--)
           {
            if(PositionGetSymbol(i) == _Symbol)
              {
               ctx.position_ticket = PositionGetTicket(i);
               ctx.position_pnl = PositionGetDouble(POSITION_PROFIT);
               break;
              }
           }
        }
      
      m_current_stage.Stop();
      return STAGE_OK;
     }
   
   ENUM_STAGE_RESULT Stage_Recovery(PipelineContext &ctx)
     {
      m_current_stage.Start();
      
      if(CheckPointer(m_recovery) == POINTER_INVALID)
        {
         m_current_stage.Stop();
         m_current_stage.skipped = true;
         return STAGE_SKIP;
        }
      
      // Recovery engine runs on existing positions
      // Actual recovery logic is in RecoveryManager.OnTick()
      
      m_current_stage.Stop();
      return STAGE_OK;
     }
   
   ENUM_STAGE_RESULT Stage_Dashboard(PipelineContext &ctx)
     {
      m_current_stage.Start();
      
      if(CheckPointer(m_dash) == POINTER_INVALID)
        {
         m_current_stage.Stop();
         m_current_stage.skipped = true;
         return STAGE_SKIP;
        }
      
      // Dashboard update happens internally via event bus
      
      m_current_stage.Stop();
      return STAGE_OK;
     }
   
   ENUM_STAGE_RESULT Stage_Journal(PipelineContext &ctx)
     {
      m_current_stage.Start();
      
      // Journal entries are written on trade close
      // This stage logs pipeline metrics if enabled
      
      if(m_profiling_enabled && m_debug_mode)
        {
         string msg = StringFormat("Pipeline cycle: %dµs (avg %.2fms)",
                                   m_report.last_cycle_time,
                                   m_report.avg_cycle_time_ms);
         if(CheckPointer(m_journal) != POINTER_INVALID)
            m_journal->LogInfo(msg);
        }
      
      m_current_stage.Stop();
      return STAGE_OK;
     }
   
public:
   CPipelineEngine()
      : m_data(NULL), m_sr(NULL), m_zone(NULL), m_pattern(NULL),
        m_signal(NULL), m_ai(NULL), m_regime(NULL), m_risk(NULL),
        m_exec(NULL), m_recovery(NULL), m_dash(NULL), m_journal(NULL),
        m_bus(NULL),
        m_profiling_enabled(true), m_debug_mode(false)
     {
      m_report.Reset();
     }
   
   ~CPipelineEngine() {}
   
   void SetDebugMode(bool on) { m_debug_mode = on; }
   void EnableProfiling(bool on) { m_profiling_enabled = on; }
   
   // Inject manager dependencies
   void InjectManagers(CDataManager *data,
                       CAnalysisSRManager *sr,
                       CAnalysisZoneManager *zone,
                       CPatternManager *pattern,
                       CSignalManager *signal,
                       AIManager *ai,
                       CRegimeFilter *regime,
                       CRiskManager *risk,
                       CExecutionManager *exec,
                       CRecoveryManager *recovery,
                       CDashboardManager *dash,
                       CJournalManager *journal,
                       CEventBus *bus)
     {
      m_data = data;
      m_sr = sr;
      m_zone = zone;
      m_pattern = pattern;
      m_signal = signal;
      m_ai = ai;
      m_regime = regime;
      m_risk = risk;
      m_exec = exec;
      m_recovery = recovery;
      m_dash = dash;
      m_journal = journal;
      m_bus = bus;
     }
   
   // Execute full pipeline
   ENUM_STAGE_RESULT ExecutePipeline(PipelineContext &ctx)
     {
      ulong cycle_start = GetMicrosecondCount();
      
      // Define stage function pointers
      typedef ENUM_STAGE_RESULT (CPipelineEngine::*StageFunc)(PipelineContext&);
      static const StageFunc stages[STAGE_COUNT] =
        {
         NULL,                    // STAGE_NONE
         &CPipelineEngine::Stage_DataSync,      // STAGE_DATA_SYNC
         &CPipelineEngine::Stage_AnalysisSR,    // STAGE_ANALYSIS_SR
         &CPipelineEngine::Stage_AnalysisZone,  // STAGE_ANALYSIS_ZONE
         &CPipelineEngine::Stage_PatternRec,    // STAGE_PATTERN_REC
         &CPipelineEngine::Stage_RegimeDet,     // STAGE_REGIME_DET
         &CPipelineEngine::Stage_SignalGen,     // STAGE_SIGNAL_GEN
         &CPipelineEngine::Stage_AIInference,   // STAGE_AI_INFERENCE
         &CPipelineEngine::Stage_RiskCheck,     // STAGE_RISK_CHECK
         &CPipelineEngine::Stage_Execution,     // STAGE_EXECUTION
         &CPipelineEngine::Stage_PositionMgmt,  // STAGE_POSITION_MGMT
         &CPipelineEngine::Stage_Recovery,      // STAGE_RECOVERY
         &CPipelineEngine::Stage_Dashboard,     // STAGE_DASHBOARD
         &CPipelineEngine::Stage_Journal        // STAGE_JOURNAL
        };
      
      ENUM_STAGE_RESULT result = STAGE_OK;
      
      // Execute stages in order
      for(int i = 1; i < STAGE_COUNT && ctx.ShouldContinue(); i++)
        {
         m_current_stage.Reset();
         m_current_stage.stage_id = i;
         
         if(stages[i] != NULL)
            result = (this.*stages[i])(ctx);
         
         // Record stage metrics
         if(m_profiling_enabled)
           {
            m_report.stage_metrics[i].elapsed_us += m_current_stage.elapsed_us;
            if(m_current_stage.executed) m_report.stage_metrics[i].executed = true;
            if(m_current_stage.skipped)  m_report.stage_metrics[i].skipped = true;
            if(m_current_stage.aborted)  m_report.stage_metrics[i].aborted = true;
           }
         
         if(result != STAGE_OK) break;
        }
      
      // Record cycle metrics
      ulong elapsed = GetMicrosecondCount() - cycle_start;
      if(m_profiling_enabled)
         m_report.RecordCycle(elapsed, result);
      
      ctx.exit_reason = result;
      return result;
     }
   
   // Get profiling report
   const PipelineReport& GetReport() const { return m_report; }
   
   // Print profiling summary
   void PrintProfile() const
     {
      if(!m_profiling_enabled) return;
      Print(m_report.ToString());
     }
  };

#endif // __CORE_PIPELINE_ENGINE_MQH__
