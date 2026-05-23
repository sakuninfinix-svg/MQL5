//+------------------------------------------------------------------+
//| Signal/SignalScorer.mqh — v1.00                                  |
//| Signal scoring and quality assessment component                  |
//|                                                                  |
//| PURPOSE:                                                         |
//|   - Calculate signal quality scores                              |
//|   - MTF bias scoring with quality tiers                          |
//|   - Urgency level determination                                  |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_SCORER_MQH__
#define __SIGNAL_SCORER_MQH__

#include "../Data/SRStruct.mqh"
#include "SignalConfig.mqh"

//+------------------------------------------------------------------+
//| Signal Quality Enum                                              |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_QUALITY
  {
   SIGNAL_QUALITY_HIGH   = 0,   // Score > 80 (strong confluence)
   SIGNAL_QUALITY_MEDIUM = 1,   // Score 50-80 (moderate confluence)
   SIGNAL_QUALITY_LOW    = 2    // Score < 50 (weak signal)
  };

//+------------------------------------------------------------------+
//| Signal Urgency Enum                                              |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_URGENCY
  {
   SIGNAL_URGENCY_HIGH   = 0,   // score >= 0.75
   SIGNAL_URGENCY_MEDIUM = 1,   // score >= 0.55
   SIGNAL_URGENCY_LOW    = 2    // score <  0.55 (filtered by default)
  };

//+------------------------------------------------------------------+
//| ScoredSignal - Signal with quality and urgency metrics           |
//+------------------------------------------------------------------+
struct ScoredSignal
  {
   ENUM_SIGNAL_DIR     direction;
   double              rawScore;         // Raw aggregated score
   double              normalizedScore;  // Normalized 0.0-1.0 score
   double              confidence;       // Alias for normalizedScore
   int                 confluence;       // Count of agreeing sources
   ENUM_SIGNAL_QUALITY quality;          // HIGH/MEDIUM/LOW quality tier
   ENUM_SIGNAL_URGENCY urgency;          // HIGH/MEDIUM/LOW urgency
   string              contributingSources; // Names of agreeing sources
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

//+------------------------------------------------------------------+
//| CSignalScorer - Scoring engine for signals                       |
//+------------------------------------------------------------------+
class CSignalScorer
  {
private:
   const CSignalConfig *m_config;
   
   // Quality thresholds
   double m_qualityHighThreshold;    // > this = HIGH quality
   double m_qualityMediumThreshold;  // >= this = MEDIUM quality
   
public:
   //+------------------------------------------------------------------+
   //| Constructor                                                      |
   //+------------------------------------------------------------------+
   CSignalScorer() : m_config(NULL),
                     m_qualityHighThreshold(0.75),
                     m_qualityMediumThreshold(0.55)
     {
     }
   
   //+------------------------------------------------------------------+
   //| Initialize with config                                           |
   //+------------------------------------------------------------------+
   void Init(const CSignalConfig &config)
     {
      m_config = &config;
      m_qualityHighThreshold = config.GetUrgencyHighThreshold();
      m_qualityMediumThreshold = config.GetUrgencyMediumThreshold();
     }
   
   //+------------------------------------------------------------------+
   //| Set quality thresholds                                           |
   //+------------------------------------------------------------------+
   void SetQualityThresholds(double highThreshold, double mediumThreshold)
     {
      m_qualityHighThreshold = highThreshold;
      m_qualityMediumThreshold = mediumThreshold;
     }
   
   //+------------------------------------------------------------------+
   //| Calculate MTF Bias                                               |
   //| Returns: 1 (bullish), -1 (bearish), 0 (neutral)                  |
   //+------------------------------------------------------------------+
   int CalculateMTFBias(double price, 
                       double htfSupport, 
                       double htfResistance, 
                       double atrPoints,
                       double atrBufferMult) const
     {
      if(m_config != NULL && !m_config->GetUseMTF())
        return 0;
      
      double zone = (atrPoints * atrBufferMult) * _Point;
      bool nearHtfSupport = (price <= htfSupport + zone);
      bool nearHtfResistance = (price >= htfResistance - zone);
      
      if(nearHtfSupport && !nearHtfResistance) 
        return 1;   // Bullish bias
      if(nearHtfResistance && !nearHtfSupport) 
        return -1;  // Bearish bias
      return 0;     // Neutral
     }
   
   //+------------------------------------------------------------------+
   //| Calculate Quality Score based on MTF alignment                   |
   //| dir: 1=BUY, -1=SELL                                              |
   //| bias: from CalculateMTFBias()                                    |
   //| Returns: quality score (higher = better)                         |
   //+------------------------------------------------------------------+
   int CalculateQualityScore(int dir, int bias) const
     {
      // dir * bias gives us:
      //   1  = aligned (HIGH quality)
      //   0  = neutral (MEDIUM quality)
      //  -1  = contra (LOW quality / blocked)
      return dir * bias;
     }
   
   //+------------------------------------------------------------------+
   //| Get Quality Tier from score                                      |
   //+------------------------------------------------------------------+
   ENUM_SIGNAL_QUALITY GetQualityTier(double score) const
     {
      if(score > 80.0) return SIGNAL_QUALITY_HIGH;
      if(score >= 50.0) return SIGNAL_QUALITY_MEDIUM;
      return SIGNAL_QUALITY_LOW;
     }
   
   //+------------------------------------------------------------------+
   //| Get Urgency Level from score                                     |
   //+------------------------------------------------------------------+
   ENUM_SIGNAL_URGENCY GetUrgencyLevel(double score) const
     {
      if(score >= m_qualityHighThreshold)   return SIGNAL_URGENCY_HIGH;
      if(score >= m_qualityMediumThreshold) return SIGNAL_URGENCY_MEDIUM;
      return SIGNAL_URGENCY_LOW;
     }
   
   //+------------------------------------------------------------------+
   //| Normalize score to 0.0-1.0 range                                 |
   //+------------------------------------------------------------------+
   double NormalizeScore(double rawScore, double totalWeight) const
     {
      if(totalWeight <= 0.0) return 0.0;
      return MathMax(0.0, MathMin(1.0, rawScore / totalWeight));
     }
   
   //+------------------------------------------------------------------+
   //| Apply multiplier factor to score                                 |
   //+------------------------------------------------------------------+
   double ApplyMultiplier(double score, double multiplier) const
     {
      return score * multiplier;
     }
   
   //+------------------------------------------------------------------+
   //| Check if score passes minimum threshold                          |
   //+------------------------------------------------------------------+
   bool PassesMinScore(double score) const
     {
      if(m_config == NULL) return true;
      return score >= m_config->GetMinScore();
     }
   
   //+------------------------------------------------------------------+
   //| Check if confluence meets minimum requirement                    |
   //+------------------------------------------------------------------+
   bool PassesMinConfluence(int confluence) const
     {
      if(m_config == NULL) return true;
      return confluence >= m_config->GetMinConfluence();
     }
   
   //+------------------------------------------------------------------+
   //| Build scored signal from aggregation results                     |
   //+------------------------------------------------------------------+
   ScoredSignal BuildScoredSignal(ENUM_SIGNAL_DIR direction,
                                 double rawScore,
                                 double totalWeight,
                                 double multiplierFactor,
                                 int confluenceCount,
                                 const string &sources)
     {
      ScoredSignal sig;
      sig.Clear();
      
      sig.direction = direction;
      sig.rawScore = rawScore;
      sig.normalizedScore = NormalizeScore(rawScore, totalWeight);
      sig.normalizedScore = ApplyMultiplier(sig.normalizedScore, multiplierFactor);
      sig.confidence = sig.normalizedScore;
      sig.confluence = confluenceCount;
      sig.contributingSources = sources;
      sig.time = TimeCurrent();
      
      // Determine quality and urgency
      sig.quality = GetQualityTier(sig.normalizedScore * 100.0);
      sig.urgency = GetUrgencyLevel(sig.normalizedScore);
      
      return sig;
     }
   
   //+------------------------------------------------------------------+
   //| Validate signal meets all criteria                               |
   //+------------------------------------------------------------------+
   bool IsValidSignal(const ScoredSignal &sig) const
     {
      if(sig.direction == SIGNAL_NONE) return false;
      if(!PassesMinScore(sig.normalizedScore)) return false;
      if(!PassesMinConfluence(sig.confluence)) return false;
      if(sig.urgency == SIGNAL_URGENCY_LOW) return false;
      return true;
     }
  };

#endif // __SIGNAL_SCORER_MQH__
