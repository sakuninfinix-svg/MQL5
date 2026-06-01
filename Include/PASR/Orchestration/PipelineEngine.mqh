//+------------------------------------------------------------------+
//| Orchestration/PipelineEngine.mqh — v2.20                         |
//| AI-primary pipeline with declarative stage registry + observability|
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_PIPELINE_ENGINE_MQH__
#define __CORE_PIPELINE_ENGINE_MQH__

#include <PASR/Core/PipelineTypes.mqh>
#include <PASR/Core/Config/Types.mqh>
#include <PASR/Core/Globals.mqh>
#include <PASR/Orchestration/PipelineStageRegistry.mqh>
#include <PASR/Orchestration/Stages/DataSyncStage.mqh>
#include <PASR/Orchestration/Stages/AnalysisSRStage.mqh>
#include <PASR/Orchestration/Stages/AnalysisZoneStage.mqh>
#include <PASR/Orchestration/Stages/PatternStage.mqh>
#include <PASR/Orchestration/Stages/RegimeStage.mqh>
#include <PASR/Orchestration/Stages/SignalStage.mqh>
#include <PASR/Orchestration/Stages/AIInferStage.mqh>
#include <PASR/Orchestration/Stages/RiskStage.mqh>
#include <PASR/Orchestration/Stages/AdaptiveParamsStage.mqh>
#include <PASR/Orchestration/Stages/ExecutionStage.mqh>
#include <PASR/Orchestration/Stages/PositionStage.mqh>
#include <PASR/Orchestration/Stages/RecoveryStage.mqh>
#include <PASR/Orchestration/Stages/DashboardStage.mqh>
#include <PASR/Orchestration/Stages/JournalStage.mqh>
#include <PASR/Analysis/SRZoneStore.mqh>
#include <PASR/Analysis/SRManager.mqh>
#include <PASR/Analysis/ZoneManager.mqh>
#include <PASR/Analysis/Pattern/PatternManager.mqh>
#include <PASR/AI/AIOrchestrator.mqh>
#include <PASR/Signal/SignalManager.mqh>
#include <PASR/Signal/RegimeFilter.mqh>
#include <PASR/Analysis/MarketRegimeDetector.mqh>
#include <PASR/Infra/DataManager.mqh>
#include <PASR/Trade/TradePlan.mqh>
#include <PASR/Trade/ExitEngine.mqh>
#include <PASR/Trade/ExecutionManager.mqh>
#include <PASR/Trade/RiskManager.mqh>
#include <PASR/Trade/RecoveryManager.mqh>
#include <PASR/UI/DashboardManager.mqh>
#include <PASR/Analysis/AdaptiveParameterManager.mqh>
#include <PASR/Infra/JournalManager.mqh>
#include <PASR/Infra/TelemetryRecorder.mqh>
#include <Trade/Trade.mqh>

#ifdef __CORE_PASR_MASTER_MQH__
#else
  class CDataManager;
  class CAnalysisSRManager;
  class CAnalysisZoneManager;
  class CPatternManager;
  class CSignalManager;
  class CAIOrchestrator;
  class CRegimeFilter;
  class CRiskManager;
  class CExecutionManager;
  class CExitEngine;
  class CRecoveryManager;
  class CDashboardManager;
  class CJournalManager;
  class CSanityManager;
  class CTelemetryRecorder;
  class CAdaptiveParameterManager;
  class CMarketRegimeDetector;
  class CLatencyOptimizer;
  class CAsyncOrderManager;
  class CHealthMonitor;
  class CSnapshotManager;
  class CTrade;
#endif

class CPipelineEngine
  {
private:
   CDataManager              *m_data;
   CAnalysisSRManager        *m_sr;
   CAnalysisZoneManager      *m_zone;
   CPatternManager           *m_pattern;
   CSignalManager            *m_signal;
   CAIOrchestrator           *m_ai_orch;
   CRegimeFilter             *m_regime;
   CRiskManager              *m_risk;
   CExecutionManager         *m_exec;
   CExitEngine               *m_exit;
   CRecoveryManager          *m_recovery;
   CDashboardManager         *m_dash;
   CJournalManager           *m_journal;
   CEventBus                 *m_bus;
   CSanityManager            *m_sanity;
   CTelemetryRecorder        *m_telemetry;
   CAdaptiveParameterManager *m_adaptive;
   CMarketRegimeDetector     *m_regime_det;
   CLatencyOptimizer         *m_optimizer;
   CAsyncOrderManager        *m_async_orders;
   CHealthMonitor            *m_health;
   CSnapshotManager          *m_snapshot;

   bool   m_debug_mode;
   bool   m_profiling_enabled;
   CPerfTimer m_stage_timer;
   CPipelineStageRegistry m_stage_registry;
   CDataSyncStage m_data_stage;
   CAnalysisSRStage m_analysis_sr_stage;
   CAnalysisZoneStage m_analysis_zone_stage;
   CPatternStage  m_pattern_stage;
   CRegimeStage   m_regime_stage;
   CSignalStage   m_signal_stage;
   CAIInferStage   m_ai_infer_stage;
   CRiskStage     m_risk_stage;
   CAdaptiveParamsStage m_adaptive_stage;
   CExecutionStage m_execution_stage;
   CPositionStage  m_position_stage;
   CRecoveryStage m_recovery_stage;
   CDashboardStage m_dashboard_stage;
   CJournalStage   m_journal_stage;
   string m_last_observability;
   ulong  m_observability_ticks;

   string SignalDirText(ENUM_SIGNAL_DIR dir) const
     {
      if(dir == SIGNAL_BUY) return "BUY";
      if(dir == SIGNAL_SELL) return "SELL";
      return "NONE";
     }

   ENUM_STAGE_RESULT SkipIfNull(const void *ptr, const string stageName)
     {
      if(ptr == NULL)
        {
         if(m_debug_mode) PrintFormat("[Pipeline] %s SKIP: manager is NULL", stageName);
         return STAGE_SKIP;
        }
      return STAGE_OK;
     }

   string BuildObservabilityText(PipelineContext &ctx, ENUM_STAGE_RESULT result)
     {
      int sourceCount = 0;
      int cooldowns = 0;
      int failedZones = 0;
      bool signalReady = false;
      string signalReason = "";
      if(m_signal != NULL)
        {
         SignalLayerSnapshot ss = m_signal.GetSnapshot();
         sourceCount = ss.sourceCount;
         cooldowns = ss.cooldownCount;
         failedZones = ss.failedZoneCount;
         signalReady = ss.ready;
         signalReason = ss.lastReason;
        }

      string riskStatus = "NA";
      int openTrades = PositionsTotal();
      double dd = 0.0;
      if(m_risk != NULL)
        {
         RiskSnapshot rs = m_risk.GetSnapshot();
         riskStatus = rs.status;
         openTrades = rs.openTrades;
         dd = rs.drawdownPct;
        }

      int execStatus = (int)ctx.exec_result.status;
      ulong ticket = ctx.exec_result.ticket;
      int retcode = ctx.exec_result.retcode;
      if(m_exec != NULL)
        {
         ExecutionSnapshot es = m_exec.GetSnapshot();
         execStatus = (int)es.lastStatus;
         ticket = es.lastTicket;
         retcode = es.lastRetcode;
        }

      int exitReason = 0;
      ulong exitTotal = 0;
      if(m_exit != NULL)
        {
         ExitSnapshot xs = m_exit.GetSnapshot();
         exitReason = (int)xs.lastSignal.reason;
         exitTotal = xs.totalExits;
        }

      bool recoveryActive = false;
      if(m_recovery != NULL)
        {
         RecoverySnapshot rec = m_recovery.GetSnapshot();
         recoveryActive = rec.active;
        }

      return StringFormat("res=%d sig=%s %.2f src=%d ready=%s cd=%d fz=%d risk=%s dd=%.2f open=%d exec=%d ret=%d tk=%I64u exit=%d/%I64u rec=%s %s",
                          (int)result,
                          SignalDirText(ctx.signal.direction),
                          ctx.signal.confidence,
                          sourceCount,
                          signalReady ? "Y" : "N",
                          cooldowns,
                          failedZones,
                          riskStatus,
                          dd,
                          openTrades,
                          execStatus,
                          retcode,
                          ticket,
                          exitReason,
                          exitTotal,
                          recoveryActive ? "Y" : "N",
                          signalReason);
     }

   void PublishObservability(PipelineContext &ctx, ENUM_STAGE_RESULT result)
     {
      m_last_observability = BuildObservabilityText(ctx, result);
      m_observability_ticks++;

      if(m_dash != NULL)
         m_dash.SetObservabilityText(m_last_observability);

      if(m_telemetry != NULL)
        {
         m_telemetry.RecordObservabilityText(m_last_observability);
         m_telemetry.RecordObservabilityMetric("SignalConfidence", ctx.signal.confidence, "normalized");
         m_telemetry.RecordObservabilityMetric("AIScore", ctx.ai_score, "score");
         m_telemetry.RecordObservabilityMetric("SpreadPts", ctx.spread_pts, "points");
         m_telemetry.RecordObservabilityMetric("Result", (double)result, "enum");
        }

      if(m_debug_mode && (ctx.new_bar || (m_observability_ticks % 100 == 0)))
         Print("[PipelineObs] ", m_last_observability);
     }

   ENUM_STAGE_RESULT Stage_DataSync(PipelineContext &ctx)
     {
      return m_data_stage.Execute(ctx);
     }

   ENUM_STAGE_RESULT Stage_AnalysisSR(PipelineContext &ctx)
     {
      return m_analysis_sr_stage.Execute(ctx);
     }

   ENUM_STAGE_RESULT Stage_AnalysisZone(PipelineContext &ctx)
     {
      return m_analysis_zone_stage.Execute(ctx);
     }

   ENUM_STAGE_RESULT Stage_PatternRec(PipelineContext &ctx)
     {
      return m_pattern_stage.Execute(ctx);
     }

   ENUM_STAGE_RESULT Stage_RegimeDet(PipelineContext &ctx)
     {
      return m_regime_stage.Execute(ctx);
     }

   ENUM_STAGE_RESULT Stage_SignalGen(PipelineContext &ctx)
     {
      return m_signal_stage.Execute(ctx);
     }

   ENUM_STAGE_RESULT Stage_AIInfer(PipelineContext &ctx)
     {
      return m_ai_infer_stage.Execute(ctx);
     }

   ENUM_STAGE_RESULT Stage_RiskCheck(PipelineContext &ctx)
     {
      return m_risk_stage.Execute(ctx);
     }

   ENUM_STAGE_RESULT Stage_AdaptiveParams(PipelineContext &ctx)
     {
      return m_adaptive_stage.Execute(ctx);
     }

   ENUM_STAGE_RESULT Stage_Execution(PipelineContext &ctx)
     {
      return m_execution_stage.Execute(ctx);
     }

   ENUM_STAGE_RESULT Stage_PosMgmt(PipelineContext &ctx)
     {
      return m_position_stage.Execute(ctx);
     }

   ENUM_STAGE_RESULT Stage_Recovery(PipelineContext &ctx)
     {
      return m_recovery_stage.Execute(ctx);
     }

   ENUM_STAGE_RESULT Stage_Dashboard(PipelineContext &ctx)
     {
      m_dashboard_stage.SetObservabilityText(m_last_observability);
      return m_dashboard_stage.Execute(ctx);
     }

   ENUM_STAGE_RESULT Stage_Journal(PipelineContext &ctx)
     {
      m_journal_stage.SetObservabilityText(m_last_observability);
      return m_journal_stage.Execute(ctx);
     }

   ENUM_STAGE_RESULT ExecuteStageById(const ENUM_PIPELINE_STAGE_ID id, PipelineContext &ctx)
     {
      switch(id)
        {
         case PIPE_STAGE_DATA_SYNC:       return Stage_DataSync(ctx);
         case PIPE_STAGE_ANALYSIS_SR:     return Stage_AnalysisSR(ctx);
         case PIPE_STAGE_ANALYSIS_ZONE:   return Stage_AnalysisZone(ctx);
         case PIPE_STAGE_PATTERN_REC:     return Stage_PatternRec(ctx);
         case PIPE_STAGE_REGIME_DET:      return Stage_RegimeDet(ctx);
         case PIPE_STAGE_SIGNAL_GEN:      return Stage_SignalGen(ctx);
         case PIPE_STAGE_AI_INFER:        return Stage_AIInfer(ctx);
         case PIPE_STAGE_RISK_CHECK:      return Stage_RiskCheck(ctx);
         case PIPE_STAGE_ADAPTIVE_PARAMS: return Stage_AdaptiveParams(ctx);
         case PIPE_STAGE_EXECUTION:       return Stage_Execution(ctx);
         case PIPE_STAGE_POSITION_MGMT:   return Stage_PosMgmt(ctx);
         case PIPE_STAGE_RECOVERY:        return Stage_Recovery(ctx);
         case PIPE_STAGE_DASHBOARD:       return Stage_Dashboard(ctx);
         case PIPE_STAGE_JOURNAL:         return Stage_Journal(ctx);
         default:                         return STAGE_SKIP;
        }
     }

   ENUM_STAGE_RESULT RunRegisteredStages(PipelineContext &ctx)
     {
      ENUM_STAGE_RESULT r = STAGE_OK;
      int total = m_stage_registry.Count();
      for(int i = 0; i < total; i++)
        {
         ENUM_PIPELINE_STAGE_ID id = m_stage_registry.IdAt(i);
         if(!m_stage_registry.IsEnabled(id))
           {
            m_stage_registry.Record(id, STAGE_SKIP);
            continue;
           }

         r = ExecuteStageById(id, ctx);
         m_stage_registry.Record(id, r);

         if(r == STAGE_ABORT)
           {
            ctx.exit_reason = STAGE_ABORT;
            return STAGE_ABORT;
           }
        }
      return STAGE_OK;
     }

public:
   CPipelineEngine()
      : m_data(NULL), m_sr(NULL), m_zone(NULL), m_pattern(NULL), m_signal(NULL),
        m_ai_orch(NULL), m_regime(NULL), m_risk(NULL), m_exec(NULL), m_exit(NULL),
        m_recovery(NULL), m_dash(NULL), m_journal(NULL), m_bus(NULL),
        m_sanity(NULL), m_telemetry(NULL), m_adaptive(NULL), m_regime_det(NULL),
        m_optimizer(NULL), m_async_orders(NULL), m_health(NULL), m_snapshot(NULL),
        m_debug_mode(false), m_profiling_enabled(true), m_last_observability(""),
        m_observability_ticks(0)
     {
      m_stage_registry.RegisterDefaultStages();
     }

   void SetDebugMode(bool on)
     {
      m_debug_mode = on;
      m_stage_registry.SetDebugMode(on);
      m_data_stage.SetDebugMode(on);
      m_analysis_sr_stage.SetDebugMode(on);
      m_analysis_zone_stage.SetDebugMode(on);
      m_pattern_stage.SetDebugMode(on);
      m_regime_stage.SetDebugMode(on);
      m_signal_stage.SetDebugMode(on);
      m_risk_stage.SetDebugMode(on);
      m_adaptive_stage.SetDebugMode(on);
      m_execution_stage.SetDebugMode(on);
      m_position_stage.SetDebugMode(on);
      m_recovery_stage.SetDebugMode(on);
      m_dashboard_stage.SetDebugMode(on);
      m_journal_stage.SetDebugMode(on);
     }

   void EnableProfiling(bool on)
     {
      m_profiling_enabled = on;
      m_data_stage.EnableProfiling(on);
      m_analysis_sr_stage.EnableProfiling(on);
      m_analysis_zone_stage.EnableProfiling(on);
      m_pattern_stage.EnableProfiling(on);
      m_regime_stage.EnableProfiling(on);
      m_signal_stage.EnableProfiling(on);
      m_risk_stage.EnableProfiling(on);
      m_adaptive_stage.EnableProfiling(on);
      m_execution_stage.EnableProfiling(on);
      m_position_stage.EnableProfiling(on);
      m_recovery_stage.EnableProfiling(on);
      m_dashboard_stage.EnableProfiling(on);
      m_journal_stage.EnableProfiling(on);
     }

   void InjectManagers(CDataManager *data, CAnalysisSRManager *sr, CAnalysisZoneManager *zone,
      CPatternManager *pattern, CSignalManager *signal, CAIOrchestrator *ai_orch,
      CRegimeFilter *regime, CRiskManager *risk, CExecutionManager *exec,
      CRecoveryManager *recovery, CDashboardManager *dash, CJournalManager *journal,
      CEventBus *bus, CSanityManager *sanity, CTelemetryRecorder *telemetry,
      CAdaptiveParameterManager *adaptive, CMarketRegimeDetector *regime_det,
      CLatencyOptimizer *optimizer=NULL, CAsyncOrderManager *async_orders=NULL,
      CHealthMonitor *health=NULL, CSnapshotManager *snapshot=NULL,
      CExitEngine *exit_engine=NULL)
     {
      m_data=data; m_sr=sr; m_zone=zone; m_pattern=pattern; m_signal=signal;
      m_ai_orch=ai_orch; m_regime=regime; m_risk=risk; m_exec=exec;
      m_exit=exit_engine; m_recovery=recovery; m_dash=dash; m_journal=journal; m_bus=bus;
      m_sanity=sanity; m_telemetry=telemetry; m_adaptive=adaptive;
      m_regime_det=regime_det; m_optimizer=optimizer; m_async_orders=async_orders;
      m_health=health; m_snapshot=snapshot;
      m_data_stage.Bind(m_data);
      m_analysis_sr_stage.Bind(m_sr, m_bus);
      m_analysis_zone_stage.Bind(m_zone);
      m_pattern_stage.Bind(m_pattern);
      m_regime_stage.Bind(m_regime, m_regime_det);
      m_signal_stage.Bind(m_signal, m_ai_orch, m_sr, m_pattern);
      m_ai_infer_stage.Bind(m_ai_orch);
      m_risk_stage.Bind(m_risk);
      m_adaptive_stage.Bind(m_adaptive);
      m_execution_stage.Bind(m_exec, m_recovery);
      m_position_stage.Bind(m_exit, m_data);
      m_recovery_stage.Bind(m_recovery);
      m_dashboard_stage.Bind(m_dash);
      m_journal_stage.Bind(m_journal);
      if(m_stage_registry.Count() == 0)
         m_stage_registry.RegisterDefaultStages();
     }

   bool EnableStage(ENUM_PIPELINE_STAGE_ID id, bool enabled)
     {
      return m_stage_registry.SetEnabled(id, enabled);
     }

   int StageCount() const
     {
      return m_stage_registry.Count();
     }

   string StageNameAt(int index) const
     {
      return m_stage_registry.NameAt(index);
     }

   int GetStageCount() const
     {
      return StageCount();
     }

   string GetStageName(int index) const
     {
      return StageNameAt(index);
     }

   bool InitializeWithMocks(CEventBus *bus, CDataManager *data)
     {
      if(bus == NULL || data == NULL)
         return false;

      InjectManagers(data, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
                     NULL, NULL, NULL, bus, NULL, NULL, NULL, NULL);
      return true;
     }

   ENUM_STAGE_RESULT RunStage(int index, PipelineContext &ctx)
     {
      if(m_stage_registry.Count() == 0)
         m_stage_registry.RegisterDefaultStages();

      ENUM_PIPELINE_STAGE_ID id = m_stage_registry.IdAt(index);
      if(id == PIPE_STAGE_NONE)
         return STAGE_SKIP;

      if(!m_stage_registry.IsEnabled(id))
        {
         m_stage_registry.Record(id, STAGE_SKIP);
         return STAGE_SKIP;
        }

      ENUM_STAGE_RESULT result = ExecuteStageById(id, ctx);
      m_stage_registry.Record(id, result);
      return result;
     }

   string LastObservabilityText() const
     {
      return m_last_observability;
     }

   void PrintStageSummary() const
     {
      m_stage_registry.PrintSummary();
     }

   ENUM_STAGE_RESULT ExecutePipeline(PipelineContext &ctx)
     {
      if(m_stage_registry.Count() == 0)
         m_stage_registry.RegisterDefaultStages();

      if(ctx.health_status < 0)
        {
         ctx.exit_reason = STAGE_ABORT;
         ctx.exit_message = "Health gate: critical status";
         PublishObservability(ctx, STAGE_ABORT);
         return STAGE_ABORT;
        }

      if(ctx.session_dd > 0.0 && ctx.max_session_dd > 0.0 && ctx.session_dd >= ctx.max_session_dd)
        {
         PublishObservability(ctx, STAGE_SKIP);
         ENUM_STAGE_RESULT rd = Stage_Dashboard(ctx);
         m_stage_registry.Record(PIPE_STAGE_DASHBOARD, rd);
         ENUM_STAGE_RESULT rj = Stage_Journal(ctx);
         m_stage_registry.Record(PIPE_STAGE_JOURNAL, rj);
         ctx.exit_reason = STAGE_SKIP;
         return STAGE_SKIP;
        }

      ENUM_STAGE_RESULT result = RunRegisteredStages(ctx);
      PublishObservability(ctx, result);
      if(result == STAGE_ABORT)
         return result;

      ctx.exit_reason = STAGE_OK;
      return STAGE_OK;
     }
  };

#endif // __CORE_PIPELINE_ENGINE_MQH__
