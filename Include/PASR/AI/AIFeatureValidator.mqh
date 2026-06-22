//+------------------------------------------------------------------+
//| AI/AIFeatureValidator.mqh — v1.02                                |
//| Validates feature vectors and sequence tensors before inference  |
//| Copyright @2026                                                  |
//| agsicentre.wordpress.com                                         |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_FEATURE_VALIDATOR_MQH__
#define __AI_FEATURE_VALIDATOR_MQH__

#include "AITypes.mqh"
#include "AIEnsemble.mqh"

struct AIFeatureValidationResult
  {
   bool   passed;
   string reason;
   double outlier_ratio;
   int    nan_count;
   int    zero_count;

   void Clear()
     {
      passed = false;
      reason = "";
      outlier_ratio = 0.0;
      nan_count = 0;
      zero_count = 0;
     }
  };

class CAIFeatureValidator
  {
private:
   double m_outlier_zscore_threshold;
   double m_max_zero_ratio;
   int    m_min_models_required;

   bool IsNaN(double v) const { return (v != v); }
   bool IsInf(double v) const { return (MathAbs(v) > 1e15); }

public:
   CAIFeatureValidator()
      : m_outlier_zscore_threshold(5.0),
        m_max_zero_ratio(0.90),
        m_min_models_required(1)
     {}

   // FIX: CAIEnsemble passed by pointer — avoids object-copy operator= error;
   //      uses IsReady() and GetModelCount() which are now public on CAIEnsemble
   bool Validate(const SAIFeatureVector &fv, CAIEnsemble *ensemble,
                 AIFeatureValidationResult &result)
     {
      result.Clear();

      if(!fv.valid)
        {
         result.reason = "Feature vector invalid";
         return false;
        }

      // Check ensemble readiness — FIX: use pointer, IsReady() and GetModelCount()
      if(ensemble == NULL || !ensemble.IsReady())
        {
         result.reason = "Ensemble not ready";
         return false;
        }
      if(ensemble.GetModelCount() < m_min_models_required)
        {
         result.reason = StringFormat("Ensemble has only %d models (need %d)",
                                      ensemble.GetModelCount(), m_min_models_required);
         return false;
        }

      // Feature quality checks
      int nan_count  = 0;
      int zero_count = 0;
      double sum     = 0.0;
      double sum_sq  = 0.0;

      for(int i = 0; i < AI_FEATURE_DIM; i++)
        {
         double v = fv.features[i];
         if(IsNaN(v) || IsInf(v)) { nan_count++; continue; }
         if(v == 0.0) zero_count++;
         sum    += v;
         sum_sq += v * v;
        }

      result.nan_count  = nan_count;
      result.zero_count = zero_count;

      if(nan_count > 0)
        {
         result.reason = StringFormat("%d NaN/Inf features detected", nan_count);
         return false;
        }

      double zero_ratio = (double)zero_count / AI_FEATURE_DIM;
      if(zero_ratio > m_max_zero_ratio)
        {
         result.reason = StringFormat("Zero ratio too high: %.1f%%", zero_ratio * 100.0);
         return false;
        }

      double mean = sum / AI_FEATURE_DIM;
      double variance = (sum_sq / AI_FEATURE_DIM) - (mean * mean);
      double stddev = (variance > 0.0) ? MathSqrt(variance) : 1.0;

      int outlier_count = 0;
      for(int i = 0; i < AI_FEATURE_DIM; i++)
        {
         if(IsNaN(fv.features[i]) || IsInf(fv.features[i])) continue;
         double z = MathAbs(fv.features[i] - mean) / MathMax(stddev, 1e-9);
         if(z > m_outlier_zscore_threshold) outlier_count++;
        }

      result.outlier_ratio = (double)outlier_count / AI_FEATURE_DIM;
      if(result.outlier_ratio > 0.5)
        {
         result.reason = StringFormat("Too many outliers: %.1f%%", result.outlier_ratio * 100.0);
         return false;
        }

      result.passed = true;
      result.reason = "OK";
      return true;
     }

   bool ValidateSequence(SAISequenceTensor &seq,
                         AIFeatureValidationResult &result)
     {
      result.Clear();
      if(!seq.valid)
        {
         result.reason = "Sequence tensor invalid";
         return false;
        }
      if(seq.seq_len <= 0 || seq.feat_dim <= 0)
        {
         result.reason = "Sequence dimensions zero";
         return false;
        }
      result.passed = true;
      result.reason = "OK";
      return true;
     }
  };

#endif // __AI_FEATURE_VALIDATOR_MQH__
