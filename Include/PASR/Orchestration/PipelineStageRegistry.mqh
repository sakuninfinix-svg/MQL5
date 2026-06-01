//+------------------------------------------------------------------+
//| Orchestration/PipelineStageRegistry.mqh — v0.20                  |
//| Declarative stage table for Centralized Modular Pipeline          |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_ORCHESTRATION_PIPELINE_STAGE_REGISTRY_MQH__
#define __PASR_ORCHESTRATION_PIPELINE_STAGE_REGISTRY_MQH__

#include <PASR/Core/PipelineTypes.mqh>

#ifndef PASR_PIPELINE_STAGE_CAPACITY
#define PASR_PIPELINE_STAGE_CAPACITY 32
#endif

#define PASR_STAGE_NAME_DATA_SYNC       "DataSync"
#define PASR_STAGE_NAME_ANALYSIS_SR     "AnalysisSR"
#define PASR_STAGE_NAME_ANALYSIS_ZONE   "AnalysisZone"
#define PASR_STAGE_NAME_PATTERN_REC     "PatternRec"
#define PASR_STAGE_NAME_REGIME_DET      "RegimeDet"
#define PASR_STAGE_NAME_SIGNAL_GEN      "SignalGen"
#define PASR_STAGE_NAME_AI_INFER        "AIInfer"
#define PASR_STAGE_NAME_RISK_CHECK      "RiskCheck"
#define PASR_STAGE_NAME_ADAPTIVE_PARAMS "AdaptiveParams"
#define PASR_STAGE_NAME_EXECUTION       "Execution"
#define PASR_STAGE_NAME_POSITION_MGMT   "PositionMgmt"
#define PASR_STAGE_NAME_RECOVERY        "Recovery"
#define PASR_STAGE_NAME_DASHBOARD       "Dashboard"
#define PASR_STAGE_NAME_JOURNAL         "Journal"

enum ENUM_PIPELINE_STAGE_ID
  {
   PIPE_STAGE_NONE            = 0,
   PIPE_STAGE_DATA_SYNC       = 10,
   PIPE_STAGE_ANALYSIS_SR     = 20,
   PIPE_STAGE_ANALYSIS_ZONE   = 30,
   PIPE_STAGE_PATTERN_REC     = 40,
   PIPE_STAGE_REGIME_DET      = 50,
   PIPE_STAGE_SIGNAL_GEN      = 60,
   PIPE_STAGE_AI_INFER        = 70,
   PIPE_STAGE_RISK_CHECK      = 80,
   PIPE_STAGE_ADAPTIVE_PARAMS = 90,
   PIPE_STAGE_EXECUTION       = 100,
   PIPE_STAGE_POSITION_MGMT   = 110,
   PIPE_STAGE_RECOVERY        = 120,
   PIPE_STAGE_DASHBOARD       = 130,
   PIPE_STAGE_JOURNAL         = 140
  };

struct SPipelineStageInfo
  {
   ENUM_PIPELINE_STAGE_ID id;
   string                 name;
   bool                   enabled;
   ENUM_STAGE_RESULT      lastResult;
   ulong                  calls;
   ulong                  okCount;
   ulong                  skipCount;
   ulong                  abortCount;

   void Clear()
     {
      id = PIPE_STAGE_NONE;
      name = "";
      enabled = false;
      lastResult = STAGE_SKIP;
      calls = 0;
      okCount = 0;
      skipCount = 0;
      abortCount = 0;
     }

   void Init(ENUM_PIPELINE_STAGE_ID stageId, string stageName, bool isEnabled = true)
     {
      Clear();
      id = stageId;
      name = stageName;
      enabled = isEnabled;
     }

   void Record(ENUM_STAGE_RESULT result)
     {
      lastResult = result;
      calls++;
      if(result == STAGE_OK) okCount++;
      else if(result == STAGE_SKIP) skipCount++;
      else if(result == STAGE_ABORT) abortCount++;
     }
  };

class CPipelineStageRegistry
  {
private:
   SPipelineStageInfo m_stages[PASR_PIPELINE_STAGE_CAPACITY];
   int                m_count;
   bool               m_debug;

   int FindIndexById(ENUM_PIPELINE_STAGE_ID id) const
     {
      for(int i = 0; i < m_count; i++)
         if(m_stages[i].id == id)
            return i;
      return -1;
     }

public:
   CPipelineStageRegistry() : m_count(0), m_debug(false)
     {
      Clear();
     }

   void SetDebugMode(bool enabled)
     {
      m_debug = enabled;
     }

   void Clear()
     {
      for(int i = 0; i < PASR_PIPELINE_STAGE_CAPACITY; i++)
         m_stages[i].Clear();
      m_count = 0;
     }

   bool RegisterStage(ENUM_PIPELINE_STAGE_ID id, string name, bool enabled = true)
     {
      if(id == PIPE_STAGE_NONE || name == "") return false;
      int idx = FindIndexById(id);
      if(idx >= 0)
        {
         m_stages[idx].Init(id, name, enabled);
         return true;
        }
      if(m_count >= PASR_PIPELINE_STAGE_CAPACITY) return false;
      m_stages[m_count].Init(id, name, enabled);
      m_count++;
      return true;
     }

   void RegisterDefaultStages()
     {
      Clear();
      RegisterStage(PIPE_STAGE_DATA_SYNC,       PASR_STAGE_NAME_DATA_SYNC,       true);
      RegisterStage(PIPE_STAGE_ANALYSIS_SR,     PASR_STAGE_NAME_ANALYSIS_SR,     true);
      RegisterStage(PIPE_STAGE_ANALYSIS_ZONE,   PASR_STAGE_NAME_ANALYSIS_ZONE,   true);
      RegisterStage(PIPE_STAGE_PATTERN_REC,     PASR_STAGE_NAME_PATTERN_REC,     true);
      RegisterStage(PIPE_STAGE_REGIME_DET,      PASR_STAGE_NAME_REGIME_DET,      true);
      RegisterStage(PIPE_STAGE_SIGNAL_GEN,      PASR_STAGE_NAME_SIGNAL_GEN,      true);
      RegisterStage(PIPE_STAGE_AI_INFER,        PASR_STAGE_NAME_AI_INFER,        true);
      RegisterStage(PIPE_STAGE_RISK_CHECK,      PASR_STAGE_NAME_RISK_CHECK,      true);
      RegisterStage(PIPE_STAGE_ADAPTIVE_PARAMS, PASR_STAGE_NAME_ADAPTIVE_PARAMS, true);
      RegisterStage(PIPE_STAGE_EXECUTION,       PASR_STAGE_NAME_EXECUTION,       true);
      RegisterStage(PIPE_STAGE_POSITION_MGMT,   PASR_STAGE_NAME_POSITION_MGMT,   true);
      RegisterStage(PIPE_STAGE_RECOVERY,        PASR_STAGE_NAME_RECOVERY,        true);
      RegisterStage(PIPE_STAGE_DASHBOARD,       PASR_STAGE_NAME_DASHBOARD,       true);
      RegisterStage(PIPE_STAGE_JOURNAL,         PASR_STAGE_NAME_JOURNAL,         true);
     }

   bool SetEnabled(ENUM_PIPELINE_STAGE_ID id, bool enabled)
     {
      int idx = FindIndexById(id);
      if(idx < 0) return false;
      m_stages[idx].enabled = enabled;
      return true;
     }

   bool IsEnabled(ENUM_PIPELINE_STAGE_ID id) const
     {
      int idx = FindIndexById(id);
      if(idx < 0) return false;
      return m_stages[idx].enabled;
     }

   void Record(ENUM_PIPELINE_STAGE_ID id, ENUM_STAGE_RESULT result)
     {
      int idx = FindIndexById(id);
      if(idx < 0) return;
      m_stages[idx].Record(result);
     }

   int Count() const { return m_count; }

   ENUM_PIPELINE_STAGE_ID IdAt(int index) const
     {
      if(index < 0 || index >= m_count) return PIPE_STAGE_NONE;
      return m_stages[index].id;
     }

   string NameAt(int index) const
     {
      if(index < 0 || index >= m_count) return "";
      return m_stages[index].name;
     }

   ENUM_STAGE_RESULT LastResultAt(int index) const
     {
      if(index < 0 || index >= m_count) return STAGE_SKIP;
      return m_stages[index].lastResult;
     }

   bool GetStage(ENUM_PIPELINE_STAGE_ID id, SPipelineStageInfo &out) const
     {
      int idx = FindIndexById(id);
      if(idx < 0) return false;
      out = m_stages[idx];
      return true;
     }

   void PrintSummary() const
     {
      PrintFormat("[PipelineStageRegistry] stages=%d", m_count);
      for(int i = 0; i < m_count; i++)
        {
         PrintFormat("[PipelineStageRegistry] %02d %s enabled=%s calls=%I64u ok=%I64u skip=%I64u abort=%I64u last=%d",
                     i,
                     m_stages[i].name,
                     m_stages[i].enabled ? "true" : "false",
                     m_stages[i].calls,
                     m_stages[i].okCount,
                     m_stages[i].skipCount,
                     m_stages[i].abortCount,
                     (int)m_stages[i].lastResult);
        }
     }
  };

#endif // __PASR_ORCHESTRATION_PIPELINE_STAGE_REGISTRY_MQH__
