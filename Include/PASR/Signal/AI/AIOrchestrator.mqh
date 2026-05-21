//+------------------------------------------------------------------+
//|                                  Signal/AI/AIOrchestrator.mqh   |
//|                                     Copyright 2026, Agsicentre  |
//|                                                                  |
//|  PURPOSE: Thin coordinator between Inference and Trainer.       |
//|    - ONLY file included by SignalManager.mqh                    |
//|    - Decides WHEN to train (throttle, market hours, session)    |
//|    - Manages expert regime switch (trend / ranging / volatile)  |
//|    - Passes weight updates from Trainer -> Inference atomically  |
//|    - Training is DEFERRED: triggered by NewBar event, not tick  |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_AI_ORCHESTRATOR_MQH__
#define __SIGNAL_AI_ORCHESTRATOR_MQH__

#include "AIInference.mqh"
#include "AITrainer.mqh"
#include "../../Core/IManager.mqh"
#include "../../Core/Events.mqh"

//--- Regime types detected by Orchestrator
enum ENUM_MARKET_EXPERT
  {
   EXPERT_TREND    = 0,  // strong directional move
   EXPERT_RANGING  = 1,  // sideways / mean-revert
   EXPERT_VOLATILE = 2,  // high ATR, breakout candidate
   EXPERT_COUNT    = 3
  };

//--- Training throttle: min bars between training cycles
#define ORCH_TRAIN_INTERVAL_BARS   5
//--- Min confidence required to emit a signal
#define ORCH_MIN_CONFIDENCE        0.60
//--- How many NewBar events without improvement before regime switch
#define ORCH_REGIME_PATIENCE       20

//+------------------------------------------------------------------+
//| CAIOrchestrator                                                  |
//+------------------------------------------------------------------+
class CAIOrchestrator : public IManager
  {
private:
   CAIInference       m_inference;          // per-tick forward pass
   CAITrainer         m_trainer;            // per-newbar training
   ENUM_MARKET_EXPERT m_currentRegime;
   int                m_barsSinceTraining;  // throttle counter
   int                m_barsSinceSwitch;    // regime patience counter
   double             m_lastLoss;           // track training improvement
   bool               m_weightsLoaded;      // inference engine ready flag
   InferenceResult    m_lastResult;         // cached last prediction

   //--- Detect regime from cached config / market data
   ENUM_MARKET_EXPERT DetectRegime()
     {
      // Use ATR vs long-term ATR ratio for regime detection
      double atrFast = iATR(_Symbol, PERIOD_CURRENT, 14,  1);
      double atrSlow = iATR(_Symbol, PERIOD_CURRENT, 50,  1);
      if(atrSlow <= 0.0) return EXPERT_RANGING;
      double ratio = atrFast / atrSlow;
      if(ratio > 1.4) return EXPERT_VOLATILE;
      if(ratio > 0.9) return EXPERT_TREND;
      return EXPERT_RANGING;
     }

   //--- Atomic weight swap: Trainer -> Inference (no partial state)
   void CommitWeights()
     {
      const AIWeightSet *ws = m_trainer.GetWeights();
      if(ws == NULL) return;
      if(m_inference.LoadWeights(*ws))
         m_weightsLoaded = true;
     }

   //--- Build feature vector from current bar
   void BuildFeatures(double &features[], int &count)
     {
      ArrayResize(features, AI_MAX_INPUTS);
      count = 0;

      // Price-based features (normalised)
      double close  = iClose(_Symbol, PERIOD_CURRENT, 1);
      double open   = iOpen(_Symbol, PERIOD_CURRENT, 1);
      double high   = iHigh(_Symbol, PERIOD_CURRENT, 1);
      double low    = iLow(_Symbol, PERIOD_CURRENT, 1);
      double range  = high - low;
      if(range <= 0.0) range = _Point;

      features[count++] = (close - low)  / range;          // candle position
      features[count++] = (close - open) / range;          // body ratio
      features[count++] = (high  - close)/ range;          // upper wick
      features[count++] = (close - low)  / range;          // lower wick

      // ATR normalised
      double atr = iATR(_Symbol, PERIOD_CURRENT, 14, 1);
      features[count++] = MathMin(atr / (_Point * 100.0), 1.0);

      // RSI normalised [0,1]
      double rsi = iRSI(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE, 1);
      features[count++] = rsi / 100.0;

      // Regime one-hot
      features[count++] = (m_currentRegime == EXPERT_TREND)    ? 1.0 : 0.0;
      features[count++] = (m_currentRegime == EXPERT_RANGING)  ? 1.0 : 0.0;
      features[count++] = (m_currentRegime == EXPERT_VOLATILE) ? 1.0 : 0.0;

      // Pad remaining with 0
      while(count < AI_MAX_INPUTS) features[count++] = 0.0;
     }

public:
   CAIOrchestrator()
      : m_currentRegime(EXPERT_RANGING),
        m_barsSinceTraining(0), m_barsSinceSwitch(0),
        m_lastLoss(1e9), m_weightsLoaded(false)
     {}

   //--- Called once from EA OnInit (after ConfigManager sets up m_cfg)
   bool Init()
     {
      // Try load saved weights; init fresh network if not found
      if(!m_trainer.LoadWeights())
        {
         int hidden[] = {32, 16};
         m_trainer.InitNetwork(AI_MAX_INPUTS, hidden, 2, AI_MAX_OUTPUTS);
         Print("AIOrchestrator: new network initialised");
        }
      CommitWeights();
      return true;
     }

   //--- OnNewBar: run training cycle (deferred from tick thread)
   void OnNewBar() override
     {
      m_barsSinceTraining++;
      m_barsSinceSwitch++;

      // Regime check every bar
      ENUM_MARKET_EXPERT newRegime = DetectRegime();
      if(newRegime != m_currentRegime)
        {
         // Switch regime if patience exceeded or regime is volatile (urgent)
         if(m_barsSinceSwitch >= ORCH_REGIME_PATIENCE ||
            newRegime == EXPERT_VOLATILE)
           {
            m_currentRegime   = newRegime;
            m_barsSinceSwitch = 0;
            if(m_bus != NULL)
               m_bus.Publish(EVENT_REGIME_CHANGED);
           }
        }

      // Training throttle
      if(m_barsSinceTraining < ORCH_TRAIN_INTERVAL_BARS) return;
      if(!m_trainer.HasEnoughData()) return;
      m_barsSinceTraining = 0;

      // Run training step
      int updates = m_trainer.TrainStep();
      if(updates > 0)
        {
         CommitWeights();            // atomic swap to inference
         m_trainer.SaveWeights();    // persist to disk
        }
     }

   //--- OnPriceUpdate: run inference, publish signal event if confident
   void OnPriceUpdate() override
     {
      if(!m_weightsLoaded) return;

      double features[AI_MAX_INPUTS];
      int    featureCount = 0;
      BuildFeatures(features, featureCount);

      m_lastResult = m_inference.Predict(features, featureCount);

      // Only publish if above confidence threshold and not NONE class
      if(m_lastResult.confidence >= ORCH_MIN_CONFIDENCE &&
         m_lastResult.bestClass != 0 &&
         m_bus != NULL)
         m_bus.Publish(EVENT_SIGNAL_GENERATED);
     }

   //--- Push experience into trainer replay buffer
   void Remember(const double &state[], int action, double reward,
                 const double &nextState[], bool done)
     { m_trainer.Remember(state, action, reward, nextState, done); }

   //--- Accessors
   InferenceResult    GetLastResult()  const { return m_lastResult; }
   ENUM_MARKET_EXPERT GetRegime()      const { return m_currentRegime; }
   bool               IsReady()        const { return m_weightsLoaded; }
   int                TrainSteps()     const { return m_trainer.TrainSteps(); }
   int                ReplayBuffer()   const { return m_trainer.BufferSize(); }
   bool               IsHealthy()      const override { return m_weightsLoaded; }
  };

#endif // __SIGNAL_AI_ORCHESTRATOR_MQH__
