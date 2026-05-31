//+------------------------------------------------------------------+
//| Signal/SignalScorer.mqh — v1.02                                  |
//| Signal scoring and quality assessment component                  |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_SCORER_MQH__
#define __SIGNAL_SCORER_MQH__

#include "../Data/SRStruct.mqh"
#include "../Trade/TradePlan.mqh"
#include "SignalConfig.mqh"

enum ENUM_SIGNAL_QUALITY
  {
   SIGNAL_QUALITY_HIGH   = 0,
   SIGNAL_QUALITY_MEDIUM = 1,
   SIGNAL_QUALITY_LOW    = 2
  };

struct ScoredSignal
  {
   ENUM_SIGNAL_DIR     direction;
   double              rawScore;
   double              normalizedScore;
   double              confidence;
   int                 confluence;
   ENUM_SIGNAL_QUALITY quality;
   ENUM_SIGNAL_URGENCY urgency;
   string              contributingSources;
   datetime            time;

   void Clear()
     {
      direction = SIGNAL_NONE;
      rawScore = 0.0;
      normalizedScore = 0.0;
      confidence = 0.0;
      confluence = 0;
      quality = SIGNAL_QUALITY_LOW;
      urgency = SIGNAL_URGENCY_LOW;
      contributingSources = "";
      time = 0;
     }
  };

class CSignalScorer
  {
private:
   const CSignalConfig *m_config;
   double m_qualityHighThreshold;
   double m_qualityMediumThreshold;

public:
   CSignalScorer() : m_config(NULL),
                     m_qualityHighThreshold(0.75),
                     m_qualityMediumThreshold(0.55)
     {}

   void Init(const CSignalConfig &config)
     {
      m_config = &config;
      m_qualityHighThreshold = config.GetUrgencyHighThreshold();
      m_qualityMediumThreshold = config.GetUrgencyMediumThreshold();
     }

   void SetQualityThresholds(double highThreshold, double mediumThreshold)
     {
      m_qualityHighThreshold = highThreshold;
      m_qualityMediumThreshold = mediumThreshold;
     }

   int CalculateMTFBias(double price,
                        double htfSupport,
                        double htfResistance,
                        double atrPoints,
                        double atrBufferMult) const
     {
      if(m_config != NULL && !m_config.GetUseMTF())
         return 0;
      if(price <= 0.0 || atrPoints <= 0.0)
         return 0;
      if(htfSupport <= 0.0 || htfResistance <= 0.0)
         return 0;

      double zone = (atrPoints * atrBufferMult) * _Point;
      bool nearHtfSupport = (price <= htfSupport + zone);
      bool nearHtfResistance = (price >= htfResistance - zone);

      if(nearHtfSupport && !nearHtfResistance) return 1;
      if(nearHtfResistance && !nearHtfSupport) return -1;
      return 0;
     }

   int CalculateQualityScore(int dir, int bias) const
     { return dir * bias; }

   ENUM_SIGNAL_QUALITY GetQualityTier(double score) const
     {
      if(score > 80.0) return SIGNAL_QUALITY_HIGH;
      if(score >= 50.0) return SIGNAL_QUALITY_MEDIUM;
      return SIGNAL_QUALITY_LOW;
     }

   ENUM_SIGNAL_URGENCY GetUrgencyLevel(double score) const
     {
      if(score >= m_qualityHighThreshold)   return SIGNAL_URGENCY_HIGH;
      if(score >= m_qualityMediumThreshold) return SIGNAL_URGENCY_MEDIUM;
      return SIGNAL_URGENCY_LOW;
     }

   double NormalizeScore(double rawScore, double totalWeight) const
     {
      if(totalWeight <= 0.0) return 0.0;
      return MathMax(0.0, MathMin(1.0, rawScore / totalWeight));
     }

   double ApplyMultiplier(double score, double multiplier) const
     { return score * multiplier; }

   bool PassesMinScore(double score) const
     {
      if(m_config == NULL) return true;
      return score >= m_config.GetMinScore();
     }
  };

#endif // __SIGNAL_SCORER_MQH__
