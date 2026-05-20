//+------------------------------------------------------------------+
//|                                                   AIManager.mqh  |
//|                                       Copyright 2026, Agsicentre |
//|            Adaptive AI & Signal Scoring Module                   |
//|                   VERSION 2.03 - MarketRegime Integration        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "2.03"
#property strict

#ifndef __AI_MANAGER_MQH__
#define __AI_MANAGER_MQH__

#include "IManager.mqh"
#include "10.DataManager.mqh"
#include "12.MarketRegime.mqh"

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
//| v2.03: MarketRegimeFilter integrated — no duplicate indicators   |
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
      // ML feature weights
      double regimeScoreWeight;     // [v2.03] ganti volatilityWeight → pakai regime score
      double timeOfDayWeight;
      double mtConfluenceWeight;    // [v2.03] ganti mtConfluence manual → pakai MarketRegime
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
      double nn_hidden2_w1, nn_hidden2_bias;
      double nn_output_w1,  nn_output_w2,  nn_output_bias;
      double nnLearningRate;
      int    nnTrainingSamples;
      // Safety & validation
      bool   initialized;
      datetime lastUpdateTime;
      int    validationCounter;
   } m_model;

   datetime         m_lastHeartbeat;
   double           m_lastSavedWinRate;
   bool             m_modelDirty;
   string           m_datasetFilename;
   string           m_ticketMapFilename;
   string           m_outcomeFilename;
   int              m_loggedSamples;

   // [v2.03] MarketRegimeFilter injection — TIDAK buat instance baru,
   // pointer ke instance yang sudah ada di EA utama
   MarketRegimeFilter *m_regime;

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

   // [v2.03] EvalContext: cache semua feature normalization per signal evaluation
   // untuk menghindari redundant CopyRates() berganda
   struct EvalContext
   {
      double atrNorm;
      double spreadNorm;
      double slNorm;
      double regimeScore;       // dari MarketRegimeFilter.GetRegimeScore()
      double volatilityScore;   // dari MarketRegimeFilter.GetVolatilityScore()
      double timeOfDayNorm;
      double mtConfluenceNorm;  // dari MarketRegimeFilter.GetResult().regimeScore
      double volumeNorm;
      double momentumNorm;
      double zoneNorm;
      double lossStreakNorm;
      double noiseNorm;
   };

public:
   AIManager() : IManager("AIManager", 35),
                 m_lastHeartbeat(0),
                 m_lastSavedWinRate(-1.0),
                 m_modelDirty(false),
                 m_datasetFilename(""),
                 m_ticketMapFilename(""),
                 m_outcomeFilename(""),
                 m_loggedSamples(0),
                 m_regime(NULL)
   {
      // Initialize model with safe defaults
      m_model.bias               = 0.55;
      m_model.atrWeight          = 0.18;
      m_model.spreadWeight       = 0.14;
      m_model.slWeight           = 0.16;
      m_model.momentumWeight     = 0.08;
      m_model.lossStreakWeight    = 0.06;
      m_model.volNoiseWeight     = 0.12;
      m_model.regimeScoreWeight  = 0.15;  // [v2.03] bobot regime score dari MarketRegimeFilter
      m_model.timeOfDayWeight    = 0.10;
      m_model.mtConfluenceWeight = 0.20;
      m_model.volumeWeight       = 0.12;
      m_model.trendExpertWeight    = 0.35;
      m_model.meanRevExpertWeight  = 0.25;
      m_model.momentumExpertWeight = 0.25;
      m_model.recentWinRate        = -1.0;
      m_model.longTermWinRate      = -1.0;
      m_model.driftDetectionWindow = 50;
      // Neural Network: Layer 1 (3 inputs → 1 node, ReLU)
      m_model.nn_hidden1_w1 = 0.3; m_model.nn_hidden1_w2 = 0.3;
      m_model.nn_hidden1_w3 = 0.3; m_model.nn_hidden1_bias = 0.1;
      // Layer 2: 1 input (dari hidden1) → 1 node (ReLU)
      m_model.nn_hidden2_w1 = 0.5; m_model.nn_hidden2_bias = 0.1;
      // Output layer: combine h1 dan h2 (residual-like connection)
      m_model.nn_output_w1  = 0.5; m_model.nn_output_w2  = 0.5;
      m_model.nn_output_bias = 0.1;
      m_model.nnLearningRate    = 0.01;
      m_model.nnTrainingSamples = 0;
      // Safety fields
      m_model.initialized       = true;
      m_model.lastUpdateTime    = TimeCurrent();
      m_model.validationCounter = 0;
   }

   // [v2.03] Inject pointer MarketRegimeFilter dari EA utama
   // Panggil ini sebelum Init(), mirip pola SetDataManager()
   void SetRegimeFilter(MarketRegimeFilter *regime)
   {
      m_regime = regime;
      Log("✅ MarketRegimeFilter injected.");
   }

   MarketRegimeFilter* GetRegimeFilter() const { return m_regime; }

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
      
      if (CheckPointer(m_data) == POINTER_INVALID)
      {
         Log("❌ CRITICAL: DataManager is NULL during AIManager initialization");
         return false;
      }

      // [v2.03] Peringatan jika regime filter belum di-inject
      if (CheckPointer(m_regime) == POINTER_INVALID)
         Log("⚠️ WARNING: MarketRegimeFilter not injected. Call SetRegimeFilter() before Init() for best results.");
      
      string prefix        = "AI_ml_" + IntegerToString(cfg.magic) + "_" + _Symbol + "_";
      m_datasetFilename    = prefix + "data.csv";
      m_ticketMapFilename  = prefix + "ticketmap.csv";
      m_outcomeFilename    = prefix + "outcomes.csv";
      
      LoadModelState();
      
      Log("✅ AIManager v2.03 initialized. NN samples: " + IntegerToString(m_model.nnTrainingSamples));
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
      if (!cfg.use_ai)
         return;

      // [v2.03] Update regime filter setiap bar baru (jika tersedia)
      if (CheckPointer(m_regime) != POINTER_INVALID)
         m_regime.Update();

      DecayModel(0.98);
   }

   virtual void OnHeartbeat(HeartbeatEvent *e) override
   {
      if (!cfg.use_ai)
         return;
      if (TimeCurrent() - m_lastHeartbeat < 5)
         return;
      m_lastHeartbeat = TimeCurrent();
      AdaptModelToPerformance();
   }

   virtual void OnSignalGenerated(SignalGeneratedEvent *e) override
   {
      if (CheckPointer(e) == POINTER_INVALID)
      {
         Log("⚠️ OnSignalGenerated: NULL event pointer");
         return;
      }
      
      if (!cfg.use_ai || !e.signal.valid)
         return;

      // [v2.03] Build EvalContext sekali, dipakai oleh semua expert evaluator
      EvalContext ctx;
      BuildEvalContext(ctx, e.signal, e.atrPoints, e.support, e.resistance);

      double score = EvaluateSignal(e.signal, e.atrPoints, e.support, e.resistance, ctx);

      // SL Adjustment: 1.0 – 1.12 (berbasis score dan volNoiseWeight)
      double aiSlAdjustment = 1.0 + (Logistic(score) * m_model.volNoiseWeight);

      // [v2.03] Threshold dinamis dari MarketRegimeFilter, bukan flat cfg.ai_min_confidence
      double dynamicThreshold = GetDynamicThreshold();
      bool accepted = score >= dynamicThreshold;

      Log("AI score=" + DoubleToString(score, 2) +
          " threshold=" + DoubleToString(dynamicThreshold, 2) +
          " for signal " + IntegerToString((int)e.signal.patternType));
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
      if (CheckPointer(e) == POINTER_INVALID)
      {
         Log("⚠️ OnOrderExecution: NULL event pointer");
         return;
      }
      
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
      if (CheckPointer(e) == POINTER_INVALID)
      {
         Log("⚠️ OnPositionUpdate: NULL event pointer");
         return;
      }
      
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

   //+------------------------------------------------------------------+
   //| [v2.03] BuildEvalContext: hitung semua feature sekali saja        |
   //| Menghindari redundant CopyRates() di setiap expert evaluator      |
   //+------------------------------------------------------------------+
   void BuildEvalContext(EvalContext &ctx,
                         const SignalDecision &signal, const double atrPoints,
                         const double support, const double resistance) const
   {
      ctx.atrNorm      = NormalizeATRFeature(atrPoints);
      ctx.spreadNorm   = NormalizeSpreadFeature();
      ctx.slNorm       = NormalizeSLFeature(signal.slMultiplier);
      ctx.timeOfDayNorm = NormalizeTimeOfDayFeature();
      ctx.volumeNorm   = NormalizeVolumeFeature();
      ctx.momentumNorm = NormalizeMomentumFeature();
      ctx.zoneNorm     = NormalizeZoneFeature(signal.zonePrice, support, resistance);
      ctx.lossStreakNorm = NormalizeLossStreak();
      ctx.noiseNorm    = NormalizeNoiseFeature();

      // [v2.03] Regime & volatility: pakai MarketRegimeFilter jika tersedia
      if (CheckPointer(m_regime) != POINTER_INVALID)
      {
         const RegimeResult &r = m_regime.GetResult();
         ctx.regimeScore      = r.regimeScore;          // ADX-based 0-1 dari MarketRegimeFilter
         ctx.volatilityScore  = r.volatilityScore;      // ATR ratio-based 0-1
         ctx.mtConfluenceNorm = r.mtfConfirmed ? 1.0 : (double)r.tfAlignment / 3.0;
      }
      else
      {
         // Fallback: hitung manual hanya jika regime filter tidak tersedia
         ctx.regimeScore      = NormalizeVolatilityFeatureFallback();
         ctx.volatilityScore  = ctx.regimeScore;
         ctx.mtConfluenceNorm = NormalizeMultiTimeframeConfluenceFallback(signal);
      }
   }

   // [v2.03] Threshold dinamis: pakai MarketRegimeFilter.GetDynamicThreshold()
   // Jika filter tidak tersedia, fallback ke cfg.ai_min_confidence
   double GetDynamicThreshold() const
   {
      if (CheckPointer(m_regime) != POINTER_INVALID)
         return m_regime.GetDynamicThreshold(cfg.ai_min_confidence);
      return cfg.ai_min_confidence;
   }

   double EvaluateSignal(const SignalDecision &signal, const double atrPoints,
                         const double support, const double resistance,
                         const EvalContext &ctx) const
   {
      double trendScore    = EvaluateTrendExpert(signal, ctx);
      double meanRevScore  = EvaluateMeanReversionExpert(signal, ctx);
      double momentumScore = EvaluateMomentumExpert(ctx);

      // [v2.03] Bias ensemble per regime — tanpa indikator baru
      double tW = m_model.trendExpertWeight;
      double mW = m_model.meanRevExpertWeight;
      double moW = m_model.momentumExpertWeight;

      if (CheckPointer(m_regime) != POINTER_INVALID)
      {
         switch(m_regime.GetMarketRegime())
         {
            case REGIME_TRENDING_STRONG:
               tW  *= 1.20; mW  *= 0.80; break;
            case REGIME_TRENDING_WEAK:
               tW  *= 1.10; mW  *= 0.90; break;
            case REGIME_RANGING_SIDEWAYS:
               tW  *= 0.80; mW  *= 1.25; break;
            case REGIME_CHOPPY_HIGH_VOL:
               tW  *= 0.70; mW  *= 0.80; moW *= 0.70; break;
            case REGIME_TRANSITION:
               tW  *= 0.60; mW  *= 0.60; moW *= 0.60; break;
            default: break;
         }
      }

      double totalWeight = tW + mW + moW;
      double ensembleScore = 0.0;
      if (totalWeight > 0)
         ensembleScore = (tW * trendScore + mW * meanRevScore + moW * momentumScore) / totalWeight;

      double nnScore = EvaluateNeuralNetwork(ctx);

      // NN weight tumbuh lambat: max 35% setelah ~70 sample
      double nnWeight  = MathMin(0.35, 0.005 * m_model.nnTrainingSamples);
      double hybridScore = (1.0 - nnWeight) * ensembleScore + nnWeight * nnScore;

      return Logistic(hybridScore);
   }

   double EvaluateTrendExpert(const SignalDecision &signal, const EvalContext &ctx) const
   {
      double score = m_model.bias;
      score += m_model.atrWeight          * ctx.atrNorm;
      score += m_model.slWeight           * ctx.slNorm;
      score += m_model.mtConfluenceWeight * ctx.mtConfluenceNorm;  // [v2.03] dari regime
      score += m_model.regimeScoreWeight  * ctx.regimeScore;       // [v2.03] regime score
      if (signal.patternType != PATTERN_NONE)
         score += cfg.ai_pattern_bonus * 0.8;
      return score;
   }

   double EvaluateMeanReversionExpert(const SignalDecision &signal, const EvalContext &ctx) const
   {
      double score = m_model.bias;
      score += m_model.spreadWeight    * ctx.spreadNorm;
      score += m_model.regimeScoreWeight * ctx.volatilityScore;  // [v2.03] volatility dari regime
      score += m_model.momentumWeight  * ctx.zoneNorm;
      score += m_model.timeOfDayWeight * ctx.timeOfDayNorm;
      if (signal.patternType != PATTERN_NONE)
         score += cfg.ai_pattern_bonus * 1.2;
      return score;
   }

   double EvaluateMomentumExpert(const EvalContext &ctx) const
   {
      double score = m_model.bias;
      score += m_model.volumeWeight      * ctx.volumeNorm;
      score += m_model.momentumWeight    * ctx.momentumNorm;
      score += m_model.lossStreakWeight  * ctx.lossStreakNorm;
      score -= m_model.volNoiseWeight    * ctx.noiseNorm;
      return score;
   }

   //--- Feature Normalizers (atomic, no CopyRates ganda) ---

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

   double NormalizeTimeOfDayFeature() const
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int hour = dt.hour;
      if ((hour >= 8 && hour <= 11) || (hour >= 13 && hour <= 16)) return 1.0;
      if  (hour >= 7 && hour <= 19)                                  return 0.7;
      return 0.3;
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
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if (dt.hour == 8 || dt.hour == 13) return 1.0;
      return 0.2;
   }

   double NormalizeLossStreak() const
   {
      if (CheckPointer(m_data) == POINTER_INVALID) return 0.0;
      int losses = (*m_data).GetConsecutiveLosses();
      return MathMax(0.0, 1.0 - MathMin(1.0, losses * 0.1));
   }

   // [v2.03] Fallback hanya digunakan jika MarketRegimeFilter tidak di-inject
   double NormalizeVolatilityFeatureFallback() const
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

   // [v2.03] Fallback hanya digunakan jika MarketRegimeFilter tidak di-inject
   double NormalizeMultiTimeframeConfluenceFallback(const SignalDecision &signal) const
   {
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

      double currentPrice  = bars[0].close;
      double distFromHigh  = MathAbs(currentPrice - highestHigh);
      double distFromLow   = MathAbs(currentPrice - lowestLow);
      double minDist       = MathMin(distFromHigh, distFromLow);
      double confluence    = 1.0 - MathMin(1.0, minDist / (rangeSize * 0.3));
      return MathMax(0.3, confluence);
   }

   //--- Neural Network ---

   double EvaluateNeuralNetwork(const EvalContext &ctx) const
   {
      if (!m_model.initialized)
         return 0.5;
      
      // [v2.03] Input: atr, regimeScore (ganti volatility raw), mtConfluence
      double input1 = ctx.atrNorm;
      double input2 = ctx.regimeScore;      // [v2.03] dari MarketRegimeFilter
      double input3 = ctx.mtConfluenceNorm; // [v2.03] dari MarketRegimeFilter

      double h1_in  = m_model.nn_hidden1_w1 * input1 +
                      m_model.nn_hidden1_w2 * input2 +
                      m_model.nn_hidden1_w3 * input3 +
                      m_model.nn_hidden1_bias;
      double h1_out = MathMax(0.0, h1_in);

      double h2_in  = m_model.nn_hidden2_w1 * h1_out +
                      m_model.nn_hidden2_bias;
      double h2_out = MathMax(0.0, h2_in);

      double output = m_model.nn_output_w1 * h1_out +
                      m_model.nn_output_w2 * h2_out +
                      m_model.nn_output_bias;
      return output;
   }

   void TrainNeuralNetwork(const SignalDecision &signal, const double atrPoints,
                           const double support, const double resistance, bool actualOutcome)
   {
      if (!m_model.initialized)
         return;
      
      // Build context untuk training (menggunakan data saat trade ditutup)
      EvalContext ctx;
      BuildEvalContext(ctx, signal, atrPoints, support, resistance);

      // --- Forward Pass ---
      double input1 = ctx.atrNorm;
      double input2 = ctx.regimeScore;
      double input3 = ctx.mtConfluenceNorm;

      double h1_in     = m_model.nn_hidden1_w1 * input1 +
                         m_model.nn_hidden1_w2 * input2 +
                         m_model.nn_hidden1_w3 * input3 +
                         m_model.nn_hidden1_bias;
      double h1_out    = MathMax(0.0, h1_in);
      int    h1_active = (h1_in > 0) ? 1 : 0;

      double h2_in     = m_model.nn_hidden2_w1 * h1_out + m_model.nn_hidden2_bias;
      double h2_out    = MathMax(0.0, h2_in);
      int    h2_active = (h2_in > 0) ? 1 : 0;

      double predicted        = m_model.nn_output_w1 * h1_out +
                                m_model.nn_output_w2 * h2_out +
                                m_model.nn_output_bias;
      double predictedSigmoid = Logistic(predicted);
      double target           = actualOutcome ? 1.0 : 0.0;
      double error            = predictedSigmoid - target;

      // --- Backward Pass ---
      double d_out = error * predictedSigmoid * (1.0 - predictedSigmoid);

      // Update output weights
      m_model.nn_output_w1   -= m_model.nnLearningRate * d_out * h1_out;
      m_model.nn_output_w2   -= m_model.nnLearningRate * d_out * h2_out;
      m_model.nn_output_bias -= m_model.nnLearningRate * d_out;

      // Gradient ke hidden2
      double d_h2 = d_out * m_model.nn_output_w2 * h2_active;
      m_model.nn_hidden2_w1   -= m_model.nnLearningRate * d_h2 * h1_out;
      m_model.nn_hidden2_bias -= m_model.nnLearningRate * d_h2;

      // Gradient ke hidden1
      double d_h1 = (d_out * m_model.nn_output_w1 + d_h2 * m_model.nn_hidden2_w1) * h1_active;
      m_model.nn_hidden1_w1   -= m_model.nnLearningRate * d_h1 * input1;
      m_model.nn_hidden1_w2   -= m_model.nnLearningRate * d_h1 * input2;
      m_model.nn_hidden1_w3   -= m_model.nnLearningRate * d_h1 * input3;
      m_model.nn_hidden1_bias -= m_model.nnLearningRate * d_h1;

      m_model.nnTrainingSamples++;
      m_model.validationCounter++;

      // Learning rate decay setiap 100 sample
      if (m_model.nnTrainingSamples % 100 == 0 && m_model.nnLearningRate > 0.001)
         m_model.nnLearningRate *= 0.95;

      m_model.lastUpdateTime = TimeCurrent();

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
      
      if (GlobalVariableCheck(prefix + "bias"))       m_model.bias             = GlobalVariableGet(prefix + "bias");
      if (GlobalVariableCheck(prefix + "atr"))        m_model.atrWeight        = GlobalVariableGet(prefix + "atr");
      if (GlobalVariableCheck(prefix + "spread"))     m_model.spreadWeight     = GlobalVariableGet(prefix + "spread");
      if (GlobalVariableCheck(prefix + "sl"))         m_model.slWeight         = GlobalVariableGet(prefix + "sl");
      if (GlobalVariableCheck(prefix + "momentum"))   m_model.momentumWeight   = GlobalVariableGet(prefix + "momentum");
      if (GlobalVariableCheck(prefix + "loss"))       m_model.lossStreakWeight = GlobalVariableGet(prefix + "loss");
      if (GlobalVariableCheck(prefix + "volnoise"))   m_model.volNoiseWeight   = GlobalVariableGet(prefix + "volnoise");
      // [v2.03] regimeScoreWeight menggantikan volatilityWeight
      if (GlobalVariableCheck(prefix + "regimescore"))  m_model.regimeScoreWeight  = GlobalVariableGet(prefix + "regimescore");
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
      if (GlobalVariableCheck(prefix + "nn_h2w1")) m_model.nn_hidden2_w1   = GlobalVariableGet(prefix + "nn_h2w1");
      if (GlobalVariableCheck(prefix + "nn_h2b"))  m_model.nn_hidden2_bias = GlobalVariableGet(prefix + "nn_h2b");
      if (GlobalVariableCheck(prefix + "nn_ow1"))  m_model.nn_output_w1    = GlobalVariableGet(prefix + "nn_ow1");
      if (GlobalVariableCheck(prefix + "nn_ow2"))  m_model.nn_output_w2    = GlobalVariableGet(prefix + "nn_ow2");
      if (GlobalVariableCheck(prefix + "nn_ob"))   m_model.nn_output_bias  = GlobalVariableGet(prefix + "nn_ob");
      if (GlobalVariableCheck(prefix + "nn_lr"))   m_model.nnLearningRate  = GlobalVariableGet(prefix + "nn_lr");
      if (GlobalVariableCheck(prefix + "nn_ts"))   m_model.nnTrainingSamples = (int)GlobalVariableGet(prefix + "nn_ts");

      m_model.initialized = true;
      // [v2.03 FIX] Hapus SaveModelState() yang tidak perlu setelah load
      
      Log("📥 Model state loaded. NN samples: " + IntegerToString(m_model.nnTrainingSamples));
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
      GlobalVariableSet(prefix + "volnoise",     m_model.volNoiseWeight);
      // [v2.03] simpan regimeScoreWeight
      GlobalVariableSet(prefix + "regimescore",  m_model.regimeScoreWeight);
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
      // [v2.03] Gunakan regime score jika tersedia
      sample.volatility   = (CheckPointer(m_regime) != POINTER_INVALID)
                            ? m_regime.GetVolatilityScore()
                            : NormalizeVolatilityFeatureFallback();
      sample.mtConfluence = (CheckPointer(m_regime) != POINTER_INVALID)
                            ? m_regime.GetRegimeScore()
                            : NormalizeMultiTimeframeConfluenceFallback(signal);
      sample.volumeRatio  = NormalizeVolumeFeature();
      sample.zoneStrength = NormalizeZoneFeature(signal.zonePrice, support, resistance);
      sample.slMultiplier = signal.slMultiplier;
      sample.patternType  = (int)signal.patternType;

      int size = ArraySize(m_pendingSamples);
      ArrayResize(m_pendingSamples, size + 1);
      m_pendingSamples[size] = sample;

      while (ArraySize(m_pendingSamples) > 48)
         ArrayRemove(m_pendingSamples, 0);
   }

   int FindRecentPendingSampleIndex() const
   {
      // [v2.03 FIX] Window diperlebar 15s → 60s untuk market lambat / pending order
      for (int i = ArraySize(m_pendingSamples) - 1; i >= 0; --i)
      {
         if (m_pendingSamples[i].ticket == 0 &&
             !m_pendingSamples[i].labeled &&
             TimeCurrent() - m_pendingSamples[i].timestamp <= 60)
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
                   "sl_mult","zone_conf","loss_streak","regime_score","volatility_score","timeofday",
                   "mt_confluence","volume","trend_score","meanrev_score",
                   "momentum_score","ensemble_score","regime_type","accepted");
      }

      long spreadInt = 0;
      SymbolInfoInteger(_Symbol, SYMBOL_SPREAD, spreadInt);

      int currentLosses = (CheckPointer(m_data) != POINTER_INVALID) ? (*m_data).GetConsecutiveLosses() : 0;

      // [v2.03] Pakai regime info untuk logging
      string regimeType = "UNKNOWN";
      double regimeScoreVal = 0.5;
      double volScoreVal = 0.5;
      if (CheckPointer(m_regime) != POINTER_INVALID)
      {
         regimeScoreVal = m_regime.GetRegimeScore();
         volScoreVal    = m_regime.GetVolatilityScore();
         regimeType     = m_regime.GetDescription();
      }

      // Build context untuk score detail
      EvalContext ctx;
      BuildEvalContext(ctx, signal, atrPoints, support, resistance);

      double trendScore    = EvaluateTrendExpert(signal, ctx);
      double meanRevScore  = EvaluateMeanReversionExpert(signal, ctx);
      double momentumScore = EvaluateMomentumExpert(ctx);

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
                DoubleToString(regimeScoreVal, 4),
                DoubleToString(volScoreVal, 4),
                DoubleToString(ctx.timeOfDayNorm, 2),
                DoubleToString(ctx.mtConfluenceNorm, 4),
                DoubleToString(ctx.volumeNorm, 4),
                DoubleToString(trendScore, 4),
                DoubleToString(meanRevScore, 4),
                DoubleToString(momentumScore, 4),
                DoubleToString(score, 4),
                regimeType,
                accepted ? "1" : "0");
      FileClose(handle);

      RegisterPendingSample(sampleId, accepted, atrPoints, support, resistance, signal);
   }

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
                "sl_multiplier","tp_multiplier","atr_points","spread","regime_score",
                "volatility_score","time_of_day","mt_confluence","volume_ratio","zone_strength",
                "loss_streak","bias","trend_score","meanrev_score","momentum_score",
                "ensemble_score","regime_type","accepted","outcome_pnl","outcome_label");
      FileClose(handle);

      Log("WARNING: ExportDatasetForExternalTraining() is a stub. Only header written.");
      Log("To complete: read " + m_datasetFilename + " and join with " + m_outcomeFilename);
   }

   //--- Adaptive Model ---

   void AdaptModelToPerformance()
   {
      if (CheckPointer(m_data) == POINTER_INVALID)
      {
         Log("⚠️ AdaptModelToPerformance: DataManager is NULL");
         return;
      }

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
      m_model.regimeScoreWeight = NormalizeWeight(m_model.regimeScoreWeight + error * 0.01);

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
      m_model.atrWeight         = NormalizeWeight(m_model.atrWeight         * d);
      m_model.spreadWeight      = NormalizeWeight(m_model.spreadWeight      * d);
      m_model.slWeight          = NormalizeWeight(m_model.slWeight          * d);
      m_model.momentumWeight    = NormalizeWeight(m_model.momentumWeight    * d);
      m_model.lossStreakWeight   = NormalizeWeight(m_model.lossStreakWeight  * d);
      m_model.regimeScoreWeight  = NormalizeWeight(m_model.regimeScoreWeight * d);
      m_model.timeOfDayWeight    = NormalizeWeight(m_model.timeOfDayWeight   * d);
      m_model.mtConfluenceWeight = NormalizeWeight(m_model.mtConfluenceWeight * d);
      m_model.volumeWeight       = NormalizeWeight(m_model.volumeWeight      * d);

      // [v2.03 FIX] NN weights pakai NormalizeNNWeight() agar boleh negatif
      double nd = 0.999;
      m_model.nn_hidden1_w1   = NormalizeNNWeight(m_model.nn_hidden1_w1   * nd);
      m_model.nn_hidden1_w2   = NormalizeNNWeight(m_model.nn_hidden1_w2   * nd);
      m_model.nn_hidden1_w3   = NormalizeNNWeight(m_model.nn_hidden1_w3   * nd);
      m_model.nn_hidden1_bias = NormalizeNNWeight(m_model.nn_hidden1_bias * nd);
      m_model.nn_hidden2_w1   = NormalizeNNWeight(m_model.nn_hidden2_w1   * nd);
      m_model.nn_hidden2_bias = NormalizeNNWeight(m_model.nn_hidden2_bias * nd);
      m_model.nn_output_w1    = NormalizeNNWeight(m_model.nn_output_w1    * nd);
      m_model.nn_output_w2    = NormalizeNNWeight(m_model.nn_output_w2    * nd);
      m_model.nn_output_bias  = NormalizeNNWeight(m_model.nn_output_bias  * nd);
   }

   // Feature weights: hanya positif [0.01, 2.0]
   double NormalizeWeight(double value) const
   {
      return MathMax(0.01, MathMin(2.0, value));
   }

   // [v2.03 FIX] NN weights: boleh negatif [-2.0, 2.0]
   double NormalizeNNWeight(double value) const
   {
      return MathMax(-2.0, MathMin(2.0, value));
   }

public:
   int    GetNNTrainingSamples() const { return m_model.nnTrainingSamples; }
   double GetNNLearningRate()    const { return m_model.nnLearningRate; }
};

#endif
