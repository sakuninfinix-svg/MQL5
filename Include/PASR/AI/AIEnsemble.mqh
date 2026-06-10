//+------------------------------------------------------------------+
//| AIEnsemble.mqh                                                   |
//| Multi-model voting ensemble with ONNX bridge integration         |
//+------------------------------------------------------------------+
#pragma once
#include "../Core/AITypes.mqh"
#include "MLPModel.mqh"
#include "ONNXBridge.mqh"

//──────────────────────────────────────────────────────────────────
// Ensemble configuration & result types
//──────────────────────────────────────────────────────────────────
struct SAIEnsembleConfig
  {
   int    n_models;           // number of MLP models
   double onnx_weight;        // weight assigned to the ONNX voter
   bool   enable_onnx;        // whether ONNX voter is active
   string onnx_model_path;    // path to the ONNX model file
   int    seq_len;            // ONNX sequence length
   int    feat_dim;           // ONNX feature dimension

   SAIEnsembleConfig()
     {
      n_models        = ENSEMBLE_MODEL_COUNT;
      onnx_weight     = 0.3;
      enable_onnx     = false;
      onnx_model_path = "";
      seq_len         = AI_SEQUENCE_LEN;
      feat_dim        = AI_FEATURE_DIM;
     }
  };

struct SAIEnsembleVote
  {
   double scores[];
   double weights[];
   int    n_models;
   double final_score;
   double confidence;
   bool   valid;

   void Reset()
     {
      ArrayResize(scores,  0);
      ArrayResize(weights, 0);
      n_models    = 0;
      final_score = 0.0;
      confidence  = 0.0;
      valid       = false;
     }
  };

//──────────────────────────────────────────────────────────────────
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

   double ScoreFromOnnxOutputs(const double &outputs[], const int count)
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

   bool Init(const SAIEnsembleConfig &cfg)
     {
      m_ready     = false;
      m_n_models  = MathMin(cfg.n_models, ENSEMBLE_MODEL_COUNT);
      m_onnx_weight = cfg.onnx_weight;

      for(int i = 0; i < m_n_models; i++)
        {
         if(m_models[i] != NULL) { delete m_models[i]; m_models[i] = NULL; }
         m_models[i] = new CMLPModel();
         if(m_models[i] == NULL) return false;
         m_models[i].RandomInit();
         m_weights[i] = 1.0 / (double)m_n_models;
        }

      if(cfg.enable_onnx && cfg.onnx_model_path != "")
        {
         TryLoadOnnxModel();
        }

      m_ready = (m_n_models > 0);
      return m_ready;
     }

   bool Vote(SAIFeatureVector &fv, SAIEnsembleVote &out)
     {
      return Vote(fv, NULL, out);
     }

   bool Vote(SAIFeatureVector &fv, const SAISequenceTensor *seq, SAIEnsembleVote &out)
     {
      out.Reset();
      if(!m_ready || m_n_models == 0) return false;

      int total_voters = m_n_models + ((m_onnx_loaded && seq != NULL && seq->valid) ? 1 : 0);
      ArrayResize(out.scores, total_voters);
      ArrayResize(out.weights, total_voters);
      out.n_models = total_voters;

      double weighted_sum = 0.0;
      double weight_total = 0.0;
      int score_idx = 0;

      for(int i = 0; i < m_n_models; i++)
        {
         double score = 0.0;
         if(m_models[i] == NULL || !m_models[i].ForwardFV(fv, score)) score = 0.0;
         out.scores[score_idx]  = score;
         out.weights[score_idx] = m_weights[i];
         weighted_sum += score * m_weights[i];
         weight_total += m_weights[i];
         score_idx++;
        }

      m_last_onnx_score   = 0.0;
      m_last_onnx_outputs = 0;
      if(m_onnx_loaded && seq != NULL && seq->valid)
        {
         double onnx_outputs[];
         int out_count = 0;
         if(m_onnx.RunSequenceTensor(*seq, onnx_outputs, out_count))
           {
            double onnx_score = ScoreFromOnnxOutputs(onnx_outputs, out_count);
            m_last_onnx_score   = onnx_score;
            m_last_onnx_outputs = out_count;
            out.scores[score_idx]  = onnx_score;
            out.weights[score_idx] = m_onnx_weight;
            weighted_sum += onnx_score * m_onnx_weight;
            weight_total += m_onnx_weight;
            score_idx++;
           }
        }

      out.final_score = (weight_total > 0.0) ? weighted_sum / weight_total : 0.0;
      out.confidence  = MathMin(1.0, weight_total / (double)total_voters);
      out.valid       = true;
      return true;
     }

   void UpdateWeights(const double &new_weights[], const int count)
     {
      int n = MathMin(count, m_n_models);
      for(int i = 0; i < n; i++)
         m_weights[i] = new_weights[i];
     }

   CMLPModel* GetModel(int idx)
     {
      if(idx < 0 || idx >= m_n_models) return NULL;
      return m_models[idx];
     }

   int   ModelCount()      const { return m_n_models; }
   bool  IsReady()         const { return m_ready; }
   bool  IsOnnxLoaded()    const { return m_onnx_loaded; }
   double LastOnnxScore()  const { return m_last_onnx_score; }
  };
