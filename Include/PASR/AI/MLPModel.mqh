//+------------------------------------------------------------------+
//| AI/MLPModel.mqh — v1.00                                          |
//| Lightweight Multi-Layer Perceptron for ensemble voting           |
//| Copyright @2026                                                  |
//| agsicentre.wordpress.com                                         |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_MLP_MODEL_MQH__
#define __AI_MLP_MODEL_MQH__

#include "AITypes.mqh"

#define MLP_HIDDEN1 64
#define MLP_HIDDEN2 32

//+------------------------------------------------------------------+
//| CMLPModel — simple 2-hidden-layer MLP                           |
//| Input: AI_FEATURE_DIM  Hidden1: 64  Hidden2: 32  Output: 1      |
//+------------------------------------------------------------------+
class CMLPModel
  {
private:
   double   m_W1[AI_FEATURE_DIM * MLP_HIDDEN1];
   double   m_b1[MLP_HIDDEN1];
   double   m_W2[MLP_HIDDEN1 * MLP_HIDDEN2];
   double   m_b2[MLP_HIDDEN2];
   double   m_W3[MLP_HIDDEN2];
   double   m_b3;

   bool     m_loaded;
   string   m_model_id;
   int      m_rand_seed;
   int      m_train_count;

   double ReLU(double x)     const { return MathMax(0.0, x); }
   double Sigmoid(double x)  const { return 1.0 / (1.0 + MathExp(-x)); }

   // FIX v1.02: explicit feat_dim param — avoids any const/ArraySize issue
   void Forward1(double &x[], int feat_dim, double &h1[]) const
     {
      for(int j = 0; j < MLP_HIDDEN1; j++)
        {
         double z = m_b1[j];
         for(int i = 0; i < feat_dim; i++)
            z += x[i] * m_W1[i * MLP_HIDDEN1 + j];
         h1[j] = ReLU(z);
        }
     }

   void Forward2(double &h1[], double &h2[]) const
     {
      for(int j = 0; j < MLP_HIDDEN2; j++)
        {
         double z = m_b2[j];
         for(int i = 0; i < MLP_HIDDEN1; i++)
            z += h1[i] * m_W2[i * MLP_HIDDEN2 + j];
         h2[j] = ReLU(z);
        }
     }

   double Forward3(double &h2[]) const
     {
      double z = m_b3;
      for(int i = 0; i < MLP_HIDDEN2; i++)
         z += h2[i] * m_W3[i];
      return Sigmoid(z);
     }

public:
   CMLPModel(int seed = 42)
      : m_loaded(false), m_rand_seed(seed), m_train_count(0), m_b3(0.0)
     {
      m_model_id = StringFormat("mlp_s%d", seed);
      ArrayInitialize(m_W1, 0.0);
      ArrayInitialize(m_b1, 0.0);
      ArrayInitialize(m_W2, 0.0);
      ArrayInitialize(m_b2, 0.0);
      ArrayInitialize(m_W3, 0.0);
     }

   void RandomInit(int seed = -1)
     {
      if(seed >= 0) m_rand_seed = seed;
      MathSrand(m_rand_seed);

      double scale1 = MathSqrt(2.0 / AI_FEATURE_DIM);
      for(int i = 0; i < AI_FEATURE_DIM * MLP_HIDDEN1; i++)
         m_W1[i] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * scale1;
      ArrayInitialize(m_b1, 0.0);

      double scale2 = MathSqrt(2.0 / MLP_HIDDEN1);
      for(int i = 0; i < MLP_HIDDEN1 * MLP_HIDDEN2; i++)
         m_W2[i] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * scale2;
      ArrayInitialize(m_b2, 0.0);

      double scale3 = MathSqrt(2.0 / MLP_HIDDEN2);
      for(int i = 0; i < MLP_HIDDEN2; i++)
         m_W3[i] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * scale3;
      m_b3 = 0.0;

      m_loaded = true;
     }

   // FIX v1.02: Forward takes explicit feat_dim — caller passes AI_FEATURE_DIM
   bool Forward(double &x[], int feat_dim, double &out_score) const
     {
      out_score = 0.0;
      if(!m_loaded || feat_dim < 1) return false;

      double h1[MLP_HIDDEN1];
      double h2[MLP_HIDDEN2];
      Forward1(x, feat_dim, h1);
      Forward2(h1, h2);
      out_score = Forward3(h2);
      return true;
     }

   // Convenience overload: uses AI_FEATURE_DIM directly
   bool ForwardFV(SAIFeatureVector &fv, double &out_score) const
     {
      return Forward(fv.features, AI_FEATURE_DIM, out_score);
     }

   // FIX v1.02: OnlineUpdate takes explicit feat_dim and lr params
   void OnlineUpdate(double &x[], int feat_dim, double label, double lr = 0.01)
     {
      if(!m_loaded || feat_dim < 1) return;

      double h1[MLP_HIDDEN1];
      double h2[MLP_HIDDEN2];
      Forward1(x, feat_dim, h1);
      Forward2(h1, h2);
      double y = Forward3(h2);

      double delta3 = (y - label) * y * (1.0 - y);
      for(int i = 0; i < MLP_HIDDEN2; i++)
         m_W3[i] -= lr * delta3 * h2[i];
      m_b3 -= lr * delta3;

      double d2[MLP_HIDDEN2];
      for(int j = 0; j < MLP_HIDDEN2; j++)
        {
         d2[j] = delta3 * m_W3[j] * (h2[j] > 0 ? 1.0 : 0.0);
         for(int i = 0; i < MLP_HIDDEN1; i++)
            m_W2[i * MLP_HIDDEN2 + j] -= lr * d2[j] * h1[i];
         m_b2[j] -= lr * d2[j];
        }

      double d1[MLP_HIDDEN1];
      for(int j = 0; j < MLP_HIDDEN1; j++)
        {
         d1[j] = 0.0;
         for(int k = 0; k < MLP_HIDDEN2; k++)
            d1[j] += d2[k] * m_W2[j * MLP_HIDDEN2 + k];
         d1[j] *= (h1[j] > 0 ? 1.0 : 0.0);
         for(int i = 0; i < feat_dim; i++)
            m_W1[i * MLP_HIDDEN1 + j] -= lr * d1[j] * x[i];
         m_b1[j] -= lr * d1[j];
        }

      m_train_count++;
     }

   bool   IsLoaded()    const { return m_loaded; }
   string ModelId()     const { return m_model_id; }
   int    TrainCount()  const { return m_train_count; }
  };

#endif // __AI_MLP_MODEL_MQH__
