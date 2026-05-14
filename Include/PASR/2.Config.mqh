//+------------------------------------------------------------------+
//|                                                       2.Config.mqh |
//|                                       Copyright 2026, Agsicentre |
//|            Core Configuration & System Definitions               |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "2.00"
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
   PATTERN_BOTTOM,               // bottom
   PATTERN_FAKEY,                // Fakey
   PATTERN_INSIDE_BAR_BREAKOUT, // Inside Bar Breakout
   PATTERN_MORNING_STAR,        // Morning/Evening Star
   PATTERN_THREE_INSIDE,        // Three Inside Up/Down
   PATTERN_RAILROAD_TRACKS,     // Railroad Tracks
   PATTERN_DARK_CLOUD_PIERCING, // Dark Cloud Cover / Piercing Line
   PATTERN_MARUBOZU             // Momentum Marubozu
};

/**
 * ID Event untuk Sistem Event-Driven (Static Dispatch)
 */
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
   MODE_SAFE,      // Sinyal Valid & Optimal
   MODE_AGGRESSIVE // Sinyal Valid saja
};

enum ENUM_TPSL_MODE
{
   TPSL_SR,     // Support/Resistance
   TPSL_PATTERN // Extreme Pattern
};

enum ENUM_SR_MODE
{
   SR_EXTREME, // Extreme High/Low
   SR_SWING,   // Swing
   SR_AUTO     // Otomatis
};

enum ENUM_NEWS_LEVEL
{
   NEWS_HIGH = 1,        // News High
   NEWS_HIGH_MEDIUM = 2, // News High & Medium
   NEWS_ALL = 3,         // Semua News (High, Medium, Low)
   NEWS_OFF = 0          // Nonaktif
};

enum ENUM_TRADE_STATE
{
   TRADE_STATE_NONE = 0,
   TRADE_STATE_NORMAL,
   TRADE_STATE_RECOVERY, // Position hit SL, now looking for re-entry
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
   double slMultiplier; // SL multiplier for this pattern
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
input string InpSessionSun = "0";                                      // Sunday    (0=Off HH:MM-HH:MM=on)
input string InpSessionMon = "0";                                      // Monday    (0=Off HH:MM-HH:MM=on)
input string InpSessionTue = "0";                                      // Tuesday   (0=Off HH:MM-HH:MM=on)
input string InpSessionWed = "0";                                      // Wednesday (0=Off HH:MM-HH:MM=on)
input string InpSessionThu = "0";                                      // Thursday  (0=Off HH:MM-HH:MM=on)
input string InpSessionFri = "0";                                      // Friday    (0=Off HH:MM-HH:MM=on)
input string InpSessionSat = "0";                                      // Saturday  (0=Off HH:MM-HH:MM=on)
input ENUM_NEWS_LEVEL InpNewsLevel = NEWS_OFF;                         // News Filter Level (NEWS_OFF = Disabled)
input int InpNewsFreezeMinutes = 30;                                   // News Freeze (Minutes before/after)
input string InpNewsWebURL = "https://nfs.faireconomy.media/ff_calendar_thisweek.xml";                                       // News XML Calendar URL

// [GROUP] MARKET REGIME & VOLATILITY FILTER
input bool InpUseMarketRegime;        // Aktifkan Filter Market Regime
input double InpMinTrendStrength;     // Kekuatan Tren Minimum (0.0-1.0)
input bool InpAllowSidewaysTrading;   // Izinkan Trading di Sideways
input double InpRegimeLotMultStrong;  // Lot Multiplier Strong Trend
input double InpRegimeLotMultWeak;    // Lot Multiplier Weak Trend
input double InpRegimeLotMultSide;    // Lot Multiplier Sideways
input double InpRegimeLotMultChop;    // Lot Multiplier Volatile Chop

// [GROUP] RISK MANAGEMENT
input bool InpUseAutoLot;           // Gunakan AutoLot (Risk %)
input double InpRiskPct;            // Risiko % per Trade
input double InpLotSize;            // Lot Statis (jika AutoLot OFF)
input double InpMaxDailyLossPct;    // Batas Maksimal Loss Harian (%)
input ulong InpMagicNum;            // ID Transaksi Magic
input ENUM_ENTRY_MODE InpEntryMode; // Mode Entry (Safe/Aggressive)
input ENUM_TPSL_MODE InpTPSLMode;   // Mode Penentuan TP/SL
input bool InpUseMTF;               // Gunakan Filter Multi-Timeframe (HTF)
input ENUM_TIMEFRAMES InpHTF;       // Higher Timeframe (HTF)
input int InpHTFLookback;           // HTF Lookback (Candles)
input double InpQualityLotMult;     // Multiplier Lot Sinyal Lemah

// [GROUP] SUPPORT & RESISTANCE (SR) ENGINE
input ENUM_SR_MODE InpSRMode;     // Mode Deteksi SR
input int InpSRLookback;          // SR Lookback (Candles)
input int InpSwingLookback;       // Swing/Fractal Lookback
input double InpSRTouchBufferATR; // Toleransi Sentuhan Zona (ATR x)
input int InpSRMinTouchesStrong;  // Min Sentuhan Zona Kuat
input double InpMinSRRangeATR;    // Min Range Antar Zona (ATR x)
input double InpATRBufferMult;    // Global ATR Buffer Mult
input double InpBufferMultStrong; // Strong Zone Buffer Mult
input double InpBufferMultWeak;   // Weak Zone Buffer Mult

// [GROUP] SIGNAL DETECTION & PATTERNS
input int InpSignalLookback;           // Scan Pattern (Lookback Bar)
input double InpMTFConfluenceBonus;    // Skor Jika Searah/Aligned HTF
input double InpStrongZoneBonus;       // Skor di Zona Kuat
input double InpStrongZoneThreshold;   // Ambang Multiplier Zona Kuat
input double InpMaxSignalATR;          // Max Ukuran Candle Sinyal (ATR x)
input double InpMomentumThresholdATR;  // Threshold Dorongan Momentum (ATR x)
input bool InpUsePatternWeights;       // Gunakan Bobot Historis Pattern
input double InpAntiBreakoutPct;       // Batas Body Ratio (Anti-Breakout)
input double InpMarubozuMinBodyPct;    // Minimal Body Marubozu (0.9 = 90%)
input double InpEngulfingBodyMult;     // Rasio Tubuh Engulfing
input double InpMinDominanceGap;       // Minimal Selisih Skor Dominansi
input double InpStrongZoneBufferMult;  // Buffer multiplier untuk zona kuat
input bool InpUseAdaptiveZoneBuffer;   // Buffer zona adaptif berdasarkan strength
input double InpPatternSensitivityATR; // Toleransi Gap & Aliansi Pattern (ATR x)
input double InpStarMiddleBodyMult;    // Rasio Maksimal Candle Tengah Star
input double InpRailroadMinBodyRatio;  // Min ratio body untuk Railroad Tracks
input double InpZoneReuseATR;          // Jarak Reuse Zona (ATR x)

// NEW: Generic Pattern Scoring Parameters
input double InpPatternBaseScore;                 // Skor dasar untuk setiap pola valid
input double InpPatternBonusStrongATRRange;       // skor candle dengan range ATR signifikan
input double InpPatternBonusStrongBodyRatio;      // skor candle dengan rasio body signifikan (misal: body kecil untuk rejection)
input double InpPatternBonusStrongWickRejection;  // skor candle dengan rejection wick signifikan
input double InpPatternBonusFollowThrough;        // skor candle follow-through (misal: close searah dengan bias)
input double InpPatternBonusGapConfirmation;      // skor konfirmasi gap (misal: pola Star)
input double InpPatternBonusBreakoutConfirmation; // skor konfirmasi breakout (misal: pola Three Inside)
input double InpPatternBonusSmall;                // skor kecil untuk pengakuan pola dasar

// NEW: Generic Pattern Thresholds
input double InpPatternATRRangeThreshold;  // Faktor ATR untuk candle dianggap "range signifikan" (misal: range > 0.6 * ATR)
input double InpPatternBodyRatioThreshold; // Rasio Body/Range untuk candle dianggap "body kecil" (misal: untuk rejection)
input double InpPatternWickRatioThreshold; // Rasio Wick/Range untuk candle dianggap "rejection signifikan" (misal: wick > 0.5 * range)

// NEW: Pattern-Specific Thresholds (hanya jika berbeda dari umum atau unik)
input double InpPinbarWickToOppositeWickRatio; // Rasio min wick utama terhadap wick berlawanan untuk Pinbar
input double InpInsideBarChildMotherRangeMax;  // Rasio maks range child bar terhadap mother bar untuk Inside Bar
input double InpStarClosePositionMin;          // Posisi close min untuk pola Star (misal: close di 60% atas/bawah range)
input double InpThreeInsideBodyRatioMin;       // Rasio min body candle breakout terhadap body mother bar untuk Three Inside
input double InpRailroadAvgBodyMinATR;         // Ukuran body rata-rata min relatif terhadap ATR untuk Railroad Tracks
input double InpRailroadWickRejectionMult;     // Multiplier min rejection wick relatif terhadap body untuk Railroad Tracks
input double InpMarubozuMinATRRangeMult;       // Multiplier untuk MomentumThresholdATR untuk range min Marubozu
input double InpMarubozuStrongATRRangeMin;     // Faktor ATR min untuk bonus ekstra pada Marubozu

// [GROUP] RECOVERY MODE & FAKEOUT PROTECTION
input bool InpUseRecoveryMode;                 // Aktifkan mode recovery setelah SL hit (includes fakeout detection)
input int InpRecoveryCooldownBars;             // Cooldown bars setelah SL hit sebelum mencari re-entry
input int InpMaxRecoveryAttempts;              // Maksimal percobaan re-entry untuk satu posisi
input double InpRecoveryLotMult;               // Multiplier lot untuk re-entry
input double InpRecoveryPatternScoreThreshold; // Skor minimal pattern untuk re-entry (lowered for more opportunities)
input double InpRecoveryZoneToleranceATR;      // Toleransi ATR dari SL hit price untuk mencari re-entry
input double InpFakeoutDetectionSensitivity;   // Sensitivitas deteksi fakeout (0.2-0.5, lower = more sensitive)
input double InpFakeoutSLAdjustmentATR;        // Adjustment SL saat fakeout terdeteksi (ATR multiplier)

// [GROUP] PATTERN SPECIFIC VOLATILITY (SL MULTIPLIERS)
input double InpDefaultSLMult;   // SL Mult Standar
input double InpPinbarSLMult;    // SL Mult khusus Pinbar
input double InpInsideBarSLMult; // SL Mult khusus Inside Bar

// [GROUP] COOLDOWNS & PROTECTION
input int InpMaxOpenPositions;           // Max Posisi Berjalan
input int InpMaxConsecutiveLoss;         // Batas Loss Beruntun
input int InpMaxTradeDurationDays;       // Durasi Maksimal Trade (Hari)
input int InpEntryCooldownBars;          // Cooldown Antar Entry (Bars)
input int InpSignalCooldownBars;         // Cooldown Sinyal Area (Bars)
input int InpLossCooldownBars;           // Cooldown Setelah Loss (Bars)
input int InpPatternFailureCooldownBars; // Cooldown Level Gagal (Bars)
input double InpHighQualityThreshold;    // Skor Setup Premium (Bypass Cooldown)
input bool InpUseDynamicCooldown;        // Aktifkan Cooldown Adaptif HQ
input int InpReducedCooldownBars;        // Cooldown untuk HQ Setup

// [GROUP] EXECUTION, TRAILING & RECOVERY
input double InpMaxSpread;          // Batas Maksimal Spread (Points)
input int InpOrderThrottleMs;       // Throttle Eksekusi (ms)
input bool InpUseTrailing;          // Aktifkan Trailing Stop
input bool InpUsePartialClose;      // Aktifkan Partial Close
input bool InpExitOnOpposite;       // Close Jika Muncul Sinyal Lawan
input double InpTPBufferATR;        // TP Buffer Dalam Zona (ATR x)
input double InpSLBufferATR;        // SL Buffer Luar Zona (ATR x)
input double InpMinTPDistanceATR;   // Min Jarak TP (ATR x)
input double InpMaxTPDistanceATR;   // Max Jarak TP (ATR x)
input double InpTrailingStartATR;   // Trailing Start (ATR x)
input double InpTrailingBufferATR;  // Jarak Aman Buffer (ATR x)
input double InpTrailActivationATR; // Aktivasi Trailing (ATR x)
input double InpTrailStepATR;       // Trailing Step (ATR x)
input double InpLockProfitATR;      // Lock Profit Activation (ATR x)
input double InpLockOffsetATR;      // Profit Terkunci (ATR x)
input double InpPartialCloseLotPct; // % Lot Partial Close
input double InpPartialCloseATR;    // Target Partial TP (ATR x)

// [GROUP] AI / MACHINE LEARNING
input bool InpUseAI;             // Aktifkan Penggunaan AI Filter
input int InpAITrainingWindowBars; // Jendela Training (Bars)
input double InpAIMinConfidence;  // Ambang Kepercayaan Minimum
input double InpAIPatternBonus;   // Bonus pada Pola Valid

// [GROUP] SYSTEM & DEBUG
input bool InpDebugMode; // Log Debug ke Konsol
input bool InpSafeMode;  // Aktifkan Proteksi Safe Mode
input int InpATRPeriod;  // Periode ATR
input double InpATRMin;  // Batas Bawah Volatilitas (Points)
input double InpATRMax;  // Batas Atas Volatilitas (Points)

//+------------------------------------------------------------------+
//| VALIDATION HELPERS - Central validation utilities                |
//+------------------------------------------------------------------+

/**
 * Clamp value between min and max
 */
template<typename T>
T Clamp(T value, T minVal, T maxVal)
{
   if(value < minVal) return minVal;
   if(value > maxVal) return maxVal;
   return value;
}

/**
 * Ensure value is positive, return default if not
 */
double EnsurePositive(double value, double defaultValue)
{
   return (value > 0) ? value : defaultValue;
}

/**
 * Ensure value is non-negative, return default if not
 */
double EnsureNonNegative(double value, double defaultValue)
{
   return (value >= 0) ? value : defaultValue;
}

/**
 * Validate range: min <= value <= max, return default if invalid
 */
double ValidateRange(double value, double minVal, double maxVal, double defaultValue)
{
   if(value < minVal || value > maxVal) return defaultValue;
   return value;
}

/**
 * Validate integer range: min <= value <= max, return default if invalid
 */
int ValidateIntRange(int value, int minVal, int maxVal, int defaultValue)
{
   if(value < minVal || value > maxVal) return defaultValue;
   return value;
}

/**
 * Log warning for invalid parameter
 */
void LogWarning(const string paramName, const string message)
{
   Print("WARNING: ", paramName, " ", message);
}

//+------------------------------------------------------------------+
//| DOMAIN-SPECIFIC VALIDATION RULES                                 |
//| Centralized validation logic per configuration domain            |
//+------------------------------------------------------------------+

/**
 * Market parameter validation rules
 */
struct MarketValidation
{
   static bool ValidateATRPeriod(int period) { return period >= 1 && period <= 1000; }
   static bool ValidateTrendStrength(double strength) { return strength >= 0.0 && strength <= 1.0; }
   static bool ValidateLotMultiplier(double mult) { return mult >= 0.1 && mult <= 10.0; }
   
   static int NormalizeATRPeriod(int period)
   {
      if(!ValidateATRPeriod(period))
      {
         LogWarning("ATRPeriod", "must be 1-1000. Using default 14.");
         return 14;
      }
      return period;
   }
   
   static double NormalizeTrendStrength(double strength)
   {
      double normalized = Clamp(strength, 0.0, 1.0);
      if(normalized != strength)
         LogWarning("TrendStrength", "must be 0.0-1.0. Clamped.");
      return normalized;
   }
   
   static double NormalizeLotMultiplier(double mult, double defaultVal = 1.0)
   {
      if(!ValidateLotMultiplier(mult))
      {
         LogWarning("LotMultiplier", "must be 0.1-10.0. Using default.");
         return defaultVal;
      }
      return mult;
   }
};

/**
 * Risk parameter validation rules
 */
struct RiskValidation
{
   static bool ValidateRiskPct(double pct) { return pct >= 0.01 && pct <= 100.0; }
   static bool ValidateLotSize(double lot) { return lot >= 0.01; }
   static bool ValidateMaxPositions(int count) { return count >= 0 && count <= 100; }
   
   static double NormalizeRiskPct(double pct)
   {
      if(!ValidateRiskPct(pct))
      {
         LogWarning("RiskPct", "must be 0.01-100. Using default 1.0.");
         return 1.0;
      }
      return pct;
   }
   
   static double NormalizeLotSize(double lot)
   {
      if(!ValidateLotSize(lot))
      {
         LogWarning("LotSize", "must be >= 0.01. Using default 0.01.");
         return 0.01;
      }
      return lot;
   }
   
   static int NormalizeMaxPositions(int count)
   {
      if(!ValidateMaxPositions(count))
      {
         LogWarning("MaxPositions", "must be 0-100. Using default 0.");
         return 0;
      }
      return count;
   }
};

/**
 * Pattern parameter validation rules
 */
struct PatternValidation
{
   static bool ValidateScore(double score) { return score >= 0.0; }
   static bool ValidateRatio(double ratio) { return ratio >= 0.0 && ratio <= 1.0; }
   static bool ValidateSLMultiplier(double mult) { return mult >= 0.5 && mult <= 5.0; }
   
   static double NormalizeScore(double score, double defaultVal = 0.0)
   {
      if(!ValidateScore(score))
      {
         LogWarning("PatternScore", "must be >= 0. Using default.");
         return defaultVal;
      }
      return score;
   }
   
   static double NormalizeRatio(double ratio, double defaultVal = 0.5)
   {
      if(!ValidateRatio(ratio))
      {
         LogWarning("PatternRatio", "must be 0.0-1.0. Using default.");
         return defaultVal;
      }
      return ratio;
   }
   
   static double NormalizeSLMultiplier(double mult)
   {
      if(!ValidateSLMultiplier(mult))
      {
         LogWarning("SLMultiplier", "must be 0.5-5.0. Using default 1.0.");
         return 1.0;
      }
      return mult;
   }
};

/**
 * Recovery parameter validation rules
 */
struct RecoveryValidation
{
   static bool ValidateCooldownBars(int bars) { return bars >= 0 && bars <= 1000; }
   static bool ValidateMaxAttempts(int attempts) { return attempts >= 0 && attempts <= 10; }
   static bool ValidateSensitivity(double sens) { return sens >= 0.1 && sens <= 1.0; }
   
   static int NormalizeCooldownBars(int bars, int defaultVal = 3)
   {
      if(!ValidateCooldownBars(bars))
      {
         LogWarning("RecoveryCooldown", "must be 0-1000. Using default.");
         return defaultVal;
      }
      return bars;
   }
   
   static int NormalizeMaxAttempts(int attempts)
   {
      if(!ValidateMaxAttempts(attempts))
      {
         LogWarning("MaxRecoveryAttempts", "must be 0-10. Using default 2.");
         return 2;
      }
      return attempts;
   }
   
   static double NormalizeSensitivity(double sens)
   {
      if(!ValidateSensitivity(sens))
      {
         LogWarning("FakeoutSensitivity", "must be 0.1-1.0. Using default 0.3.");
         return 0.3;
      }
      return sens;
   }
};

//+------------------------------------------------------------------+
//| STRATEGY CONFIG - Single Source of Truth                         |
//| Nested struct dengan camelCase, validasi terintegrasi            |
//+------------------------------------------------------------------+
struct StrategyConfig
{
    struct Market {
      int atrPeriod;
      double atrMin;
      double atrMax;
      double maxSpread;
      string sessions[7];
      // Market Regime
      bool useRegime;
      double minTrendStrength;
      bool allowSideways;
      double regimeLotMultStrong;
      double regimeLotMultWeak;
      double regimeLotMultSide;
      double regimeLotMultChop;
      
      // Validation method
      void Validate()
      {
         atrPeriod = MarketValidation::NormalizeATRPeriod(atrPeriod);
         minTrendStrength = MarketValidation::NormalizeTrendStrength(minTrendStrength);
         regimeLotMultStrong = MarketValidation::NormalizeLotMultiplier(regimeLotMultStrong, 1.0);
         regimeLotMultWeak = MarketValidation::NormalizeLotMultiplier(regimeLotMultWeak, 1.0);
         regimeLotMultSide = MarketValidation::NormalizeLotMultiplier(regimeLotMultSide, 1.0);
         regimeLotMultChop = MarketValidation::NormalizeLotMultiplier(regimeLotMultChop, 1.0);
         
         // Cross-field validation
         if(atrMax < atrMin)
         {
            LogWarning("ATRMax", "must be >= ATRMin. Adjusted.");
            atrMax = atrMin;
         }
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
         pct = RiskValidation::NormalizeRiskPct(pct);
         lot = RiskValidation::NormalizeLotSize(lot);
         maxPositions = RiskValidation::NormalizeMaxPositions(maxPositions);
         
         maxConsecutiveLoss = ValidateIntRange(maxConsecutiveLoss, 0, 100, 0);
         maxTradeDurationDays = ValidateIntRange(maxTradeDurationDays, 0, 365, 0);
         entryCooldownBars = ValidateIntRange(entryCooldownBars, 0, 1000, 0);
         signalCooldownBars = ValidateIntRange(signalCooldownBars, 0, 1000, 0);
         lossCooldownBars = ValidateIntRange(lossCooldownBars, 0, 1000, 0);
         htfLookback = ValidateIntRange(htfLookback, 1, 1000, 100);
         
         qualityLotMult = MarketValidation::NormalizeLotMultiplier(qualityLotMult, 1.0);
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
         lookback = ValidateIntRange(lookback, 10, 10000, 100);
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
      // Scoring
      double baseScore;
      double bonusStrongATR;
      double bonusStrongBody;
      double bonusStrongWick;
      double bonusFollowThrough;
      double bonusGapConfirm;
      double bonusBreakoutConfirm;
      double bonusSmall;
      // Thresholds
      double atrRangeThreshold;
      double bodyRatioThreshold;
      double wickRatioThreshold;
      // Specifics
      double pinbarWickRatio;
      double insideBarRangeMax;
      double starCloseMin;
      double threeInsideBodyMin;
      double railroadAvgBodyMin;
      double railroadWickMult;
      double marubozuMinATRMult;
      double marubozuStrongATRMin;
      // SL Multipliers
      double defaultSLMult;
      double pinbarSLMult;
      double insideBarSLMult;
      
      void Validate()
      {
         lookback = ValidateIntRange(lookback, 1, 500, 5);
         failureCooldownBars = ValidateIntRange(failureCooldownBars, 0, 1000, 0);
         reducedCooldownBars = ValidateIntRange(reducedCooldownBars, 0, 1000, 0);
         
         // Scores
         baseScore = PatternValidation::NormalizeScore(baseScore, 0.0);
         bonusStrongATR = PatternValidation::NormalizeScore(bonusStrongATR, 0.0);
         bonusStrongBody = PatternValidation::NormalizeScore(bonusStrongBody, 0.0);
         bonusStrongWick = PatternValidation::NormalizeScore(bonusStrongWick, 0.0);
         
         // Ratios
         marubozuMinBodyPct = PatternValidation::NormalizeRatio(marubozuMinBodyPct, 0.9);
         antiBreakoutPct = PatternValidation::NormalizeRatio(antiBreakoutPct, 0.5);
         
         // SL Multipliers
         defaultSLMult = PatternValidation::NormalizeSLMultiplier(defaultSLMult);
         pinbarSLMult = PatternValidation::NormalizeSLMultiplier(pinbarSLMult);
         insideBarSLMult = PatternValidation::NormalizeSLMultiplier(insideBarSLMult);
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
      // SAFEGUARD: Maximum recovery positions per initial position
      int maxRecoveryPositions;
      double maxExposureMultiplier;
      int recoveryTimeoutBars;
      double hardStopLossPct;
      
      void Validate()
      {
         cooldownBars = RecoveryValidation::NormalizeCooldownBars(cooldownBars, 3);
         maxAttempts = RecoveryValidation::NormalizeMaxAttempts(maxAttempts);
         fakeoutSensitivity = RecoveryValidation::NormalizeSensitivity(fakeoutSensitivity);
         
         maxRecoveryPositions = ValidateIntRange(maxRecoveryPositions, 0, 10, 2);
         recoveryTimeoutBars = ValidateIntRange(recoveryTimeoutBars, 0, 1000, 20);
         hardStopLossPct = ValidateRange(hardStopLossPct, 0.0, 100.0, 3.0);
         
         lotMult = EnsureNonNegative(lotMult, 1.0);
         maxExposureMultiplier = EnsurePositive(maxExposureMultiplier, 2.0);
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
         partialLotPct = ValidateRange(partialLotPct, 1.0, 100.0, 50.0);
         trailingStartATR = EnsureNonNegative(trailingStartATR, 1.5);
         
         // Cross-field validation
         if(maxTPDistATR < minTPDistATR)
         {
            LogWarning("MaxTPDistance", "must be >= MinTPDistance. Adjusted.");
            maxTPDistATR = minTPDistATR;
         }
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
         {
            LogWarning("AITrainingWindow", "too small for AI. Using default 200.");
            trainingWindow = 200;
         }
      }
   } ai;

   struct System {
      bool debug;
      bool safe;
      int orderThrottleMs;
      
      void Validate()
      {
         orderThrottleMs = ValidateIntRange(orderThrottleMs, 0, 10000, 100);
      }
   } system;
   
   // Master validation - calls all sub-struct validators
   void Validate()
   {
      market.Validate();
      news.Validate();
      risk.Validate();
      sr.Validate();
      pattern.Validate();
      recovery.Validate();
      exit.Validate();
      ai.Validate();
      system.Validate();
   }
};

//+------------------------------------------------------------------+
//| ConfigManager - Singleton untuk mengelola konfigurasi global     |
//| Membatasi akses mutabilitas, hanya melalui getter dan setter     |
//+------------------------------------------------------------------+
class ConfigManager
{
private:
   static ConfigManager *m_instance;
   StrategyConfig m_config;
   bool m_initialized;
   
   // Constructor privat untuk singleton
   ConfigManager() : m_initialized(false) {}
   
public:
   // Mendapatkan instance singleton
   static ConfigManager *GetInstance()
   {
      if(m_instance == NULL)
         m_instance = new ConfigManager();
      return m_instance;
   }
   
   // Getter untuk membaca konfigurasi (const reference, read-only)
   const StrategyConfig& GetConfig() const { return m_config; }
   
   // Check apakah sudah diinisialisasi
   bool IsInitialized() const { return m_initialized; }
   
   // Helper method to copy config (for caching purposes)
   void CopyTo(StrategyConfig &dest) const
   {
      dest = m_config;
   }
   
   // Reload konfigurasi dari input parameters
   void Reload()
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
      m_initialized = true;
   }
   
   //+------------------------------------------------------------------+
   //| Modular Loading Functions with Centralized Validation            |
   //+------------------------------------------------------------------+
   
   void LoadMarketParams()
   {
      // Sessions - direct assignment
      m_config.market.sessions[0] = InpSessionSun;
      m_config.market.sessions[1] = InpSessionMon;
      m_config.market.sessions[2] = InpSessionTue;
      m_config.market.sessions[3] = InpSessionWed;
      m_config.market.sessions[4] = InpSessionThu;
      m_config.market.sessions[5] = InpSessionFri;
      m_config.market.sessions[6] = InpSessionSat;
      
      // Market Regime Filter - use validation helpers
      m_config.market.useRegime = InpUseMarketRegime;
      m_config.market.minTrendStrength = MarketValidation::NormalizeTrendStrength(InpMinTrendStrength);
      m_config.market.allowSideways = InpAllowSidewaysTrading;
      m_config.market.regimeLotMultStrong = MarketValidation::NormalizeLotMultiplier(InpRegimeLotMultStrong, 1.0);
      m_config.market.regimeLotMultWeak = MarketValidation::NormalizeLotMultiplier(InpRegimeLotMultWeak, 1.0);
      m_config.market.regimeLotMultSide = MarketValidation::NormalizeLotMultiplier(InpRegimeLotMultSide, 1.0);
      m_config.market.regimeLotMultChop = MarketValidation::NormalizeLotMultiplier(InpRegimeLotMultChop, 1.0);
      
      // ATR & Spread
      m_config.market.atrPeriod = MarketValidation::NormalizeATRPeriod(InpATRPeriod);
      m_config.market.atrMin = EnsureNonNegative(InpATRMin, 0.0);
      m_config.market.atrMax = EnsureNonNegative(InpATRMax, m_config.market.atrMin);
      m_config.market.maxSpread = EnsureNonNegative(InpMaxSpread, 0.0);
      
      // Run domain-specific validation
      m_config.market.Validate();
   }
   
   void LoadNewsParams()
   {
      m_config.news.level = InpNewsLevel;
      m_config.news.freeze = ValidateIntRange(InpNewsFreezeMinutes, 0, 1440, 30);
      m_config.news.url = InpNewsWebURL;
      
      // Run domain-specific validation
      m_config.news.Validate();
   }
   
   void LoadRiskParams()
   {
      m_config.risk.autoLot = InpUseAutoLot;
      m_config.risk.pct = RiskValidation::NormalizeRiskPct(InpRiskPct);
      m_config.risk.lot = RiskValidation::NormalizeLotSize(InpLotSize);
      m_config.risk.maxDailyLoss = EnsureNonNegative(InpMaxDailyLossPct, 0.0);
      m_config.risk.magic = InpMagicNum;
      m_config.risk.entryMode = InpEntryMode;
      m_config.risk.tpslMode = InpTPSLMode;
      m_config.risk.useMTF = InpUseMTF;
      m_config.risk.htf = InpHTF;
      m_config.risk.htfLookback = ValidateIntRange(InpHTFLookback, 1, 1000, 100);
      m_config.risk.qualityLotMult = MarketValidation::NormalizeLotMultiplier(InpQualityLotMult, 1.0);
      
      // Cooldowns & limits
      m_config.risk.maxPositions = RiskValidation::NormalizeMaxPositions(InpMaxOpenPositions);
      m_config.risk.maxConsecutiveLoss = ValidateIntRange(InpMaxConsecutiveLoss, 0, 100, 0);
      m_config.risk.maxTradeDurationDays = ValidateIntRange(InpMaxTradeDurationDays, 0, 365, 0);
      m_config.risk.entryCooldownBars = ValidateIntRange(InpEntryCooldownBars, 0, 1000, 0);
      m_config.risk.signalCooldownBars = ValidateIntRange(InpSignalCooldownBars, 0, 1000, 0);
      m_config.risk.lossCooldownBars = ValidateIntRange(InpLossCooldownBars, 0, 1000, 0);
      
      // Run domain-specific validation
      m_config.risk.Validate();
   }
   
   void LoadSRParams()
   {
      m_config.sr.mode = InpSRMode;
      m_config.sr.lookback = ValidateIntRange(InpSRLookback, 10, 10000, 100);
      m_config.sr.swingLookback = ValidateIntRange(InpSwingLookback, 5, 500, 20);
      m_config.sr.touchBufferATR = InpSRTouchBufferATR;
      m_config.sr.minTouchesStrong = InpSRMinTouchesStrong;
      m_config.sr.minRangeATR = InpMinSRRangeATR;
      m_config.sr.atrBufferMult = InpATRBufferMult;
      m_config.sr.bufferMultStrong = InpBufferMultStrong;
      m_config.sr.bufferMultWeak = InpBufferMultWeak;
      m_config.sr.zoneReuseATR = InpZoneReuseATR;
      
      // Run domain-specific validation
      m_config.sr.Validate();
   }
   
   void LoadPatternParams()
   {
      m_config.pattern.lookback = ValidateIntRange(InpSignalLookback, 1, 500, 5);
      m_config.pattern.mtfConfluenceBonus = InpMTFConfluenceBonus;
      m_config.pattern.strongZoneBonus = InpStrongZoneBonus;
      m_config.pattern.strongZoneThreshold = InpStrongZoneThreshold;
      m_config.pattern.maxSignalATR = InpMaxSignalATR;
      m_config.pattern.momentumThresholdATR = InpMomentumThresholdATR;
      m_config.pattern.useWeights = InpUsePatternWeights;
      m_config.pattern.antiBreakoutPct = PatternValidation::NormalizeRatio(InpAntiBreakoutPct, 0.5);
      m_config.pattern.marubozuMinBodyPct = PatternValidation::NormalizeRatio(InpMarubozuMinBodyPct, 0.9);
      m_config.pattern.engulfingBodyMult = InpEngulfingBodyMult;
      m_config.pattern.minDominanceGap = InpMinDominanceGap;
      m_config.pattern.strongZoneBufferMult = InpStrongZoneBufferMult;
      m_config.pattern.useAdaptiveZoneBuffer = InpUseAdaptiveZoneBuffer;
      m_config.pattern.sensitivityATR = InpPatternSensitivityATR;
      m_config.pattern.starMiddleBodyMult = InpStarMiddleBodyMult;
      m_config.pattern.railroadMinBodyRatio = InpRailroadMinBodyRatio;
      m_config.pattern.failureCooldownBars = ValidateIntRange(InpPatternFailureCooldownBars, 0, 1000, 0);
      m_config.pattern.hqThreshold = InpHighQualityThreshold;
      m_config.pattern.useDynamicCooldown = InpUseDynamicCooldown;
      m_config.pattern.reducedCooldownBars = ValidateIntRange(InpReducedCooldownBars, 0, 1000, 0);
      
      // Scoring parameters
      m_config.pattern.baseScore = PatternValidation::NormalizeScore(InpPatternBaseScore, 0.0);
      m_config.pattern.bonusStrongATR = PatternValidation::NormalizeScore(InpPatternBonusStrongATRRange, 0.0);
      m_config.pattern.bonusStrongBody = PatternValidation::NormalizeScore(InpPatternBonusStrongBodyRatio, 0.0);
      m_config.pattern.bonusStrongWick = PatternValidation::NormalizeScore(InpPatternBonusStrongWickRejection, 0.0);
      m_config.pattern.bonusFollowThrough = PatternValidation::NormalizeScore(InpPatternBonusFollowThrough, 0.0);
      m_config.pattern.bonusGapConfirm = PatternValidation::NormalizeScore(InpPatternBonusGapConfirmation, 0.0);
      m_config.pattern.bonusBreakoutConfirm = PatternValidation::NormalizeScore(InpPatternBonusBreakoutConfirmation, 0.0);
      m_config.pattern.bonusSmall = PatternValidation::NormalizeScore(InpPatternBonusSmall, 0.0);
      
      // Thresholds
      m_config.pattern.atrRangeThreshold = InpPatternATRRangeThreshold;
      m_config.pattern.bodyRatioThreshold = InpPatternBodyRatioThreshold;
      m_config.pattern.wickRatioThreshold = InpPatternWickRatioThreshold;
      
      // Specific thresholds
      m_config.pattern.pinbarWickRatio = InpPinbarWickToOppositeWickRatio;
      m_config.pattern.insideBarRangeMax = InpInsideBarChildMotherRangeMax;
      m_config.pattern.starCloseMin = InpStarClosePositionMin;
      m_config.pattern.threeInsideBodyMin = InpThreeInsideBodyRatioMin;
      m_config.pattern.railroadAvgBodyMin = InpRailroadAvgBodyMinATR;
      m_config.pattern.railroadWickMult = InpRailroadWickRejectionMult;
      m_config.pattern.marubozuMinATRMult = InpMarubozuMinATRRangeMult;
      m_config.pattern.marubozuStrongATRMin = InpMarubozuStrongATRRangeMin;
      
      // SL Multipliers
      m_config.pattern.defaultSLMult = PatternValidation::NormalizeSLMultiplier(InpDefaultSLMult);
      m_config.pattern.pinbarSLMult = PatternValidation::NormalizeSLMultiplier(InpPinbarSLMult);
      m_config.pattern.insideBarSLMult = PatternValidation::NormalizeSLMultiplier(InpInsideBarSLMult);
      
      // Run domain-specific validation
      m_config.pattern.Validate();
   }
   
   void LoadRecoveryParams()
   {
      m_config.recovery.use = InpUseRecoveryMode;
      m_config.recovery.cooldownBars = RecoveryValidation::NormalizeCooldownBars(InpRecoveryCooldownBars, 3);
      m_config.recovery.maxAttempts = RecoveryValidation::NormalizeMaxAttempts(InpMaxRecoveryAttempts);
      m_config.recovery.lotMult = EnsureNonNegative(InpRecoveryLotMult, 1.0);
      m_config.recovery.scoreThreshold = InpRecoveryPatternScoreThreshold;
      m_config.recovery.zoneToleranceATR = InpRecoveryZoneToleranceATR;
      m_config.recovery.fakeoutSensitivity = RecoveryValidation::NormalizeSensitivity(InpFakeoutDetectionSensitivity);
      m_config.recovery.fakeoutSLAdjATR = InpFakeoutSLAdjustmentATR;
      
      // Safeguards
      m_config.recovery.maxRecoveryPositions = ValidateIntRange(InpMaxRecoveryPositions, 0, 10, 2);
      m_config.recovery.maxExposureMultiplier = EnsurePositive(InpMaxRecoveryExposureMult, 2.0);
      m_config.recovery.recoveryTimeoutBars = ValidateIntRange(InpRecoveryTimeoutBars, 0, 1000, 20);
      m_config.recovery.hardStopLossPct = ValidateRange(InpRecoveryHardStopPct, 0.0, 100.0, 3.0);
      
      // Run domain-specific validation
      m_config.recovery.Validate();
   }
   
   void LoadExitParams()
   {
      m_config.exit.useTrailing = InpUseTrailing;
      m_config.exit.usePartial = InpUsePartialClose;
      m_config.exit.exitOnOpposite = InpExitOnOpposite;
      m_config.exit.tpBufferATR = InpTPBufferATR;
      m_config.exit.slBufferATR = InpSLBufferATR;
      m_config.exit.minTPDistATR = InpMinTPDistanceATR;
      m_config.exit.maxTPDistATR = InpMaxTPDistanceATR;
      m_config.exit.trailingStartATR = EnsureNonNegative(InpTrailingStartATR, 1.5);
      m_config.exit.trailingBufferATR = InpTrailingBufferATR;
      m_config.exit.trailActivationATR = InpTrailActivationATR;
      m_config.exit.trailStepATR = InpTrailStepATR;
      m_config.exit.lockProfitATR = InpLockProfitATR;
      m_config.exit.lockOffsetATR = InpLockOffsetATR;
      m_config.exit.partialLotPct = ValidateRange(InpPartialCloseLotPct, 1.0, 100.0, 50.0);
      m_config.exit.partialATR = InpPartialCloseATR;
      
      // Run domain-specific validation
      m_config.exit.Validate();
   }
   
   void LoadAIParams()
   {
      m_config.ai.use = InpUseAI;
      m_config.ai.trainingWindow = ValidateIntRange(InpAITrainingWindowBars, 10, 10000, 200);
      m_config.ai.minConfidence = InpAIMinConfidence;
      m_config.ai.patternBonus = InpAIPatternBonus;
      
      // Run domain-specific validation
      m_config.ai.Validate();
   }
   
   void LoadSystemParams()
   {
      m_config.system.debug = InpDebugMode;
      m_config.system.safe = InpSafeMode;
      m_config.system.orderThrottleMs = ValidateIntRange(InpOrderThrottleMs, 0, 10000, 100);
      
      // Run domain-specific validation
      m_config.system.Validate();
   }
};

// Static member initialization
ConfigManager *ConfigManager::m_instance = NULL;

// Global accessor function (read-only access to config)
const StrategyConfig& GetConfig()
{
   return ConfigManager::GetInstance()->GetConfig();
}

// Macro for convenient read-only access to global config
#define CFG GetConfig()

// Backward compatibility wrapper - deprecated, use ConfigManager::GetInstance()->Reload() instead
void SetCommonDefaults()
{
   ConfigManager::GetInstance()->Reload();
}

//+------------------------------------------------------------------+
//| PrintConfigSummary - Display active configuration in debug mode  |
//+------------------------------------------------------------------+
void PrintConfigSummary()
{
   const StrategyConfig &cfg = GetConfig();
   
   if(!cfg.system.debug)
      return;

   Print("=== PASR CONFIG ACTIVE ===");
   Print("ATR Period       : ", cfg.market.atrPeriod);
   Print("ATR Range        : ", DoubleToString(cfg.market.atrMin, 1), " - ", DoubleToString(cfg.market.atrMax, 1));
   Print("SR Mode          : ", (string)cfg.sr.mode);
   Print("Risk %           : ", DoubleToString(cfg.risk.pct, 2));
   Print("Magic Number     : ", cfg.risk.magic);
   Print("Signal Lookback  : ", cfg.pattern.lookback);
   Print("Recovery Mode    : ", (cfg.recovery.use ? "Enabled" : "Disabled"));
   if(cfg.recovery.use) {
      Print("  Fakeout Sensitivity: ", DoubleToString(cfg.recovery.fakeoutSensitivity, 2));
   }
   Print("Use MTF          : ", (cfg.risk.useMTF ? "true" : "false"));
   Print("Use Trailing     : ", (cfg.exit.useTrailing ? "true" : "false"));
}

//+------------------------------------------------------------------+
//| RecoveryEngine - Mengelola state persistensi untuk satu posisi  |
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

   // Recovery Mode fields
   double slHitPrice;
   datetime slHitTime;
   double originalEntry;
   double originalSL;
   double originalTP;
   double originalLot;
   int recoveryAttempts;
   datetime recoveryCooldownExpiry;

   void SaveState() const // Removed magic parameter, use CFG.risk.magic directly
   {
      if (mainTicket <= 0)
         return;
   string p = "PASR_" + IntegerToString(CFG.risk.magic) + "_" + IntegerToString(mainTicket) + "_";

      GlobalVariableSet(p + "v2", 2.0);
      GlobalVariableSet(p + "st", (double)state);
      GlobalVariableSet(p + "ep", entryPrice);
      GlobalVariableSet(p + "it", initialTP);
      GlobalVariableSet(p + "bs", brokerSL);
      GlobalVariableSet(p + "zp", zonePrice);
      GlobalVariableSet(p + "dr", (double)direction);
      GlobalVariableSet(p + "at", lastKnownATR);
      GlobalVariableSet(p + "pk", peakEquity);
      GlobalVariableSet(p + "tm", (double)entryTime);
      GlobalVariableSet(p + "pc", (double)partialClosed);
      GlobalVariableSet(p + "an", (double)partialArmedNormal);
      GlobalVariableSet(p + "lo", lot);
      GlobalVariableSet(p + "sm", slMultiplier);
      GlobalVariableSet(p + "ak", (double)lastActionTick);

      // Recovery fields
      GlobalVariableSet(p + "sh", slHitPrice);
      GlobalVariableSet(p + "sht", (double)slHitTime);
      GlobalVariableSet(p + "oe", originalEntry);
      GlobalVariableSet(p + "os", originalSL);
      GlobalVariableSet(p + "ot", originalTP);
      GlobalVariableSet(p + "ol", originalLot);
      GlobalVariableSet(p + "ra", (double)recoveryAttempts);
      GlobalVariableSet(p + "rc", (double)recoveryCooldownExpiry);
   }

   void LoadState(ulong ticket)
   {
      string p = "PASR_" + IntegerToString(CFG.risk.magic) + "_" + IntegerToString(ticket) + "_";
      if (GlobalVariableCheck(p + "v2"))
      {
         mainTicket = ticket;
         state = (ENUM_TRADE_STATE)(int)GlobalVariableGet(p + "st");
         entryPrice = GlobalVariableGet(p + "ep");
         initialTP = GlobalVariableGet(p + "it");
         brokerSL = GlobalVariableGet(p + "bs");
         zonePrice = GlobalVariableGet(p + "zp");
         direction = (int)GlobalVariableGet(p + "dr");
         lastKnownATR = GlobalVariableGet(p + "at");
         peakEquity = GlobalVariableGet(p + "pk");
         entryTime = (datetime)GlobalVariableGet(p + "tm");
         partialClosed = (GlobalVariableGet(p + "pc") > 0.5);
         partialArmedNormal = (GlobalVariableGet(p + "an") > 0.5);
         lot = GlobalVariableGet(p + "lo");
         slMultiplier = GlobalVariableGet(p + "sm");
         lastActionTick = (ulong)GlobalVariableGet(p + "ak");

         // Recovery fields
         slHitPrice = GlobalVariableGet(p + "sh");
         slHitTime = (datetime)GlobalVariableGet(p + "sht");
         originalEntry = GlobalVariableGet(p + "oe");
         originalSL = GlobalVariableGet(p + "os");
         originalTP = GlobalVariableGet(p + "ot");
         originalLot = GlobalVariableGet(p + "ol");
         recoveryAttempts = (int)GlobalVariableGet(p + "ra");
         recoveryCooldownExpiry = (datetime)GlobalVariableGet(p + "rc");

         double pcDist = lastKnownATR * CFG.exit.partialATR * _Point;
         partialTP = NormalizeDouble(entryPrice + ((direction == 1 ? 1.0 : -1.0) * pcDist), _Digits);
         active = true;
      }
   }

   void ClearGVs()
   {
      if (mainTicket <= 0)
         return;
      string p = "PASR_" + IntegerToString(CFG.risk.magic) + "_" + IntegerToString(mainTicket) + "_";
      GlobalVariablesDeleteAll(p);
   }

   void Reset()
   {
      active = false;
      mainTicket = 0;
      direction = 0;
      state = TRADE_STATE_NONE;
      entryTime = 0;
      entryPrice = 0.0;
      zonePrice = 0.0;
      initialTP = 0.0;
      brokerSL = 0.0;
      partialTP = 0.0;
      slMultiplier = 1.0;
      lastKnownATR = 0.0;
      lot = 0.0;
      peakEquity = 0.0;
      partialClosed = false;
      partialArmedNormal = false;
      lastActionTick = 0;

      // Recovery Reset
      slHitPrice = 0.0;
      slHitTime = 0;
      originalEntry = 0.0;
      originalSL = 0.0;
      originalTP = 0.0;
      originalLot = 0.0;
      recoveryAttempts = 0;
      recoveryCooldownExpiry = 0;
   }

   RecoveryEngine() { Reset(); }
};

#endif // __CONFIG_MQH__