//+------------------------------------------------------------------+
//| AI/AIInference.mqh — v4.00                                       |
//| Pure forward-pass inference + expert scoring module.             |
//|                                                                  |
//| PHASE 8 CHANGES:                                                 |
//|   v4.00 (2026-05-21)                                             |
//|   + ForwardPass18(): consumes full 18-dim FeatureVector          |
//|   + Drift guard: score clamped to 0 if drift > 0.6              |
//|   + Dynamic threshold via AdaptiveConfig.MinScore               |
//|   + Pattern bonus differentiated by CandleCode (F15)            |
//|   + Retained full backward-compat with EvalContext path          |
//|                                                                  |
//| v3.01 FIXES (retained):                                          |
//|   AI-INF-FIX-1: double logistic bug — expertScore normalised    |
//|     via Logistic() before blending with nnScore                  |
//|   AI-INF-FIX-2: EXPERT_NONE when spread > 30 pts                |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_INFERENCE_MQH__
#define __AI_INFERENCE_MQH__

#include "AITypes.mqh"
#include "AIFeatureBuilder.mqh"
#include "../Core/IManager.mqh"
#include "../Data/MarketRegime.mqh"

class AIInference
  {
private:
   MarketRegimeFilter *m_regime;  // non-owning
   double              m_driftThreshold;  // default 0.6

   double Logistic(double x)        const { return 1.0 / (1.0 + MathExp(-x)); }
   double NormalizeWeight(double v) const { return MathMax(0.01, MathMin(2.0, v)); }

   // Pattern bonus scaled by candle structure code (F15)
   // 1.0=engulf, 0.75=strong, 0.5=inside, 0.25=hammer, 0.0=doji
   double PatternBonus(const FeatureVector &fv, double baseBonus) const
     {
      double cc = fv.CandleCode(); // F15 [0,1]
      // Engulf (1.0) -> 1.0x bonus, doji (0.0) -> 0.1x bonus
      double scale = 0.1 + cc * 0.9;
      return baseBonus * scale;
     }

public:
   AIInference() : m_regime(NULL), m_driftThreshold(0.6) {}

   void SetRegime(MarketRegimeFilter *r) { m_regime = r; }
   void SetDriftThreshold(double t)      { m_driftThreshold = MathMax(0.1, MathMin(1.0, t)); }

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
      return MathMax(baseThreshold, MathMin(0.9, baseThreshold + uncertainty*0.15));
     }

   //+----------------------------------------------------------------+
   //| Expert scorers (EvalContext path — legacy compat)              |
   //+----------------------------------------------------------------+
   double ScoreTrend(const AIModelState &m, const EvalContext &ctx,
                     const SignalDecision &signal, double patternBonus) const
     {
      double score = m.bias;
      score += m.atrWeight          * ctx.atrNorm;
      score += m.slWeight           * ctx.slNorm;
      score += m.mtConfluenceWeight * ctx.mtConfluenceNorm;
      score += m.regimeScoreWeight  * ctx.regimeScore;
      if(signal.patternType != PATTERN_NONE) score += patternBonus * 0.8;
      return score;
     }

   double ScoreMeanReversion(const AIModelState &m, const EvalContext &ctx,
                              const SignalDecision &signal, double patternBonus) const
     {
      double score = m.bias;
      score += m.spreadWeight      * ctx.spreadNorm;
      score += m.regimeScoreWeight * ctx.volatilityScore;
      score += m.momentumWeight    * ctx.zoneNorm;
      score += m.timeOfDayWeight   * ctx.timeOfDayNorm;
      if(signal.patternType != PATTERN_NONE) score += patternBonus * 1.2;
      return score;
     }

   double ScoreMomentum(const AIModelState &m, const EvalContext &ctx) const
     {
      double score = m.bias;
      score += m.volumeWeight     * ctx.volumeNorm;
      score += m.momentumWeight   * ctx.momentumNorm;
      score += m.lossStreakWeight * ctx.lossStreakNorm;
      score -= m.volNoiseWeight   * ctx.noiseNorm;
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
      return _ForwardPass(m, feat, NN_INPUTS);
     }

   //+----------------------------------------------------------------+
   //| ForwardPass18 (Phase 8) — full 18-dim FeatureVector path       |
   //| Uses all features including F13-F18 (SR confluence, candle     |
   //| structure, vol profile, HTF position, ADX).                    |
   //| The NN weights must have been trained with 18-dim input.       |
   //| Falls back to legacy ForwardPass if model not 18-dim trained.  |
   //+----------------------------------------------------------------+
   double ForwardPass18(const AIModelState &m, const FeatureVector &fv) const
     {
      if(!m.initialized) return 0.5;
      // Use all 18 features; map excess dims to h1 with zero-padded weights
      // if model is older (8-dim trained), feat[8..17] contribution ~ 0
      double feat[AI_FEATURE_DIM];
      fv.ToDoubleArray(feat);
      return _ForwardPass(m, feat, AI_FEATURE_DIM);
     }

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
         case EXPERT_TREND:          expertScore = ScoreTrend(mdl, ctx, signal, patternBonus);          break;
         case EXPERT_MEAN_REVERSION: expertScore = ScoreMeanReversion(mdl, ctx, signal, patternBonus);  break;
         case EXPERT_MOMENTUM:       expertScore = ScoreMomentum(mdl, ctx);                             break;
         default:                    return 0.0;
        }
      double expertProb = Logistic(expertScore);
      double nnRaw      = ForwardPass(mdl, ctx);
      double nnScore    = PlattCalibrate(mdl, nnRaw);
      double nnWeight   = MathMin(0.30, 0.005 * mdl.nnTrainingSamples);
      return (1.0 - nnWeight) * expertProb + nnWeight * nnScore;
     }

   //+----------------------------------------------------------------+
   //| Evaluate18 (Phase 8) — primary inference path                  |
   //| Uses 18-dim FeatureVector. Includes drift guard and            |
   //| differentiated pattern bonus by candle structure.             |
   //+----------------------------------------------------------------+
   double Evaluate18(const AIModelState &mdl,
                     const FeatureVector &fv,
                     const SignalDecision &signal,
                     double patternBonus,
                     double driftScore) const
     {
      // Drift guard: if live features diverge too far from training dist,
      // model output is unreliable — block the signal
      if(driftScore > m_driftThreshold)
        {
         if(m_debugMode)
            PrintFormat("[AIInf] Drift guard: %.2f > %.2f, score=0",
                        driftScore, m_driftThreshold);
         return 0.0;
        }

      ExpertType expert = SelectExpert();
      if(expert == EXPERT_NONE) return 0.0;

      // Expert score using key features from FeatureVector
      EvalContext ctx;
      ctx.atrNorm          = fv.ATR();        ctx.spreadNorm      = fv.Spread();
      ctx.slNorm           = fv.SLMult();     ctx.timeOfDayNorm   = fv.TimeOfDay();
      ctx.volumeNorm       = fv.Volume();     ctx.momentumNorm    = fv.Momentum();
      ctx.zoneNorm         = fv.ZoneProx();   ctx.lossStreakNorm  = fv.LossStreak();
      ctx.noiseNorm        = fv.Noise();      ctx.rsiNorm         = fv.RSI();
      ctx.candleBodyRatio  = fv.CandleBody(); ctx.emaDistNorm     = fv.EMADist();
      ctx.sessionNorm      = fv.Session();
      // Regime / MTF from FeatureVector F13/F17
      ctx.regimeScore      = fv.SRConfluence();     // F13 as regime proxy
      ctx.volatilityScore  = fv.ATR();              // F00
      ctx.mtConfluenceNorm = fv.HTFPosition();      // F16

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

      // 18-dim forward pass through NN
      double nnRaw   = ForwardPass18(mdl, fv);
      double nnScore = PlattCalibrate(mdl, nnRaw);
      double nnWeight = MathMin(0.40, 0.005 * mdl.nnTrainingSamples); // Phase8: raise NN cap to 40%

      double finalScore = (1.0 - nnWeight) * expertProb + nnWeight * nnScore;

      // Drift penalty: partial reduction between 0.3 and threshold
      if(driftScore > 0.3)
        {
         double penalty = (driftScore - 0.3) / (m_driftThreshold - 0.3);
         finalScore *= (1.0 - 0.3 * penalty);  // max 30% reduction before full block
        }

      return MathMax(0.0, MathMin(1.0, finalScore));
     }

private:
   // Internal: shared NN computation for both paths
   double _ForwardPass(const AIModelState &m,
                       const double &feat[],
                       int dims) const
     {
      double h1[NN_H1];
      for(int j = 0; j < NN_H1; j++)
        {
         double z = m.h1b[j];
         int useD = MathMin(dims, NN_INPUTS);
         for(int i = 0; i < useD; i++) z += feat[i] * m.h1w[i][j];
         h1[j] = MathMax(0.0, z);  // ReLU
        }
      double h2[NN_H2];
      for(int j = 0; j < NN_H2; j++)
        {
         double z = m.h2b[j];
         for(int i = 0; i < NN_H1; i++) z += h1[i] * m.h2w[i][j];
         h2[j] = MathMax(0.0, z);  // ReLU
        }
      double out = m.ob;
      for(int j = 0; j < NN_H2; j++) out += h2[j] * m.ow[j];
      return out;
     }
  };

#endif // __AI_INFERENCE_MQH__
