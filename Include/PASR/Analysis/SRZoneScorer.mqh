//+------------------------------------------------------------------+
//| Analysis/SRZoneScorer.mqh — v1.00                                |
//| Copyright 2026                                                   |
//| agsicentre.wordpress.com                                         |
//+------------------------------------------------------------------+
#property strict
#ifndef __ANALYSIS_SR_ZONE_SCORER_MQH__
#define __ANALYSIS_SR_ZONE_SCORER_MQH__

#include "../Data/SRStruct.mqh"

struct SRZoneScoreDetail
  {
   double proximityScore;
   double strengthScore;
   double touchScore;
   double freshnessScore;
   double compositeScore;

   void Clear()
     {
      proximityScore  = 0.0;
      strengthScore   = 0.0;
      touchScore      = 0.0;
      freshnessScore  = 0.0;
      compositeScore  = 0.0;
     }
  };

class CSRZoneScorer
  {
private:
   double m_proximityWeight;
   double m_strengthWeight;
   double m_touchWeight;
   double m_freshnessWeight;

   double Clamp01(double v) const { return MathMax(0.0, MathMin(1.0, v)); }

public:
   CSRZoneScorer()
      : m_proximityWeight(0.35),
        m_strengthWeight(0.30),
        m_touchWeight(0.20),
        m_freshnessWeight(0.15)
     {}

   void SetWeights(double proximity, double strength, double touch, double freshness)
     {
      m_proximityWeight  = proximity;
      m_strengthWeight   = strength;
      m_touchWeight      = touch;
      m_freshnessWeight  = freshness;
     }

   double ScoreProximity(double price, const SRZone &zone, double atrPoints) const
     {
      if(atrPoints <= 0.0 || price <= 0.0) return 0.0;
      double atrPrice = atrPoints * _Point;
      double distance = MathAbs(price - zone.price);
      return Clamp01(1.0 - (distance / (atrPrice * 3.0)));
     }

   double ScoreStrength(const SRZone &zone) const
     {
      return Clamp01(zone.strength / 100.0);
     }

   double ScoreTouchCount(const SRZone &zone) const
     {
      if(zone.touchCount <= 0) return 0.0;
      if(zone.touchCount >= 5) return 1.0;
      return (double)zone.touchCount / 5.0;
     }

   double ScoreFreshness(const SRZone &zone) const
     {
      if(zone.lastTouchAge <= 0) return 1.0;
      if(zone.lastTouchAge >= 50) return 0.0;
      return Clamp01(1.0 - (double)zone.lastTouchAge / 50.0);
     }

   double Score(double price, const SRZone &zone, double atrPoints) const
     {
      if(!zone.IsValid()) return 0.0;
      double prox   = ScoreProximity(price, zone, atrPoints);
      double str    = ScoreStrength(zone);
      double touch  = ScoreTouchCount(zone);
      double fresh  = ScoreFreshness(zone);
      return Clamp01(prox * m_proximityWeight + str * m_strengthWeight +
                     touch * m_touchWeight + fresh * m_freshnessWeight);
     }

   SRZoneScoreDetail ScoreDetailed(double price, const SRZone &zone, double atrPoints) const
     {
      SRZoneScoreDetail detail;
      detail.Clear();
      if(!zone.IsValid()) return detail;
      detail.proximityScore = ScoreProximity(price, zone, atrPoints);
      detail.strengthScore  = ScoreStrength(zone);
      detail.touchScore     = ScoreTouchCount(zone);
      detail.freshnessScore = ScoreFreshness(zone);
      detail.compositeScore = Clamp01(
         detail.proximityScore * m_proximityWeight +
         detail.strengthScore  * m_strengthWeight  +
         detail.touchScore     * m_touchWeight      +
         detail.freshnessScore * m_freshnessWeight);
      return detail;
     }
  };

#endif // __ANALYSIS_SR_ZONE_SCORER_MQH__

