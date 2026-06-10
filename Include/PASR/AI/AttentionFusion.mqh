//+------------------------------------------------------------------+
//| AI/AttentionFusion.mqh — v1.01                                   |
//| Multi-head attention mechanism for feature fusion                |
//| Enables adaptive weighting of different signal sources           |
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
   double W_q[][ATTENTION_DIM];  // Query weights
   double W_k[][ATTENTION_DIM];  // Key weights
   double W_v[][ATTENTION_DIM];  // Value weights
   double W_o[ATTENTION_DIM];    // Output weights
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
      for(int i = 0; i < count; i++)
         sum += weights[i];
      
      if(sum > 0)
      {
         for(int i = 0; i < count; i++)
            weights[i] /= sum;
      }
   }
};

class CAttentionFusion : public IManager
{
private:
   AttentionHead m_heads[ATTENTION_HEADS];
   double         m_layer_norm_gamma;
   double         m_layer_norm_beta;
   int            m_input_dim;
   int            m_output_dim;
   // REMOVED: bool m_initialized; — inherited from IManager, redeclaration hides base member
   int            m_rand_seed;
   
   double Softmax(const double &scores[], int count, double &output[])
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
      {
         for(int i = 0; i < count; i++)
            output[i] /= sum;
      }
      
      return sum;
   }
   
   double DotProduct(const double &a[], const double &b[], int size) const
   {
      double result = 0.0;
      for(int i = 0; i < size; i++)
         result += a[i] * b[i];
      return result;
   }
   
   void InitializeWeights()
   {
      MathSrand(m_rand_seed);
      double scale = MathSqrt(2.0 / (m_input_dim + ATTENTION_DIM));
      
      for(int h = 0; h < ATTENTION_HEADS; h++)
      {
         m_heads[h].input_dim = m_input_dim;
         ArrayResize(m_heads[h].W_q, m_input_dim);
         ArrayResize(m_heads[h].W_k, m_input_dim);
         ArrayResize(m_heads[h].W_v, m_input_dim);
         
         for(int i = 0; i < m_input_dim; i++)
         {
            for(int j = 0; j < ATTENTION_DIM; j++)
            {
               m_heads[h].W_q[i][j] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * scale;
               m_heads[h].W_k[i][j] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * scale;
               m_heads[h].W_v[i][j] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * scale;
            }
         }
         
         for(int j = 0; j < ATTENTION_DIM; j++)
            m_heads[h].W_o[j] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * scale;
      }
      
      m_layer_norm_gamma = 1.0;
      m_layer_norm_beta = 0.0;
   }
   
   void LayerNorm(const double &input[], double &output[], int size) const
   {
      double mean = 0.0;
      for(int i = 0; i < size; i++)
         mean += input[i];
      mean /= size;
      
      double variance = 0.0;
      for(int i = 0; i < size; i++)
         variance += (input[i] - mean) * (input[i] - mean);
      variance /= size;
      
      double std = MathSqrt(variance + 1e-6);
      
      for(int i = 0; i < size; i++)
         output[i] = m_layer_norm_gamma * (input[i] - mean) / std + m_layer_norm_beta;
   }
   
public:
   CAttentionFusion(int inputDim = AI_FEATURE_DIM, int seed = 42)
      : IManager(), m_input_dim(inputDim), m_output_dim(ATTENTION_HEADS * ATTENTION_DIM),
        m_rand_seed(seed), m_layer_norm_gamma(1.0), m_layer_norm_beta(0.0)
   {
      for(int h = 0; h < ATTENTION_HEADS; h++)
         m_heads[h].Reset();
   }
   
   virtual string HandlerName() const override { return "AttentionFusion"; }
   
   virtual bool Init(IDataManager *data, CEventBus *bus) override
   {
      if(!IManager::Init(data, bus)) return false;
      InitializeWeights();
      m_initialized = true;
      PrintFormat("[AttentionFusion] Multi-head attention initialized: %d heads, %d dim", 
                  ATTENTION_HEADS, ATTENTION_DIM);
      return true;
   }
   
   virtual void Deinit() override
   {
      m_initialized = false;
      IManager::Deinit();
   }
   
   virtual void DeclareEvents() override {}
   virtual void OnEvent(const PASREvent &ev) override {}
   
   bool ComputeAttention(const double &features[][AI_FEATURE_DIM], int featureCount, 
                        AttentionWeights &outWeights)
   {
      if(!m_initialized) return false;
      if(featureCount <= 0 || featureCount > MAX_FEATURE_SOURCES) return false;
      
      outWeights.Reset();
      outWeights.count = featureCount;
      
      double totalScores[MAX_FEATURE_SOURCES];
      ArrayInitialize(totalScores, 0.0);
      
      for(int h = 0; h < ATTENTION_HEADS; h++)
      {
         double headScores[MAX_FEATURE_SOURCES];
         ArrayInitialize(headScores, 0.0);
         
         for(int f = 0; f < featureCount; f++)
         {
            double q[ATTENTION_DIM], k[ATTENTION_DIM], v[ATTENTION_DIM];
            ArrayInitialize(q, 0.0);
            ArrayInitialize(k, 0.0);
            ArrayInitialize(v, 0.0);
            
            for(int i = 0; i < m_input_dim; i++)
            {
               for(int j = 0; j < ATTENTION_DIM; j++)
               {
                  q[j] += features[f][i] * m_heads[h].W_q[i][j];
                  k[j] += features[f][i] * m_heads[h].W_k[i][j];
                  v[j] += features[f][i] * m_heads[h].W_v[i][j];
               }
            }
            
            double score = DotProduct(q, k, ATTENTION_DIM) / MathSqrt((double)ATTENTION_DIM);
            headScores[f] = score;
         }
         
         double softmaxScores[MAX_FEATURE_SOURCES];
         Softmax(headScores, featureCount, softmaxScores);
         
         for(int f = 0; f < featureCount; f++)
            totalScores[f] += softmaxScores[f];
      }
      
      for(int f = 0; f < featureCount; f++)
         totalScores[f] /= ATTENTION_HEADS;
      
      Softmax(totalScores, featureCount, outWeights.weights);
      outWeights.Normalize();
      
      return true;
   }
   
   bool FuseFeatures(const double &features[][AI_FEATURE_DIM], int featureCount,
                    const AttentionWeights &weights, double &fusedOutput[])
   {
      if(!m_initialized) return false;
      if(featureCount <= 0 || featureCount > MAX_FEATURE_SOURCES) return false;
      
      int outputSize = ATTENTION_HEADS * ATTENTION_DIM;
      ArrayResize(fusedOutput, outputSize);
      ArrayInitialize(fusedOutput, 0.0);
      
      for(int h = 0; h < ATTENTION_HEADS; h++)
      {
         int offset = h * ATTENTION_DIM;
         
         for(int f = 0; f < featureCount; f++)
         {
            double weight = weights.weights[f];
            
            double v[ATTENTION_DIM];
            ArrayInitialize(v, 0.0);
            
            for(int i = 0; i < m_input_dim; i++)
            {
               for(int j = 0; j < ATTENTION_DIM; j++)
                  v[j] += features[f][i] * m_heads[h].W_v[i][j];
            }
            
            for(int j = 0; j < ATTENTION_DIM; j++)
               fusedOutput[offset + j] += weight * v[j];
         }
         
         for(int j = 0; j < ATTENTION_DIM; j++)
            fusedOutput[offset + j] *= m_heads[h].W_o[j];
      }
      
      double normalized[];
      ArrayResize(normalized, outputSize);
      LayerNorm(fusedOutput, normalized, outputSize);
      
      for(int i = 0; i < outputSize; i++)
         fusedOutput[i] = normalized[i];
      
      return true;
   }
   
   bool Forward(const double &features[][AI_FEATURE_DIM], int featureCount,
               double &fusedOutput[], AttentionWeights &outWeights)
   {
      if(!ComputeAttention(features, featureCount, outWeights))
         return false;
      
      return FuseFeatures(features, featureCount, outWeights, fusedOutput);
   }
   
   int GetInputDim() const { return m_input_dim; }
   int GetOutputDim() const { return m_output_dim; }
   int GetNumHeads() const { return ATTENTION_HEADS; }
   bool IsInitialized() const { return m_initialized; }
};

#endif // __AI_ATTENTION_FUSION_MQH__
