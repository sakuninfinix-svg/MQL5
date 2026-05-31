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
#ifndef AI_FEATURE_DIM
#define AI_FEATURE_DIM 34
#endif

//--- Confidence threshold defaults
#ifndef AI_DEFAULT_CONF_THRESHOLD
#define AI_DEFAULT_CONF_THRESHOLD  0.55
#endif
#ifndef AI_MIN_CONF_THRESHOLD
#define AI_MIN_CONF_THRESHOLD      0.40
#endif
#ifndef AI_MAX_CONF_THRESHOLD
#define AI_MAX_CONF_THRESHOLD      0.90
#endif

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
   bool     vetoed;
   string   veto_reason;
   double   drift_score;
   double   raw_outputs[4];

   void Clear()
     {
      score       = 0.0;
      confidence  = 0.0;
      direction   = 0;
      valid       = false;
      model_id    = "";
      timestamp   = 0;
      vetoed      = false;
      veto_reason = "";
      drift_score = 0.0;
      ArrayInitialize(raw_outputs, 0.0);
     }
  };

//--- Feature vector used across AI bridge/trainer/calibration
struct SAIFeatureVector
  {
   double   features[AI_FEATURE_DIM];
   datetime timestamp;
   string   symbol;
   ENUM_TIMEFRAMES timeframe;
   EMarketRegime regime;

   void Clear()
     {
      ArrayInitialize(features, 0.0);
      timestamp = 0;
      symbol = "";
      timeframe = PERIOD_CURRENT;
      regime = REGIME_UNKNOWN;
     }
  };

#endif // __AI_TYPES_MQH__
