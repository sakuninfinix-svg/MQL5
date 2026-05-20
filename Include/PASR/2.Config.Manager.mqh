//+------------------------------------------------------------------+
//|                                                2.Config.Manager.mqh |
//|                                       Copyright 2026, Agsicentre |
//|            Core Configuration Manager & Recovery Engine          |
//| v2.01 FIXES:                                                     |
//| - BUG-04 CRITICAL: ArrayResize returns new size, not index.      |
//|   ValidationResult::AddIssue used idx=newSize (OOB write).       |
//|   Fixed: idx = newSize - 1.                                      |
//| - BUG-02 CRITICAL: RecoveryEngine::LoadState pcDist multiplied   |
//|   lastKnownATR * _Point → 1000x too small. Fixed: remove _Point. |
//| - BUG-03 HIGH: ConfigManager::Reload condition                   |
//|   !m_lastKnownConfig.market.atrPeriod>0 never re-runs context    |
//|   validation after first load. Fixed: m_firstLoad flag.          |
//| - BUG-07 MEDIUM: ArrayInt is not a standard MQL5 type.           |
//|   Replaced Compare() return type with int[] and updated          |
//|   GetChanges() accordingly.                                      |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "2.01"
#property strict

#ifndef __CONFIG_MANAGER_MQH__
#define __CONFIG_MANAGER_MQH__

#include "2.Config.Types.mqh"

class ConfigManager
{
private:
   static ConfigManager *m_instance;
   StrategyConfig  m_config;
   StrategyConfig  m_lastKnownConfig;
   InstrumentContext m_instrumentCtx;
   string          m_lastSymbol;
   bool            m_initialized;
   bool            m_firstLoad;   // [BUG-03 FIX] replaces atrPeriod==0 heuristic

   ConfigManager() : m_initialized(false), m_lastSymbol(""), m_firstLoad(true) {}

public:
   static ConfigManager *GetInstance()
   {
      if(m_instance == NULL) m_instance = new ConfigManager();
      return m_instance;
   }

   const StrategyConfig&    GetConfig()            const { return m_config; }
   const InstrumentContext& GetInstrumentContext()  const { return m_instrumentCtx; }
   bool                     IsInitialized()         const { return m_initialized; }

   void CopyTo(StrategyConfig &dest) const { dest = m_config; }

   // [BUG-07 FIX] GetChanges now uses int[] instead of ArrayInt
   void GetChanges(int &changed[])
   {
      m_config.Compare(m_lastKnownConfig, changed);
      if(ArraySize(changed) > 0)
         m_lastKnownConfig = m_config;
   }

   bool HasFieldChanged(ENUM_CONFIG_FIELD_ID fieldId) const
   {
      return m_config.HasChanged(m_lastKnownConfig, fieldId);
   }

   void UpdateLastKnownConfig() { m_lastKnownConfig = m_config; }
   void ResetDiffState()        { m_lastKnownConfig = m_config; }

   ValidationResult Reload()
   {
      LoadMarketParams();
      LoadNewsParams();
      LoadRiskParams();
      LoadSRParams();
      LoadPatternParams();
      LoadRecoveryParams();
      LoadExitParams();
      LoadAIParams();
      LoadSystemParams();

      bool symbolChanged = (_Symbol != m_lastSymbol);
      if(symbolChanged || !m_instrumentCtx.IsValid())
      {
         m_instrumentCtx.Refresh();
         m_lastSymbol = _Symbol;
         PrintFormat("[ConfigManager] Symbol → %s. ATR14=%.5f Spread=%.1f TickSz=%.5f",
                     _Symbol, m_instrumentCtx.atr14,
                     m_instrumentCtx.averageSpread, m_instrumentCtx.tickSize);
      }

      m_initialized = true;

      ValidationResult result;

      // [BUG-03 FIX] Use explicit m_firstLoad flag instead of atrPeriod==0 heuristic.
      // Old code: !m_lastKnownConfig.market.atrPeriod > 0
      //   - After first load atrPeriod is always > 0, so context-validation never ran again.
      // Fix: dedicated bool flag, reset only here.
      bool runContextValidation = symbolChanged || m_firstLoad;

      if(runContextValidation)
      {
         result = m_config.Validate(m_instrumentCtx);
         if(result.HasErrors())
         {
            PrintFormat("[ConfigManager] CRITICAL: Context-aware validation failed for %s", _Symbol);
            result.LogIssues();
            return result;
         }
         if(result.HasWarnings())
         {
            PrintFormat("[ConfigManager] Warnings for %s:", _Symbol);
            result.LogIssues();
         }
      }
      else
      {
         result = m_config.Validate();
      }

      if(m_firstLoad)
      {
         m_lastKnownConfig = m_config;
         m_firstLoad = false;
      }

      return result;
   }

   void LoadMarketParams()
   {
      m_config.market.sessions[0] = InpSessionSun;
      m_config.market.sessions[1] = InpSessionMon;
      m_config.market.sessions[2] = InpSessionTue;
      m_config.market.sessions[3] = InpSessionWed;
      m_config.market.sessions[4] = InpSessionThu;
      m_config.market.sessions[5] = InpSessionFri;
      m_config.market.sessions[6] = InpSessionSat;
      m_config.market.useRegime           = InpUseMarketRegime;
      m_config.market.minTrendStrength     = MarketValidation::NormalizeTrendStrength(InpMinTrendStrength);
      m_config.market.allowSideways       = InpAllowSidewaysTrading;
      m_config.market.regimeLotMultStrong = MarketValidation::NormalizeLotMultiplier(InpRegimeLotMultStrong, 1.0);
      m_config.market.regimeLotMultWeak   = MarketValidation::NormalizeLotMultiplier(InpRegimeLotMultWeak, 1.0);
      m_config.market.regimeLotMultSide   = MarketValidation::NormalizeLotMultiplier(InpRegimeLotMultSide, 1.0);
      m_config.market.regimeLotMultChop   = MarketValidation::NormalizeLotMultiplier(InpRegimeLotMultChop, 1.0);
      m_config.market.atrPeriod           = MarketValidation::NormalizeATRPeriod(InpATRPeriod);
      m_config.market.atrMin              = EnsureNonNegative(InpATRMin, 0.0);
      m_config.market.atrMax              = EnsureNonNegative(InpATRMax, m_config.market.atrMin);
      m_config.market.maxSpread           = EnsureNonNegative(InpMaxSpread, 0.0);
   }

   void LoadNewsParams()
   {
      m_config.news.level  = InpNewsLevel;
      m_config.news.freeze = ValidateIntRange(InpNewsFreezeMinutes, 0, 1440, 30);
      m_config.news.url    = InpNewsWebURL;
      m_config.news.use    = (InpNewsLevel != NEWS_OFF); // explicit, don't rely on Validate()
   }

   void LoadRiskParams()
   {
      m_config.risk.autoLot            = InpUseAutoLot;
      m_config.risk.pct                = RiskValidation::NormalizeRiskPct(InpRiskPct);
      m_config.risk.lot                = RiskValidation::NormalizeLotSize(InpLotSize);
      m_config.risk.maxDailyLoss       = EnsureNonNegative(InpMaxDailyLossPct, 0.0);
      m_config.risk.magic              = InpMagicNum;
      m_config.risk.entryMode          = InpEntryMode;
      m_config.risk.tpslMode           = InpTPSLMode;
      m_config.risk.useMTF             = InpUseMTF;
      m_config.risk.htf                = InpHTF;
      m_config.risk.htfLookback        = ValidateIntRange(InpHTFLookback, 1, 1000, 100);
      m_config.risk.qualityLotMult     = MarketValidation::NormalizeLotMultiplier(InpQualityLotMult, 1.0);
      m_config.risk.maxPositions       = RiskValidation::NormalizeMaxPositions(InpMaxOpenPositions);
      m_config.risk.maxConsecutiveLoss = ValidateIntRange(InpMaxConsecutiveLoss, 0, 100, 0);
      m_config.risk.maxTradeDurationDays = ValidateIntRange(InpMaxTradeDurationDays, 0, 365, 0);
      m_config.risk.entryCooldownBars  = ValidateIntRange(InpEntryCooldownBars, 0, 1000, 0);
      m_config.risk.signalCooldownBars = ValidateIntRange(InpSignalCooldownBars, 0, 1000, 0);
      m_config.risk.lossCooldownBars   = ValidateIntRange(InpLossCooldownBars, 0, 1000, 0);
   }

   void LoadSRParams()
   {
      m_config.sr.mode             = InpSRMode;
      m_config.sr.lookback         = ValidateIntRange(InpSRLookback, 10, 10000, 100);
      m_config.sr.swingLookback    = ValidateIntRange(InpSwingLookback, 5, 500, 20);
      m_config.sr.touchBufferATR   = InpSRTouchBufferATR;
      m_config.sr.minTouchesStrong = InpSRMinTouchesStrong;
      m_config.sr.minRangeATR      = InpMinSRRangeATR;
      m_config.sr.atrBufferMult    = InpATRBufferMult;
      m_config.sr.bufferMultStrong = InpBufferMultStrong;
      m_config.sr.bufferMultWeak   = InpBufferMultWeak;
      m_config.sr.zoneReuseATR     = InpZoneReuseATR;
   }

   void LoadPatternParams()
   {
      m_config.pattern.lookback              = ValidateIntRange(InpSignalLookback, 1, 500, 5);
      m_config.pattern.mtfConfluenceBonus    = InpMTFConfluenceBonus;
      m_config.pattern.strongZoneBonus       = InpStrongZoneBonus;
      m_config.pattern.strongZoneThreshold   = InpStrongZoneThreshold;
      m_config.pattern.maxSignalATR          = InpMaxSignalATR;
      m_config.pattern.momentumThresholdATR  = InpMomentumThresholdATR;
      m_config.pattern.useWeights            = InpUsePatternWeights;
      m_config.pattern.antiBreakoutPct       = PatternValidation::NormalizeRatio(InpAntiBreakoutPct, 0.5);
      m_config.pattern.marubozuMinBodyPct    = PatternValidation::NormalizeRatio(InpMarubozuMinBodyPct, 0.9);
      m_config.pattern.engulfingBodyMult     = InpEngulfingBodyMult;
      m_config.pattern.minDominanceGap       = InpMinDominanceGap;
      m_config.pattern.strongZoneBufferMult  = InpStrongZoneBufferMult;
      m_config.pattern.useAdaptiveZoneBuffer = InpUseAdaptiveZoneBuffer;
      m_config.pattern.sensitivityATR        = InpPatternSensitivityATR;
      m_config.pattern.starMiddleBodyMult    = InpStarMiddleBodyMult;
      m_config.pattern.railroadMinBodyRatio  = InpRailroadMinBodyRatio;
      m_config.pattern.failureCooldownBars   = ValidateIntRange(InpPatternFailureCooldownBars, 0, 1000, 0);
      m_config.pattern.hqThreshold           = InpHighQualityThreshold;
      m_config.pattern.useDynamicCooldown    = InpUseDynamicCooldown;
      m_config.pattern.reducedCooldownBars   = ValidateIntRange(InpReducedCooldownBars, 0, 1000, 0);
      m_config.pattern.baseScore             = PatternValidation::NormalizeScore(InpPatternBaseScore, 0.0);
      m_config.pattern.bonusStrongATR        = PatternValidation::NormalizeScore(InpPatternBonusStrongATRRange, 0.0);
      m_config.pattern.bonusStrongBody       = PatternValidation::NormalizeScore(InpPatternBonusStrongBodyRatio, 0.0);
      m_config.pattern.bonusStrongWick       = PatternValidation::NormalizeScore(InpPatternBonusStrongWickRejection, 0.0);
      m_config.pattern.bonusFollowThrough    = PatternValidation::NormalizeScore(InpPatternBonusFollowThrough, 0.0);
      m_config.pattern.bonusGapConfirm       = PatternValidation::NormalizeScore(InpPatternBonusGapConfirmation, 0.0);
      m_config.pattern.bonusBreakoutConfirm  = PatternValidation::NormalizeScore(InpPatternBonusBreakoutConfirmation, 0.0);
      m_config.pattern.bonusSmall            = PatternValidation::NormalizeScore(InpPatternBonusSmall, 0.0);
      m_config.pattern.atrRangeThreshold     = InpPatternATRRangeThreshold;
      m_config.pattern.bodyRatioThreshold    = InpPatternBodyRatioThreshold;
      m_config.pattern.wickRatioThreshold    = InpPatternWickRatioThreshold;
      m_config.pattern.pinbarWickRatio       = InpPinbarWickToOppositeWickRatio;
      m_config.pattern.insideBarRangeMax     = InpInsideBarChildMotherRangeMax;
      m_config.pattern.starCloseMin          = InpStarClosePositionMin;
      m_config.pattern.threeInsideBodyMin    = InpThreeInsideBodyRatioMin;
      m_config.pattern.railroadAvgBodyMin    = InpRailroadAvgBodyMinATR;
      m_config.pattern.railroadWickMult      = InpRailroadWickRejectionMult;
      m_config.pattern.marubozuMinATRMult    = InpMarubozuMinATRRangeMult;
      m_config.pattern.marubozuStrongATRMin  = InpMarubozuStrongATRRangeMin;
      m_config.pattern.defaultSLMult         = PatternValidation::NormalizeSLMultiplier(InpDefaultSLMult);
      m_config.pattern.pinbarSLMult          = PatternValidation::NormalizeSLMultiplier(InpPinbarSLMult);
      m_config.pattern.insideBarSLMult       = PatternValidation::NormalizeSLMultiplier(InpInsideBarSLMult);
   }

   void LoadRecoveryParams()
   {
      m_config.recovery.use                  = InpUseRecoveryMode;
      m_config.recovery.cooldownBars         = RecoveryValidation::NormalizeCooldownBars(InpRecoveryCooldownBars, 3);
      m_config.recovery.maxAttempts          = RecoveryValidation::NormalizeMaxAttempts(InpMaxRecoveryAttempts);
      m_config.recovery.lotMult              = EnsureNonNegative(InpRecoveryLotMult, 1.0);
      m_config.recovery.scoreThreshold       = InpRecoveryPatternScoreThreshold;
      m_config.recovery.zoneToleranceATR     = InpRecoveryZoneToleranceATR;
      m_config.recovery.fakeoutSensitivity   = RecoveryValidation::NormalizeSensitivity(InpFakeoutDetectionSensitivity);
      m_config.recovery.fakeoutSLAdjATR      = InpFakeoutSLAdjustmentATR;
      m_config.recovery.maxRecoveryPositions = ValidateIntRange(InpMaxRecoveryPositions, 0, 10, 2);
      m_config.recovery.maxExposureMultiplier= EnsurePositive(InpMaxRecoveryExposureMult, 2.0);
      m_config.recovery.recoveryTimeoutBars  = ValidateIntRange(InpRecoveryTimeoutBars, 0, 1000, 20);
      m_config.recovery.hardStopLossPct      = ValidateRange(InpRecoveryHardStopPct, 0.0, 100.0, 3.0);
   }

   void LoadExitParams()
   {
      m_config.exit.useTrailing       = InpUseTrailing;
      m_config.exit.usePartial        = InpUsePartialClose;
      m_config.exit.exitOnOpposite    = InpExitOnOpposite;
      m_config.exit.tpBufferATR       = InpTPBufferATR;
      m_config.exit.slBufferATR       = InpSLBufferATR;
      m_config.exit.minTPDistATR      = InpMinTPDistanceATR;
      m_config.exit.maxTPDistATR      = InpMaxTPDistanceATR;
      m_config.exit.trailingStartATR  = EnsureNonNegative(InpTrailingStartATR, 1.5);
      m_config.exit.trailingBufferATR = InpTrailingBufferATR;
      m_config.exit.trailActivationATR= InpTrailActivationATR;
      m_config.exit.trailStepATR      = InpTrailStepATR;
      m_config.exit.lockProfitATR     = InpLockProfitATR;
      m_config.exit.lockOffsetATR     = InpLockOffsetATR;
      m_config.exit.partialLotPct     = ValidateRange(InpPartialCloseLotPct, 1.0, 100.0, 50.0);
      m_config.exit.partialATR        = InpPartialCloseATR;
   }

   void LoadAIParams()
   {
      m_config.ai.use            = InpUseAI;
      m_config.ai.trainingWindow = ValidateIntRange(InpAITrainingWindowBars, 10, 10000, 200);
      m_config.ai.minConfidence  = InpAIMinConfidence;
      m_config.ai.patternBonus   = InpAIPatternBonus;
   }

   void LoadSystemParams()
   {
      m_config.system.debug          = InpDebugMode;
      m_config.system.safe           = InpSafeMode;
      m_config.system.orderThrottleMs= ValidateIntRange(InpOrderThrottleMs, 0, 10000, 100);
   }
};

ConfigManager *ConfigManager::m_instance = NULL;

const StrategyConfig& GetConfig()
{
   return ConfigManager::GetInstance()->GetConfig();
}

#define CFG GetConfig()

ValidationResult SetCommonDefaults()
{
   return ConfigManager::GetInstance()->Reload();
}

void PrintConfigSummary()
{
   const StrategyConfig &cfg = GetConfig();
   if(!cfg.system.debug) return;
   Print("=== PASR CONFIG ACTIVE ===");
   Print("ATR Period       : ", cfg.market.atrPeriod);
   Print("ATR Range        : ", DoubleToString(cfg.market.atrMin, 1), " - ", DoubleToString(cfg.market.atrMax, 1));
   Print("SR Mode          : ", EnumToString(cfg.sr.mode));
   Print("Risk %           : ", DoubleToString(cfg.risk.pct, 2));
   Print("Magic Number     : ", cfg.risk.magic);
   Print("Signal Lookback  : ", cfg.pattern.lookback);
   Print("Recovery Mode    : ", (cfg.recovery.use ? "Enabled" : "Disabled"));
   if(cfg.recovery.use)
      Print("  Fakeout Sensitivity: ", DoubleToString(cfg.recovery.fakeoutSensitivity, 2));
   Print("Use MTF          : ", (cfg.risk.useMTF ? "true" : "false"));
   Print("Use Trailing     : ", (cfg.exit.useTrailing ? "true" : "false"));
}

//+------------------------------------------------------------------+
//| RecoveryEngine                                                   |
//+------------------------------------------------------------------+
class RecoveryEngine
{
public:
   bool active;
   ulong mainTicket;
   int direction;
   ENUM_TRADE_STATE state;
   datetime entryTime;
   double entryPrice;
   double initialTP;
   double brokerSL;
   double zonePrice;
   double partialTP;
   double lastKnownATR;
   double lot;
   double slMultiplier;
   double peakEquity;
   bool partialClosed;
   bool partialArmedNormal;
   ulong lastActionTick;

   double slHitPrice;
   datetime slHitTime;
   double originalEntry;
   double originalSL;
   double originalTP;
   double originalLot;
   int recoveryAttempts;
   datetime recoveryCooldownExpiry;

   void SaveState() const
   {
      if(mainTicket <= 0) return;
      string p = "PASR_" + IntegerToString(CFG.risk.magic) + "_" + IntegerToString(mainTicket) + "_";
      GlobalVariableSet(p + "v2",  2.0);
      GlobalVariableSet(p + "st",  (double)state);
      GlobalVariableSet(p + "ep",  entryPrice);
      GlobalVariableSet(p + "it",  initialTP);
      GlobalVariableSet(p + "bs",  brokerSL);
      GlobalVariableSet(p + "zp",  zonePrice);
      GlobalVariableSet(p + "dr",  (double)direction);
      GlobalVariableSet(p + "at",  lastKnownATR);
      GlobalVariableSet(p + "pk",  peakEquity);
      GlobalVariableSet(p + "tm",  (double)entryTime);
      GlobalVariableSet(p + "pc",  (double)partialClosed);
      GlobalVariableSet(p + "an",  (double)partialArmedNormal);
      GlobalVariableSet(p + "lo",  lot);
      GlobalVariableSet(p + "sm",  slMultiplier);
      GlobalVariableSet(p + "ak",  (double)lastActionTick);
      GlobalVariableSet(p + "sh",  slHitPrice);
      GlobalVariableSet(p + "sht", (double)slHitTime);
      GlobalVariableSet(p + "oe",  originalEntry);
      GlobalVariableSet(p + "os",  originalSL);
      GlobalVariableSet(p + "ot",  originalTP);
      GlobalVariableSet(p + "ol",  originalLot);
      GlobalVariableSet(p + "ra",  (double)recoveryAttempts);
      GlobalVariableSet(p + "rc",  (double)recoveryCooldownExpiry);
   }

   void LoadState(ulong ticket)
   {
      string p = "PASR_" + IntegerToString(CFG.risk.magic) + "_" + IntegerToString(ticket) + "_";
      if(GlobalVariableCheck(p + "v2"))
      {
         mainTicket          = ticket;
         state               = (ENUM_TRADE_STATE)(int)GlobalVariableGet(p + "st");
         entryPrice          = GlobalVariableGet(p + "ep");
         initialTP           = GlobalVariableGet(p + "it");
         brokerSL            = GlobalVariableGet(p + "bs");
         zonePrice           = GlobalVariableGet(p + "zp");
         direction           = (int)GlobalVariableGet(p + "dr");
         lastKnownATR        = GlobalVariableGet(p + "at");
         peakEquity          = GlobalVariableGet(p + "pk");
         entryTime           = (datetime)GlobalVariableGet(p + "tm");
         partialClosed       = (GlobalVariableGet(p + "pc") > 0.5);
         partialArmedNormal  = (GlobalVariableGet(p + "an") > 0.5);
         lot                 = GlobalVariableGet(p + "lo");
         slMultiplier        = GlobalVariableGet(p + "sm");
         lastActionTick      = (ulong)GlobalVariableGet(p + "ak");
         slHitPrice          = GlobalVariableGet(p + "sh");
         slHitTime           = (datetime)GlobalVariableGet(p + "sht");
         originalEntry       = GlobalVariableGet(p + "oe");
         originalSL          = GlobalVariableGet(p + "os");
         originalTP          = GlobalVariableGet(p + "ot");
         originalLot         = GlobalVariableGet(p + "ol");
         recoveryAttempts    = (int)GlobalVariableGet(p + "ra");
         recoveryCooldownExpiry = (datetime)GlobalVariableGet(p + "rc");

         // [BUG-02 FIX] lastKnownATR is already in price units (e.g. 0.00120 for EURUSD).
         // Old: lastKnownATR * CFG.exit.partialATR * _Point  ← multiplied _Point twice!
         // Fix: remove _Point multiplication.
         double pcDist = lastKnownATR * CFG.exit.partialATR;
         partialTP = NormalizeDouble(
            entryPrice + ((direction == 1 ? 1.0 : -1.0) * pcDist), _Digits);

         active = true;
      }
   }

   void ClearGVs()
   {
      if(mainTicket <= 0) return;
      string p = "PASR_" + IntegerToString(CFG.risk.magic) + "_" + IntegerToString(mainTicket) + "_";
      GlobalVariablesDeleteAll(p);
   }

   void Reset()
   {
      active              = false;
      mainTicket          = 0;
      direction           = 0;
      state               = TRADE_STATE_NONE;
      entryTime           = 0;
      entryPrice          = 0.0;
      zonePrice           = 0.0;
      initialTP           = 0.0;
      brokerSL            = 0.0;
      partialTP           = 0.0;
      slMultiplier        = 1.0;
      lastKnownATR        = 0.0;
      lot                 = 0.0;
      peakEquity          = 0.0;
      partialClosed       = false;
      partialArmedNormal  = false;
      lastActionTick      = 0;
      slHitPrice          = 0.0;
      slHitTime           = 0;
      originalEntry       = 0.0;
      originalSL          = 0.0;
      originalTP          = 0.0;
      originalLot         = 0.0;
      recoveryAttempts    = 0;
      recoveryCooldownExpiry = 0;
   }

   RecoveryEngine() { Reset(); }
};

#endif // __CONFIG_MANAGER_MQH__
