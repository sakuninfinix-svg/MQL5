//+------------------------------------------------------------------+
//| Orchestration/AdaptivePipelineEngine.mqh — v1.1                     |
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
   bool   stages_enabled[STAGE_COUNT];
   double stage_weights[STAGE_COUNT];
   int    execution_frequency;
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
   CPipelineEngine      *m_base_pipeline;
   CHMMRegimeDetector   *m_regime_detector;
   RegimePipelineConfig  m_regime_configs[REGIME_COUNT];
   RegimePipelineConfig  m_current_config;
   EMarketRegime         m_current_regime;
   int                   m_regime_change_count;
   datetime              m_last_regime_change;
   bool                  m_adaptive_enabled;
   // FIX: Move bar tracking from static locals to instance members
   datetime              m_last_bar_time;
   int                   m_bar_counter;

   void InitializeRegimeConfigs()
     {
      for(int i = 0; i < REGIME_COUNT; i++)
         m_regime_configs[i].Reset();

      m_regime_configs[REGIME_TREND_UP].ai_confidence_threshold = 0.65;
      m_regime_configs[REGIME_TREND_UP].pattern_weight_multiplier = 0.8;
      m_regime_configs[REGIME_TREND_UP].sr_weight_multiplier = 1.2;
      m_regime_configs[REGIME_TREND_UP].regime_weight_multiplier = 1.5;
      m_regime_configs[REGIME_TREND_UP].execution_frequency = 0;

      m_regime_configs[REGIME_TREND_DOWN].ai_confidence_threshold = 0.65;
      m_regime_configs[REGIME_TREND_DOWN].pattern_weight_multiplier = 0.8;
      m_regime_configs[REGIME_TREND_DOWN].sr_weight_multiplier = 1.2;
      m_regime_configs[REGIME_TREND_DOWN].regime_weight_multiplier = 1.5;
      m_regime_configs[REGIME_TREND_DOWN].execution_frequency = 0;

      m_regime_configs[REGIME_RANGE].ai_confidence_threshold = 0.75;
      m_regime_configs[REGIME_RANGE].pattern_weight_multiplier = 1.5;
      m_regime_configs[REGIME_RANGE].sr_weight_multiplier = 1.5;
      m_regime_configs[REGIME_RANGE].regime_weight_multiplier = 1.0;
      m_regime_configs[REGIME_RANGE].execution_frequency = 1;

      m_regime_configs[REGIME_VOLATILE].ai_confidence_threshold = 0.85;
      m_regime_configs[REGIME_VOLATILE].pattern_weight_multiplier = 0.5;
      m_regime_configs[REGIME_VOLATILE].sr_weight_multiplier = 0.8;
      m_regime_configs[REGIME_VOLATILE].regime_weight_multiplier = 1.2;
      m_regime_configs[REGIME_VOLATILE].execution_frequency = 0;
      m_regime_configs[REGIME_VOLATILE].stages_enabled[STAGE_PATTERN_RECOGNITION] = false;

      m_regime_configs[REGIME_SQUEEZE].ai_confidence_threshold = 0.80;
      m_regime_configs[REGIME_SQUEEZE].pattern_weight_multiplier = 1.0;
      m_regime_configs[REGIME_SQUEEZE].sr_weight_multiplier = 1.0;
      m_regime_configs[REGIME_SQUEEZE].regime_weight_multiplier = 1.0;
      m_regime_configs[REGIME_SQUEEZE].execution_frequency = 2;

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
      if(m_current_config.execution_frequency == 0) return true;

      if(m_current_config.execution_frequency == 1)
        {
         datetime bar_time = iTime(_Symbol, _Period, 0);
         if(bar_time != m_last_bar_time)
           {
            m_last_bar_time = bar_time;
            return true;
           }
         return false;
        }

      if(m_current_config.execution_frequency >= 2)
        {
         datetime bar_time = iTime(_Symbol, _Period, 0);
         if(bar_time != m_last_bar_time)
           {
            m_last_bar_time = bar_time;
            m_bar_counter++;
            if(m_bar_counter % m_current_config.execution_frequency == 0)
               return true;
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

      if(confidence > 0.6 && new_regime != m_current_regime)
        {
         if(m_regime_detector.IsRegimeStable(3))
           {
            m_regime_change_count++;
            m_last_regime_change = TimeCurrent();
            // FIX: Save old regime before assignment for correct debug print
            EMarketRegime old_regime = m_current_regime;
            ApplyRegimeConfig(new_regime);

            if(m_debugMode)
               PrintFormat("[AdaptivePipeline] Regime changed: %s -> %s (confidence: %.2f%%)",
                          EnumToString(old_regime), EnumToString(new_regime), confidence * 100);
           }
        }
     }

public:
   CAdaptivePipelineEngine()
      : IManager(), m_base_pipeline(NULL), m_regime_detector(NULL),
        m_current_regime(REGIME_UNKNOWN), m_regime_change_count(0),
        m_last_regime_change(0), m_adaptive_enabled(true),
        m_last_bar_time(0), m_bar_counter(0)
     {
      InitializeRegimeConfigs();
      m_current_config.Reset();
     }

   virtual string HandlerName() const override { return "AdaptivePipelineEngine"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;

      m_regime_detector = new CHMMRegimeDetector();
      if(m_regime_detector == NULL || !m_regime_detector.Init(data, bus))
        {
         Print("[AdaptivePipeline] Failed to initialize HMM regime detector");
         if(m_regime_detector != NULL) { delete m_regime_detector; m_regime_detector = NULL; }
         m_adaptive_enabled = false;
        }

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
      if(ev.id == EVENT_ID_NEW_BAR || ev.id == EVENT_ID_REGIME_CHANGE)
         UpdateRegime();
     }

   void SetBasePipeline(CPipelineEngine *pipeline) { m_base_pipeline = pipeline; }

   bool ExecutePipeline()
     {
      if(!m_adaptive_enabled || m_base_pipeline == NULL)
        {
         if(m_base_pipeline != NULL)
            return m_base_pipeline.Execute();
         return false;
        }

      UpdateRegime();
      // FIX: Delegate to base pipeline instead of empty stage bodies
      return m_base_pipeline.Execute();
     }

   // FIX: Add ExecutePipeline(PipelineContext&) with drawdown guard
   ENUM_STAGE_RESULT ExecutePipeline(PipelineContext &ctx)
     {
      if(!m_adaptive_enabled || m_base_pipeline == NULL)
        {
         if(m_base_pipeline != NULL)
            return m_base_pipeline.ExecutePipeline(ctx);
         return STAGE_ABORT;
        }

      // FIX: Drawdown check (mirrors CPipelineEngine)
      if(ctx.session_dd > ctx.max_session_dd)
        {
         ctx.exit_message = "Adaptive pipeline halted: session drawdown exceeded";
         return STAGE_ABORT;
        }

      UpdateRegime();
      return m_base_pipeline.ExecutePipeline(ctx);
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
