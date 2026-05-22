//+------------------------------------------------------------------+
//|                                           PatternPipeline.mqh    |
//|                                 Copyright 2024, PASR Architecture|
//|                                     https://pasr-architecture.com|
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, PASR Architecture"
#property link      "https://pasr-architecture.com"
#property version   "1.00"
//+------------------------------------------------------------------+
//| Pattern Pipeline Engine - Orchestrator untuk pattern detection   |
//+------------------------------------------------------------------+
#include "Core\IPatternStage.mqh"
#include "Core\PatternContext.mqh"
#include <Arrays\ArrayObj.mqh>

//+------------------------------------------------------------------+
//| Enum untuk pipeline status                                       |
//+------------------------------------------------------------------+
enum ENUM_PIPELINE_STATUS
{
   PIPELINE_IDLE      = 0,  // Tidak aktif
   PIPELINE_RUNNING   = 1,  // Sedang berjalan
   PIPELINE_COMPLETED = 2,  // Selesai
   PIPELINE_ERROR     = 3,  // Error
   PIPELINE_ABORTED   = 4   // Dibatalkan
};

//+------------------------------------------------------------------+
//| Class PatternPipeline                                            |
//+------------------------------------------------------------------+
class CPatternPipeline
{
private:
   string              m_name;              // Pipeline name
   CArrayObj           m_stages;            // Array of IPatternStage*
   CPatternContext     m_context;           // Context object
   ENUM_PIPELINE_STATUS m_status;           // Current status
   datetime            m_lastRun;           // Last run timestamp
   int                 m_totalRuns;         // Total runs counter
   int                 m_successfulRuns;    // Successful runs counter
   
   // Statistics
   int                 m_totalPatterns;     // Total patterns detected
   double              m_avgScore;          // Average score
   
public:
   CPatternPipeline(const string name = "DefaultPipeline") : 
      m_name(name), m_status(PIPELINE_IDLE), m_lastRun(0),
      m_totalRuns(0), m_successfulRuns(0), m_totalPatterns(0), m_avgScore(0)
   {
      m_stages.Init();
   }
   
   ~CPatternPipeline()
   {
      Clear();
   }
   
   //+------------------------------------------------------------------+
   //| Get/Set pipeline name                                            |
   //+------------------------------------------------------------------+
   void SetName(const string name) { m_name = name; }
   string GetName() const { return m_name; }
   
   //+------------------------------------------------------------------+
   //| Add a stage to the pipeline                                      |
   //+------------------------------------------------------------------+
   bool AddStage(IPatternStage *stage)
   {
      if(stage == NULL)
      {
         LogStageMessage(m_name, "Cannot add NULL stage", LOG_ERROR);
         return false;
      }
      
      // Check for duplicate names
      for(int i = 0; i < m_stages.Total(); i++)
      {
         IPatternStage *existing = m_stages.At(i);
         if(existing != NULL && existing->GetName() == stage->GetName())
         {
            LogStageMessage(m_name, StringFormat("Duplicate stage name: %s", 
                              stage->GetName()), LOG_WARNING);
            return false;
         }
      }
      
      // Initialize stage
      if(!stage->Init())
      {
         LogStageMessage(m_name, StringFormat("Failed to initialize stage: %s", 
                           stage->GetName()), LOG_ERROR);
         delete stage;
         return false;
      }
      
      m_stages.Add(stage);
      LogStageMessage(m_name, StringFormat("Added stage: %s", stage->GetName()), LOG_DEBUG);
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Remove a stage by name                                           |
   //+------------------------------------------------------------------+
   bool RemoveStage(const string stageName)
   {
      for(int i = 0; i < m_stages.Total(); i++)
      {
         IPatternStage *stage = m_stages.At(i);
         if(stage != NULL && stage->GetName() == stageName)
         {
            stage->Shutdown();
            delete stage;
            m_stages.Delete(i);
            LogStageMessage(m_name, StringFormat("Removed stage: %s", stageName), LOG_INFO);
            return true;
         }
      }
      
      LogStageMessage(m_name, StringFormat("Stage not found: %s", stageName), LOG_WARNING);
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| Enable/Disable a stage                                           |
   //+------------------------------------------------------------------+
   bool SetStageEnabled(const string stageName, bool enabled)
   {
      for(int i = 0; i < m_stages.Total(); i++)
      {
         IPatternStage *stage = m_stages.At(i);
         if(stage != NULL && stage->GetName() == stageName)
         {
            stage->Enable(enabled);
            LogStageMessage(m_name, StringFormat("Stage %s %s", 
                              stageName, enabled ? "enabled" : "disabled"), LOG_INFO);
            return true;
         }
      }
      
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| Get stage count                                                  |
   //+------------------------------------------------------------------+
   int GetStageCount() const { return m_stages.Total(); }
   
   IPatternStage* GetStage(int index)
   {
      return m_stages.At(index);
   }
   
   IPatternStage* GetStageByName(const string name)
   {
      for(int i = 0; i < m_stages.Total(); i++)
      {
         IPatternStage *stage = m_stages.At(i);
         if(stage != NULL && stage->GetName() == name)
            return stage;
      }
      return NULL;
   }
   
   //+------------------------------------------------------------------+
   //| Execute the pipeline                                             |
   //+------------------------------------------------------------------+
   ENUM_PIPELINE_STATUS Execute(CPatternContext &context)
   {
      if(m_status == PIPELINE_RUNNING)
      {
         LogStageMessage(m_name, "Pipeline already running", LOG_WARNING);
         return PIPELINE_ERROR;
      }
      
      if(!context.IsValid())
      {
         LogStageMessage(m_name, "Invalid context", LOG_ERROR);
         return PIPELINE_ERROR;
      }
      
      m_status = PIPELINE_RUNNING;
      m_lastRun = TimeCurrent();
      m_totalRuns++;
      
      LogStageMessage(m_name, StringFormat("Starting pipeline execution with %d stages", 
                        m_stages.Total()), LOG_INFO);
      
      // Clear previous results
      context.ClearResults();
      
      // Execute each stage in order
      ENUM_STAGE_STATUS stageStatus = STAGE_OK;
      int processedStages = 0;
      
      for(int i = 0; i < m_stages.Total(); i++)
      {
         IPatternStage *stage = m_stages.At(i);
         if(stage == NULL)
            continue;
         
         if(!stage->IsEnabled())
         {
            LogStageMessage(m_name, StringFormat("Skipping disabled stage: %s", 
                              stage->GetName()), LOG_DEBUG);
            continue;
         }
         
         LogStageMessage(m_name, StringFormat("Executing stage %d/%d: %s", 
                           i + 1, m_stages.Total(), stage->GetName()), LOG_DEBUG);
         
         stageStatus = stage->Process(context);
         processedStages++;
         
         // Handle stage status
         if(stageStatus == STAGE_ABORT)
         {
            LogStageMessage(m_name, StringFormat("Stage %s aborted pipeline", 
                              stage->GetName()), LOG_WARNING);
            m_status = PIPELINE_ABORTED;
            return m_status;
         }
         else if(stageStatus == STAGE_FAIL)
         {
            LogStageMessage(m_name, StringFormat("Stage %s failed", 
                              stage->GetName()), LOG_ERROR);
            // Continue with next stage (fail doesn't stop pipeline)
         }
         else if(stageStatus == STAGE_SKIP)
         {
            LogStageMessage(m_name, StringFormat("Stage %s skipped", 
                              stage->GetName()), LOG_DEBUG);
         }
         else
         {
            LogStageMessage(m_name, StringFormat("Stage %s completed successfully", 
                              stage->GetName()), LOG_DEBUG);
         }
      }
      
      // Pipeline completed
      m_status = PIPELINE_COMPLETED;
      m_successfulRuns++;
      
      // Update statistics
      m_totalPatterns += context.GetResultCount();
      if(m_totalPatterns > 0)
      {
         m_avgScore = context.GetOverallScore();
      }
      
      LogStageMessage(m_name, StringFormat("Pipeline completed. Patterns found: %d, Score: %.2f", 
                        context.GetResultCount(), context.GetOverallScore()), LOG_INFO);
      
      return m_status;
   }
   
   //+------------------------------------------------------------------+
   //| Get current status                                               |
   //+------------------------------------------------------------------+
   ENUM_PIPELINE_STATUS GetStatus() const { return m_status; }
   datetime GetLastRun() const { return m_lastRun; }
   int GetTotalRuns() const { return m_totalRuns; }
   int GetSuccessfulRuns() const { return m_successfulRuns; }
   int GetTotalPatternsDetected() const { return m_totalPatterns; }
   double GetAverageScore() const { return m_avgScore; }
   
   //+------------------------------------------------------------------+
   //| Get success rate                                                 |
   //+------------------------------------------------------------------+
   double GetSuccessRate() const
   {
      if(m_totalRuns == 0)
         return 0.0;
      return (double)m_successfulRuns / (double)m_totalRuns * 100.0;
   }
   
   //+------------------------------------------------------------------+
   //| Clear all stages                                                 |
   //+------------------------------------------------------------------+
   void Clear()
   {
      for(int i = m_stages.Total() - 1; i >= 0; i--)
      {
         IPatternStage *stage = m_stages.At(i);
         if(stage != NULL)
         {
            stage->Shutdown();
            delete stage;
         }
      }
      m_stages.Clear();
      m_status = PIPELINE_IDLE;
   }
   
   //+------------------------------------------------------------------+
   //| Get pipeline description                                         |
   //+------------------------------------------------------------------+
   string ToString() const
   {
      string desc = StringFormat("Pipeline[%s] Status=%s Stages=%d Runs=%d SuccessRate=%.1f%%",
                                m_name,
                                EnumToString(m_status),
                                m_stages.Total(),
                                m_totalRuns,
                                GetSuccessRate());
      return desc;
   }
   
   //+------------------------------------------------------------------+
   //| Get detailed report                                              |
   //+------------------------------------------------------------------+
   string GetReport() const
   {
      string report = "=== Pattern Pipeline Report ===\n";
      report += StringFormat("Name: %s\n", m_name);
      report += StringFormat("Status: %s\n", EnumToString(m_status));
      report += StringFormat("Total Runs: %d\n", m_totalRuns);
      report += StringFormat("Successful Runs: %d\n", m_successfulRuns);
      report += StringFormat("Success Rate: %.2f%%\n", GetSuccessRate());
      report += StringFormat("Total Patterns: %d\n", m_totalPatterns);
      report += StringFormat("Avg Score: %.2f\n", m_avgScore);
      report += StringFormat("Last Run: %s\n", TimeToString(m_lastRun));
      report += "\n--- Stages ---\n";
      
      for(int i = 0; i < m_stages.Total(); i++)
      {
         IPatternStage *stage = m_stages.At(i);
         if(stage != NULL)
         {
            report += StringFormat("%d. %s [%s]\n", 
                                  i + 1, 
                                  stage->GetName(),
                                  stage->IsEnabled() ? "Enabled" : "Disabled");
         }
      }
      
      return report;
   }
};
//+------------------------------------------------------------------+
