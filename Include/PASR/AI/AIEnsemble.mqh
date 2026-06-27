//+------------------------------------------------------------------+
//| AIEnsemble.mqh — v1.00                                           |
//| Multi-model voting ensemble with ONNX bridge integration         |
//| Copyright @2026                                                  |
//| agsicentre.wordpress.com                                         |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_AI_ENSEMBLE_MQH__
#define __PASR_AI_ENSEMBLE_MQH__

#include "AITypes.mqh"
#include "MLPModel.mqh"
#include "ONNXBridge.mqh"

class IDataManager;
class CEventBus;

struct SAIEnsembleConfig
  {
   int    n_models;
   double onnx_weight;
   bool   enable_onnx;
   string onnx_model_path;
   string mlp_model_path;
   int    seq_len;
   int    feat_dim;

   SAIEnsembleConfig()
     {
      n_models        = 1;
      onnx_weight     = 0.3;
      enable_onnx     = false;
      onnx_model_path = "";
      mlp_model_path  = "";
      seq_len         = AI_SEQ_LEN;
      feat_dim        = AI_FEATURE_DIM;
     }
  };

class CAIEnsemble
  {
private:
   CMLPModel        *m_models[ENSEMBLE_MODEL_COUNT];
   double            m_weights[ENSEMBLE_MODEL_COUNT];
   int               m_n_models;
   bool              m_ready;
   CONNXBridge       m_onnx;
   bool              m_onnx_loaded;
   double            m_onnx_weight;
   double            m_last_onnx_score;
   int               m_last_onnx_outputs;

   double ScoreFromOnnxOutputs(double &outputs[], int count)
     {
      if(count <= 0) return 0.0;
      return MathMax(0.0, MathMin(1.0, outputs[0]));
     }

   void TryLoadOnnxModel(const string path)
     {
      if(path == "")
        {
         m_onnx_loaded = false;
         return;
        }
      // FIX: Pass correct parameters — ONNX_INPUT_SEQUENCE for sequence models
      m_onnx_loaded = m_onnx.Load(path, ONNX_INPUT_SEQUENCE);
      if(m_onnx_loaded)
        {
         // Query output size after successful load
         m_last_onnx_outputs = 1;  // Default; override if bridge exposes getter
         PrintFormat("[AIEnsemble] ONNX model loaded: %s (seq=%d feat=%d)",
                     path, m_onnx.GetSeqLen(), m_onnx.GetFeatDim());
        }
      else
         PrintFormat("[AIEnsemble] ONNX model load failed: %s", path);
     }

   string MLPPathForIndex(const string base_path, const int idx)
     {
      if(idx <= 0 || base_path == "")
         return base_path;

      string path = base_path;
      string from = "_m0";
      string to = StringFormat("_m%d", idx);
      if(StringFind(path, from) >= 0)
        {
         StringReplace(path, from, to);
         return path;
        }

      int dot = StringFind(path, ".bin");
      if(dot >= 0)
         return StringSubstr(path, 0, dot) + to + StringSubstr(path, dot);
      return path;
     }

public:
   CAIEnsemble() : m_n_models(0), m_ready(false), m_onnx_loaded(false),
                   m_onnx_weight(0.3), m_last_onnx_score(0.0), m_last_onnx_outputs(0)
     {
      ArrayInitialize(m_weights, 0.0);
      for(int i = 0; i < ENSEMBLE_MODEL_COUNT; i++)
         m_models[i] = NULL;
     }

  ~CAIEnsemble()
     {
      for(int i = 0; i < ENSEMBLE_MODEL_COUNT; i++)
        {
         if(m_models[i] != NULL) { delete m_models[i]; m_models[i] = NULL; }
        }
     }

   // IManager-compatible shim
   bool Init(IDataManager *data, CEventBus *bus)
     {
      SAIEnsembleConfig cfg;
      return Init(cfg);
     }
   void Deinit() {}

   bool Init(const SAIEnsembleConfig &cfg)
     {
      m_ready    = false;
      m_n_models = MathMin(cfg.n_models, ENSEMBLE_MODEL_COUNT);
      m_onnx_weight = cfg.onnx_weight;

      for(int i = 0; i < m_n_models; i++)
        {
         if(m_models[i] != NULL) { delete m_models[i]; m_models[i] = NULL; }
         m_models[i] = new CMLPModel(i + 1);
         if(m_models[i] == NULL) return false;
         m_models[i].RandomInit(i + 1);
         if(cfg.mlp_model_path != "")
           {
            string model_path = MLPPathForIndex(cfg.mlp_model_path, i);
            if(m_models[i].LoadWeights(model_path))
               PrintFormat("[AIEnsemble] MLP model loaded: %s", model_path);
            else
               PrintFormat("[AIEnsemble] MLP model load failed: %s, using random init", model_path);
           }
         m_weights[i] = 1.0 / (double)m_n_models;
        }

      if(cfg.enable_onnx && cfg.onnx_model_path != "")
         TryLoadOnnxModel(cfg.onnx_model_path);

      m_ready = (m_n_models > 0);
      return m_ready;
     }

   // FIX v1.03: accessors required by AIFeatureValidator and AITrainer
   bool       IsReady()        const { return m_ready; }
   bool       IsOnnxLoaded()   const { return m_onnx_loaded; }
   bool       IsOnnxSupported() const { return m_onnx.IsCompiledIn(); }
   int        GetModelCount()  const { return m_n_models; }
   CMLPModel* GetModel(int idx)
     {
      if(idx < 0 || idx >= m_n_models) return NULL;
      return m_models[idx];
     }

   // 2-arg overload — no sequence tensor
  bool Vote(SAIFeatureVector &fv, SAIEnsembleVote &out)
  {
   out.Reset();
   if(!m_ready || m_n_models == 0)
      return false;

   ArrayResize(out.scores, m_n_models);
   ArrayResize(out.weights, m_n_models);

   double weighted_sum = 0.0;
   double weight_total = 0.0;
   int score_idx = 0;

   for(int i = 0; i < m_n_models; i++)
     {
      if(CheckPointer(m_models[i]) == POINTER_INVALID || m_models[i] == NULL)
         continue;

      double score = 0.5;
      if(!m_models[i].Forward(fv.features, AI_FEATURE_DIM, score))
         continue;

      score = score * 2.0 - 1.0;

      out.scores[score_idx]  = score;
      out.weights[score_idx] = m_weights[i];
      weighted_sum += score * m_weights[i];
      weight_total += m_weights[i];
      score_idx++;
     }

   if(score_idx <= 0 || weight_total <= 0.0)
      return false;

   ArrayResize(out.scores, score_idx);
   ArrayResize(out.weights, score_idx);

   out.n_models = score_idx;
   out.final_score = weighted_sum / weight_total;
   out.confidence = MathAbs(out.final_score);
   out.valid = true;

   int agree = 0;
   for(int i = 0; i < score_idx; i++)
     {
      if((out.final_score >= 0.0 && out.scores[i] >= 0.0) ||
         (out.final_score < 0.0 && out.scores[i] < 0.0))
         agree++;
     }

   out.agreement = (score_idx > 0) ? (double)agree / score_idx : 0.0;
   return true;
  }
};
#endif // __PASR_AI_ENSEMBLE_MQH__
