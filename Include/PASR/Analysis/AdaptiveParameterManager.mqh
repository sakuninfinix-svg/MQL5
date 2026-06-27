//+------------------------------------------------------------------+
//| Analysis/AdaptiveParameterManager.mqh — v1.00                    |
//| Dynamic SL/TP/lot sizing based on canonical market regime.       |
//| Copyright @2026                                                  |
//| agsicentre.wordpress.com                                         |
//+------------------------------------------------------------------+
#property strict
#ifndef __ANALYSIS_ADAPTIVE_PARAMETER_MANAGER_MQH__
#define __ANALYSIS_ADAPTIVE_PARAMETER_MANAGER_MQH__

#include "MarketRegimeDetector.mqh"
#include "../Infra/DataManager.mqh"
#include "../Core/IManager.mqh"

struct SAdaptiveConfig
  {
   double        StopLossPoints;
   double        TakeProfitPoints;
   double        TrailingStopPoints;
   double        PositionSizePercent;
   double        EntryThreshold;
   int           MaxOpenPositions;
   EMarketRegime CurrentRegime;
   double        ATR_Value;
   double        ADX_Value;
   ulong         LastUpdateBar;
   datetime      LastUpdateTime;
   ulong         ConfigHash;
  };

class CAdaptiveParameterManager : public IManager
  {
private:
   CMarketRegimeDetector *m_regimeDetector;
   SAdaptiveConfig        m_config;
   double                 m_baseSL;
   double                 m_baseTP;
   double                 m_baseRisk;
   bool                   m_cacheValid;
   datetime               m_lastBarTime;

   struct SRegimeProfile
     {
      double sl_mult;
      double tp_mult;
      double risk_mult;
      double entry_mult;
      int    max_pos;
     };

   void SetProfile(SRegimeProfile &p, double sl, double tp, double risk, double entry, int maxpos) const
     {
      p.sl_mult = sl;
      p.tp_mult = tp;
      p.risk_mult = risk;
      p.entry_mult = entry;
      p.max_pos = maxpos;
     }

   SRegimeProfile ProfileForRegime(EMarketRegime regime) const
     {
      SRegimeProfile p;
      switch(regime)
        {
         case REGIME_RANGE:      SetProfile(p, 0.8, 1.2, 1.0, 0.9, 5); break;
         case REGIME_TREND_UP:
         case REGIME_TREND_DOWN: SetProfile(p, 1.5, 2.0, 1.2, 0.8, 2); break;
         case REGIME_VOLATILE:   SetProfile(p, 2.0, 1.5, 0.5, 0.8, 1); break;
         case REGIME_CRASH:      SetProfile(p, 3.0, 1.0, 0.1, 0.95, 0); break;
         case REGIME_SQUEEZE:    SetProfile(p, 0.7, 1.0, 0.6, 0.9, 2); break;
         default:                SetProfile(p, 1.0, 1.0, 1.0, 1.0, 3); break;
        }
      return p;
     }

   void ApplyRegimeMultipliers(SDynamicParams &params, EMarketRegime regime)
     {
      SRegimeProfile p = ProfileForRegime(regime);
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

   void PublishRegimeChange(EMarketRegime regime)
     {
      PASREvent ev;
      ev.id       = EVENT_ID_ADAPTIVE_UPDATE;
      ev.priority = 3;
      ev.data1    = (double)regime;
      ev.data2    = m_config.StopLossPoints;
      ev.tag      = StringFormat("TP=%.1f", m_config.TakeProfitPoints);
      QueueEvent(ev);

      if(m_config.MaxOpenPositions == 0)
        {
         PASREvent stop;
         stop.id       = EVENT_ID_SYSTEM_HALT;
         stop.priority = 1;
         stop.data1    = (double)regime;
         stop.tag      = "Adaptive regime halted trading";
         DispatchImmediate(stop);
        }
     }

public:
   CAdaptiveParameterManager()
      : IManager(), m_regimeDetector(NULL),
        m_baseSL(20.0), m_baseTP(40.0), m_baseRisk(1.0),
        m_cacheValid(false), m_lastBarTime(0)
     {
      ZeroMemory(m_config);
      m_config.CurrentRegime = REGIME_UNKNOWN;
     }

   virtual string HandlerName() const override { return "AdaptiveParameterManager"; }

   virtual void DeclareEvents() override
     { AddEvent(EVENT_ID_NEW_BAR); AddEvent(EVENT_ID_CONFIG_RELOAD); }

   virtual void OnNewBar() override { UpdateParameters(); }

   virtual void OnEvent(const PASREvent &ev) override
     {
      if(ev.id == EVENT_ID_NEW_BAR)
        { if(m_cfgDirty) RefreshConfig(); OnNewBar(); }
      if(ev.id == EVENT_ID_CONFIG_RELOAD) m_cfgDirty = true;
     }

   bool Initialize(CMarketRegimeDetector *regimeDetector,
                   double baseSL=20.0, double baseTP=40.0, double baseRisk=1.0)
     {
      if(regimeDetector == NULL)
        { Print("[AdaptiveParams] ERROR: regimeDetector is NULL"); return false; }
      m_regimeDetector = regimeDetector;
      m_baseSL = (baseSL > 0.0) ? baseSL : 20.0;
      m_baseTP = (baseTP > 0.0) ? baseTP : 40.0;
      m_baseRisk = (baseRisk > 0.0) ? baseRisk : 1.0;
      m_cacheValid = false;
      m_lastBarTime = 0;
      return true;
     }

   bool Initialize(CDataManager *dataMgr, CEventBus *eventBus,
                   CMarketRegimeDetector *regimeDetector,
                   double baseSL, double baseTP, double baseRisk)
     {
      m_bus  = eventBus;
      m_data = dataMgr;
      return Initialize(regimeDetector, baseSL, baseTP, baseRisk);
     }

   bool UpdateParameters()
     {
      if(m_regimeDetector == NULL)
        { m_cacheValid = false; return false; }

      datetime curBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
      if(curBarTime == 0) return false;
      if(curBarTime == m_lastBarTime && m_cacheValid) return true;

      EMarketRegime detectedRegime = m_regimeDetector.Detect(_Symbol, PERIOD_CURRENT, m_data);
      SDynamicParams params = m_regimeDetector.GetParams();

      m_config.CurrentRegime = detectedRegime;
      m_config.LastUpdateBar = (ulong)iBarShift(_Symbol, PERIOD_CURRENT, curBarTime);
      m_config.LastUpdateTime = curBarTime;
      m_lastBarTime = curBarTime;

      ApplyRegimeMultipliers(params, detectedRegime);
      m_cacheValid = true;
      PublishRegimeChange(detectedRegime);

      if(m_debugMode) PrintFormat("[AdaptiveParams] %s", ExportConfigToString());
      return true;
     }

   double        GetStopLoss()       const { return m_cacheValid ? m_config.StopLossPoints      : m_baseSL;   }
   double        GetTakeProfit()     const { return m_cacheValid ? m_config.TakeProfitPoints    : m_baseTP;   }
   double        GetPositionSize()   const { return m_cacheValid ? m_config.PositionSizePercent : m_baseRisk; }
   double        GetEntryThreshold() const { return m_cacheValid ? m_config.EntryThreshold      : 0.5;        }
   int           GetMaxPositions()   const { return m_cacheValid ? m_config.MaxOpenPositions    : 1;          }
   EMarketRegime GetRegime()         const { return m_config.CurrentRegime; }

   string GetRegimeName() const { return MarketRegimeName(m_config.CurrentRegime); }

   string ExportConfigToString() const
     {
      return StringFormat("Regime=%s | SL=%.1f | TP=%.1f | Risk=%.2f%% | MaxPos=%d",
                          GetRegimeName(), m_config.StopLossPoints,
                          m_config.TakeProfitPoints,
                          m_config.PositionSizePercent * 100.0,
                          m_config.MaxOpenPositions);
     }
  };

class AdaptiveParameterManager : public CAdaptiveParameterManager {};

#endif // __ANALYSIS_ADAPTIVE_PARAMETER_MANAGER_MQH__
