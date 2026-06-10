//+------------------------------------------------------------------+
//| AI/AttentionFusion.mqh — v1.03                                   |
//| Attention-based fusion of MLP and LSTM scores                    |
//| FIX v1.03: all array params without 'const'; no m_initialized    |
//|            redeclaration; ForwardAttention explicit size param    |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_ATTENTION_FUSION_MQH__
#define __AI_ATTENTION_FUSION_MQH__

#include "AITypes.mqh"
#include "../Core/IManager.mqh"

#define ATTN_HEAD_DIM  16
#define ATTN_NUM_HEADS  4
#define ATTN_EMBED_DIM 64   // HEAD_DIM * NUM_HEADS

class CAttentionFusion : public IManager
  {
private:
   // Projection weights: input (AI_FEATURE_DIM) -> embed (ATTN_EMBED_DIM)
   double m_W_q[AI_FEATURE_DIM * ATTN_EMBED_DIM];
   double m_W_k[AI_FEATURE_DIM * ATTN_EMBED_DIM];
   double m_W_v[AI_FEATURE_DIM * ATTN_EMBED_DIM];
   // Output projection: embed -> 1
   double m_W_out[ATTN_EMBED_DIM];
   double m_b_out;

   bool   m_loaded;
   int    m_rand_seed;
   // NOTE: m_initialized is inherited from IManager — do NOT redeclare here

   double Sigmoid(double x) { return 1.0 / (1.0 + MathExp(-x)); }
   double SoftmaxDot(double &q[], double &k[], int dim)
     {
      double dot = 0.0;
      for(int i = 0; i < dim; i++) dot += q[i] * k[i];
      return dot / MathSqrt((double)dim);
     }

   // FIX v1.03: explicit int feat_dim — no 'const' on array param
   void Project(double &x[], int feat_dim, double &W[], int out_dim, double &out[])
     {
      ArrayResize(out, out_dim);
      for(int j = 0; j < out_dim; j++)
        {
         double z = 0.0;
         for(int i = 0; i < feat_dim; i++)
            z += x[i] * W[i * out_dim + j];
         out[j] = z;
        }
     }

   void InitRandomWeights()
     {
      MathSrand(m_rand_seed);
      double scale = MathSqrt(2.0 / (AI_FEATURE_DIM + ATTN_EMBED_DIM));
      for(int i = 0; i < AI_FEATURE_DIM * ATTN_EMBED_DIM; i++)
        {
         m_W_q[i] = ((double)MathRand()/32767.0-0.5)*2.0*scale;
         m_W_k[i] = ((double)MathRand()/32767.0-0.5)*2.0*scale;
         m_W_v[i] = ((double)MathRand()/32767.0-0.5)*2.0*scale;
        }
      double scale_out = MathSqrt(2.0 / ATTN_EMBED_DIM);
      for(int i = 0; i < ATTN_EMBED_DIM; i++)
         m_W_out[i] = ((double)MathRand()/32767.0-0.5)*2.0*scale_out;
      m_b_out = 0.0;
     }

public:
   CAttentionFusion(int seed = 42)
      : IManager(), m_loaded(false), m_rand_seed(seed), m_b_out(0.0)
     {
      ArrayInitialize(m_W_q,   0.0);
      ArrayInitialize(m_W_k,   0.0);
      ArrayInitialize(m_W_v,   0.0);
      ArrayInitialize(m_W_out, 0.0);
     }

   virtual string HandlerName() const override { return "AttentionFusion"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      InitRandomWeights();
      m_loaded = true;
      return true;
     }

   virtual void Deinit() override
     {
      m_loaded = false;
      IManager::Deinit();
     }

   virtual void DeclareEvents() override {}
   virtual void OnEvent(const PASREvent &ev) override {}

   // FIX v1.03: array param without 'const'; explicit AI_FEATURE_DIM passed
   bool ForwardAttention(double &features[], double mlp_score,
                         double lstm_score,  double &out_score)
     {
      out_score = 0.0;
      if(!m_loaded) return false;
      if(ArraySize(features) < AI_FEATURE_DIM) return false;

      double q[ATTN_EMBED_DIM];
      double k[ATTN_EMBED_DIM];
      double v[ATTN_EMBED_DIM];

      Project(features, AI_FEATURE_DIM, m_W_q, ATTN_EMBED_DIM, q);
      Project(features, AI_FEATURE_DIM, m_W_k, ATTN_EMBED_DIM, k);
      Project(features, AI_FEATURE_DIM, m_W_v, ATTN_EMBED_DIM, v);

      // Scaled dot-product attention
      double attn = SoftmaxDot(q, k, ATTN_EMBED_DIM);
      double attn_w = Sigmoid(attn);

      // Weighted fusion: attention-gated combination of MLP and LSTM scores
      double fused_score = attn_w * mlp_score + (1.0 - attn_w) * lstm_score;

      // Final projection through value vector
      double proj = m_b_out;
      for(int i = 0; i < ATTN_EMBED_DIM; i++)
         proj += v[i] * m_W_out[i];

      // Combine fused score with value projection
      out_score = Sigmoid(fused_score + proj * 0.1);
      return true;
     }

   bool IsLoaded() const { return m_loaded; }
  };

#endif // __AI_ATTENTION_FUSION_MQH__
