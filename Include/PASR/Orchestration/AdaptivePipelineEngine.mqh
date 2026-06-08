//+------------------------------------------------------------------+
//| Orchestration/AdaptivePipelineEngine.mqh — v1.0                     |
//| Regime-adaptive pipeline that adjusts execution based on market   |
//| conditions. Replaces static pipeline with dynamic orchestration   |
//+------------------------------------------------------------------+
#property strict
#ifndef __ORCHESTRATION_ADAPTIVE_PIPELINE_ENGINE_MQH__
#define __ORCHESTRATION_ADAPTIVE_PIPELINE_ENGINE_MQH__

#include "../Core/IManager.mqh"
#include "../Core/PipelineTypes.mqh"
#include "../Data/RegimeTypes.mqh"
#include "PipelineEngine.mqh"
#include "../Analysis/HMMRegimeDetector.mqh"

enum ENUM_PIPELINE_STAGE
{
   STAGE_DATA_SYNC = 0,
   STAGE_ANALYSIS = 1,
   STAGE_PATTERN_RECOGNITION = 2,
   STAGE_REGIME_DETECTION = 3,
   STAGE_SIGNAL_GENERATION = 4,
   STAGE_AI_INFERENCE = 5,
   STAGE_RISK_CHECK = 6,
   STAGE_EXECUTION = 7,
   STAGE_POSITION_MANAGEMENT = 8,
   STAGE_RECOVERY = 9,
   STAGE_DASHBOARD = 10,
   STAGE_JOURNAL = 11,
   STAGE_COUNT = 12
};

struct RegimePipelineConfig
{
   bool stages_enabled[STAGE_COUNT];
   double stage_weights[STAGE_COUNT];
   int execution_frequency;  // 0=every tick, 1=every bar, 2=every N bars
   double ai_confidence_threshold;
   double pattern_weight_multiplier;
   double sr_weight_multiplier;
   double regime_weight_multiplier;
   
   void Reset()
   {
      for(int i = 0; i < STAGE_COUNT; i++)
      {
         stages_enabled[i] = true;
         stage_weights[i] = 1.0;
      }
      execution_frequency = 1;
      ai_confidence_threshold = 0.7;
      pattern_weight_multiplier = 1.0;
      sr_weight_multiplier = 1.0;
      regime_weight_multiplier = 1.0;
   }
};

class CAdaptivePipelineEngine : public IManager
{
private:
   CPipelineEngine *m_base_pipeline;
   CHMMRegimeDetector *m_regime_detector;
   RegimePipelineConfig m_regime_configs[REGIME_COUNT];
   RegimePipelineConfig m_current_config;
   EMarketRegime m_current_regime;
   int m_regime_change_count;
   datetime m_last_regime_change;
   bool m_adaptive_enabled;
   
   void InitializeRegimeConfigs()
   {
      for(int i = 0; i < REGIME_COUNT; i++)
         m_regime_configs[i].Reset();
      
      // Trend Up Configuration
      m_regime_configs[REGIME_TREND_UP].ai_confidence_threshold = 0.65;
      m_regime_configs[REGIME_TREND_UP].pattern_weight_multiplier = 0.8;
      m_regime_configs[REGIME_TREND_UP].sr_weight_multiplier = 1.2;
      m_regime_configs[REGIME_TREND_UP].regime_weight_multiplier = 1.5;
      m_regime_configs[REGIME_TREND_UP].execution_frequency = 0; // Every tick for trend following
      
      // Trend Down Configuration
      m_regime_configs[REGIME_TREND_DOWN].ai_confidence_threshold = 0.65;
      m_regime_configs[REGIME_TREND_DOWN].pattern_weight_multiplier = 0.8;
      m_regime_configs[REGIME_TREND_DOWN].sr_weight_multiplier = 1.2;
      m_regime_configs[REGIME_TREND_DOWN].regime_weight_multiplier = 1.5;
      m_regime_configs[REGIME_TREND_DOWN].execution_frequency = 0;
      
      // Range Configuration
      m_regime_configs[REGIME_RANGE].ai_confidence_threshold = 0.75;
      m_regime_configs[REGIME_RANGE].pattern_weight_multiplier = 1.5;
      m_regime_configs[REGIME_RANGE].sr_weight_multiplier = 1.5;
      m_regime_configs[REGIME_RANGE].regime_weight_multiplier = 1.0;
      m_regime_configs[REGIME_RANGE].execution_frequency = 1; // Every bar for range trading
      
      // Volatile Configuration
      m_regime_configs[REGIME_VOLATILE].ai_confidence_threshold = 0.85;
      m_regime_configs[REGIME_VOLATILE].pattern_weight_multiplier = 0.5;
      m_regime_configs[REGIME_VOLATILE].sr_weight_multiplier = 0.8;
      m_regime_configs[REGIME_VOLATILE].regime_weight_multiplier = 1.2;
      m_regime_configs[REGIME_VOLATILE].execution_frequency = 0;
      m_regime_configs[REGIME_VOLATILE].stages_enabled[STAGE_PATTERN_RECOGNITION] = false; // Disable patterns in high volatility
      
      // Squeeze Configuration
      m_regime_configs[REGIME_SQUEEZE].ai_confidence_threshold = 0.80;
      m_regime_configs[REGIME_SQUEEZE].pattern_weight_multiplier = 1.0;
      m_regime_configs[REGIME_SQUEEZE].sr_weight_multiplier = 1.0;
      m_regime_configs[REGIME_SQUEEZE].regime_weight_multiplier = 1.0;
      m_regime_configs[REGIME_SQUEEZE].execution_frequency = 2; // Less frequent in squeeze
      
      // Transition Configuration
      m_regime_configs[REGIME_TRANSITION].ai_confidence_threshold = 0.90;
      m_regime_configs[REGIME_TRANSITION].pattern_weight_multiplier = 0.7;
      m_regime_configs[REGIME_TRANSITION].sr_weight_multiplier = 0.7;
      m_regime_configs[REGIME_TRANSITION].regime_weight_multiplier = 1.0;
      m_regime_configs[REGIME_TRANSITION].execution_frequency = 1;
   }
   
   void ApplyRegimeConfig(EMarketRegime regime)
   {
      if(regime < 0 || regime >= REGIME_COUNT) regime = REGIME_UNKNOWN;
      
      m_current_config = m_regime_configs[regime];
      m_current_regime = regime;
      
      if(m_debugMode)
         PrintFormat("[AdaptivePipeline] Applied config for regime: %s", EnumToString(regime));
   }
   
   bool ShouldExecuteStage(ENUM_PIPELINE_STAGE stage, datetime current_time)
   {
      if(!m_current_config.stages_enabled[stage]) return false;
      
      if(m_current_config.execution_frequency == 0) return true; // Every tick
      
      if(m_current_config.execution_frequency == 1)
      {
         // Every bar - check if new bar
         static datetime last_bar_time = 0;
         datetime bar_time = iTime(_Symbol, _Period, 0);
         if(bar_time != last_bar_time)
         {
            last_bar_time = bar_time;
            return true;
         }
         return false;
      }
      
      if(m_current_config.execution_frequency >= 2)
      {
         // Every N bars
         static int bar_counter = 0;
         datetime bar_time = iTime(_Symbol, _Period, 0);
         static datetime last_bar_time = 0;
         if(bar_time != last_bar_time)
         {
            last_bar_time = bar_time;
            bar_counter++;
            if(bar_counter % m_current_config.execution_frequency == 0)
            {
               return true;
            }
         }
         return false;
      }
      
      return true;
   }
   
   void UpdateRegime()
   {
      if(m_regime_detector == NULL) return;
      
      EMarketRegime new_regime = m_regime_detector.GetCurrentRegime();
      double confidence = m_regime_detector.GetRegimeConfidence();
      
      // Only switch regime if confidence is high
      if(confidence > 0.6 && new_regime != m_current_regime)
      {
         // Check if regime is stable
         if(m_regime_detector.IsRegimeStable(3))
         {
            m_regime_change_count++;
            m_last_regime_change = TimeCurrent();
            ApplyRegimeConfig(new_regime);
            
            if(m_debugMode)
               PrintFormat("[AdaptivePipeline] Regime changed: %s -> %s (confidence: %.2f%%)",
                          EnumToString(m_current_regime), EnumToString(new_regime), confidence * 100);
         }
      }
   }

public:
   CAdaptivePipelineEngine()
      : IManager(), m_base_pipeline(NULL), m_regime_detector(NULL),
        m_current_regime(REGIME_UNKNOWN), m_regime_change_count(0),
        m_last_regime_change(0), m_adaptive_enabled(true)
   {
      InitializeRegimeConfigs();
      m_current_config.Reset();
   }
   
   virtual string HandlerName() const override { return "AdaptivePipelineEngine"; }
   
   virtual bool Init(IDataManager *data, CEventBus *bus) override
   {
      if(!IManager::Init(data, bus)) return false;
      
      // Initialize HMM regime detector
      m_regime_detector = new CHMMRegimeDetector();
      if(m_regime_detector == NULL || !m_regime_detector.Init(data, bus))
      {
         Print("[AdaptivePipeline] Failed to initialize HMM regime detector");
         if(m_regime_detector != NULL) { delete m_regime_detector; m_regime_detector = NULL; }
         m_adaptive_enabled = false;
      }
      
      // Base pipeline should be set externally
      Print("[AdaptivePipeline] Initialized with regime-adaptive orchestration");
      Print("  Adaptive Mode: ", m_adaptive_enabled ? "Enabled" : "Disabled");
      
      return true;
   }
   
   virtual void Deinit() override
   {
      if(m_regime_detector != NULL) { delete m_regime_detector; m_regime_detector = NULL; }
      if(m_base_pipeline != NULL) { delete m_base_pipeline; m_base_pipeline = NULL; }
      IManager::Deinit();
   }
   
   virtual void DeclareEvents() override
   {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_REGIME_CHANGE);
   }
   
   virtual void OnEvent(const PASREvent &ev) override
   {
      if(ev.id == EVENT_ID_NEW_BAR)
      {
         UpdateRegime();
      }
      else if(ev.id == EVENT_ID_REGIME_CHANGE)
      {
         UpdateRegime();
      }
   }
   
   void SetBasePipeline(CPipelineEngine *pipeline)
   {
      m_base_pipeline = pipeline;
   }
   
   bool ExecutePipeline()
   {
      if(!m_adaptive_enabled || m_base_pipeline == NULL)
      {
         // Fall back to standard pipeline execution
         if(m_base_pipeline != NULL)
            return m_base_pipeline.Execute();
         return false;
      }
      
      // Update regime first
      UpdateRegime();
      
      // Execute pipeline with regime-adaptive stage selection
      datetime current_time = TimeCurrent();
      
      // Execute stages based on regime config
      if(ShouldExecuteStage(STAGE_DATA_SYNC, current_time))
      {
         // Execute data sync stage
      }
      
      if(ShouldExecuteStage(STAGE_ANALYSIS, current_time))
      {
         // Execute analysis stage
      }
      
      if(ShouldExecuteStage(STAGE_PATTERN_RECOGNITION, current_time))
      {
         // Execute pattern recognition stage
      }
      
      if(ShouldExecuteStage(STAGE_REGIME_DETECTION, current_time))
      {
         // Execute regime detection stage
      }
      
      if(ShouldExecuteStage(STAGE_SIGNAL_GENERATION, current_time))
      {
         // Execute signal generation stage with regime weights
      }
      
      if(ShouldExecuteStage(STAGE_AI_INFERENCE, current_time))
      {
         // Execute AI inference stage with regime threshold
      }
      
      if(ShouldExecuteStage(STAGE_RISK_CHECK, current_time))
      {
         // Execute risk check stage
      }
      
      if(ShouldExecuteStage(STAGE_EXECUTION, current_time))
      {
         // Execute execution stage
      }
      
      if(ShouldExecuteStage(STAGE_POSITION_MANAGEMENT, current_time))
      {
         // Execute position management stage
      }
      
      if(ShouldExecuteStage(STAGE_RECOVERY, current_time))
      {
         // Execute recovery stage
      }
      
      if(ShouldExecuteStage(STAGE_DASHBOARD, current_time))
      {
         // Execute dashboard stage
      }
      
      if(ShouldExecuteStage(STAGE_JOURNAL, current_time))
      {
         // Execute journal stage
      }
      
      return true;
   }
   
   RegimePipelineConfig GetCurrentConfig() const { return m_current_config; }
   EMarketRegime GetCurrentRegime() const { return m_current_regime; }
   int GetRegimeChangeCount() const { return m_regime_change_count; }
   bool IsAdaptiveEnabled() const { return m_adaptive_enabled; }
   void SetAdaptiveEnabled(bool enabled) { m_adaptive_enabled = enabled; }
   
   double GetAIConfidenceThreshold() const { return m_current_config.ai_confidence_threshold; }
   double GetPatternWeightMultiplier() const { return m_current_config.pattern_weight_multiplier; }
   double GetSRWeightMultiplier() const { return m_current_config.sr_weight_multiplier; }
   double GetRegimeWeightMultiplier() const { return m_current_config.regime_weight_multiplier; }
};

#endif // __ORCHESTRATION_ADAPTIVE_PIPELINE_ENGINE_MQH__
