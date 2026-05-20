//+------------------------------------------------------------------+
//|                                                   AIManager.mqh  |
//|                                       Copyright 2026, Agsicentre |
//|            Adaptive AI & Signal Scoring Module                   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "2.07"
#property strict

#ifndef __AI_MANAGER_MQH__
#define __AI_MANAGER_MQH__

#include "IManager.mqh"
#include "10.DataManager.mqh"
#include "12.MarketRegime.mqh"

#define NN_INPUTS        8
#define NN_H1            6
#define NN_H2            4
#define REPLAY_CAPACITY  500
#define MINIBATCH_SIZE   16
#define L2_LAMBDA        0.0001

//+------------------------------------------------------------------+
//| Multi-Model Expert Types for Regime-Based Switching
//+------------------------------------------------------------------+
enum ExpertType
{
   EXPERT_NONE = 0,           // No active expert (skip trading)
   EXPERT_TREND = 1,          // Trend-following specialist
   EXPERT_MEAN_REVERSION = 2, // Mean-reversion specialist
   EXPERT_MOMENTUM = 3        // Momentum breakout specialist
};

//+------------------------------------------------------------------+
//| Cached Bar Data Structure for Performance Optimization
//| Prevents repeated CopyRates calls within same tick
//+------------------------------------------------------------------+
struct CachedBarData
{
   datetime timestamp;         // Bar open time (cache key)
   double   open;
   double   high;
   double   low;
   double   close;
   long     volume;
   bool     valid;
   
   CachedBarData()
   {
      timestamp = 0;
      open = high = low = close = 0.0;
      volume = 0;
      valid = false;
   }
};

// Cache for multiple timeframes
struct BarCache
{
   CachedBarData current;      // Current chart timeframe
   CachedBarData higher;       // Higher timeframe
   CachedBarData longTerm;     // Long-term timeframe
   datetime      lastUpdate;   // Last cache refresh time
   
   BarCache() : lastUpdate(0) {}
};

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
      double regimeScoreWeight;
      double timeOfDayWeight;
      double mtConfluenceWeight;
      double volumeWeight;
      double trendExpertWeight;
      double meanRevExpertWeight;
      double momentumExpertWeight;
      double recentWinRate;
      double longTermWinRate;
      int    driftDetectionWindow;
      double h1w[NN_INPUTS][NN_H1];
      double h1b[NN_H1];
      double h2w[NN_H1][NN_H2];
      double h2b[NN_H2];
      double ow[NN_H2];
      double ob;
      double plattA;
      double plattB;
      int    plattSamples;
      double nnLearningRate;
      int    nnTrainingSamples;
      int    replayTrainCount;
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
   int              m_labeledSinceLastBatch;

   MarketRegimeFilter *m_regime;
   BarCache          m_barCache;    // Performance cache for bar data
   ExpertType        m_activeExpert;// Currently selected expert model

   struct EvalContext
   {
      double atrNorm;
      double spreadNorm;
      double slNorm;
      double regimeScore;
      double volatilityScore;
      double timeOfDayNorm;
      double mtConfluenceNorm;
      double volumeNorm;
      double momentumNorm;
      double zoneNorm;
      double lossStreakNorm;
      double noiseNorm;
      double rsiNorm;
      double candleBodyRatio;
      double emaDistNorm;
      double sessionNorm;
   };

   struct ReplaySample
   {
      double features[NN_INPUTS];
      double label;
   } m_replayBuffer[REPLAY_CAPACITY];
   int m_replayHead;
   int m_replayCount;

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
      double         features[NN_INPUTS];
   } m_pendingSamples[];

   static ENUM_TIMEFRAMES GetHigherTimeframe(ENUM_TIMEFRAMES tf)
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

public:
   AIManager() : IManager("AIManager", 35),
                 m_lastHeartbeat(0),
                 m_lastSavedWinRate(-1.0),
                 m_modelDirty(false),
                 m_datasetFilename(""),
                 m_ticketMapFilename(""),
                 m_outcomeFilename(""),
                 m_loggedSamples(0),
                 m_labeledSinceLastBatch(0),
                 m_regime(NULL),
                 m_replayHead(0),
                 m_replayCount(0),
                 m_activeExpert(EXPERT_NONE)
   {
      m_model.bias               = 0.55;
      m_model.atrWeight          = 0.18;
      m_model.spreadWeight       = 0.14;
      m_model.slWeight           = 0.16;
      m_model.momentumWeight     = 0.08;
      m_model.lossStreakWeight    = 0.06;
      m_model.volNoiseWeight     = 0.12;
      m_model.regimeScoreWeight  = 0.15;
      m_model.timeOfDayWeight    = 0.10;
      m_model.mtConfluenceWeight = 0.20;
      m_model.volumeWeight       = 0.12;
      m_model.trendExpertWeight    = 0.35;
      m_model.meanRevExpertWeight  = 0.25;
      m_model.momentumExpertWeight = 0.25;
      m_model.recentWinRate        = -1.0;
      m_model.longTermWinRate      = -1.0;
      m_model.driftDetectionWindow = 50;

      double scale1 = MathSqrt(2.0 / (NN_INPUTS + NN_H1));
      double scale2 = MathSqrt(2.0 / (NN_H1 + NN_H2));
      double scale3 = MathSqrt(2.0 / (NN_H2 + 1));
      for(int i = 0; i < NN_INPUTS; i++)
         for(int j = 0; j < NN_H1; j++)
            m_model.h1w[i][j] = scale1 * (0.2 - (double)(i + j) * 0.01);
      for(int j = 0; j < NN_H1; j++) m_model.h1b[j] = 0.01;
      for(int i = 0; i < NN_H1; i++)
         for(int j = 0; j < NN_H2; j++)
            m_model.h2w[i][j] = scale2 * (0.2 - (double)(i + j) * 0.01);
      for(int j = 0; j < NN_H2; j++) m_model.h2b[j] = 0.01;
      for(int j = 0; j < NN_H2; j++) m_model.ow[j]  = scale3 * 0.5;
      m_model.ob = 0.0;

      m_model.plattA       = 1.0;
      m_model.plattB       = 0.0;
      m_model.plattSamples = 0;
      m_model.nnLearningRate    = 0.01;
      m_model.nnTrainingSamples = 0;
      m_model.replayTrainCount  = 0;
      m_model.initialized       = true;
      m_model.lastUpdateTime    = TimeCurrent();
      m_model.validationCounter = 0;
      ArrayInitialize(m_replayBuffer, 0.0);
      
      // Initialize bar cache
      m_barCache.lastUpdate = 0;
      m_activeExpert = EXPERT_NONE;
   }

   void SetRegimeFilter(MarketRegimeFilter *regime)
   {
      m_regime = regime;
      Log("✅ MarketRegimeFilter injected.");
   }
   MarketRegimeFilter* GetRegimeFilter() const { return m_regime; }
   
   //+------------------------------------------------------------------+
   //| Bar Data Caching for Performance Optimization
   //| Called once per tick/event to cache OHLCV data
   //+------------------------------------------------------------------+
   void CacheCurrentBars()
   {
      datetime now = TimeCurrent();
      
      // Only refresh cache once per second to avoid redundant calls
      if(now - m_barCache.lastUpdate < 1) return;
      
      MqlRates bars[1];
      
      // Cache current timeframe bar (shift=1 for closed bar)
      if(CopyRates(_Symbol, _Period, 1, 1, bars) == 1)
      {
         m_barCache.current.timestamp = bars[0].time;
         m_barCache.current.open = bars[0].open;
         m_barCache.current.high = bars[0].high;
         m_barCache.current.low = bars[0].low;
         m_barCache.current.close = bars[0].close;
         m_barCache.current.volume = bars[0].tick_volume;
         m_barCache.current.valid = true;
      }
      
      // Cache higher timeframe
      ENUM_TIMEFRAMES htf = GetHigherTimeframe((ENUM_TIMEFRAMES)Period());
      if(CopyRates(_Symbol, htf, 1, 1, bars) == 1)
      {
         m_barCache.higher.timestamp = bars[0].time;
         m_barCache.higher.open = bars[0].open;
         m_barCache.higher.high = bars[0].high;
         m_barCache.higher.low = bars[0].low;
         m_barCache.higher.close = bars[0].close;
         m_barCache.higher.volume = bars[0].tick_volume;
         m_barCache.higher.valid = true;
      }
      
      m_barCache.lastUpdate = now;
   }
   
   // Helper to get cached bars array for a specific timeframe
   bool GetCachedBars(ENUM_TIMEFRAMES tf, MqlRates &outBars[], int count, int shift = 1) const
   {
      // For current timeframe, use cache if available
      if(tf == (ENUM_TIMEFRAMES)Period() && m_barCache.current.valid)
      {
         if(count == 1 && shift == 1)
         {
            ArrayResize(outBars, 1);
            outBars[0].time = m_barCache.current.timestamp;
            outBars[0].open = m_barCache.current.open;
            outBars[0].high = m_barCache.current.high;
            outBars[0].low = m_barCache.current.low;
            outBars[0].close = m_barCache.current.close;
            outBars[0].tick_volume = m_barCache.current.volume;
            return true;
         }
      }
      
      // Fallback to CopyRates for other cases
      return CopyRates(_Symbol, tf, shift, count, outBars) >= count;
   }

   //+------------------------------------------------------------------+
   //| Multi-Model Expert Switching Logic
   //+------------------------------------------------------------------+
   ExpertType GetActiveExpert() const
   {
      if(CheckPointer(m_regime) == POINTER_INVALID)
         return EXPERT_NONE;
      
      ENUM_MARKET_REGIME regime = m_regime.GetMarketRegime();
      const RegimeResult &r = m_regime.GetResult();
      
      // Skip trading during transition or low confidence
      if(regime == REGIME_TRANSITION || r.regimeScore < 0.3)
         return EXPERT_NONE;
      
      // Select expert based on market regime
      switch(regime)
      {
         case REGIME_TRENDING_STRONG:
         case REGIME_TRENDING_WEAK:
            return EXPERT_TREND;
            
         case REGIME_RANGING_SIDEWAYS:
            return EXPERT_MEAN_REVERSION;
            
         case REGIME_CHOPPY_HIGH_VOL:
            // In high volatility chop, use momentum for breakouts only
            return EXPERT_MOMENTUM;
            
         default:
            return EXPERT_NONE;
      }
   }

   virtual void RefreshConfigCache() override { IManager::RefreshConfigCache(); }
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
      if(!IManager::Init()) return false;
      m_data = IManager::GetGlobalDataManager();
      if(CheckPointer(m_data) == POINTER_INVALID)
      {
         Log("❌ CRITICAL: DataManager is NULL during AIManager initialization");
         return false;
      }
      if(CheckPointer(m_regime) == POINTER_INVALID)
         Log("⚠️ WARNING: MarketRegimeFilter not injected. Call SetRegimeFilter() before Init().");

      StrategyConfig cfg;
      m_data.GetConfigCache(cfg);
      string prefix       = "AI_ml_" + IntegerToString(cfg.risk.magic) + "_" + _Symbol + "_";
      m_datasetFilename   = prefix + "data.csv";
      m_ticketMapFilename = prefix + "ticketmap.csv";
      m_outcomeFilename   = prefix + "outcomes.csv";

      LoadModelState();
      Log("✅ AIManager v2.07 initialized. NN samples: " + IntegerToString(m_model.nnTrainingSamples) +
          " | ReplayBuffer: " + IntegerToString(m_replayCount));
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
      if(CheckPointer(m_data) == POINTER_INVALID) return;
      StrategyConfig cfg;
      m_data.GetConfigCache(cfg);
      if(!cfg.ai.use) return;
      if(CheckPointer(m_regime) != POINTER_INVALID) m_regime.Update();
      // Refresh bar cache on new bar event
      CacheCurrentBars();
      DecayFeatureWeightsOnly(0.995);
   }

   virtual void OnHeartbeat(HeartbeatEvent *e) override
   {
      if(CheckPointer(m_data) == POINTER_INVALID) return;
      StrategyConfig cfg;
      m_data.GetConfigCache(cfg);
      if(!cfg.ai.use) return;
      if(TimeCurrent() - m_lastHeartbeat < 5) return;
      m_lastHeartbeat = TimeCurrent();
      // Refresh bar cache periodically
      CacheCurrentBars();
      AdaptModelToPerformance();
   }

   virtual void OnSignalGenerated(SignalGeneratedEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID)
      { Log("⚠️ OnSignalGenerated: NULL event pointer"); return; }
      if(CheckPointer(m_data) == POINTER_INVALID) return;
      StrategyConfig cfg;
      m_data.GetConfigCache(cfg);
      if(!cfg.ai.use || !e.signal.valid) return;
      
      // Ensure bar cache is fresh before feature extraction
      CacheCurrentBars();

      EvalContext ctx;
      BuildEvalContext(ctx, e.signal, e.atrPoints, e.support, e.resistance);

      double score = EvaluateSignal(e.signal, e.atrPoints, e.support, e.resistance, ctx, cfg);

      double aiSlAdjustment  = 1.0 + (Logistic(score) * m_model.volNoiseWeight);
      double dynamicThreshold = GetDynamicThreshold(cfg);
      bool   accepted         = score >= dynamicThreshold;

      Log("AI score=" + DoubleToString(score, 2) +
          " threshold=" + DoubleToString(dynamicThreshold, 2) +
          " replay=" + IntegerToString(m_replayCount) +
          " batches=" + IntegerToString(m_model.replayTrainCount));

      LogSignalSample(e.signal, e.atrPoints, e.support, e.resistance, score, accepted, cfg, ctx);

      if(!accepted)
      {
         e.signal.valid  = false;
         e.signal.reason = e.signal.reason + " | AI_REJECT(" + DoubleToString(score, 2) + ")";
         return;
      }
      e.signal.reason      = e.signal.reason + " | AI_ACCEPT(" + DoubleToString(score, 2) + ") SL_ADJ:" + DoubleToString(aiSlAdjustment, 2);
      e.signal.slMultiplier *= aiSlAdjustment;
   }

   virtual void OnOrderExecution(OrderExecutionEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID)
      { Log("⚠️ OnOrderExecution: NULL event pointer"); return; }
      if(CheckPointer(m_data) == POINTER_INVALID) return;
      StrategyConfig cfg;
      m_data.GetConfigCache(cfg);
      if(!cfg.ai.use) return;
      if(e.success) AttachTicketToRecentSample(e.ticket);
      else
      {
         m_model.bias = NormalizeWeight(m_model.bias - 0.01);
         m_modelDirty = true;
      }
      SaveModelState(cfg);
   }

   virtual void OnPositionUpdate(PositionUpdateEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID)
      { Log("⚠️ OnPositionUpdate: NULL event pointer"); return; }
      if(CheckPointer(m_data) == POINTER_INVALID) return;
      StrategyConfig cfg;
      m_data.GetConfigCache(cfg);
      if(!cfg.ai.use) return;
      if(e.isClosing) { LabelSampleOutcome(e.ticket, e.unrealizedPnL); return; }
      if(e.unrealizedPnL < 0)      { m_model.bias = MathMax(0.25, m_model.bias - 0.002); m_modelDirty = true; }
      else if(e.unrealizedPnL > 0) { m_model.bias = MathMin(0.85, m_model.bias + 0.002); m_modelDirty = true; }
   }

private:

   void BuildEvalContext(EvalContext &ctx,
                         const SignalDecision &signal, const double atrPoints,
                         const double support, const double resistance) const
   {
      ctx.atrNorm        = NormalizeATRFeature(atrPoints);
      ctx.spreadNorm     = NormalizeSpreadFeature();
      ctx.slNorm         = NormalizeSLFeature(signal.slMultiplier);
      ctx.timeOfDayNorm  = NormalizeTimeOfDayFeature();
      ctx.volumeNorm     = NormalizeVolumeFeature();
      ctx.momentumNorm   = NormalizeMomentumFeature();
      ctx.zoneNorm       = NormalizeZoneFeature(signal.zonePrice, support, resistance);
      ctx.lossStreakNorm  = NormalizeLossStreak();
      ctx.noiseNorm      = NormalizeNoiseFeature();
      ctx.rsiNorm         = NormalizeRSIFeature();
      ctx.candleBodyRatio = NormalizeCandleBodyRatio();
      ctx.emaDistNorm     = NormalizeEMADistanceFeature();
      ctx.sessionNorm     = NormalizeSessionFeature();

      if(CheckPointer(m_regime) != POINTER_INVALID)
      {
         const RegimeResult &r = m_regime.GetResult();
         ctx.regimeScore      = r.regimeScore;
         ctx.volatilityScore  = r.volatilityScore;
         ctx.mtConfluenceNorm = r.mtfConfirmed ? 1.0 : (double)r.tfAlignment / 3.0;
      }
      else
      {
         ctx.regimeScore      = NormalizeVolatilityFeatureFallback();
         ctx.volatilityScore  = ctx.regimeScore;
         ctx.mtConfluenceNorm = NormalizeMultiTimeframeConfluenceFallback(signal);
      }
   }

   double GetDynamicThreshold(const StrategyConfig &cfg) const
   {
      if(CheckPointer(m_regime) != POINTER_INVALID)
         return m_regime.GetDynamicThreshold(cfg.ai.minConfidence);
      return cfg.ai.minConfidence;
   }

   double EvaluateSignal(const SignalDecision &signal, const double atrPoints,
                         const double support, const double resistance,
                         const EvalContext &ctx, const StrategyConfig &cfg) const
   {
      // Get active expert based on current market regime
      ExpertType activeExpert = GetActiveExpert();
      
      // Skip trading during transition or low confidence regimes
      if(activeExpert == EXPERT_NONE)
         return 0.0;  // Return zero score to reject signal
      
      double expertScore = 0.0;
      
      // Call only the relevant expert model (not weighted average of all)
      switch(activeExpert)
      {
         case EXPERT_TREND:
            expertScore = EvaluateTrendExpert(signal, ctx, cfg);
            break;
            
         case EXPERT_MEAN_REVERSION:
            expertScore = EvaluateMeanReversionExpert(signal, ctx, cfg);
            break;
            
         case EXPERT_MOMENTUM:
            expertScore = EvaluateMomentumExpert(ctx);
            break;
            
         default:
            return 0.0;
      }
      
      // Neural network provides additional calibration
      double nnRaw   = ForwardPassNN(ctx);
      double nnScore = PlattCalibrate(nnRaw);
      
      // Weight NN based on training samples - less weight when undertrained
      double nnWeight   = MathMin(0.30, 0.005 * m_model.nnTrainingSamples);
      double hybridScore = (1.0 - nnWeight) * expertScore + nnWeight * nnScore;
      
      return Logistic(hybridScore);
   }

   double EvaluateTrendExpert(const SignalDecision &signal, const EvalContext &ctx,
                               const StrategyConfig &cfg) const
   {
      double score = m_model.bias;
      score += m_model.atrWeight          * ctx.atrNorm;
      score += m_model.slWeight           * ctx.slNorm;
      score += m_model.mtConfluenceWeight * ctx.mtConfluenceNorm;
      score += m_model.regimeScoreWeight  * ctx.regimeScore;
      if(signal.patternType != PATTERN_NONE) score += cfg.ai.patternBonus * 0.8;
      return score;
   }

   double EvaluateMeanReversionExpert(const SignalDecision &signal, const EvalContext &ctx,
                                       const StrategyConfig &cfg) const
   {
      double score = m_model.bias;
      score += m_model.spreadWeight      * ctx.spreadNorm;
      score += m_model.regimeScoreWeight * ctx.volatilityScore;
      score += m_model.momentumWeight    * ctx.zoneNorm;
      score += m_model.timeOfDayWeight   * ctx.timeOfDayNorm;
      if(signal.patternType != PATTERN_NONE) score += cfg.ai.patternBonus * 1.2;
      return score;
   }

   double EvaluateMomentumExpert(const EvalContext &ctx) const
   {
      double score = m_model.bias;
      score += m_model.volumeWeight     * ctx.volumeNorm;
      score += m_model.momentumWeight   * ctx.momentumNorm;
      score += m_model.lossStreakWeight * ctx.lossStreakNorm;
      score -= m_model.volNoiseWeight   * ctx.noiseNorm;
      return score;
   }

   // ─── Feature Normalizers ───────────────────────────────────────

   double NormalizeATRFeature(double atrPoints) const
   { return (atrPoints <= 0) ? 0.0 : MathMin(1.0, atrPoints / 20.0); }

   double NormalizeSpreadFeature() const
   {
      long sp = 0;
      if(!SymbolInfoInteger(_Symbol, SYMBOL_SPREAD, sp) || sp <= 0) return 1.0;
      return MathMax(0.0, 1.0 - MathMin(1.0, (double)sp / 10.0));
   }

   double NormalizeSLFeature(double slMultiplier) const
   { return (slMultiplier <= 0) ? 0.0 : MathMin(1.0, slMultiplier / 3.0); }

   double NormalizeZoneFeature(double zonePrice, double support, double resistance) const
   {
      double dist  = MathAbs(zonePrice - (support + resistance) / 2.0);
      double range = MathMax(1.0, MathAbs(resistance - support));
      return 1.0 - MathMin(1.0, dist / range);
   }

   double NormalizeTimeOfDayFeature() const
   {
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      int h = dt.hour;
      if((h >= 8 && h <= 11) || (h >= 13 && h <= 16)) return 1.0;
      if(h >= 7 && h <= 19)                            return 0.7;
      return 0.3;
   }

   double NormalizeVolumeFeature() const
   {
      long vol[20];
      // FIX: CopyTickVolume returns count of copied ticks, not boolean
      // Use shift=1 to avoid current forming bar, get last 20 completed ticks
      if(CopyTickVolume(_Symbol, _Period, 1, 20, vol) < 20) return 0.5;
      
      long sum = 0;
      for(int i = 0; i < 20; i++) sum += vol[i];
      long avg = sum / 20;
      
      // Avoid division by zero and clamp result
      if(avg == 0) return 0.5;
      double ratio = (double)vol[0] / avg;
      return MathMax(0.0, MathMin(2.0, ratio));  // Allow some headroom above 1.0
   }

   double NormalizeMomentumFeature() const
   {
      MqlRates bars[14];
      // FIX: Use shift=1 to avoid current forming bar - use last 14 CLOSED bars
      if(CopyRates(_Symbol, _Period, 1, 14, bars) < 14) return 0.5;
      double momentum = bars[0].close - bars[13].close;
      double maxMove  = 0;
      for(int i = 1; i < 14; i++) maxMove = MathMax(maxMove, MathAbs(bars[i].close - bars[0].close));
      if(maxMove == 0) return 0.5;
      return 0.5 + (momentum / maxMove) * 0.5;
   }

   double NormalizeNoiseFeature() const
   {
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      return (dt.hour == 8 || dt.hour == 13) ? 1.0 : 0.2;
   }

   double NormalizeLossStreak() const
   {
      if(CheckPointer(m_data) == POINTER_INVALID) return 0.0;
      return MathMax(0.0, 1.0 - MathMin(1.0, m_data.GetConsecutiveLosses() * 0.1));
   }

   double NormalizeRSIFeature() const
   {
      MqlRates bars[15];
      // FIX: Use shift=1 to avoid current forming bar - use last 15 CLOSED bars for RSI calculation
      if(CopyRates(_Symbol, _Period, 1, 15, bars) < 15) return 0.5;
      double gains = 0, losses = 0;
      for(int i = 0; i < 14; i++)
      {
         double diff = bars[i].close - bars[i+1].close;
         if(diff > 0) gains  += diff;
         else         losses -= diff;
      }
      double rs  = (losses == 0) ? 100.0 : gains / losses;
      double rsi = 100.0 - (100.0 / (1.0 + rs));
      return rsi / 100.0;
   }

   double NormalizeCandleBodyRatio() const
   {
      MqlRates bar[1];
      // FIX: Use shift=1 to get last CLOSED bar, not current forming bar
      if(CopyRates(_Symbol, _Period, 1, 1, bar) < 1) return 0.5;
      double body  = MathAbs(bar[0].close - bar[0].open);
      double range = bar[0].high - bar[0].low;
      return (range == 0) ? 0.5 : MathMin(1.0, body / range);
   }

   double NormalizeEMADistanceFeature() const
   {
      MqlRates bars[20];
      // FIX: Use shift=1 to avoid current forming bar - use last 20 CLOSED bars
      if(CopyRates(_Symbol, _Period, 1, 20, bars) < 20) return 0.5;
      double ema = bars[19].close;
      double k   = 2.0 / 21.0;
      for(int i = 18; i >= 0; i--) ema = bars[i].close * k + ema * (1.0 - k);
      double dist   = MathAbs(bars[0].close - ema);
      double atrEst = 0;
      for(int i = 0; i < 20; i++) atrEst += bars[i].high - bars[i].low;
      atrEst /= 20.0;
      return (atrEst == 0) ? 0.5 : MathMin(1.0, dist / (atrEst * 2.0));
   }

   double NormalizeSessionFeature() const
   {
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      int h = dt.hour;
      if(h >= 13 && h <= 21) return 1.0;
      if(h >= 7  && h <= 16) return 0.5;
      return 0.0;
   }

   double NormalizeVolatilityFeatureFallback() const
   {
      MqlRates bars[20];
      // FIX: Use shift=1 to avoid current forming bar - use last 20 CLOSED bars
      if(CopyRates(_Symbol, _Period, 1, 20, bars) < 20) return 0.5;
      double avg = 0;
      for(int i = 0; i < 20; i++) avg += bars[i].close;
      avg /= 20;
      double sumSq = 0;
      for(int i = 0; i < 20; i++) { double d = bars[i].close - avg; sumSq += d * d; }
      double vol = MathSqrt(sumSq / 20);
      return MathMin(1.0, vol / (SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 100));
   }

   double NormalizeMultiTimeframeConfluenceFallback(const SignalDecision &signal) const
   {
      ENUM_TIMEFRAMES htf = GetHigherTimeframe((ENUM_TIMEFRAMES)Period());
      MqlRates bars[10];
      if(CopyRates(_Symbol, htf, 0, 10, bars) < 10) return 0.5;
      double hi = bars[0].high, lo = bars[0].low;
      for(int i = 1; i < 10; i++) { hi = MathMax(hi, bars[i].high); lo = MathMin(lo, bars[i].low); }
      double rangeSize = hi - lo;
      if(rangeSize == 0) return 0.5;
      double minDist = MathMin(MathAbs(bars[0].close - hi), MathAbs(bars[0].close - lo));
      return MathMax(0.3, 1.0 - MathMin(1.0, minDist / (rangeSize * 0.3)));
   }

   // ─── Neural Network ────────────────────────────────────────────

   double ForwardPassNN(const EvalContext &ctx) const
   {
      if(!m_model.initialized) return 0.5;
      double feat[NN_INPUTS];
      feat[0] = ctx.atrNorm;
      feat[1] = ctx.regimeScore;
      feat[2] = ctx.mtConfluenceNorm;
      feat[3] = ctx.rsiNorm;
      feat[4] = ctx.candleBodyRatio;
      feat[5] = ctx.emaDistNorm;
      feat[6] = ctx.sessionNorm;
      feat[7] = ctx.momentumNorm;

      double h1[NN_H1];
      for(int j = 0; j < NN_H1; j++)
      {
         double z = m_model.h1b[j];
         for(int i = 0; i < NN_INPUTS; i++) z += feat[i] * m_model.h1w[i][j];
         h1[j] = MathMax(0.0, z);
      }
      double h2[NN_H2];
      for(int j = 0; j < NN_H2; j++)
      {
         double z = m_model.h2b[j];
         for(int i = 0; i < NN_H1; i++) z += h1[i] * m_model.h2w[i][j];
         h2[j] = MathMax(0.0, z);
      }
      double out = m_model.ob;
      for(int j = 0; j < NN_H2; j++) out += h2[j] * m_model.ow[j];
      return out;
   }

   double PlattCalibrate(double nnRaw) const
   {
      if(m_model.plattSamples < 30) return Logistic(nnRaw);
      return Logistic(m_model.plattA * nnRaw + m_model.plattB);
   }

   void UpdatePlattScaling(double nnRaw, double label)
   {
      double pred  = Logistic(m_model.plattA * nnRaw + m_model.plattB);
      double error = pred - label;
      double lr    = 0.01;
      m_model.plattA -= lr * error * pred * (1.0 - pred) * nnRaw;
      m_model.plattB -= lr * error * pred * (1.0 - pred);
      m_model.plattSamples++;
   }

   void TrainMiniBatch()
   {
      if(m_replayCount < MINIBATCH_SIZE) return;
      double lr = m_model.nnLearningRate;

      for(int b = 0; b < MINIBATCH_SIZE; b++)
      {
         int idx = (int)(MathRand() % MathMin(m_replayCount, REPLAY_CAPACITY));
         double feat[NN_INPUTS];
         for(int i = 0; i < NN_INPUTS; i++) feat[i] = m_replayBuffer[idx].features[i];
         double label = m_replayBuffer[idx].label;

         double h1[NN_H1], z1[NN_H1];
         for(int j = 0; j < NN_H1; j++)
         {
            z1[j] = m_model.h1b[j];
            for(int i = 0; i < NN_INPUTS; i++) z1[j] += feat[i] * m_model.h1w[i][j];
            h1[j] = MathMax(0.0, z1[j]);
         }
         double h2[NN_H2], z2[NN_H2];
         for(int j = 0; j < NN_H2; j++)
         {
            z2[j] = m_model.h2b[j];
            for(int i = 0; i < NN_H1; i++) z2[j] += h1[i] * m_model.h2w[i][j];
            h2[j] = MathMax(0.0, z2[j]);
         }
         double raw  = m_model.ob;
         for(int j = 0; j < NN_H2; j++) raw += h2[j] * m_model.ow[j];
         double pred  = Logistic(raw);
         double error = pred - label;

         double d_out = error * pred * (1.0 - pred);
         for(int j = 0; j < NN_H2; j++)
            m_model.ow[j] -= lr * (d_out * h2[j] + L2_LAMBDA * m_model.ow[j]);
         m_model.ob -= lr * d_out;

         double d_h2[NN_H2];
         for(int j = 0; j < NN_H2; j++)
         {
            d_h2[j] = (z2[j] > 0) ? d_out * m_model.ow[j] : 0.0;
            for(int i = 0; i < NN_H1; i++)
               m_model.h2w[i][j] -= lr * (d_h2[j] * h1[i] + L2_LAMBDA * m_model.h2w[i][j]);
            m_model.h2b[j] -= lr * d_h2[j];
         }

         for(int j = 0; j < NN_H1; j++)
         {
            double grad = 0;
            for(int k = 0; k < NN_H2; k++) grad += d_h2[k] * m_model.h2w[j][k];
            double d_h1 = (z1[j] > 0) ? grad : 0.0;
            for(int i = 0; i < NN_INPUTS; i++)
               m_model.h1w[i][j] -= lr * (d_h1 * feat[i] + L2_LAMBDA * m_model.h1w[i][j]);
            m_model.h1b[j] -= lr * d_h1;
         }

         UpdatePlattScaling(raw, label);
      }

      m_model.replayTrainCount++;
      m_model.nnTrainingSamples += MINIBATCH_SIZE;
      if(m_model.replayTrainCount % 10 == 0 && m_model.nnLearningRate > 0.001)
         m_model.nnLearningRate *= 0.95;
      m_model.lastUpdateTime = TimeCurrent();
      m_labeledSinceLastBatch = 0;

      Log("Mini-batch #" + IntegerToString(m_model.replayTrainCount) +
          " | LR=" + DoubleToString(m_model.nnLearningRate, 5) +
          " | replay=" + IntegerToString(m_replayCount) +
          " | platt_samples=" + IntegerToString(m_model.plattSamples));
   }

   void PushReplayBuffer(const double &features[], double label)
   {
      for(int i = 0; i < NN_INPUTS; i++)
         m_replayBuffer[m_replayHead].features[i] = features[i];
      m_replayBuffer[m_replayHead].label = label;
      m_replayHead  = (m_replayHead + 1) % REPLAY_CAPACITY;
      if(m_replayCount < REPLAY_CAPACITY) m_replayCount++;
   }

   double Logistic(double x) const { return 1.0 / (1.0 + MathExp(-x)); }

   void DecayFeatureWeightsOnly(double decay)
   {
      double d = MathMax(0.9, MathMin(1.0, decay));
      m_model.atrWeight          = NormalizeWeight(m_model.atrWeight          * d);
      m_model.spreadWeight       = NormalizeWeight(m_model.spreadWeight       * d);
      m_model.slWeight           = NormalizeWeight(m_model.slWeight           * d);
      m_model.momentumWeight     = NormalizeWeight(m_model.momentumWeight     * d);
      m_model.lossStreakWeight    = NormalizeWeight(m_model.lossStreakWeight   * d);
      m_model.regimeScoreWeight   = NormalizeWeight(m_model.regimeScoreWeight  * d);
      m_model.timeOfDayWeight     = NormalizeWeight(m_model.timeOfDayWeight    * d);
      m_model.mtConfluenceWeight  = NormalizeWeight(m_model.mtConfluenceWeight * d);
      m_model.volumeWeight        = NormalizeWeight(m_model.volumeWeight       * d);
   }

   double NormalizeWeight(double value)   const { return MathMax(0.01,  MathMin(2.0,  value)); }
   double NormalizeNNWeight(double value) const { return MathMax(-2.0,  MathMin(2.0,  value)); }

   // ─── Persistence ───────────────────────────────────────────────

   string ModelGVPrefix(const StrategyConfig &cfg) const
   { return "PASR_AI_" + IntegerToString(cfg.risk.magic) + "_" + _Symbol + "_"; }

   void LoadModelState()
   {
      if(CheckPointer(m_data) == POINTER_INVALID) return;
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      string p = ModelGVPrefix(cfg);

      if(GlobalVariableCheck(p+"bias"))         m_model.bias               = GlobalVariableGet(p+"bias");
      if(GlobalVariableCheck(p+"atr"))          m_model.atrWeight          = GlobalVariableGet(p+"atr");
      if(GlobalVariableCheck(p+"spread"))       m_model.spreadWeight       = GlobalVariableGet(p+"spread");
      if(GlobalVariableCheck(p+"sl"))           m_model.slWeight           = GlobalVariableGet(p+"sl");
      if(GlobalVariableCheck(p+"momentum"))     m_model.momentumWeight     = GlobalVariableGet(p+"momentum");
      if(GlobalVariableCheck(p+"loss"))         m_model.lossStreakWeight   = GlobalVariableGet(p+"loss");
      if(GlobalVariableCheck(p+"volnoise"))     m_model.volNoiseWeight     = GlobalVariableGet(p+"volnoise");
      if(GlobalVariableCheck(p+"regimescore"))  m_model.regimeScoreWeight  = GlobalVariableGet(p+"regimescore");
      if(GlobalVariableCheck(p+"timeofday"))    m_model.timeOfDayWeight    = GlobalVariableGet(p+"timeofday");
      if(GlobalVariableCheck(p+"mtconfluence")) m_model.mtConfluenceWeight = GlobalVariableGet(p+"mtconfluence");
      if(GlobalVariableCheck(p+"volume"))       m_model.volumeWeight       = GlobalVariableGet(p+"volume");
      if(GlobalVariableCheck(p+"trendexpert"))     m_model.trendExpertWeight    = GlobalVariableGet(p+"trendexpert");
      if(GlobalVariableCheck(p+"meanrevexpert"))   m_model.meanRevExpertWeight  = GlobalVariableGet(p+"meanrevexpert");
      if(GlobalVariableCheck(p+"momentumexpert"))  m_model.momentumExpertWeight = GlobalVariableGet(p+"momentumexpert");
      if(GlobalVariableCheck(p+"recentwr"))     m_model.recentWinRate      = GlobalVariableGet(p+"recentwr");
      if(GlobalVariableCheck(p+"longtermwr"))   m_model.longTermWinRate    = GlobalVariableGet(p+"longtermwr");

      for(int i=0;i<NN_INPUTS;i++) for(int j=0;j<NN_H1;j++)
      { string k=p+"h1w_"+IntegerToString(i)+"_"+IntegerToString(j); if(GlobalVariableCheck(k)) m_model.h1w[i][j]=GlobalVariableGet(k); }
      for(int j=0;j<NN_H1;j++) { string k=p+"h1b_"+IntegerToString(j); if(GlobalVariableCheck(k)) m_model.h1b[j]=GlobalVariableGet(k); }
      for(int i=0;i<NN_H1;i++) for(int j=0;j<NN_H2;j++)
      { string k=p+"h2w_"+IntegerToString(i)+"_"+IntegerToString(j); if(GlobalVariableCheck(k)) m_model.h2w[i][j]=GlobalVariableGet(k); }
      for(int j=0;j<NN_H2;j++) { string k=p+"h2b_"+IntegerToString(j); if(GlobalVariableCheck(k)) m_model.h2b[j]=GlobalVariableGet(k); }
      for(int j=0;j<NN_H2;j++) { string k=p+"ow_"+IntegerToString(j);  if(GlobalVariableCheck(k)) m_model.ow[j] =GlobalVariableGet(k); }
      if(GlobalVariableCheck(p+"ob"))     m_model.ob               = GlobalVariableGet(p+"ob");
      if(GlobalVariableCheck(p+"plattA")) m_model.plattA           = GlobalVariableGet(p+"plattA");
      if(GlobalVariableCheck(p+"plattB")) m_model.plattB           = GlobalVariableGet(p+"plattB");
      if(GlobalVariableCheck(p+"plattS")) m_model.plattSamples     = (int)GlobalVariableGet(p+"plattS");
      if(GlobalVariableCheck(p+"nn_lr"))  m_model.nnLearningRate   = GlobalVariableGet(p+"nn_lr");
      if(GlobalVariableCheck(p+"nn_ts"))  m_model.nnTrainingSamples= (int)GlobalVariableGet(p+"nn_ts");
      if(GlobalVariableCheck(p+"nn_rb"))  m_model.replayTrainCount = (int)GlobalVariableGet(p+"nn_rb");

      // [v2.06+] Do NOT call SaveModelState() here
      m_model.initialized = true;
      Log("📥 Model loaded. NN samples=" + IntegerToString(m_model.nnTrainingSamples) +
          " batches=" + IntegerToString(m_model.replayTrainCount));
   }

   void SaveModelState(const StrategyConfig &cfg)
   {
      string p = ModelGVPrefix(cfg);
      GlobalVariableSet(p+"bias",         m_model.bias);
      GlobalVariableSet(p+"atr",          m_model.atrWeight);
      GlobalVariableSet(p+"spread",       m_model.spreadWeight);
      GlobalVariableSet(p+"sl",           m_model.slWeight);
      GlobalVariableSet(p+"momentum",     m_model.momentumWeight);
      GlobalVariableSet(p+"loss",         m_model.lossStreakWeight);
      GlobalVariableSet(p+"volnoise",     m_model.volNoiseWeight);
      GlobalVariableSet(p+"regimescore",  m_model.regimeScoreWeight);
      GlobalVariableSet(p+"timeofday",    m_model.timeOfDayWeight);
      GlobalVariableSet(p+"mtconfluence", m_model.mtConfluenceWeight);
      GlobalVariableSet(p+"volume",       m_model.volumeWeight);
      GlobalVariableSet(p+"trendexpert",    m_model.trendExpertWeight);
      GlobalVariableSet(p+"meanrevexpert",  m_model.meanRevExpertWeight);
      GlobalVariableSet(p+"momentumexpert", m_model.momentumExpertWeight);
      GlobalVariableSet(p+"recentwr",     m_model.recentWinRate);
      GlobalVariableSet(p+"longtermwr",   m_model.longTermWinRate);

      for(int i=0;i<NN_INPUTS;i++) for(int j=0;j<NN_H1;j++)
         GlobalVariableSet(p+"h1w_"+IntegerToString(i)+"_"+IntegerToString(j), m_model.h1w[i][j]);
      for(int j=0;j<NN_H1;j++) GlobalVariableSet(p+"h1b_"+IntegerToString(j), m_model.h1b[j]);
      for(int i=0;i<NN_H1;i++) for(int j=0;j<NN_H2;j++)
         GlobalVariableSet(p+"h2w_"+IntegerToString(i)+"_"+IntegerToString(j), m_model.h2w[i][j]);
      for(int j=0;j<NN_H2;j++) GlobalVariableSet(p+"h2b_"+IntegerToString(j), m_model.h2b[j]);
      for(int j=0;j<NN_H2;j++) GlobalVariableSet(p+"ow_"+IntegerToString(j), m_model.ow[j]);
      GlobalVariableSet(p+"ob",      m_model.ob);
      GlobalVariableSet(p+"plattA",  m_model.plattA);
      GlobalVariableSet(p+"plattB",  m_model.plattB);
      GlobalVariableSet(p+"plattS",  (double)m_model.plattSamples);
      GlobalVariableSet(p+"nn_lr",   m_model.nnLearningRate);
      GlobalVariableSet(p+"nn_ts",   (double)m_model.nnTrainingSamples);
      GlobalVariableSet(p+"nn_rb",   (double)m_model.replayTrainCount);
      m_modelDirty = false;
   }

   // ─── Sample Management ─────────────────────────────────────────

   string CreateSampleId()
   { m_loggedSamples++; return "S" + IntegerToString(m_loggedSamples) + "_" + IntegerToString((int)TimeCurrent()); }

   void RegisterPendingSample(const string &sampleId, bool accepted,
                              double atrPoints, double support, double resistance,
                              const SignalDecision &signal, const EvalContext &ctx)
   {
      AISignalSample sample;
      sample.sampleId   = sampleId;
      sample.ticket     = 0;
      sample.timestamp  = TimeCurrent();
      sample.accepted   = accepted;
      sample.labeled    = false;
      sample.atrPoints  = atrPoints;
      sample.support    = support;
      sample.resistance = resistance;
      sample.signal     = signal;
      sample.volatility   = (CheckPointer(m_regime) != POINTER_INVALID)
                            ? m_regime.GetVolatilityScore()
                            : NormalizeVolatilityFeatureFallback();
      sample.mtConfluence = (CheckPointer(m_regime) != POINTER_INVALID)
                            ? m_regime.GetRegimeScore()
                            : NormalizeMultiTimeframeConfluenceFallback(signal);
      sample.volumeRatio  = ctx.volumeNorm;
      sample.zoneStrength = ctx.zoneNorm;
      sample.slMultiplier = signal.slMultiplier;
      sample.patternType  = (int)signal.patternType;
      sample.features[0]  = ctx.atrNorm;
      sample.features[1]  = ctx.regimeScore;
      sample.features[2]  = ctx.mtConfluenceNorm;
      sample.features[3]  = ctx.rsiNorm;
      sample.features[4]  = ctx.candleBodyRatio;
      sample.features[5]  = ctx.emaDistNorm;
      sample.features[6]  = ctx.sessionNorm;
      sample.features[7]  = ctx.momentumNorm;

      int sz = ArraySize(m_pendingSamples);
      ArrayResize(m_pendingSamples, sz + 1);
      m_pendingSamples[sz] = sample;
      while(ArraySize(m_pendingSamples) > 64) ArrayRemove(m_pendingSamples, 0);
   }

   // [v2.06] 60s window (was 15s)
   int FindRecentPendingSampleIndex() const
   {
      for(int i = ArraySize(m_pendingSamples) - 1; i >= 0; --i)
         if(m_pendingSamples[i].ticket == 0 && !m_pendingSamples[i].labeled &&
            TimeCurrent() - m_pendingSamples[i].timestamp <= 60) return i;
      return -1;
   }

   int FindPendingSampleIndexByTicket(ulong ticket) const
   {
      for(int i = ArraySize(m_pendingSamples) - 1; i >= 0; --i)
         if(m_pendingSamples[i].ticket == ticket) return i;
      return -1;
   }

   void AttachTicketToRecentSample(ulong ticket)
   {
      int idx = FindRecentPendingSampleIndex();
      if(idx < 0) return;
      m_pendingSamples[idx].ticket = ticket;
      AppendCsvRow(m_ticketMapFilename,
                   "sample_id","ticket","accepted","attached_time",
                   m_pendingSamples[idx].sampleId,
                   IntegerToString((int)ticket),
                   m_pendingSamples[idx].accepted ? "1" : "0",
                   TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
   }

   void LabelSampleOutcome(ulong ticket, double pnl)
   {
      int idx = FindPendingSampleIndexByTicket(ticket);
      if(idx < 0 || m_pendingSamples[idx].labeled) return;
      m_pendingSamples[idx].labeled = true;

      AppendCsvRow(m_outcomeFilename,
                   "sample_id","ticket","pnl","label_time",
                   m_pendingSamples[idx].sampleId,
                   IntegerToString((int)ticket),
                   DoubleToString(pnl, 2),
                   TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));

      double label = (pnl > 0) ? 1.0 : 0.0;
      PushReplayBuffer(m_pendingSamples[idx].features, label);

      m_labeledSinceLastBatch++;
      if(m_labeledSinceLastBatch >= MINIBATCH_SIZE)
      {
         TrainMiniBatch();
         StrategyConfig cfg; m_data.GetConfigCache(cfg);
         m_modelDirty = true;
         SaveModelState(cfg);
      }

      Log("Labeled: PnL=" + DoubleToString(pnl, 2) +
          " | " + (pnl > 0 ? "WIN" : "LOSS") +
          " | replay=" + IntegerToString(m_replayCount));
   }
   
   //+------------------------------------------------------------------+
   //| Time-Based Labeling: Check price X bars ahead for win/loss
   //| Replaces slow close-position-based labeling with forward-looking
   //+------------------------------------------------------------------+
   void ApplyTimeBasedLabel(AISignalSample &sample, int lookforwardBars = 5, double profitThreshold = 1.5)
   {
      if(!sample.accepted || sample.labeled) return;
      
      MqlRates futureBars[];
      ArrayResize(futureBars, lookforwardBars);
      
      // Get bars starting from entry point (shift=0 from sample timestamp)
      // We need to find the bar index corresponding to sample.timestamp
      datetime entryTime = sample.timestamp;
      int totalBars = Bars(_Symbol, _Period);
      
      // Find position of entry bar
      int entryIndex = -1;
      MqlRates tempBar[1];
      for(int i = 1; i < totalBars && i < 50; i++)
      {
         if(CopyRates(_Symbol, _Period, i, 1, tempBar) == 1)
         {
            if(tempBar[0].time <= entryTime && tempBar[0].time >= entryTime - PeriodSeconds(_Period))
            {
               entryIndex = i;
               break;
            }
         }
      }
      
      if(entryIndex < 0 || entryIndex + lookforwardBars >= totalBars)
         return;  // Not enough data
      
      // Get future bars for labeling
      if(CopyRates(_Symbol, _Period, entryIndex - lookforwardBars, lookforwardBars, futureBars) < lookforwardBars)
         return;
      
      // Calculate max profit potential over lookforward period
      double maxProfit = 0.0;
      double maxAdverse = 0.0;
      
      for(int i = 0; i < lookforwardBars; i++)
      {
         double highDiff = futureBars[i].high - sample.signal.entryPrice;
         double lowDiff = sample.signal.entryPrice - futureBars[i].low;
         
         if(sample.signal.type == ORDER_TYPE_BUY)
         {
            maxProfit = MathMax(maxProfit, highDiff);
            maxAdverse = MathMax(maxAdverse, lowDiff);
         }
         else if(sample.signal.type == ORDER_TYPE_SELL)
         {
            maxProfit = MathMax(maxProfit, lowDiff);
            maxAdverse = MathMax(maxAdverse, highDiff);
         }
      }
      
      // Normalize by ATR at entry
      double atrNorm = (sample.atrPoints > 0) ? maxProfit / sample.atrPoints : 0.0;
      double adverseNorm = (sample.atrPoints > 0) ? maxAdverse / sample.atrPoints : 0.0;
      
      // Label based on whether profit threshold was reached before stop
      double label = 0.0;
      if(atrNorm >= profitThreshold && adverseNorm < profitThreshold * 0.5)
         label = 1.0;  // Win: reached profit target without major drawdown
      else if(adverseNorm >= profitThreshold * 0.5)
         label = -1.0; // Loss: hit significant drawdown
      
      // Record time-based label
      if(label != 0.0)
      {
         sample.labeled = true;
         PushReplayBuffer(sample.features, label);
         
         AppendCsvRow(m_outcomeFilename,
                      "sample_id","ticket","pnl","label_time","label_type","atr_norm","adverse_norm",
                      sample.sampleId,
                      IntegerToString((int)sample.ticket),
                      "0.00",  // No actual PnL yet
                      TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
                      "TIME_BASED",
                      DoubleToString(atrNorm, 2),
                      DoubleToString(adverseNorm, 2));
         
         m_labeledSinceLastBatch++;
         if(m_labeledSinceLastBatch >= MINIBATCH_SIZE)
         {
            TrainMiniBatch();
            StrategyConfig cfg; m_data.GetConfigCache(cfg);
            m_modelDirty = true;
            SaveModelState(cfg);
         }
         
         Log("TimeBasedLabel: " + (label > 0 ? "WIN" : "LOSS") +
             " | ATR_Norm=" + DoubleToString(atrNorm, 2) +
             " | Adv_Norm=" + DoubleToString(adverseNorm, 2));
      }
   }

   void AppendCsvRow(const string filename,
                     const string h1, const string h2, const string h3, const string h4,
                     const string v1, const string v2, const string v3, const string v4)
   {
      int handle = FileOpen(filename, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI);
      if(handle == INVALID_HANDLE) return;
      FileSeek(handle, 0, SEEK_END);
      if(FileTell(handle) == 0) FileWrite(handle, h1, h2, h3, h4);
      FileWrite(handle, v1, v2, v3, v4);
      FileClose(handle);
   }

   void LogSignalSample(const SignalDecision &signal, double atrPoints,
                        double support, double resistance, double score,
                        bool accepted, const StrategyConfig &cfg,
                        const EvalContext &ctx)
   {
      string sampleId = CreateSampleId();

      int handle = FileOpen(m_datasetFilename, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI);
      if(handle == INVALID_HANDLE) return;
      FileSeek(handle, 0, SEEK_END);
      if(FileTell(handle) == 0)
         FileWrite(handle, "sample_id","time","symbol","pattern","bias","atr","spread",
                   "sl_mult","zone_conf","loss_streak","regime_score","volatility_score","timeofday",
                   "mt_confluence","volume","rsi","candle_body","ema_dist","session",
                   "trend_score","meanrev_score","momentum_score","ensemble_score",
                   "regime_type","accepted");

      long sp = 0; SymbolInfoInteger(_Symbol, SYMBOL_SPREAD, sp);
      int  losses   = (CheckPointer(m_data) != POINTER_INVALID) ? m_data.GetConsecutiveLosses() : 0;
      string regType = "UNKNOWN";
      double regVal  = 0.5, volVal = 0.5;
      if(CheckPointer(m_regime) != POINTER_INVALID)
      { regVal = m_regime.GetRegimeScore(); volVal = m_regime.GetVolatilityScore(); regType = m_regime.GetDescription(); }

      double trendScore    = EvaluateTrendExpert(signal, ctx, cfg);
      double meanRevScore  = EvaluateMeanReversionExpert(signal, ctx, cfg);
      double momentumScore = EvaluateMomentumExpert(ctx);

      FileWrite(handle,
                sampleId,
                TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
                _Symbol,
                IntegerToString((int)signal.patternType),
                DoubleToString(m_model.bias, 3),
                DoubleToString(atrPoints, 2),
                DoubleToString((double)sp, 2),
                DoubleToString(signal.slMultiplier, 2),
                DoubleToString(ctx.zoneNorm, 2),
                IntegerToString(losses),
                DoubleToString(regVal, 4),
                DoubleToString(volVal, 4),
                DoubleToString(ctx.timeOfDayNorm, 2),
                DoubleToString(ctx.mtConfluenceNorm, 4),
                DoubleToString(ctx.volumeNorm, 4),
                DoubleToString(ctx.rsiNorm, 4),
                DoubleToString(ctx.candleBodyRatio, 4),
                DoubleToString(ctx.emaDistNorm, 4),
                DoubleToString(ctx.sessionNorm, 2),
                DoubleToString(trendScore, 4),
                DoubleToString(meanRevScore, 4),
                DoubleToString(momentumScore, 4),
                DoubleToString(score, 4),
                regType,
                accepted ? "1" : "0");
      FileClose(handle);

      RegisterPendingSample(sampleId, accepted, atrPoints, support, resistance, signal, ctx);
   }

   // ─── Adaptive Model ────────────────────────────────────────────

   void AdaptModelToPerformance()
   {
      if(CheckPointer(m_data) == POINTER_INVALID) return;
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      PerformanceStats stats = m_data.GetPerformanceStats();
      int total = stats.safeTotal + stats.aggTotal;
      if(total <= 0) return;

      double winRate = (double)(stats.safeWins + stats.aggWins) / total;
      if(m_model.recentWinRate  < 0) m_model.recentWinRate  = winRate;
      else                            m_model.recentWinRate  = m_model.recentWinRate  * 0.9  + winRate * 0.1;
      if(m_model.longTermWinRate< 0) m_model.longTermWinRate = winRate;
      else                            m_model.longTermWinRate = m_model.longTermWinRate* 0.95 + winRate * 0.05;

      bool drift = DetectConceptDrift();
      if(MathAbs(winRate - m_lastSavedWinRate) < 0.01 && !drift) return;

      double error = winRate - 0.50;
      m_model.bias              = NormalizeWeight(m_model.bias              + error * 0.08);
      m_model.atrWeight         = NormalizeWeight(m_model.atrWeight         + error * 0.015);
      m_model.spreadWeight      = NormalizeWeight(m_model.spreadWeight      + error * 0.015);
      m_model.slWeight          = NormalizeWeight(m_model.slWeight          + error * 0.012);
      m_model.momentumWeight    = NormalizeWeight(m_model.momentumWeight    + error * 0.01);
      m_model.lossStreakWeight   = NormalizeWeight(m_model.lossStreakWeight  - m_data.GetConsecutiveLosses() * 0.005);
      m_model.regimeScoreWeight  = NormalizeWeight(m_model.regimeScoreWeight + error * 0.01);

      if(drift) { Log("CONCEPT DRIFT detected. Rebalancing ensemble..."); AdaptEnsembleWeights(error); }

      m_lastSavedWinRate = winRate;
      m_modelDirty = true;
      SaveModelState(cfg);
      Log("AI updated winRate=" + DoubleToString(winRate, 2) + (drift ? " [DRIFT]" : ""));
   }

   bool DetectConceptDrift() const
   {
      if(m_model.recentWinRate < 0 || m_model.longTermWinRate < 0) return false;
      return (m_model.longTermWinRate - m_model.recentWinRate) > 0.15;
   }

   //+------------------------------------------------------------------+
   //| [v2.07 FIX] AdaptEnsembleWeights: normalize total weight after   |
   //| adjust so ratios stay consistent (was missing in v2.06)          |
   //+------------------------------------------------------------------+
   void AdaptEnsembleWeights(double error)
   {
      m_model.trendExpertWeight    = NormalizeWeight(m_model.trendExpertWeight    + error * 0.15);
      m_model.meanRevExpertWeight  = NormalizeWeight(m_model.meanRevExpertWeight  - error * 0.05);
      m_model.momentumExpertWeight = NormalizeWeight(m_model.momentumExpertWeight + error * 0.08);

      // [v2.07 FIX] Re-normalize so weights sum to 1.0 for interpretability
      double total = m_model.trendExpertWeight + m_model.meanRevExpertWeight + m_model.momentumExpertWeight;
      if(total > 0.0)
      {
         m_model.trendExpertWeight    /= total;
         m_model.meanRevExpertWeight  /= total;
         m_model.momentumExpertWeight /= total;
      }

      Log("Ensemble rebalanced: T=" + DoubleToString(m_model.trendExpertWeight, 3) +
          " MR=" + DoubleToString(m_model.meanRevExpertWeight, 3) +
          " Mo=" + DoubleToString(m_model.momentumExpertWeight, 3) +
          " (sum=1.0)");
   }

   void ExportDatasetForExternalTraining(int minSamples = 100)
   {
      if(m_loggedSamples < minSamples) { Log("Insufficient samples for export."); return; }
      if(CheckPointer(m_data) == POINTER_INVALID) return;
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      string fn = "AI_ml_export_" + IntegerToString(cfg.risk.magic) + "_" + _Symbol + "_full.csv";
      int h = FileOpen(fn, FILE_WRITE|FILE_CSV|FILE_ANSI);
      if(h == INVALID_HANDLE) return;
      FileWrite(h, "timestamp","symbol","pattern_type","direction","entry_price",
                "sl_multiplier","tp_multiplier","atr_points","spread","regime_score",
                "volatility_score","time_of_day","mt_confluence","volume_ratio","zone_strength",
                "rsi","candle_body","ema_dist","session","loss_streak","bias",
                "trend_score","meanrev_score","momentum_score","ensemble_score",
                "regime_type","accepted","outcome_pnl","outcome_label");
      FileClose(h);
      Log("Export header written to: " + fn);
   }

public:
   int    GetNNTrainingSamples() const { return m_model.nnTrainingSamples; }
   double GetNNLearningRate()    const { return m_model.nnLearningRate; }
   int    GetReplayCount()       const { return m_replayCount; }
   int    GetReplayTrainCount()  const { return m_model.replayTrainCount; }
   double GetPlattA()            const { return m_model.plattA; }
   double GetPlattB()            const { return m_model.plattB; }
};

#endif
