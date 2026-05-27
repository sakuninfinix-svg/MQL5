//+------------------------------------------------------------------+
//| AI/AIOrchestrator.mqh — v2.03                                    |
//| Top-level AI subsystem manager                                    |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_ORCHESTRATOR_MQH__
#define __AI_ORCHESTRATOR_MQH__

#include "AITypes.mqh"
#include "AIFeatureBuilder.mqh"
#include "AIInference.mqh"
#include "AIEnsemble.mqh"
#include "AITrainer.mqh"
#include "ConfidenceCalibrator.mqh"
#include "OnlineLearningGuard.mqh"
#include "../../Core/IManager.mqh"

class CAIOrchestrator : public IManager
  {
private:
   CAIFeatureBuilder     *m_feat;
   CAIInference          *m_infer;
   CAIEnsemble           *m_ensemble;
   CAITrainer            *m_trainer;
   CConfidenceCalibrator *m_calib;
   COnlineLearningGuard  *m_guard;

   SAIInferenceResult     m_last_result;
   SAIModelPerf           m_perf;
   bool                   m_ready;
   string                 m_model_path;
   int                    m_min_bars_required;
   SAIFeatureVector       m_open_features;
   bool                   m_open_features_valid;

   void ReleaseComponents()
     {
      m_ready = false;
      if(m_guard    != NULL) { m_guard.Deinit();    delete m_guard;    m_guard    = NULL; }
      if(m_calib    != NULL) { m_calib.Deinit();    delete m_calib;    m_calib    = NULL; }
      if(m_trainer  != NULL) { m_trainer.Deinit();  delete m_trainer;  m_trainer  = NULL; }
      if(m_ensemble != NULL) { m_ensemble.Deinit(); delete m_ensemble; m_ensemble = NULL; }
      if(m_infer    != NULL) { m_infer.Deinit();    delete m_infer;    m_infer    = NULL; }
      if(m_feat     != NULL) { m_feat.Deinit();     delete m_feat;     m_feat     = NULL; }
      m_open_features_valid = false;
      m_open_features.Reset();
     }

public:
   CAIOrchestrator()
      : IManager(), m_feat(NULL), m_infer(NULL), m_ensemble(NULL),
        m_trainer(NULL), m_calib(NULL), m_guard(NULL),
        m_ready(false), m_model_path(""), m_min_bars_required(50),
        m_open_features_valid(false)
     {
      m_last_result.Reset();
      m_perf.Reset();
      m_open_features.Reset();
     }

   ~CAIOrchestrator() { ReleaseComponents(); }

   virtual string HandlerName() const override { return "AIOrchestrator"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      ReleaseComponents();

      m_feat     = new CAIFeatureBuilder();
      m_infer    = new CAIInference();
      m_ensemble = new CAIEnsemble();
      m_trainer  = new CAITrainer();
      m_calib    = new CConfidenceCalibrator();
      m_guard    = new COnlineLearningGuard();

      if(m_feat == NULL || m_infer == NULL || m_ensemble == NULL ||
         m_trainer == NULL || m_calib == NULL || m_guard == NULL)
        {
         Print("AI: allocation failed");
         ReleaseComponents();
         return false;
        }

      if(!m_feat.Init(data, bus))     { Print("AI: FeatureBuilder init failed"); ReleaseComponents(); return false; }
      if(!m_infer.Init(data, bus))    { Print("AI: Inference init failed");      ReleaseComponents(); return false; }
      if(!m_ensemble.Init(data, bus)) { Print("AI: Ensemble init failed");       ReleaseComponents(); return false; }
      if(!m_trainer.Init(data, bus))  { Print("AI: Trainer init failed");        ReleaseComponents(); return false; }
      if(!m_calib.Init(data, bus))    { Print("AI: Calibrator init failed");     ReleaseComponents(); return false; }
      if(!m_guard.Init(data, bus))    { Print("AI: Guard init failed");          ReleaseComponents(); return false; }

      m_trainer.SetEnsemble(m_ensemble);
      m_ready = true;
      Print("CAIOrchestrator v2.03: Initialized");
      return true;
     }

   virtual void Deinit() override
     {
      ReleaseComponents();
      IManager::Deinit();
     }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_TRADE_OPEN);
      AddEvent(EVENT_ID_TRADE_CLOSE);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
     }

   virtual void OnEvent(const PASREvent &ev) override
     {
      if(ev.id == EVENT_ID_CONFIG_RELOAD) { OnConfigReload(); return; }
      if(!m_ready) return;

      if(ev.id == EVENT_ID_TRADE_CLOSE)
        {
         OnTradeResult(ev.profit > 0.0);
         return;
        }

      if(ev.id == EVENT_ID_TRADE_OPEN)
        {
         if(m_last_result.valid && m_feat != NULL)
           {
            const double *last = m_feat.GetLastFeatures();
            if(last != NULL) ArrayCopy(m_open_features.features, last);
            m_open_features.valid = true;
            m_open_features.bar_time = iTime(_Symbol, PERIOD_CURRENT, 1);
            m_open_features_valid = true;
           }
        }
     }

   bool Predict(SAIInferenceResult &out_result)
     {
      out_result.Reset();
      if(!m_ready || m_feat == NULL || m_guard == NULL || m_ensemble == NULL || m_calib == NULL)
         return false;

      SAIFeatureVector fv;
      fv.Reset();
      if(!m_feat.Build(fv))
        {
         out_result.valid = false;
         out_result.vetoed = true;
         out_result.veto_reason = "Feature build failed";
         return false;
        }

      double drift = m_guard.ComputeDrift(fv);
      if(m_guard.ShouldVeto(drift))
        {
         out_result.drift_score = drift;
         out_result.vetoed = true;
         out_result.veto_reason = StringFormat("Drift veto: %.3f", drift);
         out_result.valid = false;
         return false;
        }

      SAIEnsembleVote vote;
      vote.Reset();
      m_ensemble.Vote(fv, vote);

      double raw_conf = MathAbs(vote.final_score);
      double cal_conf = m_calib.Calibrate(raw_conf, vote.agreement);

      out_result.score = vote.final_score;
      out_result.confidence = cal_conf;
      out_result.direction = (vote.final_score > 0.0) ? 1 : ((vote.final_score < 0.0) ? -1 : 0);
      out_result.valid = (cal_conf >= AI_DEFAULT_CONF_THRESHOLD);
      out_result.model_id = "ensemble_v2.03";
      out_result.timestamp = TimeCurrent();
      out_result.drift_score = drift;
      out_result.vetoed = false;

      m_last_result = out_result;
      return out_result.valid;
     }

   double Evaluate()
     {
      SAIInferenceResult result;
      Predict(result);
      return result.score;
     }

   bool GetLastVeto() const { return m_last_result.vetoed; }
   double GetLastDriftScore() const { return m_last_result.drift_score; }

   void OnTradeResult(bool was_profitable)
     {
      if(!m_ready || m_trainer == NULL || m_feat == NULL) return;

      SAITrainSample sample;
      sample.Reset();
      if(m_open_features_valid)
        {
         ArrayCopy(sample.features, m_open_features.features);
         m_open_features_valid = false;
         m_open_features.Reset();
        }
      else
        {
         const double *last = m_feat.GetLastFeatures();
         if(last != NULL) ArrayCopy(sample.features, last);
        }

      sample.label = was_profitable ? 1.0 : -1.0;
      sample.weight = m_last_result.confidence;
      sample.timestamp = TimeCurrent();
      m_trainer.AddSample(sample);
      m_trainer.MaybeRetrain();
      m_perf.Update(was_profitable, m_last_result.confidence, m_last_result.drift_score);
     }

   void InjectContext(double sr_dist, double zone_str, double pattern_score, EMarketRegime regime)
     {
      if(m_feat == NULL) return;
      m_feat.InjectStructure(sr_dist, zone_str, pattern_score);
      m_feat.InjectRegime(regime);
     }

   bool IsReady() const { return m_ready; }
   virtual bool IsHealthy() const override { return IsInitialized() && m_ready; }
   const SAIInferenceResult &GetLastResult() const { return m_last_result; }
   const SAIModelPerf &GetPerf() const { return m_perf; }
   CAIFeatureBuilder *GetFeatureBuilder() { return m_feat; }
   CAIEnsemble *GetEnsemble() { return m_ensemble; }
  };

#endif // __AI_ORCHESTRATOR_MQH__
