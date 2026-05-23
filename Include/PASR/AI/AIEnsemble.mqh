//+------------------------------------------------------------------+
//| AI/AIEnsemble.mqh                                                |
//| Ensemble voting across multiple CAIInference models              |
//| FIX AI-004: Each model uses a different seed so weights differ   |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_ENSEMBLE_MQH__
#define __AI_ENSEMBLE_MQH__

#include "AITypes.mqh"
#include "AIInference.mqh"

#define AI_ENSEMBLE_MAX_MODELS 4

// FIX AI-004: Distinct seeds produce different Xavier-random weights per model,
//             giving genuine diversity without loading external files.
static const int AI_ENSEMBLE_SEEDS[AI_ENSEMBLE_MAX_MODELS] = {42, 137, 271, 919};

//+------------------------------------------------------------------+
//| CAIEnsemble — weighted ensemble of CAIInference models           |
//+------------------------------------------------------------------+
class CAIEnsemble : public IManager
{
private:
   CAIInference *m_models[AI_ENSEMBLE_MAX_MODELS];
   double        m_weights[AI_ENSEMBLE_MAX_MODELS];
   int           m_n_models;
   bool          m_ready;

   double ComputeAgreement(const double &scores[])
   {
      int n = ArraySize(scores);
      if(n <= 1) return 1.0;
      int pos=0, neg=0;
      for(int i=0; i<n; i++)
      {
         if(scores[i] > 0.0) pos++;
         else if(scores[i] < 0.0) neg++;
      }
      return (double)MathMax(pos, neg) / n;
   }

public:
   CAIEnsemble() : m_n_models(0), m_ready(false)
   {
      ArrayInitialize(m_weights, 1.0);
      for(int i=0; i<AI_ENSEMBLE_MAX_MODELS; i++) m_models[i] = NULL;
   }

   ~CAIEnsemble() { Shutdown(); }

   virtual bool Initialize(CEventBus *bus) override
   {
      if(!IManager::Initialize(bus)) return false;

      // FIX AI-004: Create 2 models with DIFFERENT seeds for genuine diversity
      for(int i=0; i<2; i++)
      {
         // FIX AI-004: Pass distinct seed from table — was always seed=42
         m_models[m_n_models] = new CAIInference(AI_ENSEMBLE_SEEDS[i]);
         m_models[m_n_models]->SetModelId(StringFormat("mlp_v2_m%d_s%d", i, AI_ENSEMBLE_SEEDS[i]));
         if(!m_models[m_n_models]->Initialize(bus)) return false;
         m_weights[m_n_models] = 1.0;
         m_n_models++;
      }

      NormalizeWeights();
      m_ready = true;
      PrintFormat("CAIEnsemble: %d models ready (seeds: %d, %d)",
                  m_n_models, AI_ENSEMBLE_SEEDS[0], AI_ENSEMBLE_SEEDS[1]);
      return true;
   }

   virtual void Shutdown() override
   {
      for(int i=0; i<m_n_models; i++)
         if(m_models[i]) { delete m_models[i]; m_models[i]=NULL; }
      m_n_models = 0;
      m_ready    = false;
      IManager::Shutdown();
   }

   virtual void DeclareEvents() override {}
   virtual void OnEvent(const PASREvent &ev) override {}

   bool Vote(const SAIFeatureVector &fv, SAIEnsembleVote &out)
   {
      out.Reset();
      if(!m_ready || m_n_models == 0) return false;

      ArrayResize(out.scores,  m_n_models);
      ArrayResize(out.weights, m_n_models);
      out.n_models = m_n_models;

      double weighted_sum = 0.0, weight_total = 0.0;
      for(int i=0; i<m_n_models; i++)
      {
         double score = 0.0;
         if(!m_models[i]->ForwardFV(fv, score)) score = 0.0;
         out.scores[i]  = score;
         out.weights[i] = m_weights[i];
         weighted_sum  += score * m_weights[i];
         weight_total  += m_weights[i];
      }

      out.final_score = (weight_total > 0.0) ? weighted_sum / weight_total : 0.0;
      out.agreement   = ComputeAgreement(out.scores);
      return true;
   }

   void UpdateWeight(int model_idx, double new_weight)
   {
      if(model_idx < 0 || model_idx >= m_n_models) return;
      m_weights[model_idx] = MathMax(0.1, new_weight);
      NormalizeWeights();
   }

   // FIX AI-003: Expose model for SGD update from CAITrainer
   CAIInference *GetModel(int idx)
   {
      if(idx < 0 || idx >= m_n_models) return NULL;
      return m_models[idx];
   }

   void NormalizeWeights()
   {
      double total = 0.0;
      for(int i=0; i<m_n_models; i++) total += m_weights[i];
      if(total > 0.0)
         for(int i=0; i<m_n_models; i++) m_weights[i] /= total;
   }

   int  GetModelCount() const { return m_n_models; }
   bool IsReady()       const { return m_ready;    }
};

#endif // __AI_ENSEMBLE_MQH__
