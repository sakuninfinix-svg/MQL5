//+------------------------------------------------------------------+
//|                                  MarketRegimeDetector.mqh        |
//|                        Copyright 2024, PASR Architecture         |
//|                                                                  |
//| OPTIMIZED v2.01:                                                 |
//| - Uses centralized EMarketRegime from RegimeTypes.mqh            |
//| - Enhanced regime detection with multi-factor analysis           |
//| - Added crash detection and emergency handling                   |
//| - Improved parameter adjustment logic                            |
//| - Better integration with AdaptiveParameterManager               |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, PASR Architecture"
#property link      "https://pasr.quant"
#property version   "2.01"
#property description "Detects market regime (Trending/Ranging/Volatile) with multi-factor analysis (v2.01)"

#include "../Infra/DataManager.mqh"
#include "../Data/RegimeTypes.mqh"

// Remove duplicate enum - use EMarketRegime from RegimeTypes.mqh

//+------------------------------------------------------------------+
//| Dynamic Parameters Structure                                     |
//+------------------------------------------------------------------+
struct SDynamicParams
{
   double sl_multiplier;       // SL adjustment factor
   double tp_multiplier;       // TP adjustment factor
   double risk_percent;        // Dynamic risk %
   double entry_threshold;     // Min signal strength required
   int    max_positions;       // Max concurrent positions
   string regime_name;         // Human readable name
   
   // Additional metrics for advanced analysis
   double volatility_ratio;    // Current ATR / Average ATR
   double trend_strength;      // ADX value normalized
   double momentum_score;      // DI+ vs DI- differential
};

//+------------------------------------------------------------------+
//| Class CMarketRegimeDetector - Optimized                          |
//+------------------------------------------------------------------+
class CMarketRegimeDetector
{
private:
   EMarketRegime    m_current_regime;
   SDynamicParams   m_params;
   
   // Configuration with defaults
   int              m_atr_period;
   int              m_adx_period;
   int              m_vol_lookback;     // Period for average ATR
   double           m_vol_low_thresh;
   double           m_vol_high_thresh;
   double           m_trend_strength_thresh;
   double           m_crash_thresh;
   
   // Cache for performance
   double           m_last_atr;
   double           m_last_adx;
   double           m_last_di_plus;
   double           m_last_di_minus;
   double           m_avg_atr;
   datetime         m_last_update;
   ulong            m_update_count;
   
   // Hysteresis to prevent rapid regime switching
   EMarketRegime    m_prev_regime;
   int              m_regime_stable_bars;
   const int        MIN_STABLE_BARS = 2;  // Minimum bars before regime change

public:
   CMarketRegimeDetector() : m_current_regime(REGIME_UNKNOWN), 
                             m_prev_regime(REGIME_UNKNOWN),
                             m_last_update(0),
                             m_update_count(0),
                             m_regime_stable_bars(0)
   {
      // Default configuration
      m_atr_period           = 14;
      m_adx_period           = 14;
      m_vol_lookback         = 50;
      m_vol_low_thresh       = 0.5;
      m_vol_high_thresh      = 2.0;
      m_trend_strength_thresh= 25.0;
      m_crash_thresh         = 3.0;
      
      // Initialize cache
      m_last_atr             = 0;
      m_last_adx             = 0;
      m_last_di_plus         = 0;
      m_last_di_minus        = 0;
      m_avg_atr              = 0;
      
      ResetToDefault();
   }
   
   ~CMarketRegimeDetector() {}
   
   //--- Configure detector parameters
   void SetParameters(int atrPeriod, int adxPeriod, int volLookback,
                     double volLowThresh, double volHighThresh, 
                     double trendThresh, double crashThresh)
   {
      m_atr_period            = atrPeriod;
      m_adx_period            = adxPeriod;
      m_vol_lookback          = volLookback;
      m_vol_low_thresh        = volLowThresh;
      m_vol_high_thresh       = volHighThresh;
      m_trend_strength_thresh = trendThresh;
      m_crash_thresh          = crashThresh;
      
      // Invalidate cache when parameters change
      m_last_update = 0;
   }
   
   void ResetToDefault()
   {
      m_params.sl_multiplier    = 1.0;
      m_params.tp_multiplier    = 1.0;
      m_params.risk_percent     = 1.0;
      m_params.entry_threshold  = 0.5;
      m_params.max_positions    = 3;
      m_params.regime_name      = "NEUTRAL";
      m_params.volatility_ratio = 1.0;
      m_params.trend_strength   = 0.0;
      m_params.momentum_score   = 0.0;
   }
   
   //--- Main detection logic with hysteresis
   EMarketRegime Detect(const string symbol, ENUM_TIMEFRAMES tf, DataManager* dataMgr)
   {
      if(dataMgr == NULL) return m_current_regime;
      
      // Check if we need to recalculate (new bar or first run)
      datetime currentBarTime = iTime(symbol, tf, 0);
      if(currentBarTime == m_last_update && m_update_count > 0)
         return m_current_regime;  // Return cached regime
      
      // Get latest metrics from DataManager
      double atr = dataMgr.GetATR(symbol, tf, m_atr_period);
      double adx = dataMgr.GetADX(symbol, tf, m_adx_period);
      double di_plus = dataMgr.GetDIPlus(symbol, tf, m_adx_period);
      double di_minus = dataMgr.GetDIMinus(symbol, tf, m_adx_period);
      
      if(atr <= 0 || adx < 0) 
      {
         // Invalid data - maintain current regime
         return m_current_regime;
      }
      
      // Update cache
      m_last_atr      = atr;
      m_last_adx      = adx;
      m_last_di_plus  = di_plus;
      m_last_di_minus = di_minus;
      m_avg_atr       = dataMgr.GetAverageATR(symbol, tf, m_vol_lookback);
      m_last_update   = currentBarTime;
      m_update_count++;
      
      // Calculate derived metrics
      m_params.volatility_ratio = (m_avg_atr > 0) ? (atr / m_avg_atr) : 1.0;
      m_params.trend_strength   = adx;
      m_params.momentum_score   = di_plus - di_minus;
      
      // Detect regime with multi-factor analysis
      EMarketRegime detectedRegime = AnalyzeRegime();
      
      // Apply hysteresis to prevent rapid switching
      if(detectedRegime != m_current_regime)
      {
         m_regime_stable_bars++;
         
         // Only switch if regime has been stable for MIN_STABLE_BARS
         if(m_regime_stable_bars >= MIN_STABLE_BARS)
         {
            m_prev_regime = m_current_regime;
            m_current_regime = detectedRegime;
            m_regime_stable_bars = 0;
            
            // Adjust parameters for new regime
            ApplyRegimeAdjustments();
            
            PrintFormat("[Regime] Changed from %s to %s (stable after %d bars)",
                       GetRegimeName(m_prev_regime),
                       GetRegimeName(m_current_regime),
                       m_regime_stable_bars);
         }
      }
      else
      {
         m_regime_stable_bars = 0;  // Reset counter when regime matches
      }
      
      return m_current_regime;
   }
   
   //--- Accessors
   const SDynamicParams& GetParams() const { return m_params; }
   EMarketRegime GetCurrentRegime() const { return m_current_regime; }
   string GetRegimeName(EMarketRegime regime) const
   {
      // Use centralized mapping from RegimeTypes.mqh logic
      switch(regime)
      {
         case REGIME_RANGE:       return "RANGE";        // was LOW_VOL
         case REGIME_TREND_UP:    return "TREND_UP";     // was TRENDING_UP
         case REGIME_TREND_DOWN:  return "TREND_DOWN";   // was TRENDING_DOWN
         case REGIME_VOLATILE:    return "VOLATILE";     // was HIGH_VOL
         case REGIME_CRASH:       return "CRASH";
         default:                 return "UNKNOWN";
      }
   }
   
   //--- Export regime info for logging
   string ExportRegimeInfo() const
   {
      return StringFormat("Regime=%s|VolRatio=%.2f|ADX=%.1f|Momentum=%.2f|Risk=%.1f%%",
                         GetRegimeName(m_current_regime),
                         m_params.volatility_ratio,
                         m_params.trend_strength,
                         m_params.momentum_score,
                         m_params.risk_percent * 100.0);
   }
   
   //--- Get statistics
   ulong GetUpdateCount() const { return m_update_count; }
   datetime GetLastUpdate() const { return m_last_update; }
   
private:
   //--- Multi-factor regime analysis
   EMarketRegime AnalyzeRegime()
   {
      double volRatio = m_params.volatility_ratio;
      double adx      = m_params.trend_strength;
      double momScore = m_params.momentum_score;
      
      // Priority 1: Crash detection (extreme volatility)
      if(volRatio > m_crash_thresh) 
      {
         return REGIME_CRASH;
      }
      
      // Priority 2: High volatility (chaotic market)
      if(volRatio > m_vol_high_thresh)
      {
         return REGIME_VOLATILE;
      }
      
      // Priority 3: Trending market (strong ADX)
      if(adx > m_trend_strength_thresh)
      {
         // Determine trend direction using DI differential
         if(momScore > 5.0)  // DI+ significantly above DI-
         {
            return REGIME_TREND_UP;
         }
         else if(momScore < -5.0)  // DI- significantly above DI+
         {
            return REGIME_TREND_DOWN;
         }
         // ADX high but no clear direction = high volatility
         return REGIME_VOLATILE;
      }
      
      // Priority 4: Low volatility (quiet market)
      if(volRatio < m_vol_low_thresh)
      {
         return REGIME_RANGE;
      }
      
      // Default: Normal/range-bound market
      return REGIME_RANGE;
   }
   
   //--- Apply parameter adjustments based on regime
   void ApplyRegimeAdjustments()
   {
      switch(m_current_regime)
      {
         case REGIME_TREND_UP:
         case REGIME_TREND_DOWN:
            AdjustParamsForTrend(m_current_regime == REGIME_TREND_UP);
            break;
            
         case REGIME_VOLATILE:
            AdjustParamsForHighVol();
            break;
            
         case REGIME_RANGE:
            AdjustParamsForLowVol();
            break;
            
         case REGIME_CRASH:
            AdjustParamsForCrash();
            break;
            
         default:
            AdjustParamsForRange();
      }
   }
   
   void AdjustParamsForTrend(bool is_bullish)
   {
      m_params.regime_name    = is_bullish ? "TREND_UP" : "TREND_DOWN";
      m_params.sl_multiplier  = 1.5;   // Wider SL to avoid noise
      m_params.tp_multiplier  = 2.0;   // Let profits run
      m_params.risk_percent   = 1.2;   // Slightly higher risk in trends
      m_params.entry_threshold= 0.4;   // Lower threshold to catch early
      m_params.max_positions  = 2;     // Fewer but bigger trades
   }
   
   void AdjustParamsForRange()
   {
      m_params.regime_name    = "RANGE";
      m_params.sl_multiplier  = 0.8;   // Tight SL
      m_params.tp_multiplier  = 1.2;   // Quick take profit
      m_params.risk_percent   = 0.8;   // Conservative
      m_params.entry_threshold= 0.7;   // Only high confidence
      m_params.max_positions  = 4;     // More frequent scalping
   }
   
   void AdjustParamsForHighVol()
   {
      m_params.regime_name    = "HIGH_VOL";
      m_params.sl_multiplier  = 2.0;   // Very wide SL
      m_params.tp_multiplier  = 1.5;
      m_params.risk_percent   = 0.5;   // Reduce size due to volatility
      m_params.entry_threshold= 0.8;   // Very selective
      m_params.max_positions  = 1;     // One trade at a time
   }
   
   void AdjustParamsForLowVol()
   {
      m_params.regime_name    = "LOW_VOL";
      m_params.sl_multiplier  = 0.7;
      m_params.tp_multiplier  = 1.0;
      m_params.risk_percent   = 0.6;
      m_params.entry_threshold= 0.6;
      m_params.max_positions  = 5;     // Scalp often
   }
   
   void AdjustParamsForCrash()
   {
      m_params.regime_name    = "CRASH";
      m_params.sl_multiplier  = 3.0;
      m_params.tp_multiplier  = 1.0;
      m_params.risk_percent   = 0.1;   // Minimal risk
      m_params.entry_threshold= 0.95;  // Almost no trading
      m_params.max_positions  = 0;     // Stop trading effectively
   }
};
