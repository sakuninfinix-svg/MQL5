//+------------------------------------------------------------------+
//|                                          AI/AIOrchestrator.mqh   |
//|                                       Copyright 2026, Agsicentre|
//|   AI/ML Model Orchestration, Inference & Deferred Training       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#property strict

#ifndef __AI_ORCHESTRATOR_MQH__
#define __AI_ORCHESTRATOR_MQH__

#include "../Core/IManager.mqh"
#include "AITypes.mqh"
#include "AIFeatureBuilder.mqh"
#include "AIInference.mqh"
#include "AITrainer.mqh"

enum ENUM_MODEL_STATUS
  {
   MODEL_STATUS_NOT_LOADED,
   MODEL_STATUS_LOADING,
   MODEL_STATUS_READY,
   MODEL_STATUS_ERROR,
   MODEL_STATUS_DEPRECATED
  };

struct ModelConfig
  {
   string              name;
   string              path;
   ENUM_AI_MODEL_TYPE  type;
   int                 version;
   bool                isActive;
   double              confidenceThreshold;
   int                 maxFeatures;
   datetime            lastTrained;
   datetime            lastUsed;
   ENUM_MODEL_STATUS   status;

   ModelConfig()
      : name(""), path(""), type(AI_MODEL_LOGISTIC_REGRESSION),
        version(1), isActive(false), confidenceThreshold(0.6),
        maxFeatures(50), lastTrained(0), lastUsed(0),
        status(MODEL_STATUS_NOT_LOADED) {}
  };

struct InferenceResult
  {
   bool              isValid;
   datetime          timestamp;
   string            modelName;
   double            prediction;
   double            confidence;
   int               predictedClass;
   ENUM_ORDER_TYPE   signal;
   string            reasoning;

   InferenceResult()
      : isValid(false), timestamp(0), modelName(""),
        prediction(0.5), confidence(0.0), predictedClass(1),
        signal(ORDER_TYPE_BUY), reasoning("") {}

   string GetSignalString() const
     {
      switch(signal)
        {
         case ORDER_TYPE_BUY:  return "BUY";
         case ORDER_TYPE_SELL: return "SELL";
         default:              return "NEUTRAL";
        }
     }
  };

struct EnsemblePrediction
  {
   double            avgPrediction;
   double            avgConfidence;
   int               voteCount;
   int               buyVotes;
   int               sellVotes;
   int               neutralVotes;
   ENUM_ORDER_TYPE   consensusSignal;
   string            contributingModels[];

   EnsemblePrediction()
      : avgPrediction(0.5), avgConfidence(0.0),
        voteCount(0), buyVotes(0), sellVotes(0),
        neutralVotes(0), consensusSignal(ORDER_TYPE_BUY) {}
  };

struct AIStats
  {
   int      totalInferences;
   int      successfulInferences;
   int      failedInferences;
   int      modelSwitches;
   double   avgConfidence;
   double   avgLatencyMs;
   datetime lastInferenceTime;

   AIStats()
      : totalInferences(0), successfulInferences(0),
        failedInferences(0), modelSwitches(0),
        avgConfidence(0.0), avgLatencyMs(0.0), lastInferenceTime(0) {}
  };

class CAIOrchestrator : public IManager
  {
private:
   ModelConfig       m_models[];
   int               m_activeModelIndex;
   AIInference       m_inferenceEngine;
   AIFeatureBuilder  m_featureBuilder;
   AITrainer         m_trainer;
   AIStats           m_stats;

   datetime          m_lastFeatureBuildTime;
   double            m_cachedFeatures[];
   bool              m_featuresValid;

   datetime          m_lastInferenceTime;
   int               m_inferenceIntervalSec;
   double            m_lastInferenceScore;
   bool              m_lastAIVeto;
   double            m_lastDriftScore;

   bool              m_trainPending;
   int               m_trainTargetModel;

   int               m_consecutiveFailures;
   int               m_maxConsecutiveFailures;

   bool LoadModel(int modelIndex)
     {
      if(modelIndex < 0 || modelIndex >= ArraySize(m_models)) return false;
      ModelConfig &model = m_models[modelIndex];
      model.status = MODEL_STATUS_LOADING;
      bool ok = m_inferenceEngine.LoadModel(model.path, model.type);
      if(!ok)
        {
         Print("[AIOrchestrator] Failed to load model: ", model.name, " from ", model.path);
         model.status = MODEL_STATUS_ERROR;
         return false;
        }
      model.status = MODEL_STATUS_READY;
      Print("[AIOrchestrator] Model loaded: ", model.name, " v", model.version);
      return true;
     }

   bool BuildFeatureVector(double &features[])
     {
      datetime now = TimeCurrent();
      if(m_featuresValid && (now - m_lastFeatureBuildTime) < 5)
        {
         ArrayCopy(features, m_cachedFeatures);
         return true;
        }
      int count = m_featureBuilder.BuildFeatures(_Symbol, _Period, features);
      if(count <= 0)
        {
         Print("[AIOrchestrator] BuildFeatures returned 0");
         return false;
        }
      ArrayCopy(m_cachedFeatures, features);
      m_lastFeatureBuildTime = now;
      m_featuresValid        = true;
      return true;
     }

   double EstimateDriftScore(const InferenceResult &result) const
     {
      if(!result.isValid) return 1.0;
      return MathAbs(result.prediction - 0.5) < 0.05 ? 0.5 : 0.0;
     }

   InferenceResult RunInference(const double &features[])
     {
      InferenceResult result;
      result.timestamp = TimeCurrent();
      if(m_activeModelIndex < 0 || m_activeModelIndex >= ArraySize(m_models))
        { result.reasoning = "No active model"; return result; }
      ModelConfig &model = m_models[m_activeModelIndex];
      if(model.status != MODEL_STATUS_READY)
        { result.reasoning = "Model not ready"; return result; }
      ulong  t0         = GetMicrosecondCount();
      double prediction = m_inferenceEngine.Predict(features, ArraySize(features));
      double confidence = m_inferenceEngine.GetConfidence();
      double latencyMs  = (double)(GetMicrosecondCount() - t0) / 1000.0;
      if(confidence < model.confidenceThreshold)
        {
         result.reasoning = StringFormat("Confidence %.3f < threshold %.3f", confidence, model.confidenceThreshold);
         return result;
        }
      int predClass = 1;
      ENUM_ORDER_TYPE sig = ORDER_TYPE_BUY;
      if(prediction > 0.6)      { sig = ORDER_TYPE_BUY;  predClass = 2; }
      else if(prediction < 0.4) { sig = ORDER_TYPE_SELL; predClass = 0; }
      result.isValid        = true;
      result.modelName      = model.name;
      result.prediction     = prediction;
      result.confidence     = confidence;
      result.predictedClass = predClass;
      result.signal         = sig;
      result.reasoning      = StringFormat("%s → %s (%.1f%%)", model.name, result.GetSignalString(), confidence * 100.0);
      m_stats.totalInferences++;
      m_stats.successfulInferences++;
      m_stats.avgConfidence = (m_stats.avgConfidence * (m_stats.successfulInferences - 1) + confidence) / m_stats.successfulInferences;
      m_stats.avgLatencyMs = (m_stats.avgLatencyMs * (m_stats.totalInferences - 1) + latencyMs) / m_stats.totalInferences;
      m_stats.lastInferenceTime = result.timestamp;
      model.lastUsed = result.timestamp;
      return result;
     }

   void ExecuteDeferredTraining()
     {
      if(!m_trainPending) return;
      m_trainPending = false;
      int idx = m_trainTargetModel;
      if(idx < 0 || idx >= ArraySize(m_models)) return;
      ModelConfig &model = m_models[idx];
      Print("[AIOrchestrator] Deferred training start: ", model.name);
      double trainingData[];
      int    labels[];
      int samples = m_trainer.CollectTrainingData(_Symbol, _Period, trainingData, labels);
      if(samples <= 0)
        { Print("[AIOrchestrator] No training data"); return; }
      bool ok = m_trainer.TrainModel(model.path, model.type, trainingData, labels, samples);
      if(ok)
        {
         model.lastTrained = TimeCurrent();
         model.version++;
         m_inferenceEngine.UnloadModel();
         LoadModel(idx);
         Print("[AIOrchestrator] Training OK: ", model.name, " v", model.version);
        }
     }

   void SwitchToFallback()
     {
      m_consecutiveFailures++;
      if(m_consecutiveFailures < m_maxConsecutiveFailures) return;
      for(int i = 0; i < ArraySize(m_models); i++)
        {
         if(i != m_activeModelIndex && m_models[i].status == MODEL_STATUS_READY)
           {
            Print("[AIOrchestrator] Fallback → ", m_models[i].name);
            m_activeModelIndex = i;
            m_stats.modelSwitches++;
            m_consecutiveFailures = 0;
            return;
           }
        }
      Print("[AIOrchestrator] No fallback model available");
     }

public:
   CAIOrchestrator()
      : m_activeModelIndex(-1),  m_inferenceIntervalSec(10),
        m_lastInferenceScore(0.5), m_lastAIVeto(false), m_lastDriftScore(0.0),
        m_consecutiveFailures(0), m_maxConsecutiveFailures(3),
        m_lastInferenceTime(0),  m_featuresValid(false),
        m_trainPending(false),   m_trainTargetModel(-1)
     { ArrayResize(m_cachedFeatures, AI_FEATURE_DIM); }

   virtual ~CAIOrchestrator()
     {
      ArrayFree(m_models);
      ArrayFree(m_cachedFeatures);
     }

   virtual string HandlerName() const override { return "AIOrchestrator"; }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_PRICE_UPDATE);
     }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      if(!m_featureBuilder.Init()) Print("[AIOrchestrator] FeatureBuilder init warning");
      if(!m_inferenceEngine.Init()) Print("[AIOrchestrator] InferenceEngine init warning");
      if(m_cfg.AI.EnableAI && StringLen(m_cfg.AI.ModelFileName) > 0)
         RegisterModel("Primary", m_cfg.AI.ModelFileName, AI_MODEL_LOGISTIC_REGRESSION, 1, true);
      Print("[AIOrchestrator] Init OK — ", ArraySize(m_models), " model(s)");
      return true;
     }

   virtual void OnEvent(const PASREvent &ev) override
     {
      if(ev.id == EVENT_ID_NEW_BAR) OnNewBar();
      else if(ev.id == EVENT_ID_PRICE_UPDATE) OnPriceUpdate();
     }

   int RegisterModel(const string name, const string path, ENUM_AI_MODEL_TYPE type, int version, bool activate = false)
     {
      int idx = ArraySize(m_models);
      ArrayResize(m_models, idx + 1);
      m_models[idx].name      = name;
      m_models[idx].path      = path;
      m_models[idx].type      = type;
      m_models[idx].version   = version;
      m_models[idx].isActive  = activate;
      m_models[idx].status    = MODEL_STATUS_NOT_LOADED;
      m_models[idx].confidenceThreshold = m_cfg.AI.MinConfidence;
      if(activate)
        { m_activeModelIndex = idx; LoadModel(idx); }
      return idx;
     }

   InferenceResult GetPrediction()
     {
      InferenceResult empty;
      datetime now = TimeCurrent();
      if(now - m_lastInferenceTime < m_inferenceIntervalSec)
        { empty.reasoning = "Throttled"; return empty; }
      double features[];
      if(!BuildFeatureVector(features))
        {
         m_consecutiveFailures++;
         m_stats.totalInferences++;
         m_stats.failedInferences++;
         empty.reasoning = "Feature build failed";
         m_lastAIVeto = true;
         m_lastDriftScore = 1.0;
         return empty;
        }
      InferenceResult result = RunInference(features);
      if(!result.isValid)
        {
         m_stats.totalInferences++;
         m_stats.failedInferences++;
         SwitchToFallback();
         m_lastAIVeto = true;
        }
      else
        {
         m_consecutiveFailures = 0;
         m_lastInferenceTime   = now;
         m_lastInferenceScore  = result.prediction;
         m_lastAIVeto          = false;
        }
      m_lastDriftScore = EstimateDriftScore(result);
      return result;
     }

   double Evaluate()
     {
      InferenceResult r = GetPrediction();
      if(r.isValid) return r.prediction;
      return m_lastInferenceScore;
     }

   bool GetLastVeto() const { return m_lastAIVeto; }
   double GetLastDriftScore() const { return m_lastDriftScore; }

   void TriggerRetraining(int modelIndex)
     {
      if(modelIndex < 0 || modelIndex >= ArraySize(m_models)) return;
      m_trainPending     = true;
      m_trainTargetModel = modelIndex;
      Print("[AIOrchestrator] Retraining scheduled for: ", m_models[modelIndex].name);
     }

   virtual void OnNewBar() override
     {
      m_featuresValid = false;
      ExecuteDeferredTraining();
     }

   virtual void OnPriceUpdate() override
     {
      if(!m_cfg.AI.EnableAI) return;
      GetPrediction();
     }

   const AIStats &GetStats() const { return m_stats; }
   int GetActiveModel() const { return m_activeModelIndex; }
   int GetModelCount() const { return ArraySize(m_models); }
   bool IsTrainPending() const { return m_trainPending; }
   double GetLastInferenceScore() const { return m_lastInferenceScore; }

   void SetInferenceInterval(int sec) { m_inferenceIntervalSec = MathMax(1, sec); }
   void SetMaxFailures(int max) { m_maxConsecutiveFailures = MathMax(1, max); }

   virtual bool IsHealthy() const override
     {
      return IManager::IsHealthy() &&
             m_activeModelIndex >= 0 &&
             m_activeModelIndex < ArraySize(m_models) &&
             m_models[m_activeModelIndex].status == MODEL_STATUS_READY;
     }
  };

#endif // __AI_ORCHESTRATOR_MQH__
