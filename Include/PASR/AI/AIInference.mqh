//+------------------------------------------------------------------+
//| AI/AIInference.mqh — v1.02                                       |
//| Expert routing + MLP forward pass for PASR AI subsystem          |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_INFERENCE_MQH__
#define __AI_INFERENCE_MQH__

#include "AITypes.mqh"
#include "../Core/IManager.mqh"

struct SMLPLayer
  {
   double weights[];
   double biases[];
   bool   relu;
   int    in_size;
   int    out_size;
  };

class CAIInference : public IManager
  {
private:
   bool     m_loaded;
   string   m_model_id;
   int      m_n_layers;
   int      m_rand_seed;

   double   m_w1[][64];
   double   m_b1[64];
   double   m_w2[64][32];
   double   m_b2[32];
   double   m_w3[32];
   double   m_b3;

   double ReLU(double x) { return MathMax(0.0, x); }
   double Tanh(double x)
     {
      double e2 = MathExp(2.0 * x);
      return (e2 - 1.0) / (e2 + 1.0);
     }

   void InitRandomWeights()
     {
      MathSrand(m_rand_seed);
      double scale1 = MathSqrt(2.0 / (AI_FEATURE_DIM + 64));
      double scale2 = MathSqrt(2.0 / (64 + 32));
      double scale3 = MathSqrt(2.0 / (32 + 1));

      ArrayResize(m_w1, AI_FEATURE_DIM);
      for(int i = 0; i < AI_FEATURE_DIM; i++)
         for(int j = 0; j < 64; j++)
            m_w1[i][j] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * scale1;
      for(int j = 0; j < 64; j++) m_b1[j] = 0.0;
      for(int i = 0; i < 64; i++)
         for(int j = 0; j < 32; j++)
            m_w2[i][j] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * scale2;
      for(int j = 0; j < 32; j++) m_b2[j] = 0.0;
      for(int i = 0; i < 32; i++)
         m_w3[i] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * scale3;
      m_b3 = 0.0;
     }

public:
   CAIInference(int seed = 42)
      : IManager(), m_loaded(false), m_model_id("mlp_v2_26dim"), m_n_layers(3),
        m_rand_seed(seed), m_b3(0.0)
     {
      ArrayInitialize(m_b1, 0.0);
      ArrayInitialize(m_b2, 0.0);
      ArrayInitialize(m_w3, 0.0);
     }

   virtual string HandlerName() const override { return "AIInference"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      InitRandomWeights();
      m_loaded = true;
      PrintFormat("CAIInference[seed=%d]: MLP 26->64->32->1 ready", m_rand_seed);
      return true;
     }

   virtual void Deinit() override
     {
      m_loaded = false;
      IManager::Deinit();
     }

   virtual void DeclareEvents() override {}
   virtual void OnEvent(const PASREvent &ev) override {}

   bool Forward(const double &features[], double &out_score)
     {
      out_score = 0.0;
      if(!m_loaded) return false;
      if(ArraySize(features) < AI_FEATURE_DIM) return false;

      double h1[64];
      for(int j = 0; j < 64; j++)
        {
         double s = m_b1[j];
         for(int i = 0; i < AI_FEATURE_DIM; i++) s += features[i] * m_w1[i][j];
         h1[j] = ReLU(s);
        }

      double h2[32];
      for(int j = 0; j < 32; j++)
        {
         double s = m_b2[j];
         for(int i = 0; i < 64; i++) s += h1[i] * m_w2[i][j];
         h2[j] = ReLU(s);
        }

      double s = m_b3;
      for(int i = 0; i < 32; i++) s += h2[i] * m_w3[i];
      out_score = Tanh(s);
      return true;
     }

   bool ForwardFV(const SAIFeatureVector &fv, double &out_score)
     {
      return Forward(fv.features, out_score);
     }

   bool SGDUpdate(const double &features[], double label, double lr)
     {
      if(!m_loaded || ArraySize(features) < AI_FEATURE_DIM) return false;

      double h1[64], h2[32];
      for(int j = 0; j < 64; j++)
        {
         double s = m_b1[j];
         for(int i = 0; i < AI_FEATURE_DIM; i++) s += features[i] * m_w1[i][j];
         h1[j] = ReLU(s);
        }
      for(int j = 0; j < 32; j++)
        {
         double s = m_b2[j];
         for(int i = 0; i < 64; i++) s += h1[i] * m_w2[i][j];
         h2[j] = ReLU(s);
        }

      double s3 = m_b3;
      for(int i = 0; i < 32; i++) s3 += h2[i] * m_w3[i];
      double pred = Tanh(s3);
      double delta3 = 2.0 * (pred - label) * (1.0 - pred * pred);

      for(int i = 0; i < 32; i++) m_w3[i] -= lr * delta3 * h2[i];
      m_b3 -= lr * delta3;

      double delta2[32];
      for(int j = 0; j < 32; j++)
         delta2[j] = (h2[j] > 0.0) ? delta3 * m_w3[j] : 0.0;
      for(int j = 0; j < 32; j++)
        {
         for(int i = 0; i < 64; i++) m_w2[i][j] -= lr * delta2[j] * h1[i];
         m_b2[j] -= lr * delta2[j];
        }

      double delta1[64];
      for(int k = 0; k < 64; k++)
        {
         if(h1[k] <= 0.0) { delta1[k] = 0.0; continue; }
         double g = 0.0;
         for(int j = 0; j < 32; j++) g += delta2[j] * m_w2[k][j];
         delta1[k] = g;
        }
      for(int k = 0; k < 64; k++)
        {
         for(int i = 0; i < AI_FEATURE_DIM; i++) m_w1[i][k] -= lr * delta1[k] * features[i];
         m_b1[k] -= lr * delta1[k];
        }

      return true;
     }

   bool   IsLoaded() const { return m_loaded; }
   string GetModelId() const { return m_model_id; }
   int    GetSeed() const { return m_rand_seed; }
   void   SetModelId(string id) { m_model_id = id; }
  };

#endif // __AI_INFERENCE_MQH__