//+------------------------------------------------------------------+
//| Trade/RecoveryScorer.mqh — v1.00                                 |
//| Scores recovery opportunity for a losing position.               |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_TRADE_RECOVERY_SCORER_MQH__
#define __PASR_TRADE_RECOVERY_SCORER_MQH__

struct SRecoveryContext
  {
   double currentPrice;
   int    direction;
   double entryPrice;
   double atrPoints;
   double nearestZoneDistance;
   double nearestZoneStrength;
   int    trendDirection;
   int    barsSinceEntry;

   void Clear()
     {
      currentPrice        = 0.0;
      direction           = 0;
      entryPrice          = 0.0;
      atrPoints           = 0.0;
      nearestZoneDistance = 0.0;
      nearestZoneStrength = 0.0;
      trendDirection      = 0;
      barsSinceEntry      = 0;
     }
  };

struct SRecoveryScore
  {
   double drawdownScore;
   double zoneScore;
   double trendScore;
   double timeScore;
   double composite;
   bool   shouldRecover;
   string reason;

   void Reset()
     {
      drawdownScore = 0.0;
      zoneScore     = 0.0;
      trendScore    = 0.0;
      timeScore     = 0.0;
      composite     = 0.0;
      shouldRecover = false;
      reason        = "";
     }
  };

class CRecoveryScorer
  {
private:
   double m_minScore;
   double m_maxDrawdownATR;
   double m_maxBars;

   double Clamp01(double v) const { return MathMax(0.0, MathMin(1.0, v)); }

public:
   CRecoveryScorer()
      : m_minScore(0.45),
        m_maxDrawdownATR(3.0),
        m_maxBars(20.0)
     {}

   void SetMinScore(double score) { m_minScore = score; }

   double ScoreDrawdown(const SRecoveryContext &ctx) const
     {
      if(ctx.atrPoints <= 0.0 || ctx.currentPrice <= 0.0) return 0.0;
      double atrPrice = ctx.atrPoints * _Point;
      double dd = MathAbs(ctx.currentPrice - ctx.entryPrice);
      double ddATR = dd / atrPrice;
      return Clamp01(1.0 - (ddATR / m_maxDrawdownATR));
     }

   double ScoreZoneProximity(const SRecoveryContext &ctx) const
     {
      if(ctx.atrPoints <= 0.0 || ctx.nearestZoneDistance <= 0.0) return 0.0;
      double atrPrice = ctx.atrPoints * _Point;
      double distATR = ctx.nearestZoneDistance / atrPrice;
      double proximity = Clamp01(1.0 - (distATR / 2.0));
      double strength = Clamp01(ctx.nearestZoneStrength / 100.0);
      return (proximity + strength) * 0.5;
     }

   double ScoreTrendAlignment(const SRecoveryContext &ctx) const
     {
      if(ctx.direction == 0 || ctx.trendDirection == 0) return 0.3;
      if(ctx.direction == ctx.trendDirection) return 1.0;
      if(ctx.direction == -ctx.trendDirection) return 0.0;
      return 0.3;
     }

   double ScoreTime(const SRecoveryContext &ctx) const
     {
      if(ctx.barsSinceEntry <= 0) return 1.0;
      return Clamp01(1.0 - (double)ctx.barsSinceEntry / m_maxBars);
     }

   SRecoveryScore Score(const SRecoveryContext &ctx)
     {
      SRecoveryScore out;
      out.Reset();

      if(ctx.currentPrice <= 0.0 || ctx.entryPrice <= 0.0 ||
         ctx.atrPoints <= 0.0 || ctx.direction == 0)
        {
         out.reason = "InvalidContext";
         return out;
        }

      out.drawdownScore = ScoreDrawdown(ctx);
      out.zoneScore     = ScoreZoneProximity(ctx);
      out.trendScore    = ScoreTrendAlignment(ctx);
      out.timeScore     = ScoreTime(ctx);

      out.composite = Clamp01(
         out.drawdownScore * 0.35 +
         out.zoneScore     * 0.25 +
         out.trendScore    * 0.25 +
         out.timeScore     * 0.15);

      out.shouldRecover = (out.composite >= m_minScore);

      out.reason = StringFormat("dd=%.2f zone=%.2f trend=%.2f time=%.2f => %.2f %s",
                                out.drawdownScore, out.zoneScore,
                                out.trendScore, out.timeScore,
                                out.composite,
                                out.shouldRecover ? "RECOVER" : "SKIP");
      return out;
     }
  };

#endif // __PASR_TRADE_RECOVERY_SCORER_MQH__
