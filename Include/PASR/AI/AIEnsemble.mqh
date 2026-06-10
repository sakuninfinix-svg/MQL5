//+------------------------------------------------------------------+
//| AIEnsemble.mqh — v1.03                                          |
//| Multi-model voting ensemble with ONNX bridge integration         |
//| FIX v1.03: add IsReady()/GetModelCount()/GetModel() accessors    |
//|            fix SAISequenceTensor pointer handling                 |
//|            update Vote() calls to new MLPModel.Forward signature |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_AI_ENSEMBLE_MQH__
#define __PASR_AI_ENSEMBLE_MQH__

#include "AITypes.mqh"
#include "MLPModel.mqh"
#include "ONNXBridge.mqh"

struct SAIEnsembleConfig
  {
   int    n_models;
   double onnx_weight;
   bool   enable_onnx;
   string onnx_model_path;
   int    seq_len;
   int    feat_dim;

   SAIEnsembleConfig()
     {
      n_models        = ENSEMBLE_MODEL_COUNT;
      onnx_weight     = 0.3;
      enable_onnx     = false;
      onnx_model_path = "";
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

   void TryLoadOnnxModel()
     {
      m_onnx_loaded = false;
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
         m_weights[i] = 1.0 / (double)m_n_models;
        }

      if(cfg.enable_onnx && cfg.onnx_model_path != "")
         TryLoadOnnxModel();

      m_ready = (m_n_models > 0);
      return m_ready;
     }

   // FIX v1.03: accessors required by AIFeatureValidator and AITrainer
   bool       IsReady()        const { return m_ready; }
   bool       IsOnnxLoaded()   const { return m_onnx_loaded; }
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
   int total_voters = m_n_models + (use_onnx ? 1 : 0);
   ArrayResize(out.scores,  total_voters);
   ArrayResize(out.weights, total_voters);
   out.n_models = total_voters;

   for(int i = 0; i < m_n_models; i++)
        {
         if(CheckPointer(m_models[i]) == POINTER_INVALID) continue;

         double score = 0.5;
         // FIX v1.03: Forward now requires explicit feat_dim
         m_models[i].Forward(fv.features, AI_FEATURE_DIM, score);
         score = score * 2.0 - 1.0;

         out.scores[score_idx]  = score;
         out.weights[score_idx] = m_weights[i];
         weighted_sum += score * m_weights[i];
         weight_total += m_weights[i];
         score_idx++;
        }

      if(use_onnx)
        {
         out.scores[score_idx]  = m_last_onnx_score * 2.0 - 1.0;
         out.weights[score_idx] = m_onnx_weight;
         weighted_sum += out.scores[score_idx] * m_onnx_weight;
         weight_total += m_onnx_weight;
         score_idx++;
        }

      if(weight_total <= 0.0) return false;

      out.final_score = weighted_sum / weight_total;
      out.confidence  = MathAbs(out.final_score);

      int agree = 0;
      for(int i = 0; i < score_idx; i++)
         if((out.final_score >= 0.0 && out.scores[i] >= 0.0) ||
            (out.final_score <  0.0 && out.scores[i] <  0.0))
            agree++;
      out.agreement = (score_idx > 0) ? (double)agree / score_idx : 0.0;

      return true;
     }
  };

#endif // __PASR_AI_ENSEMBLE_MQH__
