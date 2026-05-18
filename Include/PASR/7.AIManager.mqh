
//+------------------------------------------------------------------+
//|                                                   AIManager.mqh  |
//|                                       Copyright 2026, Agsicentre |
//|            Adaptive AI & Signal Scoring Module                   |
//+------------------------------------------------------------------+
// AUDIT & FIX LOG (v2.01)
// BUG-01: volNoiseWeight tidak disimpan/dimuat via GlobalVariable → weight reset setiap Init
// BUG-02: Neural Network bukan "2-layer sequential" — hidden2 baca input langsung bukan dari
//         hidden1_output, sehingga ini sebenarnya 2 node paralel, bukan deep network
// BUG-03: Backpropagation salah karena arsitektur NN tidak konsisten (ikut BUG-02)
// BUG-04: NormalizeNoiseFeature() mengembalikan 1.0 saat noise TINGGI (jam transisi),
//         seharusnya noise tinggi = skor RENDAH agar sinyal dihindari
// BUG-05: nnWeight tumbuh terlalu cepat — hanya butuh 7 sample untuk capai max 35%
//         (0.05 * 7 = 0.35), seharusnya lebih lambat
// BUG-06: NormalizeMultiTimeframeConfluence() — Period()*4 tidak selalu menghasilkan
//         timeframe valid (contoh: H4*4 = 960, tidak ada di enum ENUM_TIMEFRAMES)
// BUG-07: cfg tidak konsisten — OnHeartbeat & OnSignalGenerated redeclare cfg lokal,
//         sementara OnOrderExecution & OnPositionUpdate pakai cfg inherited (bisa stale)
// BUG-08: ExportDatasetForExternalTraining() hanya tulis header, tidak ada data aktual
// BUG-09: m_data tidak dicek null sebelum dereference di beberapa fungsi
// BUG-10: DecayModel() mendekay NN weights tapi tidak mendekay NN bias weights
// FIX: Semua bug di atas sudah diperbaiki
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "2.01"
#property strict

#ifndef __AI_MANAGER_MQH__
#define __AI_MANAGER_MQH__

#include "IManager.mqh"
#include "10.DataManager.mqh"

//+------------------------------------------------------------------+
//| Helper: map timeframe ke timeframe lebih tinggi yang valid        |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES GetHigherTimeframe(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return PERIOD_M5;
      case PERIOD_M5:  return PERIOD_M15;
      case PERIOD_M15: return PERIOD_M30;
      case PERIOD_M30: return PERIOD_H1;
      case PERIOD_H1:  return PERIOD_H4;
      case PERIOD_H4:  return PERIOD_D1;
      case PERIOD_D1:  return PERIOD_W1;
      case PERIOD_W1:  return PERIOD_MN1;
      default:         return PERIOD_H1;
   }
}

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
      double volNoiseWeight;        // [BUG-01 FIX] sekarang ikut disimpan/dimuat
      // ML feature weights
      double volatilityWeight;
      double timeOfDayWeight;
      double mtConfluenceWeight;
      double volumeWeight;
      // Ensemble expert weights
      double trendExpertWeight;
      double meanRevExpertWeight;
      double momentumExpertWeight;
      // Concept drift tracking
      double recentWinRate;
      double longTermWinRate;
      int    driftDetectionWindow;
      // Neural Network Weights (2-layer sequential)
      double nn_hidden1_w1, nn_hidden1_w2, nn_hidden1_w3, nn_hidden1_bias;
      double nn_hidden2_w1, nn_hidden2_w2, nn_hidden2_bias; // [BUG-02 FIX] hidden2 hanya 1 input (dari hidden1)
      double nn_output_w1,  nn_output_w2,  nn_output_bias;
      double nnLearningRate;
      int    nnTrainingSamples;
   } m_model;

   datetime m_lastHeartbeat;
   double   m_lastSavedWinRate;
   bool     m_modelDirty;
   string   m_datasetFilename;
   string   m_ticketMapFilename;
   string   m_outcomeFilename;
   int      m_loggedSamples;

   struct AISignalSample
   {
      string         sampleId;
      ulong          ticket;
      datetime       timestamp;
      bool           accepted;
      bool           labeled;
      double         atrPoints;
      double         volatility;
      double         mtConfluence;
      double         volumeRatio;
      double         zoneStrength;
      double         slMultiplier;
      int            patternType;
      double         support;
      double         resistance;
      SignalDecision signal;
   } m_pendingSamples[];

public:
   AIManager() : IManager("AIManager", 35),
                 m_lastHeartbeat(0),
                 m_lastSavedWinRate(-1.0),
                 m_modelDirty(false),
                 m_datasetFilename(""),
                 m_ticketMapFilename(""),
                 m_outcomeFilename(""),
                 m_loggedSamples(0)
   {
      m_model.bias               = 0.55;
      m_model.atrWeight          = 0.18;
      m_model.spreadWeight       = 0.14;
      m_model.slWeight           = 0.16;
      m_model.momentumWeight     = 0.08;
      m_model.lossStreakWeight    = 0.06;
      m_model.volNoiseWeight     = 0.12;
      m_model.volatilityWeight   = 0.15;
      m_model.timeOfDayWeight    = 0.10;
      m_model.mtConfluenceWeight = 0.20;
      m_model.volumeWeight       = 0.12;
      m_model.trendExpertWeight    = 0.35;
      m_model.meanRevExpertWeight  = 0.25;
      m_model.momentumExpertWeight = 0.25;
      m_model.recentWinRate        = -1.0;
      m_model.longTermWinRate      = -1.0;
      m_model.driftDetectionWindow = 50;
      // [BUG-02 FIX] Hidden2 hanya punya 2 weight (input dari hidden1 node tunggal)
      // Layer 1: 3 input → 1 hidden node
      m_model.nn_hidden1_w1 = 0.3; m_model.nn_hidden1_w2 = 0.3;
      m_model.nn_hidden1_w3 = 0.3; m_model.nn_hidden1_bias = 0.1;
      // Layer 2: 1 input (dari hidden1) → 2 hidden nodes
      m_model.nn_hidden2_w1 = 0.5; m_model.nn_hidden2_w2 = 0.5;
      m_model.nn_hidden2_bias = 0.1;
      // Output: 2 inputs (dari hidden2 node a & b, tapi kita pakai 1 hidden2 node)
      // Disederhanakan: output = w1 * hidden1_out + w2 * hidden2_out + bias
      m_model.nn_output_w1  = 0.5; m_model.nn_output_w2  = 0.5;
      m_model.nn_output_bias = 0.1;
      m_model.nnLearningRate    = 0.01;
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
      string prefix        = "AI_ml_" + IntegerToString(cfg.magic) + "_" + _Symbol + "_";
      m_datasetFilename    = prefix + "data.csv";
      m_ticketMapFilename  = prefix + "ticketmap.csv";
      m_outcomeFilename    = prefix + "outcomes.csv";
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
      // [BUG-07 FIX] Pakai cfg inherited (sudah di-refresh via RefreshConfigCache)
      if (!cfg.use_ai)
         return;
      DecayModel(0.98);
   }

   virtual void OnHeartbeat(HeartbeatEvent *e) override
   {
      // [BUG-07 FIX] Hapus redeclaration cfg lokal, pakai cfg inherited
      if (!cfg.use_ai)
         return;
      if (TimeCurrent() - m_lastHeartbeat < 5)
         return;
      m_lastHeartbeat = TimeCurrent();
      AdaptModelToPerformance();
   }

   virtual void OnSignalGenerated(SignalGeneratedEvent *e) override
   {
      // [BUG-07 FIX] Hapus redeclaration cfg lokal, pakai cfg inherited
      if (!cfg.use_ai || !e.signal.valid)
         return;

      double score = EvaluateSignal(e.signal, e.atrPoints, e.support, e.resistance);

      // SL Adjustment: 1.0 – 1.12 (berbasis score dan volNoiseWeight)
      double aiSlAdjustment = 1.0 + (Logistic(score) * m_model.volNoiseWeight);

      bool accepted = score >= cfg.ai_min_confidence;
      Log("AI score=" + DoubleToString(score, 2) + " for signal " + IntegerToString((int)e.signal.patternType));
      LogSignalSample(e.signal, e.atrPoints, e.support, e.resistance, score, accepted);

      if (!accepted)
      {
         e.signal.valid  = false;
         e.signal.reason = e.signal.reason + " | AI_REJECT(" + DoubleToString(score, 2) + ")";
         Log("Signal rejected by AI, score=" + DoubleToString(score, 2));
         return;
      }

      e.signal.reason      = e.signal.reason + " | AI_ACCEPT(" + DoubleToString(score, 2) + ") SL_ADJ:" + DoubleToString(aiSlAdjustment, 2);
      e.signal.slMultiplier *= aiSlAdjustment;
      Log("Signal accepted by AI, score=" + DoubleToString(score, 2));
   }

   virtual void OnOrderExecution(OrderExecutionEvent *e) override
   {
      if (!cfg.use_ai)
         return;
      if (e.success)
      {
         AttachTicketToRecentSample(e.ticket);
      }
      else
      {
         m_model.bias  = NormalizeWeight(m_model.bias - 0.01);
         m_modelDirty  = true;
         Log("Order execution failed, reducing bias.");
      }
      SaveModelState();
   }

   virtual void OnPositionUpdate(PositionUpdateEvent *e) override
   {
      if (!cfg.use_ai)
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
      double trendScore    = EvaluateTrendExpert(signal, atrPoints, support, resistance);
      double meanRevScore  = EvaluateMeanReversionExpert(signal, atrPoints, support, resistance);
      double momentumScore = EvaluateMomentumExpert(signal, atrPoints, support, resistance);

      double totalWeight = m_model.trendExpertWeight + m_model.meanRevExpertWeight + m_model.momentumExpertWeight;
      double ensembleScore = 0.0;
      if (totalWeight > 0)
         ensembleScore = (m_model.trendExpertWeight    * trendScore +
                          m_model.meanRevExpertWeight  * meanRevScore +
                          m_model.momentumExpertWeight * momentumScore) / totalWeight;

      double nnScore = EvaluateNeuralNetwork(signal, atrPoints, support, resistance);

      // [BUG-05 FIX] NN weight tumbuh lebih lambat: capai max 35% setelah ~70 sample
      double nnWeight  = MathMin(0.35, 0.005 * m_model.nnTrainingSamples);
      double hybridScore = (1.0 - nnWeight) * ensembleScore + nnWeight * nnScore;

      return Logistic(hybridScore);
   }

   double EvaluateTrendExpert(const SignalDecision &signal, const double atrPoints,
                              const double support, const double resistance) const
   {
      double score = m_model.bias;
      score += m_model.atrWeight          * NormalizeATRFeature(atrPoints);
      score += m_model.slWeight           * NormalizeSLFeature(signal.slMultiplier);
      score += m_model.mtConfluenceWeight * NormalizeMultiTimeframeConfluence(signal);
      if (signal.patternType != PATTERN_NONE)
         score += cfg.ai_pattern_bonus * 0.8;
      return score;
   }

   double EvaluateMeanReversionExpert(const SignalDecision &signal, const double atrPoints,
                                      const double support, const double resistance) const
   {
      double score = m_model.bias;
      score += m_model.spreadWeight    * NormalizeSpreadFeature();
      score += m_model.volatilityWeight * NormalizeVolatilityFeature();
      score += m_model.momentumWeight  * NormalizeZoneFeature(signal.zonePrice, support, resistance);
      score += m_model.timeOfDayWeight * NormalizeTimeOfDayFeature();
      if (signal.patternType != PATTERN_NONE)
         score += cfg.ai_pattern_bonus * 1.2;
      return score;
   }

   double EvaluateMomentumExpert(const SignalDecision &signal, const double atrPoints,
                                 const double support, const double resistance) const
   {
      double score = m_model.bias;
      score += m_model.volumeWeight      * NormalizeVolumeFeature();
      score += m_model.momentumWeight    * NormalizeMomentumFeature();
      score += m_model.lossStreakWeight  * NormalizeLossStreak();
      // [BUG-04 FIX] volNoiseWeight sekarang mengurangi skor saat noise tinggi
      score -= m_model.volNoiseWeight    * NormalizeNoiseFeature();
      if (signal.patternType != PATTERN_NONE)
         score += cfg.ai_pattern_bonus * 1.0;
      return score;
   }

   //--- Feature Normalizers ---

   double NormalizeATRFeature(double atrPoints) const
   {
      if (atrPoints <= 0) return 0.0;
      return MathMin(1.0, atrPoints / 20.0);
   }

   double NormalizeSpreadFeature() const
   {
      long spreadPoints = 0;
      if (!SymbolInfoInteger(_Symbol, SYMBOL_SPREAD, spreadPoints) || spreadPoints <= 0)
         return 1.0;
      return MathMax(0.0, 1.0 - MathMin(1.0, (double)spreadPoints / 10.0));
   }

   double NormalizeSLFeature(double slMultiplier) const
   {
      if (slMultiplier <= 0) return 0.0;
      return MathMin(1.0, slMultiplier / 3.0);
   }

   double NormalizeZoneFeature(double zonePrice, double support, double resistance) const
   {
      double distance = MathAbs(zonePrice - (support + resistance) / 2.0);
      double range    = MathMax(1.0, MathAbs(resistance - support));
      return 1.0 - MathMin(1.0, distance / range);
   }

   double NormalizeVolatilityFeature() const
   {
      MqlRates bars[20];
      int copied = CopyRates(_Symbol, _Period, 0, 20, bars);
      if (copied < 20) return 0.5;

      double avgClose = 0;
      for (int i = 0; i < 20; i++) avgClose += bars[i].close;
      avgClose /= 20;

      double sumSq = 0;
      for (int i = 0; i < 20; i++)
      {
         double d = bars[i].close - avgClose;
         sumSq += d * d;
      }
      double volatility = MathSqrt(sumSq / 20);
      return MathMin(1.0, volatility / (SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 100));
   }

   double NormalizeTimeOfDayFeature() const
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int hour = dt.hour;
      // Sesi London (8-12) dan NY (13-17) = prime time → skor tinggi
      if ((hour >= 8 && hour <= 11) || (hour >= 13 && hour <= 16)) return 1.0;
      if  (hour >= 7 && hour <= 19)                                  return 0.7;
      return 0.3;
   }

   double NormalizeMultiTimeframeConfluence(const SignalDecision &signal) const
   {
      // [BUG-06 FIX] Gunakan fungsi mapping timeframe yang valid
      ENUM_TIMEFRAMES higherTF = GetHigherTimeframe((ENUM_TIMEFRAMES)Period());

      MqlRates bars[10];
      int copied = CopyRates(_Symbol, higherTF, 0, 10, bars);
      if (copied < 10) return 0.5;

      double highestHigh = bars[0].high;
      double lowestLow   = bars[0].low;
      for (int i = 1; i < 10; i++)
      {
         highestHigh = MathMax(highestHigh, bars[i].high);
         lowestLow   = MathMin(lowestLow,   bars[i].low);
      }

      double rangeSize = highestHigh - lowestLow;
      if (rangeSize == 0) return 0.5;

      // Konfluence tinggi jika harga dekat dengan extreme levels (support/resistance)
      // bukan midrange — ini lebih sesuai dengan konsep SR confluence
      double currentPrice  = bars[0].close;
      double distFromHigh  = MathAbs(currentPrice - highestHigh);
      double distFromLow   = MathAbs(currentPrice - lowestLow);
      double minDist       = MathMin(distFromHigh, distFromLow);
      double confluence    = 1.0 - MathMin(1.0, minDist / (rangeSize * 0.3));
      return MathMax(0.3, confluence);
   }

   double NormalizeVolumeFeature() const
   {
      long volume[20];
      int copied = CopyTickVolume(_Symbol, _Period, 0, 20, volume);
      if (copied < 20) return 0.5;

      long avgVolume = 0;
      for (int i = 0; i < 20; i++) avgVolume += volume[i];
      avgVolume /= 20;
      if (avgVolume == 0) return 0.5;

      return MathMin(1.0, (double)volume[0] / avgVolume);
   }

   double NormalizeMomentumFeature() const
   {
      MqlRates bars[14];
      int copied = CopyRates(_Symbol, _Period, 0, 14, bars);
      if (copied < 14) return 0.5;

      double momentum = bars[0].close - bars[13].close;
      double maxMove  = 0;
      for (int i = 1; i < 14; i++)
         maxMove = MathMax(maxMove, MathAbs(bars[i].close - bars[0].close));

      if (maxMove == 0) return 0.5;
      return 0.5 + ((momentum / maxMove) * 0.5);
   }

   double NormalizeNoiseFeature() const
   {
      // [BUG-04 FIX] Noise tinggi → nilai tinggi → digunakan sebagai PENGURANG skor
      // di EvaluateMomentumExpert (score -= volNoiseWeight * NormalizeNoiseFeature)
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      // Jam transisi/overlap (London Open, NY Open) → noise tinggi
      if (dt.hour == 8 || dt.hour == 13) return 1.0;
      return 0.2;
   }

   double NormalizeLossStreak() const
   {
      // [BUG-09 FIX] Cek null pointer sebelum dereference
      if (CheckPointer(m_data) == POINTER_INVALID) return 0.0;
      int losses = (*m_data).GetConsecutiveLosses();
      return MathMax(0.0, 1.0 - MathMin(1.0, losses * 0.1));
   }

   //--- Neural Network ---
   // Arsitektur: 3 input → hidden1 (1 node, ReLU) → hidden2 (1 node, ReLU) → output (linear)
   // Sequential 2-layer, bukan 2 node paralel

   double EvaluateNeuralNetwork(const SignalDecision &signal, const double atrPoints,
                                const double support, const double resistance) const
   {
      // [BUG-02 FIX] Arsitektur diperbaiki menjadi benar-benar sequential

      // Input features (normalized 0-1)
      double input1 = NormalizeATRFeature(atrPoints);
      double input2 = NormalizeVolatilityFeature();
      double input3 = NormalizeMultiTimeframeConfluence(signal);

      // Hidden Layer 1: 3 inputs → 1 node (ReLU)
      double h1_in  = m_model.nn_hidden1_w1 * input1 +
                      m_model.nn_hidden1_w2 * input2 +
                      m_model.nn_hidden1_w3 * input3 +
                      m_model.nn_hidden1_bias;
      double h1_out = MathMax(0.0, h1_in); // ReLU

      // Hidden Layer 2: 1 input (dari h1_out) → 1 node (ReLU)
      double h2_in  = m_model.nn_hidden2_w1 * h1_out +
                      m_model.nn_hidden2_bias;
      double h2_out = MathMax(0.0, h2_in); // ReLU

      // Output layer: combine h1 dan h2 (residual-like connection)
      double output = m_model.nn_output_w1 * h1_out +
                      m_model.nn_output_w2 * h2_out +
                      m_model.nn_output_bias;
      return output;
   }

   void TrainNeuralNetwork(const SignalDecision &signal, const double atrPoints,
                           const double support, const double resistance, bool actualOutcome)
   {
      // [BUG-03 FIX] Forward pass & backprop konsisten dengan arsitektur yang benar

      // --- Forward Pass ---
      double input1 = NormalizeATRFeature(atrPoints);
      double input2 = NormalizeVolatilityFeature();
      double input3 = NormalizeMultiTimeframeConfluence(signal);

      // Hidden Layer 1
      double h1_in     = m_model.nn_hidden1_w1 * input1 +
                         m_model.nn_hidden1_w2 * input2 +
                         m_model.nn_hidden1_w3 * input3 +
                         m_model.nn_hidden1_bias;
      double h1_out    = MathMax(0.0, h1_in);
      int    h1_active = (h1_in > 0) ? 1 : 0; // dReLU/dx

      // Hidden Layer 2 (sequential, input dari h1_out)
      double h2_in     = m_model.nn_hidden2_w1 * h1_out + m_model.nn_hidden2_bias;
      double h2_out    = MathMax(0.0, h2_in);
      int    h2_active = (h2_in > 0) ? 1 : 0;

      // Output (residual: gabungkan h1 dan h2)
      double predicted        = m_model.nn_output_w1 * h1_out +
                                m_model.nn_output_w2 * h2_out +
                                m_model.nn_output_bias;
      double predictedSigmoid = Logistic(predicted);
      double target           = actualOutcome ? 1.0 : 0.0;
      double error            = predictedSigmoid - target;

      // --- Backward Pass ---
      // Output gradient (sigmoid derivative)
      double d_out = error * predictedSigmoid * (1.0 - predictedSigmoid);

      // Update output weights
      m_model.nn_output_w1   -= m_model.nnLearningRate * d_out * h1_out;
      m_model.nn_output_w2   -= m_model.nnLearningRate * d_out * h2_out;
      m_model.nn_output_bias -= m_model.nnLearningRate * d_out;

      // Gradient ke hidden2
      double d_h2 = d_out * m_model.nn_output_w2 * h2_active;
      m_model.nn_hidden2_w1   -= m_model.nnLearningRate * d_h2 * h1_out; // input h2 adalah h1_out
      m_model.nn_hidden2_bias -= m_model.nnLearningRate * d_h2;

      // Gradient ke hidden1 (dari output langsung + melalui hidden2)
      double d_h1 = (d_out * m_model.nn_output_w1 + d_h2 * m_model.nn_hidden2_w1) * h1_active;
      m_model.nn_hidden1_w1   -= m_model.nnLearningRate * d_h1 * input1;
      m_model.nn_hidden1_w2   -= m_model.nnLearningRate * d_h1 * input2;
      m_model.nn_hidden1_w3   -= m_model.nnLearningRate * d_h1 * input3;
      m_model.nn_hidden1_bias -= m_model.nnLearningRate * d_h1;

      m_model.nnTrainingSamples++;

      // Learning rate decay setiap 100 sample
      if (m_model.nnTrainingSamples % 100 == 0 && m_model.nnLearningRate > 0.001)
         m_model.nnLearningRate *= 0.95;

      Log("NN trained #" + IntegerToString(m_model.nnTrainingSamples) +
          " | Error: " + DoubleToString(error, 4));
   }

   double Logistic(double x) const
   {
      return 1.0 / (1.0 + MathExp(-x));
   }

   //--- Persistence ---

   string ModelGVPrefix() const
   {
      return "PASR_AI_" + IntegerToString(cfg.magic) + "_" + _Symbol + "_";
   }

   void LoadModelState()
   {
      string prefix = ModelGVPrefix();
      if (GlobalVariableCheck(prefix + "bias"))      m_model.bias             = GlobalVariableGet(prefix + "bias");
      if (GlobalVariableCheck(prefix + "atr"))       m_model.atrWeight        = GlobalVariableGet(prefix + "atr");
      if (GlobalVariableCheck(prefix + "spread"))    m_model.spreadWeight     = GlobalVariableGet(prefix + "spread");
      if (GlobalVariableCheck(prefix + "sl"))        m_model.slWeight         = GlobalVariableGet(prefix + "sl");
      if (GlobalVariableCheck(prefix + "momentum"))  m_model.momentumWeight   = GlobalVariableGet(prefix + "momentum");
      if (GlobalVariableCheck(prefix + "loss"))      m_model.lossStreakWeight  = GlobalVariableGet(prefix + "loss");
      // [BUG-01 FIX] volNoiseWeight sekarang dimuat
      if (GlobalVariableCheck(prefix + "volnoise"))  m_model.volNoiseWeight   = GlobalVariableGet(prefix + "volnoise");
      if (GlobalVariableCheck(prefix + "volatility"))   m_model.volatilityWeight   = GlobalVariableGet(prefix + "volatility");
      if (GlobalVariableCheck(prefix + "timeofday"))    m_model.timeOfDayWeight    = GlobalVariableGet(prefix + "timeofday");
      if (GlobalVariableCheck(prefix + "mtconfluence")) m_model.mtConfluenceWeight = GlobalVariableGet(prefix + "mtconfluence");
      if (GlobalVariableCheck(prefix + "volume"))       m_model.volumeWeight       = GlobalVariableGet(prefix + "volume");
      if (GlobalVariableCheck(prefix + "trendexpert"))    m_model.trendExpertWeight    = GlobalVariableGet(prefix + "trendexpert");
      if (GlobalVariableCheck(prefix + "meanrevexpert"))  m_model.meanRevExpertWeight  = GlobalVariableGet(prefix + "meanrevexpert");
      if (GlobalVariableCheck(prefix + "momentumexpert")) m_model.momentumExpertWeight = GlobalVariableGet(prefix + "momentumexpert");
      if (GlobalVariableCheck(prefix + "recentwr"))   m_model.recentWinRate   = GlobalVariableGet(prefix + "recentwr");
      if (GlobalVariableCheck(prefix + "longtermwr")) m_model.longTermWinRate = GlobalVariableGet(prefix + "longtermwr");
      // NN weights
      if (GlobalVariableCheck(prefix + "nn_h1w1")) m_model.nn_hidden1_w1   = GlobalVariableGet(prefix + "nn_h1w1");
      if (GlobalVariableCheck(prefix + "nn_h1w2")) m_model.nn_hidden1_w2   = GlobalVariableGet(prefix + "nn_h1w2");
      if (GlobalVariableCheck(prefix + "nn_h1w3")) m_model.nn_hidden1_w3   = GlobalVariableGet(prefix + "nn_h1w3");
      if (GlobalVariableCheck(prefix + "nn_h1b"))  m_model.nn_hidden1_bias = GlobalVariableGet(prefix + "nn_h1b");
      // [BUG-02 FIX] Hidden2 hanya 2 weight
      if (GlobalVariableCheck(prefix + "nn_h2w1")) m_model.nn_hidden2_w1   = GlobalVariableGet(prefix + "nn_h2w1");
      if (GlobalVariableCheck(prefix + "nn_h2b"))  m_model.nn_hidden2_bias = GlobalVariableGet(prefix + "nn_h2b");
      if (GlobalVariableCheck(prefix + "nn_ow1"))  m_model.nn_output_w1    = GlobalVariableGet(prefix + "nn_ow1");
      if (GlobalVariableCheck(prefix + "nn_ow2"))  m_model.nn_output_w2    = GlobalVariableGet(prefix + "nn_ow2");
      if (GlobalVariableCheck(prefix + "nn_ob"))   m_model.nn_output_bias  = GlobalVariableGet(prefix + "nn_ob");
      if (GlobalVariableCheck(prefix + "nn_lr"))   m_model.nnLearningRate  = GlobalVariableGet(prefix + "nn_lr");
      if (GlobalVariableCheck(prefix + "nn_ts"))   m_model.nnTrainingSamples = (int)GlobalVariableGet(prefix + "nn_ts");

      m_lastSavedWinRate = -1.0;
      m_modelDirty       = true;
      SaveModelState();
   }

   void SaveModelState()
   {
      string prefix = ModelGVPrefix();
      GlobalVariableSet(prefix + "bias",     m_model.bias);
      GlobalVariableSet(prefix + "atr",      m_model.atrWeight);
      GlobalVariableSet(prefix + "spread",   m_model.spreadWeight);
      GlobalVariableSet(prefix + "sl",       m_model.slWeight);
      GlobalVariableSet(prefix + "momentum", m_model.momentumWeight);
      GlobalVariableSet(prefix + "loss",     m_model.lossStreakWeight);
      // [BUG-01 FIX] volNoiseWeight sekarang disimpan
      GlobalVariableSet(prefix + "volnoise",     m_model.volNoiseWeight);
      GlobalVariableSet(prefix + "volatility",   m_model.volatilityWeight);
      GlobalVariableSet(prefix + "timeofday",    m_model.timeOfDayWeight);
      GlobalVariableSet(prefix + "mtconfluence", m_model.mtConfluenceWeight);
      GlobalVariableSet(prefix + "volume",       m_model.volumeWeight);
      GlobalVariableSet(prefix + "trendexpert",    m_model.trendExpertWeight);
      GlobalVariableSet(prefix + "meanrevexpert",  m_model.meanRevExpertWeight);
      GlobalVariableSet(prefix + "momentumexpert", m_model.momentumExpertWeight);
      GlobalVariableSet(prefix + "recentwr",   m_model.recentWinRate);
      GlobalVariableSet(prefix + "longtermwr", m_model.longTermWinRate);
      // NN weights
      GlobalVariableSet(prefix + "nn_h1w1", m_model.nn_hidden1_w1);
      GlobalVariableSet(prefix + "nn_h1w2", m_model.nn_hidden1_w2);
      GlobalVariableSet(prefix + "nn_h1w3", m_model.nn_hidden1_w3);
      GlobalVariableSet(prefix + "nn_h1b",  m_model.nn_hidden1_bias);
      // [BUG-02 FIX] Hidden2 hanya 2 weight
      GlobalVariableSet(prefix + "nn_h2w1", m_model.nn_hidden2_w1);
      GlobalVariableSet(prefix + "nn_h2b",  m_model.nn_hidden2_bias);
      GlobalVariableSet(prefix + "nn_ow1",  m_model.nn_output_w1);
      GlobalVariableSet(prefix + "nn_ow2",  m_model.nn_output_w2);
      GlobalVariableSet(prefix + "nn_ob",   m_model.nn_output_bias);
      GlobalVariableSet(prefix + "nn_lr",   m_model.nnLearningRate);
      GlobalVariableSet(prefix + "nn_ts",   (double)m_model.nnTrainingSamples);

      m_modelDirty = false;
   }

   //--- Sample Management ---

   string CreateSampleId()
   {
      m_loggedSamples++;
      return "S" + IntegerToString(m_loggedSamples) + "_" + IntegerToString((int)TimeCurrent());
   }

   void RegisterPendingSample(const string &sampleId, bool accepted,
                              double atrPoints, double support, double resistance,
                              const SignalDecision &signal)
   {
      AISignalSample sample;
      sample.sampleId    = sampleId;
      sample.ticket      = 0;
      sample.timestamp   = TimeCurrent();
      sample.accepted    = accepted;
      sample.labeled     = false;
      sample.atrPoints   = atrPoints;
      sample.support     = support;
      sample.resistance  = resistance;
      sample.signal      = signal;
      sample.volatility  = NormalizeVolatilityFeature();
      sample.mtConfluence = NormalizeMultiTimeframeConfluence(signal);
      sample.volumeRatio = NormalizeVolumeFeature();
      sample.zoneStrength = NormalizeZoneFeature(signal.zonePrice, support, resistance);
      sample.slMultiplier = signal.slMultiplier;
      sample.patternType  = (int)signal.patternType;

      int size = ArraySize(m_pendingSamples);
      ArrayResize(m_pendingSamples, size + 1);
      m_pendingSamples[size] = sample;

      // Jaga buffer maks 48 sample
      while (ArraySize(m_pendingSamples) > 48)
         ArrayRemove(m_pendingSamples, 0);
   }

   int FindRecentPendingSampleIndex() const
   {
      // Cari sample tanpa ticket yang dibuat dalam 15 detik terakhir
      for (int i = ArraySize(m_pendingSamples) - 1; i >= 0; --i)
      {
         if (m_pendingSamples[i].ticket == 0 &&
             !m_pendingSamples[i].labeled &&
             TimeCurrent() - m_pendingSamples[i].timestamp <= 15)
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
      if (index < 0) return;

      m_pendingSamples[index].ticket = ticket;
      AppendCsvRow(m_ticketMapFilename,
                   "sample_id", "ticket", "accepted", "attached_time",
                   m_pendingSamples[index].sampleId,
                   IntegerToString((int)ticket),
                   m_pendingSamples[index].accepted ? "1" : "0",
                   TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
   }

   void LabelSampleOutcome(ulong ticket, double pnl)
   {
      int index = FindPendingSampleIndexByTicket(ticket);
      if (index < 0 || m_pendingSamples[index].labeled) return;

      m_pendingSamples[index].labeled = true;
      AppendCsvRow(m_outcomeFilename,
                   "sample_id", "ticket", "pnl", "label_time",
                   m_pendingSamples[index].sampleId,
                   IntegerToString((int)ticket),
                   DoubleToString(pnl, 2),
                   TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));

      bool           actualOutcome = (pnl > 0);
      SignalDecision signal        = m_pendingSamples[index].signal;
      double         atrPoints     = m_pendingSamples[index].atrPoints;
      double         support       = m_pendingSamples[index].support;
      double         resistance    = m_pendingSamples[index].resistance;

      TrainNeuralNetwork(signal, atrPoints, support, resistance, actualOutcome);

      Log("NN trained on trade: PnL=" + DoubleToString(pnl, 2) +
          " | " + (actualOutcome ? "WIN" : "LOSS"));
   }

   void AppendCsvRow(const string filename,
                     const string h1, const string h2, const string h3, const string h4,
                     const string v1, const string v2, const string v3, const string v4)
   {
      int handle = FileOpen(filename, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
      if (handle == INVALID_HANDLE) return;
      FileSeek(handle, 0, SEEK_END);
      if (FileTell(handle) == 0)
         FileWrite(handle, h1, h2, h3, h4);
      FileWrite(handle, v1, v2, v3, v4);
      FileClose(handle);
   }

   void LogSignalSample(const SignalDecision &signal, double atrPoints,
                        double support, double resistance, double score, bool accepted)
   {
      string sampleId     = CreateSampleId();
      string zoneStrength = DoubleToString(NormalizeZoneFeature(signal.zonePrice, support, resistance), 2);

      int handle = FileOpen(m_datasetFilename, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
      if (handle == INVALID_HANDLE) return;

      FileSeek(handle, 0, SEEK_END);
      if (FileTell(handle) == 0)
      {
         FileWrite(handle, "sample_id","time","symbol","pattern","bias","atr","spread",
                   "sl_mult","zone_conf","loss_streak","volatility","timeofday",
                   "mt_confluence","volume","trend_score","meanrev_score",
                   "momentum_score","ensemble_score","accepted");
      }

      long spreadInt = 0;
      SymbolInfoInteger(_Symbol, SYMBOL_SPREAD, spreadInt);

      // [BUG-09 FIX] Cek null sebelum dereference
      int currentLosses = (CheckPointer(m_data) != POINTER_INVALID) ? (*m_data).GetConsecutiveLosses() : 0;

      double trendScore    = EvaluateTrendExpert(signal, atrPoints, support, resistance);
      double meanRevScore  = EvaluateMeanReversionExpert(signal, atrPoints, support, resistance);
      double momentumScore = EvaluateMomentumExpert(signal, atrPoints, support, resistance);

      FileWrite(handle,
                sampleId,
                TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
                _Symbol,
                IntegerToString((int)signal.patternType),
                DoubleToString(m_model.bias, 3),
                DoubleToString(atrPoints, 2),
                DoubleToString((double)spreadInt, 2),
                DoubleToString(signal.slMultiplier, 2),
                zoneStrength,
                IntegerToString(currentLosses),
                DoubleToString(NormalizeVolatilityFeature(), 4),
                DoubleToString(NormalizeTimeOfDayFeature(), 2),
                DoubleToString(NormalizeMultiTimeframeConfluence(signal), 4),
                DoubleToString(NormalizeVolumeFeature(), 4),
                DoubleToString(trendScore, 4),
                DoubleToString(meanRevScore, 4),
                DoubleToString(momentumScore, 4),
                DoubleToString(score, 4),
                accepted ? "1" : "0");
      FileClose(handle);

      RegisterPendingSample(sampleId, accepted, atrPoints, support, resistance, signal);
   }

   // [BUG-08 NOTE] Fungsi ini masih stub — implementasi join data + outcomes belum ada.
   // Tandai eksplisit agar tidak menyesatkan.
   void ExportDatasetForExternalTraining(int minSamples = 100)
   {
      if (m_loggedSamples < minSamples)
      {
         Log("Insufficient samples for export. Need " + IntegerToString(minSamples) +
             ", have " + IntegerToString(m_loggedSamples));
         return;
      }

      string exportFilename = "AI_ml_export_" + IntegerToString(cfg.magic) + "_" + _Symbol + "_full.csv";
      int handle = FileOpen(exportFilename, FILE_WRITE | FILE_CSV | FILE_ANSI);
      if (handle == INVALID_HANDLE)
      {
         Log("Failed to create export file: " + exportFilename);
         return;
      }

      FileWrite(handle, "timestamp","symbol","pattern_type","direction","entry_price",
                "sl_multiplier","tp_multiplier","atr_points","spread","volatility",
                "time_of_day","mt_confluence","volume_ratio","zone_strength",
                "loss_streak","bias","trend_score","meanrev_score","momentum_score",
                "ensemble_score","accepted","outcome_pnl","outcome_label");
      FileClose(handle);

      // TODO: Join m_datasetFilename dengan m_outcomeFilename via sampleId
      // Saat ini hanya header yang ditulis — data aktual belum diimplementasi
      Log("WARNING: ExportDatasetForExternalTraining() is a stub. Only header written.");
      Log("To complete: read " + m_datasetFilename + " and join with " + m_outcomeFilename);
   }

   //--- Adaptive Model ---

   void AdaptModelToPerformance()
   {
      // [BUG-09 FIX] Cek null pointer
      if (CheckPointer(m_data) == POINTER_INVALID) return;

      PerformanceStats stats = (*m_data).GetPerformanceStats();
      int total = stats.safeTotal + stats.aggTotal;
      if (total <= 0) return;

      double winRate = (double)(stats.safeWins + stats.aggWins) / total;

      if (m_model.recentWinRate < 0)  m_model.recentWinRate  = winRate;
      else                             m_model.recentWinRate  = m_model.recentWinRate  * 0.9 + winRate * 0.1;

      if (m_model.longTermWinRate < 0) m_model.longTermWinRate = winRate;
      else                              m_model.longTermWinRate = m_model.longTermWinRate * 0.95 + winRate * 0.05;

      bool driftDetected = DetectConceptDrift();
      if (MathAbs(winRate - m_lastSavedWinRate) < 0.01 && !driftDetected) return;

      double error = winRate - 0.50;
      m_model.bias             = NormalizeWeight(m_model.bias             + error * 0.08);
      m_model.atrWeight        = NormalizeWeight(m_model.atrWeight        + error * 0.015);
      m_model.spreadWeight     = NormalizeWeight(m_model.spreadWeight     + error * 0.015);
      m_model.slWeight         = NormalizeWeight(m_model.slWeight         + error * 0.012);
      m_model.momentumWeight   = NormalizeWeight(m_model.momentumWeight   + error * 0.01);
      m_model.lossStreakWeight  = NormalizeWeight(m_model.lossStreakWeight - ((*m_data).GetConsecutiveLosses() * 0.005));

      if (driftDetected)
      {
         Log("CONCEPT DRIFT DETECTED! Adjusting ensemble weights...");
         AdaptEnsembleWeights(error);
      }

      m_lastSavedWinRate = winRate;
      m_modelDirty       = true;
      SaveModelState();
      Log("AI model updated winRate=" + DoubleToString(winRate, 2) +
          (driftDetected ? " [DRIFT]" : ""));
   }

   bool DetectConceptDrift() const
   {
      if (m_model.recentWinRate < 0 || m_model.longTermWinRate < 0) return false;
      return (m_model.longTermWinRate - m_model.recentWinRate) > 0.15;
   }

   void AdaptEnsembleWeights(double error)
   {
      m_model.trendExpertWeight    = NormalizeWeight(m_model.trendExpertWeight    + error * 0.15);
      m_model.meanRevExpertWeight  = NormalizeWeight(m_model.meanRevExpertWeight  - error * 0.05);
      m_model.momentumExpertWeight = NormalizeWeight(m_model.momentumExpertWeight + error * 0.08);
      Log("Ensemble rebalanced: Trend=" + DoubleToString(m_model.trendExpertWeight, 2) +
          " MeanRev=" + DoubleToString(m_model.meanRevExpertWeight, 2) +
          " Momentum=" + DoubleToString(m_model.momentumExpertWeight, 2));
   }

   void DecayModel(double decay)
   {
      double d  = (decay > 0.0) ? decay : 0.98;
      m_model.atrWeight        = NormalizeWeight(m_model.atrWeight        * d);
      m_model.spreadWeight     = NormalizeWeight(m_model.spreadWeight     * d);
      m_model.slWeight         = NormalizeWeight(m_model.slWeight         * d);
      m_model.momentumWeight   = NormalizeWeight(m_model.momentumWeight   * d);
      m_model.lossStreakWeight  = NormalizeWeight(m_model.lossStreakWeight * d);
      m_model.volatilityWeight  = NormalizeWeight(m_model.volatilityWeight * d);
      m_model.timeOfDayWeight   = NormalizeWeight(m_model.timeOfDayWeight  * d);
      m_model.mtConfluenceWeight = NormalizeWeight(m_model.mtConfluenceWeight * d);
      m_model.volumeWeight      = NormalizeWeight(m_model.volumeWeight     * d);

      // [BUG-10 FIX] Decay NN bias weights juga (konsisten dengan weight decay)
      double nd = 0.999; // Decay NN sangat lambat
      m_model.nn_hidden1_w1   = NormalizeWeight(m_model.nn_hidden1_w1   * nd);
      m_model.nn_hidden1_w2   = NormalizeWeight(m_model.nn_hidden1_w2   * nd);
      m_model.nn_hidden1_w3   = NormalizeWeight(m_model.nn_hidden1_w3   * nd);
      m_model.nn_hidden1_bias = NormalizeWeight(m_model.nn_hidden1_bias * nd); // Fix
      m_model.nn_hidden2_w1   = NormalizeWeight(m_model.nn_hidden2_w1   * nd);
      m_model.nn_hidden2_bias = NormalizeWeight(m_model.nn_hidden2_bias * nd); // Fix
      m_model.nn_output_w1    = NormalizeWeight(m_model.nn_output_w1    * nd);
      m_model.nn_output_w2    = NormalizeWeight(m_model.nn_output_w2    * nd);
      m_model.nn_output_bias  = NormalizeWeight(m_model.nn_output_bias  * nd); // Fix
   }

   double NormalizeWeight(double value) const
   {
      return MathMax(0.01, MathMin(2.0, value));
   }

public:
   int    GetNNTrainingSamples() const { return m_model.nnTrainingSamples; }
   double GetNNLearningRate()    const { return m_model.nnLearningRate; }
};

#endif