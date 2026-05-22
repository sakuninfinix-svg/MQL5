//+------------------------------------------------------------------+
//| AI/AIInference.mqh — v4.01                                       |
//| Pure forward-pass inference + expert scoring module.             |
//|                                                                  |
//| v4.01 CHANGES (2026-05-21):                                      |
//|   + Evaluate26(): primary path for 26-dim FeatureVector          |
//|   + Evaluate18(): retained for backward compat, delegates to 26  |
//|   + Expert scorers: consume F19-F26 weights from AIModelState    |
//|       ScoreTrend:         +srProxWeight, +htfTrendWeight         |
//|       ScoreMeanReversion: +wickRatioWeight, +srProxWeight        |
//|       ScoreMomentum:      +atrPercentileWeight                   |
//|   + FIX: remove non-existent ToDoubleArray()                     |
//|       NN path now uses fv.ToNNInputs() (12-dim)                  |
//|       Expert path uses fv.f[] direct access                      |
//|   + FIX: m_debugMode member declaration added                    |
//|   + FIX: Evaluate18/26 EvalContext maps F19-F26 new fields       |
//|                                                                  |
//| v4.00 CHANGES (retained):                                        |
//|   + ForwardPass18(): 18-dim FeatureVector path                   |
//|   + Drift guard: score clamped to 0 if drift > 0.6              |
//|   + Dynamic threshold via AdaptiveConfig.MinScore               |
//|   + Pattern bonus by CandleCode (F15)                           |
//|                                                                  |
//| v3.01 FIXES (retained):                                          |
//|   AI-INF-FIX-1: double logistic bug fixed                       |
//|   AI-INF-FIX-2: EXPERT_NONE when spread > 30 pts                |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_INFERENCE_MQH__
#define __AI_INFERENCE_MQH__

#include "AITypes.mqh"
#include "AIFeatureBuilder.mqh"
#include "../Core/IManager.mqh"
#include "../Data/RegimeTypes.mqh"

class AIInference
  {
private:
   MarketRegimeFilter *m_regime;         // non-owning
   double              m_driftThreshold; // default 0.6
   bool                m_debugMode;      // FIX v4.01: was referenced but undeclared

   double Logistic(double x)        const { return 1.0 / (1.0 + MathExp(-x)); }
   double NormalizeWeight(double v) const { return MathMax(0.01, MathMin(2.0, v)); }

   // Pattern bonus scaled by candle structure code (F15)
   // 1.0=engulf, 0.75=strong, 0.5=inside, 0.25=hammer, 0.0=doji
   double PatternBonus(const FeatureVector &fv, double baseBonus) const
     {
      double cc    = fv.CandleCode(); // F15 [0,1]
      double scale = 0.1 + cc * 0.9; // engulf->1.0x, doji->0.1x
      return baseBonus * scale;
     }

public:
   AIInference() : m_regime(NULL), m_driftThreshold(0.6), m_debugMode(false) {}

   void SetRegime(MarketRegimeFilter *r) { m_regime = r; }
   void SetDriftThreshold(double t)      { m_driftThreshold = MathMax(0.1, MathMin(1.0, t)); }
   void SetDebugMode(bool d)             { m_debugMode = d; }

   //+----------------------------------------------------------------+
   //| Expert routing — selects scorer by regime                      |
   //+----------------------------------------------------------------+
   ExpertType SelectExpert() const
     {
      if(CheckPointer(m_regime) == POINTER_INVALID) return EXPERT_NONE;
      long spread = 0;
      SymbolInfoInteger(_Symbol, SYMBOL_SPREAD, spread);
      if(spread > 30) return EXPERT_NONE;
      ENUM_MARKET_REGIME regime     = m_regime.GetMarketRegime();
      double             confidence = m_regime.GetResult().regimeScore;
      if(regime == REGIME_TRANSITION || confidence < 0.3) return EXPERT_NONE;
      switch(regime)
        {
         case REGIME_TRENDING_STRONG:
         case REGIME_TRENDING_WEAK:    return EXPERT_TREND;
         case REGIME_RANGING_SIDEWAYS: return EXPERT_MEAN_REVERSION;
         case REGIME_CHOPPY_HIGH_VOL:  return EXPERT_MOMENTUM;
         default:                      return EXPERT_NONE;
        }
     }

   //+----------------------------------------------------------------+
   //| Adaptive threshold — regime uncertainty raises the bar         |
   //+----------------------------------------------------------------+
   double AdaptiveThreshold(double baseThreshold) const
     {
      if(CheckPointer(m_regime) == POINTER_INVALID) return baseThreshold;
      const RegimeResult &r = m_regime.GetResult();
      double uncertainty = 0.0;
      switch(r.regime)
        {
         case REGIME_TRANSITION:       uncertainty = 1.0; break;
         case REGIME_CHOPPY_HIGH_VOL:  uncertainty = 0.8; break;
         case REGIME_RANGING_SIDEWAYS: uncertainty = 0.5; break;
         case REGIME_TRENDING_WEAK:    uncertainty = 0.3; break;
         case REGIME_TRENDING_STRONG:  uncertainty = 0.1; break;
         default:                      uncertainty = 0.6; break;
        }
      if(!r.mtfConfirmed) uncertainty *= 1.3;
      return MathMax(baseThreshold, MathMin(0.9, baseThreshold + uncertainty * 0.15));
     }

   //+----------------------------------------------------------------+
   //| Expert scorers — v4.01: consume F19-F26 weights                |
   //+----------------------------------------------------------------+

   // Trend expert: ATR quality + SL distance + MTF confluence + SR proximity bull
   // + HTF H4 trend alignment
   double ScoreTrend(const AIModelState &m, const EvalContext &ctx,
                     const SignalDecision &signal, double patternBonus) const
     {
      double score = m.bias;
      score += m.atrWeight          * ctx.atrNorm;
      score += m.slWeight           * ctx.slNorm;
      score += m.mtConfluenceWeight * ctx.mtConfluenceNorm;
      score += m.regimeScoreWeight  * ctx.regimeScore;
      // v4.01: SR proximity and HTF trend are high-value for trend following
      score += m.srProxWeight       * ctx.srProxBull;   // F19: price at support
      score += m.htfTrendWeight     * ctx.htfTrendH4;   // F25: H4 EMA alignment
      if(signal.patternType != PATTERN_NONE) score += patternBonus * 0.8;
      return score;
     }

   // Mean reversion expert: spread quality + zone proximity + wick rejections
   // + SR proximity bear (price at resistance = mean reversion sell)
   double ScoreMeanReversion(const AIModelState &m, const EvalContext &ctx,
                              const SignalDecision &signal, double patternBonus) const
     {
      double score = m.bias;
      score += m.spreadWeight      * ctx.spreadNorm;
      score += m.regimeScoreWeight * ctx.volatilityScore;
      score += m.momentumWeight    * ctx.zoneNorm;
      score += m.timeOfDayWeight   * ctx.timeOfDayNorm;
      // v4.01: wick rejections and SR proximity are core mean reversion signals
      score += m.wickRatioWeight   * MathMax(ctx.upperWickRatio, ctx.lowerWickRatio); // F21/F22
      score += m.srProxWeight      * ctx.srProxBear;    // F20: price at resistance
      if(signal.patternType != PATTERN_NONE) score += patternBonus * 1.2;
      return score;
     }

   // Momentum expert: volume + momentum + loss streak + noise avoidance
   // + ATR percentile (high ATR rank = expansion = momentum context)
   double ScoreMomentum(const AIModelState &m, const EvalContext &ctx) const
     {
      double score = m.bias;
      score += m.volumeWeight          * ctx.volumeNorm;
      score += m.momentumWeight        * ctx.momentumNorm;
      score += m.lossStreakWeight       * ctx.lossStreakNorm;
      score -= m.volNoiseWeight         * ctx.noiseNorm;
      // v4.01: ATR percentile rank — high = expansion regime = good for momentum
      score += m.atrPercentileWeight   * ctx.atrPercentile; // F26
      return score;
     }

   //+----------------------------------------------------------------+
   //| ForwardPass (8-feat, legacy) — EvalContext path                |
   //+----------------------------------------------------------------+
   double ForwardPass(const AIModelState &m, const EvalContext &ctx) const
     {
      if(!m.initialized) return 0.5;
      double feat[NN_INPUTS];
      feat[0]=ctx.atrNorm;          feat[1]=ctx.regimeScore;
      feat[2]=ctx.mtConfluenceNorm; feat[3]=ctx.rsiNorm;
      feat[4]=ctx.candleBodyRatio;  feat[5]=ctx.emaDistNorm;
      feat[6]=ctx.sessionNorm;      feat[7]=ctx.momentumNorm;
      // v4.01: fill new NN input slots (F8-F11) from extended EvalContext
      feat[8] = ctx.srProxBull;     // F19
      feat[9] = ctx.hourSin;        // F23
      feat[10]= ctx.htfTrendH4;     // F25
      feat[11]= ctx.atrPercentile;  // F26
      return _ForwardPass(m, feat);
     }

   //+----------------------------------------------------------------+
   //| ForwardPass26 — full 26-dim FeatureVector → 12-dim NN input    |
   //| Uses fv.ToNNInputs() to select the 12 most predictive dims     |
   //| for the NN branch (mapped in AIFeatureBuilder.ToNNInputs).     |
   //+----------------------------------------------------------------+
   double ForwardPass26(const AIModelState &m, const FeatureVector &fv) const
     {
      if(!m.initialized) return 0.5;
      double feat[NN_INPUTS];
      fv.ToNNInputs(feat);   // maps 26-dim → 12 selected dims
      return _ForwardPass(m, feat);
     }

   // Kept for backward compat — delegates to ForwardPass26
   double ForwardPass18(const AIModelState &m, const FeatureVector &fv) const
     { return ForwardPass26(m, fv); }

   //+----------------------------------------------------------------+
   //| Platt scaling calibration                                       |
   //+----------------------------------------------------------------+
   double PlattCalibrate(const AIModelState &m, double nnRaw) const
     { return (m.plattSamples < 30) ? Logistic(nnRaw)
              : Logistic(m.plattA * nnRaw + m.plattB); }

   //+----------------------------------------------------------------+
   //| Evaluate (legacy EvalContext path — backward compat)           |
   //+----------------------------------------------------------------+
   double Evaluate(const AIModelState &mdl, const EvalContext &ctx,
                   const SignalDecision &signal, double patternBonus) const
     {
      ExpertType expert = SelectExpert();
      if(expert == EXPERT_NONE) return 0.0;
      double expertScore = 0.0;
      switch(expert)
        {
         case EXPERT_TREND:          expertScore = ScoreTrend(mdl, ctx, signal, patternBonus);         break;
         case EXPERT_MEAN_REVERSION: expertScore = ScoreMeanReversion(mdl, ctx, signal, patternBonus); break;
         case EXPERT_MOMENTUM:       expertScore = ScoreMomentum(mdl, ctx);                            break;
         default:                    return 0.0;
        }
      double expertProb = Logistic(expertScore);
      double nnRaw      = ForwardPass(mdl, ctx);
      double nnScore    = PlattCalibrate(mdl, nnRaw);
      double nnWeight   = MathMin(0.30, 0.005 * mdl.nnTrainingSamples);
      return (1.0 - nnWeight) * expertProb + nnWeight * nnScore;
     }

   //+----------------------------------------------------------------+
   //| Evaluate26 — PRIMARY inference path (v4.01)                    |
   //| Consumes full 26-dim FeatureVector.                            |
   //| Includes drift guard, pattern bonus, F19-F26 expert weights.   |
   //+----------------------------------------------------------------+
   double Evaluate26(const AIModelState &mdl,
                     const FeatureVector &fv,
                     const SignalDecision &signal,
                     double patternBonus,
                     double driftScore) const
     {
      // Drift guard
      if(driftScore > m_driftThreshold)
        {
         if(m_debugMode)
            PrintFormat("[AIInf] Drift guard: %.2f > %.2f, score=0",
                        driftScore, m_driftThreshold);
         return 0.0;
        }

      ExpertType expert = SelectExpert();
      if(expert == EXPERT_NONE) return 0.0;

      // Build full EvalContext from 26-dim FeatureVector
      // F01-F18 (original)
      EvalContext ctx;
      ctx.atrNorm         = fv.ATR();          ctx.spreadNorm      = fv.Spread();
      ctx.slNorm          = fv.SLMult();       ctx.timeOfDayNorm   = fv.TimeOfDay();
      ctx.volumeNorm      = fv.Volume();       ctx.momentumNorm    = fv.Momentum();
      ctx.zoneNorm        = fv.ZoneProx();     ctx.lossStreakNorm  = fv.LossStreak();
      ctx.noiseNorm       = fv.Noise();        ctx.rsiNorm         = fv.RSI();
      ctx.candleBodyRatio = fv.CandleBody();   ctx.emaDistNorm     = fv.EMADist();
      ctx.sessionNorm     = fv.Session();
      // Regime proxies from structural features
      ctx.regimeScore      = fv.SRConfluence();  // F14: SR confluence as regime proxy
      ctx.volatilityScore  = fv.ATR();           // F01
      ctx.mtConfluenceNorm = fv.HTFPosition();   // F17: HTF close position
      // v4.01: F19-F26 new fields
      ctx.srProxBull      = fv.SRProxBull();    // F19
      ctx.srProxBear      = fv.SRProxBear();    // F20
      ctx.upperWickRatio  = fv.UpperWick();     // F21
      ctx.lowerWickRatio  = fv.LowerWick();     // F22
      ctx.hourSin         = fv.HourSin();       // F23
      ctx.hourCos         = fv.HourCos();       // F24
      ctx.htfTrendH4      = fv.HTFTrendH4();    // F25
      ctx.atrPercentile   = fv.ATRPercentile(); // F26

      double adjustedBonus = PatternBonus(fv, patternBonus);

      double expertScore = 0.0;
      switch(expert)
        {
         case EXPERT_TREND:          expertScore = ScoreTrend(mdl, ctx, signal, adjustedBonus);         break;
         case EXPERT_MEAN_REVERSION: expertScore = ScoreMeanReversion(mdl, ctx, signal, adjustedBonus); break;
         case EXPERT_MOMENTUM:       expertScore = ScoreMomentum(mdl, ctx);                             break;
         default:                    return 0.0;
        }

      double expertProb = Logistic(expertScore);

      // 26→12-dim NN forward pass via ToNNInputs()
      double nnRaw    = ForwardPass26(mdl, fv);
      double nnScore  = PlattCalibrate(mdl, nnRaw);
      double nnWeight = MathMin(0.40, 0.005 * mdl.nnTrainingSamples); // cap 40%

      double finalScore = (1.0 - nnWeight) * expertProb + nnWeight * nnScore;

      // Partial drift penalty [0.3, threshold)
      if(driftScore > 0.3)
        {
         double penalty = (driftScore - 0.3) / (m_driftThreshold - 0.3);
         finalScore *= (1.0 - 0.3 * penalty); // max 30% reduction before full block
        }

      if(m_debugMode)
         PrintFormat("[AIInf26] expert=%.3f nn=%.3f w=%.2f drift=%.2f → %.3f",
                     expertProb, nnScore, nnWeight, driftScore, finalScore);

      return MathMax(0.0, MathMin(1.0, finalScore));
     }

   // Backward compat alias — Evaluate18 delegates to Evaluate26
   double Evaluate18(const AIModelState &mdl,
                     const FeatureVector &fv,
                     const SignalDecision &signal,
                     double patternBonus,
                     double driftScore) const
     { return Evaluate26(mdl, fv, signal, patternBonus, driftScore); }

private:
   // Internal: NN forward pass — always uses 12-dim feat[] (NN_INPUTS)
   // v4.01: no longer accepts variable dims — caller must use ToNNInputs()
   double _ForwardPass(const AIModelState &m, const double &feat[]) const
     {
      double h1[NN_H1];
      for(int j = 0; j < NN_H1; j++)
        {
         double z = m.h1b[j];
         for(int i = 0; i < NN_INPUTS; i++) z += feat[i] * m.h1w[i][j];
         h1[j] = MathMax(0.0, z); // ReLU
        }
      double h2[NN_H2];
      for(int j = 0; j < NN_H2; j++)
        {
         double z = m.h2b[j];
         for(int i = 0; i < NN_H1; i++) z += h1[i] * m.h2w[i][j];
         h2[j] = MathMax(0.0, z); // ReLU
        }
      double out = m.ob;
      for(int j = 0; j < NN_H2; j++) out += h2[j] * m.ow[j];
      return out;
     }
  };

#endif // __AI_INFERENCE_MQH__
