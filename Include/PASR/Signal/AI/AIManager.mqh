//+------------------------------------------------------------------+
//|                                        AI/AIManager.mqh          |
//|                           Copyright 2026, Agsicentre            |
//|                                                                  |
//|  PURPOSE: DEPRECATED - Legacy 8-dim AI system.                  |
//|           USE CAIOrchestrator + AIFeatureBuilder (26-dim) instead|
//|                                                                  |
//|  STATUS: Kept for backward compatibility only.                  |
//|          All new development should use AIInference +          |
//|          AIFeatureBuilder with 26-dimensional features.         |
//|                                                                  |
//|  CHANGE LOG:                                                     |
//|  v2.16 (2026-05-21) — DEPRECATION NOTICE:                       |
//|    + Marked as deprecated in favor of 26-dim system             |
//|    + Users should migrate to CAIOrchestrator                    |
//|  v2.15 (2026-05-21) — FIX #4 + FIX #5:                         |
//|    FIX #4: BuildFeaturesPublic() added as public accessor        |
//|            Orchestrator.OnTradeTransaction() now passes real     |
//|            features instead of ArrayInitialize(0) zeros         |
//|    FIX #5: '#include "../Infra/DataManager.mqh"' ->             |
//|            '#include "../Data/DataManager.mqh"'                 |
//|    m_lastScore moved to declaration order fix (was at end)      |
//|                                                                  |
//|  v2.14 (2026-05-21) — Phase 7: initial file                     |
//|    + Deferred backprop (tick -> bar boundary)                   |
//|    + Experience replay ring buffer (no malloc per tick)         |
//|    + Fisher-Yates minibatch sampling                            |
//|    + SaveWeights() / LoadWeights() via MQL5/Common/             |
//|    + DeclareEvents: AI_TRAIN, NEW_BAR, CONFIG_RELOAD            |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "2.16"
#property strict

#ifndef __AI_AIMANAGER_MQH__
#define __AI_AIMANAGER_MQH__

#warning "AIManager is deprecated. Use CAIOrchestrator with 26-dim features instead."

#include "../Core/IManager.mqh"
#include "../Data/DataManager.mqh"   // FIX #5: was ../Infra/DataManager.mqh

//+------------------------------------------------------------------+
//| Network architecture constants (LEGACY 8-DIM)                    |
//| WARNING: This is the old 8-feature system.                       |
//|          New system uses AI_FEATURE_DIM=26 from AITypes.mqh      |
//+------------------------------------------------------------------+
#define AI_INPUT_DIM   8
#define AI_HIDDEN_DIM  16
#define AI_OUTPUT_DIM  1

//+------------------------------------------------------------------+
//| Experience sample for replay buffer (LEGACY)                     |
//+------------------------------------------------------------------+
struct AIExperience
  {
   float features[AI_INPUT_DIM];
   float label;
   float weight;

   AIExperience()
     {
      ArrayInitialize(features, 0.0f);
      label  = 0.0f;
      weight = 1.0f;
     }
  };

//+------------------------------------------------------------------+
//| AIManager                                                        |
//+------------------------------------------------------------------+
class AIManager : public IManager
  {
private:
   float m_w1[AI_INPUT_DIM][AI_HIDDEN_DIM];
   float m_b1[AI_HIDDEN_DIM];
   float m_w2[AI_HIDDEN_DIM][AI_OUTPUT_DIM];
   float m_b2[AI_OUTPUT_DIM];

   AIExperience  m_replayBuffer[512];
   int           m_replayHead;
   int           m_replaySize;
   int           m_replayCapacity;

   bool   m_trainPending;
   int    m_barsSinceLastTrain;
   int    m_totalEpochs;
   double m_lastLoss;
   float  m_lastScore;  // FIX: moved from end-of-class to here

   float  m_hidden[AI_HIDDEN_DIM];
   int    m_shuffleIdx[512];

   float Sigmoid(float x) const
     {
      if(x >  20.0f) return 0.9999546f;
      if(x < -20.0f) return 0.0000454f;
      return 1.0f / (1.0f + (float)MathExp(-x));
     }

   float Tanh(float x) const
     {
      if(x >  10.0f) return  1.0f;
      if(x < -10.0f) return -1.0f;
      float ex = (float)MathExp(2.0f * x);
      return (ex - 1.0f) / (ex + 1.0f);
     }

   float ForwardPass(const float &features[])
     {
      for(int j = 0; j < AI_HIDDEN_DIM; j++)
        {
         float sum = m_b1[j];
         for(int i = 0; i < AI_INPUT_DIM; i++)
            sum += m_w1[i][j] * features[i];
         m_hidden[j] = Tanh(sum);
        }
      float sum = m_b2[0];
      for(int j = 0; j < AI_HIDDEN_DIM; j++)
         sum += m_w2[j][0] * m_hidden[j];
      return Sigmoid(sum);
     }

   void PushExperience(const AIExperience &exp)
     {
      m_replayBuffer[m_replayHead] = exp;
      m_replayHead = (m_replayHead + 1) % m_replayCapacity;
      if(m_replaySize < m_replayCapacity) m_replaySize++;
      m_trainPending = true;
     }

   int SampleMinibatch(int batchSize)
     {
      int avail = MathMin(m_replaySize, m_replayCapacity);
      if(avail == 0) return 0;
      for(int i = 0; i < avail; i++) m_shuffleIdx[i] = i;
      int actual = MathMin(batchSize, avail);
      for(int i = 0; i < actual; i++)
        {
         int j  = i + (int)(MathRand() % (avail - i));
         int tmp = m_shuffleIdx[i];
         m_shuffleIdx[i] = m_shuffleIdx[j];
         m_shuffleIdx[j] = tmp;
        }
      return actual;
     }

   double Backprop()
     {
      int actual = SampleMinibatch(m_cfg.AI.MinibatchSize);
      if(actual == 0) return 0.0;

      float lr = (float)m_cfg.AI.LearningRate;

      float dW2[AI_HIDDEN_DIM][AI_OUTPUT_DIM];
      float dB2[AI_OUTPUT_DIM];
      float dW1[AI_INPUT_DIM][AI_HIDDEN_DIM];
      float dB1[AI_HIDDEN_DIM];

      ArrayInitialize(dW2, 0.0f);
      ArrayInitialize(dB2, 0.0f);
      ArrayInitialize(dW1, 0.0f);
      ArrayInitialize(dB1, 0.0f);

      double totalLoss  = 0.0;
      float  hiddenBuf[AI_HIDDEN_DIM];

      for(int s = 0; s < actual; s++)
        {
         AIExperience &exp = m_replayBuffer[m_shuffleIdx[s]];
         float y = exp.label;
         float w = exp.weight;

         for(int j = 0; j < AI_HIDDEN_DIM; j++)
           {
            float sum = m_b1[j];
            for(int i = 0; i < AI_INPUT_DIM; i++)
               sum += m_w1[i][j] * exp.features[i];
            hiddenBuf[j] = Tanh(sum);
           }
         float netOut = m_b2[0];
         for(int j = 0; j < AI_HIDDEN_DIM; j++)
            netOut += m_w2[j][0] * hiddenBuf[j];
         float pred = Sigmoid(netOut);

         float predC = MathMax(1e-7f, MathMin(1.0f - 1e-7f, pred));
         totalLoss  += -((y * MathLog(predC) + (1.0f - y) * MathLog(1.0f - predC)) * w);

         float delta2 = (pred - y) * w;
         for(int j = 0; j < AI_HIDDEN_DIM; j++)
            dW2[j][0] += delta2 * hiddenBuf[j];
         dB2[0] += delta2;

         for(int j = 0; j < AI_HIDDEN_DIM; j++)
           {
            float delta1 = m_w2[j][0] * delta2 * (1.0f - hiddenBuf[j] * hiddenBuf[j]);
            for(int i = 0; i < AI_INPUT_DIM; i++)
               dW1[i][j] += delta1 * exp.features[i];
            dB1[j] += delta1;
           }
        }

      float inv = 1.0f / (float)actual;
      for(int j = 0; j < AI_HIDDEN_DIM; j++)
         m_w2[j][0] -= lr * dW2[j][0] * inv;
      m_b2[0] -= lr * dB2[0] * inv;
      for(int j = 0; j < AI_HIDDEN_DIM; j++)
        {
         for(int i = 0; i < AI_INPUT_DIM; i++)
            m_w1[i][j] -= lr * dW1[i][j] * inv;
         m_b1[j] -= lr * dB1[j] * inv;
        }

      return totalLoss / actual;
     }

   bool SaveWeights()
     {
      if(!m_cfg.AI.PersistWeights) return true;
      string path = m_cfg.AI.ModelFileName;
      int fh = FileOpen(path, FILE_WRITE | FILE_BIN | FILE_COMMON);
      if(fh == INVALID_HANDLE) return false;
      uint magic = 0x50415352;
      uint ver   = 1;
      FileWriteInteger(fh, (int)magic);
      FileWriteInteger(fh, (int)ver);
      for(int i = 0; i < AI_INPUT_DIM; i++)
         for(int j = 0; j < AI_HIDDEN_DIM; j++)
            FileWriteFloat(fh, m_w1[i][j]);
      for(int j = 0; j < AI_HIDDEN_DIM; j++) FileWriteFloat(fh, m_b1[j]);
      for(int j = 0; j < AI_HIDDEN_DIM; j++)
         for(int k = 0; k < AI_OUTPUT_DIM; k++)
            FileWriteFloat(fh, m_w2[j][k]);
      for(int k = 0; k < AI_OUTPUT_DIM; k++) FileWriteFloat(fh, m_b2[k]);
      FileClose(fh);
      return true;
     }

   bool LoadWeights()
     {
      if(!m_cfg.AI.PersistWeights) return true;
      string path = m_cfg.AI.ModelFileName;
      if(!FileIsExist(path, FILE_COMMON)) return false;
      int fh = FileOpen(path, FILE_READ | FILE_BIN | FILE_COMMON);
      if(fh == INVALID_HANDLE) return false;
      uint magic = (uint)FileReadInteger(fh);
      uint ver   = (uint)FileReadInteger(fh);
      if(magic != 0x50415352 || ver != 1) { FileClose(fh); return false; }
      for(int i = 0; i < AI_INPUT_DIM; i++)
         for(int j = 0; j < AI_HIDDEN_DIM; j++)
            m_w1[i][j] = FileReadFloat(fh);
      for(int j = 0; j < AI_HIDDEN_DIM; j++) m_b1[j] = FileReadFloat(fh);
      for(int j = 0; j < AI_HIDDEN_DIM; j++)
         for(int k = 0; k < AI_OUTPUT_DIM; k++)
            m_w2[j][k] = FileReadFloat(fh);
      for(int k = 0; k < AI_OUTPUT_DIM; k++) m_b2[k] = FileReadFloat(fh);
      FileClose(fh);
      return true;
     }

   void InitWeightsXavier()
     {
      float range1 = (float)MathSqrt(6.0 / (AI_INPUT_DIM  + AI_HIDDEN_DIM));
      float range2 = (float)MathSqrt(6.0 / (AI_HIDDEN_DIM + AI_OUTPUT_DIM));
      MathSrand((uint)TimeCurrent());
      for(int i = 0; i < AI_INPUT_DIM; i++)
         for(int j = 0; j < AI_HIDDEN_DIM; j++)
            m_w1[i][j] = range1 * (2.0f * (float)MathRand() / 32767.0f - 1.0f);
      ArrayInitialize(m_b1, 0.0f);
      for(int j = 0; j < AI_HIDDEN_DIM; j++)
         for(int k = 0; k < AI_OUTPUT_DIM; k++)
            m_w2[j][k] = range2 * (2.0f * (float)MathRand() / 32767.0f - 1.0f);
      ArrayInitialize(m_b2, 0.0f);
     }

   // FIX #4: BuildFeatures is now accessible publicly via BuildFeaturesPublic()
   bool BuildFeatures(float &features[])
     {
      ArrayResize(features, AI_INPUT_DIM);

      double atr = m_data.GetATRPoints();
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      features[0] = (bid > 0) ? (float)(atr * _Point / bid) * 100.0f : 0.0f;
      features[1] = (float)(m_data.GetADXValue() / 100.0);

      double sma20 = m_data.GetSMA(20, 0);
      features[2] = (atr > 0) ? (float)((bid - sma20) / (atr * _Point)) : 0.0f;
      features[2] = MathMax(-3.0f, MathMin(3.0f, features[2]));

      features[3] = (float)(m_data.GetRSI(14, 0) / 100.0);

      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      features[4] = (float)dt.hour / 23.0f;
      features[5] = (float)dt.day_of_week / 6.0f;

      double spreadPips = (SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point) / (10.0 * _Point);
      features[6] = (float)MathMin(1.0, spreadPips);

      double ret = (iClose(_Symbol, _Period, 0) - iClose(_Symbol, _Period, 1));
      features[7] = (atr > 0) ? (float)(ret / (atr * _Point)) : 0.0f;
      features[7] = MathMax(-3.0f, MathMin(3.0f, features[7]));

      return true;
     }

public:
   AIManager()
      : IManager(),
        m_replayHead(0), m_replaySize(0), m_replayCapacity(512),
        m_trainPending(false), m_barsSinceLastTrain(0),
        m_totalEpochs(0), m_lastLoss(0.0), m_lastScore(0.5f)
     {
      ArrayInitialize(m_w1, 0.0f);
      ArrayInitialize(m_b1, 0.0f);
      ArrayInitialize(m_w2, 0.0f);
      ArrayInitialize(m_b2, 0.0f);
      ArrayInitialize(m_hidden, 0.0f);
      ArrayInitialize(m_shuffleIdx, 0);
     }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      m_replayCapacity = MathMin(m_cfg.AI.ReplayBufferSize, 512);
      if(m_replayCapacity < m_cfg.AI.MinibatchSize)
        {
         m_replayCapacity = m_cfg.AI.MinibatchSize;
         Print("[AIManager] Init: ReplayBufferSize < MinibatchSize, clamped to ", m_replayCapacity);
        }
      if(!LoadWeights()) InitWeightsXavier();
      return true;
     }

   virtual void Deinit() override { SaveWeights(); }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_AI_TRAIN);
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_PRICE_UPDATE);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
     }

   virtual void OnPriceUpdate() override
     {
      if(!m_cfg.AI.EnableAI) return;
      float features[];
      if(!BuildFeatures(features)) return;
      m_lastScore = ForwardPass(features);
     }

   virtual void OnNewBar() override
     {
      if(!m_cfg.AI.EnableAI) return;
      m_barsSinceLastTrain++;
      if(!m_trainPending) return;
      if(m_barsSinceLastTrain < m_cfg.AI.TrainIntervalBars) return;
      if(m_replaySize < m_cfg.AI.MinibatchSize) return;

      m_lastLoss           = Backprop();
      m_trainPending       = false;
      m_barsSinceLastTrain = 0;
      m_totalEpochs++;

      if(m_debugMode)
         PrintFormat("[AIManager] Train epoch %d: loss=%.6f replay=%d",
                     m_totalEpochs, m_lastLoss, m_replaySize);

      if(m_totalEpochs % 10 == 0) SaveWeights();

      PASREvent ev;
      ev.id       = EVENT_ID_AI_TRAIN;
      ev.priority = 5;
      DispatchEvent(ev);
     }

   void OnTradeResult(const float &features[], float label, float weight = 1.0f)
     {
      if(!m_cfg.AI.EnableAI) return;
      if(m_replayCapacity <= 0) return;
      AIExperience exp;
      ArrayCopy(exp.features, features, 0, 0, AI_INPUT_DIM);
      exp.label  = label;
      exp.weight = weight;
      PushExperience(exp);
     }

   // FIX #4: Public wrapper so Orchestrator can call BuildFeatures() at trade close
   // Returns true if features built successfully, false if data not ready.
   bool BuildFeaturesPublic(float &features[])
     {
      return BuildFeatures(features);
     }

   bool IsSignalConfident() const
     {
      if(!m_cfg.AI.EnableAI) return true;
      return m_lastScore >= (float)m_cfg.AI.MinConfidence;
     }

   double GetLastLoss()    const { return m_lastLoss; }
   int    GetTotalEpochs() const { return m_totalEpochs; }
   int    GetReplaySize()  const { return m_replaySize; }
   float  GetSignalScore() const { return m_lastScore; }
   
   // COMPATIBILITY METHODS for PipelineEngine (legacy API support)
   // These are stub implementations to maintain compatibility with old code
   // that calls Predict() and GetDriftScore(). New code should use CAIOrchestrator.
   
   // Legacy method: Predict score from features (uses ForwardPass internally)
   double Predict(const float &features[])
     {
      // Convert float[] to internal format and run forward pass
      // Note: This is a legacy compatibility shim
      return (double)ForwardPass(features);
     }
   
   // Legacy method: Get drift score (stub - returns 0.0 for backward compat)
   // Real drift detection is in AIInference + FeatureEngine
   double GetDriftScore() const { return 0.0; }

   virtual void OnConfigReload() override
     {
      IManager::OnConfigReload();
      int newCap = MathMin(m_cfg.AI.ReplayBufferSize, 512);
      if(newCap != m_replayCapacity && m_debugMode)
         PrintFormat("[AIManager] ReplayCapacity changed %d -> %d", m_replayCapacity, newCap);
      m_replayCapacity = newCap;
     }
  };

#endif // __AI_AIMANAGER_MQH__
