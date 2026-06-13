//+------------------------------------------------------------------+
//|                                      Core/Config/Manager.mqh    |
//|                                      Copyright 2026, Agsicentre |
//|                                                                  |
//|  Phase 2G: centralized config lifecycle, snapshot, diagnostics.  |
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_CONFIG_MANAGER_MQH__
#define __CORE_CONFIG_MANAGER_MQH__

#include "Types.mqh"
#include "Validator.mqh"
#include "../EventBus.mqh"
#include "../Events.mqh"

struct ConfigManagerSnapshot
  {
   bool     valid;
   datetime lastReload;
   long     magic;
   string   eaName;
   string   version;

   double   riskLotSize;
   double   riskPercent;
   double   riskSLMult;
   double   riskTPMult;
   double   maxDailyLossPct;
   double   maxDrawdownPct;
   int      maxOpenPositions;
   int      maxConsecLoss;
   bool     recoveryEnabled;
   int      maxRecoveryAttempts;
   int      recoveryCooldownBars;
   double   partialClosePct;
   int      maxTradeDurationDays;

   int      atrPeriod;
   int      adxPeriod;
   double   adxTrendThreshold;
   double   spreadFilterPips;
   int      sessionStartHour;
   int      sessionEndHour;
   bool     filterNewsTime;
   int      newsBufferMinutes;

   bool     aiEnabled;
   double   aiMinConfidence;
   double   aiLearningRate;
   int      aiTrainIntervalBars;
   int      aiReplayBufferSize;
   int      aiMinibatchSize;
   bool     aiPersistWeights;
   string   aiModelFileName;

   bool     patternsEnabled;
   double   minPatternScore;
   int      patternLookbackBars;
   double   pinBarRatio;
   double   engulfMultiplier;
   bool     requireConfirmation;

   bool     showDashboard;
   bool     showSignalArrows;
   bool     enableAlerts;
   bool     enablePushNotify;
   int      fontSize;

   string   lastValidationStatus;

   void Clear()
     {
      valid = false;
      lastReload = 0;
      magic = 0;
      eaName = "";
      version = "";
      riskLotSize = 0.0;
      riskPercent = 0.0;
      riskSLMult = 0.0;
      riskTPMult = 0.0;
      maxDailyLossPct = 0.0;
      maxDrawdownPct = 0.0;
      maxOpenPositions = 0;
      maxConsecLoss = 0;
      recoveryEnabled = false;
      maxRecoveryAttempts = 0;
      recoveryCooldownBars = 0;
      partialClosePct = 0.0;
      maxTradeDurationDays = 0;
      atrPeriod = 0;
      adxPeriod = 0;
      adxTrendThreshold = 0.0;
      spreadFilterPips = 0.0;
      sessionStartHour = 0;
      sessionEndHour = 0;
      filterNewsTime = false;
      newsBufferMinutes = 0;
      aiEnabled = false;
      aiMinConfidence = 0.0;
      aiLearningRate = 0.0;
      aiTrainIntervalBars = 0;
      aiReplayBufferSize = 0;
      aiMinibatchSize = 0;
      aiPersistWeights = false;
      aiModelFileName = "";
      patternsEnabled = false;
      minPatternScore = 0.0;
      patternLookbackBars = 0;
      pinBarRatio = 0.0;
      engulfMultiplier = 0.0;
      requireConfirmation = false;
      showDashboard = false;
      showSignalArrows = false;
      enableAlerts = false;
      enablePushNotify = false;
      fontSize = 0;
      lastValidationStatus = "UNINITIALIZED";
     }
  };

class CConfigManager
  {
private:
   StrategyConfig        m_cfg;
   bool                  m_cfgValid;
   CEventBus            *m_bus;
   datetime              m_lastReload;
   ConfigManagerSnapshot m_snapshot;

   void ApplyDefaults(StrategyConfig &cfg)
     {
      // StrategyConfig and its sub-struct constructors already provide
      // production-safe defaults. This method intentionally only fills
      // optional identity fields so bad numeric values are caught by the
      // validator instead of being silently overwritten.
      if(StringLen(cfg.EAName) == 0)  cfg.EAName  = "PASR";
      if(StringLen(cfg.Version) == 0) cfg.Version = "2.16.0";
      if(cfg.MagicNumber <= 0)        cfg.MagicNumber = 123456;
     }

   void UpdateSnapshot(const string validationStatus)
     {
      m_snapshot.Clear();
      m_snapshot.valid = m_cfgValid;
      m_snapshot.lastReload = m_lastReload;
      m_snapshot.magic = m_cfg.MagicNumber;
      m_snapshot.eaName = m_cfg.EAName;
      m_snapshot.version = m_cfg.Version;

      m_snapshot.riskLotSize = m_cfg.Risk.LotSize;
      m_snapshot.riskPercent = m_cfg.Risk.RiskPercent;
      m_snapshot.riskSLMult = m_cfg.Risk.SLMultiplier;
      m_snapshot.riskTPMult = m_cfg.Risk.TPMultiplier;
      m_snapshot.maxDailyLossPct = m_cfg.Risk.MaxDailyLossPct;
      m_snapshot.maxDrawdownPct = m_cfg.Risk.MaxDrawdownPct;
      m_snapshot.maxOpenPositions = m_cfg.Risk.MaxOpenPositions;
      m_snapshot.maxConsecLoss = m_cfg.Risk.MaxConsecLoss;
      m_snapshot.recoveryEnabled = m_cfg.Risk.RecoveryEnabled;
      m_snapshot.maxRecoveryAttempts = m_cfg.Risk.MaxRecoveryAttempts;
      m_snapshot.recoveryCooldownBars = m_cfg.Risk.RecoveryCooldownBars;
      m_snapshot.partialClosePct = m_cfg.Risk.PartialClosePct;
      m_snapshot.maxTradeDurationDays = m_cfg.Risk.MaxTradeDurationDays;

      m_snapshot.atrPeriod = m_cfg.Market.ATRPeriod;
      m_snapshot.adxPeriod = m_cfg.Market.ADXPeriod;
      m_snapshot.adxTrendThreshold = m_cfg.Market.ADXTrendThreshold;
      m_snapshot.spreadFilterPips = m_cfg.Market.SpreadFilterPips;
      m_snapshot.sessionStartHour = m_cfg.Market.SessionStartHour;
      m_snapshot.sessionEndHour = m_cfg.Market.SessionEndHour;
      m_snapshot.filterNewsTime = m_cfg.Market.FilterNewsTime;
      m_snapshot.newsBufferMinutes = m_cfg.Market.NewsBufferMinutes;

      m_snapshot.aiEnabled = m_cfg.AI.EnableAI;
      m_snapshot.aiMinConfidence = m_cfg.AI.MinConfidence;
      m_snapshot.aiLearningRate = m_cfg.AI.LearningRate;
      m_snapshot.aiTrainIntervalBars = m_cfg.AI.TrainIntervalBars;
      m_snapshot.aiReplayBufferSize = m_cfg.AI.ReplayBufferSize;
      m_snapshot.aiMinibatchSize = m_cfg.AI.MinibatchSize;
      m_snapshot.aiPersistWeights = m_cfg.AI.PersistWeights;
      m_snapshot.aiModelFileName = m_cfg.AI.ModelFileName;

      m_snapshot.patternsEnabled = m_cfg.Pattern.EnablePatterns;
      m_snapshot.minPatternScore = m_cfg.Pattern.MinPatternScore;
      m_snapshot.patternLookbackBars = m_cfg.Pattern.LookbackBars;
      m_snapshot.pinBarRatio = m_cfg.Pattern.PinBarRatio;
      m_snapshot.engulfMultiplier = m_cfg.Pattern.EngulfMultiplier;
      m_snapshot.requireConfirmation = m_cfg.Pattern.RequireConfirmation;

      m_snapshot.showDashboard = m_cfg.Display.ShowDashboard;
      m_snapshot.showSignalArrows = m_cfg.Display.ShowSignalArrows;
      m_snapshot.enableAlerts = m_cfg.Display.EnableAlerts;
      m_snapshot.enablePushNotify = m_cfg.Display.EnablePushNotify;
      m_snapshot.fontSize = m_cfg.Display.FontSize;
      m_snapshot.lastValidationStatus = validationStatus;
     }

public:
   CConfigManager()
      : m_cfgValid(false), m_bus(NULL), m_lastReload(0)
     {
      m_snapshot.Clear();
     }

   void SetEventBus(CEventBus *bus) { m_bus = bus; }

   int Init(StrategyConfig &inputCfg)
     {
      m_cfg = inputCfg;
      ApplyDefaults(m_cfg);
      string errors[];
      if(!CConfigValidator::Validate(m_cfg, errors))
        {
         CConfigValidator::PrintErrors(errors);
         m_cfgValid = false;
         m_lastReload = TimeCurrent();
         UpdateSnapshot("INIT_INVALID");
         return INIT_PARAMETERS_INCORRECT;
        }
      m_cfgValid   = true;
      m_lastReload = TimeCurrent();
      UpdateSnapshot("INIT_OK");
      Print("[CConfigManager] Init OK — magic=", m_cfg.MagicNumber,
            " EA=", m_cfg.EAName, " v", m_cfg.Version);
      return INIT_SUCCEEDED;
     }

   bool Reload(StrategyConfig &newCfg)
     {
      ApplyDefaults(newCfg);
      string errors[];
      if(!CConfigValidator::Validate(newCfg, errors))
        {
         Print("[CConfigManager] Reload rejected — keeping previous config:");
         CConfigValidator::PrintErrors(errors);
         m_cfgValid = CConfigValidator::IsValid(m_cfg);
         UpdateSnapshot("RELOAD_REJECTED");
         return false;
        }

      m_cfg        = newCfg;
      m_cfgValid   = true;
      m_lastReload = TimeCurrent();
      UpdateSnapshot("RELOAD_OK");

      if(m_bus != NULL)
        {
         PASREvent ev;
         ev.id = EVENT_ID_CONFIG_RELOAD;
         ev.priority = 20;
         ev.timestamp = TimeCurrent();
         ev.comment = "ConfigReload";
         m_bus.DispatchImmediate(ev);
        }

      Print("[CConfigManager] Reload OK and broadcast at ",
            TimeToString(m_lastReload, TIME_DATE | TIME_MINUTES));
      return true;
     }

   StrategyConfig        GetConfig()  const { return m_cfg; }
   ConfigManagerSnapshot GetSnapshot() const { return m_snapshot; }
   bool                  IsValid()    const { return m_cfgValid; }
   datetime              LastReload() const { return m_lastReload; }

   void PrintDiagnostics() const
     {
      PrintFormat("[ConfigDiag] valid=%s status=%s magic=%I64d EA=%s v=%s risk=%.2f%% lot=%.2f maxDD=%.2f daily=%.2f open=%d AI=%s conf=%.2f session=%02d-%02d spread=%.2f patterns=%s dashboard=%s",
                  m_snapshot.valid ? "true" : "false",
                  m_snapshot.lastValidationStatus,
                  m_snapshot.magic,
                  m_snapshot.eaName,
                  m_snapshot.version,
                  m_snapshot.riskPercent,
                  m_snapshot.riskLotSize,
                  m_snapshot.maxDrawdownPct,
                  m_snapshot.maxDailyLossPct,
                  m_snapshot.maxOpenPositions,
                  m_snapshot.aiEnabled ? "true" : "false",
                  m_snapshot.aiMinConfidence,
                  m_snapshot.sessionStartHour,
                  m_snapshot.sessionEndHour,
                  m_snapshot.spreadFilterPips,
                  m_snapshot.patternsEnabled ? "true" : "false",
                  m_snapshot.showDashboard ? "true" : "false");
     }
  };

#endif // __CORE_CONFIG_MANAGER_MQH__
