//+------------------------------------------------------------------+
//| AI/OnlineLearningGuard.mqh — v1.01                                |
//| Concept drift detection and veto guard for AI inference           |
//+------------------------------------------------------------------+
#property strict
#ifndef __ONLINE_LEARNING_GUARD_MQH__
#define __ONLINE_LEARNING_GUARD_MQH__

#include "AITypes.mqh"
#include "../../Core/IManager.mqh"

#define GUARD_WINDOW     100
#define GUARD_DRIFT_VETO 0.75

class COnlineLearningGuard : public IManager
  {
private:
   double   m_ref_mean[AI_FEATURE_DIM];
   double   m_ref_var[AI_FEATURE_DIM];
   bool     m_ref_built;
   int      m_ref_count;
   double   m_recent_sum[AI_FEATURE_DIM];
   double   m_recent_sq[AI_FEATURE_DIM];
   int      m_recent_count;
   double   m_veto_threshold;
   double   m_drift_history[GUARD_WINDOW];
   int      m_drift_head;
   int      m_drift_count;
   double   m_last_drift;

   double ComputePSI(const SAIFeatureVector &fv)
     {
      if(!m_ref_built) return 0.0;
      double psi = 0.0;
      int valid_dims = 0;
      for(int i = 0; i < AI_FEATURE_DIM; i++)
        {
         double ref_sd = MathSqrt(MathMax(m_ref_var[i], 1e-10));
         double z = MathAbs(fv.features[i] - m_ref_mean[i]) / ref_sd;
         psi += MathMin(z, 3.0) / 3.0;
         valid_dims++;
        }
      return (valid_dims > 0) ? psi / valid_dims : 0.0;
     }

public:
   COnlineLearningGuard()
      : IManager(), m_ref_built(false), m_ref_count(0),
        m_recent_count(0), m_veto_threshold(GUARD_DRIFT_VETO),
        m_drift_head(0), m_drift_count(0), m_last_drift(0.0)
     {
      ArrayInitialize(m_ref_mean, 0.0);
      ArrayInitialize(m_ref_var, 0.0);
      ArrayInitialize(m_recent_sum, 0.0);
      ArrayInitialize(m_recent_sq, 0.0);
      ArrayInitialize(m_drift_history, 0.0);
     }

   virtual string HandlerName() const override { return "OnlineLearningGuard"; }
   virtual bool Init(IDataManager *data, CEventBus *bus) override { return IManager::Init(data, bus); }
   virtual void Deinit() override { IManager::Deinit(); }
   virtual void DeclareEvents() override {}
   virtual void OnEvent(const PASREvent &ev) override {}

   void FeedFeature(const SAIFeatureVector &fv)
     {
      for(int i = 0; i < AI_FEATURE_DIM; i++)
        {
         m_recent_sum[i] += fv.features[i];
         m_recent_sq[i] += fv.features[i] * fv.features[i];
        }
      m_recent_count++;
      if(!m_ref_built)
        {
         m_ref_count++;
         if(m_ref_count >= GUARD_WINDOW)
           {
            for(int i = 0; i < AI_FEATURE_DIM; i++)
              {
               m_ref_mean[i] = m_recent_sum[i] / m_recent_count;
               double e2 = m_recent_sq[i] / m_recent_count;
               m_ref_var[i] = MathMax(0.0, e2 - m_ref_mean[i] * m_ref_mean[i]);
              }
            m_ref_built = true;
            Print("COnlineLearningGuard: Reference distribution built");
           }
        }
     }

   double ComputeDrift(const SAIFeatureVector &fv)
     {
      FeedFeature(fv);
      m_last_drift = ComputePSI(fv);
      m_drift_history[m_drift_head] = m_last_drift;
      m_drift_head = (m_drift_head + 1) % GUARD_WINDOW;
      m_drift_count = MathMin(m_drift_count + 1, GUARD_WINDOW);
      return m_last_drift;
     }

   bool ShouldVeto(double drift_score) const { return drift_score >= m_veto_threshold; }

   double GetAvgDrift() const
     {
      if(m_drift_count == 0) return 0.0;
      double sum = 0.0;
      for(int i = 0; i < m_drift_count; i++) sum += m_drift_history[i];
      return sum / m_drift_count;
     }

   double GetLastDrift() const { return m_last_drift; }
   bool RefIsBuilt() const { return m_ref_built; }
   void SetVetoThreshold(double t) { m_veto_threshold = MathMax(0.1, MathMin(1.0, t)); }
  };

#endif // __ONLINE_LEARNING_GUARD_MQH__
