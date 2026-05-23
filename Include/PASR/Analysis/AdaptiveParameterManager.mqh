//+------------------------------------------------------------------+
//| Analysis/AdaptiveParameterManager.mqh — v3.00                   |
//| Dynamic SL/TP/lot sizing based on market regime.                 |
//|                                                                  |
//| CHANGELOG:                                                       |
//|   v3.00 (2026-05-23) Sprint 10 — BUG-013 + BUG-014 fixed:      |
//|     BUG-013 [CRITICAL]: OnNewBar() added as IManager override.  |
//|       PipelineEngine::Stage_AdaptiveParams() calls OnNewBar().  |
//|       Previously only UpdateParameters() existed — compile fail. |
//|     BUG-014 [HIGH]: Now extends IManager.                       |
//|       DeclareEvents() subscribes EVENT_ID_NEW_BAR to EventBus.  |
//|       OnEvent() routes EVENT_ID_NEW_BAR → OnNewBar().           |
//|     BONUS: baseSL/baseTP no longer hardcoded to 20/40.          |
//|       Passed via Initialize() — properly sourced from EA inputs. |
//|     BONUS: EventBus::Publish() fixed to 4-param signature.      |
//|   v2.00 — Unified regime enum, config persistence, profiles.    |
//+------------------------------------------------------------------+
#property strict

#ifndef __ANALYSIS_ADAPTIVE_PARAMETER_MANAGER_MQH__
#define __ANALYSIS_ADAPTIVE_PARAMETER_MANAGER_MQH__

#ifdef __CORE_PASR_MASTER_MQH__
  // OK — included via PASR.mqh
#else
  #error "Include <PASR/Core/PASR.mqh> instead of AdaptiveParameterManager.mqh directly."
#endif

#include "MarketRegimeDetector.mqh"
#include "../Infra/DataManager.mqh"
#include "../Core/IManager.mqh"

//+------------------------------------------------------------------+
//| SAdaptiveConfig — runtime state snapshot                        |
//+------------------------------------------------------------------+
struct SAdaptiveConfig
  {
   double        StopLossPoints;
   double        TakeProfitPoints;
   double        TrailingStopPoints;
   double        PositionSizePercent;
   double        EntryThreshold;
   int           MaxOpenPositions;

   // State
   EMarketRegime CurrentRegime;
   double        ATR_Value;
   double        ADX_Value;
   ulong         LastUpdateBar;
   datetime      LastUpdateTime;
   ulong         ConfigHash;
  };

//+------------------------------------------------------------------+
//| CAdaptiveParameterManager : public IManager  (BUG-014 FIX)      |
//|                                                                  |
//| Extends IManager so:                                             |
//|   1. DeclareEvents() registers EVENT_ID_NEW_BAR with EventBus.  |
//|   2. OnEvent() dispatches bus events to OnNewBar().             |
//|   3. PipelineEngine Stage_AdaptiveParams() can call OnNewBar(). |
//+------------------------------------------------------------------+
class CAdaptiveParameterManager : public IManager
  {
private:
   CMarketRegimeDetector *m_regimeDetector;  // injected, not owned
   SAdaptiveConfig        m_config;

   // Base parameters from EA inputs (BUG-014 BONUS: no more hardcode)
   double                 m_baseSL;
   double                 m_baseTP;
   double                 m_baseRisk;

   // Cache
   bool                   m_cacheValid;
   datetime               m_lastBarTime;  // fallback guard

   // Per-regime multiplier profiles
   struct SRegimeProfile
     {
      double sl_mult;
      double tp_mult;
      double risk_mult;
      double entry_mult;
      int    max_pos;
     };
   SRegimeProfile m_profiles[6];  // indexed by EMarketRegime

   //+---------------------------------------------------------------+
   //| ApplyRegimeMultipliers                                        |
   //| BUG-014 BONUS: uses m_baseSL/m_baseTP, not hardcoded 20/40.  |
   //+---------------------------------------------------------------+
   void ApplyRegimeMultipliers(const SDynamicParams &params, EMarketRegime regime)
     {
      SRegimeProfile &p = m_profiles[(int)regime < 6 ? (int)regime : 0];

      m_config.StopLossPoints      = m_baseSL   * params.sl_multiplier  * p.sl_mult;
      m_config.TakeProfitPoints    = m_baseTP   * params.tp_multiplier  * p.tp_mult;
      m_config.TrailingStopPoints  = m_config.StopLossPoints * 0.5;
      m_config.PositionSizePercent = m_baseRisk * params.risk_percent   * p.risk_mult;
      m_config.EntryThreshold      = params.entry_threshold             * p.entry_mult;
      m_config.MaxOpenPositions    = MathMin(params.max_positions, p.max_pos);
      m_config.ConfigHash          = GenerateConfigHash();
     }

   ulong GenerateConfigHash() const
     {
      ulong h = 14695981039346656037UL;
      h ^= (ulong)(m_config.StopLossPoints   * 100); h *= 1099511628211UL;
      h ^= (ulong)(m_config.TakeProfitPoints * 100); h *= 1099511628211UL;
      h ^= (ulong)m_config.CurrentRegime;            h *= 1099511628211UL;
      h ^= (ulong)m_config.MaxOpenPositions;         h *= 1099511628211UL;
      return h;
     }

   //+---------------------------------------------------------------+
   //| PublishRegimeChange — BUG-014 BONUS: 4-param Publish()       |
   //| Previous code called Publish(id, long, double, double, double) |
   //| EventBus::Publish() only takes (id, long, double, double).    |
   //+---------------------------------------------------------------+
   void PublishRegimeChange(EMarketRegime regime)
     {
      if(CheckPointer(m_bus) == POINTER_INVALID) return;

      // Pack regime + SL into first two slots; TP in third
      m_bus.Publish(EVENT_ID_ADAPTIVE_UPDATE,
                    (long)regime,
                    m_config.StopLossPoints,
                    m_config.TakeProfitPoints);

      if(m_config.MaxOpenPositions == 0)
         m_bus.Publish(EVENT_ID_EMERGENCY_STOP, (long)regime, 0.0, 0.0);
     }

   void InitProfiles()
     {
      // REGIME_UNKNOWN(0)
      m_profiles[0] = {1.0, 1.0, 1.0, 1.0, 3};
      // REGIME_LOW_VOL(1)
      m_profiles[1] = {0.8, 1.2, 1.0, 0.9, 5};
      // REGIME_TRENDING_UP(2)
      m_profiles[2] = {1.5, 2.0, 1.2, 0.8, 2};
      // REGIME_TRENDING_DOWN(3)
      m_profiles[3] = {1.5, 2.0, 1.2, 0.8, 2};
      // REGIME_HIGH_VOL(4)
      m_profiles[4] = {2.0, 1.5, 0.5, 0.8, 1};
      // REGIME_CRASH(5)
      m_profiles[5] = {3.0, 1.0, 0.1, 0.95, 0};
     }

public:
   //+---------------------------------------------------------------+
   //| Constructor: all members zero-initialized via IManager chain  |
   //+---------------------------------------------------------------+
   CAdaptiveParameterManager()
      : IManager(),
        m_regimeDetector(NULL),
        m_baseSL(20.0), m_baseTP(40.0), m_baseRisk(1.0),
        m_cacheValid(false), m_lastBarTime(0)
     {
      ZeroMemory(m_config);
      m_config.CurrentRegime = REGIME_UNKNOWN;
      InitProfiles();
     }

   virtual ~CAdaptiveParameterManager() {}

   //== IManager contract (BUG-014 FIX) ============================+

   virtual string HandlerName() const override
     { return "AdaptiveParameterManager"; }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
     }

   //+---------------------------------------------------------------+
   //| OnNewBar (BUG-013 FIX)                                       |
   //| PipelineEngine::Stage_AdaptiveParams() calls m_adaptive->     |
   //| OnNewBar(). Before this fix, the method did not exist and     |
   //| caused a compile error at the Stage_AdaptiveParams call site. |
   //+---------------------------------------------------------------+
   virtual void OnNewBar() override
     {
      UpdateParameters();
     }

   //+---------------------------------------------------------------+
   //| OnEvent — routes EventBus dispatches to OnNewBar()           |
   //+---------------------------------------------------------------+
   virtual void OnEvent(const PASREvent &ev) override
     {
      if(ev.id == EVENT_ID_NEW_BAR)
        {
         if(m_cfgDirty) RefreshConfig();
         OnNewBar();
        }
      if(ev.id == EVENT_ID_CONFIG_RELOAD)
         m_cfgDirty = true;
     }

   //== Initialization =============================================+

   bool Initialize(CMarketRegimeDetector *regimeDetector,
                   double baseSL   = 20.0,
                   double baseTP   = 40.0,
                   double baseRisk = 1.0)
     {
      if(CheckPointer(regimeDetector) == POINTER_INVALID)
        {
         Print("[AdaptiveParams] ERROR: regimeDetector is NULL");
         return false;
        }
      m_regimeDetector = regimeDetector;
      m_baseSL         = (baseSL   > 0) ? baseSL   : 20.0;
      m_baseTP         = (baseTP   > 0) ? baseTP   : 40.0;
      m_baseRisk       = (baseRisk > 0) ? baseRisk : 1.0;
      m_cacheValid     = false;
      m_lastBarTime    = 0;

      PrintFormat("[AdaptiveParams] v3.00 Init | baseSL=%.1f baseTP=%.1f risk=%.2f%%",
                  m_baseSL, m_baseTP, m_baseRisk * 100.0);
      return true;
     }

   //--- Legacy 6-param overload for backward compat with Orchestrator
   bool Initialize(DataManager *dataMgr, EventBus *eventBus,
                   CMarketRegimeDetector *regimeDetector,
                   double baseSL, double baseTP, double baseRisk)
     {
      // Wire IManager fields manually (Orchestrator may not call
      // InitManager() for this class yet — BUG-004 fix scope)
      m_bus  = eventBus;
      m_data = dataMgr;
      return Initialize(regimeDetector, baseSL, baseTP, baseRisk);
     }

   //== Profile configuration ======================================+

   void SetRegimeProfile(EMarketRegime regime,
                         double slMult, double tpMult,
                         double riskMult, double entryMult, int maxPos)
     {
      int idx = (int)regime;
      if(idx < 0 || idx >= 6) return;
      m_profiles[idx] = {slMult, tpMult, riskMult, entryMult, maxPos};
      m_cacheValid = false;
     }

   //== Core Update Logic ==========================================+

   //+---------------------------------------------------------------+
   //| UpdateParameters — the actual computation.                   |
   //| OnNewBar() calls this; can also be called directly.          |
   //| BUG-013 FIX: New-bar detection now driven by EventBus        |
   //|   (OnNewBar is called per EVENT_ID_NEW_BAR dispatch) rather  |
   //|   than self-polling iTime() every tick. The iTime() guard    |
   //|   is kept as a safety fallback for double-fire prevention.   |
   //+---------------------------------------------------------------+
   bool UpdateParameters()
     {
      if(CheckPointer(m_regimeDetector) == POINTER_INVALID)
        {
         m_cacheValid = false;
         return false;
        }

      // Safety fallback: skip if same bar already processed
      datetime curBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
      if(curBarTime == m_lastBarTime && m_cacheValid)
         return true;

      // Delegate regime detection to MarketRegimeDetector
      string symbol = _Symbol;
      ENUM_TIMEFRAMES tf = PERIOD_CURRENT;
      EMarketRegime detectedRegime = m_regimeDetector.Detect(symbol, tf, m_data);
      const SDynamicParams &params  = m_regimeDetector.GetParams();

      m_config.CurrentRegime  = detectedRegime;
      m_config.LastUpdateBar  = (ulong)iBarShift(symbol, tf, 0);
      m_config.LastUpdateTime = curBarTime;
      m_lastBarTime           = curBarTime;

      ApplyRegimeMultipliers(params, detectedRegime);

      m_cacheValid = true;
      PublishRegimeChange(detectedRegime);

      if(m_debugMode)
         PrintFormat("[AdaptiveParams] %s", ExportConfigToString());

      return true;
     }

   //== Getters (cache-guarded) =====================================+

   double        GetStopLoss()       const { return m_cacheValid ? m_config.StopLossPoints      : m_baseSL;   }
   double        GetTakeProfit()     const { return m_cacheValid ? m_config.TakeProfitPoints    : m_baseTP;   }
   double        GetPositionSize()   const { return m_cacheValid ? m_config.PositionSizePercent : m_baseRisk; }
   double        GetEntryThreshold() const { return m_cacheValid ? m_config.EntryThreshold      : 0.5;        }
   int           GetMaxPositions()   const { return m_cacheValid ? m_config.MaxOpenPositions    : 1;          }
   EMarketRegime GetRegime()         const { return m_config.CurrentRegime; }

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

   string ExportConfigToString() const
     {
      return StringFormat("Regime=%s | SL=%.1f | TP=%.1f | Risk=%.2f%% | MaxPos=%d",
                         GetRegimeName(),
                         m_config.StopLossPoints,
                         m_config.TakeProfitPoints,
                         m_config.PositionSizePercent * 100.0,
                         m_config.MaxOpenPositions);
     }
  };

typedef CAdaptiveParameterManager AdaptiveParameterManager;

#endif // __ANALYSIS_ADAPTIVE_PARAMETER_MANAGER_MQH__
