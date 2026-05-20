//+------------------------------------------------------------------+
//| AI/AIManager.mqh  — SCAFFOLD v2.12 (IN-PROGRESS decomposition)  |
//| Split: AIInference | AITrainer | AIOrchestrator                  |
//| Backprop is DEFERRED via EventBus — never on tick thread         |
//+------------------------------------------------------------------+
#pragma once
#ifndef AI_AI_MANAGER_MQH
#define AI_AI_MANAGER_MQH

#include "../Core/IManager.mqh"
#include "../Core/Events.mqh"

//--- NN layer descriptor
struct NNLayer
  {
   int   neurons;
   double weights[];  // flattened [in * out]
   double biases[];
   double activations[];
   double deltas[];
  };

//+------------------------------------------------------------------+
//| AIInference — forward pass only, read-only weights               |
//| Safe to call on tick thread                                      |
//+------------------------------------------------------------------+
class CAIInference
  {
public:
   double            m_outputBuf[8];
   int               m_outputSize;

   //--- Lightweight forward pass (no allocation)
   //--- weights are pre-loaded; returns confidence in [0,1]
   double            Predict(const double &features[], int fCount)
     {
      // placeholder — real implementation reads from pre-loaded weight buffer
      // without any heap allocation on the tick thread
      if(fCount <= 0) return 0.0;
      double sum = 0.0;
      for(int i = 0; i < MathMin(fCount, 8); i++) sum += features[i];
      return 1.0 / (1.0 + MathExp(-sum)); // sigmoid stub
     }
  };

//+------------------------------------------------------------------+
//| AITrainer — backprop, deferred via EventBus                      |
//| NEVER called on OnTick/OnPriceUpdate                             |
//+------------------------------------------------------------------+
class CAITrainer
  {
public:
   int               m_replayHead;
   int               m_replaySize;
   double            m_replayFeatures[][32];
   double            m_replayLabels[];
   int               m_replayCapacity;

   CAITrainer() : m_replayHead(0), m_replaySize(0), m_replayCapacity(256)
     {
      ArrayResize(m_replayFeatures, m_replayCapacity);
      ArrayResize(m_replayLabels,   m_replayCapacity);
     }

   void              AddSample(const double &features[], int fCount, double label)
     {
      int idx = m_replayHead % m_replayCapacity;
      for(int i = 0; i < MathMin(fCount, 32); i++)
         m_replayFeatures[idx][i] = features[i];
      m_replayLabels[idx] = label;
      m_replayHead++;
      if(m_replaySize < m_replayCapacity) m_replaySize++;
     }

   //--- Deferred minibatch step — called from OnTimer or deferred queue
   //--- MUST NOT be called from OnTick
   void              TrainStep(int batchSize = 16)
     {
      if(m_replaySize < batchSize) return;
      // TODO: real backprop implementation
      // This runs on the timer thread, never on the price tick thread
     }
  };

//+------------------------------------------------------------------+
//| CAIOrchestrator — owns Inference + Trainer, wires to EventBus   |
//+------------------------------------------------------------------+
class CAIOrchestrator : public IManager
  {
private:
   CAIInference      m_inference;
   CAITrainer        m_trainer;
   double            m_featureBuf[32];
   int               m_featureCount;
   bool              m_trainPending;

   void              BuildFeatures()
     {
      // TODO: fill m_featureBuf from DataManager
      // e.g. ATR, RSI, SR distance, regime score, etc.
      m_featureCount = 0;
     }

public:
   CAIOrchestrator() : m_featureCount(0), m_trainPending(false) {}

   //--- Only inference on new bar — O(features), no allocation
   void              OnNewBar() override
     {
      BuildFeatures();
      double conf = m_inference.Predict(m_featureBuf, m_featureCount);
      // Publish result via EventBus so consumers are decoupled
      if(m_bus != NULL && conf > 0.5)
         m_bus.Publish(EVENT_AI_PREDICTION_READY);
     }

   //--- Price update: skip entirely — inference already done on bar
   void              OnPriceUpdate() override {}

   //--- Timer-driven training step (call from EA OnTimer)
   void              OnTimer()
     {
      m_trainer.TrainStep(16);
     }

   double            GetLastConfidence()
     {
      return m_inference.Predict(m_featureBuf, m_featureCount);
     }

   bool              IsHealthy() const override { return true; }
  };

//--- convenience alias — EA code uses CAIManager for minimal refactor
typedef CAIOrchestrator CAIManager;

#endif // AI_AI_MANAGER_MQH
