//+------------------------------------------------------------------+
//| AI/ConfidenceCalibrator.mqh — v1.01                               |
//| Platt scaling + agreement-weighted confidence calibration         |
//+------------------------------------------------------------------+
#property strict
#ifndef __CONFIDENCE_CALIBRATOR_MQH__
#define __CONFIDENCE_CALIBRATOR_MQH__

#include "AITypes.mqh"
#include "../../Core/IManager.mqh"

class CConfidenceCalibrator : public IManager
  {
private:
   double   m_platt_A;
   double   m_platt_B;
   double   m_threshold;
   double   m_agreement_alpha;
   int      m_calib_samples;
   double   m_sum_correct_conf;
   double   m_sum_total_conf;

   double Sigmoid(double x) { return 1.0 / (1.0 + MathExp(-x)); }

public:
   CConfidenceCalibrator()
      : IManager(), m_platt_A(-1.0), m_platt_B(0.0),
        m_threshold(AI_DEFAULT_CONF_THRESHOLD), m_agreement_alpha(0.3),
        m_calib_samples(0), m_sum_correct_conf(0.0), m_sum_total_conf(0.0)
     {}

   virtual string HandlerName() const override { return "ConfidenceCalibrator"; }
   virtual bool Init(IDataManager *data, CEventBus *bus) override { return IManager::Init(data, bus); }
   virtual void Deinit() override { IManager::Deinit(); }
   virtual void DeclareEvents() override {}
   virtual void OnEvent(const PASREvent &ev) override {}

   double Calibrate(double raw_abs_score, double agreement)
     {
      double platt = Sigmoid(m_platt_A * raw_abs_score + m_platt_B);
      double conf = platt * (1.0 - m_agreement_alpha) + platt * agreement * m_agreement_alpha;
      return MathMax(0.0, MathMin(1.0, conf));
     }

   bool IsAboveThreshold(double conf) const { return conf >= m_threshold; }

   void Update(double raw_conf, bool was_correct)
     {
      m_calib_samples++;
      m_sum_total_conf += raw_conf;
      if(was_correct) m_sum_correct_conf += raw_conf;
      if(m_calib_samples % 50 == 0)
        {
         double accuracy_est = m_sum_correct_conf / MathMax(1, m_calib_samples);
         double target_logit = MathLog(MathMax(0.01, accuracy_est) /
                                       MathMax(0.01, 1.0 - accuracy_est));
         m_platt_B = target_logit;
        }
     }

   void SetThreshold(double t) { m_threshold = MathMax(AI_MIN_CONF_THRESHOLD, MathMin(AI_MAX_CONF_THRESHOLD, t)); }
   void SetPlattParams(double A, double B) { m_platt_A = A; m_platt_B = B; }
   void SetAgreementAlpha(double a) { m_agreement_alpha = MathMax(0.0, MathMin(1.0, a)); }
   double GetThreshold() const { return m_threshold; }
   int GetCalibSampleCount() const { return m_calib_samples; }
  };

#endif // __CONFIDENCE_CALIBRATOR_MQH__
