//+------------------------------------------------------------------+
//|                                                       2.Config.mqh |
//|                                       Copyright 2026, Agsicentre |
//|            Core Configuration & System Definitions               |
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

#ifndef __CONFIG_MQH__
#define __CONFIG_MQH__

//+------------------------------------------------------------------+
//| ENUMS: System & Strategy Definitions                             |
//+------------------------------------------------------------------+
enum ENUM_PATTERN_TYPE
{
   PATTERN_NONE,
   PATTERN_PINBAR,
   PATTERN_ENGULFING,
   PATTERN_BOTTOM,
   PATTERN_FAKEY,
   PATTERN_INSIDE_BAR_BREAKOUT,
   PATTERN_MORNING_STAR,
   PATTERN_THREE_INSIDE,
   PATTERN_RAILROAD_TRACKS,
   PATTERN_DARK_CLOUD_PIERCING,
   PATTERN_MARUBOZU
};

enum ENUM_CONFIG_FIELD_ID
{
   FIELD_NONE = 0,
   FIELD_ATR_PERIOD,
   FIELD_ATR_MIN,
   FIELD_ATR_MAX,
   FIELD_MAX_SPREAD,
   FIELD_USE_REGIME,
   FIELD_MIN_TREND_STRENGTH,
   FIELD_ALLOW_SIDEWAYS,
   FIELD_REGIME_LOT_MULT_STRONG,
   FIELD_REGIME_LOT_MULT_WEAK,
   FIELD_REGIME_LOT_MULT_SIDE,
   FIELD_REGIME_LOT_MULT_CHOP,
   FIELD_NEWS_LEVEL,
   FIELD_NEWS_FREEZE,
   FIELD_RISK_PCT,
   FIELD_LOT_SIZE,
   FIELD_AUTO_LOT,
   FIELD_MAX_DAILY_LOSS,
   FIELD_MAGIC_NUM,
   FIELD_ENTRY_MODE,
   FIELD_TPSL_MODE,
   FIELD_USE_MTF,
   FIELD_HTF,
   FIELD_HTF_LOOKBACK,
   FIELD_QUALITY_LOT_MULT,
   FIELD_MAX_POSITIONS,
   FIELD_MAX_CONSECUTIVE_LOSS,
   FIELD_MAX_TRADE_DURATION,
   FIELD_ENTRY_COOLDOWN,
   FIELD_SIGNAL_COOLDOWN,
   FIELD_LOSS_COOLDOWN,
   FIELD_SR_MODE,
   FIELD_SR_LOOKBACK,
   FIELD_SR_SWING_LOOKBACK,
   FIELD_SR_TOUCH_BUFFER,
   FIELD_SR_MIN_TOUCHES,
   FIELD_SR_MIN_RANGE,
   FIELD_SR_ATR_BUFFER,
   FIELD_SR_BUFFER_STRONG,
   FIELD_SR_BUFFER_WEAK,
   FIELD_SR_ZONE_REUSE,
   FIELD_PATTERN_LOOKBACK,
   FIELD_PATTERN_MTF_BONUS,
   FIELD_PATTERN_STRONG_ZONE_BONUS,
   FIELD_PATTERN_STRONG_ZONE_THRESHOLD,
   FIELD_PATTERN_MAX_SIGNAL_ATR,
   FIELD_PATTERN_MOMENTUM_THRESHOLD,
   FIELD_PATTERN_USE_WEIGHTS,
   FIELD_PATTERN_ANTI_BREAKOUT,
   FIELD_PATTERN_MARUBOZU_BODY,
   FIELD_PATTERN_ENGULFING_MULT,
   FIELD_PATTERN_DOMINANCE_GAP,
   FIELD_PATTERN_SENSITIVITY,
   FIELD_PATTERN_DEFAULT_SL_MULT,
   FIELD_PATTERN_PINBAR_SL_MULT,
   FIELD_PATTERN_INSIDEBAR_SL_MULT,
   FIELD_PATTERN_HQ_THRESHOLD,
   FIELD_RECOVERY_USE,
   FIELD_RECOVERY_COOLDOWN,
   FIELD_RECOVERY_MAX_ATTEMPTS,
   FIELD_RECOVERY_LOT_MULT,
   FIELD_RECOVERY_SCORE_THRESHOLD,
   FIELD_RECOVERY_ZONE_TOLERANCE,
   FIELD_RECOVERY_FAKEOUT_SENS,
   FIELD_EXIT_TRAILING,
   FIELD_EXIT_PARTIAL,
   FIELD_EXIT_ON_OPPOSITE,
   FIELD_EXIT_TP_BUFFER,
   FIELD_EXIT_SL_BUFFER,
   FIELD_EXIT_MIN_TP_DIST,
   FIELD_EXIT_MAX_TP_DIST,
   FIELD_EXIT_TRAILING_START,
   FIELD_EXIT_TRAILING_BUFFER,
   FIELD_EXIT_PARTIAL_LOT_PCT,
   FIELD_EXIT_PARTIAL_ATR,
   FIELD_AI_USE,
   FIELD_AI_TRAINING_WINDOW,
   FIELD_AI_MIN_CONFIDENCE,
   FIELD_AI_PATTERN_BONUS,
   FIELD_SYSTEM_DEBUG,
   FIELD_SYSTEM_SAFE,
   FIELD_SYSTEM_THROTTLE
};

enum ENUM_EVENT_ID
{
   EVENT_ID_NONE = 0,
   EVENT_ID_PRICE_UPDATE,
   EVENT_ID_NEW_BAR,
   EVENT_ID_HEARTBEAT,
   EVENT_ID_CONFIG_RELOAD,
   EVENT_ID_EMERGENCY_STOP,
   EVENT_ID_ZONE_UPDATE,
   EVENT_ID_SIGNAL_GENERATED,
   EVENT_ID_ORDER_EXECUTION,
   EVENT_ID_POSITION_UPDATE,
   EVENT_ID_RECOVERY_OPPORTUNITY,
   EVENT_ID_RECOVERY_SIGNAL,
   EVENT_ID_MARKET_GATE,
   EVENT_ID_PAUSE_TOGGLE,
   EVENT_ID_SESSION_CHANGE,
   EVENT_ID_NEWS_ALERT
};

enum ENUM_ENTRY_MODE
{
   MODE_SAFE,
   MODE_AGGRESSIVE
};

enum ENUM_TPSL_MODE
{
   TPSL_SR,
   TPSL_PATTERN
};

enum ENUM_SR_MODE
{
   SR_EXTREME,
   SR_SWING,
   SR_AUTO
};

enum ENUM_NEWS_LEVEL
{
   NEWS_HIGH = 1,
   NEWS_HIGH_MEDIUM = 2,
   NEWS_ALL = 3,
   NEWS_OFF = 0
};

enum ENUM_TRADE_STATE
{
   TRADE_STATE_NONE = 0,
   TRADE_STATE_NORMAL,
   TRADE_STATE_RECOVERY,
   TRADE_STATE_DONE
};

//+------------------------------------------------------------------+
//| STRUCTS: Data Containers                                         |
//+------------------------------------------------------------------+

struct SignalDecision
{
   bool valid;
   ENUM_ORDER_TYPE orderType;
   double signalPrice;
   double zonePrice;
   ENUM_PATTERN_TYPE patternType;
   int bias;
   int signalShift;
   double slMultiplier;
   string reason;
};

struct OrderPlan
{
   ENUM_ORDER_TYPE type;
   double entry;
   double brokerSL;
   double tp;
   double lot;
   double atrUsed;
   string comment;
};

struct PositionScanResult
{
   int normalCount;
   int buyCount;
   int sellCount;
   int pendingCount;
   double totalProfit;
   double floatingPnL;
   double dailyRealized;
   double dailyDrawdown;
};

struct PerformanceStats
{
   int safeTotal;
   int safeWins;
   int aggTotal;
   int aggWins;
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+

// [GROUP] MARKET SESSIONS & NEWS
input string InpSessionSun = "0";
input string InpSessionMon = "0";
input string InpSessionTue = "0";
input string InpSessionWed = "0";
input string InpSessionThu = "0";
input string InpSessionFri = "0";
input string InpSessionSat = "0";
input ENUM_NEWS_LEVEL InpNewsLevel = NEWS_OFF;
input int InpNewsFreezeMinutes = 30;
input string InpNewsWebURL = "https://nfs.faireconomy.media/ff_calendar_thisweek.xml";

// [GROUP] MARKET REGIME & VOLATILITY FILTER
input bool InpUseMarketRegime;
input double InpMinTrendStrength;
input bool InpAllowSidewaysTrading;
input double InpRegimeLotMultStrong;
input double InpRegimeLotMultWeak;
input double InpRegimeLotMultSide;
input double InpRegimeLotMultChop;

// [GROUP] RISK MANAGEMENT
input bool InpUseAutoLot;
input double InpRiskPct;
input double InpLotSize;
input double InpMaxDailyLossPct;
input ulong InpMagicNum;
input ENUM_ENTRY_MODE InpEntryMode;
input ENUM_TPSL_MODE InpTPSLMode;
input bool InpUseMTF;
input ENUM_TIMEFRAMES InpHTF;
input int InpHTFLookback;
input double InpQualityLotMult;

// [GROUP] SUPPORT & RESISTANCE (SR) ENGINE
input ENUM_SR_MODE InpSRMode;
input int InpSRLookback;
input int InpSwingLookback;
input double InpSRTouchBufferATR;
input int InpSRMinTouchesStrong;
input double InpMinSRRangeATR;
input double InpATRBufferMult;
input double InpBufferMultStrong;
input double InpBufferMultWeak;

// [GROUP] SIGNAL DETECTION & PATTERNS
input int InpSignalLookback;
input double InpMTFConfluenceBonus;
input double InpStrongZoneBonus;
input double InpStrongZoneThreshold;
input double InpMaxSignalATR;
input double InpMomentumThresholdATR;
input bool InpUsePatternWeights;
input double InpAntiBreakoutPct;
input double InpMarubozuMinBodyPct;
input double InpEngulfingBodyMult;
input double InpMinDominanceGap;
input double InpStrongZoneBufferMult;
input bool InpUseAdaptiveZoneBuffer;
input double InpPatternSensitivityATR;
input double InpStarMiddleBodyMult;
input double InpRailroadMinBodyRatio;
input double InpZoneReuseATR;

// NEW: Generic Pattern Scoring Parameters
input double InpPatternBaseScore;
input double InpPatternBonusStrongATRRange;
input double InpPatternBonusStrongBodyRatio;
input double InpPatternBonusStrongWickRejection;
input double InpPatternBonusFollowThrough;
input double InpPatternBonusGapConfirmation;
input double InpPatternBonusBreakoutConfirmation;
input double InpPatternBonusSmall;

// NEW: Generic Pattern Thresholds
input double InpPatternATRRangeThreshold;
input double InpPatternBodyRatioThreshold;
input double InpPatternWickRatioThreshold;

// NEW: Pattern-Specific Thresholds
input double InpPinbarWickToOppositeWickRatio;
input double InpInsideBarChildMotherRangeMax;
input double InpStarClosePositionMin;
input double InpThreeInsideBodyRatioMin;
input double InpRailroadAvgBodyMinATR;
input double InpRailroadWickRejectionMult;
input double InpMarubozuMinATRRangeMult;
input double InpMarubozuStrongATRRangeMin;

// [GROUP] RECOVERY MODE & FAKEOUT PROTECTION
input bool InpUseRecoveryMode;
input int InpRecoveryCooldownBars;
input int InpMaxRecoveryAttempts;
input double InpRecoveryLotMult;
input double InpRecoveryPatternScoreThreshold;
input double InpRecoveryZoneToleranceATR;
input double InpFakeoutDetectionSensitivity;
input double InpFakeoutSLAdjustmentATR;

// [GROUP] RECOVERY SAFEGUARDS (BUG-06 FIX: inputs were missing)
input int    InpMaxRecoveryPositions;       // Max Recovery Positions per trade
input double InpMaxRecoveryExposureMult;    // Max Exposure Multiplier (Recovery)
input int    InpRecoveryTimeoutBars;        // Timeout bars untuk recovery mode
input double InpRecoveryHardStopPct;        // Hard Stop Loss % (Recovery)

// [GROUP] PATTERN SPECIFIC VOLATILITY (SL MULTIPLIERS)
input double InpDefaultSLMult;
input double InpPinbarSLMult;
input double InpInsideBarSLMult;

// [GROUP] COOLDOWNS & PROTECTION
input int InpMaxOpenPositions;
input int InpMaxConsecutiveLoss;
input int InpMaxTradeDurationDays;
input int InpEntryCooldownBars;
input int InpSignalCooldownBars;
input int InpLossCooldownBars;
input int InpPatternFailureCooldownBars;
input double InpHighQualityThreshold;
input bool InpUseDynamicCooldown;
input int InpReducedCooldownBars;

// [GROUP] EXECUTION, TRAILING & RECOVERY
input double InpMaxSpread;
input int InpOrderThrottleMs;
input bool InpUseTrailing;
input bool InpUsePartialClose;
input bool InpExitOnOpposite;
input double InpTPBufferATR;
input double InpSLBufferATR;
input double InpMinTPDistanceATR;
input double InpMaxTPDistanceATR;
input double InpTrailingStartATR;
input double InpTrailingBufferATR;
input double InpTrailActivationATR;
input double InpTrailStepATR;
input double InpLockProfitATR;
input double InpLockOffsetATR;
input double InpPartialCloseLotPct;
input double InpPartialCloseATR;

// [GROUP] AI / MACHINE LEARNING
input bool InpUseAI;
input int InpAITrainingWindowBars;
input double InpAIMinConfidence;
input double InpAIPatternBonus;

// [GROUP] SYSTEM & DEBUG
input bool InpDebugMode;
input bool InpSafeMode;
input int InpATRPeriod;
input double InpATRMin;
input double InpATRMax;

//+------------------------------------------------------------------+
//| VALIDATION HELPERS                                               |
//+------------------------------------------------------------------+

template<typename T>
T Clamp(T value, T minVal, T maxVal)
{
   if(value < minVal) return minVal;
   if(value > maxVal) return maxVal;
   return value;
}

double EnsurePositive(double value, double defaultValue)
{
   return (value > 0) ? value : defaultValue;
}

double EnsureNonNegative(double value, double defaultValue)
{
   return (value >= 0) ? value : defaultValue;
}

double ValidateRange(double value, double minVal, double maxVal, double defaultValue)
{
   if(value < minVal || value > maxVal) return defaultValue;
   return value;
}

int ValidateIntRange(int value, int minVal, int maxVal, int defaultValue)
{
   if(value < minVal || value > maxVal) return defaultValue;
   return value;
}

void LogWarning(const string paramName, const string message)
{
   Print("WARNING: ", paramName, " ", message);
}

//+------------------------------------------------------------------+
//| ValidationResult                                                 |
//+------------------------------------------------------------------+

enum ENUM_VALIDATION_SEVERITY
{
   VALIDATION_INFO,
   VALIDATION_WARNING,
   VALIDATION_ERROR,
   VALIDATION_CRITICAL
};

struct ValidationIssue
{
   string field;
   string message;
   ENUM_VALIDATION_SEVERITY severity;
   string defaultValue;

   ValidationIssue() : severity(VALIDATION_INFO) {}

   ValidationIssue(const string f, const string msg,
                   ENUM_VALIDATION_SEVERITY sev = VALIDATION_WARNING,
                   const string defVal = "")
   {
      field = f;
      message = msg;
      severity = sev;
      defaultValue = defVal;
   }

   string ToString() const
   {
      string severityStr = "";
      switch(severity)
      {
         case VALIDATION_INFO:     severityStr = "INFO";     break;
         case VALIDATION_WARNING:  severityStr = "WARNING";  break;
         case VALIDATION_ERROR:    severityStr = "ERROR";    break;
         case VALIDATION_CRITICAL: severityStr = "CRITICAL"; break;
      }
      return StringFormat("[%s] %s: %s%s", severityStr, field, message,
                         (defaultValue != "" ? " (Default: " + defaultValue + ")" : ""));
   }
};

struct ValidationResult
{
   bool isValid;
   ValidationIssue issues[];
   int issueCount;

   ValidationResult() : isValid(true), issueCount(0) {}

   // [BUG-04 FIX] ArrayResize returns new size, NOT the index of the new element.
   // Old code: int idx = ArrayResize(...); issues[idx] = ...  → out-of-bounds write
   // Fix: idx = newSize - 1
   void AddIssue(const string field, const string message,
                 ENUM_VALIDATION_SEVERITY severity = VALIDATION_WARNING,
                 const string defaultValue = "")
   {
      int newSize = ArraySize(issues) + 1;
      ArrayResize(issues, newSize);
      int idx = newSize - 1;   // correct last-element index
      issues[idx] = ValidationIssue(field, message, severity, defaultValue);
      issueCount++;

      if(severity >= VALIDATION_ERROR)
         isValid = false;
   }

   void LogIssues() const
   {
      if(issueCount == 0) return;
      Print("=== VALIDATION REPORT ===");
      for(int i = 0; i < issueCount; i++)
         Print(issues[i].ToString());
      Print("=========================");
   }

   void Clear()
   {
      ArrayFree(issues);
      issueCount = 0;
      isValid = true;
   }

   bool HasErrors() const
   {
      for(int i = 0; i < issueCount; i++)
         if(issues[i].severity >= VALIDATION_ERROR) return true;
      return false;
   }

   bool HasWarnings() const
   {
      for(int i = 0; i < issueCount; i++)
         if(issues[i].severity == VALIDATION_WARNING) return true;
      return false;
   }
};

//+------------------------------------------------------------------+
//| INSTRUMENT CONTEXT                                               |
//+------------------------------------------------------------------+
struct InstrumentContext
{
   string symbol;
   double pointValue;
   int    digits;
   double averageSpread;
   double atr14;
   double tickSize;
   double tickValue;
   double contractSize;

   InstrumentContext(const string sym = "")
   {
      string targetSymbol = (sym == "" || sym == NULL) ? _Symbol : sym;
      symbol       = targetSymbol;
      digits       = (int)SymbolInfoInteger(targetSymbol, SYMBOL_DIGITS);
      pointValue   = SymbolInfoDouble(targetSymbol, SYMBOL_POINT);
      tickSize     = SymbolInfoDouble(targetSymbol, SYMBOL_TRADE_TICK_SIZE);
      tickValue    = SymbolInfoDouble(targetSymbol, SYMBOL_TRADE_TICK_VALUE);
      contractSize = SymbolInfoDouble(targetSymbol, SYMBOL_TRADE_CONTRACT_SIZE);

      long spreadPoints = SymbolInfoInteger(targetSymbol, SYMBOL_SPREAD);
      averageSpread = (double)spreadPoints * pointValue;

      atr14 = CalculateATR14(targetSymbol);
   }

   double CalculateATR14(const string sym) const
   {
      int handle = iATR(sym, PERIOD_CURRENT, 14);
      if(handle == INVALID_HANDLE) return 0.0;
      double buf[1];
      ArraySetAsSeries(buf, true);
      double result = 0.0;
      if(CopyBuffer(handle, 0, 0, 1, buf) > 0)
         result = buf[0];
      IndicatorRelease(handle);
      return result;
   }

   void Refresh() { *this = InstrumentContext(symbol); }

   bool IsValid() const { return (symbol != "" && digits > 0 && pointValue > 0); }
};

//+------------------------------------------------------------------+
//| DOMAIN-SPECIFIC VALIDATION RULES                                 |
//+------------------------------------------------------------------+

struct MarketValidation
{
   static bool ValidateATRPeriod(int period) { return period >= 1 && period <= 1000; }
   static bool ValidateTrendStrength(double strength) { return strength >= 0.0 && strength <= 1.0; }
   static bool ValidateLotMultiplier(double mult) { return mult >= 0.1 && mult <= 10.0; }

   static int NormalizeATRPeriod(int period)
   {
      if(!ValidateATRPeriod(period)) { LogWarning("ATRPeriod", "must be 1-1000. Using default 14."); return 14; }
      return period;
   }

   static double NormalizeTrendStrength(double strength)
   {
      double normalized = Clamp(strength, 0.0, 1.0);
      if(normalized != strength) LogWarning("TrendStrength", "must be 0.0-1.0. Clamped.");
      return normalized;
   }

   static double NormalizeLotMultiplier(double mult, double defaultVal = 1.0)
   {
      if(!ValidateLotMultiplier(mult)) { LogWarning("LotMultiplier", "must be 0.1-10.0. Using default."); return defaultVal; }
      return mult;
   }
};

struct RiskValidation
{
   static bool ValidateRiskPct(double pct) { return pct >= 0.01 && pct <= 100.0; }
   static bool ValidateLotSize(double lot) { return lot >= 0.01; }
   static bool ValidateMaxPositions(int count) { return count >= 0 && count <= 100; }

   static double NormalizeRiskPct(double pct)
   {
      if(!ValidateRiskPct(pct)) { LogWarning("RiskPct", "must be 0.01-100. Using default 1.0."); return 1.0; }
      return pct;
   }

   static double NormalizeLotSize(double lot)
   {
      if(!ValidateLotSize(lot)) { LogWarning("LotSize", "must be >= 0.01. Using default 0.01."); return 0.01; }
      return lot;
   }

   static int NormalizeMaxPositions(int count)
   {
      if(!ValidateMaxPositions(count)) { LogWarning("MaxPositions", "must be 0-100. Using default 0."); return 0; }
      return count;
   }
};

struct PatternValidation
{
   static bool ValidateScore(double score) { return score >= 0.0; }
   static bool ValidateRatio(double ratio) { return ratio >= 0.0 && ratio <= 1.0; }
   static bool ValidateSLMultiplier(double mult) { return mult >= 0.5 && mult <= 5.0; }

   static double NormalizeScore(double score, double defaultVal = 0.0)
   {
      if(!ValidateScore(score)) { LogWarning("PatternScore", "must be >= 0. Using default."); return defaultVal; }
      return score;
   }

   static double NormalizeRatio(double ratio, double defaultVal = 0.5)
   {
      if(!ValidateRatio(ratio)) { LogWarning("PatternRatio", "must be 0.0-1.0. Using default."); return defaultVal; }
      return ratio;
   }

   static double NormalizeSLMultiplier(double mult)
   {
      if(!ValidateSLMultiplier(mult)) { LogWarning("SLMultiplier", "must be 0.5-5.0. Using default 1.0."); return 1.0; }
      return mult;
   }
};

struct RecoveryValidation
{
   static bool ValidateCooldownBars(int bars) { return bars >= 0 && bars <= 1000; }
   static bool ValidateMaxAttempts(int attempts) { return attempts >= 0 && attempts <= 10; }
   static bool ValidateSensitivity(double sens) { return sens >= 0.1 && sens <= 1.0; }

   static int NormalizeCooldownBars(int bars, int defaultVal = 3)
   {
      if(!ValidateCooldownBars(bars)) { LogWarning("RecoveryCooldown", "must be 0-1000. Using default."); return defaultVal; }
      return bars;
   }

   static int NormalizeMaxAttempts(int attempts)
   {
      if(!ValidateMaxAttempts(attempts)) { LogWarning("MaxRecoveryAttempts", "must be 0-10. Using default 2."); return 2; }
      return attempts;
   }

   static double NormalizeSensitivity(double sens)
   {
      if(!ValidateSensitivity(sens)) { LogWarning("FakeoutSensitivity", "must be 0.1-1.0. Using default 0.3."); return 0.3; }
      return sens;
   }
};

//+------------------------------------------------------------------+
//| STRATEGY CONFIG                                                  |
//+------------------------------------------------------------------+
struct StrategyConfig
{
   struct Market {
      int atrPeriod;
      double atrMin;
      double atrMax;
      double maxSpread;
      string sessions[7];
      bool useRegime;
      double minTrendStrength;
      bool allowSideways;
      double regimeLotMultStrong;
      double regimeLotMultWeak;
      double regimeLotMultSide;
      double regimeLotMultChop;

      void Validate()
      {
         atrPeriod           = MarketValidation::NormalizeATRPeriod(atrPeriod);
         minTrendStrength    = MarketValidation::NormalizeTrendStrength(minTrendStrength);
         regimeLotMultStrong = MarketValidation::NormalizeLotMultiplier(regimeLotMultStrong, 1.0);
         regimeLotMultWeak   = MarketValidation::NormalizeLotMultiplier(regimeLotMultWeak, 1.0);
         regimeLotMultSide   = MarketValidation::NormalizeLotMultiplier(regimeLotMultSide, 1.0);
         regimeLotMultChop   = MarketValidation::NormalizeLotMultiplier(regimeLotMultChop, 1.0);
         if(atrMax < atrMin) { LogWarning("ATRMax", "must be >= ATRMin. Adjusted."); atrMax = atrMin; }
      }
   } market;

   struct News {
      bool use;
      ENUM_NEWS_LEVEL level;
      int freeze;
      string url;

      void Validate()
      {
         freeze = ValidateIntRange(freeze, 0, 1440, 30);
         use = (level != NEWS_OFF);
      }
   } news;

   struct Risk {
      bool autoLot;
      double pct;
      double lot;
      double maxDailyLoss;
      ulong magic;
      ENUM_ENTRY_MODE entryMode;
      ENUM_TPSL_MODE tpslMode;
      bool useMTF;
      ENUM_TIMEFRAMES htf;
      int htfLookback;
      double qualityLotMult;
      int maxPositions;
      int maxConsecutiveLoss;
      int maxTradeDurationDays;
      int entryCooldownBars;
      int signalCooldownBars;
      int lossCooldownBars;

      void Validate()
      {
         pct                  = RiskValidation::NormalizeRiskPct(pct);
         lot                  = RiskValidation::NormalizeLotSize(lot);
         maxPositions         = RiskValidation::NormalizeMaxPositions(maxPositions);
         maxConsecutiveLoss   = ValidateIntRange(maxConsecutiveLoss, 0, 100, 0);
         maxTradeDurationDays = ValidateIntRange(maxTradeDurationDays, 0, 365, 0);
         entryCooldownBars    = ValidateIntRange(entryCooldownBars, 0, 1000, 0);
         signalCooldownBars   = ValidateIntRange(signalCooldownBars, 0, 1000, 0);
         lossCooldownBars     = ValidateIntRange(lossCooldownBars, 0, 1000, 0);
         htfLookback          = ValidateIntRange(htfLookback, 1, 1000, 100);
         qualityLotMult       = MarketValidation::NormalizeLotMultiplier(qualityLotMult, 1.0);
      }
   } risk;

   struct SR {
      ENUM_SR_MODE mode;
      int lookback;
      int swingLookback;
      double touchBufferATR;
      int minTouchesStrong;
      double minRangeATR;
      double atrBufferMult;
      double bufferMultStrong;
      double bufferMultWeak;
      double zoneReuseATR;

      void Validate()
      {
         lookback      = ValidateIntRange(lookback, 10, 10000, 100);
         swingLookback = ValidateIntRange(swingLookback, 5, 500, 20);
      }
   } sr;

   struct Pattern {
      int lookback;
      double mtfConfluenceBonus;
      double strongZoneBonus;
      double strongZoneThreshold;
      double maxSignalATR;
      double momentumThresholdATR;
      bool useWeights;
      double antiBreakoutPct;
      double marubozuMinBodyPct;
      double engulfingBodyMult;
      double minDominanceGap;
      double strongZoneBufferMult;
      bool useAdaptiveZoneBuffer;
      double sensitivityATR;
      double starMiddleBodyMult;
      double railroadMinBodyRatio;
      int failureCooldownBars;
      double hqThreshold;
      bool useDynamicCooldown;
      int reducedCooldownBars;
      double baseScore;
      double bonusStrongATR;
      double bonusStrongBody;
      double bonusStrongWick;
      double bonusFollowThrough;
      double bonusGapConfirm;
      double bonusBreakoutConfirm;
      double bonusSmall;
      double atrRangeThreshold;
      double bodyRatioThreshold;
      double wickRatioThreshold;
      double pinbarWickRatio;
      double insideBarRangeMax;
      double starCloseMin;
      double threeInsideBodyMin;
      double railroadAvgBodyMin;
      double railroadWickMult;
      double marubozuMinATRMult;
      double marubozuStrongATRMin;
      double defaultSLMult;
      double pinbarSLMult;
      double insideBarSLMult;

      void Validate()
      {
         lookback            = ValidateIntRange(lookback, 1, 500, 5);
         failureCooldownBars = ValidateIntRange(failureCooldownBars, 0, 1000, 0);
         reducedCooldownBars = ValidateIntRange(reducedCooldownBars, 0, 1000, 0);
         baseScore           = PatternValidation::NormalizeScore(baseScore, 0.0);
         bonusStrongATR      = PatternValidation::NormalizeScore(bonusStrongATR, 0.0);
         bonusStrongBody     = PatternValidation::NormalizeScore(bonusStrongBody, 0.0);
         bonusStrongWick     = PatternValidation::NormalizeScore(bonusStrongWick, 0.0);
         marubozuMinBodyPct  = PatternValidation::NormalizeRatio(marubozuMinBodyPct, 0.9);
         antiBreakoutPct     = PatternValidation::NormalizeRatio(antiBreakoutPct, 0.5);
         defaultSLMult       = PatternValidation::NormalizeSLMultiplier(defaultSLMult);
         pinbarSLMult        = PatternValidation::NormalizeSLMultiplier(pinbarSLMult);
         insideBarSLMult     = PatternValidation::NormalizeSLMultiplier(insideBarSLMult);
      }
   } pattern;

   struct Recovery {
      bool use;
      int cooldownBars;
      int maxAttempts;
      double lotMult;
      double scoreThreshold;
      double zoneToleranceATR;
      double fakeoutSensitivity;
      double fakeoutSLAdjATR;
      int maxRecoveryPositions;
      double maxExposureMultiplier;
      int recoveryTimeoutBars;
      double hardStopLossPct;

      void Validate()
      {
         cooldownBars            = RecoveryValidation::NormalizeCooldownBars(cooldownBars, 3);
         maxAttempts             = RecoveryValidation::NormalizeMaxAttempts(maxAttempts);
         fakeoutSensitivity      = RecoveryValidation::NormalizeSensitivity(fakeoutSensitivity);
         maxRecoveryPositions    = ValidateIntRange(maxRecoveryPositions, 0, 10, 2);
         recoveryTimeoutBars     = ValidateIntRange(recoveryTimeoutBars, 0, 1000, 20);
         hardStopLossPct         = ValidateRange(hardStopLossPct, 0.0, 100.0, 3.0);
         lotMult                 = EnsureNonNegative(lotMult, 1.0);
         maxExposureMultiplier   = EnsurePositive(maxExposureMultiplier, 2.0);
      }
   } recovery;

   struct Exit {
      bool useTrailing;
      bool usePartial;
      bool exitOnOpposite;
      double tpBufferATR;
      double slBufferATR;
      double minTPDistATR;
      double maxTPDistATR;
      double trailingStartATR;
      double trailingBufferATR;
      double trailActivationATR;
      double trailStepATR;
      double lockProfitATR;
      double lockOffsetATR;
      double partialLotPct;
      double partialATR;

      void Validate()
      {
         partialLotPct    = ValidateRange(partialLotPct, 1.0, 100.0, 50.0);
         trailingStartATR = EnsureNonNegative(trailingStartATR, 1.5);
         if(maxTPDistATR < minTPDistATR)
         { LogWarning("MaxTPDistance", "must be >= MinTPDistance. Adjusted."); maxTPDistATR = minTPDistATR; }
      }
   } exit;

   struct AI {
      bool use;
      int trainingWindow;
      double minConfidence;
      double patternBonus;

      void Validate()
      {
         trainingWindow = ValidateIntRange(trainingWindow, 10, 10000, 200);
         if(use && trainingWindow < 100)
         { LogWarning("AITrainingWindow", "too small for AI. Using default 200."); trainingWindow = 200; }
      }
   } ai;

   struct System {
      bool debug;
      bool safe;
      int orderThrottleMs;

      void Validate() { orderThrottleMs = ValidateIntRange(orderThrottleMs, 0, 10000, 100); }
   } system;

   ValidationResult Validate()
   {
      ValidationResult result;

      if(market.atrMax < market.atrMin)
      {
         result.AddIssue("market.atrMax", "must be >= atrMin. Auto-adjusted to atrMin.",
                         VALIDATION_WARNING, DoubleToString(market.atrMin, _Digits));
         market.atrMax = market.atrMin;
      }

      if(risk.autoLot && risk.pct > 10.0)
         result.AddIssue("risk.pct", "AutoLot risk > 10% is very high. Consider reducing.",
                         VALIDATION_WARNING, "1.0-5.0 recommended");

      if(recovery.use && recovery.maxAttempts > 5)
         result.AddIssue("recovery.maxAttempts", "High recovery attempts may lead to overtrading.",
                         VALIDATION_WARNING, "2-3 recommended");

      if(recovery.use && recovery.lotMult > 2.0)
         result.AddIssue("recovery.lotMult", "High recovery lot multiplier increases risk significantly.",
                         VALIDATION_WARNING, "1.0-1.5 recommended");

      if(exit.maxTPDistATR < exit.minTPDistATR)
      {
         result.AddIssue("exit.maxTPDistATR", "must be >= minTPDistATR. Auto-adjusted.",
                         VALIDATION_ERROR, DoubleToString(exit.minTPDistATR, 2));
         exit.maxTPDistATR = exit.minTPDistATR;
      }

      if(ai.use && ai.trainingWindow < 100)
      {
         result.AddIssue("ai.trainingWindow", "Training window too small for meaningful AI learning.",
                         VALIDATION_ERROR, "200+ recommended");
         ai.trainingWindow = 200;
      }

      market.Validate();
      news.Validate();
      risk.Validate();
      sr.Validate();
      pattern.Validate();
      recovery.Validate();
      exit.Validate();
      ai.Validate();
      system.Validate();

      return result;
   }

   ValidationResult Validate(const InstrumentContext &ctx)
   {
      ValidationResult result = Validate();

      if(!ctx.IsValid())
      {
         result.AddIssue("InstrumentContext",
                         "Invalid instrument context. Cannot perform context-aware validation.",
                         VALIDATION_ERROR, ctx.symbol);
         return result;
      }

      double minSLPoints      = exit.slBufferATR * GetATRValue();
      double minRecommendedSL = ctx.averageSpread * 1.5;
      if(minSLPoints < minRecommendedSL && minSLPoints > 0)
         result.AddIssue("exit.slBufferATR",
                         StringFormat("SL Distance (%.1f pts) too small for spread %s (%.1f pts). Min: %.1f pts.",
                                      minSLPoints, ctx.symbol, ctx.averageSpread, minRecommendedSL),
                         VALIDATION_ERROR, StringFormat("%.2f ATR", minRecommendedSL / ctx.atr14));

      if(exit.useTrailing && exit.trailingBufferATR > 0)
      {
         double trailingPoints = exit.trailingBufferATR * GetATRValue();
         if(trailingPoints < ctx.tickSize * 2)
            result.AddIssue("exit.trailingBufferATR",
                            StringFormat("Trailing buffer (%.1f pts) too small for %s (tick %.1f pts). Min: %.1f pts.",
                                         trailingPoints, ctx.symbol, ctx.tickSize, ctx.tickSize * 2),
                            VALIDATION_WARNING, StringFormat("%.2f ATR", (ctx.tickSize * 2) / GetATRValue()));
      }

      if(market.maxSpread > 0 && market.maxSpread < ctx.averageSpread * 1.2)
         result.AddIssue("market.maxSpread",
                         StringFormat("Max Spread (%.1f pts) too close to avg spread %s (%.1f pts). Min recommended: %.1f pts.",
                                      market.maxSpread, ctx.symbol, ctx.averageSpread, ctx.averageSpread * 2.0),
                         VALIDATION_WARNING, StringFormat("%.1f pts", ctx.averageSpread * 2.0));

      return result;
   }

   double GetATRValue() const
   {
      int handle = iATR(_Symbol, PERIOD_CURRENT, market.atrPeriod);
      if(handle == INVALID_HANDLE) return 0.0;
      double buf[1];
      ArraySetAsSeries(buf, true);
      double result = 0.0;
      if(CopyBuffer(handle, 0, 0, 1, buf) > 0) result = buf[0];
      IndicatorRelease(handle);
      return result;
   }

   // [BUG-07 FIX] Replace non-standard ArrayInt with standard int[]
   // Caller passes changed[] by reference; function fills it.
   void Compare(const StrategyConfig &other, int &changed[]) const
   {
      ArrayResize(changed, 0);

      #define ADD_IF_CHANGED(expr, fid) if(expr) { int sz=ArraySize(changed); ArrayResize(changed,sz+1); changed[sz]=(int)(fid); }

      ADD_IF_CHANGED(market.atrPeriod            != other.market.atrPeriod,            FIELD_ATR_PERIOD)
      ADD_IF_CHANGED(market.atrMin               != other.market.atrMin,               FIELD_ATR_MIN)
      ADD_IF_CHANGED(market.atrMax               != other.market.atrMax,               FIELD_ATR_MAX)
      ADD_IF_CHANGED(market.maxSpread            != other.market.maxSpread,            FIELD_MAX_SPREAD)
      ADD_IF_CHANGED(market.useRegime            != other.market.useRegime,            FIELD_USE_REGIME)
      ADD_IF_CHANGED(market.minTrendStrength      != other.market.minTrendStrength,      FIELD_MIN_TREND_STRENGTH)
      ADD_IF_CHANGED(market.allowSideways        != other.market.allowSideways,        FIELD_ALLOW_SIDEWAYS)
      ADD_IF_CHANGED(market.regimeLotMultStrong  != other.market.regimeLotMultStrong,  FIELD_REGIME_LOT_MULT_STRONG)
      ADD_IF_CHANGED(market.regimeLotMultWeak    != other.market.regimeLotMultWeak,    FIELD_REGIME_LOT_MULT_WEAK)
      ADD_IF_CHANGED(market.regimeLotMultSide    != other.market.regimeLotMultSide,    FIELD_REGIME_LOT_MULT_SIDE)
      ADD_IF_CHANGED(market.regimeLotMultChop    != other.market.regimeLotMultChop,    FIELD_REGIME_LOT_MULT_CHOP)
      ADD_IF_CHANGED(news.level                  != other.news.level,                  FIELD_NEWS_LEVEL)
      ADD_IF_CHANGED(news.freeze                 != other.news.freeze,                 FIELD_NEWS_FREEZE)
      ADD_IF_CHANGED(risk.autoLot                != other.risk.autoLot,                FIELD_AUTO_LOT)
      ADD_IF_CHANGED(risk.pct                    != other.risk.pct,                    FIELD_RISK_PCT)
      ADD_IF_CHANGED(risk.lot                    != other.risk.lot,                    FIELD_LOT_SIZE)
      ADD_IF_CHANGED(risk.maxDailyLoss           != other.risk.maxDailyLoss,           FIELD_MAX_DAILY_LOSS)
      ADD_IF_CHANGED(risk.magic                  != other.risk.magic,                  FIELD_MAGIC_NUM)
      ADD_IF_CHANGED(risk.entryMode              != other.risk.entryMode,              FIELD_ENTRY_MODE)
      ADD_IF_CHANGED(risk.tpslMode               != other.risk.tpslMode,               FIELD_TPSL_MODE)
      ADD_IF_CHANGED(risk.useMTF                 != other.risk.useMTF,                 FIELD_USE_MTF)
      ADD_IF_CHANGED(risk.htf                    != other.risk.htf,                    FIELD_HTF)
      ADD_IF_CHANGED(risk.htfLookback            != other.risk.htfLookback,            FIELD_HTF_LOOKBACK)
      ADD_IF_CHANGED(risk.qualityLotMult         != other.risk.qualityLotMult,         FIELD_QUALITY_LOT_MULT)
      ADD_IF_CHANGED(risk.maxPositions           != other.risk.maxPositions,           FIELD_MAX_POSITIONS)
      ADD_IF_CHANGED(risk.maxConsecutiveLoss     != other.risk.maxConsecutiveLoss,     FIELD_MAX_CONSECUTIVE_LOSS)
      ADD_IF_CHANGED(risk.maxTradeDurationDays   != other.risk.maxTradeDurationDays,   FIELD_MAX_TRADE_DURATION)
      ADD_IF_CHANGED(risk.entryCooldownBars      != other.risk.entryCooldownBars,      FIELD_ENTRY_COOLDOWN)
      ADD_IF_CHANGED(risk.signalCooldownBars     != other.risk.signalCooldownBars,     FIELD_SIGNAL_COOLDOWN)
      ADD_IF_CHANGED(risk.lossCooldownBars       != other.risk.lossCooldownBars,       FIELD_LOSS_COOLDOWN)
      ADD_IF_CHANGED(sr.mode                     != other.sr.mode,                     FIELD_SR_MODE)
      ADD_IF_CHANGED(sr.lookback                 != other.sr.lookback,                 FIELD_SR_LOOKBACK)
      ADD_IF_CHANGED(sr.swingLookback            != other.sr.swingLookback,            FIELD_SR_SWING_LOOKBACK)
      ADD_IF_CHANGED(sr.touchBufferATR           != other.sr.touchBufferATR,           FIELD_SR_TOUCH_BUFFER)
      ADD_IF_CHANGED(sr.minTouchesStrong         != other.sr.minTouchesStrong,         FIELD_SR_MIN_TOUCHES)
      ADD_IF_CHANGED(sr.minRangeATR              != other.sr.minRangeATR,              FIELD_SR_MIN_RANGE)
      ADD_IF_CHANGED(sr.atrBufferMult            != other.sr.atrBufferMult,            FIELD_SR_ATR_BUFFER)
      ADD_IF_CHANGED(sr.bufferMultStrong         != other.sr.bufferMultStrong,         FIELD_SR_BUFFER_STRONG)
      ADD_IF_CHANGED(sr.bufferMultWeak           != other.sr.bufferMultWeak,           FIELD_SR_BUFFER_WEAK)
      ADD_IF_CHANGED(sr.zoneReuseATR             != other.sr.zoneReuseATR,             FIELD_SR_ZONE_REUSE)
      ADD_IF_CHANGED(pattern.lookback            != other.pattern.lookback,            FIELD_PATTERN_LOOKBACK)
      ADD_IF_CHANGED(pattern.mtfConfluenceBonus  != other.pattern.mtfConfluenceBonus,  FIELD_PATTERN_MTF_BONUS)
      ADD_IF_CHANGED(pattern.strongZoneBonus     != other.pattern.strongZoneBonus,     FIELD_PATTERN_STRONG_ZONE_BONUS)
      ADD_IF_CHANGED(pattern.strongZoneThreshold != other.pattern.strongZoneThreshold, FIELD_PATTERN_STRONG_ZONE_THRESHOLD)
      ADD_IF_CHANGED(pattern.maxSignalATR        != other.pattern.maxSignalATR,        FIELD_PATTERN_MAX_SIGNAL_ATR)
      ADD_IF_CHANGED(pattern.momentumThresholdATR!= other.pattern.momentumThresholdATR,FIELD_PATTERN_MOMENTUM_THRESHOLD)
      ADD_IF_CHANGED(pattern.useWeights          != other.pattern.useWeights,          FIELD_PATTERN_USE_WEIGHTS)
      ADD_IF_CHANGED(pattern.antiBreakoutPct     != other.pattern.antiBreakoutPct,     FIELD_PATTERN_ANTI_BREAKOUT)
      ADD_IF_CHANGED(pattern.marubozuMinBodyPct  != other.pattern.marubozuMinBodyPct,  FIELD_PATTERN_MARUBOZU_BODY)
      ADD_IF_CHANGED(pattern.engulfingBodyMult   != other.pattern.engulfingBodyMult,   FIELD_PATTERN_ENGULFING_MULT)
      ADD_IF_CHANGED(pattern.minDominanceGap     != other.pattern.minDominanceGap,     FIELD_PATTERN_DOMINANCE_GAP)
      ADD_IF_CHANGED(pattern.sensitivityATR      != other.pattern.sensitivityATR,      FIELD_PATTERN_SENSITIVITY)
      ADD_IF_CHANGED(pattern.defaultSLMult       != other.pattern.defaultSLMult,       FIELD_PATTERN_DEFAULT_SL_MULT)
      ADD_IF_CHANGED(pattern.pinbarSLMult        != other.pattern.pinbarSLMult,        FIELD_PATTERN_PINBAR_SL_MULT)
      ADD_IF_CHANGED(pattern.insideBarSLMult     != other.pattern.insideBarSLMult,     FIELD_PATTERN_INSIDEBAR_SL_MULT)
      ADD_IF_CHANGED(pattern.hqThreshold         != other.pattern.hqThreshold,         FIELD_PATTERN_HQ_THRESHOLD)
      ADD_IF_CHANGED(recovery.use                != other.recovery.use,                FIELD_RECOVERY_USE)
      ADD_IF_CHANGED(recovery.cooldownBars       != other.recovery.cooldownBars,       FIELD_RECOVERY_COOLDOWN)
      ADD_IF_CHANGED(recovery.maxAttempts        != other.recovery.maxAttempts,        FIELD_RECOVERY_MAX_ATTEMPTS)
      ADD_IF_CHANGED(recovery.lotMult            != other.recovery.lotMult,            FIELD_RECOVERY_LOT_MULT)
      ADD_IF_CHANGED(recovery.scoreThreshold     != other.recovery.scoreThreshold,     FIELD_RECOVERY_SCORE_THRESHOLD)
      ADD_IF_CHANGED(recovery.zoneToleranceATR   != other.recovery.zoneToleranceATR,   FIELD_RECOVERY_ZONE_TOLERANCE)
      ADD_IF_CHANGED(recovery.fakeoutSensitivity != other.recovery.fakeoutSensitivity, FIELD_RECOVERY_FAKEOUT_SENS)
      ADD_IF_CHANGED(exit.useTrailing            != other.exit.useTrailing,            FIELD_EXIT_TRAILING)
      ADD_IF_CHANGED(exit.usePartial             != other.exit.usePartial,             FIELD_EXIT_PARTIAL)
      ADD_IF_CHANGED(exit.exitOnOpposite         != other.exit.exitOnOpposite,         FIELD_EXIT_ON_OPPOSITE)
      ADD_IF_CHANGED(exit.tpBufferATR            != other.exit.tpBufferATR,            FIELD_EXIT_TP_BUFFER)
      ADD_IF_CHANGED(exit.slBufferATR            != other.exit.slBufferATR,            FIELD_EXIT_SL_BUFFER)
      ADD_IF_CHANGED(exit.minTPDistATR           != other.exit.minTPDistATR,           FIELD_EXIT_MIN_TP_DIST)
      ADD_IF_CHANGED(exit.maxTPDistATR           != other.exit.maxTPDistATR,           FIELD_EXIT_MAX_TP_DIST)
      ADD_IF_CHANGED(exit.trailingStartATR       != other.exit.trailingStartATR,       FIELD_EXIT_TRAILING_START)
      ADD_IF_CHANGED(exit.trailingBufferATR      != other.exit.trailingBufferATR,      FIELD_EXIT_TRAILING_BUFFER)
      ADD_IF_CHANGED(exit.partialLotPct          != other.exit.partialLotPct,          FIELD_EXIT_PARTIAL_LOT_PCT)
      ADD_IF_CHANGED(exit.partialATR             != other.exit.partialATR,             FIELD_EXIT_PARTIAL_ATR)
      ADD_IF_CHANGED(ai.use                      != other.ai.use,                      FIELD_AI_USE)
      ADD_IF_CHANGED(ai.trainingWindow           != other.ai.trainingWindow,           FIELD_AI_TRAINING_WINDOW)
      ADD_IF_CHANGED(ai.minConfidence            != other.ai.minConfidence,            FIELD_AI_MIN_CONFIDENCE)
      ADD_IF_CHANGED(ai.patternBonus             != other.ai.patternBonus,             FIELD_AI_PATTERN_BONUS)
      ADD_IF_CHANGED(system.debug                != other.system.debug,                FIELD_SYSTEM_DEBUG)
      ADD_IF_CHANGED(system.safe                 != other.system.safe,                 FIELD_SYSTEM_SAFE)
      ADD_IF_CHANGED(system.orderThrottleMs      != other.system.orderThrottleMs,      FIELD_SYSTEM_THROTTLE)

      #undef ADD_IF_CHANGED
   }

   bool HasChanged(const StrategyConfig &other, ENUM_CONFIG_FIELD_ID fieldId) const
   {
      switch(fieldId)
      {
         case FIELD_ATR_PERIOD:               return market.atrPeriod            != other.market.atrPeriod;
         case FIELD_ATR_MIN:                  return market.atrMin               != other.market.atrMin;
         case FIELD_ATR_MAX:                  return market.atrMax               != other.market.atrMax;
         case FIELD_MAX_SPREAD:               return market.maxSpread            != other.market.maxSpread;
         case FIELD_USE_REGIME:               return market.useRegime            != other.market.useRegime;
         case FIELD_MIN_TREND_STRENGTH:       return market.minTrendStrength      != other.market.minTrendStrength;
         case FIELD_ALLOW_SIDEWAYS:           return market.allowSideways        != other.market.allowSideways;
         case FIELD_REGIME_LOT_MULT_STRONG:   return market.regimeLotMultStrong  != other.market.regimeLotMultStrong;
         case FIELD_REGIME_LOT_MULT_WEAK:     return market.regimeLotMultWeak    != other.market.regimeLotMultWeak;
         case FIELD_REGIME_LOT_MULT_SIDE:     return market.regimeLotMultSide    != other.market.regimeLotMultSide;
         case FIELD_REGIME_LOT_MULT_CHOP:     return market.regimeLotMultChop    != other.market.regimeLotMultChop;
         case FIELD_NEWS_LEVEL:               return news.level                  != other.news.level;
         case FIELD_NEWS_FREEZE:              return news.freeze                 != other.news.freeze;
         case FIELD_AUTO_LOT:                 return risk.autoLot                != other.risk.autoLot;
         case FIELD_RISK_PCT:                 return risk.pct                    != other.risk.pct;
         case FIELD_LOT_SIZE:                 return risk.lot                    != other.risk.lot;
         case FIELD_MAX_DAILY_LOSS:           return risk.maxDailyLoss           != other.risk.maxDailyLoss;
         case FIELD_MAGIC_NUM:                return risk.magic                  != other.risk.magic;
         case FIELD_ENTRY_MODE:               return risk.entryMode              != other.risk.entryMode;
         case FIELD_TPSL_MODE:                return risk.tpslMode               != other.risk.tpslMode;
         case FIELD_USE_MTF:                  return risk.useMTF                 != other.risk.useMTF;
         case FIELD_HTF:                      return risk.htf                    != other.risk.htf;
         case FIELD_HTF_LOOKBACK:             return risk.htfLookback            != other.risk.htfLookback;
         case FIELD_QUALITY_LOT_MULT:         return risk.qualityLotMult         != other.risk.qualityLotMult;
         case FIELD_MAX_POSITIONS:            return risk.maxPositions           != other.risk.maxPositions;
         case FIELD_MAX_CONSECUTIVE_LOSS:     return risk.maxConsecutiveLoss     != other.risk.maxConsecutiveLoss;
         case FIELD_MAX_TRADE_DURATION:       return risk.maxTradeDurationDays   != other.risk.maxTradeDurationDays;
         case FIELD_ENTRY_COOLDOWN:           return risk.entryCooldownBars      != other.risk.entryCooldownBars;
         case FIELD_SIGNAL_COOLDOWN:          return risk.signalCooldownBars     != other.risk.signalCooldownBars;
         case FIELD_LOSS_COOLDOWN:            return risk.lossCooldownBars       != other.risk.lossCooldownBars;
         case FIELD_SR_MODE:                  return sr.mode                     != other.sr.mode;
         case FIELD_SR_LOOKBACK:              return sr.lookback                 != other.sr.lookback;
         case FIELD_SR_SWING_LOOKBACK:        return sr.swingLookback            != other.sr.swingLookback;
         case FIELD_SR_TOUCH_BUFFER:          return sr.touchBufferATR           != other.sr.touchBufferATR;
         case FIELD_SR_MIN_TOUCHES:           return sr.minTouchesStrong         != other.sr.minTouchesStrong;
         case FIELD_SR_MIN_RANGE:             return sr.minRangeATR              != other.sr.minRangeATR;
         case FIELD_SR_ATR_BUFFER:            return sr.atrBufferMult            != other.sr.atrBufferMult;
         case FIELD_SR_BUFFER_STRONG:         return sr.bufferMultStrong         != other.sr.bufferMultStrong;
         case FIELD_SR_BUFFER_WEAK:           return sr.bufferMultWeak           != other.sr.bufferMultWeak;
         case FIELD_SR_ZONE_REUSE:            return sr.zoneReuseATR             != other.sr.zoneReuseATR;
         case FIELD_PATTERN_LOOKBACK:         return pattern.lookback            != other.pattern.lookback;
         case FIELD_PATTERN_MTF_BONUS:        return pattern.mtfConfluenceBonus  != other.pattern.mtfConfluenceBonus;
         case FIELD_PATTERN_STRONG_ZONE_BONUS:return pattern.strongZoneBonus     != other.pattern.strongZoneBonus;
         case FIELD_PATTERN_STRONG_ZONE_THRESHOLD: return pattern.strongZoneThreshold != other.pattern.strongZoneThreshold;
         case FIELD_PATTERN_MAX_SIGNAL_ATR:   return pattern.maxSignalATR        != other.pattern.maxSignalATR;
         case FIELD_PATTERN_MOMENTUM_THRESHOLD:return pattern.momentumThresholdATR!= other.pattern.momentumThresholdATR;
         case FIELD_PATTERN_USE_WEIGHTS:      return pattern.useWeights          != other.pattern.useWeights;
         case FIELD_PATTERN_ANTI_BREAKOUT:    return pattern.antiBreakoutPct     != other.pattern.antiBreakoutPct;
         case FIELD_PATTERN_MARUBOZU_BODY:    return pattern.marubozuMinBodyPct  != other.pattern.marubozuMinBodyPct;
         case FIELD_PATTERN_ENGULFING_MULT:   return pattern.engulfingBodyMult   != other.pattern.engulfingBodyMult;
         case FIELD_PATTERN_DOMINANCE_GAP:    return pattern.minDominanceGap     != other.pattern.minDominanceGap;
         case FIELD_PATTERN_SENSITIVITY:      return pattern.sensitivityATR      != other.pattern.sensitivityATR;
         case FIELD_PATTERN_DEFAULT_SL_MULT:  return pattern.defaultSLMult       != other.pattern.defaultSLMult;
         case FIELD_PATTERN_PINBAR_SL_MULT:   return pattern.pinbarSLMult        != other.pattern.pinbarSLMult;
         case FIELD_PATTERN_INSIDEBAR_SL_MULT:return pattern.insideBarSLMult     != other.pattern.insideBarSLMult;
         case FIELD_PATTERN_HQ_THRESHOLD:     return pattern.hqThreshold         != other.pattern.hqThreshold;
         case FIELD_RECOVERY_USE:             return recovery.use                != other.recovery.use;
         case FIELD_RECOVERY_COOLDOWN:        return recovery.cooldownBars       != other.recovery.cooldownBars;
         case FIELD_RECOVERY_MAX_ATTEMPTS:    return recovery.maxAttempts        != other.recovery.maxAttempts;
         case FIELD_RECOVERY_LOT_MULT:        return recovery.lotMult            != other.recovery.lotMult;
         case FIELD_RECOVERY_SCORE_THRESHOLD: return recovery.scoreThreshold     != other.recovery.scoreThreshold;
         case FIELD_RECOVERY_ZONE_TOLERANCE:  return recovery.zoneToleranceATR   != other.recovery.zoneToleranceATR;
         case FIELD_RECOVERY_FAKEOUT_SENS:    return recovery.fakeoutSensitivity != other.recovery.fakeoutSensitivity;
         case FIELD_EXIT_TRAILING:            return exit.useTrailing            != other.exit.useTrailing;
         case FIELD_EXIT_PARTIAL:             return exit.usePartial             != other.exit.usePartial;
         case FIELD_EXIT_ON_OPPOSITE:         return exit.exitOnOpposite         != other.exit.exitOnOpposite;
         case FIELD_EXIT_TP_BUFFER:           return exit.tpBufferATR            != other.exit.tpBufferATR;
         case FIELD_EXIT_SL_BUFFER:           return exit.slBufferATR            != other.exit.slBufferATR;
         case FIELD_EXIT_MIN_TP_DIST:         return exit.minTPDistATR           != other.exit.minTPDistATR;
         case FIELD_EXIT_MAX_TP_DIST:         return exit.maxTPDistATR           != other.exit.maxTPDistATR;
         case FIELD_EXIT_TRAILING_START:      return exit.trailingStartATR       != other.exit.trailingStartATR;
         case FIELD_EXIT_TRAILING_BUFFER:     return exit.trailingBufferATR      != other.exit.trailingBufferATR;
         case FIELD_EXIT_PARTIAL_LOT_PCT:     return exit.partialLotPct          != other.exit.partialLotPct;
         case FIELD_EXIT_PARTIAL_ATR:         return exit.partialATR             != other.exit.partialATR;
         case FIELD_AI_USE:                   return ai.use                      != other.ai.use;
         case FIELD_AI_TRAINING_WINDOW:       return ai.trainingWindow           != other.ai.trainingWindow;
         case FIELD_AI_MIN_CONFIDENCE:        return ai.minConfidence            != other.ai.minConfidence;
         case FIELD_AI_PATTERN_BONUS:         return ai.patternBonus             != other.ai.patternBonus;
         case FIELD_SYSTEM_DEBUG:             return system.debug                != other.system.debug;
         case FIELD_SYSTEM_SAFE:              return system.safe                 != other.system.safe;
         case FIELD_SYSTEM_THROTTLE:          return system.orderThrottleMs      != other.system.orderThrottleMs;
         default: return false;
      }
   }
};

//+------------------------------------------------------------------+
//| ConfigManager - Singleton                                        |
//+------------------------------------------------------------------+
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

#endif // __CONFIG_MQH__
