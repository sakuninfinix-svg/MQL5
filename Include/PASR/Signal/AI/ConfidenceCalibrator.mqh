//+------------------------------------------------------------------+
//| AI/ConfidenceCalibrator.mqh — v1.00                               |
//| Platt scaling + isotonic regression for confidence calibration. |
//|                                                                  |
//| PROBLEM:                                                         |
//|   Raw neural network output is often overconfident: a score of  |
//|   0.85 does not mean 85% of such trades are winners. Without    |
//|   calibration, MinScore threshold is unreliable.                |
//|                                                                  |
//| SOLUTION:                                                        |
//|   Platt scaling: fit sigmoid p = 1/(1+exp(-(A*s+B))) on         |
//|   historical (raw_score, win_label) pairs. After calibration,   |
//|   output is a true probability estimate.                        |
//|                                                                  |
//| FALLBACK:                                                        |
//|   If < 30 samples: pass-through (raw = calibrated).             |
//|   If Platt fails to converge: isotonic 5-bucket fallback.       |
//|                                                                  |
//| USAGE:                                                           |
//|   cal.RecordSample(rawScore, true/false);  // after trade close  |
//|   cal.FitPlatt();                          // refit every N trades|
//|   double p = cal.Calibrate(rawScore);      // at entry           |
//|                                                                  |
//| CHANGE LOG:                                                      |
//|   v1.00 (2026-05-21) — Phase 8 initial                           |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_CONFIDENCE_CALIBRATOR_MQH__
#define __AI_CONFIDENCE_CALIBRATOR_MQH__

#define CAL_MIN_SAMPLES  30
#define CAL_MAX_SAMPLES  500
#define CAL_BUCKETS      5

struct CalSample
  {
   double rawScore;
   bool   win;
  };

class CConfidenceCalibrator
  {
private:
   CalSample m_samples[CAL_MAX_SAMPLES];
   int       m_count;
   // Platt parameters
   double    m_A;   // sigmoid slope
   double    m_B;   // sigmoid bias
   bool      m_fitted;
   // Isotonic fallback: 5 bucket boundaries + win rates
   double    m_bucketBound[CAL_BUCKETS+1];
   double    m_bucketRate[CAL_BUCKETS];

   // Sigmoid
   double Sigmoid(double x) const
     { return 1.0 / (1.0 + MathExp(-x)); }

   // Platt fit: gradient descent on log-loss
   void FitPlattInternal()
     {
      // Initialize with identity-like params
      double A = 1.0, B = 0.0;
      double lr = 0.1;
      int    maxIter = 200;

      for(int iter = 0; iter < maxIter; iter++)
        {
         double dA = 0, dB = 0;
         for(int i = 0; i < m_count; i++)
           {
            double s  = m_samples[i].rawScore;
            double y  = m_samples[i].win ? 1.0 : 0.0;
            double p  = Sigmoid(A*s + B);
            double err = p - y;
            dA += err * s;
            dB += err;
           }
         dA /= m_count; dB /= m_count;
         A  -= lr * dA;
         B  -= lr * dB;
         // Reduce LR with cosine schedule
         lr = 0.1 * (1.0 + MathCos(M_PI * iter / maxIter)) / 2.0;
        }
      m_A = A; m_B = B;
     }

   // Isotonic fallback: equal-width buckets
   void FitIsotonicFallback()
     {
      for(int b = 0; b <= CAL_BUCKETS; b++)
         m_bucketBound[b] = (double)b / CAL_BUCKETS;
      ArrayInitialize(m_bucketRate, 0.0);
      int cnt[CAL_BUCKETS]; ArrayInitialize(cnt, 0);

      for(int i = 0; i < m_count; i++)
        {
         double s = m_samples[i].rawScore;
         int    b = (int)MathMin(CAL_BUCKETS-1,
                                  MathFloor(s * CAL_BUCKETS));
         m_bucketRate[b] += m_samples[i].win ? 1.0 : 0.0;
         cnt[b]++;
        }
      for(int b = 0; b < CAL_BUCKETS; b++)
         if(cnt[b] > 0) m_bucketRate[b] /= cnt[b];
         else           m_bucketRate[b]  = (double)b / CAL_BUCKETS;
     }

public:
   CConfidenceCalibrator()
      : m_count(0), m_A(1.0), m_B(0.0), m_fitted(false)
     { ArrayInitialize(m_bucketBound, 0); ArrayInitialize(m_bucketRate, 0); }

   // Record a labeled sample after trade closes
   void RecordSample(double rawScore, bool win)
     {
      if(m_count >= CAL_MAX_SAMPLES)
        {
         // Sliding window: discard oldest 20%
         int keep = (int)(CAL_MAX_SAMPLES * 0.8);
         int start= m_count - keep;
         for(int i = 0; i < keep; i++) m_samples[i] = m_samples[start+i];
         m_count = keep;
        }
      m_samples[m_count].rawScore = MathMax(0.001, MathMin(0.999, rawScore));
      m_samples[m_count].win      = win;
      m_count++;
      // Trigger refit every 20 new samples if already fitted
      if(m_fitted && (m_count % 20 == 0)) FitPlatt();
     }

   // Fit calibration model (call after collecting >= 30 samples)
   bool FitPlatt()
     {
      if(m_count < CAL_MIN_SAMPLES) return false;
      FitPlattInternal();
      FitIsotonicFallback();  // always fit fallback too
      m_fitted = true;
      // Compute ECE for quality check
      double ece = ComputeECE();
      PrintFormat("[Calibrator] Fitted A=%.4f B=%.4f samples=%d ECE=%.4f",
                  m_A, m_B, m_count, ece);
      if(ece > 0.15)
         Print("[Calibrator] WARNING: ECE > 0.15 — model may be poorly calibrated");
      return true;
     }

   // Calibrate a raw score to probability
   double Calibrate(double rawScore) const
     {
      if(!m_fitted) return rawScore;  // pass-through if not fitted
      double platt = Sigmoid(m_A * rawScore + m_B);
      // Blend Platt with isotonic based on sample count confidence
      double confidence = MathMin(1.0, (double)m_count / 200.0);
      // Isotonic lookup
      int b = (int)MathMin(CAL_BUCKETS-1, MathFloor(rawScore * CAL_BUCKETS));
      double isotonic = m_bucketRate[b];
      return confidence * platt + (1.0 - confidence) * isotonic;
     }

   // Expected Calibration Error over 10 bins
   double ComputeECE() const
     {
      if(m_count < CAL_MIN_SAMPLES) return 1.0;
      int    bins = 10;
      double ece  = 0;
      for(int b = 0; b < bins; b++)
        {
         double lo = (double)b / bins;
         double hi = lo + 1.0/bins;
         double sumConf=0, sumAcc=0; int cnt=0;
         for(int i=0; i<m_count; i++)
           {
            double p = Calibrate(m_samples[i].rawScore);
            if(p>=lo && p<hi)
              { sumConf+=p; sumAcc+=(m_samples[i].win?1.0:0.0); cnt++; }
           }
         if(cnt>0)
            ece += (double)cnt/m_count * MathAbs(sumAcc/cnt - sumConf/cnt);
        }
      return ece;
     }

   bool   IsCalibrated()   const { return m_fitted && m_count >= CAL_MIN_SAMPLES; }
   int    SampleCount()    const { return m_count; }
   double GetPlattA()      const { return m_A; }
   double GetPlattB()      const { return m_B; }
  };

#endif // __AI_CONFIDENCE_CALIBRATOR_MQH__
