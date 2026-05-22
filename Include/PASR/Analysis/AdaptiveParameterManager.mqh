//+------------------------------------------------------------------+
//|                                  AdaptiveParameterManager.mqh    |
//|                        Copyright 2024, PASR Modular System       |
//|                                     Adaptive Dynamic Parameters  |
//|                                                                  |
//| OPTIMIZED v2.00:                                                 |
//| - Unified regime enum with MarketRegimeDetector                  |
//| - Removed duplicate detection logic (delegate to RegimeDetector) |
//| - Enhanced event publishing with proper payload                  |
//| - Added configuration persistence                                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, PASR Modular System"
#property link      "https://pasr.system"
#property version   "2.00"
#property description "Dynamic parameter adjustment based on market regime (v2.00 optimized)"

#include "MarketRegimeDetector.mqh"
#include "../Infra/DataManager.mqh"
#include "../Core/EventBus.mqh"

// Use unified regime enum from MarketRegimeDetector
// Import SDynamicParams for consistency

//+------------------------------------------------------------------+
//| Extended Configuration with Persistence                          |
//+------------------------------------------------------------------+
struct SAdaptiveConfig
  {
   double StopLossPoints;         // Dynamic SL
   double TakeProfitPoints;       // Dynamic TP
   double TrailingStopPoints;     // Dynamic Trail
   double PositionSizePercent;    // Dynamic Risk %
   double EntryThreshold;         // Signal strength required
   int    MaxOpenPositions;       // Concurrent position limit
   
   // State tracking
   EMarketRegime CurrentRegime;
   double        ATR_Value;
   double        ADX_Value;
   ulong         LastUpdateBar;
   datetime      LastUpdateTime;
   
   // Persistence hash
   ulong         ConfigHash;
  };

//+------------------------------------------------------------------+
//| CAdaptiveParameterManager Class - Optimized                      |
//+------------------------------------------------------------------+
class CAdaptiveParameterManager
  {
private:
   DataManager            *m_dataMgr;
   EventBus               *m_eventBus;
   CMarketRegimeDetector  *m_regimeDetector;  // Delegate regime detection
   SAdaptiveConfig         m_config;
   
   // Cache for performance
   double                  m_cachedSL;
   double                  m_cachedTP;
   double                  m_cachedRisk;
   bool                    m_cacheValid;
   
   // Configuration profiles per regime
   struct SRegimeProfile
     {
      double sl_mult;
      double tp_mult;
      double risk_mult;
      double entry_mult;
      int    max_pos;
     };
   
   SRegimeProfile m_profiles[6];  // One per regime type
   
public:
   CAdaptiveParameterManager()
     {
      m_dataMgr          = NULL;
      m_eventBus         = NULL;
      m_regimeDetector   = NULL;
      m_cacheValid       = false;
      ZeroMemory(m_config);
      m_config.CurrentRegime = REGIME_UNKNOWN;
      
      // Initialize default profiles
      InitProfiles();
     }
     
   ~CAdaptiveParameterManager()
     {
      // Don't delete m_regimeDetector - owned elsewhere
      m_cacheValid = false;
     }
     
   //--- Initialize with dependency injection
   bool Initialize(DataManager *dataMgr, EventBus *eventBus, 
                   CMarketRegimeDetector *regimeDetector,
                   double baseSL, double baseTP, double baseRisk)
     {
      if(dataMgr == NULL || eventBus == NULL || regimeDetector == NULL) 
        {
         Print("[AdaptiveParams] ERROR: Null dependencies");
         return false;
        }
      
      m_dataMgr        = dataMgr;
      m_eventBus       = eventBus;
      m_regimeDetector = regimeDetector;
      
      // Store base parameters in profile REGIME_UNKNOWN
      m_profiles[REGIME_UNKNOWN].sl_mult   = 1.0;
      m_profiles[REGIME_UNKNOWN].tp_mult   = 1.0;
      m_profiles[REGIME_UNKNOWN].risk_mult = 1.0;
      m_profiles[REGIME_UNKNOWN].entry_mult= 1.0;
      m_profiles[REGIME_UNKNOWN].max_pos   = 3;
      
      m_config.StopLossPoints      = baseSL;
      m_config.TakeProfitPoints    = baseTP;
      m_config.PositionSizePercent = baseRisk;
      m_config.EntryThreshold      = 0.5;
      
      m_cacheValid = false;
      
      Print("[AdaptiveParams] Initialized v2.00 with regime delegation");
      return true;
     }
     
   //--- Configure regime-specific profiles
   void SetRegimeProfile(EMarketRegime regime, double slMult, double tpMult, 
                         double riskMult, double entryMult, int maxPos)
     {
      if(regime < 0 || regime >= ArraySize(m_profiles)) return;
      
      m_profiles[regime].sl_mult   = slMult;
      m_profiles[regime].tp_mult   = tpMult;
      m_profiles[regime].risk_mult = riskMult;
      m_profiles[regime].entry_mult= entryMult;
      m_profiles[regime].max_pos   = maxPos;
      
      m_cacheValid = false;  // Invalidate cache
     }
     
   //--- Main Update Logic (Call every bar, not tick)
   bool UpdateParameters()
     {
      if(m_dataMgr == NULL || m_regimeDetector == NULL) 
        {
         m_cacheValid = false;
         return false;
        }
      
      // Check if new bar formed to avoid recalculation
      datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
      if(currentBarTime == m_config.LastUpdateTime && m_cacheValid) 
        return true;  // Already updated for this bar
      
      // Get regime and params from detector (delegated logic)
      string symbol = _Symbol;
      ENUM_TIMEFRAMES tf = PERIOD_CURRENT;
      
      EMarketRegime detectedRegime = m_regimeDetector->Detect(symbol, tf, m_dataMgr);
      const SDynamicParams &params = m_regimeDetector->GetParams();
      
      // Update config
      m_config.CurrentRegime = detectedRegime;
      m_config.LastUpdateBar = (ulong)iBarShift(symbol, tf, 0);
      m_config.LastUpdateTime = currentBarTime;
      
      // Apply regime-specific multipliers
      ApplyRegimeMultipliers(params, detectedRegime);
      
      // Update cache
      m_cacheValid = true;
      
      // Publish update event with structured payload
      PublishRegimeChange(detectedRegime);
      
      return true;
     }
     
   //--- Getters with cache
   double GetStopLoss() const    
     { return m_cacheValid ? m_config.StopLossPoints : 0.0; }
   double GetTakeProfit() const  
     { return m_cacheValid ? m_config.TakeProfitPoints : 0.0; }
   double GetPositionSize() const
     { return m_cacheValid ? m_config.PositionSizePercent : 0.0; }
   double GetEntryThreshold() const
     { return m_cacheValid ? m_config.EntryThreshold : 0.5; }
   int    GetMaxPositions() const
     { return m_cacheValid ? m_config.MaxOpenPositions : 1; }
     
   EMarketRegime GetRegime() const 
     { return m_config.CurrentRegime; }
     
   string GetRegimeName() const
     {
      switch(m_config.CurrentRegime)
        {
         case REGIME_LOW_VOL:       return "LOW_VOL";
         case REGIME_TRENDING_UP:   return "TREND_UP";
         case REGIME_TRENDING_DOWN: return "TREND_DOWN";
         case REGIME_HIGH_VOL:      return "HIGH_VOL";
         case REGIME_CRASH:         return "CRASH";
         default:                   return "UNKNOWN";
        }
     }
     
   //--- Export config for logging
   string ExportConfigToString() const
     {
      return StringFormat("Regime=%s|SL=%.1f|TP=%.1f|Risk=%.2f%%|MaxPos=%d",
                         GetRegimeName(),
                         m_config.StopLossPoints,
                         m_config.TakeProfitPoints,
                         m_config.PositionSizePercent * 100.0,
                         m_config.MaxOpenPositions);
     }
     
private:
   void InitProfiles()
     {
      // REGIME_LOW_VOL: Tight stops, quick targets
      SetRegimeProfile(REGIME_LOW_VOL, 0.8, 1.2, 1.0, 0.9, 5);
      
      // REGIME_TRENDING_UP: Wide stops, let profits run
      SetRegimeProfile(REGIME_TRENDING_UP, 1.5, 2.0, 1.2, 0.8, 2);
      
      // REGIME_TRENDING_DOWN: Same as trending up
      SetRegimeProfile(REGIME_TRENDING_DOWN, 1.5, 2.0, 1.2, 0.8, 2);
      
      // REGIME_HIGH_VOL: Very wide stops, reduced risk
      SetRegimeProfile(REGIME_HIGH_VOL, 2.0, 1.5, 0.5, 0.8, 1);
      
      // REGIME_CRASH: Minimal trading
      SetRegimeProfile(REGIME_CRASH, 3.0, 1.0, 0.1, 0.95, 0);
     }
     
   void ApplyRegimeMultipliers(const SDynamicParams &params, EMarketRegime regime)
     {
      // Base values (could be from input or learned)
      double baseSL = 20.0;   // Example: 20 points
      double baseTP = 40.0;   // Example: 40 points
      double baseRisk = 1.0;  // 1% risk
      
      // Get profile multipliers
      SRegimeProfile &profile = m_profiles[regime];
      
      // Apply both detector params and profile multipliers
      m_config.StopLossPoints      = baseSL * params.sl_multiplier * profile.sl_mult;
      m_config.TakeProfitPoints    = baseTP * params.tp_multiplier * profile.tp_mult;
      m_config.TrailingStopPoints  = m_config.StopLossPoints * 0.5;
      m_config.PositionSizePercent = baseRisk * params.risk_percent * profile.risk_mult;
      m_config.EntryThreshold      = params.entry_threshold * profile.entry_mult;
      m_config.MaxOpenPositions    = MathMin(params.max_positions, profile.max_pos);
      
      // Generate config hash for change detection
      m_config.ConfigHash = GenerateConfigHash();
     }
     
   ulong GenerateConfigHash() const
     {
      // Simple hash of current config for change tracking
      ulong hash = 14695981039346656037UL;
      hash ^= (ulong)(m_config.StopLossPoints * 100);
      hash *= 1099511628211UL;
      hash ^= (ulong)(m_config.TakeProfitPoints * 100);
      hash *= 1099511628211UL;
      hash ^= (ulong)m_config.CurrentRegime;
      hash *= 1099511628211UL;
      hash ^= (ulong)m_config.MaxOpenPositions;
      return hash;
     }
     
   void PublishRegimeChange(EMarketRegime regime)
     {
      if(m_eventBus == NULL) return;
      
      // Pack structured event data
      long regimeCode = (long)regime;
      double sl = m_config.StopLossPoints;
      double tp = m_config.TakeProfitPoints;
      double risk = m_config.PositionSizePercent;
      
      // Publish to event bus
      m_eventBus->Publish(EVENT_ID_ADAPTIVE_UPDATE, 
                         regimeCode, 
                         sl, 
                         tp,
                         risk);
      
      if(m_config.MaxOpenPositions == 0)
        {
         // Emergency stop - publish high priority event
         m_eventBus->Publish(EVENT_ID_EMERGENCY_STOP, 
                            regimeCode, 
                            0, 
                            0);
        }
     }
  };
