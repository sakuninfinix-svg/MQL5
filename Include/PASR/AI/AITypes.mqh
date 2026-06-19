//+------------------------------------------------------------------+
//|                                                      AITypes.mqh |
//|                        Shared structs & enums for AI subsystem   |
//| Copyright @2026                                                  |
//| agsicentre.wordpress.com                                         |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_TYPES_MQH__
#define __AI_TYPES_MQH__

#include "../Data/RegimeTypes.mqh"

#ifndef AI_FEATURE_DIM
#define AI_FEATURE_DIM 34
#endif

#ifndef AI_SEQ_LEN
#define AI_SEQ_LEN 64
#endif
#ifndef AI_SEQ_FEATURE_DIM
#define AI_SEQ_FEATURE_DIM 12
#endif
#ifndef AI_SEQ_TENSOR_SIZE
#define AI_SEQ_TENSOR_SIZE (AI_SEQ_LEN * AI_SEQ_FEATURE_DIM)
#endif

// FIX: define ENSEMBLE_MODEL_COUNT used by CAIEnsemble
#ifndef ENSEMBLE_MODEL_COUNT
#define ENSEMBLE_MODEL_COUNT 3
#endif

#ifndef AI_DEFAULT_CONF_THRESHOLD
#define AI_DEFAULT_CONF_THRESHOLD  0.55
#endif
#ifndef AI_MIN_CONF_THRESHOLD
#define AI_MIN_CONF_THRESHOLD      0.40
#endif
#ifndef AI_MAX_CONF_THRESHOLD
#define AI_MAX_CONF_THRESHOLD      0.90
#endif

enum ENUM_AI_MODEL_TYPE
  {
   AI_MODEL_NONE         = 0,
   AI_MODEL_MLP          = 1,
   AI_MODEL_ONNX         = 2,
   AI_MODEL_ENSEMBLE     = 3,
   AI_MODEL_ONLINE       = 4,
   AI_MODEL_TRANSFORMER  = 5
  };

enum ENUM_AI_DECISION_CLASS
  {
   AI_DECISION_NO_TRADE    = 0,
   AI_DECISION_WEAK_BUY    = 1,
   AI_DECISION_STRONG_BUY  = 2,
   AI_DECISION_WEAK_SELL   = -1,
   AI_DECISION_STRONG_SELL = -2
  };

enum ENUM_AI_LABEL_CLASS
  {
   AI_LABEL_INVALID       = 0,
   AI_LABEL_NO_TRADE      = 1,
   AI_LABEL_GOOD_BUY      = 2,
   AI_LABEL_GOOD_SELL     = 3,
   AI_LABEL_BAD_BUY       = 4,
   AI_LABEL_BAD_SELL      = 5
  };

enum EActiveStrategy
  {
   STRAT_NONE          = 0,
   STRAT_TREND_FOLLOW  = 1,
   STRAT_RANGE_TRADING = 2,
   STRAT_MEAN_REVERT   = 3,
   STRAT_BREAKOUT      = 4,
   STRAT_SCALP_AI      = 5,
   STRAT_CONSERVATIVE  = 6
  };

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

   void Reset() { Clear(); }
  };

struct SAIFeatureVector
  {
   double   features[AI_FEATURE_DIM];
   datetime timestamp;
   datetime bar_time;
   string   symbol;
   ENUM_TIMEFRAMES timeframe;
   EMarketRegime regime;
   bool     valid;

   void Clear()
     {
      ArrayInitialize(features, 0.0);
      timestamp = 0;
      bar_time = 0;
      symbol = "";
      timeframe = PERIOD_CURRENT;
      regime = REGIME_UNKNOWN;
      valid = false;
     }

   void Reset() { Clear(); }
  };

struct SAISequenceTensor
  {
   double           data[AI_SEQ_TENSOR_SIZE];
   int              seq_len;
   int              feat_dim;
   datetime         timestamp;
   datetime         newest_bar_time;
   string           symbol;
   ENUM_TIMEFRAMES  timeframe;
   EMarketRegime    regime;
   bool             valid;

   int FlatIndex(const int bar, const int feat) const
     {
      return bar * feat_dim + feat;
     }

   double At(const int bar, const int feat) const
     {
      int idx = FlatIndex(bar, feat);
      if(idx < 0 || idx >= AI_SEQ_TENSOR_SIZE) return 0.0;
      return data[idx];
     }

   void Set(const int bar, const int feat, const double value)
     {
      int idx = FlatIndex(bar, feat);
      if(idx < 0 || idx >= AI_SEQ_TENSOR_SIZE) return;
      data[idx] = value;
     }

   void Clear()
     {
      ArrayInitialize(data, 0.0);
      seq_len = AI_SEQ_LEN;
      feat_dim = AI_SEQ_FEATURE_DIM;
      timestamp = 0;
      newest_bar_time = 0;
      symbol = "";
      timeframe = PERIOD_CURRENT;
      regime = REGIME_UNKNOWN;
      valid = false;
     }

   void Reset() { Clear(); }
  };

struct SAITrainSample
  {
   double   features[AI_FEATURE_DIM];
   double   label;
   double   weight;
   datetime timestamp;
   string   symbol;
   EMarketRegime regime;

   void Clear()
     {
      ArrayInitialize(features, 0.0);
      label = 0.0;
      weight = 1.0;
      timestamp = 0;
      symbol = "";
      regime = REGIME_UNKNOWN;
     }

   void Reset() { Clear(); }
  };

// FIX: added 'confidence' and 'valid' fields required by CAIEnsemble and CAIOrchestrator
struct SAIEnsembleVote
  {
   double scores[];
   double weights[];
   int    n_models;
   double final_score;
   double agreement;    // kept for backward compat (used by ConfidenceCalibrator)
   double confidence;   // FIX: field referenced in CAIEnsemble::Vote and CAIOrchestrator
   bool   valid;        // FIX: field referenced in CAIOrchestrator

   void Clear()
     {
      ArrayResize(scores, 0);
      ArrayResize(weights, 0);
      n_models    = 0;
      final_score = 0.0;
      agreement   = 0.0;
      confidence  = 0.0;
      valid       = false;
     }

   void Reset() { Clear(); }
  };

struct SAIModelPerf
  {
   int    samples;
   int    correct;
   double accuracy;
   double avg_confidence;
   double avg_drift;
   datetime last_update;

   void Clear()
     {
      samples = 0;
      correct = 0;
      accuracy = 0.0;
      avg_confidence = 0.0;
      avg_drift = 0.0;
      last_update = 0;
     }

   void Reset() { Clear(); }

   void Update(bool is_correct, double conf, double drift)
     {
      samples++;
      if(is_correct) correct++;
      accuracy = (samples > 0) ? (double)correct / (double)samples : 0.0;
      avg_confidence = ((avg_confidence * (samples - 1)) + conf) / samples;
      avg_drift = ((avg_drift * (samples - 1)) + drift) / samples;
      last_update = TimeCurrent();
     }
  };

struct SAIRiskDecision
  {
   bool                   allow_trade;
   int                    direction;
   ENUM_AI_DECISION_CLASS decisionClass;
   double                 risk_multiplier;   // canonical field
   double                 confidence;
   double                 failureProbability;
   double                 expectedR;
   double                 noTradePenalty;
   double                 recommendedSL_ATR;
   double                 recommendedTP_ATR;
   string                 reason;

   void Clear()
     {
      allow_trade = false;
      direction = 0;
      decisionClass = AI_DECISION_NO_TRADE;
      risk_multiplier = 1.0;
      confidence = 0.0;
      failureProbability = 1.0;
      expectedR = 0.0;
      noTradePenalty = 0.0;
      recommendedSL_ATR = 1.0;
      recommendedTP_ATR = 2.0;
      reason = "";
     }

   void Reset() { Clear(); }
  };

// FIX: removed duplicate labelClass — use label_class only
struct SAITradeLabel
  {
   ENUM_AI_LABEL_CLASS label_class;   // canonical field
   double   label;
   double   reward;
   bool     valid;
   string   reason;
   datetime timestamp;
   int      direction;
   double   realizedR;
   bool     hitTPBeforeSL;
   double   durationBars;

   void Clear()
     {
      label_class = AI_LABEL_INVALID;
      label = 0.0;
      reward = 0.0;
      valid = false;
      reason = "";
      timestamp = 0;
      direction = 0;
      realizedR = 0.0;
      hitTPBeforeSL = false;
      durationBars = 0.0;
     }

   void Reset() { Clear(); }
  };

#endif // __AI_TYPES_MQH__
