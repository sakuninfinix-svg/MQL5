//+------------------------------------------------------------------+
//| AI/AIInference.mqh                                               |
//| Copyright @2026                                                  |
//| agsicentre.wordpress.com                                         |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_INFERENCE_MQH__
#define __AI_INFERENCE_MQH__

#include "AITypes.mqh"
#include "../Core/IManager.mqh"

#define AI_MLP_HIDDEN1 64
#define AI_MLP_HIDDEN2 32
#define AI_MLP_OUTPUTS 1

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
   bool     m_external_weights_loaded;
   string   m_weights_file;

   double   m_w1[][AI_MLP_HIDDEN1];
   double   m_b1[AI_MLP_HIDDEN1];
   double   m_w2[AI_MLP_HIDDEN1][AI_MLP_HIDDEN2];
   double   m_b2[AI_MLP_HIDDEN2];
   double   m_w3[AI_MLP_HIDDEN2];
   double   m_b3;
   double   m_decision_threshold;

   double ReLU(double x) { return MathMax(0.0, x); }
   double Tanh(double x)
     {
      double e2 = MathExp(2.0 * x);
      return (e2 - 1.0) / (e2 + 1.0);
     }

   void InitRandomWeights()
     {
      MathSrand(m_rand_seed);
      double scale1 = MathSqrt(2.0 / (AI_FEATURE_DIM + AI_MLP_HIDDEN1));
      double scale2 = MathSqrt(2.0 / (AI_MLP_HIDDEN1 + AI_MLP_HIDDEN2));
      double scale3 = MathSqrt(2.0 / (AI_MLP_HIDDEN2 + AI_MLP_OUTPUTS));

      ArrayResize(m_w1, AI_FEATURE_DIM);
      for(int i = 0; i < AI_FEATURE_DIM; i++)
         for(int j = 0; j < AI_MLP_HIDDEN1; j++)
            m_w1[i][j] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * scale1;
      for(int j = 0; j < AI_MLP_HIDDEN1; j++) m_b1[j] = 0.0;
      for(int i = 0; i < AI_MLP_HIDDEN1; i++)
         for(int j = 0; j < AI_MLP_HIDDEN2; j++)
            m_w2[i][j] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * scale2;
      for(int j = 0; j < AI_MLP_HIDDEN2; j++) m_b2[j] = 0.0;
      for(int i = 0; i < AI_MLP_HIDDEN2; i++)
         m_w3[i] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * scale3;
      m_b3 = 0.0;
      m_decision_threshold = 0.5;
      m_external_weights_loaded = false;
      m_weights_file = "";
     }

   bool ReadFloatChecked(const int handle, double &out_value)
     {
      if(FileIsEnding(handle)) return false;
      out_value = (double)FileReadFloat(handle);
      return true;
     }

public:
   CAIInference(int seed = 42)
      : IManager(), m_loaded(false), m_model_id("mlp_v2_34dim"), m_n_layers(3),
        m_rand_seed(seed), m_external_weights_loaded(false), m_weights_file(""), m_b3(0.0),
        m_decision_threshold(0.5)
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
      PrintFormat("CAIInference[seed=%d]: MLP %d->%d->%d->%d ready (external_weights=%s)",
                  m_rand_seed, AI_FEATURE_DIM, AI_MLP_HIDDEN1, AI_MLP_HIDDEN2, AI_MLP_OUTPUTS,
                  m_external_weights_loaded ? "true" : "false");
      return true;
     }

   virtual void Deinit()
     {
      m_loaded = false;
      IManager::Deinit();
     }

   virtual void DeclareEvents() override {}
   virtual void OnEvent(const PASREvent &ev) override {}

   bool LoadWeights(const string filename)
     {
      if(StringLen(filename) == 0) return false;
      int handle = FileOpen(filename, FILE_READ | FILE_BIN);
      if(handle == INVALID_HANDLE)
         return false;

      double din = 0.0, dh1 = 0.0, dh2 = 0.0, dout = 0.0;
      bool ok = ReadFloatChecked(handle, din) && ReadFloatChecked(handle, dh1) &&
                ReadFloatChecked(handle, dh2) && ReadFloatChecked(handle, dout);
      if(!ok)
        {
         FileClose(handle);
         PrintFormat("CAIInference: invalid or truncated MLP weight header in '%s'", filename);
         return false;
        }

      int in_dim = (int)MathRound(din);
      int h1_dim = (int)MathRound(dh1);
      int h2_dim = (int)MathRound(dh2);
      int out_dim = (int)MathRound(dout);
      if(in_dim != AI_FEATURE_DIM || h1_dim != AI_MLP_HIDDEN1 ||
         h2_dim != AI_MLP_HIDDEN2 || out_dim != AI_MLP_OUTPUTS)
        {
         FileClose(handle);
         PrintFormat("CAIInference: MLP weight shape mismatch in '%s' got %d->%d->%d->%d expected %d->%d->%d->%d",
                     filename, in_dim, h1_dim, h2_dim, out_dim,
                     AI_FEATURE_DIM, AI_MLP_HIDDEN1, AI_MLP_HIDDEN2, AI_MLP_OUTPUTS);
         return false;
        }

      ArrayResize(m_w1, AI_FEATURE_DIM);
      for(int i = 0; i < AI_FEATURE_DIM && ok; i++)
         for(int j = 0; j < AI_MLP_HIDDEN1 && ok; j++)
            ok = ReadFloatChecked(handle, m_w1[i][j]);
      for(int j = 0; j < AI_MLP_HIDDEN1 && ok; j++)
         ok = ReadFloatChecked(handle, m_b1[j]);
      for(int i = 0; i < AI_MLP_HIDDEN1 && ok; i++)
         for(int j = 0; j < AI_MLP_HIDDEN2 && ok; j++)
            ok = ReadFloatChecked(handle, m_w2[i][j]);
      for(int j = 0; j < AI_MLP_HIDDEN2 && ok; j++)
         ok = ReadFloatChecked(handle, m_b2[j]);
      for(int i = 0; i < AI_MLP_HIDDEN2 && ok; i++)
         ok = ReadFloatChecked(handle, m_w3[i]);
      if(ok) ok = ReadFloatChecked(handle, m_b3);

      m_decision_threshold = 0.5;
      double thresh_val = 0.0;
      if(ok && ReadFloatChecked(handle, thresh_val))
        {
         m_decision_threshold = MathMax(0.1, MathMin(0.9, thresh_val));
         PrintFormat("CAIInference: decision threshold=%.3f from '%s'", m_decision_threshold, filename);
        }

      FileClose(handle);
      if(!ok)
        {
         PrintFormat("CAIInference: truncated MLP weights in '%s'; keeping current weights", filename);
         return false;
        }

      m_external_weights_loaded = true;
      m_weights_file = filename;
      PrintFormat("CAIInference: loaded MLP weights from '%s'", filename);
      return true;
     }

   bool Forward(const double &features[], double &out_score)
     {
      out_score = 0.0;
      if(!m_loaded) return false;
      if(ArraySize(features) < AI_FEATURE_DIM) return false;

      double h1[AI_MLP_HIDDEN1];
      for(int j = 0; j < AI_MLP_HIDDEN1; j++)
        {
         double s = m_b1[j];
         for(int i = 0; i < AI_FEATURE_DIM; i++) s += features[i] * m_w1[i][j];
         h1[j] = ReLU(s);
        }

      double h2[AI_MLP_HIDDEN2];
      for(int j = 0; j < AI_MLP_HIDDEN2; j++)
        {
         double s = m_b2[j];
         for(int i = 0; i < AI_MLP_HIDDEN1; i++) s += h1[i] * m_w2[i][j];
         h2[j] = ReLU(s);
        }

      double s = m_b3;
      for(int i = 0; i < AI_MLP_HIDDEN2; i++) s += h2[i] * m_w3[i];
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

      double h1[AI_MLP_HIDDEN1], h2[AI_MLP_HIDDEN2];
      for(int j = 0; j < AI_MLP_HIDDEN1; j++)
        {
         double s = m_b1[j];
         for(int i = 0; i < AI_FEATURE_DIM; i++) s += features[i] * m_w1[i][j];
         h1[j] = ReLU(s);
        }
      for(int j = 0; j < AI_MLP_HIDDEN2; j++)
        {
         double s = m_b2[j];
         for(int i = 0; i < AI_MLP_HIDDEN1; i++) s += h1[i] * m_w2[i][j];
         h2[j] = ReLU(s);
        }

      double s3 = m_b3;
      for(int i = 0; i < AI_MLP_HIDDEN2; i++) s3 += h2[i] * m_w3[i];
      double pred = Tanh(s3);
      double delta3 = 2.0 * (pred - label) * (1.0 - pred * pred);

      for(int i = 0; i < AI_MLP_HIDDEN2; i++) m_w3[i] -= lr * delta3 * h2[i];
      m_b3 -= lr * delta3;

      double delta2[AI_MLP_HIDDEN2];
      for(int j = 0; j < AI_MLP_HIDDEN2; j++)
         delta2[j] = (h2[j] > 0.0) ? delta3 * m_w3[j] : 0.0;
      for(int j = 0; j < AI_MLP_HIDDEN2; j++)
        {
         for(int i = 0; i < AI_MLP_HIDDEN1; i++) m_w2[i][j] -= lr * delta2[j] * h1[i];
         m_b2[j] -= lr * delta2[j];
        }

      double delta1[AI_MLP_HIDDEN1];
      for(int k = 0; k < AI_MLP_HIDDEN1; k++)
        {
         if(h1[k] <= 0.0) { delta1[k] = 0.0; continue; }
         double g = 0.0;
         for(int j = 0; j < AI_MLP_HIDDEN2; j++) g += delta2[j] * m_w2[k][j];
         delta1[k] = g;
        }
      for(int k = 0; k < AI_MLP_HIDDEN1; k++)
        {
         for(int i = 0; i < AI_FEATURE_DIM; i++) m_w1[i][k] -= lr * delta1[k] * features[i];
         m_b1[k] -= lr * delta1[k];
        }

      return true;
     }

   bool   IsLoaded() const { return m_loaded; }
   bool   HasExternalWeights() const { return m_external_weights_loaded; }
   double GetDecisionThreshold() const { return m_decision_threshold; }
   string GetWeightsFile() const { return m_weights_file; }
   string GetModelId() const { return m_model_id; }
   int    GetSeed() const { return m_rand_seed; }
   void   SetModelId(string id) { m_model_id = id; }
  };

#endif // __AI_INFERENCE_MQH__
