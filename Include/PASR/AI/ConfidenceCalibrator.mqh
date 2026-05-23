//+------------------------------------------------------------------+
//| AI/ConfidenceCalibrator.mqh                                      |
//| Platt scaling + agreement-weighted confidence calibration        |
//+------------------------------------------------------------------+
#property strict
#ifndef __CONFIDENCE_CALIBRATOR_MQH__
#define __CONFIDENCE_CALIBRATOR_MQH__

#include "AITypes.mqh"

//+------------------------------------------------------------------+
//| CConfidenceCalibrator                                            |
//| Applies Platt scaling to raw model outputs                       |
//| Also weights by ensemble agreement fraction                      |
//+------------------------------------------------------------------+
class CConfidenceCalibrator : public IManager
{
private:
   // Platt scaling parameters: P(y=1|f) = sigmoid(A*f + B)
   double   m_platt_A;
   double   m_platt_B;
   double   m_threshold;       // minimum calibrated confidence to emit signal
   double   m_agreement_alpha; // how much agreement multiplies confidence
   
   // Running calibration state
   int      m_calib_samples;
   double   m_sum_correct_conf;
   double   m_sum_total_conf;
   
   double Sigmoid(double x) { return 1.0 / (1.0 + MathExp(-x)); }
   
public:
   CConfidenceCalibrator()
      : m_platt_A(-1.0), m_platt_B(0.0),
        m_threshold(AI_DEFAULT_CONF_THRESHOLD),
        m_agreement_alpha(0.3),
        m_calib_samples(0), m_sum_correct_conf(0.0), m_sum_total_conf(0.0)
   {}
   
   virtual bool Initialize(CEventBus *bus) override
   {
      return IManager::Initialize(bus);
   }
   virtual void Shutdown() override { IManager::Shutdown(); }
   virtual void DeclareEvents() override {}
   virtual void OnEvent(const PASREvent &ev) override {}
   
   //--- Calibrate raw score to confidence probability
   //    raw_score: [-1..1] from model
   //    agreement: [0..1] ensemble agreement fraction
   double Calibrate(double raw_abs_score, double agreement)
   {
      // Step 1: Platt scaling
      double platt = Sigmoid(m_platt_A * raw_abs_score + m_platt_B);
      
      // Step 2: Agreement weighting
      // Blend: final = platt * (1 - alpha) + platt * agreement * alpha
      double conf = platt * (1.0 - m_agreement_alpha) + platt * agreement * m_agreement_alpha;
      
      // Clamp
      return MathMax(0.0, MathMin(1.0, conf));
   }
   
   //--- Is calibrated confidence above threshold?
   bool IsAboveThreshold(double conf) const
   {
      return conf >= m_threshold;
   }
   
   //--- Online calibration update (call after trade result known)
   void Update(double raw_conf, bool was_correct)
   {
      m_calib_samples++;
      m_sum_total_conf   += raw_conf;
      if(was_correct) m_sum_correct_conf += raw_conf;
      
      // Every 50 samples, do a simple Platt re-estimation
      if(m_calib_samples % 50 == 0)
      {
         double mean_conf    = m_sum_total_conf   / m_calib_samples;
         double accuracy_est = m_sum_correct_conf / m_calib_samples;
         // Adjust B to centre calibration around observed accuracy
         double target_logit = MathLog(MathMax(0.01, accuracy_est) /
                                       MathMax(0.01, 1.0 - accuracy_est));
         m_platt_B = target_logit;
      }
   }
   
   //--- Accessors / mutators
   void   SetThreshold(double t)         { m_threshold = MathMax(AI_MIN_CONF_THRESHOLD, MathMin(AI_MAX_CONF_THRESHOLD, t)); }
   void   SetPlattParams(double A, double B) { m_platt_A = A; m_platt_B = B; }
   void   SetAgreementAlpha(double a)    { m_agreement_alpha = MathMax(0.0, MathMin(1.0, a)); }
   double GetThreshold()           const { return m_threshold; }
   int    GetCalibSampleCount()    const { return m_calib_samples; }
};

#endif // __CONFIDENCE_CALIBRATOR_MQH__
