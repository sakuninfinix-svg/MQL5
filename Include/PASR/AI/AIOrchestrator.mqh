//+------------------------------------------------------------------+
//|                                              AIOrchestrator.mqh  |
//|                                       Copyright 2026, Agsicentre |
//|            AI/ML Model Orchestration & Inference Manager         |
//+------------------------------------------------------------------+
//| PURPOSE: Coordinates AI model loading, feature preparation,      |
//|          inference execution, and signal integration.            |
//|          Supports multiple models with fallback logic.           |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "2.00"
#property strict

#ifndef __AI_ORCHESTRATOR_MQH__
#define __AI_ORCHESTRATOR_MQH__

#include "IManager.mqh"
#include "10.DataManager.mqh"
#include "AI/AITypes.mqh"
#include "AI/AIFeatureBuilder.mqh"
#include "AI/AIInference.mqh"
#include "AI/AITrainer.mqh"

//+------------------------------------------------------------------+
//| AI Model Status                                                  |
//+------------------------------------------------------------------+
enum ENUM_MODEL_STATUS
{
   MODEL_STATUS_NOT_LOADED,     // Model not loaded
   MODEL_STATUS_LOADING,        // Model is loading
   MODEL_STATUS_READY,          // Model ready for inference
   MODEL_STATUS_ERROR,          // Model failed to load
   MODEL_STATUS_DEPRECATED      // Model replaced by newer version
};

//+------------------------------------------------------------------+
//| Model Configuration                                              |
//+------------------------------------------------------------------+
struct ModelConfig
{
   string   name;                // Model identifier
   string   path;                // File path to model
   ENUM_AI_MODEL_TYPE type;      // Model type (LR, GBM, NN, etc.)
   int      version;             // Model version
   bool     isActive;            // Is this model currently active
   double   confidenceThreshold; // Minimum confidence to use signal
   int      maxFeatures;         // Maximum features expected
   datetime lastTrained;         // Last training timestamp
   datetime lastUsed;            // Last inference timestamp
   
   ModelConfig() : name(""), path(""), type(AI_MODEL_LOGISTIC_REGRESSION),
                   version(1), isActive(false), confidenceThreshold(0.6),
                   maxFeatures(50), lastTrained(0), lastUsed(0) {}
};

//+------------------------------------------------------------------+
//| Inference Result                                                 |
//+------------------------------------------------------------------+
struct InferenceResult
{
   bool     isValid;
   datetime timestamp;
   string   modelName;
   double   prediction;          // Raw prediction (0-1 for classification)
   double   confidence;          // Confidence score
   int      predictedClass;      // 0=SELL, 1=NEUTRAL, 2=BUY
   ENUM_ORDER_TYPE signal;       // Converted trading signal
   double   featureImportance[]; // Feature importance scores
   string   reasoning;           // Human-readable explanation
   
   InferenceResult() : isValid(false), timestamp(0), modelName(""),
                       prediction(0.5), confidence(0.0), predictedClass(1),
                       signal(ORDER_TYPE_BUY) {}
   
   string GetSignalString() const
   {
      switch(signal)
      {
         case ORDER_TYPE_BUY:  return "BUY";
         case ORDER_TYPE_SELL: return "SELL";
         default: return "NEUTRAL";
      }
   }
};

//+------------------------------------------------------------------+
//| Ensemble Prediction                                              |
//+------------------------------------------------------------------+
struct EnsemblePrediction
{
   double   avgPrediction;
   double   avgConfidence;
   int      voteCount;
   int      buyVotes;
   int      sellVotes;
   int      neutralVotes;
   ENUM_ORDER_TYPE consensusSignal;
   string   contributingModels[];
   
   EnsemblePrediction() : avgPrediction(0.5), avgConfidence(0.0),
                          voteCount(0), buyVotes(0), sellVotes(0),
                          neutralVotes(0), consensusSignal(ORDER_TYPE_BUY) {}
};

//+------------------------------------------------------------------+
//| AI Orchestrator Statistics                                       |
//+------------------------------------------------------------------+
struct AIStats
{
   int    totalInferences;
   int    successfulInferences;
   int    failedInferences;
   int    modelSwitches;
   double avgConfidence;
   double avgLatencyMs;
   datetime lastInferenceTime;
   int    predictionsByModel[]; // Per-model inference count
   
   AIStats() : totalInferences(0), successfulInferences(0),
               failedInferences(0), modelSwitches(0),
               avgConfidence(0.0), avgLatencyMs(0.0), lastInferenceTime(0) {}
};

//+------------------------------------------------------------------+
//| AIOrchestrator Class                                             |
//+------------------------------------------------------------------+
class AIOrchestrator : public IManager
{
private:
   ModelConfig      m_models[];
   int              m_activeModelIndex;
   AIInference      m_inferenceEngine;
   AIFeatureBuilder m_featureBuilder;
   AITrainer        m_trainer;
   AIStats          m_stats;
   
   // Cache for performance
   datetime         m_lastFeatureBuildTime;
   double           m_cachedFeatures[];
   bool             m_featuresValid;
   
   // Throttling
   datetime         m_lastInferenceTime;
   int              m_inferenceIntervalSec;
   
   // Fallback logic
   int              m_consecutiveFailures;
   int              m_maxConsecutiveFailures;
   
private:
   //--- Load model from file
   bool LoadModel(int modelIndex)
   {
      if(modelIndex < 0 || modelIndex >= ArraySize(m_models))
         return false;
      
      ModelConfig &model = m_models[modelIndex];
      
      if(CheckPointer(m_inferenceEngine.LoadModel(model.path, model.type)) == POINTER_INVALID)
      {
         Log("❌ Failed to load model: " + model.name + " from " + model.path);
         model.status = MODEL_STATUS_ERROR;
         return false;
      }
      
      model.status = MODEL_STATUS_READY;
      Log("✅ Model loaded: " + model.name + " (v" + IntegerToString(model.version) + ")");
      
      return true;
   }
   
   //--- Build feature vector from current market data
   bool BuildFeatureVector(double &features[])
   {
      datetime now = TimeCurrent();
      
      // Use cached features if still valid (prevent redundant calculations)
      if(m_featuresValid && (now - m_lastFeatureBuildTime) < 5)
      {
         ArrayCopy(features, m_cachedFeatures);
         return true;
      }
      
      // Build fresh features
      int featureCount = m_featureBuilder.BuildFeatures(m_symbol, _Period, features);
      
      if(featureCount <= 0)
      {
         Log("⚠️ Feature building returned no features");
         return false;
      }
      
      // Cache features
      ArrayCopy(m_cachedFeatures, features);
      m_lastFeatureBuildTime = now;
      m_featuresValid = true;
      
      return true;
   }
   
   //--- Run inference with active model
   InferenceResult RunInference(const double &features[])
   {
      InferenceResult result;
      result.timestamp = TimeCurrent();
      
      if(m_activeModelIndex < 0 || m_activeModelIndex >= ArraySize(m_models))
      {
         result.isValid = false;
         result.reasoning = "No active model selected";
         return result;
      }
      
      ModelConfig &model = m_models[m_activeModelIndex];
      
      // Check model status
      if(model.status != MODEL_STATUS_READY)
      {
         result.isValid = false;
         result.reasoning = "Model not ready: " + EnumToString(model.status);
         return result;
      }
      
      // Run inference
      ulong startTime = GetMicrosecondCount();
      
      double prediction = m_inferenceEngine.Predict(features, ArraySize(features));
      double confidence = m_inferenceEngine.GetConfidence();
      
      ulong elapsed = GetMicrosecondCount() - startTime;
      double latencyMs = (double)elapsed / 1000.0;
      
      // Convert prediction to signal
      ENUM_ORDER_TYPE signal = ORDER_TYPE_BUY;
      int predictedClass = 1; // NEUTRAL
      
      if(prediction > 0.6)
      {
         signal = ORDER_TYPE_BUY;
         predictedClass = 2;
      }
      else if(prediction < 0.4)
      {
         signal = ORDER_TYPE_SELL;
         predictedClass = 0;
      }
      
      // Apply confidence threshold
      if(confidence < model.confidenceThreshold)
      {
         result.isValid = false;
         result.reasoning = "Confidence below threshold: " + DoubleToString(confidence, 3);
         return result;
      }
      
      // Populate result
      result.isValid = true;
      result.modelName = model.name;
      result.prediction = prediction;
      result.confidence = confidence;
      result.predictedClass = predictedClass;
      result.signal = signal;
      result.reasoning = StringFormat("Model %s predicts %s with %.1f%% confidence",
                                      model.name, result.GetSignalString(), confidence * 100);
      
      // Update stats
      m_stats.totalInferences++;
      m_stats.successfulInferences++;
      m_stats.avgLatencyMs = (m_stats.avgLatencyMs * (m_stats.totalInferences - 1) + 
                              latencyMs) / m_stats.totalInferences;
      m_stats.lastInferenceTime = now;
      
      model.lastUsed = now;
      
      return result;
   }
   
   //--- Run ensemble inference across multiple models
   EnsemblePrediction RunEnsembleInference(const double &features[])
   {
      EnsemblePrediction ensemble;
      
      int activeCount = 0;
      for(int i = 0; i < ArraySize(m_models); i++)
      {
         if(!m_models[i].isActive || m_models[i].status != MODEL_STATUS_READY)
            continue;
         
         // Temporarily set as active model
         int prevActive = m_activeModelIndex;
         m_activeModelIndex = i;
         
         InferenceResult result = RunInference(features);
         
         m_activeModelIndex = prevActive;
         
         if(result.isValid)
         {
            activeCount++;
            ensemble.voteCount++;
            ensemble.avgPrediction += result.prediction;
            ensemble.avgConfidence += result.confidence;
            
            if(result.signal == ORDER_TYPE_BUY)
               ensemble.buyVotes++;
            else if(result.signal == ORDER_TYPE_SELL)
               ensemble.sellVotes++;
            else
               ensemble.neutralVotes++;
            
            // Track contributing models
            int idx = ArraySize(ensemble.contributingModels);
            ArrayResize(ensemble.contributingModels, idx + 1);
            ensemble.contributingModels[idx] = result.modelName;
         }
      }
      
      if(activeCount > 0)
      {
         ensemble.avgPrediction /= activeCount;
         ensemble.avgConfidence /= activeCount;
         
         // Determine consensus
         if(ensemble.buyVotes > ensemble.sellVotes && ensemble.buyVotes > ensemble.neutralVotes)
            ensemble.consensusSignal = ORDER_TYPE_BUY;
         else if(ensemble.sellVotes > ensemble.buyVotes && ensemble.sellVotes > ensemble.neutralVotes)
            ensemble.consensusSignal = ORDER_TYPE_SELL;
         else
            ensemble.consensusSignal = ORDER_TYPE_BUY; // Default to neutral/buy
      }
      
      return ensemble;
   }
   
   //--- Switch to fallback model on failure
   void SwitchToFallbackModel()
   {
      m_consecutiveFailures++;
      
      if(m_consecutiveFailures >= m_maxConsecutiveFailures)
      {
         Log("⚠️ Multiple inference failures, checking for fallback models...");
         
         // Find next available model
         for(int i = 0; i < ArraySize(m_models); i++)
         {
            if(i != m_activeModelIndex && m_models[i].status == MODEL_STATUS_READY)
            {
               Log("🔄 Switching to fallback model: " + m_models[i].name);
               m_activeModelIndex = i;
               m_stats.modelSwitches++;
               m_consecutiveFailures = 0;
               return;
            }
         }
         
         Log("❌ No fallback models available");
      }
   }
   
public:
   AIOrchestrator() : m_activeModelIndex(-1), m_inferenceIntervalSec(10),
                      m_consecutiveFailures(0), m_maxConsecutiveFailures(3),
                      m_lastInferenceTime(0), m_featuresValid(false)
   {
      ArrayResize(m_cachedFeatures, 100);
   }
   
   virtual ~AIOrchestrator()
   {
      ArrayFree(m_models);
      ArrayFree(m_cachedFeatures);
   }
   
   virtual bool Init() override
   {
      if(!IManager::Init()) return false;
      
      // Initialize sub-components
      if(!m_featureBuilder.Init())
      {
         Log("⚠️ FeatureBuilder initialization had issues");
      }
      
      if(!m_inferenceEngine.Init())
      {
         Log("⚠️ InferenceEngine initialization had issues");
      }
      
      // Register default models (in production, these would be configured via input params)
      RegisterModel("LR_Default", "models/logistic_regression_v1.bin", 
                   AI_MODEL_LOGISTIC_REGRESSION, 1, true);
      
      Log("✅ AIOrchestrator initialized with " + IntegerToString(ArraySize(m_models)) + " model(s)");
      return true;
   }
   
   virtual void DeclareEvents() override
   {
      AddEvent(EVENT_ID_SIGNAL_GENERATED);
      AddEvent(EVENT_ID_NEW_BAR);
   }
   
   //--- Register a new model
   int RegisterModel(const string name, const string path, 
                    ENUM_AI_MODEL_TYPE type, int version, bool activate = false)
   {
      int idx = ArraySize(m_models);
      ArrayResize(m_models, idx + 1);
      
      m_models[idx].name = name;
      m_models[idx].path = path;
      m_models[idx].type = type;
      m_models[idx].version = version;
      m_models[idx].isActive = activate;
      m_models[idx].status = MODEL_STATUS_NOT_LOADED;
      
      if(activate)
      {
         m_activeModelIndex = idx;
         LoadModel(idx);
      }
      
      return idx;
   }
   
   //--- Activate a specific model
   bool ActivateModel(int modelIndex)
   {
      if(modelIndex < 0 || modelIndex >= ArraySize(m_models))
         return false;
      
      if(m_models[modelIndex].status != MODEL_STATUS_READY)
      {
         if(!LoadModel(modelIndex))
            return false;
      }
      
      m_activeModelIndex = modelIndex;
      m_models[modelIndex].isActive = true;
      
      Log("🎯 Activated model: " + m_models[modelIndex].name);
      return true;
   }
   
   //--- Get prediction from AI model
   InferenceResult GetPrediction()
   {
      InferenceResult emptyResult;
      
      // Check throttle
      datetime now = TimeCurrent();
      if(now - m_lastInferenceTime < m_inferenceIntervalSec)
      {
         emptyResult.reasoning = "Inference throttled - too soon";
         return emptyResult;
      }
      
      // Build features
      double features[];
      if(!BuildFeatureVector(features))
      {
         emptyResult.reasoning = "Failed to build feature vector";
         m_consecutiveFailures++;
         return emptyResult;
      }
      
      // Run inference
      InferenceResult result = RunInference(features);
      
      if(!result.isValid)
      {
         m_consecutiveFailures++;
         SwitchToFallbackModel();
      }
      else
      {
         m_consecutiveFailures = 0;
         m_lastInferenceTime = now;
      }
      
      return result;
   }
   
   //--- Get ensemble prediction
   EnsemblePrediction GetEnsemblePrediction()
   {
      double features[];
      if(!BuildFeatureVector(features))
      {
         EnsemblePrediction empty;
         return empty;
      }
      
      return RunEnsembleInference(features);
   }
   
   //--- Integrate AI signal with trading system
   bool TryGenerateAISignal()
   {
      InferenceResult result = GetPrediction();
      
      if(!result.isValid)
      {
         if(m_debugMode)
            Log("🤖 AI signal skipped: " + result.reasoning);
         return false;
      }
      
      Log("🤖 AI Signal: " + result.GetSignalString() + 
          " | Confidence: " + DoubleToString(result.confidence * 100, 1) + "%" +
          " | Model: " + result.modelName);
      
      // Emit signal event (integration with SignalManager would happen here)
      // For now, just log the signal
      return true;
   }
   
   //--- Event handlers
   virtual void OnNewBar(NewBarEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      
      // Invalidate cached features on new bar
      m_featuresValid = false;
      
      // Try to generate AI signal on new bar
      TryGenerateAISignal();
   }
   
   virtual void OnHeartbeat(HeartbeatEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      
      // Periodic model health check
      CheckModelHealth();
   }
   
   //--- Model health monitoring
   void CheckModelHealth()
   {
      for(int i = 0; i < ArraySize(m_models); i++)
      {
         ModelConfig &model = m_models[i];
         
         // Check if model hasn't been used in a long time
         if(model.isActive && model.lastUsed > 0)
         {
            datetime age = TimeCurrent() - model.lastUsed;
            if(age > 86400 * 7) // 7 days
            {
               Log("⚠️ Model " + model.name + " hasn't been used in " + 
                   IntegerToString(age / 86400) + " days");
            }
         }
         
         // Check if model needs retraining
         if(model.lastTrained > 0)
         {
            datetime trainAge = TimeCurrent() - model.lastTrained;
            if(trainAge > 86400 * 30) // 30 days
            {
               Log("⚠️ Model " + model.name + " may need retraining (last trained " + 
                   IntegerToString(trainAge / 86400) + " days ago)");
            }
         }
      }
   }
   
   //--- Training trigger (manual or scheduled)
   bool TriggerRetraining(int modelIndex)
   {
      if(modelIndex < 0 || modelIndex >= ArraySize(m_models))
         return false;
      
      ModelConfig &model = m_models[modelIndex];
      
      Log("📚 Starting retraining for model: " + model.name);
      
      // Collect training data
      double trainingData[];
      int labels[];
      
      int samples = m_trainer.CollectTrainingData(m_symbol, _Period, trainingData, labels);
      
      if(samples <= 0)
      {
         Log("❌ No training data collected");
         return false;
      }
      
      // Train model
      bool success = m_trainer.TrainModel(model.path, model.type, 
                                         trainingData, labels, samples);
      
      if(success)
      {
         model.lastTrained = TimeCurrent();
         model.version++;
         
         // Reload newly trained model
         m_inferenceEngine.UnloadModel();
         LoadModel(modelIndex);
         
         Log("✅ Model retrained successfully: " + model.name + " v" + 
             IntegerToString(model.version));
         return true;
      }
      
      return false;
   }
   
   //--- Accessors
   const AIStats& GetStats() const { return m_stats; }
   int GetActiveModelIndex() const { return m_activeModelIndex; }
   int GetModelCount() const { return ArraySize(m_models); }
   
   ModelConfig* GetModel(int index)
   {
      if(index < 0 || index >= ArraySize(m_models))
         return NULL;
      return &m_models[index];
   }
   
   //--- Configuration
   void SetInferenceInterval(int seconds) 
   { 
      m_inferenceIntervalSec = MathMax(1, seconds); 
   }
   
   void SetMaxConsecutiveFailures(int max)
   {
      m_maxConsecutiveFailures = MathMax(1, max);
   }
};

#endif // __AI_ORCHESTRATOR_MQH__
