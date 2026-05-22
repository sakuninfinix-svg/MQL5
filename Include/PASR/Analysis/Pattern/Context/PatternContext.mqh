//+------------------------------------------------------------------+
//|                                             PatternContext.mqh   |
//|                                 Copyright 2024, PASR Framework   |
//|                                     https://pasr-framework.com   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, PASR Framework"
#property link      "https://pasr-framework.com"
#property version   "2.0.0"
#property description "Rich context enrichment for pattern detection"

#include <Arrays/ArrayObj.mqh>
#include "../Data/RegimeTypes.mqh"
#include "../../Trade/RiskManager.mqh"

//+------------------------------------------------------------------+
//| Market Context Structure                                         |
//+------------------------------------------------------------------+
struct SMarketContext
{
   ENUM_MARKET_REGIME   regime;              // Current market regime
   ENUM_TIMEFRAMES      timeframe;          // Current timeframe
   double               atr;                // ATR value (volatility)
   double               atrRatio;           // ATR ratio vs average
   int                  trendStrength;      // -100 to +100
   double               adx;                // ADX value
   bool                 isHighImpactNews;   // News filter
   int                  sessionStrength;    // 1-3 (Asia=1, London=2, NY=3)
   datetime             lastBarTime;        // Last bar timestamp
   
   void Init()
   {
      regime            = REGIME_UNKNOWN;
      timeframe         = PERIOD_CURRENT;
      atr               = 0.0;
      atrRatio          = 1.0;
      trendStrength     = 0;
      adx               = 0.0;
      isHighImpactNews  = false;
      sessionStrength   = 1;
      lastBarTime       = 0;
   }
   
   bool IsTrending() const
   {
      return (regime == REGIME_TRENDING_STRONG || regime == REGIME_TRENDING_WEAK);
   }
   
   bool IsRanging() const
   {
      return (regime == REGIME_RANGING);
   }
   
   bool IsVolatile() const
   {
      return (regime == REGIME_VOLATILE);
   }
};

//+------------------------------------------------------------------+
//| Location Context (S/R, Support/Resistance confluence)            |
//+------------------------------------------------------------------+
struct SLocationContext
{
   bool               nearSupport;          // Near support zone
   bool               nearResistance;       // Near resistance zone
   double             distanceToSR;         // Distance to nearest S/R in points
   int                srTouchCount;         // Number of touches on nearby SR
   double             srStrength;           // Strength of nearby SR (0-100)
   bool               atRoundNumber;        // At psychological level
   bool               atFibLevel;           // At Fibonacci level
   double             fibLevel;             // Which Fib level (0.382, 0.5, 0.618, etc)
   
   void Init()
   {
      nearSupport      = false;
      nearResistance   = false;
      distanceToSR     = DBL_MAX;
      srTouchCount     = 0;
      srStrength       = 0.0;
      atRoundNumber    = false;
      atFibLevel       = false;
      fibLevel         = 0.0;
   }
   
   double GetConfluenceScore() const
   {
      double score = 0.0;
      
      if(nearSupport || nearResistance)
         score += 30.0;
      
      if(srTouchCount >= 3)
         score += 20.0;
      else if(srTouchCount >= 2)
         score += 10.0;
      
      if(srStrength > 70.0)
         score += 25.0;
      else if(srStrength > 50.0)
         score += 15.0;
      
      if(atRoundNumber)
         score += 15.0;
      
      if(atFibLevel && (fibLevel == 0.618 || fibLevel == 0.5 || fibLevel == 0.382))
         score += 20.0;
      
      return MathMin(score, 100.0);
   }
};

//+------------------------------------------------------------------+
//| Multi-Timeframe Context                                          |
//+------------------------------------------------------------------+
struct SMTFContext
{
   ENUM_MARKET_REGIME   higherTF_Regime;    // Higher timeframe regime
   ENUM_MARKET_REGIME   lowerTF_Regime;     // Lower timeframe regime
   int                  higherTF_Trend;     // Higher TF trend direction (-1, 0, 1)
   int                  lowerTF_Trend;      // Lower TF trend direction
   bool                 mtfAlignment;       // All TFs aligned
   double               higherTF_ATR;       // Higher TF volatility
   double               lowerTF_ATR;        // Lower TF volatility
   
   void Init()
   {
      higherTF_Regime   = REGIME_UNKNOWN;
      lowerTF_Regime    = REGIME_UNKNOWN;
      higherTF_Trend    = 0;
      lowerTF_Trend     = 0;
      mtfAlignment      = false;
      higherTF_ATR      = 0.0;
      lowerTF_ATR       = 0.0;
   }
   
   void CheckAlignment(int currentTrend)
   {
      mtfAlignment = (higherTF_Trend == currentTrend && lowerTF_Trend == currentTrend);
   }
   
   double GetAlignmentBonus() const
   {
      if(mtfAlignment)
         return 25.0;
      
      if(higherTF_Trend != 0 && higherTF_Trend == lowerTF_Trend)
         return 15.0;
      
      return 0.0;
   }
};

//+------------------------------------------------------------------+
//| Volume/Momentum Context                                          |
//+------------------------------------------------------------------+
struct SVolumeContext
{
   double             volumeRatio;          // Current volume vs average
   bool               volumeSpike;          // Unusual volume
   double             obvTrend;             // OBV trend strength
   double             momentumValue;        // Momentum indicator value
   bool               divergence;           // Price/momentum divergence
   int                divergenceBars;       // Bars since divergence started
   
   void Init()
   {
      volumeRatio      = 1.0;
      volumeSpike      = false;
      obvTrend         = 0.0;
      momentumValue    = 0.0;
      divergence       = false;
      divergenceBars   = 0;
   }
   
   double GetVolumeScore() const
   {
      double score = 50.0;  // Neutral
      
      if(volumeSpike)
         score += 20.0;
      
      if(volumeRatio > 2.0)
         score += 15.0;
      else if(volumeRatio > 1.5)
         score += 10.0;
      else if(volumeRatio < 0.5)
         score -= 15.0;
      
      if(divergence)
         score += 25.0;  // Divergence is strong signal
      
      return MathMax(0.0, MathMin(score, 100.0));
   }
};

//+------------------------------------------------------------------+
//| Complete Pattern Context (Aggregation)                           |
//+------------------------------------------------------------------+
class CPatternContext
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
   
   // Setters
   void SetMarketContext(const SMarketContext &ctx) { m_marketCtx = ctx; }
   void SetLocationContext(const SLocationContext &ctx) { m_locationCtx = ctx; }
   void SetMTFContext(const SMTFContext &ctx) { m_mtfCtx = ctx; }
   void SetVolumeContext(const SVolumeContext &ctx) { m_volumeCtx = ctx; }
   
   // Getters
   const SMarketContext& GetMarketContext() const { return m_marketCtx; }
   const SLocationContext& GetLocationContext() const { return m_locationCtx; }
   const SMTFContext& GetMTFContext() const { return m_mtfCtx; }
   const SVolumeContext& GetVolumeContext() const { return m_volumeCtx; }
   
   // Calculate total context score (0-100)
   double GetTotalContextScore() const
   {
      double score = 0.0;
      int weightCount = 0;
      
      // Market regime weight (30%)
      if(m_marketCtx.IsTrending())
         score += 25.0;
      else if(m_marketCtx.regy == REGIME_RANGING)
         score += 15.0;
      weightCount += 30;
      
      // Location confluence weight (35%)
      double locScore = m_locationCtx.GetConfluenceScore();
      score += locScore * 0.35;
      
      // MTF alignment weight (20%)
      double mtfBonus = m_mtfCtx.GetAlignmentBonus();
      score += mtfBonus * 0.20;
      
      // Volume/momentum weight (15%)
      double volScore = m_volumeCtx.GetVolumeScore();
      score += volScore * 0.15;
      
      return MathMax(0.0, MathMin(score, 100.0));
   }
   
   // Check if context is favorable for trading
   bool IsContextFavorable(double minScore = 50.0) const
   {
      return GetTotalContextScore() >= minScore;
   }
   
   // Get recommended position size modifier based on context
   double GetPositionSizeModifier() const
   {
      double score = GetTotalContextScore();
      
      if(score >= 80.0)
         return 1.0;    // Full size
      else if(score >= 65.0)
         return 0.75;   // 75% size
      else if(score >= 50.0)
         return 0.5;    // Half size
      else if(score >= 35.0)
         return 0.25;   // Quarter size
      else
         return 0.0;    // No trade
   }
   
   string ToString() const
   {
      string result = "Pattern Context:\n";
      result += StringFormat("  Regime: %s\n", EnumToString(m_marketCtx.regime));
      result += StringFormat("  Location Score: %.1f\n", m_locationCtx.GetConfluenceScore());
      result += StringFormat("  MTF Aligned: %s\n", m_mtfCtx.mtfAlignment ? "Yes" : "No");
      result += StringFormat("  Volume Score: %.1f\n", m_volumeCtx.GetVolumeScore());
      result += StringFormat("  Total Score: %.1f\n", GetTotalContextScore());
      return result;
   }
};
