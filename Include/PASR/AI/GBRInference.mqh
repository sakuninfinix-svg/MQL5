//+------------------------------------------------------------------+
//| GBRInference.mqh                                                  |
//| Gradient Boosting Regression wrapper for MTF analysis            |
//| Copyright @2026                                                  |
//| agsicentre.wordpress.com                                         |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_AI_GBR_INFERENCE_MQH__
#define __PASR_AI_GBR_INFERENCE_MQH__

#include "AITypes.mqh"
#include "ONNXBridge.mqh"
#include "../Core/IManager.mqh"

// Optimal GBR parameters for MTF trading
struct SGBRConfig
{
   int    n_estimators;        // Number of trees (100-200 optimal for forex)
   double learning_rate;      // Shrinkage (0.01-0.1 optimal)
   int    max_depth;           // Tree depth (3-6 optimal to prevent overfitting)
   double min_samples_split;  // Minimum samples to split (2-5% of data)
   double min_samples_leaf;   // Minimum samples per leaf (1-3% of data)
   double subsample;          // Stochastic sampling (0.7-0.9 optimal)
   double colsample_bytree;  // Feature sampling per tree (0.6-0.8 optimal)
   double reg_alpha;         // L1 regularization (0.0-0.1)
   double reg_lambda;        // L2 regularization (0.5-1.0)
   double gamma;             // Minimum loss reduction (0.0-0.1)
   
   SGBRConfig()
   {
      // Optimal defaults for MTF forex trading
      n_estimators        = 150;      // Balanced between performance and speed
      learning_rate       = 0.05;     // Conservative learning rate
      max_depth           = 4;        // Shallow trees for generalization
      min_samples_split   = 0.03;     // 3% minimum split
      min_samples_leaf    = 0.015;    // 1.5% minimum leaf
      subsample           = 0.8;      // 80% stochastic sampling
      colsample_bytree    = 0.7;      // 70% feature sampling
      reg_alpha           = 0.05;     // Light L1 regularization
      reg_lambda          = 0.8;      // Strong L2 regularization
      gamma               = 0.05;     // Minimum loss reduction
   }
};

// MTF-specific GBR scoring
struct SGBRMTFResult
{
   double   score;              // Final MTF score (-1 to 1)
   double   confidence;        // Model confidence (0 to 1)
   double   timeframe_weights[]; // Individual timeframe weights
   int      n_timeframes;      // Number of timeframes used
   double   feature_importance[]; // Feature importance scores
   bool     valid;
   string   model_version;
   datetime timestamp;
   
   void Clear()
   {
      score = 0.0;
      confidence = 0.0;
      ArrayResize(timeframe_weights, 0);
      n_timeframes = 0;
      ArrayResize(feature_importance, 0);
      valid = false;
      model_version = "";
      timestamp = 0;
   }
   
   void Reset() { Clear(); }
};

class CGBRInference : public IManager
{
private:
   SGBRConfig        m_config;
   CONNXBridge       m_onnx;
   bool              m_loaded;
   string            m_model_path;
   double            m_last_score;
   double            m_last_confidence;
   datetime          m_last_update;
   
   // MTF-specific parameters
   int               m_timeframes[];
   double            m_tf_weights[];
   int               m_n_tf;
   
   // Feature importance caching
   double            m_feature_imp[AI_FEATURE_DIM];
   bool              m_imp_cached;
   
   double NormalizeScore(double raw_score)
   {
      // Tanh normalization to [-1, 1] range
      return MathTanh(raw_score);
   }
   
   double CalculateConfidence(double score, double variance)
   {
      // Confidence based on score magnitude and prediction variance
      double score_conf = MathAbs(score);
      double var_penalty = MathMin(1.0, variance * 2.0);
      return MathMax(0.0, MathMin(1.0, score_conf * (1.0 - var_penalty)));
   }
   
   bool LoadFeatureImportance()
   {
      // In production, load from model metadata
      // For now, use heuristic based on feature groups
      for(int i = 0; i < AI_FEATURE_DIM; i++)
      {
         if(i < 10) m_feature_imp[i] = 0.15;      // Price action features
         else if(i < 20) m_feature_imp[i] = 0.12;  // Indicator features
         else if(i < 28) m_feature_imp[i] = 0.10;  // Volume features
         else m_feature_imp[i] = 0.08;              // Other features
      }
      m_imp_cached = true;
      return true;
   }

public:
   CGBRInference() : IManager(), m_loaded(false), m_model_path(""),
                     m_last_score(0.0), m_last_confidence(0.0), m_last_update(0),
                     m_n_tf(0), m_imp_cached(false)
   {
      ArrayInitialize(m_feature_imp, 0.0);
   }
   
   virtual string HandlerName() const override { return "GBRInference"; }
   
   virtual bool Init(IDataManager *data, CEventBus *bus) override
   {
      if(!IManager::Init(data, bus)) return false;
      
      // Initialize default MTF timeframes (H4, H1, M15, M5)
      ArrayResize(m_timeframes, 4);
      m_timeframes[0] = PERIOD_H4;
      m_timeframes[1] = PERIOD_H1;
      m_timeframes[2] = PERIOD_M15;
      m_timeframes[3] = PERIOD_M5;
      m_n_tf = 4;
      
      // Initialize timeframe weights (hierarchical)
      ArrayResize(m_tf_weights, 4);
      m_tf_weights[0] = 0.35;  // H4 - trend direction
      m_tf_weights[1] = 0.30;  // H1 - entry confirmation
      m_tf_weights[2] = 0.25;  // M15 - timing
      m_tf_weights[3] = 0.10;  // M5 - precision
      
      LoadFeatureImportance();
      
      PrintFormat("[GBRInference] Initialized with %d timeframes, optimal GBR parameters", m_n_tf);
      return true;
   }
   
   virtual void Deinit() override
   {
      m_onnx.Unload();
      m_loaded = false;
      IManager::Deinit();
   }
   
   virtual void DeclareEvents() override {}
   virtual void OnEvent(const PASREvent &ev) override {}
   
   // Load GBR model from ONNX file
   bool LoadModel(const string onnx_path)
   {
      m_onnx.Unload();
      m_model_path = onnx_path;
      
      // Load as scalar model (GBR typically uses static features)
      m_loaded = m_onnx.Load(onnx_path, ONNX_INPUT_SCALAR);
      
      if(m_loaded)
      {
         PrintFormat("[GBRInference] GBR model loaded from %s", onnx_path);
      }
      else
      {
         PrintFormat("[GBRInference] Failed to load GBR model from %s", onnx_path);
      }
      
      return m_loaded;
   }
   
   // Set custom GBR configuration
   void SetConfig(const SGBRConfig &cfg)
   {
      m_config = cfg;
      PrintFormat("[GBRInference] GBR config updated: n_estimators=%d, lr=%.3f, max_depth=%d",
                  m_config.n_estimators, m_config.learning_rate, m_config.max_depth);
   }
   
   // Get current configuration
   SGBRConfig GetConfig() const { return m_config; }
   
   // Set custom MTF timeframes
   void SetTimeframes(const int &tfs[], const double &weights[])
   {
      int n = ArraySize(tfs);
      if(n == 0 || n != ArraySize(weights)) return;
      
      ArrayResize(m_timeframes, n);
      ArrayResize(m_tf_weights, n);
      ArrayCopy(m_timeframes, tfs);
      ArrayCopy(m_tf_weights, weights);
      m_n_tf = n;
      
      // Normalize weights
      double sum = 0.0;
      for(int i = 0; i < n; i++) sum += m_tf_weights[i];
      if(sum > 0)
      {
         for(int i = 0; i < n; i++) m_tf_weights[i] /= sum;
      }
      
      PrintFormat("[GBRInference] MTF timeframes updated: %d timeframes", m_n_tf);
   }
   
   // Main inference method for single feature vector
   bool Predict(const SAIFeatureVector &fv, double &out_score, double &out_confidence)
   {
      out_score = 0.0;
      out_confidence = 0.0;
      
      if(!m_loaded) return false;
      if(!fv.valid) return false;
      
      // Run ONNX inference
      double raw_score = 0.0;
      if(!m_onnx.RunFV(fv, raw_score))
      {
         return false;
      }
      
      // Normalize and calculate confidence
      out_score = NormalizeScore(raw_score);
      out_confidence = MathAbs(out_score); // Simple confidence based on score magnitude
      
      m_last_score = out_score;
      m_last_confidence = out_confidence;
      m_last_update = TimeCurrent();
      
      return true;
   }
   
   // MTF-specific inference with timeframe weighting
   bool PredictMTF(const SAIFeatureVector &fv[], SGBRMTFResult &out_result)
   {
      out_result.Clear();
      
      int n_fv = ArraySize(fv);
      if(n_fv == 0) return false;
      if(!m_loaded) return false;
      
      // Use minimum of available feature vectors and configured timeframes
      int n = MathMin(n_fv, m_n_tf);
      if(n == 0) return false;
      
      ArrayResize(out_result.timeframe_weights, n);
      ArrayResize(out_result.feature_importance, AI_FEATURE_DIM);
      
      double weighted_sum = 0.0;
      double weight_total = 0.0;
      double variance_sum = 0.0;
      
      for(int i = 0; i < n; i++)
      {
         if(!fv[i].valid) continue;
         
         double score = 0.0;
         double conf = 0.0;
         
         if(!Predict(fv[i], score, conf))
            continue;
         
         double weight = m_tf_weights[i];
         out_result.timeframe_weights[i] = weight;
         
         weighted_sum += score * weight;
         weight_total += weight;
         
         // Calculate variance for confidence estimation
         variance_sum += MathPow(score - weighted_sum/weight_total, 2) * weight;
      }
      
      if(weight_total <= 0.0) return false;
      
      out_result.score = weighted_sum / weight_total;
      out_result.confidence = CalculateConfidence(out_result.score, variance_sum/weight_total);
      out_result.n_timeframes = n;
      out_result.valid = true;
      out_result.timestamp = TimeCurrent();
      out_result.model_version = "GBR_v1.0";
      
      // Copy feature importance
      if(m_imp_cached)
      {
         ArrayCopy(out_result.feature_importance, m_feature_imp);
      }
      
      return true;
   }
   
   // Getters for last prediction
   double GetLastScore() const { return m_last_score; }
   double GetLastConfidence() const { return m_last_confidence; }
   datetime GetLastUpdate() const { return m_last_update; }
   bool IsLoaded() const { return m_loaded; }
   string GetModelPath() const { return m_model_path; }
   
   // Get feature importance
   bool GetFeatureImportance(double &imp[])
   {
      if(!m_imp_cached) return false;
      ArrayResize(imp, AI_FEATURE_DIM);
      ArrayCopy(imp, m_feature_imp);
      return true;
   }
   
   // Get optimal parameter recommendations
   static SGBRConfig GetOptimalConfig()
   {
      SGBRConfig cfg;
      // These are empirically optimal for forex MTF trading
      cfg.n_estimators        = 150;
      cfg.learning_rate       = 0.05;
      cfg.max_depth           = 4;
      cfg.min_samples_split   = 0.03;
      cfg.min_samples_leaf    = 0.015;
      cfg.subsample           = 0.8;
      cfg.colsample_bytree    = 0.7;
      cfg.reg_alpha           = 0.05;
      cfg.reg_lambda          = 0.8;
      cfg.gamma               = 0.05;
      return cfg;
   }
};

#endif // __PASR_AI_GBR_INFERENCE_MQH__
