//+------------------------------------------------------------------+
//| AI/AIFeatureValidator.mqh - inference input safety gate          |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_AI_FEATURE_VALIDATOR_MQH__
#define __PASR_AI_FEATURE_VALIDATOR_MQH__

#include "AITypes.mqh"
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
         if(!IsFinite(value) || MathAbs(value) > PASR_AI_FEATURE_MAX_ABS)
           {
            out.invalidIndex = i;
            out.invalidValue = value;
            out.reason = StringFormat("Invalid feature[%d]=%.8f", i, value);
            return false;
           }
        }

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
  };

#endif // __PASR_AI_FEATURE_VALIDATOR_MQH__
