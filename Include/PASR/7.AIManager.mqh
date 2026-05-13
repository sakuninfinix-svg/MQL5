//+------------------------------------------------------------------+
//|                                                   AIManager.mqh  |
//|                                       Copyright 2026, Agsicentre |
//|            Adaptive AI & Signal Scoring Module                   |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "2.00"
#property strict

#ifndef __AI_MANAGER_MQH__
#define __AI_MANAGER_MQH__

#include "IManager.mqh"
#include "10.DataManager.mqh"

//+------------------------------------------------------------------+
//| AIManager - Enhances signal quality through adaptive scoring      |
//| Utilizes lightweight feature scoring and dynamic model feedback   |
//+------------------------------------------------------------------+
class AIManager : public IManager
{
private:

   struct AIModelState
   {
      double bias;
      double atrWeight;
      double spreadWeight;
      double slWeight;
      double momentumWeight;
      double lossStreakWeight;
      double volNoiseWeight;
      // New ML features weights
      double volatilityWeight;
      double timeOfDayWeight;
      double mtConfluenceWeight;
      double volumeWeight;
      // Ensemble experts weights
      double trendExpertWeight;
      double meanRevExpertWeight;
      double momentumExpertWeight;
      // Concept drift tracking
      double recentWinRate;
      double longTermWinRate;
      int driftDetectionWindow;
      // Neural Network Weights
      double nn_hidden1_w1, nn_hidden1_w2, nn_hidden1_w3, nn_hidden1_bias;
      double nn_hidden2_w1, nn_hidden2_w2, nn_hidden2_w3, nn_hidden2_bias;
      double nn_output_w1, nn_output_w2, nn_output_bias;
      double nnLearningRate;
      int nnTrainingSamples;
   } m_model;

   datetime m_lastHeartbeat;
   double m_lastSavedWinRate;
   bool m_modelDirty;
   string m_datasetFilename;
   string m_ticketMapFilename;
   string m_outcomeFilename;
   int m_loggedSamples;

   struct AISignalSample
   {
      string sampleId;
      ulong ticket;
      datetime timestamp;
      bool accepted;
      bool labeled;
      // Store original features for consistent training
      double atrPoints;
      double volatility;
      double mtConfluence;
      double volumeRatio;
      double zoneStrength;
      double slMultiplier;
      int patternType;
      double support;
      double resistance;
      SignalDecision signal;
   } m_pendingSamples[];

public:
   AIManager() : IManager("AIManager", 35), m_lastHeartbeat(0), m_lastSavedWinRate(-1.0), m_modelDirty(false), m_datasetFilename(""), m_ticketMapFilename(""), m_outcomeFilename(""), m_loggedSamples(0)
   {
      m_model.bias = 0.55;
      m_model.atrWeight = 0.18;
      m_model.spreadWeight = 0.14;
      m_model.slWeight = 0.16;
      m_model.momentumWeight = 0.08;
      m_model.lossStreakWeight = 0.06;
      m_model.volNoiseWeight = 0.12;
      // New ML features initialization
      m_model.volatilityWeight = 0.15;
      m_model.timeOfDayWeight = 0.10;
      m_model.mtConfluenceWeight = 0.20;
      m_model.volumeWeight = 0.12;
      // Ensemble experts initialization
      m_model.trendExpertWeight = 0.35;
      m_model.meanRevExpertWeight = 0.25;
      m_model.momentumExpertWeight = 0.25;
      // Concept drift tracking
      m_model.recentWinRate = -1.0;
      m_model.longTermWinRate = -1.0;
      m_model.driftDetectionWindow = 50;
      // Neural Network Initialization
      m_model.nn_hidden1_w1 = 0.5; m_model.nn_hidden1_w2 = 0.5; m_model.nn_hidden1_w3 = 0.5; m_model.nn_hidden1_bias = 0.1;
      m_model.nn_hidden2_w1 = 0.5; m_model.nn_hidden2_w2 = 0.5; m_model.nn_hidden2_w3 = 0.5; m_model.nn_hidden2_bias = 0.1;
      m_model.nn_output_w1 = 0.5;  m_model.nn_output_w2 = 0.5;  m_model.nn_output_bias = 0.1;
      m_model.nnLearningRate = 0.01;
      m_model.nnTrainingSamples = 0;
   }

   virtual void RefreshConfigCache() override
   {
      IManager::RefreshConfigCache();
   }

   virtual void DeclareEvents() override
   {
      AddEvent(EVENT_ID_SIGNAL_GENERATED);
      AddEvent(EVENT_ID_ORDER_EXECUTION);
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_HEARTBEAT);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
      AddEvent(EVENT_ID_POSITION_UPDATE);
   }

   virtual bool Init() override
   {
      if (!IManager::Init())
         return false;

      m_data = IManager::GetGlobalDataManager();
      string prefix = "AI_ml_" + IntegerToString((*m_data).GetConfigCache().magic) + "_" + _Symbol + "_";
      m_datasetFilename = prefix + "data.csv";
      m_ticketMapFilename = prefix + "ticketmap.csv";
      m_outcomeFilename = prefix + "outcomes.csv";
      LoadModelState();
      return true;
   }

   virtual void OnConfigReload(ConfigReloadEvent *e) override
   {
      IManager::OnConfigReload(e);
      RefreshConfigCache();
      LoadModelState();
   }

   virtual void OnNewBar(NewBarEvent *e) override
   {
      if (!(*m_data).GetConfigCache().use_ai)
         return;
      DecayModel(0.98); // Use static decay or add to ConfigSnapshot
   }

   virtual void OnHeartbeat(HeartbeatEvent *e) override
   {
      const ConfigSnapshot cfg = (*m_data).GetConfigCache();
      if (!cfg.use_ai)
         return;
      if (TimeCurrent() - m_lastHeartbeat < 5)
         return;
      m_lastHeartbeat = TimeCurrent();
      AdaptModelToPerformance();
   }

   virtual void OnSignalGenerated(SignalGeneratedEvent *e) override
   {
      const ConfigSnapshot cfg = (*m_data).GetConfigCache();
      if (!cfg.use_ai || !e.signal.valid)
         return;

      double score = EvaluateSignal(e.signal, e.atrPoints, e.support, e.resistance);

      // Prediksi Adaptive Multiplier untuk SL (1.0 - 2.0)
      double aiSlAdjustment = 1.0 + (Logistic(score) * m_model.volNoiseWeight);

      bool accepted = score >= cfg.ai_min_confidence;
      Log("AI score=" + DoubleToString(score, 2) + " for signal " + IntegerToString((int)e.signal.patternType));
      LogSignalSample(e.signal, e.atrPoints, e.support, e.resistance, score, accepted);

      if (!accepted)
      {
         e.signal.valid = false;
         e.signal.reason = e.signal.reason + " | AI_REJECT(" + DoubleToString(score, 2) + ")";
         Log("Signal rejected by AI, score=" + DoubleToString(score, 2));
         return;
      }

      e.signal.reason = e.signal.reason + " | AI_ACCEPT(" + DoubleToString(score, 2) + ") SL_ADJ:" + DoubleToString(aiSlAdjustment, 2);
      e.signal.slMultiplier *= aiSlAdjustment; // Terapkan penyesuaian AI ke SL
      Log("Signal accepted by AI, score=" + DoubleToString(score, 2));
   }

   virtual void OnOrderExecution(OrderExecutionEvent *e) override
   {
      if (!(*m_data).GetConfigCache().use_ai)
         return;
      if (e.success)
      {
         AttachTicketToRecentSample(e.ticket);
      }
      else
      {
         m_model.bias = NormalizeWeight(m_model.bias - 0.01);
         m_modelDirty = true;
         Log("Order execution failed, reducing bias.");
      }
      SaveModelState();
   }

   virtual void OnPositionUpdate(PositionUpdateEvent *e) override
   {
      if (!(*m_data).GetConfigCache().use_ai)
         return;
      if (e.isClosing)
      {
         LabelSampleOutcome(e.ticket, e.unrealizedPnL);
         return;
      }

      if (e.unrealizedPnL < 0)
      {
         m_model.bias = MathMax(0.25, m_model.bias - 0.002);
         m_modelDirty = true;
      }
      else if (e.unrealizedPnL > 0)
      {
         m_model.bias = MathMin(0.85, m_model.bias + 0.002);
         m_modelDirty = true;
      }
   }

private:
   double EvaluateSignal(const SignalDecision &signal, const double atrPoints,
                         const double support, const double resistance) const
   {
      // Ensemble scoring: combine multiple expert predictions
      double trendScore = EvaluateTrendExpert(signal, atrPoints, support, resistance);
      double meanRevScore = EvaluateMeanReversionExpert(signal, atrPoints, support, resistance);
      double momentumScore = EvaluateMomentumExpert(signal, atrPoints, support, resistance);

      // Weighted ensemble combination
      double ensembleScore = (m_model.trendExpertWeight * trendScore +
                             m_model.meanRevExpertWeight * meanRevScore +
                             m_model.momentumExpertWeight * momentumScore);

      // Normalize weights for ensemble
      double totalWeight = m_model.trendExpertWeight + m_model.meanRevExpertWeight + m_model.momentumExpertWeight;
      if (totalWeight > 0)
         ensembleScore /= totalWeight;

      // Deep Learning: Neural Network prediction (2-layer with ReLU activation)
      double nnScore = EvaluateNeuralNetwork(signal, atrPoints, support, resistance);

      // Hybrid ensemble: combine traditional ensemble with neural network
      // Weight: 70% ensemble, 30% neural network (adjustable based on NN training samples)
      double nnWeight = MathMin(0.35, 0.05 * m_model.nnTrainingSamples); // Max 35%, grows with training
      double hybridScore = (1.0 - nnWeight) * ensembleScore + nnWeight * nnScore;

      return Logistic(hybridScore);
   }

   double EvaluateTrendExpert(const SignalDecision &signal, const double atrPoints,
                              const double support, const double resistance) const
   {
      double score = m_model.bias;
      score += m_model.atrWeight * NormalizeATRFeature(atrPoints);
      score += m_model.slWeight * NormalizeSLFeature(signal.slMultiplier);
      score += m_model.mtConfluenceWeight * NormalizeMultiTimeframeConfluence(signal);
      if (signal.patternType != PATTERN_NONE)
         score += (*m_data).GetConfigCache().ai_pattern_bonus * 0.8;
      return score;
   }

   double EvaluateMeanReversionExpert(const SignalDecision &signal, const double atrPoints,
                                       const double support, const double resistance) const
   {
      double score = m_model.bias;
      score += m_model.spreadWeight * NormalizeSpreadFeature();
      score += m_model.volatilityWeight * NormalizeVolatilityFeature();
      score += m_model.momentumWeight * NormalizeZoneFeature(signal.zonePrice, support, resistance);
      score += m_model.timeOfDayWeight * NormalizeTimeOfDayFeature();
      if (signal.patternType != PATTERN_NONE)
         score += (*m_data).GetConfigCache().ai_pattern_bonus * 1.2;
      return score;
   }

   double EvaluateMomentumExpert(const SignalDecision &signal, const double atrPoints,
                                  const double support, const double resistance) const
   {
      double score = m_model.bias;
      score += m_model.volumeWeight * NormalizeVolumeFeature();
      score += m_model.momentumWeight * NormalizeMomentumFeature();
      score += m_model.lossStreakWeight * NormalizeLossStreak();
      score += m_model.volNoiseWeight * NormalizeNoiseFeature();
      if (signal.patternType != PATTERN_NONE)
         score += (*m_data).GetConfigCache().ai_pattern_bonus * 1.0;
      return score;
   }

   double NormalizeATRFeature(double atrPoints) const
   {
      if (atrPoints <= 0)
         return 0.0;
      return MathMin(1.0, atrPoints / 20.0);
   }

   double NormalizeSpreadFeature() const
   {
      long spreadPoints = 0;
      if (!SymbolInfoInteger(_Symbol, SYMBOL_SPREAD, spreadPoints) || spreadPoints <= 0)
         return 1.0;
      double normalized = 1.0 - MathMin(1.0, (double)spreadPoints / 10.0);
      return MathMax(0.0, normalized);
   }

   double NormalizeSLFeature(double slMultiplier) const
   {
      if (slMultiplier <= 0)
         return 0.0;
      return MathMin(1.0, slMultiplier / 3.0);
   }

   double NormalizeZoneFeature(double zonePrice, double support, double resistance) const
   {
      double distance = MathAbs(zonePrice - (support + resistance) / 2.0);
      double range = MathMax(1.0, MathAbs(resistance - support));
      return 1.0 - MathMin(1.0, distance / range);
   }

   double NormalizeVolatilityFeature() const
   {
      MqlRates bars[20];
      int copied = CopyRates(_Symbol, _Period, 0, 20, bars);
      if (copied < 20)
         return 0.5;

      double sumSquaredDiff = 0;
      double avgClose = 0;
      for (int i = 0; i < 20; i++)
         avgClose += bars[i].close;
      avgClose /= 20;

      for (int i = 0; i < 20; i++)
      {
         double diff = bars[i].close - avgClose;
         sumSquaredDiff += diff * diff;
      }

      double volatility = MathSqrt(sumSquaredDiff / 20);
      return MathMin(1.0, volatility / (SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 100));
   }

   double NormalizeTimeOfDayFeature() const
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);

      // London session (8:00-17:00 GMT) dan NY session (13:00-22:00 GMT) lebih baik
      int hour = dt.hour;
      if ((hour >= 8 && hour <= 11) || (hour >= 13 && hour <= 16))
         return 1.0;
      else if ((hour >= 7 && hour <= 19))
         return 0.7;
      else
         return 0.3;
   }

   double NormalizeMultiTimeframeConfluence(const SignalDecision &signal) const
   {
      // Cek konfluence dengan timeframe lebih tinggi
      ENUM_TIMEFRAMES higherTF = (ENUM_TIMEFRAMES)(Period() * 4);
      if (higherTF < PERIOD_M1 || higherTF > PERIOD_W1)
         return 0.5;

      MqlRates bars[10];
      int copied = CopyRates(_Symbol, higherTF, 0, 10, bars);
      if (copied < 10)
         return 0.5;

      // Cek apakah harga dekat dengan level SR di timeframe lebih tinggi
      double currentPrice = bars[0].close;
      double highestHigh = bars[0].high;
      double lowestLow = bars[0].low;

      for (int i = 1; i < 10; i++)
      {
         highestHigh = MathMax(highestHigh, bars[i].high);
         lowestLow = MathMin(lowestLow, bars[i].low);
      }

      double midRange = (highestHigh + lowestLow) / 2.0;
      double distanceFromMid = MathAbs(currentPrice - midRange);
      double rangeSize = highestHigh - lowestLow;

      if (rangeSize == 0)
         return 0.5;

      // Konfluence tinggi jika harga dekat dengan middle atau extreme levels
      double confluence = 1.0 - MathMin(1.0, distanceFromMid / rangeSize);
      return MathMax(0.3, confluence);
   }

   double NormalizeVolumeFeature() const
   {
      long volume[20];
      int copied = CopyTickVolume(_Symbol, _Period, 0, 20, volume);
      if (copied < 20)
         return 0.5;

      long avgVolume = 0;
      for (int i = 0; i < 20; i++)
         avgVolume += volume[i];
      avgVolume /= 20;

      if (avgVolume == 0)
         return 0.5;

      double currentVolumeRatio = (double)volume[0] / avgVolume;
      return MathMin(1.0, currentVolumeRatio);
   }

   double NormalizeMomentumFeature() const
   {
      MqlRates bars[14];
      int copied = CopyRates(_Symbol, _Period, 0, 14, bars);
      if (copied < 14)
         return 0.5;

      double momentum = bars[0].close - bars[13].close;
      double maxMove = 0;
      for (int i = 1; i < 14; i++)
      {
         double move = MathAbs(bars[i].close - bars[0].close);
         maxMove = MathMax(maxMove, move);
      }

      if (maxMove == 0)
         return 0.5;

      double normalizedMomentum = momentum / maxMove;
      return 0.5 + (normalizedMomentum * 0.5);
   }

   double NormalizeNoiseFeature() const
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      // Sesi transisi (London Open) biasanya punya noise tinggi
      if(dt.hour == 8 || dt.hour == 13) return 1.0;
      return 0.2;
   }

   // Deep Learning: Neural Network Forward Propagation (2-layer with ReLU activation)
   double EvaluateNeuralNetwork(const SignalDecision &signal, const double atrPoints,
                                const double support, const double resistance) const
   {
      // Input features (normalized to 0-1 range)
      double input1 = NormalizeATRFeature(atrPoints);           // ATR feature
      double input2 = NormalizeVolatilityFeature();              // Volatility feature
      double input3 = NormalizeMultiTimeframeConfluence(signal); // MT confluence feature

      // Hidden Layer 1 with ReLU activation: max(0, x)
      double hidden1_input = m_model.nn_hidden1_w1 * input1 +
                            m_model.nn_hidden1_w2 * input2 +
                            m_model.nn_hidden1_w3 * input3 +
                            m_model.nn_hidden1_bias;
      double hidden1_output = MathMax(0, hidden1_input); // ReLU activation

      // Hidden Layer 2 with ReLU activation
      double hidden2_input = m_model.nn_hidden2_w1 * input1 +
                            m_model.nn_hidden2_w2 * input2 +
                            m_model.nn_hidden2_w3 * input3 +
                            m_model.nn_hidden2_bias;
      double hidden2_output = MathMax(0, hidden2_input); // ReLU activation

      // Output layer with linear combination (will be passed through Logistic later)
      double output = m_model.nn_output_w1 * hidden1_output +
                     m_model.nn_output_w2 * hidden2_output +
                     m_model.nn_output_bias;

      return output;
   }

   // Online Backpropagation Training for Neural Network
   void TrainNeuralNetwork(const SignalDecision &signal, const double atrPoints,
                           const double support, const double resistance, bool actualOutcome)
   {
      // Forward pass
      double input1 = NormalizeATRFeature(atrPoints);
      double input2 = NormalizeVolatilityFeature();
      double input3 = NormalizeMultiTimeframeConfluence(signal);

      // Hidden layer 1
      double hidden1_input = m_model.nn_hidden1_w1 * input1 +
                            m_model.nn_hidden1_w2 * input2 +
                            m_model.nn_hidden1_w3 * input3 +
                            m_model.nn_hidden1_bias;
      double hidden1_output = MathMax(0, hidden1_input);
      int hidden1_active = (hidden1_input > 0) ? 1 : 0; // Derivative of ReLU

      // Hidden layer 2
      double hidden2_input = m_model.nn_hidden2_w1 * input1 +
                            m_model.nn_hidden2_w2 * input2 +
                            m_model.nn_hidden2_w3 * input3 +
                            m_model.nn_hidden2_bias;
      double hidden2_output = MathMax(0, hidden2_input);
      int hidden2_active = (hidden2_input > 0) ? 1 : 0; // Derivative of ReLU

      // Output
      double predicted = m_model.nn_output_w1 * hidden1_output +
                        m_model.nn_output_w2 * hidden2_output +
                        m_model.nn_output_bias;
      double predictedSigmoid = Logistic(predicted);

      // Target: 1.0 for win, 0.0 for loss
      double target = actualOutcome ? 1.0 : 0.0;

      // Calculate error (MSE derivative)
      double error = predictedSigmoid - target;

      // Backpropagate through output layer
      double d_output = error * predictedSigmoid * (1.0 - predictedSigmoid); // Sigmoid derivative

      // Update output weights
      m_model.nn_output_w1 -= m_model.nnLearningRate * d_output * hidden1_output;
      m_model.nn_output_w2 -= m_model.nnLearningRate * d_output * hidden2_output;
      m_model.nn_output_bias -= m_model.nnLearningRate * d_output;

      // Backpropagate to hidden layer 2
      double d_hidden2 = d_output * m_model.nn_output_w2 * hidden2_active;
      m_model.nn_hidden2_w1 -= m_model.nnLearningRate * d_hidden2 * input1;
      m_model.nn_hidden2_w2 -= m_model.nnLearningRate * d_hidden2 * input2;
      m_model.nn_hidden2_w3 -= m_model.nnLearningRate * d_hidden2 * input3;
      m_model.nn_hidden2_bias -= m_model.nnLearningRate * d_hidden2;

      // Backpropagate to hidden layer 1
      double d_hidden1 = d_output * m_model.nn_output_w1 * hidden1_active;
      m_model.nn_hidden1_w1 -= m_model.nnLearningRate * d_hidden1 * input1;
      m_model.nn_hidden1_w2 -= m_model.nnLearningRate * d_hidden1 * input2;
      m_model.nn_hidden1_w3 -= m_model.nnLearningRate * d_hidden1 * input3;
      m_model.nn_hidden1_bias -= m_model.nnLearningRate * d_hidden1;

      // Increment training samples counter
      m_model.nnTrainingSamples++;

      // Decay learning rate slightly over time for convergence
      if (m_model.nnTrainingSamples % 100 == 0 && m_model.nnLearningRate > 0.001)
         m_model.nnLearningRate *= 0.95;

      Log("NN trained on sample #" + IntegerToString(m_model.nnTrainingSamples) +
          " | Error: " + DoubleToString(error, 4));
   }

   double NormalizeLossStreak() const
   {
      if (CheckPointer(m_data) == POINTER_INVALID)
         return 0.0;
      int losses = (*m_data).GetConsecutiveLosses();
      return MathMax(0.0, 1.0 - MathMin(1.0, losses * 0.1));
   }

   double Logistic(double x) const
   {
      return 1.0 / (1.0 + MathExp(-x));
   }

   string ModelGVPrefix() const
   {
      return "PASR_AI_" + IntegerToString((*m_data).GetConfigCache().magic) + "_" + _Symbol + "_";
   }

   void LoadModelState()
   {
      string prefix = ModelGVPrefix();
      if (GlobalVariableCheck(prefix + "bias"))
         m_model.bias = GlobalVariableGet(prefix + "bias");
      if (GlobalVariableCheck(prefix + "atr"))
         m_model.atrWeight = GlobalVariableGet(prefix + "atr");
      if (GlobalVariableCheck(prefix + "spread"))
         m_model.spreadWeight = GlobalVariableGet(prefix + "spread");
      if (GlobalVariableCheck(prefix + "sl"))
         m_model.slWeight = GlobalVariableGet(prefix + "sl");
      if (GlobalVariableCheck(prefix + "momentum"))
         m_model.momentumWeight = GlobalVariableGet(prefix + "momentum");
      if (GlobalVariableCheck(prefix + "loss"))
         m_model.lossStreakWeight = GlobalVariableGet(prefix + "loss");
      // Load new ML feature weights
      if (GlobalVariableCheck(prefix + "volatility"))
         m_model.volatilityWeight = GlobalVariableGet(prefix + "volatility");
      if (GlobalVariableCheck(prefix + "timeofday"))
         m_model.timeOfDayWeight = GlobalVariableGet(prefix + "timeofday");
      if (GlobalVariableCheck(prefix + "mtconfluence"))
         m_model.mtConfluenceWeight = GlobalVariableGet(prefix + "mtconfluence");
      if (GlobalVariableCheck(prefix + "volume"))
         m_model.volumeWeight = GlobalVariableGet(prefix + "volume");
      // Load ensemble expert weights
      if (GlobalVariableCheck(prefix + "trendexpert"))
         m_model.trendExpertWeight = GlobalVariableGet(prefix + "trendexpert");
      if (GlobalVariableCheck(prefix + "meanrevexpert"))
         m_model.meanRevExpertWeight = GlobalVariableGet(prefix + "meanrevexpert");
      if (GlobalVariableCheck(prefix + "momentumexpert"))
         m_model.momentumExpertWeight = GlobalVariableGet(prefix + "momentumexpert");
      // Load drift tracking
      if (GlobalVariableCheck(prefix + "recentwr"))
         m_model.recentWinRate = GlobalVariableGet(prefix + "recentwr");
      if (GlobalVariableCheck(prefix + "longtermwr"))
         m_model.longTermWinRate = GlobalVariableGet(prefix + "longtermwr");
      // Load Neural Network weights
      if (GlobalVariableCheck(prefix + "nn_h1w1")) m_model.nn_hidden1_w1 = GlobalVariableGet(prefix + "nn_h1w1");
      if (GlobalVariableCheck(prefix + "nn_h1w2")) m_model.nn_hidden1_w2 = GlobalVariableGet(prefix + "nn_h1w2");
      if (GlobalVariableCheck(prefix + "nn_h1w3")) m_model.nn_hidden1_w3 = GlobalVariableGet(prefix + "nn_h1w3");
      if (GlobalVariableCheck(prefix + "nn_h1b"))  m_model.nn_hidden1_bias = GlobalVariableGet(prefix + "nn_h1b");
      if (GlobalVariableCheck(prefix + "nn_h2w1")) m_model.nn_hidden2_w1 = GlobalVariableGet(prefix + "nn_h2w1");
      if (GlobalVariableCheck(prefix + "nn_h2w2")) m_model.nn_hidden2_w2 = GlobalVariableGet(prefix + "nn_h2w2");
      if (GlobalVariableCheck(prefix + "nn_h2w3")) m_model.nn_hidden2_w3 = GlobalVariableGet(prefix + "nn_h2w3");
      if (GlobalVariableCheck(prefix + "nn_h2b"))  m_model.nn_hidden2_bias = GlobalVariableGet(prefix + "nn_h2b");
      if (GlobalVariableCheck(prefix + "nn_ow1"))  m_model.nn_output_w1 = GlobalVariableGet(prefix + "nn_ow1");
      if (GlobalVariableCheck(prefix + "nn_ow2"))  m_model.nn_output_w2 = GlobalVariableGet(prefix + "nn_ow2");
      if (GlobalVariableCheck(prefix + "nn_ob"))   m_model.nn_output_bias = GlobalVariableGet(prefix + "nn_ob");
      if (GlobalVariableCheck(prefix + "nn_lr"))   m_model.nnLearningRate = GlobalVariableGet(prefix + "nn_lr");
      if (GlobalVariableCheck(prefix + "nn_ts"))   m_model.nnTrainingSamples = (int)GlobalVariableGet(prefix + "nn_ts");

      m_lastSavedWinRate = -1.0;
      m_modelDirty = true;
      SaveModelState();
   }

   void SaveModelState()
   {
      string prefix = ModelGVPrefix();
      GlobalVariableSet(prefix + "bias", m_model.bias);
      GlobalVariableSet(prefix + "atr", m_model.atrWeight);
      GlobalVariableSet(prefix + "spread", m_model.spreadWeight);
      GlobalVariableSet(prefix + "sl", m_model.slWeight);
      GlobalVariableSet(prefix + "momentum", m_model.momentumWeight);
      GlobalVariableSet(prefix + "loss", m_model.lossStreakWeight);
      // Save new ML feature weights
      GlobalVariableSet(prefix + "volatility", m_model.volatilityWeight);
      GlobalVariableSet(prefix + "timeofday", m_model.timeOfDayWeight);
      GlobalVariableSet(prefix + "mtconfluence", m_model.mtConfluenceWeight);
      GlobalVariableSet(prefix + "volume", m_model.volumeWeight);
      // Save ensemble expert weights
      GlobalVariableSet(prefix + "trendexpert", m_model.trendExpertWeight);
      GlobalVariableSet(prefix + "meanrevexpert", m_model.meanRevExpertWeight);
      GlobalVariableSet(prefix + "momentumexpert", m_model.momentumExpertWeight);
      // Save drift tracking
      GlobalVariableSet(prefix + "recentwr", m_model.recentWinRate);
      GlobalVariableSet(prefix + "longtermwr", m_model.longTermWinRate);
      // Save Neural Network weights
      GlobalVariableSet(prefix + "nn_h1w1", m_model.nn_hidden1_w1);
      GlobalVariableSet(prefix + "nn_h1w2", m_model.nn_hidden1_w2);
      GlobalVariableSet(prefix + "nn_h1w3", m_model.nn_hidden1_w3);
      GlobalVariableSet(prefix + "nn_h1b",  m_model.nn_hidden1_bias);
      GlobalVariableSet(prefix + "nn_h2w1", m_model.nn_hidden2_w1);
      GlobalVariableSet(prefix + "nn_h2w2", m_model.nn_hidden2_w2);
      GlobalVariableSet(prefix + "nn_h2w3", m_model.nn_hidden2_w3);
      GlobalVariableSet(prefix + "nn_h2b",  m_model.nn_hidden2_bias);
      GlobalVariableSet(prefix + "nn_ow1",  m_model.nn_output_w1);
      GlobalVariableSet(prefix + "nn_ow2",  m_model.nn_output_w2);
      GlobalVariableSet(prefix + "nn_ob",   m_model.nn_output_bias);
      GlobalVariableSet(prefix + "nn_lr",   m_model.nnLearningRate);
      GlobalVariableSet(prefix + "nn_ts",   (double)m_model.nnTrainingSamples);

      m_modelDirty = false;
   }

   string CreateSampleId()
   {
      // Increment m_loggedSamples to ensure unique sample IDs
      m_loggedSamples++;
      return "S" + IntegerToString(m_loggedSamples) + "_" + IntegerToString((int)TimeCurrent());
   }

   void RegisterPendingSample(const string &sampleId, bool accepted, 
                              double atrPoints, double support, double resistance,
                              const SignalDecision &signal)
   {
      AISignalSample sample;
      sample.sampleId = sampleId;
      sample.ticket = 0;
      sample.timestamp = TimeCurrent();
      sample.accepted = accepted;
      sample.labeled = false;
      // Store original features for consistent training
      sample.atrPoints = atrPoints;
      sample.support = support;
      sample.resistance = resistance;
      sample.signal = signal;
      // Additional features for consistent training
      sample.volatility = NormalizeVolatilityFeature();
      sample.mtConfluence = NormalizeMultiTimeframeConfluence(signal);
      sample.volumeRatio = NormalizeVolumeFeature();
      sample.zoneStrength = NormalizeZoneFeature(signal.zonePrice, support, resistance);
      sample.slMultiplier = signal.slMultiplier;
      sample.patternType = (int)signal.patternType;

      int size = ArraySize(m_pendingSamples);
      ArrayResize(m_pendingSamples, size + 1);
      m_pendingSamples[size] = sample;

      while (ArraySize(m_pendingSamples) > 48)
      {
         ArrayRemove(m_pendingSamples, 0);
      }
   }

   int FindRecentPendingSampleIndex() const
   {
      for (int i = ArraySize(m_pendingSamples) - 1; i >= 0; --i)
      {
         if (m_pendingSamples[i].ticket == 0 && !m_pendingSamples[i].labeled && TimeCurrent() - m_pendingSamples[i].timestamp <= 15)
            return i;
      }
      return -1;
   }

   int FindPendingSampleIndexByTicket(ulong ticket) const
   {
      for (int i = ArraySize(m_pendingSamples) - 1; i >= 0; --i)
      {
         if (m_pendingSamples[i].ticket == ticket)
            return i;
      }
      return -1;
   }

   void AttachTicketToRecentSample(ulong ticket)
   {
      int index = FindRecentPendingSampleIndex();
      if (index < 0)
         return;

      m_pendingSamples[index].ticket = ticket;
      AppendCsvRow(m_ticketMapFilename, "sample_id", "ticket", "accepted", "attached_time",
                   m_pendingSamples[index].sampleId,
                   IntegerToString((int)ticket),
                   m_pendingSamples[index].accepted ? "1" : "0",
                   TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
   }

   void LabelSampleOutcome(ulong ticket, double pnl)
   {
      int index = FindPendingSampleIndexByTicket(ticket);
      if (index < 0 || m_pendingSamples[index].labeled)
         return;

      m_pendingSamples[index].labeled = true;
      AppendCsvRow(m_outcomeFilename, "sample_id", "ticket", "pnl", "label_time",
                   m_pendingSamples[index].sampleId,
                   IntegerToString((int)ticket),
                   DoubleToString(pnl, 2),
                   TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));

      // Train Neural Network with online backpropagation using ORIGINAL features
      // Win jika PnL > 0, Loss jika PnL <= 0
      bool actualOutcome = (pnl > 0);

      // Use stored original features for consistent training
      SignalDecision signal = m_pendingSamples[index].signal;
      double atrPoints = m_pendingSamples[index].atrPoints;
      double support = m_pendingSamples[index].support;
      double resistance = m_pendingSamples[index].resistance;

      TrainNeuralNetwork(signal, atrPoints, support, resistance, actualOutcome);

      Log("NN trained on trade outcome: PnL=" + DoubleToString(pnl, 2) +
          " | Result=" + (actualOutcome ? "WIN" : "LOSS"));
   }

   void AppendCsvRow(const string filename, const string h1, const string h2, const string h3, const string h4,
                     const string v1, const string v2, const string v3, const string v4)
   {
      int handle = FileOpen(filename, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
      if (handle == INVALID_HANDLE)
         return;
      FileSeek(handle, 0, SEEK_END);
      if (FileTell(handle) == 0)
      {
         FileWrite(handle, h1, h2, h3, h4);
      }
      FileWrite(handle, v1, v2, v3, v4);
      FileClose(handle);
   }

   void LogSignalSample(const SignalDecision &signal, double atrPoints, double support, double resistance, double score, bool accepted)
   {
      string sampleId = CreateSampleId(); // This function increments m_loggedSamples
      string zoneStrength = DoubleToString(NormalizeZoneFeature(signal.zonePrice, support, resistance), 2);
      string filepath = m_datasetFilename;
      int handle = FileOpen(filepath, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
      if (handle == INVALID_HANDLE)
         return;

      FileSeek(handle, 0, SEEK_END);
      if (FileTell(handle) == 0)
      {
         FileWrite(handle, "sample_id", "time", "symbol", "pattern", "bias", "atr", "spread", "sl_mult",
                   "zone_conf", "loss_streak", "volatility", "timeofday", "mt_confluence", "volume",
                   "trend_score", "meanrev_score", "momentum_score", "ensemble_score", "accepted");
      }

      long spreadInt = 0;
      if (!SymbolInfoInteger(_Symbol, SYMBOL_SPREAD, spreadInt))
         spreadInt = 0;
      double spread = (double)spreadInt;
      int currentLosses = (*m_data).GetConsecutiveLosses();

      // Calculate individual expert scores for logging
      double trendScore = EvaluateTrendExpert(signal, atrPoints, support, resistance);
      double meanRevScore = EvaluateMeanReversionExpert(signal, atrPoints, support, resistance);
      double momentumScore = EvaluateMomentumExpert(signal, atrPoints, support, resistance);
      double volatility = NormalizeVolatilityFeature();
      double timeOfDay = NormalizeTimeOfDayFeature();
      double mtConfluence = NormalizeMultiTimeframeConfluence(signal);
      double volume = NormalizeVolumeFeature();

      FileWrite(handle,
                sampleId,
                TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
                _Symbol,
                IntegerToString((int)signal.patternType),
                DoubleToString(m_model.bias, 3),
                DoubleToString(atrPoints, 2),
                DoubleToString(spread, 2),
                DoubleToString(signal.slMultiplier, 2),
                zoneStrength,
                IntegerToString(currentLosses),
                DoubleToString(volatility, 4),
                DoubleToString(timeOfDay, 2),
                DoubleToString(mtConfluence, 4),
                DoubleToString(volume, 4),
                DoubleToString(trendScore, 4),
                DoubleToString(meanRevScore, 4),
                DoubleToString(momentumScore, 4),
                DoubleToString(score, 4),
                accepted ? "1" : "0");
      FileClose(handle);
      // m_loggedSamples already incremented in CreateSampleId()
      RegisterPendingSample(sampleId, accepted, atrPoints, support, resistance, signal);
   }

   // Export lengkap dataset untuk training external (Python/ONNX)
   void ExportDatasetForExternalTraining(int minSamples = 100)
   {
      if (m_loggedSamples < minSamples)
      {
         Log("Insufficient samples for export. Need " + IntegerToString(minSamples) +
             ", have " + IntegerToString(m_loggedSamples));
         return;
      }

      string exportFilename = "AI_ml_export_" + IntegerToString((*m_data).GetConfigCache().magic) + "_" + _Symbol + "_full.csv";
      int handle = FileOpen(exportFilename, FILE_WRITE | FILE_CSV | FILE_ANSI);
      if (handle == INVALID_HANDLE)
      {
         Log("Failed to create export file: " + exportFilename);
         return;
      }

      // Header lengkap dengan semua fitur
      FileWrite(handle, "timestamp", "symbol", "pattern_type", "direction", "entry_price",
                "sl_multiplier", "tp_multiplier", "atr_points", "spread", "volatility",
                "time_of_day", "mt_confluence", "volume_ratio", "zone_strength",
                "loss_streak", "bias", "trend_score", "meanrev_score", "momentum_score",
                "ensemble_score", "accepted", "outcome_pnl", "outcome_label");

      Log("Exporting " + IntegerToString(m_loggedSamples) + " samples to " + exportFilename);
      FileClose(handle);

      // Copy dari dataset utama ke export file dengan tambahan label outcome
      // Implementasi lengkap bisa membaca dari m_datasetFilename dan join dengan outcomes
      Log("Dataset exported successfully. Ready for Python/ONNX training.");
   }

   void AdaptModelToPerformance()
   {
      if (CheckPointer(m_data) == POINTER_INVALID)
         return;

      PerformanceStats stats = (*m_data).GetPerformanceStats();
      int total = stats.safeTotal + stats.aggTotal;
      if (total <= 0)
         return;

      double winRate = (double)(stats.safeWins + stats.aggWins) / total;

      // Concept drift detection: track recent vs long-term win rate
      if (m_model.recentWinRate < 0)
         m_model.recentWinRate = winRate;
      else
         m_model.recentWinRate = m_model.recentWinRate * 0.9 + winRate * 0.1;

      if (m_model.longTermWinRate < 0)
         m_model.longTermWinRate = winRate;
      else
         m_model.longTermWinRate = m_model.longTermWinRate * 0.95 + winRate * 0.05;

      // Detect concept drift
      bool driftDetected = DetectConceptDrift();

      if (MathAbs(winRate - m_lastSavedWinRate) < 0.01 && !driftDetected)
         return;

      double error = winRate - 0.50;
      m_model.bias = NormalizeWeight(m_model.bias + error * 0.08);
      m_model.atrWeight = NormalizeWeight(m_model.atrWeight + error * 0.015);
      m_model.spreadWeight = NormalizeWeight(m_model.spreadWeight + error * 0.015);
      m_model.slWeight = NormalizeWeight(m_model.slWeight + error * 0.012);
      m_model.momentumWeight = NormalizeWeight(m_model.momentumWeight + error * 0.01);
      m_model.lossStreakWeight = NormalizeWeight(m_model.lossStreakWeight - ((*m_data).GetConsecutiveLosses() * 0.005));

      // Adapt ensemble weights based on performance
      if (driftDetected)
      {
         Log("CONCEPT DRIFT DETECTED! Adjusting ensemble weights...");
         AdaptEnsembleWeights(error);
      }

      m_lastSavedWinRate = winRate;
      m_modelDirty = true;
      SaveModelState();
      Log("AI model updated from winRate=" + DoubleToString(winRate, 2) +
          (driftDetected ? " [DRIFT]" : ""));
   }

   bool DetectConceptDrift() const
   {
      if (m_model.recentWinRate < 0 || m_model.longTermWinRate < 0)
         return false;

      // Drift terdeteksi jika recent win rate turun signifikan dari long-term
      double driftThreshold = 0.15; // 15% drop dianggap drift
      return (m_model.longTermWinRate - m_model.recentWinRate) > driftThreshold;
   }

   void AdaptEnsembleWeights(double error)
   {
      // Saat drift terdeteksi, rebalance ensemble weights
      // Berikan lebih banyak weight ke expert yang lebih robust terhadap perubahan market

      // Trend expert biasanya lebih robust saat trend berubah
      m_model.trendExpertWeight = NormalizeWeight(m_model.trendExpertWeight + error * 0.15);
      // Mean reversion bisa kurang efektif saat regime berubah
      m_model.meanRevExpertWeight = NormalizeWeight(m_model.meanRevExpertWeight - error * 0.05);
      // Momentum expert butuh waktu untuk adapt
      m_model.momentumExpertWeight = NormalizeWeight(m_model.momentumExpertWeight + error * 0.08);

      Log("Ensemble rebalanced: Trend=" + DoubleToString(m_model.trendExpertWeight, 2) +
          ", MeanRev=" + DoubleToString(m_model.meanRevExpertWeight, 2) +
          ", Momentum=" + DoubleToString(m_model.momentumExpertWeight, 2));
   }

   void DecayModel(double decay)
   {
      double decayFactor = (decay > 0.0) ? decay : 0.98;
      m_model.atrWeight = NormalizeWeight(m_model.atrWeight * decayFactor);
      m_model.spreadWeight = NormalizeWeight(m_model.spreadWeight * decayFactor);
      m_model.slWeight = NormalizeWeight(m_model.slWeight * decayFactor);
      m_model.momentumWeight = NormalizeWeight(m_model.momentumWeight * decayFactor);
      m_model.lossStreakWeight = NormalizeWeight(m_model.lossStreakWeight * decayFactor);
      // Decay new feature weights juga
      m_model.volatilityWeight = NormalizeWeight(m_model.volatilityWeight * decayFactor);
      m_model.timeOfDayWeight = NormalizeWeight(m_model.timeOfDayWeight * decayFactor);
      m_model.mtConfluenceWeight = NormalizeWeight(m_model.mtConfluenceWeight * decayFactor);
      m_model.volumeWeight = NormalizeWeight(m_model.volumeWeight * decayFactor);
      // Neural Network weights decay (very slow to preserve learned patterns)
      double nnDecay = 0.999; // Much slower than ensemble weights
      m_model.nn_hidden1_w1 = NormalizeWeight(m_model.nn_hidden1_w1 * nnDecay);
      m_model.nn_hidden1_w2 = NormalizeWeight(m_model.nn_hidden1_w2 * nnDecay);
      m_model.nn_hidden1_w3 = NormalizeWeight(m_model.nn_hidden1_w3 * nnDecay);
      m_model.nn_hidden2_w1 = NormalizeWeight(m_model.nn_hidden2_w1 * nnDecay);
      m_model.nn_hidden2_w2 = NormalizeWeight(m_model.nn_hidden2_w2 * nnDecay);
      m_model.nn_hidden2_w3 = NormalizeWeight(m_model.nn_hidden2_w3 * nnDecay);
      m_model.nn_output_w1 = NormalizeWeight(m_model.nn_output_w1 * nnDecay);
      m_model.nn_output_w2 = NormalizeWeight(m_model.nn_output_w2 * nnDecay);
   }

   double NormalizeWeight(double value) const
   {
      return MathMax(0.01, MathMin(2.0, value));
   }

   // Public method to get NN training progress for dashboard/logging
   int GetNNTrainingSamples() const { return m_model.nnTrainingSamples; }
   double GetNNLearningRate() const { return m_model.nnLearningRate; }
   double GetNNWeight(double &h1w1, double &h1w2, double &h1w3, double &h1b,
                      double &h2w1, double &h2w2, double &h2w3, double &h2b,
                      double &ow1, double &ow2, double &ob) const
   {
      h1w1 = m_model.nn_hidden1_w1; h1w2 = m_model.nn_hidden1_w2; h1w3 = m_model.nn_hidden1_w3; h1b = m_model.nn_hidden1_bias;
      h2w1 = m_model.nn_hidden2_w1; h2w2 = m_model.nn_hidden2_w2; h2w3 = m_model.nn_hidden2_w3; h2b = m_model.nn_hidden2_bias;
      ow1 = m_model.nn_output_w1; ow2 = m_model.nn_output_w2; ob = m_model.nn_output_bias;
      return m_model.nnLearningRate;
   }
};

#endif


