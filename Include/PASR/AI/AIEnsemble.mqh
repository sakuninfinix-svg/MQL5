//+------------------------------------------------------------------+
//| AI/AIEnsemble.mqh — v1.11                                        |
//| MLP ensemble with optional external weights and ONNX fallback     |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_ENSEMBLE_MQH__
#define __AI_ENSEMBLE_MQH__

#include "AITypes.mqh"
#include "AIInference.mqh"
#include "ONNXBridge.mqh"

#define AI_ENSEMBLE_MAX_MODELS 4
#define AI_ENSEMBLE_ONNX_WEIGHT 1.5
#define AI_ENSEMBLE_MLP_WEIGHT_PREFIX "PASR_mlp_m"
#define AI_ENSEMBLE_MLP_WEIGHT_SUFFIX ".bin"

class CAIEnsemble : public IManager
  {
private:
   CAIInference *m_models[AI_ENSEMBLE_MAX_MODELS];
   double        m_weights[AI_ENSEMBLE_MAX_MODELS];
   int           m_n_models;
   bool          m_ready;

   CONNXBridge   m_onnx;
   bool          m_onnx_enabled;
   bool          m_onnx_loaded;
   double        m_onnx_weight;
   string        m_onnx_path;
   double        m_last_onnx_score;
   int           m_last_onnx_outputs;

   int SeedAt(int idx) const
     {
      if(idx == 0) return 42;
      if(idx == 1) return 137;
      if(idx == 2) return 271;
      return 919;
     }

   bool IsSafeModelPath(const string path) const
     {
      if(StringLen(path) == 0) return false;
      if(StringFind(path, "../") == 0) return false;
      if(StringFind(path, "..\\") == 0) return false;
      return true;
     }

   string DefaultMlpWeightsFile(const int model_idx) const
     {
      return StringFormat("%s%d%s", AI_ENSEMBLE_MLP_WEIGHT_PREFIX, model_idx, AI_ENSEMBLE_MLP_WEIGHT_SUFFIX);
     }

   void TryLoadMlpWeights()
     {
      for(int i = 0; i < m_n_models; i++)
        {
         if(m_models[i] == NULL) continue;
         string file_name = DefaultMlpWeightsFile(i);
         if(!m_models[i].LoadWeights(file_name))
            PrintFormat("CAIEnsemble: no external MLP weights loaded for model %d (%s); using initialized weights", i, file_name);
        }
     }

   double ComputeAgreement(double &scores[])
     {
      int n = ArraySize(scores);
      if(n <= 1) return 1.0;
      int pos = 0;
      int neg = 0;
      for(int i = 0; i < n; i++)
        {
         if(scores[i] > 0.0) pos++;
         else if(scores[i] < 0.0) neg++;
        }
      return (double)MathMax(pos, neg) / (double)n;
     }

   double ScoreFromOnnxOutputs(const double &outputs[], const int out_count) const
     {
      if(out_count <= 0) return 0.0;
      if(out_count >= 2)
        {
         double direction = MathMax(-1.0, MathMin(1.0, outputs[0]));
         double confidence = MathMax(0.0, MathMin(1.0, outputs[1]));
         return direction * confidence;
        }
      return MathMax(-1.0, MathMin(1.0, outputs[0]));
     }

   void ReleaseModels()
     {
      for(int i = 0; i < m_n_models; i++)
        {
         if(m_models[i] != NULL)
           {
            m_models[i].Deinit();
            delete m_models[i];
            m_models[i] = NULL;
           }
        }
      m_n_models = 0;
      m_ready = false;
      m_onnx.Unload();
      m_onnx_loaded = false;
      m_last_onnx_score = 0.0;
      m_last_onnx_outputs = 0;
     }

   void ApplyOnnxConfig()
     {
      m_onnx_enabled = false;
      m_onnx_path = "";
      if(m_data == NULL) return;

      StrategyConfig cfg;
      m_data.GetConfigCache(cfg);
      if(!cfg.AI.EnableAI || !cfg.AI.EnableOnnx)
         return;
      if(!IsSafeModelPath(cfg.AI.OnnxModelFileName))
         return;

      m_onnx_enabled = true;
      m_onnx_path = cfg.AI.OnnxModelFileName;
     }

   void TryLoadOnnxModel()
     {
      m_onnx_loaded = false;
      m_last_onnx_score = 0.0;
      m_last_onnx_outputs = 0;
      if(!m_onnx_enabled || !IsSafeModelPath(m_onnx_path))
         return;

      if(m_onnx.LoadSequence(m_onnx_path, AI_SEQ_LEN, AI_SEQ_FEATURE_DIM, 2))
         m_onnx_loaded = true;
      else
         PrintFormat("[CAIEnsemble] ONNX load failed for '%s'; MLP fallback remains active", m_onnx_path);
     }

public:
   CAIEnsemble()
      : IManager(), m_n_models(0), m_ready(false),
        m_onnx_enabled(false), m_onnx_loaded(false),
        m_onnx_weight(AI_ENSEMBLE_ONNX_WEIGHT), m_onnx_path(""),
        m_last_onnx_score(0.0), m_last_onnx_outputs(0)
     {
      ArrayInitialize(m_weights, 1.0);
      for(int i = 0; i < AI_ENSEMBLE_MAX_MODELS; i++) m_models[i] = NULL;
     }

   ~CAIEnsemble() { ReleaseModels(); }

   virtual string HandlerName() const override { return "AIEnsemble"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      ReleaseModels();
      ApplyOnnxConfig();

      for(int i = 0; i < 2; i++)
        {
         int seed = SeedAt(i);
         m_models[m_n_models] = new CAIInference(seed);
         if(m_models[m_n_models] == NULL) return false;
         m_models[m_n_models].SetModelId(StringFormat("mlp_v2_m%d_s%d", i, seed));
         if(!m_models[m_n_models].Init(data, bus))
           {
            ReleaseModels();
            return false;
           }
         m_weights[m_n_models] = 1.0;
         m_n_models++;
        }

      TryLoadMlpWeights();
      NormalizeWeights();
      TryLoadOnnxModel();
      m_ready = true;
      PrintFormat("CAIEnsemble: %d MLP models ready, onnx=%s loaded=%s",
                  m_n_models,
                  m_onnx_enabled ? m_onnx_path : "disabled",
                  m_onnx_loaded ? "true" : "false");
      return true;
     }

   virtual void Deinit() override
     {
      ReleaseModels();
      IManager::Deinit();
     }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_CONFIG_RELOAD);
     }

   virtual void OnEvent(const PASREvent &ev) override
     {
      if(ev.id == EVENT_ID_CONFIG_RELOAD)
        {
         ApplyOnnxConfig();
         TryLoadOnnxModel();
        }
     }

   bool Vote(SAIFeatureVector &fv, SAIEnsembleVote &out)
     {
      return Vote(fv, NULL, out);
     }

   bool Vote(SAIFeatureVector &fv, const SAISequenceTensor *seq, SAIEnsembleVote &out)
     {
      out.Reset();
      if(!m_ready || m_n_models == 0) return false;

      int total_voters = m_n_models + ((m_onnx_loaded && seq != NULL && seq.valid) ? 1 : 0);
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
         out.scores[score_idx] = score;
         out.weights[score_idx] = m_weights[i];
         weighted_sum += score * m_weights[i];
         weight_total += m_weights[i];
         score_idx++;
        }

      m_last_onnx_score = 0.0;
      m_last_onnx_outputs = 0;
      if(m_onnx_loaded && seq != NULL && seq.valid)
        {
         double onnx_outputs[];
         int out_count = 0;
         if(m_onnx.RunSequenceTensor(*seq, onnx_outputs, out_count))
           {
            double onnx_score = ScoreFromOnnxOutputs(onnx_outputs, out_count);
            m_last_onnx_score = onnx_score;
            m_last_onnx_outputs = out_count;
            out.scores[score_idx] = onnx_score;
            out.weights[score_idx] = m_onnx_weight;
            weighted_sum += onnx_score * m_onnx_weight;
            weight_total += m_onnx_weight;
            score_idx++;
           }
        }

      out.n_models = score_idx;
      ArrayResize(out.scores, score_idx);
      ArrayResize(out.weights, score_idx);
      out.final_score = (weight_total > 0.0) ? weighted_sum / weight_total : 0.0;
      out.agreement = ComputeAgreement(out.scores);
      return (score_idx > 0);
     }

   void UpdateWeight(int model_idx, double new_weight)
     {
      if(model_idx < 0 || model_idx >= m_n_models) return;
      m_weights[model_idx] = MathMax(0.1, new_weight);
      NormalizeWeights();
     }

   CAIInference *GetModel(int idx)
     {
      if(idx < 0 || idx >= m_n_models) return NULL;
      return m_models[idx];
     }

   bool LoadModelWeights(int model_idx, const string filename)
     {
      if(model_idx < 0 || model_idx >= m_n_models || m_models[model_idx] == NULL) return false;
      return m_models[model_idx].LoadWeights(filename);
     }

   void NormalizeWeights()
     {
      double total = 0.0;
      for(int i = 0; i < m_n_models; i++) total += m_weights[i];
      if(total > 0.0)
         for(int i = 0; i < m_n_models; i++) m_weights[i] /= total;
     }

   int  GetModelCount() const { return m_n_models; }
   bool IsReady() const { return m_ready; }
   bool IsOnnxLoaded() const { return m_onnx_loaded; }
   bool IsOnnxEnabled() const { return m_onnx_enabled; }
   string GetOnnxPath() const { return m_onnx_path; }
   double GetLastOnnxScore() const { return m_last_onnx_score; }
  };

#endif // __AI_ENSEMBLE_MQH__