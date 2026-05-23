//+------------------------------------------------------------------+
//| AI/AITrainer.mqh                                                 |
//| Online / offline trainer for PASR AI models                     |
//| Sprint 10: Path fix ../Core/ -> ../../Core/                      |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_TRAINER_MQH__
#define __AI_TRAINER_MQH__

#include "AITypes.mqh"
#include "../../Core/IManager.mqh"

#define AI_TRAINER_BUFFER_SIZE  500
#define AI_TRAINER_MIN_RETRAIN   50
#define AI_TRAINER_RETRAIN_FREQ 100

//+------------------------------------------------------------------+
//| CAITrainer                                                       |
//| Collects trade samples + triggers periodic retraining            |
//+------------------------------------------------------------------+
class CAITrainer : public IManager
{
private:
   SAITrainSample  m_buffer[AI_TRAINER_BUFFER_SIZE];
   int             m_head;          // circular buffer write head
   int             m_count;         // total samples stored
   int             m_since_retrain; // samples since last retrain
   bool            m_retrain_pending;
   
   int    m_retrain_freq;
   int    m_min_samples;
   
   // Simple SGD state for online update (lightweight)
   double m_lr;  // learning rate
   
   //--- Compute weighted loss for logging
   double ComputeLoss()
   {
      if(m_count == 0) return 0.0;
      double loss = 0.0, total_w = 0.0;
      int n = MathMin(m_count, AI_TRAINER_BUFFER_SIZE);
      for(int i=0; i<n; i++)
      {
         loss    += m_buffer[i].weight * MathAbs(m_buffer[i].label);  // simplified
         total_w += m_buffer[i].weight;
      }
      return (total_w > 0.0) ? loss / total_w : 0.0;
   }
   
public:
   CAITrainer()
      : m_head(0), m_count(0), m_since_retrain(0),
        m_retrain_pending(false), m_retrain_freq(AI_TRAINER_RETRAIN_FREQ),
        m_min_samples(AI_TRAINER_MIN_RETRAIN), m_lr(0.001)
   {}
   
   virtual bool Initialize(CEventBus *bus) override
   {
      return IManager::Initialize(bus);
   }
   
   virtual void Shutdown() override { IManager::Shutdown(); }
   virtual void DeclareEvents() override {}
   virtual void OnEvent(const PASREvent &ev) override {}
   
   //--- Add sample to circular buffer
   void AddSample(const SAITrainSample &sample)
   {
      m_buffer[m_head] = sample;
      m_head = (m_head + 1) % AI_TRAINER_BUFFER_SIZE;
      m_count++;
      m_since_retrain++;
   }
   
   //--- Check if retraining is due and execute if so
   bool MaybeRetrain()
   {
      if(m_count < m_min_samples) return false;
      if(m_since_retrain < m_retrain_freq) return false;
      
      // Retrain
      double loss = ComputeLoss();
      PrintFormat("CAITrainer: Retrain triggered (samples=%d, loss=%.4f)", m_count, loss);
      m_since_retrain    = 0;
      m_retrain_pending  = false;
      
      // TODO: dispatch EVENT_AI_MODEL_UPDATED event via bus
      return true;
   }
   
   //--- Force retrain
   bool ForceRetrain()
   {
      m_since_retrain = m_retrain_freq;  // trigger immediately
      return MaybeRetrain();
   }
   
   int  GetSampleCount()  const { return m_count; }
   bool IsRetrainPending() const { return m_retrain_pending; }
   void SetRetrainFreq(int freq)  { m_retrain_freq = MathMax(10, freq); }
   void SetMinSamples(int n)      { m_min_samples  = MathMax(10, n);    }
   void SetLearningRate(double lr){ m_lr = MathMax(1e-6, lr);           }
};

#endif // __AI_TRAINER_MQH__
