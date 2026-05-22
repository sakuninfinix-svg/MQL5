//+------------------------------------------------------------------+
//|                                              PatternConfig.mqh   |
//|                                 Copyright 2024, PASR Framework   |
//|                                     https://pasr-framework.com   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, PASR Framework"
#property link      "https://pasr-framework.com"
#property version   "2.0.0"
#property description "Dynamic configuration for pattern detection parameters"

#include "../Data/RegimeTypes.mqh"

//+------------------------------------------------------------------+
//| Pattern Parameter Structure                                      |
//+------------------------------------------------------------------+
struct SPatternParams
{
   // General thresholds
   double          minBodyRatio;         // Minimum body/wick ratio
   double          minWickRatio;         // Minimum wick/body ratio
   double          minTotalScore;        // Minimum score to consider valid
   int             minLookbackBars;      // Minimum bars for context
   
   // Size filters (volatility adjusted)
   double          minCandleSizeATR;     // Min size in ATR units
   double          maxCandleSizeATR;     // Max size in ATR units
   
   // Location context
   bool            requireSRConfluence;  // Must be near S/R zone
   bool            requireTrendAlign;    // Must align with trend
   double          maxDistanceFromSR;    // Max distance from S/R in points
   
   // Time filters
   int             minSessionStrength;   // Minimum session importance (1-3)
   bool            avoidNewsWindows;     // Skip patterns during news
   
   // Regime-specific overrides
   double          regimeMultiplier;     // Multiplier for current regime
   
   // Constructor
   void Init()
   {
      minBodyRatio       = 0.6;
      minWickRatio       = 0.4;
      minTotalScore      = 50.0;
      minLookbackBars    = 20;
      
      minCandleSizeATR   = 0.3;
      maxCandleSizeATR   = 3.0;
      
      requireSRConfluence = false;
      requireTrendAlign   = false;
      maxDistanceFromSR   = 10.0;
      
      minSessionStrength  = 1;
      avoidNewsWindows    = true;
      
      regimeMultiplier    = 1.0;
   }
   
   // Apply regime adjustments
   void ApplyRegime(ENUM_MARKET_REGIME regime)
   {
      switch(regime)
      {
         case REGIME_TRENDING_STRONG:
            regimeMultiplier = 1.2;  // More lenient in strong trends
            minBodyRatio    *= 0.8;
            break;
            
         case REGIME_TRENDING_WEAK:
            regimeMultiplier = 1.0;
            break;
            
         case REGIME_RANGING:
            regimeMultiplier = 0.9;  // Stricter in ranges
            minBodyRatio    *= 1.2;
            minWickRatio    *= 1.1;
            break;
            
         case REGIME_VOLATILE:
            regimeMultiplier = 0.85; // Much stricter in volatile markets
            minCandleSizeATR = 0.5;  // Require larger candles
            minBodyRatio    *= 1.3;
            break;
            
         case REGIME_TRANSITION:
            regimeMultiplier = 0.95;
            break;
            
         default:
            regimeMultiplier = 1.0;
      }
   }
};

//+------------------------------------------------------------------+
//| Pattern-specific configurations                                  |
//+------------------------------------------------------------------+
struct SPinbarParams : public SPatternParams
{
   double          minTailRatio;         // Minimum tail/candle ratio
   double          minNoseRatio;         // Minimum nose restriction
   bool            requireBreakOfPrev;   // Require break of previous high/low
   
   void Init()
   {
      SPatternParams::Init();
      minTailRatio      = 0.67;  // 2/3 rule
      minNoseRatio      = 0.25;  // Nose < 25% of total
      requireBreakOfPrev = true;
   }
};

struct SEngulfingParams : public SPatternParams
{
   double          minEngulfPercent;     // Minimum engulfment percentage
   bool            requireFullEngulf;    // Must engulf entire range
   int             minPriorTrendBars;    // Minimum prior trend bars
   
   void Init()
   {
      SPatternParams::Init();
      minEngulfPercent   = 1.0;  // 100% engulf
      requireFullEngulf  = true;
      minPriorTrendBars  = 2;
   }
};

struct SInsideBarParams : public SPatternParams
{
   double          minInsideRatio;       // Minimum inside bar compression
   bool            requireBreakoutConfirm;// Wait for breakout confirmation
   int             maxConsecutiveInside; // Max consecutive inside bars
   
   void Init()
   {
      SPatternParams::Init();
      minInsideRatio      = 0.5;
      requireBreakoutConfirm = false;
      maxConsecutiveInside  = 3;
   }
};

struct SFakeyParams : public SPatternParams
{
   double          minFakeoutDistance;   // Minimum fakeout distance
   bool            requireLiquidityGrab; // Must grab liquidity
   double          minRejectionSpeed;    // Speed of rejection
   
   void Init()
   {
      SPatternParams::Init();
      minFakeoutDistance = 5.0;  // Points
      requireLiquidityGrab = true;
      minRejectionSpeed  = 0.7;  // 70% rejection within 2 bars
   }
};

//+------------------------------------------------------------------+
//| Configuration Manager                                            |
//+------------------------------------------------------------------+
class CPatternConfigManager
{
private:
   SPatternParams    m_defaultParams;
   SPinbarParams     m_pinbarParams;
   SEngulfingParams  m_engulfingParams;
   SInsideBarParams  m_insideBarParams;
   SFakeyParams      m_fakeyParams;
   
   ENUM_MARKET_REGIME m_currentRegime;
   
public:
   void Init()
   {
      m_defaultParams.Init();
      m_pinbarParams.Init();
      m_engulfingParams.Init();
      m_insideBarParams.Init();
      m_fakeyParams.Init();
      m_currentRegime = REGIME_UNKNOWN;
   }
   
   void SetRegime(ENUM_MARKET_REGIME regime)
   {
      m_currentRegime = regime;
      
      // Apply regime adjustments to all configs
      m_defaultParams.ApplyRegime(regime);
      m_pinbarParams.ApplyRegime(regime);
      m_engulfingParams.ApplyRegime(regime);
      m_insideBarParams.ApplyRegime(regime);
      m_fakeyParams.ApplyRegime(regime);
   }
   
   // Getters for specific pattern configs
   const SPatternParams& GetDefaultParams() const { return m_defaultParams; }
   const SPinbarParams& GetPinbarParams() const { return m_pinbarParams; }
   const SEngulfingParams& GetEngulfingParams() const { return m_engulfingParams; }
   const SInsideBarParams& GetInsideBarParams() const { return m_insideBarParams; }
   const SFakeyParams& GetFakeyParams() const { return m_fakeyParams; }
   
   // Dynamic adjustment based on volatility
   void AdjustForVolatility(double atrRatio)
   {
      if(atrRatio > 2.0)  // High volatility
      {
         m_defaultParams.minCandleSizeATR = 0.5;
         m_defaultParams.minBodyRatio    *= 1.2;
      }
      else if(atrRatio < 0.5)  // Low volatility
      {
         m_defaultParams.minCandleSizeATR = 0.2;
         m_defaultParams.minBodyRatio    *= 0.9;
      }
   }
};
