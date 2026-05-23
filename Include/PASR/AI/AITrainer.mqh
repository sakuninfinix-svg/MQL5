//+------------------------------------------------------------------+
//| AI/AITrainer.mqh                                                 |
//| Online / offline trainer for PASR AI models                     |
//| Sprint 10: Path fix ../Core/ -> ../../Core/                      |
//| FIX AI-003: MaybeRetrain() now performs real SGD weight updates  |
//|             on ensemble models via CAIEnsemble pointer injection  |
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

//+------------------------------------------------------------------+
//| CAITrainer                                                       |
//| Collects trade samples + triggers periodic SGD retraining        |
//| FIX AI-003: Actual SGD update performed via CAIEnsemble::GetModel|
//+------------------------------------------------------------------+
class CAITrainer : public IManager
{
private:
   SAITrainSample  m_buffer[AI_TRAINER_BUFFER_SIZE];
   int             m_head;
   int             m_count;
   int             m_since_retrain;
   bool            m_retrain_pending;

   int    m_retrain_freq;
   int    m_min_samples;
   double m_lr;

   // FIX AI-003: pointer to ensemble so trainer can call SGDUpdate
   CAIEnsemble    *m_ensemble;   // non-owning, injected via SetEnsemble()

   double ComputeLoss()
   {
      if(m_count == 0) return 0.0;
      double loss = 0.0, total_w = 0.0;
      int n = MathMin(m_count, AI_TRAINER_BUFFER_SIZE);
      for(int i=0; i<n; i++) { loss += m_buffer[i].weight * MathAbs(m_buffer[i].label); total_w += m_buffer[i].weight; }
      return (total_w > 0.0) ? loss / total_w : 0.0;
   }

   // FIX AI-003: Run one mini-batch SGD pass over the last N samples
   void RunSGD(int mini_batch)
   {
      if(m_ensemble == NULL) return;
      int n_models = m_ensemble->GetModelCount();
      if(n_models == 0) return;

      int n = MathMin(m_count, AI_TRAINER_BUFFER_SIZE);
      int start = MathMax(0, n - mini_batch);
      for(int s=start; s<n; s++)
      {
         const SAITrainSample &samp = m_buffer[s];
         // Update every model in ensemble with this sample
         for(int m=0; m<n_models; m++)
         {
            CAIInference *model = m_ensemble->GetModel(m);
            if(model != NULL)
               model->SGDUpdate(samp.features, samp.label, m_lr * samp.weight);
         }
      }
   }

public:
   CAITrainer()
      : m_head(0), m_count(0), m_since_retrain(0),
        m_retrain_pending(false), m_retrain_freq(AI_TRAINER_RETRAIN_FREQ),
        m_min_samples(AI_TRAINER_MIN_RETRAIN), m_lr(0.001),
        m_ensemble(NULL)  // FIX AI-003
   {}

   virtual bool Initialize(CEventBus *bus) override { return IManager::Initialize(bus); }
   virtual void Shutdown() override { m_ensemble = NULL; IManager::Shutdown(); }
   virtual void DeclareEvents() override {}
   virtual void OnEvent(const PASREvent &ev) override {}

   // FIX AI-003: inject ensemble pointer so trainer can perform SGD
   void SetEnsemble(CAIEnsemble *ens) { m_ensemble = ens; }

   void AddSample(const SAITrainSample &sample)
   {
      m_buffer[m_head] = sample;
      m_head = (m_head + 1) % AI_TRAINER_BUFFER_SIZE;
      m_count++;
      m_since_retrain++;
   }

   // FIX AI-003: MaybeRetrain now calls RunSGD() — no longer a no-op
   bool MaybeRetrain()
   {
      if(m_count < m_min_samples)   return false;
      if(m_since_retrain < m_retrain_freq) return false;

      double loss_before = ComputeLoss();
      int mini_batch = MathMin(m_since_retrain, 32); // max 32 samples per retrain step
      RunSGD(mini_batch);  // FIX AI-003: actual weight update
      double loss_after = ComputeLoss();

      PrintFormat("CAITrainer: Retrain (samples=%d, mini_batch=%d, loss %.4f->%.4f, lr=%.5f)",
                  m_count, mini_batch, loss_before, loss_after, m_lr);

      // Dispatch update event if bus available
      if(m_bus != NULL)
      {
         PASREvent ev;
         ev.id       = EVENT_ID_AI_MODEL_UPDATED;
         ev.priority = 5;
         m_bus->Push(ev);
      }

      m_since_retrain   = 0;
      m_retrain_pending = false;
      return true;
   }

   bool ForceRetrain()  { m_since_retrain = m_retrain_freq; return MaybeRetrain(); }

   int  GetSampleCount()   const { return m_count;           }
   bool IsRetrainPending() const { return m_retrain_pending; }
   void SetRetrainFreq(int freq)  { m_retrain_freq = MathMax(10, freq); }
   void SetMinSamples(int n)      { m_min_samples  = MathMax(10, n);   }
   void SetLearningRate(double lr){ m_lr = MathMax(1e-6, lr);          }
};

#endif // __AI_TRAINER_MQH__
