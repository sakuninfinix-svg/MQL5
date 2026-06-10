//+------------------------------------------------------------------+
//| AI/MLPModel.mqh — v1.01                                         |
//| Lightweight Multi-Layer Perceptron for ensemble voting           |
//| FIX v1.01: removed 'const' from all array reference parameters  |
//|            MQL5 forbids 'const' on reference array parameters   |
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
   // Layer weights — stored flat row-major
   double   m_W1[AI_FEATURE_DIM * MLP_HIDDEN1];   // input→hidden1
   double   m_b1[MLP_HIDDEN1];
   double   m_W2[MLP_HIDDEN1 * MLP_HIDDEN2];       // hidden1→hidden2
   double   m_b2[MLP_HIDDEN2];
   double   m_W3[MLP_HIDDEN2];                     // hidden2→output
   double   m_b3;

   bool     m_loaded;
   string   m_model_id;
   int      m_rand_seed;
   int      m_train_count;

   double ReLU(double x) const { return MathMax(0.0, x); }
   double Sigmoid(double x) const { return 1.0 / (1.0 + MathExp(-x)); }

   // FIX: MQL5 does NOT allow 'const' on reference array parameters.
   // Signature: (array_ref, size, output_array) — size param avoids ArraySize on const.
   void Forward1(double &input[], int input_size, double &h1[]) const
     {
      for(int j = 0; j < MLP_HIDDEN1; j++)
        {
         double z = m_b1[j];
         for(int i = 0; i < input_size; i++)
            z += input[i] * m_W1[i * MLP_HIDDEN1 + j];
         h1[j] = ReLU(z);
        }
     }

   // Forward pass — fills hidden2[MLP_HIDDEN2] from h1
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

   // Forward pass — returns sigmoid output from h2
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

   // Initialise with random weights (Xavier / He scaling)
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

   // FIX: Forward — remove 'const' from array param, add explicit size
   bool Forward(double &input[], double &out_score) const
     {
      out_score = 0.0;
      int sz = ArraySize(input);
      if(!m_loaded || sz < AI_FEATURE_DIM) return false;

      double h1[MLP_HIDDEN1];
      double h2[MLP_HIDDEN2];
      Forward1(input, AI_FEATURE_DIM, h1);
      Forward2(h1, h2);
      out_score = Forward3(h2);
      return true;
     }

   // Forward pass on SAIFeatureVector (convenience overload)
   bool ForwardFV(SAIFeatureVector &fv, double &out_score) const
     {
      return Forward(fv.features, out_score);
     }

   // FIX: OnlineUpdate — remove 'const' from input array param
   void OnlineUpdate(double &input[], double label, double lr = 0.01)
     {
      if(!m_loaded || ArraySize(input) < AI_FEATURE_DIM) return;

      double h1[MLP_HIDDEN1];
      double h2[MLP_HIDDEN2];
      Forward1(input, AI_FEATURE_DIM, h1);
      Forward2(h1, h2);
      double y = Forward3(h2);

      // Output layer gradient
      double delta3 = (y - label) * y * (1.0 - y);   // dL/dz3
      for(int i = 0; i < MLP_HIDDEN2; i++)
         m_W3[i] -= lr * delta3 * h2[i];
      m_b3 -= lr * delta3;

      // Hidden2 gradient
      double d2[MLP_HIDDEN2];
      for(int j = 0; j < MLP_HIDDEN2; j++)
        {
         d2[j] = delta3 * m_W3[j] * (h2[j] > 0 ? 1.0 : 0.0);  // ReLU deriv
         for(int i = 0; i < MLP_HIDDEN1; i++)
            m_W2[i * MLP_HIDDEN2 + j] -= lr * d2[j] * h1[i];
         m_b2[j] -= lr * d2[j];
        }

      // Hidden1 gradient
      double d1[MLP_HIDDEN1];
      for(int j = 0; j < MLP_HIDDEN1; j++)
        {
         d1[j] = 0.0;
         for(int k = 0; k < MLP_HIDDEN2; k++)
            d1[j] += d2[k] * m_W2[j * MLP_HIDDEN2 + k];
         d1[j] *= (h1[j] > 0 ? 1.0 : 0.0);
         for(int i = 0; i < AI_FEATURE_DIM; i++)
            m_W1[i * MLP_HIDDEN1 + j] -= lr * d1[j] * input[i];
         m_b1[j] -= lr * d1[j];
        }

      m_train_count++;
     }

   bool   IsLoaded()     const { return m_loaded; }
   string ModelId()      const { return m_model_id; }
   int    TrainCount()   const { return m_train_count; }
  };

#endif // __AI_MLP_MODEL_MQH__
