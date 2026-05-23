//+------------------------------------------------------------------+
//| AI/AIInference.mqh                                               |
//| Expert routing + MLP forward pass for PASR AI subsystem          |
//| Sprint 10: Path fix ../Core/ -> ../../Core/                      |
//|            Path fix ../Data/ -> ../../Data/                      |
//| FIX AI-007: Tanh() replaced with MathTanh() — no NaN on large x |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_INFERENCE_MQH__
#define __AI_INFERENCE_MQH__

#include "AITypes.mqh"
#include "../../Core/IManager.mqh"
#include "../../Data/RegimeTypes.mqh"

//--- Minimal MLP layer descriptor
struct SMLPLayer
{
   double weights[][];  // [in x out]
   double biases[];     // [out]
   bool   relu;         // use ReLU activation?
   int    in_size;
   int    out_size;
};

//+------------------------------------------------------------------+
//| CAIInference                                                     |
//| Lightweight MLP inference engine                                 |
//| Architecture: 26 -> 64 -> 32 -> 1 (tanh output)                 |
//| FIX AI-007: Uses MathTanh() instead of manual exp() formula     |
//+------------------------------------------------------------------+
class CAIInference : public IManager
{
private:
   bool     m_loaded;
   string   m_model_id;
   int      m_n_layers;
   int      m_rand_seed;         // FIX AI-004: configurable seed for ensemble diversity

   double   m_w1[][64];    // 26 x 64
   double   m_b1[64];
   double   m_w2[64][32];  // 64 x 32
   double   m_b2[32];
   double   m_w3[32];      // 32 x 1
   double   m_b3;

   double ReLU(double x) { return MathMax(0.0, x); }

   // FIX AI-007: Was (exp(2x)-1)/(exp(2x)+1) — computed exp(2x) twice,
   //             overflowed to INF for x>350 producing NaN.
   //             MathTanh() is the MQL5 built-in; no overflow.
   double Tanh(double x) { return MathTanh(x); }

   double Sigmoid(double x) { return 1.0/(1.0+MathExp(-x)); }

   void InitRandomWeights()
   {
      MathSrand(m_rand_seed);  // FIX AI-004: use configurable seed
      double scale1 = MathSqrt(2.0 / (AI_FEATURE_DIM + 64));
      double scale2 = MathSqrt(2.0 / (64 + 32));
      double scale3 = MathSqrt(2.0 / (32 + 1));

      ArrayResize(m_w1, AI_FEATURE_DIM);
      for(int i=0; i<AI_FEATURE_DIM; i++)
         for(int j=0; j<64; j++)
            m_w1[i][j] = ((double)MathRand()/32767.0 - 0.5) * 2.0 * scale1;
      for(int j=0; j<64; j++) m_b1[j] = 0.0;
      for(int i=0; i<64;  i++)
         for(int j=0; j<32; j++)
            m_w2[i][j] = ((double)MathRand()/32767.0 - 0.5) * 2.0 * scale2;
      for(int j=0; j<32; j++) m_b2[j] = 0.0;
      for(int i=0; i<32; i++)
         m_w3[i] = ((double)MathRand()/32767.0 - 0.5) * 2.0 * scale3;
      m_b3 = 0.0;
   }

public:
   // FIX AI-004: Accept seed in constructor so ensemble can use different seeds
   CAIInference(int seed = 42)
      : m_loaded(false), m_model_id("mlp_v2_26dim"), m_n_layers(3),
        m_rand_seed(seed), m_b3(0.0)
   {
      ArrayInitialize(m_b1, 0.0);
      ArrayInitialize(m_b2, 0.0);
      ArrayInitialize(m_w3, 0.0);
   }

   virtual bool Initialize(CEventBus *bus) override
   {
      if(!IManager::Initialize(bus)) return false;
      InitRandomWeights();
      m_loaded = true;
      PrintFormat("CAIInference[seed=%d]: MLP 26->64->32->1 ready", m_rand_seed);
      return true;
   }

   virtual void Shutdown() override { m_loaded = false; IManager::Shutdown(); }
   virtual void DeclareEvents() override {}
   virtual void OnEvent(const PASREvent &ev) override {}

   //--- Forward pass: 26-dim input -> scalar score [-1..1]
   bool Forward(const double &features[], double &out_score)
   {
      out_score = 0.0;
      if(!m_loaded) return false;
      if(ArraySize(features) < AI_FEATURE_DIM) return false;

      // Layer 1: 26 -> 64 (ReLU)
      double h1[64];
      for(int j=0; j<64; j++)
      {
         double s = m_b1[j];
         for(int i=0; i<AI_FEATURE_DIM; i++) s += features[i] * m_w1[i][j];
         h1[j] = ReLU(s);
      }

      // Layer 2: 64 -> 32 (ReLU)
      double h2[32];
      for(int j=0; j<32; j++)
      {
         double s = m_b2[j];
         for(int i=0; i<64; i++) s += h1[i] * m_w2[i][j];
         h2[j] = ReLU(s);
      }

      // Layer 3: 32 -> 1 (Tanh) — FIX AI-007: MathTanh(), no NaN
      double s = m_b3;
      for(int i=0; i<32; i++) s += h2[i] * m_w3[i];
      out_score = Tanh(s);
      return true;
   }

   bool ForwardFV(const SAIFeatureVector &fv, double &out_score)
   {
      return Forward(fv.features, out_score);
   }

   // FIX AI-003: SGD weight update — called by CAITrainer after MaybeRetrain()
   // Performs one gradient step on a mini-batch from the trainer buffer.
   // grad_w3[i] = err * h2[i], etc. (simplified one-sample SGD)
   bool SGDUpdate(const double &features[], double label, double lr)
   {
      if(!m_loaded || ArraySize(features) < AI_FEATURE_DIM) return false;

      // Forward pass (keep activations)
      double h1[64], h2[32];
      for(int j=0; j<64; j++)
      {
         double s = m_b1[j];
         for(int i=0; i<AI_FEATURE_DIM; i++) s += features[i] * m_w1[i][j];
         h1[j] = ReLU(s);
      }
      for(int j=0; j<32; j++)
      {
         double s = m_b2[j];
         for(int i=0; i<64; i++) s += h1[i] * m_w2[i][j];
         h2[j] = ReLU(s);
      }
      double s3 = m_b3;
      for(int i=0; i<32; i++) s3 += h2[i] * m_w3[i];
      double pred = Tanh(s3);

      // Output error: dL/d_pred = 2*(pred - label), tanh' = 1 - tanh^2
      double delta3 = 2.0 * (pred - label) * (1.0 - pred*pred);

      // Update layer 3
      for(int i=0; i<32; i++)
         m_w3[i] -= lr * delta3 * h2[i];
      m_b3 -= lr * delta3;

      // Backprop into layer 2 (ReLU gate: grad=0 if h2[j]==0)
      double delta2[32];
      for(int j=0; j<32; j++)
         delta2[j] = (h2[j] > 0.0) ? delta3 * m_w3[j] : 0.0;
      for(int j=0; j<32; j++)
      {
         for(int i=0; i<64; i++) m_w2[i][j] -= lr * delta2[j] * h1[i];
         m_b2[j] -= lr * delta2[j];
      }

      // Backprop into layer 1 (ReLU gate)
      double delta1[64];
      for(int k=0; k<64; k++)
      {
         if(h1[k] <= 0.0) { delta1[k]=0.0; continue; }
         double g = 0.0;
         for(int j=0; j<32; j++) g += delta2[j] * m_w2[k][j];
         delta1[k] = g;
      }
      for(int k=0; k<64; k++)
      {
         for(int i=0; i<AI_FEATURE_DIM; i++) m_w1[i][k] -= lr * delta1[k] * features[i];
         m_b1[k] -= lr * delta1[k];
      }

      return true;
   }

   bool     IsLoaded()    const { return m_loaded;    }
   string   GetModelId()  const { return m_model_id;  }
   int      GetSeed()     const { return m_rand_seed; }
   void     SetModelId(string id) { m_model_id = id; }
};

#endif // __AI_INFERENCE_MQH__
