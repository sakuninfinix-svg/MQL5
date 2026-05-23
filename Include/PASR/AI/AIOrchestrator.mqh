//+------------------------------------------------------------------+
//|                                          AI/AIOrchestrator.mqh   |
//|                                       Copyright 2026, Agsicentre|
//| Changelog:                                                       |
//|   v2.01 (2026-05-23) Sprint 10: Moved to Include/PASR/AI/       |
//|            Path fix: ../Core/ -> ../../Core/                     |
//|       Now: #include "../../Core/IManager.mqh"                       |
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
//| CAIOrchestrator — top-level AI subsystem manager                 |
//| Coordinates: feature building → inference → ensemble → calibration|
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
   
public:
   CAIOrchestrator()
      : m_feat(NULL), m_infer(NULL), m_ensemble(NULL),
        m_trainer(NULL), m_calib(NULL), m_guard(NULL),
        m_ready(false), m_model_path(""), m_min_bars_required(50)
   {
      m_last_result.Reset();
      m_perf.Reset();
   }
   
   ~CAIOrchestrator()
   {
      Shutdown();
   }
   
   //--- IManager interface
   virtual bool Initialize(CEventBus *bus) override
   {
      if(!IManager::Initialize(bus)) return false;
      
      m_feat     = new CAIFeatureBuilder();
      m_infer    = new CAIInference();
      m_ensemble = new CAIEnsemble();
      m_trainer  = new CAITrainer();
      m_calib    = new CConfidenceCalibrator();
      m_guard    = new COnlineLearningGuard();
      
      if(!m_feat->Initialize(bus))     { PrintFormat("AI: FeatureBuilder init failed"); return false; }
      if(!m_infer->Initialize(bus))    { PrintFormat("AI: Inference init failed");      return false; }
      if(!m_ensemble->Initialize(bus)) { PrintFormat("AI: Ensemble init failed");       return false; }
      if(!m_trainer->Initialize(bus))  { PrintFormat("AI: Trainer init failed");        return false; }
      if(!m_calib->Initialize(bus))    { PrintFormat("AI: Calibrator init failed");     return false; }
      if(!m_guard->Initialize(bus))    { PrintFormat("AI: Guard init failed");          return false; }
      
      m_ready = true;
      Print("CAIOrchestrator: Initialized (26-dim pipeline)");
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
      // Handle trade result for online learning
      if(ev.id == EVENT_ID_TRADE_CLOSED)
         OnTradeResult(ev.trade_closed.profit > 0);
   }
   
   //--- Core inference call (called by Stage_AIInfer in PipelineEngine)
   bool Predict(SAIInferenceResult &out_result)
   {
      out_result.Reset();
      if(!m_ready) return false;
      
      // 1. Build 26-dim feature vector
      SAIFeatureVector fv;
      fv.Reset();
      if(!m_feat->Build(fv))
      {
         out_result.valid  = false;
         out_result.vetoed = true;
         out_result.veto_reason = "Feature build failed";
         return false;
      }
      
      // 2. Guard check — detect concept drift
      double drift = m_guard->ComputeDrift(fv);
      if(m_guard->ShouldVeto(drift))
      {
         out_result.drift_score = drift;
         out_result.vetoed      = true;
         out_result.veto_reason = StringFormat("Drift veto: %.3f", drift);
         out_result.valid       = false;
         return false;
      }
      
      // 3. Ensemble inference
      SAIEnsembleVote vote;
      vote.Reset();
      m_ensemble->Vote(fv, vote);
      
      // 4. Calibrate confidence
      double raw_conf = MathAbs(vote.final_score);
      double cal_conf = m_calib->Calibrate(raw_conf, vote.agreement);
      
      // 5. Populate result
      out_result.score       = vote.final_score;
      out_result.confidence  = cal_conf;
      out_result.direction   = (vote.final_score > 0.0) ? 1 : ((vote.final_score < 0.0) ? -1 : 0);
      out_result.valid       = (cal_conf >= AI_DEFAULT_CONF_THRESHOLD);
      out_result.model_id    = "ensemble_v2";
      out_result.timestamp   = TimeCurrent();
      out_result.drift_score = drift;
      out_result.vetoed      = false;
      
      m_last_result = out_result;
      return out_result.valid;
   }
   
   //--- Called by Orchestrator.OnTradeTransaction after trade close
   void OnTradeResult(bool was_profitable)
   {
      if(!m_ready || !m_last_result.valid) return;
      m_perf.Update(was_profitable, m_last_result.confidence, m_last_result.drift_score);
      
      // Feed trainer for online learning
      SAITrainSample s;
      ArrayCopy(s.features, m_feat->GetLastFeatures());
      s.label     = was_profitable ? 1.0 : -1.0;
      s.weight    = m_last_result.confidence;
      s.timestamp = TimeCurrent();
      m_trainer->AddSample(s);
      m_trainer->MaybeRetrain();
   }
   
   //--- Accessors
   bool                     IsReady()         const { return m_ready; }
   const SAIInferenceResult &GetLastResult()  const { return m_last_result; }
   const SAIModelPerf       &GetPerf()        const { return m_perf; }
   CAIFeatureBuilder        *GetFeatureBuilder()    { return m_feat; }
};

#endif // __AI_ORCHESTRATOR_MQH__
