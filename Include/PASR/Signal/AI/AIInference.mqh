//+------------------------------------------------------------------+
//| AI/AIInference.mqh — v4.02                                       |
//| Safe lightweight inference wrapper + expert scoring module        |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_INFERENCE_MQH__
#define __AI_INFERENCE_MQH__

#include "AITypes.mqh"
#include "AIFeatureBuilder.mqh"
#include "../RegimeFilter.mqh"
#include "../../Data/RegimeTypes.mqh"

#define AI_SCORE_NO_SIGNAL (-1.0)

#if NN_INPUTS != 12
  #error "AIInference requires NN_INPUTS == 12. Update ForwardPass mapping before changing NN_INPUTS."
#endif

class AIInference
  {
private:
   CRegimeFilter *m_regime;
   AIModelState   m_model;
   double         m_driftThreshold;
   double         m_confidence;
   bool           m_debugMode;
   bool           m_loaded;

   double Logistic(double x) const { return 1.0 / (1.0 + MathExp(-x)); }

   double PatternBonus(const FeatureVector &fv, double baseBonus) const
     {
      double cc = fv.CandleCode();
      return baseBonus * (0.1 + cc * 0.9);
     }

public:
   AIInference() : m_regime(NULL), m_driftThreshold(0.6),
                   m_confidence(0.0), m_debugMode(false), m_loaded(false)
     {}

   bool Init()
     {
      if(!m_model.initialized) m_model.InitWeights();
      m_confidence = 0.0;
      return true;
     }

   bool LoadModel(const string path, ENUM_AI_MODEL_TYPE type)
     {
      // Safe fallback loader: initialize built-in weights first. External file/ONNX
      // loading can be added later without blocking EA OnInit().
      if(!m_model.initialized) m_model.InitWeights();
      m_loaded = true;
      m_confidence = 0.5;
      return true;
     }

   void UnloadModel()
     {
      m_loaded = false;
      m_confidence = 0.0;
     }

   void SetRegime(CRegimeFilter *r) { m_regime = r; }
   void SetDriftThreshold(double t) { m_driftThreshold = MathMax(0.1, MathMin(1.0, t)); }
   void SetDebugMode(bool d) { m_debugMode = d; }
   double GetConfidence() const { return m_confidence; }
   bool IsLoaded() const { return m_loaded; }

   ExpertType SelectExpert() const
     {
      if(m_regime == NULL || !m_regime.IsReady()) return EXPERT_NONE;
      long spread = 0;
      SymbolInfoInteger(_Symbol, SYMBOL_SPREAD, spread);
      if(spread > 30) return EXPERT_NONE;
      EMarketRegime regime = m_regime.GetRegime();
      switch(regime)
        {
         case REGIME_TREND_UP:
         case REGIME_TREND_DOWN: return EXPERT_TREND;
         case REGIME_RANGE:      return EXPERT_MEAN_REVERSION;
         case REGIME_TRANSITION: return EXPERT_MOMENTUM;
         case REGIME_UNKNOWN:
         case REGIME_SQUEEZE:
         case REGIME_VOLATILE:
         case REGIME_CRASH:
         default:                return EXPERT_NONE;
        }
     }

   double AdaptiveThreshold(double baseThreshold) const
     {
      if(m_regime == NULL || !m_regime.IsReady()) return MathMax(baseThreshold, 0.70);
      EMarketRegime r = m_regime.GetRegime();
      if(r == REGIME_RANGE) return baseThreshold;
      if(r == REGIME_TREND_UP || r == REGIME_TREND_DOWN) return MathMax(baseThreshold, 0.60);
      if(r == REGIME_TRANSITION) return MathMax(baseThreshold, 0.75);
      return 0.95;
     }

   double ScoreTrend(const AIModelState &m, const EvalContext &ctx,
                     const SignalDecision &signal, double patternBonus) const
     {
      double score = m.bias;
      score += m.atrWeight          * ctx.atrNorm;
      score += m.slWeight           * ctx.slNorm;
      score += m.mtConfluenceWeight * ctx.mtConfluenceNorm;
      score += m.regimeScoreWeight  * ctx.regimeScore;
      score += m.srProxWeight       * ctx.srProxBull;
      score += m.htfTrendWeight     * ctx.htfTrendH4;
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
      score += m.wickRatioWeight   * MathMax(ctx.upperWickRatio, ctx.lowerWickRatio);
      score += m.srProxWeight      * ctx.srProxBear;
      if(signal.patternType != PATTERN_NONE) score += patternBonus * 1.2;
      return score;
     }

   double ScoreMomentum(const AIModelState &m, const EvalContext &ctx) const
     {
      double score = m.bias;
      score += m.volumeWeight        * ctx.volumeNorm;
      score += m.momentumWeight      * ctx.momentumNorm;
      score += m.lossStreakWeight    * ctx.lossStreakNorm;
      score -= m.volNoiseWeight      * ctx.noiseNorm;
      score += m.atrPercentileWeight * ctx.atrPercentile;
      return score;
     }

   double ForwardPass(const AIModelState &m, const EvalContext &ctx) const
     {
      if(!m.initialized) return 0.5;
      double feat[NN_INPUTS];
      ArrayInitialize(feat, 0.5);
      feat[0]=ctx.atrNorm;          feat[1]=ctx.regimeScore;
      feat[2]=ctx.mtConfluenceNorm; feat[3]=ctx.rsiNorm;
      feat[4]=ctx.candleBodyRatio;  feat[5]=ctx.emaDistNorm;
      feat[6]=ctx.sessionNorm;      feat[7]=ctx.momentumNorm;
      feat[8]=ctx.srProxBull;       feat[9]=ctx.hourSin;
      feat[10]=ctx.htfTrendH4;      feat[11]=ctx.atrPercentile;
      return _ForwardPass(m, feat);
     }

   double ForwardPass26(const AIModelState &m, const FeatureVector &fv) const
     {
      if(!m.initialized) return 0.5;
      double feat[];
      fv.ToNNInputs(feat);
      return _ForwardPass(m, feat);
     }

   double ForwardPass18(const AIModelState &m, const FeatureVector &fv) const
     { return ForwardPass26(m, fv); }

   double PlattCalibrate(const AIModelState &m, double nnRaw) const
     { return (m.plattSamples < 30) ? Logistic(nnRaw) : Logistic(m.plattA * nnRaw + m.plattB); }

   double Evaluate(const AIModelState &mdl, const EvalContext &ctx,
                   const SignalDecision &signal, double patternBonus) const
     {
      ExpertType expert = SelectExpert();
      if(expert == EXPERT_NONE) return AI_SCORE_NO_SIGNAL;
      double expertScore = 0.0;
      switch(expert)
        {
         case EXPERT_TREND:          expertScore = ScoreTrend(mdl, ctx, signal, patternBonus); break;
         case EXPERT_MEAN_REVERSION: expertScore = ScoreMeanReversion(mdl, ctx, signal, patternBonus); break;
         case EXPERT_MOMENTUM:       expertScore = ScoreMomentum(mdl, ctx); break;
         default:                    return AI_SCORE_NO_SIGNAL;
        }
      double expertProb = Logistic(expertScore);
      double nnScore = PlattCalibrate(mdl, ForwardPass(mdl, ctx));
      double nnWeight = MathMin(0.30, 0.005 * mdl.nnTrainingSamples);
      return MathMax(0.0, MathMin(1.0, (1.0 - nnWeight) * expertProb + nnWeight * nnScore));
     }

   double Evaluate26(const AIModelState &mdl, const FeatureVector &fv,
                     const SignalDecision &signal, double patternBonus,
                     double driftScore) const
     {
      if(driftScore > m_driftThreshold) return AI_SCORE_NO_SIGNAL;
      ExpertType expert = SelectExpert();
      if(expert == EXPERT_NONE) return AI_SCORE_NO_SIGNAL;

      EvalContext ctx;
      ctx.Reset();
      ctx.atrNorm=fv.ATR(); ctx.spreadNorm=fv.Spread(); ctx.slNorm=fv.SLMult();
      ctx.timeOfDayNorm=fv.TimeOfDay(); ctx.volumeNorm=fv.Volume(); ctx.momentumNorm=fv.Momentum();
      ctx.zoneNorm=fv.ZoneProx(); ctx.lossStreakNorm=fv.LossStreak(); ctx.noiseNorm=fv.Noise();
      ctx.rsiNorm=fv.RSI(); ctx.candleBodyRatio=fv.CandleBody(); ctx.emaDistNorm=fv.EMADist();
      ctx.sessionNorm=fv.Session(); ctx.regimeScore=fv.SRConfluence(); ctx.volatilityScore=fv.ATR();
      ctx.mtConfluenceNorm=fv.HTFPosition(); ctx.srProxBull=fv.SRProxBull(); ctx.srProxBear=fv.SRProxBear();
      ctx.upperWickRatio=fv.UpperWick(); ctx.lowerWickRatio=fv.LowerWick(); ctx.hourSin=fv.HourSin();
      ctx.hourCos=fv.HourCos(); ctx.htfTrendH4=fv.HTFTrendH4(); ctx.atrPercentile=fv.ATRPercentile();

      double adjustedBonus = PatternBonus(fv, patternBonus);
      double expertScore = 0.0;
      switch(expert)
        {
         case EXPERT_TREND:          expertScore = ScoreTrend(mdl, ctx, signal, adjustedBonus); break;
         case EXPERT_MEAN_REVERSION: expertScore = ScoreMeanReversion(mdl, ctx, signal, adjustedBonus); break;
         case EXPERT_MOMENTUM:       expertScore = ScoreMomentum(mdl, ctx); break;
         default:                    return AI_SCORE_NO_SIGNAL;
        }
      double expertProb = Logistic(expertScore);
      double nnScore = PlattCalibrate(mdl, ForwardPass26(mdl, fv));
      double nnWeight = MathMin(0.40, 0.005 * mdl.nnTrainingSamples);
      double finalScore = (1.0 - nnWeight) * expertProb + nnWeight * nnScore;
      if(driftScore > 0.3)
        {
         double penalty = (driftScore - 0.3) / MathMax(0.01, (m_driftThreshold - 0.3));
         finalScore *= (1.0 - 0.3 * penalty);
        }
      return MathMax(0.0, MathMin(1.0, finalScore));
     }

   double Evaluate18(const AIModelState &mdl, const FeatureVector &fv,
                     const SignalDecision &signal, double patternBonus,
                     double driftScore) const
     { return Evaluate26(mdl, fv, signal, patternBonus, driftScore); }

   double Predict(const double &features[], int count)
     {
      if(!m_loaded) { m_confidence = 0.0; return AI_SCORE_NO_SIGNAL; }
      double z = m_model.bias;
      int n = MathMin(count, NN_INPUTS);
      for(int i=0; i<n; i++)
         z += features[i] * 0.05;
      double p = Logistic(z);
      m_confidence = MathAbs(p - 0.5) * 2.0;
      return p;
     }

private:
   double _ForwardPass(const AIModelState &m, const double &feat[]) const
     {
      double h1[NN_H1];
      for(int j=0; j<NN_H1; j++)
        {
         double z = m.h1b[j];
         for(int i=0; i<NN_INPUTS; i++) z += feat[i] * m.h1w[i][j];
         h1[j] = MathMax(0.0, z);
        }
      double h2[NN_H2];
      for(int j=0; j<NN_H2; j++)
        {
         double z = m.h2b[j];
         for(int i=0; i<NN_H1; i++) z += h1[i] * m.h2w[i][j];
         h2[j] = MathMax(0.0, z);
        }
      double out = m.ob;
      for(int j=0; j<NN_H2; j++) out += h2[j] * m.ow[j];
      return out;
     }
  };

#endif // __AI_INFERENCE_MQH__
