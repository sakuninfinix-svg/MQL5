//+------------------------------------------------------------------+
//|                                        AI/AIManager.mqh          |
//|                           Copyright 2026, Agsicentre            |
//|                                                                  |
//|  PURPOSE: AI signal filter + deferred backpropagation manager.  |
//|                                                                  |
//|  PHASE 7 CRITICAL FIX — Backprop deferral:                      |
//|    BEFORE (broken): backprop called inside OnPriceUpdate()       |
//|      → every incoming tick triggered a full backprop pass        |
//|      → at 10 ticks/sec on EURUSD this was ~600k iterations/min  |
//|      → MT5 freezes, terminal becomes unresponsive               |
//|                                                                  |
//|    AFTER (fixed): OnPriceUpdate() ONLY:                          |
//|      1. Evaluates current features against frozen weights        |
//|         (O(n*m) forward pass, cheap)                            |
//|      2. Pushes experience to replay buffer (ring buffer, O(1))  |
//|      Backprop fires ONCE per bar (OnNewBar) if:                  |
//|      - m_trainPending == true  (new experience accumulated)      |
//|      - bars elapsed >= TrainIntervalBars                         |
//|                                                                  |
//|  ARCHITECTURE:                                                   |
//|    - Single hidden layer MLP: INPUT_DIM → HIDDEN → 1 output     |
//|    - Activation: tanh (hidden), sigmoid (output)                |
//|    - Loss: binary cross-entropy (signal up/down)                |
//|    - Weights: float32 arrays (MQL5 has no tensor type)          |
//|    - Replay: ring buffer, no heap alloc on hot path             |
//|    - Minibatch: Fisher-Yates shuffle, sample size = MinibatchSize|
//|                                                                  |
//|  INPUT FEATURES (INPUT_DIM = 8):                                 |
//|    [0] Normalized ATR  [1] ADX value                            |
//|    [2] Price vs SMA20  [3] RSI-14 normalized                    |
//|    [4] Hour of day     [5] Day of week                          |
//|    [6] Spread pips     [7] Recent return (1-bar)                |
//|                                                                  |
//|  CHANGE LOG:                                                     |
//|  v2.14 (2026-05-21) — Phase 7: new file                         |
//|    + Deferred backprop (tick → bar boundary)                    |
//|    + Experience replay ring buffer (no malloc per tick)         |
//|    + Fisher-Yates minibatch sampling                            |
//|    + SaveWeights() / LoadWeights() via MQL5/Common/             |
//|    + DeclareEvents: AI_TRAIN, NEW_BAR, CONFIG_RELOAD            |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "2.14"
#property strict

#ifndef __AI_AIMANAGER_MQH__
#define __AI_AIMANAGER_MQH__

#include "../Core/IManager.mqh"
#include "../Infra/DataManager.mqh"

//+------------------------------------------------------------------+
//| Network architecture constants                                   |
//+------------------------------------------------------------------+
#define AI_INPUT_DIM   8     // number of input features
#define AI_HIDDEN_DIM  16    // hidden layer width
#define AI_OUTPUT_DIM  1     // output: signal score [0,1]

//+------------------------------------------------------------------+
//| Experience sample for replay buffer                              |
//+------------------------------------------------------------------+
struct AIExperience
  {
   float features[AI_INPUT_DIM]; // input feature vector at time of trade
   float label;                  // 1.0 = profitable outcome, 0.0 = loss
   float weight;                 // importance weighting (1.0 default)

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
   // ── Network weights — float32 for memory efficiency ───────────────
   // Layer 1: INPUT_DIM → HIDDEN_DIM  (weights + bias)
   float m_w1[AI_INPUT_DIM][AI_HIDDEN_DIM];
   float m_b1[AI_HIDDEN_DIM];
   // Layer 2: HIDDEN_DIM → OUTPUT_DIM (weights + bias)
   float m_w2[AI_HIDDEN_DIM][AI_OUTPUT_DIM];
   float m_b2[AI_OUTPUT_DIM];

   // ── Experience replay ring buffer ─────────────────────────────
   // Fixed-size ring buffer: no dynamic allocation on tick path.
   // m_replayHead wraps around when buffer is full (oldest overwritten).
   AIExperience  m_replayBuffer[512];  // max capacity; trimmed by config
   int           m_replayHead;         // next write position
   int           m_replaySize;         // current number of valid entries
   int           m_replayCapacity;     // set from m_cfg.AI.ReplayBufferSize

   // ── Training state machine ─────────────────────────────────
   // [PHASE 7 CORE] m_trainPending is the gate:
   //   OnPriceUpdate: sets m_trainPending = true when new experience arrives
   //   OnNewBar:      consumes m_trainPending, runs backprop ONCE
   // This ensures backprop NEVER runs on the tick thread.
   bool   m_trainPending;     // deferred backprop requested
   int    m_barsSinceLastTrain; // bar counter since last successful train
   int    m_totalEpochs;      // lifetime training epochs
   double m_lastLoss;         // last epoch average loss (for monitoring)

   // ── Forward pass scratch buffers (reused, no alloc per call) ───
   float  m_hidden[AI_HIDDEN_DIM];

   // ── Shuffle index array for Fisher-Yates (pre-allocated) ──────
   int    m_shuffleIdx[512];

   // ─────────────────────────────────────────────────────────────────
   //  Math helpers
   // ─────────────────────────────────────────────────────────────────

   // Sigmoid activation: maps any real to (0,1)
   float Sigmoid(float x) const
     {
      // Clamp input to avoid overflow at extremes: e^-x overflows float for x < -87
      if(x >  20.0f) return 0.9999546f;
      if(x < -20.0f) return 0.0000454f;
      return 1.0f / (1.0f + (float)MathExp(-x));
     }

   // Tanh: hidden layer activation
   float Tanh(float x) const
     {
      if(x >  10.0f) return  1.0f;
      if(x < -10.0f) return -1.0f;
      float ex = (float)MathExp(2.0f * x);
      return (ex - 1.0f) / (ex + 1.0f);
     }

   // ─────────────────────────────────────────────────────────────────
   //  Forward pass
   // ─────────────────────────────────────────────────────────────────

   // Run inference: features[INPUT_DIM] → score [0,1]
   // Writes hidden activations to m_hidden[] for reuse in backprop.
   // Cheap enough to call on every tick.
   float ForwardPass(const float &features[])
     {
      // Layer 1: hidden = tanh(W1 * x + b1)
      for(int j = 0; j < AI_HIDDEN_DIM; j++)
        {
         float sum = m_b1[j];
         for(int i = 0; i < AI_INPUT_DIM; i++)
            sum += m_w1[i][j] * features[i];
         m_hidden[j] = Tanh(sum);
        }

      // Layer 2: output = sigmoid(W2 * hidden + b2)
      float sum = m_b2[0];
      for(int j = 0; j < AI_HIDDEN_DIM; j++)
         sum += m_w2[j][0] * m_hidden[j];
      return Sigmoid(sum);
     }

   // ─────────────────────────────────────────────────────────────────
   //  Replay buffer management
   // ─────────────────────────────────────────────────────────────────

   // Push one experience to ring buffer. O(1), no allocation.
   // Oldest entries are overwritten when buffer is full.
   void PushExperience(const AIExperience &exp)
     {
      m_replayBuffer[m_replayHead] = exp;
      m_replayHead = (m_replayHead + 1) % m_replayCapacity;
      if(m_replaySize < m_replayCapacity) m_replaySize++;
      m_trainPending = true;  // signal that deferred backprop is needed
     }

   // ─────────────────────────────────────────────────────────────────
   //  Backpropagation (DEFERRED — OnNewBar only)
   // ─────────────────────────────────────────────────────────────────

   // Build a minibatch index sample using Fisher-Yates shuffle.
   // Returns the number of indices filled into m_shuffleIdx[].
   int SampleMinibatch(int batchSize)
     {
      // Fill indices 0..m_replaySize-1 and partially shuffle
      int avail = MathMin(m_replaySize, m_replayCapacity);
      if(avail == 0) return 0;

      for(int i = 0; i < avail; i++) m_shuffleIdx[i] = i;

      // Fisher-Yates: only shuffle up to batchSize elements
      // so we get batchSize random unique indices in O(batchSize)
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

   // One backprop step over a sampled minibatch.
   // [PHASE 7] ONLY called from OnNewBar(), NEVER from OnPriceUpdate().
   // Returns average cross-entropy loss over the minibatch.
   double Backprop()
     {
      int actual = SampleMinibatch(m_cfg.AI.MinibatchSize);
      if(actual == 0) return 0.0;

      float lr = (float)m_cfg.AI.LearningRate;

      // Gradient accumulators for Layer 2
      float dW2[AI_HIDDEN_DIM][AI_OUTPUT_DIM];
      float dB2[AI_OUTPUT_DIM];
      // Gradient accumulators for Layer 1
      float dW1[AI_INPUT_DIM][AI_HIDDEN_DIM];
      float dB1[AI_HIDDEN_DIM];

      ArrayInitialize(dW2, 0.0f);
      ArrayInitialize(dB2, 0.0f);
      ArrayInitialize(dW1, 0.0f);
      ArrayInitialize(dB1, 0.0f);

      double totalLoss = 0.0;
      float  hiddenBuf[AI_HIDDEN_DIM];  // per-sample hidden activations

      for(int s = 0; s < actual; s++)
        {
         AIExperience &exp = m_replayBuffer[m_shuffleIdx[s]];
         float         y   = exp.label;
         float         w   = exp.weight;

         // ─ Forward pass (inline to capture hidden activations)
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

         // ─ Binary cross-entropy loss (clamped to avoid log(0))
         float predC = MathMax(1e-7f, MathMin(1.0f - 1e-7f, pred));
         totalLoss  += -((y * MathLog(predC) + (1.0f - y) * MathLog(1.0f - predC)) * w);

         // ─ Output layer delta: d_L/d_netOut = (pred - y) * weight
         float delta2 = (pred - y) * w;

         // ─ Accumulate gradients for Layer 2
         for(int j = 0; j < AI_HIDDEN_DIM; j++)
            dW2[j][0] += delta2 * hiddenBuf[j];
         dB2[0] += delta2;

         // ─ Backprop through tanh: d_tanh = 1 - tanh^2
         for(int j = 0; j < AI_HIDDEN_DIM; j++)
           {
            float delta1 = m_w2[j][0] * delta2 * (1.0f - hiddenBuf[j] * hiddenBuf[j]);
            for(int i = 0; i < AI_INPUT_DIM; i++)
               dW1[i][j] += delta1 * exp.features[i];
            dB1[j] += delta1;
           }
        }

      // ─ Normalise by batch size
      float inv = 1.0f / (float)actual;

      // ─ Update Layer 2 weights (SGD step)
      for(int j = 0; j < AI_HIDDEN_DIM; j++)
         m_w2[j][0] -= lr * dW2[j][0] * inv;
      m_b2[0] -= lr * dB2[0] * inv;

      // ─ Update Layer 1 weights
      for(int j = 0; j < AI_HIDDEN_DIM; j++)
        {
         for(int i = 0; i < AI_INPUT_DIM; i++)
            m_w1[i][j] -= lr * dW1[i][j] * inv;
         m_b1[j] -= lr * dB1[j] * inv;
        }

      return totalLoss / actual;
     }

   // ─────────────────────────────────────────────────────────────────
   //  Weight persistence
   // ─────────────────────────────────────────────────────────────────

   // Save weights to binary file in MQL5/Common/
   // Format: magic_header(4B) | version(4B) | w1 flat | b1 | w2 flat | b2
   bool SaveWeights()
     {
      if(!m_cfg.AI.PersistWeights) return true;  // disabled by config

      string path = m_cfg.AI.ModelFileName;
      int fh = FileOpen(path, FILE_WRITE | FILE_BIN | FILE_COMMON);
      if(fh == INVALID_HANDLE)
        {
         if(m_debugMode)
            PrintFormat("[AIManager] SaveWeights: cannot open '%s' err=%d", path, GetLastError());
         return false;
        }

      // Header: magic bytes + version
      uint magic = 0x50415352; // 'PASR'
      uint ver   = 1;
      FileWriteInteger(fh, (int)magic);
      FileWriteInteger(fh, (int)ver);

      // Layer 1 weights (INPUT_DIM x HIDDEN_DIM floats)
      for(int i = 0; i < AI_INPUT_DIM; i++)
         for(int j = 0; j < AI_HIDDEN_DIM; j++)
            FileWriteFloat(fh, m_w1[i][j]);
      for(int j = 0; j < AI_HIDDEN_DIM; j++)
         FileWriteFloat(fh, m_b1[j]);

      // Layer 2 weights (HIDDEN_DIM x OUTPUT_DIM floats)
      for(int j = 0; j < AI_HIDDEN_DIM; j++)
         for(int k = 0; k < AI_OUTPUT_DIM; k++)
            FileWriteFloat(fh, m_w2[j][k]);
      for(int k = 0; k < AI_OUTPUT_DIM; k++)
         FileWriteFloat(fh, m_b2[k]);

      FileClose(fh);
      if(m_debugMode) PrintFormat("[AIManager] Weights saved: '%s'", path);
      return true;
     }

   // Load weights from binary file in MQL5/Common/
   // Returns false and leaves weights unchanged if file is absent or malformed.
   bool LoadWeights()
     {
      if(!m_cfg.AI.PersistWeights) return true;

      string path = m_cfg.AI.ModelFileName;
      if(!FileIsExist(path, FILE_COMMON)) return false;

      int fh = FileOpen(path, FILE_READ | FILE_BIN | FILE_COMMON);
      if(fh == INVALID_HANDLE) return false;

      uint magic = (uint)FileReadInteger(fh);
      uint ver   = (uint)FileReadInteger(fh);
      if(magic != 0x50415352 || ver != 1)
        {
         FileClose(fh);
         if(m_debugMode) PrintFormat("[AIManager] LoadWeights: bad header magic=0x%x ver=%d", magic, ver);
         return false;
        }

      for(int i = 0; i < AI_INPUT_DIM; i++)
         for(int j = 0; j < AI_HIDDEN_DIM; j++)
            m_w1[i][j] = FileReadFloat(fh);
      for(int j = 0; j < AI_HIDDEN_DIM; j++)
         m_b1[j] = FileReadFloat(fh);
      for(int j = 0; j < AI_HIDDEN_DIM; j++)
         for(int k = 0; k < AI_OUTPUT_DIM; k++)
            m_w2[j][k] = FileReadFloat(fh);
      for(int k = 0; k < AI_OUTPUT_DIM; k++)
         m_b2[k] = FileReadFloat(fh);

      FileClose(fh);
      if(m_debugMode) PrintFormat("[AIManager] Weights loaded from '%s'", path);
      return true;
     }

   // Xavier initialisation: range = sqrt(6 / (fan_in + fan_out))
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

   // Build feature vector from current market state (DataManager).
   // Called from OnPriceUpdate() only — cheap forward pass input.
   bool BuildFeatures(float &features[])
     {
      ArrayResize(features, AI_INPUT_DIM);

      // [0] ATR normalised to price (0..1 typical range)
      double atr = m_data.GetATRPoints();
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      features[0] = (bid > 0) ? (float)(atr * _Point / bid) * 100.0f : 0.0f;

      // [1] ADX value normalised to [0,1] (max 100)
      features[1] = (float)(m_data.GetADXValue() / 100.0);

      // [2] Price vs SMA20 (signed distance in ATR units)
      double sma20 = m_data.GetSMA(20, 0);
      features[2] = (atr > 0) ? (float)((bid - sma20) / (atr * _Point)) : 0.0f;
      features[2] = MathMax(-3.0f, MathMin(3.0f, features[2])); // clamp

      // [3] RSI-14 normalised to [0,1]
      features[3] = (float)(m_data.GetRSI(14, 0) / 100.0);

      // [4] Hour of day normalised to [0,1]
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      features[4] = (float)dt.hour / 23.0f;

      // [5] Day of week normalised to [0,1] (0=Sun, 6=Sat)
      features[5] = (float)dt.day_of_week / 6.0f;

      // [6] Current spread in pips normalised to [0,1] (cap at 10 pips)
      double spreadPips = (SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point)
                          / (10.0 * _Point);
      features[6] = (float)MathMin(1.0, spreadPips);

      // [7] 1-bar return: (close[0] - close[1]) / ATR
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
        m_totalEpochs(0), m_lastLoss(0.0)
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

      // Clamp replay capacity to array size
      m_replayCapacity = MathMin(m_cfg.AI.ReplayBufferSize, 512);
      if(m_replayCapacity < m_cfg.AI.MinibatchSize)
        {
         m_replayCapacity = m_cfg.AI.MinibatchSize;
         Print("[AIManager] Init: ReplayBufferSize < MinibatchSize, clamped to ",
               m_replayCapacity);
        }

      // Try to load persisted weights; fallback to Xavier init
      if(!LoadWeights())
        {
         InitWeightsXavier();
         if(m_debugMode) Print("[AIManager] Xavier init (no saved weights found)");
        }
      return true;
     }

   virtual void Deinit() override
     {
      SaveWeights();
     }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_AI_TRAIN);
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_PRICE_UPDATE);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
     }

   // ─────────────────────────────────────────────────────────────────
   //  Hot path: OnPriceUpdate — forward pass ONLY
   //  [PHASE 7] NEVER call Backprop() here. Only:
   //    1. BuildFeatures()
   //    2. ForwardPass() → cache score
   //    3. PushExperience() if we have a label from a recent close
   // ─────────────────────────────────────────────────────────────────
   virtual void OnPriceUpdate() override
     {
      if(!m_cfg.AI.EnableAI) return;

      float features[];
      if(!BuildFeatures(features)) return;

      // Forward pass: just inference, no weight update
      float score = ForwardPass(features);

      // Cache the last score for GetSignalScore()
      m_lastScore = score;

      // Experience labelling is done AFTER trade close via OnTradeResult().
      // Here we only update the current inference score.
      (void)score; // suppress unused warning if m_lastScore not yet declared
     }

   // ─────────────────────────────────────────────────────────────────
   //  Bar boundary: OnNewBar — deferred backprop fires here
   //  [PHASE 7] This is the ONLY place Backprop() is allowed to run.
   // ─────────────────────────────────────────────────────────────────
   virtual void OnNewBar() override
     {
      if(!m_cfg.AI.EnableAI) return;
      m_barsSinceLastTrain++;

      // Gate: only train if pending AND interval elapsed AND buffer has samples
      if(!m_trainPending) return;
      if(m_barsSinceLastTrain < m_cfg.AI.TrainIntervalBars) return;
      if(m_replaySize < m_cfg.AI.MinibatchSize) return;

      // ─ Run one deferred backprop step
      m_lastLoss           = Backprop();
      m_trainPending       = false;
      m_barsSinceLastTrain = 0;
      m_totalEpochs++;

      if(m_debugMode)
         PrintFormat("[AIManager] Train epoch %d: loss=%.6f replay=%d",
                     m_totalEpochs, m_lastLoss, m_replaySize);

      // Periodic weight save (every 10 epochs)
      if(m_totalEpochs % 10 == 0) SaveWeights();

      // Dispatch AI_TRAIN event so orchestrator can log / update UI
      PASREvent ev;
      ev.id       = EVENT_ID_AI_TRAIN;
      ev.priority = 5;
      DispatchEvent(ev);
     }

   // Call from EA OnTradeTransaction when a position closes.
   // label = 1.0 if trade was profitable, 0.0 if loss.
   void OnTradeResult(const float &features[], float label, float weight = 1.0f)
     {
      if(!m_cfg.AI.EnableAI) return;
      if(m_replaySize >= m_replayCapacity && m_replayCapacity <= 0) return;

      AIExperience exp;
      ArrayCopy(exp.features, features, 0, 0, AI_INPUT_DIM);
      exp.label  = label;
      exp.weight = weight;
      PushExperience(exp);
     }

   // Query: is the current market signal above the confidence threshold?
   // Returns false if AI is disabled.
   bool IsSignalConfident() const
     {
      if(!m_cfg.AI.EnableAI) return true; // AI off → pass through
      return m_lastScore >= (float)m_cfg.AI.MinConfidence;
     }

   double GetLastLoss()       const { return m_lastLoss; }
   int    GetTotalEpochs()    const { return m_totalEpochs; }
   int    GetReplaySize()     const { return m_replaySize; }
   float  GetSignalScore()    const { return m_lastScore; }

   virtual void OnConfigReload() override
     {
      IManager::OnConfigReload();
      // Recalculate replay capacity after config change
      int newCap = MathMin(m_cfg.AI.ReplayBufferSize, 512);
      if(newCap != m_replayCapacity && m_debugMode)
         PrintFormat("[AIManager] ReplayCapacity changed %d -> %d", m_replayCapacity, newCap);
      m_replayCapacity = newCap;
     }

private:
   float m_lastScore;  // cached inference result from last OnPriceUpdate
  };

#endif // __AI_AIMANAGER_MQH__
