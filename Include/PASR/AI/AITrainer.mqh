//+------------------------------------------------------------------+
//| AI/AITrainer.mqh — v1.01                                         |
//| Online / offline trainer for PASR AI models                      |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_TRAINER_MQH__
#define __AI_TRAINER_MQH__

#include "AITypes.mqh"
#include "AIEnsemble.mqh"
#include "../../Core/IManager.mqh"

#define AI_TRAINER_BUFFER_SIZE  500
#define AI_TRAINER_MIN_RETRAIN   50
#define AI_TRAINER_RETRAIN_FREQ 100

class CAITrainer : public IManager
  {
private:
   SAITrainSample  m_buffer[AI_TRAINER_BUFFER_SIZE];
   int             m_head;
   int             m_count;
   int             m_since_retrain;
   bool            m_retrain_pending;
   int             m_retrain_freq;
   int             m_min_samples;
   double          m_lr;
   CAIEnsemble    *m_ensemble;

   double ComputeLoss()
     {
      if(m_count == 0) return 0.0;
      double loss = 0.0, total_w = 0.0;
      int n = MathMin(m_count, AI_TRAINER_BUFFER_SIZE);
      for(int i = 0; i < n; i++)
        {
         loss += m_buffer[i].weight * MathAbs(m_buffer[i].label);
         total_w += m_buffer[i].weight;
        }
      return (total_w > 0.0) ? loss / total_w : 0.0;
     }

   void RunSGD(int mini_batch)
     {
      if(m_ensemble == NULL) return;
      int n_models = m_ensemble.GetModelCount();
      if(n_models == 0) return;

      int n = MathMin(m_count, AI_TRAINER_BUFFER_SIZE);
      int start = MathMax(0, n - mini_batch);
      for(int s = start; s < n; s++)
        {
         const SAITrainSample &samp = m_buffer[s];
         for(int m = 0; m < n_models; m++)
           {
            CAIInference *model = m_ensemble.GetModel(m);
            if(model != NULL) model.SGDUpdate(samp.features, samp.label, m_lr * samp.weight);
           }
        }
     }

public:
   CAITrainer()
      : IManager(), m_head(0), m_count(0), m_since_retrain(0),
        m_retrain_pending(false), m_retrain_freq(AI_TRAINER_RETRAIN_FREQ),
        m_min_samples(AI_TRAINER_MIN_RETRAIN), m_lr(0.001), m_ensemble(NULL)
     {}

   virtual string HandlerName() const override { return "AITrainer"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      return IManager::Init(data, bus);
     }

   virtual void Deinit() override
     {
      m_ensemble = NULL;
      IManager::Deinit();
     }

   virtual void DeclareEvents() override {}
   virtual void OnEvent(const PASREvent &ev) override {}

   void SetEnsemble(CAIEnsemble *ens) { m_ensemble = ens; }

   void AddSample(const SAITrainSample &sample)
     {
      m_buffer[m_head] = sample;
      m_head = (m_head + 1) % AI_TRAINER_BUFFER_SIZE;
      m_count++;
      m_since_retrain++;
     }

   bool MaybeRetrain()
     {
      if(m_count < m_min_samples) return false;
      if(m_since_retrain < m_retrain_freq) return false;

      double loss_before = ComputeLoss();
      int mini_batch = MathMin(m_since_retrain, 32);
      RunSGD(mini_batch);
      double loss_after = ComputeLoss();

      PrintFormat("CAITrainer: Retrain (samples=%d, mini_batch=%d, loss %.4f->%.4f, lr=%.5f)",
                  m_count, mini_batch, loss_before, loss_after, m_lr);

      PASREvent ev;
      ev.id = EVENT_ID_AI_MODEL_UPDATED;
      ev.priority = 5;
      QueueEvent(ev);

      m_since_retrain = 0;
      m_retrain_pending = false;
      return true;
     }

   bool ForceRetrain() { m_since_retrain = m_retrain_freq; return MaybeRetrain(); }
   int  GetSampleCount() const { return m_count; }
   bool IsRetrainPending() const { return m_retrain_pending; }
   void SetRetrainFreq(int freq) { m_retrain_freq = MathMax(10, freq); }
   void SetMinSamples(int n) { m_min_samples = MathMax(10, n); }
   void SetLearningRate(double lr) { m_lr = MathMax(1e-6, lr); }
  };

#endif // __AI_TRAINER_MQH__
