//+------------------------------------------------------------------+
//| AI/AttentionFusion.mqh — v1.02                                   |
//| Multi-head attention mechanism for feature fusion                |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_ATTENTION_FUSION_MQH__
#define __AI_ATTENTION_FUSION_MQH__

#include "AITypes.mqh"
#include "../Core/IManager.mqh"

#define ATTENTION_HEADS 4
#define ATTENTION_DIM 32
#define MAX_FEATURE_SOURCES 10

struct AttentionHead
{
   double W_q[][ATTENTION_DIM];
   double W_k[][ATTENTION_DIM];
   double W_v[][ATTENTION_DIM];
   double W_o[ATTENTION_DIM];
   int    input_dim;

   void Reset()
   {
      ArrayInitialize(W_q, 0.0);
      ArrayInitialize(W_k, 0.0);
      ArrayInitialize(W_v, 0.0);
      ArrayInitialize(W_o, 0.0);
   }
};

struct AttentionWeights
{
   double weights[MAX_FEATURE_SOURCES];
   int    count;

   void Reset()
   {
      ArrayInitialize(weights, 0.0);
      count = 0;
   }

   void Normalize()
   {
      double sum = 0.0;
      for(int i = 0; i < count; i++) sum += weights[i];
      if(sum > 0)
         for(int i = 0; i < count; i++) weights[i] /= sum;
   }
};

class CAttentionFusion : public IManager
{
private:
   AttentionHead m_heads[ATTENTION_HEADS];
   double        m_layer_norm_gamma;
   double        m_layer_norm_beta;
   int           m_input_dim;
   int           m_output_dim;
   // m_initialized inherited from IManager — do not redeclare
   int           m_rand_seed;

   // FIX: MQL5 does not allow 'const' on reference array parameters
   double Softmax(double &scores[], int count, double &output[])
   {
      double maxScore = -DBL_MAX;
      for(int i = 0; i < count; i++)
         if(scores[i] > maxScore) maxScore = scores[i];

      double sum = 0.0;
      for(int i = 0; i < count; i++)
      {
         output[i] = MathExp(scores[i] - maxScore);
         sum += output[i];
      }
      if(sum > 0)
         for(int i = 0; i < count; i++) output[i] /= sum;

      return sum;
   }

   void InitRandomWeights()
   {
      MathSrand(m_rand_seed);
      double scale = MathSqrt(2.0 / (m_input_dim + ATTENTION_DIM));

      for(int h = 0; h < ATTENTION_HEADS; h++)
      {
         ArrayResize(m_heads[h].W_q, m_input_dim);
         ArrayResize(m_heads[h].W_k, m_input_dim);
         ArrayResize(m_heads[h].W_v, m_input_dim);
         m_heads[h].input_dim = m_input_dim;

         for(int i = 0; i < m_input_dim; i++)
            for(int j = 0; j < ATTENTION_DIM; j++)
            {
               m_heads[h].W_q[i][j] = ((double)MathRand()/32767.0-0.5)*2.0*scale;
               m_heads[h].W_k[i][j] = ((double)MathRand()/32767.0-0.5)*2.0*scale;
               m_heads[h].W_v[i][j] = ((double)MathRand()/32767.0-0.5)*2.0*scale;
            }
         for(int j = 0; j < ATTENTION_DIM; j++)
            m_heads[h].W_o[j] = ((double)MathRand()/32767.0-0.5)*2.0*scale;
      }
      m_layer_norm_gamma = 1.0;
      m_layer_norm_beta  = 0.0;
   }

   void LayerNorm(double &input[], double &output[], int size) const
   {
      double mean = 0.0;
      for(int i = 0; i < size; i++) mean += input[i];
      mean /= size;
      double variance = 0.0;
      for(int i = 0; i < size; i++) variance += (input[i]-mean)*(input[i]-mean);
      variance /= size;
      double std = MathSqrt(variance + 1e-6);
      for(int i = 0; i < size; i++)
         output[i] = m_layer_norm_gamma * (input[i]-mean)/std + m_layer_norm_beta;
   }

public:
   CAttentionFusion(int inputDim = AI_FEATURE_DIM, int seed = 42)
      : IManager(), m_input_dim(inputDim), m_output_dim(ATTENTION_HEADS * ATTENTION_DIM),
        m_rand_seed(seed), m_layer_norm_gamma(1.0), m_layer_norm_beta(0.0)
   {
      for(int h = 0; h < ATTENTION_HEADS; h++) m_heads[h].Reset();
   }

   virtual string HandlerName() const override { return "AttentionFusion"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
   {
      if(!IManager::Init(data, bus)) return false;
      InitRandomWeights();
      m_initialized = true;
      return true;
   }

   virtual void Deinit() override
   {
      m_initialized = false;
      IManager::Deinit();
   }

   virtual void DeclareEvents() override {}
   virtual void OnEvent(const PASREvent &ev) override {}

   // FIX: remove 'const' from array params — MQL5 forbids const on ref array params
   bool Fuse(double &sources[], int n_sources,
             int source_dim, double &output[])
   {
      if(!m_initialized || n_sources <= 0 || source_dim <= 0) return false;

      ArrayResize(output, m_output_dim);
      ArrayInitialize(output, 0.0);

      // Simple weighted average attention across source blocks
      for(int h = 0; h < ATTENTION_HEADS; h++)
      {
         double attn_scores[MAX_FEATURE_SOURCES];
         double attn_weights[MAX_FEATURE_SOURCES];

         for(int s = 0; s < n_sources && s < MAX_FEATURE_SOURCES; s++)
         {
            double score = 0.0;
            int offset = s * source_dim;
            for(int i = 0; i < MathMin(source_dim, m_input_dim); i++)
               for(int j = 0; j < ATTENTION_DIM; j++)
                  score += sources[offset + i] * m_heads[h].W_q[i][j];
            attn_scores[s] = score;
         }

         Softmax(attn_scores, n_sources, attn_weights);

         for(int j = 0; j < ATTENTION_DIM; j++)
         {
            double val = 0.0;
            for(int s = 0; s < n_sources && s < MAX_FEATURE_SOURCES; s++)
            {
               int offset = s * source_dim;
               double v = 0.0;
               for(int i = 0; i < MathMin(source_dim, m_input_dim); i++)
                  v += sources[offset + i] * m_heads[h].W_v[i][j];
               val += attn_weights[s] * v;
            }
            output[h * ATTENTION_DIM + j] = val * m_heads[h].W_o[j];
         }
      }

      double normed[ATTENTION_HEADS * ATTENTION_DIM];
      LayerNorm(output, normed, m_output_dim);
      ArrayCopy(output, normed);
      return true;
   }

   bool IsReady()    const { return m_initialized; }
   int  OutputDim()  const { return m_output_dim; }
};

#endif // __AI_ATTENTION_FUSION_MQH__
