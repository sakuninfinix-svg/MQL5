//+------------------------------------------------------------------+
//|                                                      AITypes.mqh |
//|                        Shared structs & enums for AI subsystem   |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_TYPES_MQH__
#define __AI_TYPES_MQH__

#include "../Data/RegimeTypes.mqh"

//--- Feature dimensionality
// 0..25  : price/volatility/momentum/volume/structure/session/stat features
// 26..33 : rich pattern-regression features
#define AI_FEATURE_DIM 34

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

//--- Risk-aware AI decision class
enum ENUM_AI_DECISION_CLASS
  {
   AI_DECISION_NO_TRADE    = 0,
   AI_DECISION_WEAK_BUY    = 1,
   AI_DECISION_STRONG_BUY  = 2,
   AI_DECISION_WEAK_SELL   = -1,
   AI_DECISION_STRONG_SELL = -2
  };

//--- Label quality class for future supervised/offline training
enum ENUM_AI_LABEL_CLASS
  {
   AI_LABEL_INVALID       = 0,
   AI_LABEL_NO_TRADE      = 1,
   AI_LABEL_GOOD_BUY      = 2,
   AI_LABEL_GOOD_SELL     = 3,
   AI_LABEL_BAD_BUY       = 4,
   AI_LABEL_BAD_SELL      = 5
  };

//--- Inference result from a single forward pass
struct SAIInferenceResult
  {
   double   score;
   double   confidence;
   int      direction;
   bool     valid;
   string   model_id;
   datetime timestamp;
   double   drift_score;
   bool     vetoed;
   string   veto_reason;

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

struct SAIRiskDecision
  {
   ENUM_AI_DECISION_CLASS decisionClass;
   int      direction;
   double   confidence;
   double   expectedR;
   double   failureProbability;
   double   recommendedSL_ATR;
   double   recommendedTP_ATR;
   double   riskMultiplier;
   double   noTradePenalty;
   string   reason;

   void Reset()
     {
      decisionClass      = AI_DECISION_NO_TRADE;
      direction          = 0;
      confidence         = 0.0;
      expectedR          = 0.0;
      failureProbability = 1.0;
      recommendedSL_ATR  = 0.0;
      recommendedTP_ATR  = 0.0;
      riskMultiplier     = 0.0;
      noTradePenalty     = 1.0;
      reason             = "";
     }
  };

struct SAIFeatureVector
  {
   double   features[AI_FEATURE_DIM];
   bool     valid;
   datetime bar_time;
   int      regime;

   void Reset()
     {
      ArrayInitialize(features, 0.0);
      valid    = false;
      bar_time = 0;
      regime   = 0;
     }
  };

struct SAITrainSample
  {
   double   features[AI_FEATURE_DIM];
   double   label;
   double   weight;
   datetime timestamp;

   void Reset()
     {
      ArrayInitialize(features, 0.0);
      label = 0.0;
      weight = 0.0;
      timestamp = 0;
     }
  };

struct SAITradeLabel
  {
   ENUM_AI_LABEL_CLASS labelClass;
   int      direction;
   double   realizedR;
   double   maxFavorableR;
   double   maxAdverseR;
   double   durationBars;
   bool     hitTPBeforeSL;
   bool     valid;
   datetime timestamp;

   void Reset()
     {
      labelClass    = AI_LABEL_INVALID;
      direction     = 0;
      realizedR     = 0.0;
      maxFavorableR = 0.0;
      maxAdverseR   = 0.0;
      durationBars  = 0.0;
      hitTPBeforeSL = false;
      valid         = false;
      timestamp     = 0;
     }
  };

struct SAIModelPerf
  {
   int      total_predictions;
   int      correct_predictions;
   double   accuracy;
   double   avg_confidence;
   double   avg_drift;
   datetime last_updated;

   void Reset()
     {
      total_predictions   = 0;
      correct_predictions = 0;
      accuracy            = 0.0;
      avg_confidence      = 0.0;
      avg_drift           = 0.0;
      last_updated        = 0;
     }

   void Update(bool correct, double conf, double drift)
     {
      total_predictions++;
      if(correct) correct_predictions++;
      accuracy       = (double)correct_predictions / MathMax(1, total_predictions);
      avg_confidence = (avg_confidence * (total_predictions-1) + conf) / total_predictions;
      avg_drift      = (avg_drift * (total_predictions-1) + drift) / total_predictions;
      last_updated   = TimeCurrent();
     }
  };

struct SAIEnsembleVote
  {
   double   scores[];
   double   weights[];
   double   final_score;
   double   agreement;
   int      n_models;

   void Reset()
     {
      ArrayFree(scores);
      ArrayFree(weights);
      final_score = 0.0;
      agreement   = 0.0;
      n_models    = 0;
     }
  };

enum EActiveStrategy
  {
   STRAT_NONE             = 0,
   STRAT_TREND_FOLLOW     = 1,
   STRAT_RANGE_TRADING    = 2,
   STRAT_MEAN_REVERT      = 3,
   STRAT_BREAKOUT         = 4,
   STRAT_SCALP_AI         = 5,
   STRAT_CONSERVATIVE     = 6
  };

#endif // __AI_TYPES_MQH__