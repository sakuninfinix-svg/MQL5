//+------------------------------------------------------------------+
//| AI/AIFeatureValidator.mqh - inference input safety gate          |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_AI_FEATURE_VALIDATOR_MQH__
#define __PASR_AI_FEATURE_VALIDATOR_MQH__

#include "AITypes.mqh"
#include "SequenceFeatureBuilder.mqh"
#include "AIEnsemble.mqh"

#define PASR_AI_FEATURE_MAX_ABS        10.0
#define PASR_AI_FEATURE_MAX_STALE_SEC  300

struct AIFeatureValidationResult
  {
   bool     valid;
   bool     modelHealthy;
   int      featureCount;
   int      invalidIndex;
   double   invalidValue;
   datetime featureTime;
   datetime barTime;
   string   modelId;
   int      modelCount;
   int      featureDim;
   string   featureGroup;
   double   expectedMin;
   double   expectedMax;
   string   reason;

   void Clear()
     {
      valid = false;
      modelHealthy = false;
      featureCount = AI_FEATURE_DIM;
      invalidIndex = -1;
      invalidValue = 0.0;
      featureTime = 0;
      barTime = 0;
      modelId = "";
      modelCount = 0;
      featureDim = AI_FEATURE_DIM;
      featureGroup = "";
      expectedMin = 0.0;
      expectedMax = 0.0;
      reason = "";
     }
  };

class CAIFeatureValidator
  {
private:
   int m_maxStaleSec;

   bool IsFinite(const double value) const
     {
      if(value != value) return false;
      if(MathAbs(value) > DBL_MAX / 4.0) return false;
      return true;
     }

   string SequenceFeatureGroup(const int feat) const
     {
      switch(feat)
        {
         case SEQ_FEAT_NORM_RETURN:  return "seq_return";
         case SEQ_FEAT_HL_ATR_RATIO: return "seq_hl_atr";
         case SEQ_FEAT_VOL_RATIO:    return "seq_volume";
         case SEQ_FEAT_BODY_RATIO:
         case SEQ_FEAT_UPPER_WICK:
         case SEQ_FEAT_LOWER_WICK:
         case SEQ_FEAT_CLOSE_POS:    return "seq_candle";
         case SEQ_FEAT_SR_DIST:
         case SEQ_FEAT_ZONE_STR:
         case SEQ_FEAT_PATTERN:      return "seq_structure";
         case SEQ_FEAT_REGIME_TREND: return "seq_regime";
         case SEQ_FEAT_BAR_AGE:      return "seq_time";
         default:                    return "seq_unknown";
        }
     }

   void SequenceFeatureBounds(const int feat, double &lo, double &hi) const
     {
      lo = 0.0;
      hi = 1.0;
     }

   string FeatureGroup(const int index) const
     {
      if(index >= 0 && index <= 3) return "returns";
      if(index >= 4 && index <= 7) return "atr_ratio";
      if(index >= 8 && index <= 11) return "momentum";
      if(index >= 12 && index <= 15) return "volume";
      if(index >= 16 && index <= 18) return "structure";
      if(index >= 19 && index <= 21) return "regime_onehot";
      if(index >= 22 && index <= 23) return "time";
      if(index >= 24 && index <= 25) return "distribution";
      if(index >= 26 && index <= 33) return "pattern";
      return "unknown";
     }

   void FeatureBounds(const int index, double &lo, double &hi) const
     {
      if((index >= 0 && index <= 3) || (index >= 24 && index <= 25))
        {
         lo = -1.0;
         hi = 1.0;
         return;
        }
      lo = 0.0;
      hi = 1.0;
     }

   bool ValidateOneHotRegime(const SAIFeatureVector &features, AIFeatureValidationResult &out) const
     {
      double sum = features.features[19] + features.features[20] + features.features[21];
      if(MathAbs(sum - 1.0) > 0.000001)
        {
         out.invalidIndex = 19;
         out.invalidValue = sum;
         out.featureGroup = "regime_onehot";
         out.expectedMin = 1.0;
         out.expectedMax = 1.0;
         out.reason = StringFormat("Invalid regime one-hot sum=%.8f", sum);
         return false;
        }
      return true;
     }

public:
   CAIFeatureValidator() : m_maxStaleSec(PASR_AI_FEATURE_MAX_STALE_SEC) {}

   void SetMaxStaleSec(const int seconds)
     {
      m_maxStaleSec = MathMax(1, seconds);
     }

   bool ValidateFeatures(const SAIFeatureVector &features, AIFeatureValidationResult &out) const
     {
      out.Clear();
      out.featureTime = features.timestamp;
      out.barTime = features.bar_time;

      if(!features.valid)
        {
         out.reason = "Feature vector invalid flag";
         return false;
        }

      if(features.bar_time <= 0)
        {
         out.reason = "Feature bar time missing";
         return false;
        }

      datetime now = TimeCurrent();
      datetime featureTime = (features.timestamp > 0) ? features.timestamp : now;
      if(m_maxStaleSec > 0 && now - featureTime > m_maxStaleSec)
        {
         out.reason = StringFormat("Feature vector stale age=%d sec", (int)(now - featureTime));
         return false;
        }

      for(int i = 0; i < AI_FEATURE_DIM; i++)
        {
         double value = features.features[i];
         double lo = 0.0;
         double hi = 0.0;
         FeatureBounds(i, lo, hi);
         if(!IsFinite(value) || MathAbs(value) > PASR_AI_FEATURE_MAX_ABS ||
            value < lo - 0.000001 || value > hi + 0.000001)
           {
            out.invalidIndex = i;
            out.invalidValue = value;
            out.featureGroup = FeatureGroup(i);
            out.expectedMin = lo;
            out.expectedMax = hi;
            out.reason = StringFormat("Invalid %s feature[%d]=%.8f expected[%.2f..%.2f]",
                                      out.featureGroup, i, value, lo, hi);
            return false;
           }
        }

      if(!ValidateOneHotRegime(features, out))
         return false;

      out.valid = true;
      out.reason = "OK";
      return true;
     }

   bool ValidateModel(CAIEnsemble *ensemble, AIFeatureValidationResult &out) const
     {
      if(ensemble == NULL)
        {
         out.modelHealthy = false;
         if(out.reason == "" || out.reason == "OK") out.reason = "AI ensemble missing";
         return false;
        }

      out.modelHealthy = (ensemble.IsReady() && ensemble.GetModelCount() > 0);
      out.modelCount = ensemble.GetModelCount();
      out.modelId = StringFormat("ensemble:%dmodels:feat%d", out.modelCount, AI_FEATURE_DIM);
      if(!out.modelHealthy && (out.reason == "" || out.reason == "OK"))
         out.reason = "AI ensemble not ready";
      return out.modelHealthy;
     }

   bool Validate(const SAIFeatureVector &features, CAIEnsemble *ensemble, AIFeatureValidationResult &out) const
     {
      bool featureOk = ValidateFeatures(features, out);
      bool modelOk = ValidateModel(ensemble, out);
      out.valid = (featureOk && modelOk);
      if(out.valid) out.reason = "OK";
      return out.valid;
     }

   bool ValidateSequence(const SAISequenceTensor &tensor, AIFeatureValidationResult &out) const
     {
      out.Clear();
      out.featureDim = AI_SEQ_FEATURE_DIM;
      out.featureCount = AI_SEQ_TENSOR_SIZE;
      out.featureTime = tensor.timestamp;
      out.barTime = tensor.newest_bar_time;

      if(!tensor.valid)
        {
         out.reason = "Sequence tensor invalid flag";
         return false;
        }

      if(tensor.seq_len != AI_SEQ_LEN || tensor.feat_dim != AI_SEQ_FEATURE_DIM)
        {
         out.reason = StringFormat("Sequence shape mismatch len=%d feat=%d",
                                   tensor.seq_len, tensor.feat_dim);
         return false;
        }

      if(tensor.newest_bar_time <= 0)
        {
         out.reason = "Sequence newest bar time missing";
         return false;
        }

      datetime now = TimeCurrent();
      datetime featureTime = (tensor.timestamp > 0) ? tensor.timestamp : now;
      if(m_maxStaleSec > 0 && now - featureTime > m_maxStaleSec)
        {
         out.reason = StringFormat("Sequence tensor stale age=%d sec", (int)(now - featureTime));
         return false;
        }

      for(int b = 0; b < AI_SEQ_LEN; b++)
        {
         for(int f = 0; f < AI_SEQ_FEATURE_DIM; f++)
           {
            double value = tensor.At(b, f);
            double lo = 0.0;
            double hi = 0.0;
            SequenceFeatureBounds(f, lo, hi);
            if(!IsFinite(value) || MathAbs(value) > PASR_AI_FEATURE_MAX_ABS ||
               value < lo - 0.000001 || value > hi + 0.000001)
              {
               out.invalidIndex = tensor.FlatIndex(b, f);
               out.invalidValue = value;
               out.featureGroup = SequenceFeatureGroup(f);
               out.expectedMin = lo;
               out.expectedMax = hi;
               out.reason = StringFormat("Invalid %s tensor[%d,%d]=%.8f expected[%.2f..%.2f]",
                                         out.featureGroup, b, f, value, lo, hi);
               return false;
              }
           }
        }

      out.valid = true;
      out.modelHealthy = true;
      out.modelId = StringFormat("sequence:%dx%d", AI_SEQ_LEN, AI_SEQ_FEATURE_DIM);
      out.reason = "OK";
      return true;
     }
  };

#endif // __PASR_AI_FEATURE_VALIDATOR_MQH__
