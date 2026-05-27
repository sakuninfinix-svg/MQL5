//+------------------------------------------------------------------+
//|                                                      AITypes.mqh |
//|                        Shared structs & enums for AI subsystem   |
//|  Zero external dependencies — safe to include anywhere           |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_TYPES_MQH__
#define __AI_TYPES_MQH__

//--- Feature dimensionality (26-dim as of v2.00)
#define AI_FEATURE_DIM 26

//--- Confidence threshold defaults
#define AI_DEFAULT_CONF_THRESHOLD  0.55
#define AI_MIN_CONF_THRESHOLD      0.40
#define AI_MAX_CONF_THRESHOLD      0.90

//--- Model type enumeration
enum ENUM_AI_MODEL_TYPE
{
   AI_MODEL_NONE       = 0,
   AI_MODEL_MLP        = 1,
   AI_MODEL_ONNX       = 2,
   AI_MODEL_ENSEMBLE   = 3,
   AI_MODEL_ONLINE     = 4
};

//--- Inference result from a single forward pass
struct SAIInferenceResult
{
   double   score;           // Raw output score [-1..1]
   double   confidence;      // Calibrated confidence [0..1]
   int      direction;       // +1 BUY / -1 SELL / 0 FLAT
   bool     valid;           // Is result usable?
   string   model_id;        // Which model produced it
   datetime timestamp;       // When produced
   double   drift_score;     // Concept drift indicator [0..1]
   bool     vetoed;          // Vetoed by guard?
   string   veto_reason;     // Reason if vetoed
   
   void Reset()
   {
      score       = 0.0;
      confidence  = 0.0;
      direction   = 0;
      valid       = false;
      model_id    = "";
      timestamp   = 0;
      drift_score = 0.0;
      vetoed      = false;
      veto_reason = "";
   }
};

//--- Feature vector wrapper (26-dim)
struct SAIFeatureVector
{
   double   features[AI_FEATURE_DIM]; // Raw feature values
   bool     valid;                    // Are features usable?
   datetime bar_time;                 // Bar this was built on
   int      regime;                   // Regime at build time
   
   void Reset()
   {
      ArrayInitialize(features, 0.0);
      valid    = false;
      bar_time = 0;
      regime   = 0;
   }
};

//--- Training sample
struct SAITrainSample
{
   double   features[AI_FEATURE_DIM];
   double   label;          // +1 / -1
   double   weight;         // Sample importance weight
   datetime timestamp;
};

//--- Model performance snapshot
struct SAIModelPerf
{
   int      total_predictions;
   int      correct_predictions;
   double   accuracy;          // correct/total
   double   avg_confidence;    // mean confidence on correct
   double   avg_drift;         // mean drift score
   datetime last_updated;
   
   void Reset()
   {
      total_predictions  = 0;
      correct_predictions= 0;
      accuracy           = 0.0;
      avg_confidence     = 0.0;
      avg_drift          = 0.0;
      last_updated       = 0;
   }
   
   void Update(bool correct, double conf, double drift)
   {
      total_predictions++;
      if(correct) correct_predictions++;
      accuracy     = (double)correct_predictions / MathMax(1, total_predictions);
      avg_confidence = (avg_confidence * (total_predictions-1) + conf) / total_predictions;
      avg_drift      = (avg_drift * (total_predictions-1) + drift) / total_predictions;
      last_updated   = TimeCurrent();
   }
};

//--- Ensemble vote
struct SAIEnsembleVote
{
   double   scores[];       // Raw scores from each model
   double   weights[];      // Model weights
   double   final_score;    // Weighted aggregate
   double   agreement;      // Vote agreement [0..1]
   int      n_models;       // Number of voters
   
   void Reset()
   {
      ArrayFree(scores);
      ArrayFree(weights);
      final_score = 0.0;
      agreement   = 0.0;
      n_models    = 0;
   }
};

//+------------------------------------------------------------------+
//| Market Regime Enumeration                                        |
//+------------------------------------------------------------------+
enum EMarketRegime
{
   REGIME_UNKNOWN         = 0,  // Not enough data
   REGIME_STRONG_TREND    = 1,  // ADX > 30, clear direction
   REGIME_SIDEWAYS        = 2,  // ADX < 20, range-bound
   REGIME_VOLATILE        = 3,  // High ATR, breakout potential
   REGIME_CHAOS           = 4,  // Erratic, avoid trading
   REGIME_TRENDING_WEAK   = 5   // ADX 20-30, weak trend
};

//+------------------------------------------------------------------+
//| Active Strategy Enumeration                                      |
//+------------------------------------------------------------------+
enum EActiveStrategy
{
   STRAT_NONE             = 0,  // No active strategy (chaos)
   STRAT_TREND_FOLLOW     = 1,  // Follow strong trends
   STRAT_RANGE_TRADING    = 2,  // Bounce off S/R in sideways (NEW!)
   STRAT_MEAN_REVERT      = 3,  // Fade extremes (risky in strong S/R)
   STRAT_BREAKOUT         = 4,  // Trade volatility breakouts
   STRAT_SCALP_AI         = 5,  // High-frequency AI scalping
   STRAT_CONSERVATIVE     = 6   // Capital preservation mode
};

#endif // __AI_TYPES_MQH__
