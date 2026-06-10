//+------------------------------------------------------------------+
//| AI/AITrainer.mqh — v1.03                                        |
//| Online trainer: collects samples and retrains MLP ensemble       |
//| FIX v1.03: use ensemble.GetModelCount()/GetModel() directly;     |
//|            pass ArraySize(features)+AI_FEATURE_DIM to OnlineUpdate|
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_TRAINER_MQH__
#define __AI_TRAINER_MQH__

#include "AITypes.mqh"
#include "AIEnsemble.mqh"
#include "../Core/IManager.mqh"

#define TRAINER_MAX_SAMPLES   500
#define TRAINER_RETRAIN_EVERY  50
#define TRAINER_LEARNING_RATE 0.005

class CAITrainer : public IManager
  {
private:
   SAITrainSample   m_samples[TRAINER_MAX_SAMPLES];
   int              m_sample_count;
   int              m_sample_head;
   int              m_since_retrain;
   CAIEnsemble     *m_ensemble;
   bool             m_auto_retrain;

public:
   CAITrainer()
      : IManager(), m_sample_count(0), m_sample_head(0),
        m_since_retrain(0), m_ensemble(NULL), m_auto_retrain(true)
     {}

   virtual string HandlerName() const override { return "AITrainer"; }
   virtual void DeclareEvents()              override {}
   virtual void OnEvent(const PASREvent &ev) override {}

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      return IManager::Init(data, bus);
     }

   virtual void Deinit() override
     {
      m_ensemble = NULL;
      IManager::Deinit();
     }

   void SetEnsemble(CAIEnsemble *ens) { m_ensemble = ens; }

   void AddSample(const SAITrainSample &s)
     {
      int idx = m_sample_head;
      m_samples[idx] = s;
      m_sample_head = (m_sample_head + 1) % TRAINER_MAX_SAMPLES;
      if(m_sample_count < TRAINER_MAX_SAMPLES) m_sample_count++;
      m_since_retrain++;
     }

   void MaybeRetrain()
     {
      if(!m_auto_retrain) return;
      if(m_since_retrain < TRAINER_RETRAIN_EVERY) return;
      Retrain();
     }

   void Retrain()
     {
      if(m_ensemble == NULL || m_sample_count == 0) return;
      // FIX v1.03: call GetModelCount()/GetModel() directly on ensemble pointer
      int n_models = m_ensemble.GetModelCount();
      int n        = m_sample_count;

      for(int model = 0; model < n_models; model++)
        {
         CMLPModel *m = m_ensemble.GetModel(model);
         if(m == NULL) continue;

         for(int s = 0; s < n; s++)
           {
            int idx = (m_sample_head - n + s + TRAINER_MAX_SAMPLES) % TRAINER_MAX_SAMPLES;
            double features[];
            ArrayCopy(features, m_samples[idx].features);
            double lbl = MathMax(0.0, MathMin(1.0, (m_samples[idx].label + 1.0) / 2.0));
            // FIX v1.03: OnlineUpdate now requires explicit feat_dim parameter
            m.OnlineUpdate(features, AI_FEATURE_DIM, lbl,
                           TRAINER_LEARNING_RATE * m_samples[idx].weight);
           }
        }

      m_since_retrain = 0;
      if(m_debugMode)
         PrintFormat("[AITrainer] Retrained %d models on %d samples", n_models, n);
     }
  };

#endif // __AI_TRAINER_MQH__
