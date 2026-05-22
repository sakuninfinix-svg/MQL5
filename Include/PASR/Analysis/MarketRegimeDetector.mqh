//+------------------------------------------------------------------+
//|                                  MarketRegimeDetector.mqh        |
//|                        Copyright 2024, PASR Architecture         |
//|                                     Adaptive Dynamic Parameters  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, PASR Architecture"
#property link      "https://pasr.quant"
#property version   "1.00"
#property description "Detects market regime (Trending/Ranging/Volatile) and adjusts parameters dynamically"

#include "../Infra/DataManager.mqh"

//--- Enum Market Regimes
enum EMarketRegime
{
   REGIME_UNKNOWN      = 0,
   REGIME_LOW_VOL      = 1,  // Sideways, tight range
   REGIME_TRENDING_UP  = 2,  // Strong bullish
   REGIME_TRENDING_DOWN= 3,  // Strong bearish
   REGIME_HIGH_VOL     = 4,  // Chaotic, news events
   REGIME_CRASH        = 5   // Extreme move
};

//--- Structure for Dynamic Parameters
struct SDynamicParams
{
   double sl_multiplier;       // SL adjustment factor
   double tp_multiplier;       // TP adjustment factor
   double risk_percent;        // Dynamic risk %
   double entry_threshold;     // Min signal strength required
   int    max_positions;       // Max concurrent positions
   string regime_name;         // Human readable name
};

//+------------------------------------------------------------------+
//| Class CMarketRegimeDetector                                      |
//+------------------------------------------------------------------+
class CMarketRegimeDetector
{
private:
   EMarketRegime m_current_regime;
   SDynamicParams m_params;
   
   // Configuration
   int m_atr_period;
   int m_adx_period;
   double m_vol_low_thresh;
   double m_vol_high_thresh;
   double m_trend_strength_thresh;
   
   // Cache
   double m_last_atr;
   double m_last_adx;
   double m_last_di_plus;
   double m_last_di_minus;
   datetime m_last_update;

public:
   CMarketRegimeDetector() : m_current_regime(REGIME_UNKNOWN), m_last_update(0)
   {
      m_atr_period = 14;
      m_adx_period = 14;
      m_vol_low_thresh = 0.5;   // Relative to average
      m_vol_high_thresh = 2.0;  // Relative to average
      m_trend_strength_thresh = 25.0; // ADX level
      
      // Default params (Neutral)
      ResetToDefault();
   }
   
   ~CMarketRegimeDetector() {}
   
   void ResetToDefault()
   {
      m_params.sl_multiplier = 1.0;
      m_params.tp_multiplier = 1.0;
      m_params.risk_percent = 1.0;
      m_params.entry_threshold = 0.5;
      m_params.max_positions = 3;
      m_params.regime_name = "NEUTRAL";
   }
   
   // Initialize indicators (called once in OnInit)
   bool Initialize(const string symbol, ENUM_TIMEFRAMES tf)
   {
      // In real implementation, create indicator handles here
      // For now, we assume DataManager provides ATR/ADX values
      return true;
   }
   
   // Main detection logic
   EMarketRegime Detect(const string symbol, ENUM_TIMEFRAMES tf, CDataManager* dataMgr)
   {
      if(dataMgr == NULL) return m_current_regime;
      
      // Get latest metrics from DataManager
      double atr = dataMgr.GetATR(symbol, tf, m_atr_period);
      double adx = dataMgr.GetADX(symbol, tf, m_adx_period);
      double di_plus = dataMgr.GetDIPlus(symbol, tf, m_adx_period);
      double di_minus = dataMgr.GetDIMinus(symbol, tf, m_adx_period);
      
      if(atr <= 0 || adx < 0) return m_current_regime; // Invalid data
      
      m_last_atr = atr;
      m_last_adx = adx;
      m_last_di_plus = di_plus;
      m_last_di_minus = di_minus;
      m_last_update = TimeCurrent();
      
      // 1. Check Volatility (ATR based)
      double avg_atr = dataMgr.GetAverageATR(symbol, tf, 50); // 50-period average
      double vol_ratio = (avg_atr > 0) ? (atr / avg_atr) : 1.0;
      
      if(vol_ratio > 3.0) 
      {
         m_current_regime = REGIME_CRASH;
         AdjustParamsForCrash();
         return m_current_regime;
      }
      
      if(vol_ratio > m_vol_high_thresh)
      {
         m_current_regime = REGIME_HIGH_VOL;
         AdjustParamsForHighVol();
         return m_current_regime;
      }
      
      if(vol_ratio < m_vol_low_thresh)
      {
         m_current_regime = REGIME_LOW_VOL;
         AdjustParamsForLowVol();
         return m_current_regime;
      }
      
      // 2. Check Trend Strength (ADX based)
      if(adx > m_trend_strength_thresh)
      {
         if(di_plus > di_minus)
         {
            m_current_regime = REGIME_TRENDING_UP;
            AdjustParamsForTrend(true);
         }
         else
         {
            m_current_regime = REGIME_TRENDING_DOWN;
            AdjustParamsForTrend(false);
         }
         return m_current_regime;
      }
      
      // Default: Low/Med Vol + Weak Trend = Range
      m_current_regime = REGIME_LOW_VOL;
      AdjustParamsForRange();
      return m_current_regime;
   }
   
   const SDynamicParams& GetParams() const { return m_params; }
   EMarketRegime GetCurrentRegime() const { return m_current_regime; }
   
private:
   void AdjustParamsForTrend(bool is_bullish)
   {
      m_params.regime_name = is_bullish ? "TREND_UP" : "TREND_DOWN";
      m_params.sl_multiplier = 1.5;   // Wider SL to avoid noise
      m_params.tp_multiplier = 2.0;   // Let profits run
      m_params.risk_percent = 1.2;    // Slightly higher risk
      m_params.entry_threshold = 0.4; // Lower threshold to catch early
      m_params.max_positions = 2;     // Fewer but bigger trades
   }
   
   void AdjustParamsForRange()
   {
      m_params.regime_name = "RANGE";
      m_params.sl_multiplier = 0.8;   // Tight SL
      m_params.tp_multiplier = 1.2;   // Quick take profit
      m_params.risk_percent = 0.8;    // Conservative
      m_params.entry_threshold = 0.7; // Only high confidence
      m_params.max_positions = 4;     // More frequent scalping
   }
   
   void AdjustParamsForHighVol()
   {
      m_params.regime_name = "HIGH_VOL";
      m_params.sl_multiplier = 2.0;   // Very wide SL
      m_params.tp_multiplier = 1.5;
      m_params.risk_percent = 0.5;    // Reduce size due to volatility
      m_params.entry_threshold = 0.8; // Very selective
      m_params.max_positions = 1;     // One trade at a time
   }
   
   void AdjustParamsForLowVol()
   {
      m_params.regime_name = "LOW_VOL";
      m_params.sl_multiplier = 0.7;
      m_params.tp_multiplier = 1.0;
      m_params.risk_percent = 0.6;
      m_params.entry_threshold = 0.6;
      m_params.max_positions = 5;     // Scalp often
   }
   
   void AdjustParamsForCrash()
   {
      m_params.regime_name = "CRASH";
      m_params.sl_multiplier = 3.0;
      m_params.tp_multiplier = 1.0;
      m_params.risk_percent = 0.1;    // Minimal risk
      m_params.entry_threshold = 0.95;// Almost no trading
      m_params.max_positions = 0;     // Stop trading effectively
   }
};
