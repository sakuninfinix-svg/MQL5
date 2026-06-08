//+------------------------------------------------------------------+
//| Signal/SignalConfig.mqh — v1.02                                  |
//| Centralized configuration cache for Signal module                |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_CONFIG_MQH__
#define __SIGNAL_CONFIG_MQH__

#include "../Core/Config/Types.mqh"

enum ENUM_ENTRY_MODE
  {
   MODE_SAFE       = 0,
   MODE_BALANCED   = 1,
   MODE_AGGRESSIVE = 2
  };

struct SignalConfigData
  {
   int      SignalLookback;
   int      MinConfluence;
   double   MinScore;
   double   MinDominanceGap;
   int      MaxSourceAgeSeconds;
   int      SignalCooldownBars;
   bool     ExitOnOpposite;

   bool     UseMTF;
   double   ZoneReuseATR;
   int      PatternFailureCooldownBars;
   ENUM_ENTRY_MODE EntryMode;
   double   MaxSignalATR;
   double   AntiBreakoutPct;
   double   MomentumThresholdATR;
   double   MinTPDistanceATR;
   double   MinRRRatio;
   double   ATRBufferMult;
   double   MaxSpreadPoints;
   double   MinATRPoints;
   bool     UseSessionFilter;

   double   UrgencyHighThreshold;
   double   UrgencyMediumThreshold;

   bool     DebugMode;
   datetime LastUpdate;

   void Init()
     {
      SignalLookback                 = 20;
      MinConfluence                  = 1;
      MinScore                       = 0.45;
      MinDominanceGap                = 0.08;
      MaxSourceAgeSeconds            = 120;
      SignalCooldownBars             = 3;
      ExitOnOpposite                 = false;

      UseMTF                         = true;
      ZoneReuseATR                   = 0.5;
      PatternFailureCooldownBars     = 5;
      EntryMode                      = MODE_SAFE;
      MaxSignalATR                   = 2.0;
      AntiBreakoutPct                = 0.85;
      MomentumThresholdATR           = 0.3;
      MinTPDistanceATR               = 1.5;
      MinRRRatio                     = 1.5;
      ATRBufferMult                  = 1.0;
      MaxSpreadPoints                = 30;
      MinATRPoints                   = 0.0;
      UseSessionFilter               = false;

      UrgencyHighThreshold           = 0.75;
      UrgencyMediumThreshold         = 0.55;

      DebugMode                      = false;
      LastUpdate                     = 0;
     }

   bool IsStale(int maxAgeSeconds = 60) const
     {
      return (TimeCurrent() - LastUpdate) > maxAgeSeconds;
     }
  };

class CSignalConfig
  {
private:
   SignalConfigData m_config;
   bool             m_initialized;

   double Clamp01(const double value) const
     {
      return MathMax(0.0, MathMin(1.0, value));
     }

   double PipToPoints(const double pips) const
     {
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double factor = (digits == 3 || digits == 5) ? 10.0 : 1.0;
      return MathMax(0.0, pips) * factor;
     }

public:
   CSignalConfig() : m_initialized(false)
     { m_config.Init(); }

   void Init()
     {
      m_config.Init();
      m_config.LastUpdate = TimeCurrent();
      m_initialized = true;
     }

   void ApplyStrategyConfig(const StrategyConfig &cfg, const bool debugMode = false)
     {
      m_config.Init();

      m_config.SignalLookback = MathMax(5, cfg.Pattern.LookbackBars);
      m_config.SignalCooldownBars = MathMax(1, cfg.Risk.RecoveryCooldownBars);
      m_config.PatternFailureCooldownBars = MathMax(1, cfg.Risk.RecoveryCooldownBars);
      m_config.MaxSpreadPoints = PipToPoints(cfg.Market.SpreadFilterPips);
      m_config.UseSessionFilter = !(cfg.Market.SessionStartHour == 0 && cfg.Market.SessionEndHour == 23);
      m_config.DebugMode = debugMode;
      m_config.LastUpdate = TimeCurrent();
      m_initialized = true;
     }

   int      GetSignalLookback()              const { return m_config.SignalLookback; }
   int      GetMinConfluence()               const { return m_config.MinConfluence; }
   double   GetMinScore()                    const { return m_config.MinScore; }
   double   GetMinDominanceGap()             const { return m_config.MinDominanceGap; }
   int      GetMaxSourceAgeSeconds()         const { return m_config.MaxSourceAgeSeconds; }
   int      GetSignalCooldownBars()          const { return m_config.SignalCooldownBars; }
   bool     GetExitOnOpposite()              const { return m_config.ExitOnOpposite; }

   bool     GetUseMTF()                      const { return m_config.UseMTF; }
   double   GetZoneReuseATR()                const { return m_config.ZoneReuseATR; }
   int      GetPatternFailureCooldownBars()  const { return m_config.PatternFailureCooldownBars; }
   ENUM_ENTRY_MODE GetEntryMode()            const { return m_config.EntryMode; }
   double   GetMaxSignalATR()                const { return m_config.MaxSignalATR; }
   double   GetAntiBreakoutPct()             const { return m_config.AntiBreakoutPct; }
   double   GetMomentumThresholdATR()        const { return m_config.MomentumThresholdATR; }
   double   GetMinTPDistanceATR()            const { return m_config.MinTPDistanceATR; }
   double   GetMinRRRatio()                  const { return m_config.MinRRRatio; }
   double   GetATRBufferMult()               const { return m_config.ATRBufferMult; }
   double   GetMaxSpreadPoints()             const { return m_config.MaxSpreadPoints; }
   double   GetMinATRPoints()                const { return m_config.MinATRPoints; }
   bool     GetUseSessionFilter()            const { return m_config.UseSessionFilter; }

   double   GetUrgencyHighThreshold()        const { return m_config.UrgencyHighThreshold; }
   double   GetUrgencyMediumThreshold()      const { return m_config.UrgencyMediumThreshold; }

   bool     GetDebugMode()                   const { return m_config.DebugMode; }

   int GetUrgencyLevel(double score) const
     {
      if(score >= m_config.UrgencyHighThreshold)   return 0;
      if(score >= m_config.UrgencyMediumThreshold) return 1;
      return 2;
     }

   bool PassesMinScore(double score) const
     { return score >= m_config.MinScore; }

   bool PassesMinConfluence(int confluence) const
     { return confluence >= m_config.MinConfluence; }
  };

#endif // __SIGNAL_CONFIG_MQH__
