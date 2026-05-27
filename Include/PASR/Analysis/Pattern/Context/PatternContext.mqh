//+------------------------------------------------------------------+
//| Analysis/Pattern/Context/PatternContext.mqh — v2.0.1             |
//| Rich context enrichment for pattern detection                    |
//+------------------------------------------------------------------+
#property strict
#ifndef __ANALYSIS_PATTERN_CONTEXT_MQH__
#define __ANALYSIS_PATTERN_CONTEXT_MQH__

#include "../../../Data/RegimeTypes.mqh"

//+------------------------------------------------------------------+
//| Market Context Structure                                         |
//+------------------------------------------------------------------+
struct SMarketContext
  {
   EMarketRegime      regime;              // Current market regime
   ENUM_TIMEFRAMES    timeframe;           // Current timeframe
   double             atr;                 // ATR value (volatility)
   double             atrRatio;            // ATR ratio vs average
   int                trendStrength;       // -100 to +100
   double             adx;                 // ADX value
   bool               isHighImpactNews;    // News filter
   int                sessionStrength;     // 1-3 (Asia=1, London=2, NY=3)
   datetime           lastBarTime;         // Last bar timestamp

   void Init()
     {
      regime           = REGIME_UNKNOWN;
      timeframe        = PERIOD_CURRENT;
      atr              = 0.0;
      atrRatio         = 1.0;
      trendStrength    = 0;
      adx              = 0.0;
      isHighImpactNews = false;
      sessionStrength  = 1;
      lastBarTime      = 0;
     }

   bool IsTrending() const
     {
      return (regime == REGIME_TREND_UP || regime == REGIME_TREND_DOWN);
     }

   bool IsRanging() const
     {
      return (regime == REGIME_RANGE);
     }

   bool IsVolatile() const
     {
      return (regime == REGIME_VOLATILE || regime == REGIME_CRASH);
     }
  };

//+------------------------------------------------------------------+
//| Location Context                                                  |
//+------------------------------------------------------------------+
struct SLocationContext
  {
   bool     nearSupport;
   bool     nearResistance;
   double   distanceToSR;
   int      srTouchCount;
   double   srStrength;
   bool     atRoundNumber;
   bool     atFibLevel;
   double   fibLevel;

   void Init()
     {
      nearSupport    = false;
      nearResistance = false;
      distanceToSR   = DBL_MAX;
      srTouchCount   = 0;
      srStrength     = 0.0;
      atRoundNumber  = false;
      atFibLevel     = false;
      fibLevel       = 0.0;
     }

   double GetConfluenceScore() const
     {
      double score = 0.0;
      if(nearSupport || nearResistance) score += 30.0;
      if(srTouchCount >= 3) score += 20.0;
      else if(srTouchCount >= 2) score += 10.0;
      if(srStrength > 70.0) score += 25.0;
      else if(srStrength > 50.0) score += 15.0;
      if(atRoundNumber) score += 15.0;
      if(atFibLevel && (fibLevel == 0.618 || fibLevel == 0.5 || fibLevel == 0.382)) score += 20.0;
      return MathMin(score, 100.0);
     }
  };

//+------------------------------------------------------------------+
//| Multi-Timeframe Context                                           |
//+------------------------------------------------------------------+
struct SMTFContext
  {
   EMarketRegime   higherTF_Regime;
   EMarketRegime   lowerTF_Regime;
   int             higherTF_Trend;
   int             lowerTF_Trend;
   bool            mtfAlignment;
   double          higherTF_ATR;
   double          lowerTF_ATR;

   void Init()
     {
      higherTF_Regime = REGIME_UNKNOWN;
      lowerTF_Regime  = REGIME_UNKNOWN;
      higherTF_Trend  = 0;
      lowerTF_Trend   = 0;
      mtfAlignment    = false;
      higherTF_ATR    = 0.0;
      lowerTF_ATR     = 0.0;
     }

   void CheckAlignment(int currentTrend)
     {
      mtfAlignment = (higherTF_Trend == currentTrend && lowerTF_Trend == currentTrend);
     }

   double GetAlignmentBonus() const
     {
      if(mtfAlignment) return 25.0;
      if(higherTF_Trend != 0 && higherTF_Trend == lowerTF_Trend) return 15.0;
      return 0.0;
     }
  };

//+------------------------------------------------------------------+
//| Volume/Momentum Context                                           |
//+------------------------------------------------------------------+
struct SVolumeContext
  {
   double   volumeRatio;
   bool     volumeSpike;
   double   obvTrend;
   double   momentumValue;
   bool     divergence;
   int      divergenceBars;

   void Init()
     {
      volumeRatio   = 1.0;
      volumeSpike   = false;
      obvTrend      = 0.0;
      momentumValue = 0.0;
      divergence    = false;
      divergenceBars= 0;
     }

   double GetVolumeScore() const
     {
      double score = 50.0;
      if(volumeSpike) score += 20.0;
      if(volumeRatio > 2.0) score += 15.0;
      else if(volumeRatio > 1.5) score += 10.0;
      else if(volumeRatio < 0.5) score -= 15.0;
      if(divergence) score += 25.0;
      return MathMax(0.0, MathMin(score, 100.0));
     }
  };

//+------------------------------------------------------------------+
//| Complete Pattern Context                                          |
//+------------------------------------------------------------------+
class CPatternContextEnriched
  {
private:
   SMarketContext     m_marketCtx;
   SLocationContext   m_locationCtx;
   SMTFContext        m_mtfCtx;
   SVolumeContext     m_volumeCtx;

public:
   void Init()
     {
      m_marketCtx.Init();
      m_locationCtx.Init();
      m_mtfCtx.Init();
      m_volumeCtx.Init();
     }

   void SetMarketContext(const SMarketContext &ctx)     { m_marketCtx = ctx; }
   void SetLocationContext(const SLocationContext &ctx) { m_locationCtx = ctx; }
   void SetMTFContext(const SMTFContext &ctx)           { m_mtfCtx = ctx; }
   void SetVolumeContext(const SVolumeContext &ctx)     { m_volumeCtx = ctx; }

   const SMarketContext&   GetMarketContext()   const { return m_marketCtx; }
   const SLocationContext& GetLocationContext() const { return m_locationCtx; }
   const SMTFContext&      GetMTFContext()      const { return m_mtfCtx; }
   const SVolumeContext&   GetVolumeContext()   const { return m_volumeCtx; }

   double GetTotalContextScore() const
     {
      double score = 0.0;
      if(m_marketCtx.IsTrending()) score += 25.0;
      else if(m_marketCtx.regime == REGIME_RANGE) score += 15.0;
      score += m_locationCtx.GetConfluenceScore() * 0.35;
      score += m_mtfCtx.GetAlignmentBonus() * 0.20;
      score += m_volumeCtx.GetVolumeScore() * 0.15;
      return MathMax(0.0, MathMin(score, 100.0));
     }

   bool IsContextFavorable(double minScore = 50.0) const
     {
      return GetTotalContextScore() >= minScore;
     }

   double GetPositionSizeModifier() const
     {
      double score = GetTotalContextScore();
      if(score >= 80.0) return 1.0;
      if(score >= 65.0) return 0.75;
      if(score >= 50.0) return 0.5;
      if(score >= 35.0) return 0.25;
      return 0.0;
     }

   string ToString() const
     {
      string result = "Pattern Context:\n";
      result += StringFormat("  Regime: %s\n", MarketRegimeName(m_marketCtx.regime));
      result += StringFormat("  Location Score: %.1f\n", m_locationCtx.GetConfluenceScore());
      result += StringFormat("  MTF Aligned: %s\n", m_mtfCtx.mtfAlignment ? "Yes" : "No");
      result += StringFormat("  Volume Score: %.1f\n", m_volumeCtx.GetVolumeScore());
      result += StringFormat("  Total Score: %.1f\n", GetTotalContextScore());
      return result;
     }
  };

#endif // __ANALYSIS_PATTERN_CONTEXT_MQH__
