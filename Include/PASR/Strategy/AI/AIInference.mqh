//+------------------------------------------------------------------+
//|                                                  AIInference.mqh |
//|          Pure forward-pass inference + expert scoring module     |
//|                                       Copyright 2026, Agsicentre |
//+------------------------------------------------------------------+
//| V3.01 FIXES:                                                     |
//| - AI-INF-FIX-1 [CRITICAL]: Double Logistic bug in Evaluate().   |
//|   expertScore (raw weighted sum) was passed directly into hybrid |
//|   blend alongside already-calibrated nnScore [0,1], then the    |
//|   whole hybrid was Logistic'd again. Fixed by normalizing        |
//|   expertScore to expertProb = Logistic(expertScore) first, then |
//|   blending two [0,1] values — no final Logistic needed.         |
//| - AI-INF-FIX-2 [MEDIUM]: SelectExpert now returns EXPERT_NONE   |
//|   when volume is critically low (spread proxy guard).            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#property version   "3.01"
#property strict

#ifndef __AI_INFERENCE_MQH__
#define __AI_INFERENCE_MQH__

#include "AITypes.mqh"
#include "../IManager.mqh"
#include "../12.MarketRegime.mqh"

/// Pure inference — no state mutation, no file I/O.
/// All methods are const. Receives model state and eval context by const-ref.
class AIInference
{
private:
   MarketRegimeFilter *m_regime; // non-owning

   double Logistic(double x)         const { return 1.0 / (1.0 + MathExp(-x)); }
   double NormalizeWeight(double v)  const { return MathMax(0.01, MathMin(2.0, v)); }

public:
   AIInference() : m_regime(NULL) {}
   void SetRegime(MarketRegimeFilter *r) { m_regime = r; }

   //--- Select the active expert based on current regime
   //    AI-INF-FIX-2: guard against abnormally wide spread (illiquid market)
   ExpertType SelectExpert() const
   {
      if(CheckPointer(m_regime) == POINTER_INVALID) return EXPERT_NONE;

      // Guard: skip trading when spread is critically wide (>30 points)
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

   //--- Adaptive threshold — regime uncertainty raises the bar
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
      double adaptive = baseThreshold + uncertainty * 0.15;
      return MathMax(baseThreshold, MathMin(0.9, adaptive));
   }

   //--- Expert scorers (pure — const ref inputs, no mutation)
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

   //--- Forward pass through the 2-hidden-layer NN
   double ForwardPass(const AIModelState &m, const EvalContext &ctx) const
   {
      if(!m.initialized) return 0.5;
      double feat[NN_INPUTS];
      feat[0]=ctx.atrNorm;          feat[1]=ctx.regimeScore;
      feat[2]=ctx.mtConfluenceNorm; feat[3]=ctx.rsiNorm;
      feat[4]=ctx.candleBodyRatio;  feat[5]=ctx.emaDistNorm;
      feat[6]=ctx.sessionNorm;      feat[7]=ctx.momentumNorm;

      double h1[NN_H1];
      for(int j=0;j<NN_H1;j++)
      {
         double z=m.h1b[j];
         for(int i=0;i<NN_INPUTS;i++) z+=feat[i]*m.h1w[i][j];
         h1[j]=MathMax(0.0,z);
      }
      double h2[NN_H2];
      for(int j=0;j<NN_H2;j++)
      {
         double z=m.h2b[j];
         for(int i=0;i<NN_H1;i++) z+=h1[i]*m.h2w[i][j];
         h2[j]=MathMax(0.0,z);
      }
      double out=m.ob;
      for(int j=0;j<NN_H2;j++) out+=h2[j]*m.ow[j];
      return out;
   }

   //--- Platt scaling calibration
   double PlattCalibrate(const AIModelState &m, double nnRaw) const
   { return (m.plattSamples < 30) ? Logistic(nnRaw) : Logistic(m.plattA*nnRaw + m.plattB); }

   //--- Full signal evaluation — returns final [0,1] score
   //    AI-INF-FIX-1: expertScore normalised to expertProb via Logistic() BEFORE
   //    blending with nnScore. Both inputs to hybrid are now [0,1].
   //    Final Logistic() removed — blending two probabilities needs no sigmoid squash.
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

      // Normalize raw expert weighted sum to probability space [0,1]
      double expertProb = Logistic(expertScore);  // AI-INF-FIX-1

      double nnRaw    = ForwardPass(mdl, ctx);
      double nnScore  = PlattCalibrate(mdl, nnRaw);             // already [0,1]
      double nnWeight = MathMin(0.30, 0.005 * mdl.nnTrainingSamples);

      // Both sides are [0,1] — linear blend, no outer Logistic needed
      return (1.0 - nnWeight) * expertProb + nnWeight * nnScore; // AI-INF-FIX-1
   }
};

#endif // __AI_INFERENCE_MQH__
