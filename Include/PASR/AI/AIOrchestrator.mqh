//+------------------------------------------------------------------+
//|                                          AI/AIOrchestrator.mqh   |
//|                                       Copyright 2026, Agsicentre|
//| Changelog:                                                       |
//|   v2.02 (2026-05-24) Sprint 15: Fix AI-001..AI-007               |
//|     AI-001: InjectStructure/InjectRegime called BEFORE Build()   |
//|     AI-003: Trainer injected with ensemble pointer (real SGD)    |
//|     AI-005: Cache SAIFeatureVector at trade-open time for         |
//|             accurate training samples at close                    |
//|   v2.01 (2026-05-23) Sprint 10: Moved to Include/PASR/AI/       |
//|            Path fix: ../Core/ -> ../../Core/                     |
//|   v2.00 (2026-05-22) Replaced deprecated AIManager              |
//|       Uses 26-dim feature vector (AI_FEATURE_DIM=26)             |
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

//+------------------------------------------------------------------+
//| CAIOrchestrator v2.02 — top-level AI subsystem manager           |
//| Coordinates: feature building -> inference -> ensemble -> calib  |
//+------------------------------------------------------------------+
class CAIOrchestrator : public IManager
{
private:
   CAIFeatureBuilder    *m_feat;
   CAIInference         *m_infer;
   CAIEnsemble          *m_ensemble;
   CAITrainer           *m_trainer;
   CConfidenceCalibrator*m_calib;
   COnlineLearningGuard *m_guard;

   SAIInferenceResult    m_last_result;
   SAIModelPerf          m_perf;
   bool                  m_ready;
   string                m_model_path;
   int                   m_min_bars_required;

   // FIX AI-005: Cache feature vector at trade-open time
   //             so training sample at close reflects entry-bar features
   SAIFeatureVector      m_open_features;        // features when trade was opened
   bool                  m_open_features_valid;  // true between open and close

public:
   CAIOrchestrator()
      : m_feat(NULL), m_infer(NULL), m_ensemble(NULL),
        m_trainer(NULL), m_calib(NULL), m_guard(NULL),
        m_ready(false), m_model_path(""), m_min_bars_required(50),
        m_open_features_valid(false)  // FIX AI-005
   {
      m_last_result.Reset();
      m_perf.Reset();
      m_open_features.Reset();  // FIX AI-005
   }

   ~CAIOrchestrator() { Shutdown(); }

   virtual bool Initialize(CEventBus *bus) override
   {
      if(!IManager::Initialize(bus)) return false;

      m_feat     = new CAIFeatureBuilder();
      m_infer    = new CAIInference();
      m_ensemble = new CAIEnsemble();
      m_trainer  = new CAITrainer();
      m_calib    = new CConfidenceCalibrator();
      m_guard    = new COnlineLearningGuard();

      if(!m_feat->Initialize(bus))     { Print("AI: FeatureBuilder init failed"); return false; }
      if(!m_infer->Initialize(bus))    { Print("AI: Inference init failed");      return false; }
      if(!m_ensemble->Initialize(bus)) { Print("AI: Ensemble init failed");       return false; }
      if(!m_trainer->Initialize(bus))  { Print("AI: Trainer init failed");        return false; }
      if(!m_calib->Initialize(bus))    { Print("AI: Calibrator init failed");     return false; }
      if(!m_guard->Initialize(bus))    { Print("AI: Guard init failed");          return false; }

      // FIX AI-003: Wire trainer to ensemble so SGD can update weights
      m_trainer->SetEnsemble(m_ensemble);

      m_ready = true;
      Print("CAIOrchestrator v2.02: Initialized (26-dim pipeline, real SGD trainer)");
      return true;
   }

   virtual void Shutdown() override
   {
      m_ready = false;
      if(m_guard)    { m_guard->Shutdown();    delete m_guard;    m_guard    = NULL; }
      if(m_calib)    { m_calib->Shutdown();    delete m_calib;    m_calib    = NULL; }
      if(m_trainer)  { m_trainer->Shutdown();  delete m_trainer;  m_trainer  = NULL; }
      if(m_ensemble) { m_ensemble->Shutdown(); delete m_ensemble; m_ensemble = NULL; }
      if(m_infer)    { m_infer->Shutdown();    delete m_infer;    m_infer    = NULL; }
      if(m_feat)     { m_feat->Shutdown();     delete m_feat;     m_feat     = NULL; }
      IManager::Shutdown();
   }

   virtual void DeclareEvents() override {}

   virtual void OnEvent(const PASREvent &ev) override
   {
      if(!m_ready) return;
      if(ev.id == EVENT_ID_TRADE_CLOSED)
         OnTradeResult(ev.trade_closed.profit > 0);
      // FIX AI-005: Cache features when a trade is opened
      if(ev.id == EVENT_ID_TRADE_OPEN)
      {
         if(m_last_result.valid)
         {
            // Copy the feature vector that produced the last valid signal
            ArrayCopy(m_open_features.features, m_feat->GetLastFeatures());
            m_open_features.valid      = true;
            m_open_features.bar_time   = iTime(_Symbol, PERIOD_CURRENT, 0);
            m_open_features_valid      = true;
         }
      }
   }

   //--- Core inference call (called by Stage_AIInfer in PipelineEngine)
   //    FIX AI-001: InjectStructure/InjectRegime must be called BEFORE Predict()
   //    They write to the pending buffer inside CAIFeatureBuilder which is
   //    consumed by Build() in this function.
   bool Predict(SAIInferenceResult &out_result)
   {
      out_result.Reset();
      if(!m_ready) return false;

      SAIFeatureVector fv;
      fv.Reset();
      if(!m_feat->Build(fv))  // Build() applies any pending injections
      {
         out_result.valid       = false;
         out_result.vetoed      = true;
         out_result.veto_reason = "Feature build failed";
         return false;
      }

      double drift = m_guard->ComputeDrift(fv);
      if(m_guard->ShouldVeto(drift))
      {
         out_result.drift_score = drift;
         out_result.vetoed      = true;
         out_result.veto_reason = StringFormat("Drift veto: %.3f", drift);
         out_result.valid       = false;
         return false;
      }

      SAIEnsembleVote vote;
      vote.Reset();
      m_ensemble->Vote(fv, vote);

      double raw_conf = MathAbs(vote.final_score);
      double cal_conf = m_calib->Calibrate(raw_conf, vote.agreement);

      out_result.score       = vote.final_score;
      out_result.confidence  = cal_conf;
      out_result.direction   = (vote.final_score > 0.0) ? 1 : ((vote.final_score < 0.0) ? -1 : 0);
      out_result.valid       = (cal_conf >= AI_DEFAULT_CONF_THRESHOLD);
      out_result.model_id    = "ensemble_v2.02";
      out_result.timestamp   = TimeCurrent();
      out_result.drift_score = drift;
      out_result.vetoed      = false;

      m_last_result = out_result;
      return out_result.valid;
   }

   //--- Called by Orchestrator.OnTradeTransaction after trade close
   //    FIX AI-005: Use cached open-bar features if available
   void OnTradeResult(bool was_profitable)
   {
      if(!m_ready) return;

      // FIX AI-005: prefer entry-bar features (valid only if cached at open)
      SAITrainSample s;
      if(m_open_features_valid)
      {
         ArrayCopy(s.features, m_open_features.features);
         m_open_features_valid = false;  // consumed
         m_open_features.Reset();
      }
      else
      {
         // Fallback: use latest features if no cached open available
         ArrayCopy(s.features, m_feat->GetLastFeatures());
      }

      s.label     = was_profitable ? 1.0 : -1.0;
      s.weight    = m_last_result.confidence;
      s.timestamp = TimeCurrent();
      m_trainer->AddSample(s);
      m_trainer->MaybeRetrain();

      m_perf.Update(was_profitable, m_last_result.confidence, m_last_result.drift_score);
   }

   // Called by PipelineEngine Stage_AIInfer before Predict()
   // to wire structure context from SR/Zone/Pattern managers
   void InjectContext(double sr_dist, double zone_str, double pattern_score, EMarketRegime regime)
   {
      if(m_feat == NULL) return;
      m_feat->InjectStructure(sr_dist, zone_str, pattern_score);  // FIX AI-001
      m_feat->InjectRegime(regime);                               // FIX AI-001
   }

   bool                     IsReady()            const { return m_ready;       }
   const SAIInferenceResult &GetLastResult()     const { return m_last_result; }
   const SAIModelPerf       &GetPerf()           const { return m_perf;        }
   CAIFeatureBuilder        *GetFeatureBuilder()       { return m_feat;        }
   CAIEnsemble              *GetEnsemble()             { return m_ensemble;    }
};

#endif // __AI_ORCHESTRATOR_MQH__
