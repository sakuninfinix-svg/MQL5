//+------------------------------------------------------------------+
//| AI/AIEnsemble.mqh — v1.00                                        |
//| Weighted ensemble of 3 sub-models: Trend, MeanRev, Momentum.    |
//|                                                                  |
//| DESIGN:                                                          |
//|   3 independent AIModelState instances, each with own Platt     |
//|   calibration. Weights auto-adjust via online win-rate EMA      |
//|   updated by CAIOrchestrator after each trade closes.           |
//|                                                                  |
//|   Ensemble output = weighted avg of 3 calibrated sub-scores.    |
//|   When score spread > 0.30 (low agreement) → score reduced 20%. |
//|                                                                  |
//| ONLINE WEIGHT UPDATE:                                            |
//|   After trade close, call UpdateWeight(expert, isWin).           |
//|   win-rate EMA: w = w*(1-alpha) + alpha*(isWin?1.0:0.0)          |
//|   Weights re-normalised to sum=1.0 after each update.            |
//|                                                                  |
//| SERIALIZATION:                                                   |
//|   SaveWeights() / LoadWeights() for persistence across restarts. |
//|                                                                  |
//| CHANGE LOG:                                                      |
//|   v1.00 (2026-05-21) — Phase 8 initial                           |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_ENSEMBLE_MQH__
#define __AI_ENSEMBLE_MQH__

#include "AITypes.mqh"
#include "AIInference.mqh"
#include "AIFeatureBuilder.mqh"

#define ENSEMBLE_MODELS 3
#define ENSEMBLE_ALPHA  0.05   // EMA smoothing for online weight update

enum ENUM_ENSEMBLE_MODEL { EM_TREND=0, EM_MEANREV=1, EM_MOMENTUM=2 };

//+------------------------------------------------------------------+
//| CEnsembleWeights                                                 |
//+------------------------------------------------------------------+
struct EnsembleWeights
  {
   double w[ENSEMBLE_MODELS];  // sum = 1.0
   int    trades[ENSEMBLE_MODELS];
   double winRate[ENSEMBLE_MODELS];

   void Init()
     {
      for(int i=0; i<ENSEMBLE_MODELS; i++)
        { w[i]=1.0/ENSEMBLE_MODELS; trades[i]=0; winRate[i]=0.5; }
     }

   void Normalize()
     {
      double sum=0; for(int i=0;i<ENSEMBLE_MODELS;i++) sum+=MathMax(0.01,w[i]);
      for(int i=0;i<ENSEMBLE_MODELS;i++) w[i]=MathMax(0.01,w[i])/sum;
     }
  };

//+------------------------------------------------------------------+
//| CAIEnsemble                                                      |
//+------------------------------------------------------------------+
class CAIEnsemble
  {
private:
   AIInference      m_infer;
   AIModelState     m_models[ENSEMBLE_MODELS];
   EnsembleWeights  m_weights;
   bool             m_initialized;
   string           m_weightsFile;

   double RunModel(int idx, const FeatureVector &fv,
                   const SignalDecision &signal,
                   double patternBonus, double drift) const
     {
      if(!m_models[idx].initialized) return 0.5;
      // Build minimal SignalDecision clone for expert routing
      return m_infer.Evaluate26(m_models[idx], fv, signal, patternBonus, drift);
     }

public:
   CAIEnsemble() : m_initialized(false), m_weightsFile("PASR_ensemble.bin")
     { m_weights.Init(); }

   void SetRegime(MarketRegimeFilter *r) { m_infer.SetRegime(r); }

   void SetWeightsFile(string f) { m_weightsFile = f; }

   // Provide model states from CAIOrchestrator (non-owning pointers-by-value copy)
   void SetModel(ENUM_ENSEMBLE_MODEL idx, const AIModelState &mdl)
     {
      m_models[(int)idx] = mdl;
      m_initialized = m_models[0].initialized ||
                      m_models[1].initialized ||
                      m_models[2].initialized;
     }

   //+----------------------------------------------------------------+
   //| GetScore — main ensemble forward pass                          |
   //| Returns [0,1] blended confidence score.                        |
   //+----------------------------------------------------------------+
   double GetScore(const FeatureVector &fv,
                   const SignalDecision &signal,
                   double patternBonus,
                   double driftScore) const
     {
      if(!m_initialized) return 0.0;

      double scores[ENSEMBLE_MODELS];
      double weightedSum = 0, totalWeight = 0;

      for(int i = 0; i < ENSEMBLE_MODELS; i++)
        {
         scores[i]     = RunModel(i, fv, signal, patternBonus, driftScore);
         weightedSum   += scores[i] * m_weights.w[i];
         totalWeight   += m_weights.w[i];
        }

      double ensembleScore = (totalWeight > 0) ? weightedSum/totalWeight : 0.5;

      // Low-agreement penalty: if 3 scores spread > 0.30, reduce by 20%
      double scoreMax = MathMax(scores[0], MathMax(scores[1], scores[2]));
      double scoreMin = MathMin(scores[0], MathMin(scores[1], scores[2]));
      double spread   = scoreMax - scoreMin;
      if(spread > 0.30)
        {
         double penalty  = MathMin(1.0, (spread - 0.30) / 0.40);  // 0-100% extra
         ensembleScore  *= (1.0 - 0.20 * penalty);               // max 20% cut
         PrintFormat("[Ensemble] Low-agree spread=%.2f penalty=%.0f%%",
                     spread, 20.0*penalty);
        }

      return MathMax(0.0, MathMin(1.0, ensembleScore));
     }

   //+----------------------------------------------------------------+
   //| GetSubScores — for dashboard and logging                       |
   //+----------------------------------------------------------------+
   void GetSubScores(const FeatureVector &fv,
                     const SignalDecision &signal,
                     double patternBonus,
                     double driftScore,
                     double &out[]) const
     {
      ArrayResize(out, ENSEMBLE_MODELS);
      for(int i = 0; i < ENSEMBLE_MODELS; i++)
         out[i] = RunModel(i, fv, signal, patternBonus, driftScore);
     }

   //+----------------------------------------------------------------+
   //| GetActiveModel — returns index of highest-weight model         |
   //+----------------------------------------------------------------+
   ENUM_ENSEMBLE_MODEL GetActiveModel() const
     {
      int best = 0;
      for(int i=1; i<ENSEMBLE_MODELS; i++)
         if(m_weights.w[i] > m_weights.w[best]) best = i;
      return (ENUM_ENSEMBLE_MODEL)best;
     }

   string GetActiveModelName() const
     {
      switch(GetActiveModel())
        {
         case EM_TREND:    return "Trend";
         case EM_MEANREV:  return "MeanRev";
         case EM_MOMENTUM: return "Momentum";
         default:          return "Unknown";
        }
     }

   //+----------------------------------------------------------------+
   //| UpdateWeight — online EMA update after trade close             |
   //| Call from CAIOrchestrator.OnTradeClosed(expert, isWin)         |
   //+----------------------------------------------------------------+
   void UpdateWeight(ENUM_ENSEMBLE_MODEL model, bool isWin)
     {
      int i = (int)model;
      m_weights.trades[i]++;
      // EMA win-rate
      m_weights.winRate[i] = m_weights.winRate[i]*(1.0-ENSEMBLE_ALPHA)
                             + (isWin?1.0:0.0)*ENSEMBLE_ALPHA;
      // Weight = win-rate; re-normalise
      m_weights.w[i] = MathMax(0.05, m_weights.winRate[i]);
      m_weights.Normalize();
      PrintFormat("[Ensemble] Updated %s: winRate=%.2f w=[%.2f,%.2f,%.2f]",
                  GetActiveModelName(),
                  m_weights.winRate[i],
                  m_weights.w[0], m_weights.w[1], m_weights.w[2]);
     }

   //+----------------------------------------------------------------+
   //| Persistence — save/load weights to binary file                |
   //+----------------------------------------------------------------+
   bool SaveWeights() const
     {
      int h = FileOpen(m_weightsFile,
                       FILE_WRITE|FILE_BIN|FILE_COMMON);
      if(h == INVALID_HANDLE)
        { Print("[Ensemble] SaveWeights failed: ", GetLastError()); return false; }
      FileWriteStruct(h, m_weights);
      FileClose(h);
      PrintFormat("[Ensemble] Weights saved to %s", m_weightsFile);
      return true;
     }

   bool LoadWeights()
     {
      int h = FileOpen(m_weightsFile,
                       FILE_READ|FILE_BIN|FILE_COMMON);
      if(h == INVALID_HANDLE)
        { Print("[Ensemble] No weights file — using uniform init"); return false; }
      FileReadStruct(h, m_weights);
      FileClose(h);
      m_weights.Normalize();
      PrintFormat("[Ensemble] Weights loaded: [%.2f, %.2f, %.2f]",
                  m_weights.w[0], m_weights.w[1], m_weights.w[2]);
      return true;
     }

   // Get weights for dashboard
   void GetWeights(double &out[]) const
     {
      ArrayResize(out, ENSEMBLE_MODELS);
      for(int i=0;i<ENSEMBLE_MODELS;i++) out[i]=m_weights.w[i];
     }

   int GetTradeCount(ENUM_ENSEMBLE_MODEL m) const
     { return m_weights.trades[(int)m]; }
  };

#endif // __AI_ENSEMBLE_MQH__
