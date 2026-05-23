//+------------------------------------------------------------------+
//| Signal/SignalConfig.mqh — v1.00                                  |
//| Centralized configuration cache for Signal module                |
//|                                                                  |
//| PURPOSE:                                                         |
//|   - Extract all hardcoded values from SignalManager.mqh          |
//|   - Provide centralized config cache with auto-refresh           |
//|   - Avoid repeated global input parameter lookups                |
//|                                                                  |
//| NOTE: This is a standalone config for Signal module.             |
//|       Future: Will be integrated into StrategyConfig.Signal      |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_CONFIG_MQH__
#define __SIGNAL_CONFIG_MQH__

//+------------------------------------------------------------------+
//| Signal Configuration Structure                                   |
//| All signal-related parameters in one place                       |
//+------------------------------------------------------------------+
struct SignalConfigData
  {
   //=== General Settings ===
   int      SignalLookback;              // Bars to scan for patterns
   int      MinConfluence;               // Minimum voter sources that must agree
   double   MinScore;                    // Minimum normalized weighted score (0-1)
   int      SignalCooldownBars;          // Bars before same direction repeatable
   bool     ExitOnOpposite;              // Exit on opposite signal
   
   //=== Filter Settings ===
   bool     UseMTF;                      // Enable MTF alignment filter
   double   ZoneReuseATR;                // ATR multiplier for zone tolerance
   int      PatternFailureCooldownBars;  // Bars cooldown after failure
   ENUM_ENTRY_MODE EntryMode;            // Entry mode (SAFE/AGGRESSIVE)
   double   MaxSignalATR;                // Max candle size for valid signal
   double   AntiBreakoutPct;             // Max body/pct ratio
   double   MomentumThresholdATR;        // Min momentum in ATR
   double   MinTPDistanceATR;            // Min TP distance in ATR
   double   ATRBufferMult;               // ATR buffer multiplier
   double   MaxSpreadPoints;             // Maximum spread allowed
   double   MinATRPoints;                // Minimum ATR required
   bool     UseSessionFilter;            // Enable session filtering
   
   //=== Urgency Thresholds ===
   double   UrgencyHighThreshold;        // Score >= this = HIGH urgency
   double   UrgencyMediumThreshold;      // Score >= this = MEDIUM urgency
   
   //=== Debug & Logging ===
   bool     DebugMode;                   // Enable debug logging
   
   //=== Cache Management ===
   datetime LastUpdate;                  // Last cache update time
   
   //+------------------------------------------------------------------+
   //| Initialize with default values                                   |
   //+------------------------------------------------------------------+
   void Init()
     {
      // General Settings
      SignalLookback                 = 20;
      MinConfluence                  = 2;
      MinScore                       = 0.45;
      SignalCooldownBars             = 3;
      ExitOnOpposite                 = false;
      
      // Filter Settings
      UseMTF                         = true;
      ZoneReuseATR                   = 0.5;
      PatternFailureCooldownBars     = 5;
      EntryMode                      = MODE_SAFE;
      MaxSignalATR                   = 2.0;
      AntiBreakoutPct                = 0.7;
      MomentumThresholdATR           = 0.3;
      MinTPDistanceATR               = 1.5;
      ATRBufferMult                  = 1.0;
      MaxSpreadPoints                = 30;  // 30 points max spread
      MinATRPoints                   = 0.0; // No minimum by default
      UseSessionFilter               = false;
      
      // Urgency Thresholds
      UrgencyHighThreshold           = 0.75;
      UrgencyMediumThreshold         = 0.55;
      
      // Debug & Logging
      DebugMode                      = false;
      LastUpdate                     = 0;
     }
   
   //+------------------------------------------------------------------+
   //| Check if cache is stale (needs refresh)                          |
   //+------------------------------------------------------------------+
   bool IsStale(int maxAgeSeconds = 60) const
     {
      return (TimeCurrent() - LastUpdate) > maxAgeSeconds;
     }
  };

//+------------------------------------------------------------------+
//| CSignalConfig - Configuration Manager for Signal Module          |
//+------------------------------------------------------------------+
class CSignalConfig
  {
private:
   SignalConfigData m_config;
   bool             m_initialized;
   
public:
   //+------------------------------------------------------------------+
   //| Constructor                                                      |
   //+------------------------------------------------------------------+
   CSignalConfig() : m_initialized(false)
     {
      m_config.Init();
     }
   
   //+------------------------------------------------------------------+
   //| Initialize configuration                                         |
   //+------------------------------------------------------------------+
   void Init()
     {
      m_config.Init();
      m_initialized = true;
     }
   
   //+------------------------------------------------------------------+
   //| Getters - General Settings                                       |
   //+------------------------------------------------------------------+
   int      GetSignalLookback()              const { return m_config.SignalLookback; }
   int      GetMinConfluence()               const { return m_config.MinConfluence; }
   double   GetMinScore()                    const { return m_config.MinScore; }
   int      GetSignalCooldownBars()          const { return m_config.SignalCooldownBars; }
   bool     GetExitOnOpposite()              const { return m_config.ExitOnOpposite; }
   
   //+------------------------------------------------------------------+
   //| Getters - Filter Settings                                        |
   //+------------------------------------------------------------------+
   bool     GetUseMTF()                      const { return m_config.UseMTF; }
   double   GetZoneReuseATR()                const { return m_config.ZoneReuseATR; }
   int      GetPatternFailureCooldownBars()  const { return m_config.PatternFailureCooldownBars; }
   ENUM_ENTRY_MODE GetEntryMode()            const { return m_config.EntryMode; }
   double   GetMaxSignalATR()                const { return m_config.MaxSignalATR; }
   double   GetAntiBreakoutPct()             const { return m_config.AntiBreakoutPct; }
   double   GetMomentumThresholdATR()        const { return m_config.MomentumThresholdATR; }
   double   GetMinTPDistanceATR()            const { return m_config.MinTPDistanceATR; }
   double   GetATRBufferMult()               const { return m_config.ATRBufferMult; }
   double   GetMaxSpreadPoints()             const { return m_config.MaxSpreadPoints; }
   double   GetMinATRPoints()                const { return m_config.MinATRPoints; }
   bool     GetUseSessionFilter()            const { return m_config.UseSessionFilter; }
   
   //+------------------------------------------------------------------+
   //| Getters - Urgency Thresholds                                     |
   //+------------------------------------------------------------------+
   double   GetUrgencyHighThreshold()        const { return m_config.UrgencyHighThreshold; }
   double   GetUrgencyMediumThreshold()      const { return m_config.UrgencyMediumThreshold; }
   
   //+------------------------------------------------------------------+
   //| Getters - Debug & Logging                                        |
   //+------------------------------------------------------------------+
   bool     GetDebugMode()                   const { return m_config.DebugMode; }
   
   //+------------------------------------------------------------------+
   //| Utility: Get urgency level from score                            |
   //+------------------------------------------------------------------+
   int GetUrgencyLevel(double score) const
     {
      if(score >= m_config.UrgencyHighThreshold)   return 0; // HIGH
      if(score >= m_config.UrgencyMediumThreshold) return 1; // MEDIUM
      return 2; // LOW
     }
   
   //+------------------------------------------------------------------+
   //| Utility: Check if score passes minimum threshold                 |
   //+------------------------------------------------------------------+
   bool PassesMinScore(double score) const
     {
      return score >= m_config.MinScore;
     }
   
   //+------------------------------------------------------------------+
   //| Utility: Check if confluence meets minimum requirement           |
   //+------------------------------------------------------------------+
   bool PassesMinConfluence(int confluence) const
     {
      return confluence >= m_config.MinConfluence;
     }
  };

#endif // __SIGNAL_CONFIG_MQH__
