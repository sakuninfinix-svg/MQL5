//+------------------------------------------------------------------+
//| AI/AICalibrationBridge.mqh                                       |
//| Copyright @2026                                                  |
//| agsicentre.wordpress.com                                         |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_CALIBRATION_BRIDGE_MQH__
#define __AI_CALIBRATION_BRIDGE_MQH__

#include "AITypes.mqh"
#include "ConfidenceCalibrator.mqh"
#include "../Infra/AdaptiveConfig.mqh"

class CAICalibrationBridge
  {
private:
   CConfidenceCalibrator *m_calib;
   CAdaptiveConfig       *m_adaptive_cfg;
   bool                   m_connected;
   datetime               m_last_sync;
   int                    m_sync_interval_sec;

public:
   CAICalibrationBridge()
      : m_calib(NULL), m_adaptive_cfg(NULL),
        m_connected(false), m_last_sync(0), m_sync_interval_sec(300)
     {}

   bool Connect(CConfidenceCalibrator *calib, CAdaptiveConfig *cfg)
     {
      if(calib == NULL || cfg == NULL) return false;
      m_calib        = calib;
      m_adaptive_cfg = cfg;
      m_connected    = true;
      return Sync();
     }

   void Disconnect()
     {
      m_calib        = NULL;
      m_adaptive_cfg = NULL;
      m_connected    = false;
     }

   bool Sync()
     {
      if(!m_connected) return false;
      if(CheckPointer(m_calib) == POINTER_INVALID) return false;
      if(CheckPointer(m_adaptive_cfg) == POINTER_INVALID) return false;

      double threshold = m_adaptive_cfg.GetAIConfidenceThreshold();
      threshold = MathMax(AI_MIN_CONF_THRESHOLD, MathMin(AI_MAX_CONF_THRESHOLD, threshold));
      m_calib.SetThreshold(threshold);
      m_last_sync = TimeCurrent();
      return true;
     }

   void MaybeSync()
     {
      if(!m_connected) return;
      if(TimeCurrent() - m_last_sync >= m_sync_interval_sec)
         Sync();
     }

   void FeedbackAccuracy(double accuracy)
     {
      if(!m_connected) return;
      if(CheckPointer(m_adaptive_cfg) == POINTER_INVALID) return;
      m_adaptive_cfg.OnAIAccuracyUpdate(accuracy);
     }

   bool IsConnected() const { return m_connected; }
   datetime GetLastSync() const { return m_last_sync; }
   void SetSyncInterval(int secs) { m_sync_interval_sec = MathMax(60, secs); }
  };

#endif // __AI_CALIBRATION_BRIDGE_MQH__
