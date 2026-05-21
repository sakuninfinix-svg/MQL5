//+------------------------------------------------------------------+
//|                                     Signal/AI/AITrainer.mqh     |
//|                                     Copyright 2026, Agsicentre  |
//|                                                                  |
//|  PURPOSE: Backpropagation + replay buffer + model persistence.  |
//|    - ONLY called via deferred EventBus event (OnNewBar)          |
//|    - NEVER called from OnTick() directly                        |
//|    - Owns replay buffer and minibatch sampling                   |
//|    - Handles file save/load of weights                           |
//|    - Latency budget: < 50ms per NewBar (deferred thread)        |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_AI_TRAINER_MQH__
#define __SIGNAL_AI_TRAINER_MQH__

#include "../../AI/AITypes.mqh"
#include "AIInference.mqh"

//--- Replay buffer config
#define TRAINER_REPLAY_SIZE    512   // experience replay capacity
#define TRAINER_MINIBATCH       32   // samples per training step
#define TRAINER_MAX_EPOCHS       3   // passes per NewBar call

//--- One experience tuple: (state, action, reward, nextState, done)
struct Experience
  {
   double   state[AI_MAX_INPUTS];
   int      action;       // 0=NONE,1=BUY,2=SELL
   double   reward;
   double   nextState[AI_MAX_INPUTS];
   bool     done;
   datetime timestamp;
  };

//+------------------------------------------------------------------+
//| CAITrainer                                                       |
//+------------------------------------------------------------------+
class CAITrainer
  {
private:
   Experience   m_buffer[TRAINER_REPLAY_SIZE];
   int          m_bufHead;       // circular write pointer
   int          m_bufSize;       // actual filled size
   AIWeightSet  m_weights;       // current model weights (shared with Inference)
   double       m_learningRate;
   double       m_gamma;         // discount factor for rewards
   int          m_trainSteps;    // total training steps completed
   string       m_modelFile;     // path for weight persistence
   bool         m_dirty;         // weights changed since last save

   //--- He initialisation for a layer
   void InitLayer(AILayerWeights &layer, int inSz, int outSz)
     {
      layer.inputSize  = inSz;
      layer.outputSize = outSz;
      double scale = MathSqrt(2.0 / inSz);
      for(int o = 0; o < outSz; o++)
        {
         layer.biases[o] = 0.0;
         for(int i = 0; i < inSz; i++)
            layer.weights[o][i] = (MathRand() / 32767.0 - 0.5) * 2.0 * scale;
        }
     }

   //--- MSE loss gradient for output layer (simplified policy gradient)
   double OutputGrad(double predicted, double target)
     { return 2.0 * (predicted - target); }

public:
   CAITrainer()
      : m_bufHead(0), m_bufSize(0),
        m_learningRate(0.001), m_gamma(0.95),
        m_trainSteps(0), m_dirty(false)
     {
      m_modelFile = "PASR_weights.bin";
      ZeroMemory(m_weights);
     }

   //--- Initialise network architecture: inputSz -> hidden[] -> outputs
   void InitNetwork(int inputSz, const int &hiddenSizes[], int hiddenCount,
                    int outputSz = AI_MAX_OUTPUTS)
     {
      m_weights.layerCount = hiddenCount + 1;
      if(m_weights.layerCount > AI_MAX_LAYERS)
         m_weights.layerCount = AI_MAX_LAYERS;

      int prevSz = inputSz;
      for(int l = 0; l < hiddenCount && l < AI_MAX_LAYERS - 1; l++)
        {
         InitLayer(m_weights.layers[l], prevSz, hiddenSizes[l]);
         prevSz = hiddenSizes[l];
        }
      InitLayer(m_weights.layers[m_weights.layerCount - 1], prevSz, outputSz);
      m_dirty = true;
     }

   //--- Push one experience into circular replay buffer
   void Remember(const double &state[], int action, double reward,
                 const double &nextState[], bool done)
     {
      Experience &e = m_buffer[m_bufHead];
      int n = MathMin(ArraySize(state), AI_MAX_INPUTS);
      for(int i = 0; i < n; i++)
        {
         e.state[i]     = state[i];
         e.nextState[i] = nextState[i];
        }
      e.action    = action;
      e.reward    = reward;
      e.done      = done;
      e.timestamp = TimeCurrent();

      m_bufHead = (m_bufHead + 1) % TRAINER_REPLAY_SIZE;
      if(m_bufSize < TRAINER_REPLAY_SIZE) m_bufSize++;
     }

   //--- Run one training cycle (called ONLY from OnNewBar deferred event)
   //--- Returns number of weight updates performed
   int TrainStep()
     {
      if(m_bufSize < TRAINER_MINIBATCH) return 0;

      int updates = 0;
      for(int epoch = 0; epoch < TRAINER_MAX_EPOCHS; epoch++)
        {
         // Sample minibatch (uniform random from replay buffer)
         for(int b = 0; b < TRAINER_MINIBATCH; b++)
           {
            int idx = MathRand() % m_bufSize;
            Experience &e = m_buffer[idx];

            // Simple Q-target: r + gamma * max(Q(s'))
            // (shallow approx — full DQN would use target network)
            double target = e.reward;
            if(!e.done) target += m_gamma * 1.0; // placeholder: use Inference for Q(s')

            // Update output layer weights for chosen action
            // (gradient descent, single output neuron approximation)
            AILayerWeights &outLayer = m_weights.layers[m_weights.layerCount - 1];
            int outIdx = e.action;
            double grad = OutputGrad(target, target); // placeholder loss
            for(int i = 0; i < outLayer.inputSize; i++)
               outLayer.weights[outIdx][i] -= m_learningRate * grad * e.state[i];
            outLayer.biases[outIdx] -= m_learningRate * grad;

            updates++;
           }
        }

      m_trainSteps += updates;
      m_dirty = true;
      return updates;
     }

   //--- Save weights to file (called by Orchestrator after TrainStep)
   bool SaveWeights()
     {
      if(!m_dirty) return true;
      int handle = FileOpen(m_modelFile, FILE_WRITE | FILE_BIN | FILE_COMMON);
      if(handle == INVALID_HANDLE)
        { Print("AITrainer: cannot open ", m_modelFile, " for write"); return false; }

      FileWriteInteger(handle, m_weights.layerCount);
      for(int l = 0; l < m_weights.layerCount; l++)
        {
         AILayerWeights &lw = m_weights.layers[l];
         FileWriteInteger(handle, lw.inputSize);
         FileWriteInteger(handle, lw.outputSize);
         for(int o = 0; o < lw.outputSize; o++)
           {
            FileWriteDouble(handle, lw.biases[o]);
            for(int i = 0; i < lw.inputSize; i++)
               FileWriteDouble(handle, lw.weights[o][i]);
           }
        }
      FileClose(handle);
      m_dirty = false;
      Print("AITrainer: weights saved (", m_trainSteps, " steps)");
      return true;
     }

   //--- Load weights from file
   bool LoadWeights()
     {
      if(!FileIsExist(m_modelFile, FILE_COMMON)) return false;
      int handle = FileOpen(m_modelFile, FILE_READ | FILE_BIN | FILE_COMMON);
      if(handle == INVALID_HANDLE) return false;

      m_weights.layerCount = FileReadInteger(handle);
      for(int l = 0; l < m_weights.layerCount; l++)
        {
         AILayerWeights &lw = m_weights.layers[l];
         lw.inputSize  = FileReadInteger(handle);
         lw.outputSize = FileReadInteger(handle);
         for(int o = 0; o < lw.outputSize; o++)
           {
            lw.biases[o] = FileReadDouble(handle);
            for(int i = 0; i < lw.inputSize; i++)
               lw.weights[o][i] = FileReadDouble(handle);
           }
        }
      FileClose(handle);
      m_dirty = false;
      Print("AITrainer: weights loaded from ", m_modelFile);
      return true;
     }

   const AIWeightSet *GetWeights() const { return &m_weights; }
   int  TrainSteps()  const { return m_trainSteps; }
   int  BufferSize()  const { return m_bufSize; }
   bool HasEnoughData() const { return m_bufSize >= TRAINER_MINIBATCH; }
   void SetLearningRate(double lr) { m_learningRate = lr; }
   void SetModelFile(const string f) { m_modelFile = f; }
  };

#endif // __SIGNAL_AI_TRAINER_MQH__
