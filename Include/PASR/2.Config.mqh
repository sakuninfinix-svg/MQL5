//+------------------------------------------------------------------+
//|                            Price Action & Support Ressistance V1 |
//|                                                       Config.mqh |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "1.00"
#property strict

#ifndef __CONFIG_MQH__
#define __CONFIG_MQH__

//+------------------------------------------------------------------+
//| ENUMS: System & Strategy Definitions                             |
//+------------------------------------------------------------------+

/**
 * Jenis Pola Price Action yang Didukung
 */
enum ENUM_PATTERN_TYPE
{
   PATTERN_NONE,
   PATTERN_PINBAR,
   PATTERN_ENGULFING,
   PATTERN_BOTTOM,
   PATTERN_FAKEY,
   PATTERN_INSIDE_BAR_BREAKOUT,
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
input string InpSessionSun;                                            // Minggu   (0=Off JAM:MENIT-JJ:MM=on)
input string InpSessionMon;                                           // Senin    (0=Off JAM:MENIT-JJ:MM=on)
input string InpSessionTue;                                            // Selasa   (0=Off JAM:MENIT-JJ:MM=on)
input string InpSessionWed;                                            // Rabu     (0=Off JAM:MENIT-JJ:MM=on)
input string InpSessionThu;                                            // Kamis    (0=Off JAM:MENIT-JJ:MM=on)
input string InpSessionFri;                                            // Jumat    (0=Off JAM:MENIT-JJ:MM=on)
input string InpSessionSat;                                                      // Sabtu    (0=Off JAM:MENIT-JJ:MM=on)
input ENUM_NEWS_LEVEL InpNewsLevel;                                                    // Filter Berita (NEWS_OFF = Nonaktif)
input int InpNewsFreezeMinutes;                                                        // News Freeze (Menit sebelum/sesudah)
input string InpNewsWebURL; // URL Kalender Berita ex "https://nfs.faireconomy.media/ff_calendar_thisweek.xml"

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
//| STRATEGY CONFIG: Global Access Object                            |
//+------------------------------------------------------------------+
struct StrategyConfig
{
    struct Market {
      int atrPeriod;
      double atrMin;
      double atrMax;
      double maxSpread;
      string sessions[7];
   } market;

   struct News {
      bool use; // Added missing parameter
      ENUM_NEWS_LEVEL level;
      int freeze;
      string url;
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
   } exit;

   struct AI {
      bool use;
      int trainingWindow;
      double minConfidence;
      double patternBonus;
   } ai;

   struct System {
      bool debug;
      bool safe;
      int orderThrottleMs;
   } system;
};

StrategyConfig CFG;

void SetCommonDefaults()
{
// Market & Sessions
   CFG.market.atrPeriod = InpATRPeriod;
   CFG.market.atrMin = InpATRMin;
   CFG.market.atrMax = InpATRMax;
   CFG.market.maxSpread = InpMaxSpread;
   CFG.market.sessions[0] = InpSessionSun;
   CFG.market.sessions[1] = InpSessionMon;
   CFG.market.sessions[2] = InpSessionTue;
   CFG.market.sessions[3] = InpSessionWed;
   CFG.market.sessions[4] = InpSessionThu;
   CFG.market.sessions[5] = InpSessionFri;
   CFG.market.sessions[6] = InpSessionSat;

   // News
   CFG.news.use = (InpNewsLevel != NEWS_OFF); // Assigned here
   CFG.news.level = InpNewsLevel;
   CFG.news.freeze = InpNewsFreezeMinutes;
   CFG.news.url = InpNewsWebURL;

   // Risk & Account
   CFG.risk.autoLot = InpUseAutoLot;
   CFG.risk.pct = InpRiskPct;
   CFG.risk.lot = InpLotSize;
   CFG.risk.maxDailyLoss = InpMaxDailyLossPct;
   CFG.risk.magic = InpMagicNum;
   CFG.risk.entryMode = InpEntryMode;
   CFG.risk.tpslMode = InpTPSLMode;
   CFG.risk.useMTF = InpUseMTF;
   CFG.risk.htf = InpHTF;
   CFG.risk.htfLookback = InpHTFLookback;
   CFG.risk.qualityLotMult = InpQualityLotMult;
   CFG.risk.maxPositions = InpMaxOpenPositions;
   CFG.risk.maxConsecutiveLoss = InpMaxConsecutiveLoss;
   CFG.risk.maxTradeDurationDays = InpMaxTradeDurationDays;
   CFG.risk.entryCooldownBars = InpEntryCooldownBars;
   CFG.risk.signalCooldownBars = InpSignalCooldownBars;
   CFG.risk.lossCooldownBars = InpLossCooldownBars;

   // SR Engine
   CFG.sr.mode = InpSRMode;
   CFG.sr.lookback = InpSRLookback;
   CFG.sr.swingLookback = InpSwingLookback;
   CFG.sr.touchBufferATR = InpSRTouchBufferATR;
   CFG.sr.minTouchesStrong = InpSRMinTouchesStrong;
   CFG.sr.minRangeATR = InpMinSRRangeATR;
   CFG.sr.atrBufferMult = InpATRBufferMult;
   CFG.sr.bufferMultStrong = InpBufferMultStrong;
   CFG.sr.bufferMultWeak = InpBufferMultWeak;
   CFG.sr.zoneReuseATR = InpZoneReuseATR;

   // Patterns
   CFG.pattern.lookback = InpSignalLookback;
   CFG.pattern.mtfConfluenceBonus = InpMTFConfluenceBonus;
   CFG.pattern.strongZoneBonus = InpStrongZoneBonus;
   CFG.pattern.strongZoneThreshold = InpStrongZoneThreshold;
   CFG.pattern.maxSignalATR = InpMaxSignalATR;
   CFG.pattern.momentumThresholdATR = InpMomentumThresholdATR;
   CFG.pattern.useWeights = InpUsePatternWeights;
   CFG.pattern.antiBreakoutPct = InpAntiBreakoutPct;
   CFG.pattern.marubozuMinBodyPct = InpMarubozuMinBodyPct;
   CFG.pattern.engulfingBodyMult = InpEngulfingBodyMult;
   CFG.pattern.minDominanceGap = InpMinDominanceGap;
   CFG.pattern.strongZoneBufferMult = InpStrongZoneBufferMult;
   CFG.pattern.useAdaptiveZoneBuffer = InpUseAdaptiveZoneBuffer;
   CFG.pattern.sensitivityATR = InpPatternSensitivityATR;
   CFG.pattern.starMiddleBodyMult = InpStarMiddleBodyMult;
   CFG.pattern.railroadMinBodyRatio = InpRailroadMinBodyRatio;
   CFG.pattern.failureCooldownBars = InpPatternFailureCooldownBars;
   CFG.pattern.hqThreshold = InpHighQualityThreshold;
   CFG.pattern.useDynamicCooldown = InpUseDynamicCooldown;
   CFG.pattern.reducedCooldownBars = InpReducedCooldownBars;
   // Scoring
   CFG.pattern.baseScore = InpPatternBaseScore;
   CFG.pattern.bonusStrongATR = InpPatternBonusStrongATRRange;
   CFG.pattern.bonusStrongBody = InpPatternBonusStrongBodyRatio;
   CFG.pattern.bonusStrongWick = InpPatternBonusStrongWickRejection;
   CFG.pattern.bonusFollowThrough = InpPatternBonusFollowThrough;
   CFG.pattern.bonusGapConfirm = InpPatternBonusGapConfirmation;
   CFG.pattern.bonusBreakoutConfirm = InpPatternBonusBreakoutConfirmation;
   CFG.pattern.bonusSmall = InpPatternBonusSmall;
   // Thresholds
   CFG.pattern.atrRangeThreshold = InpPatternATRRangeThreshold;
   CFG.pattern.bodyRatioThreshold = InpPatternBodyRatioThreshold;
   CFG.pattern.wickRatioThreshold = InpPatternWickRatioThreshold;
   // Specifics
   CFG.pattern.pinbarWickRatio = InpPinbarWickToOppositeWickRatio;
   CFG.pattern.insideBarRangeMax = InpInsideBarChildMotherRangeMax;
   CFG.pattern.starCloseMin = InpStarClosePositionMin;
   CFG.pattern.threeInsideBodyMin = InpThreeInsideBodyRatioMin;
   CFG.pattern.railroadAvgBodyMin = InpRailroadAvgBodyMinATR;
   CFG.pattern.railroadWickMult = InpRailroadWickRejectionMult;
   CFG.pattern.marubozuMinATRMult = InpMarubozuMinATRRangeMult;
   CFG.pattern.marubozuStrongATRMin = InpMarubozuStrongATRRangeMin;
   // SL Multipliers
   CFG.pattern.defaultSLMult = InpDefaultSLMult;
   CFG.pattern.pinbarSLMult = InpPinbarSLMult;
   CFG.pattern.insideBarSLMult = InpInsideBarSLMult;

   // Recovery
   CFG.recovery.use = InpUseRecoveryMode;
   CFG.recovery.cooldownBars = InpRecoveryCooldownBars;
   CFG.recovery.maxAttempts = InpMaxRecoveryAttempts;
   CFG.recovery.lotMult = InpRecoveryLotMult;
   CFG.recovery.scoreThreshold = InpRecoveryPatternScoreThreshold;
   CFG.recovery.zoneToleranceATR = InpRecoveryZoneToleranceATR;
   CFG.recovery.fakeoutSensitivity = InpFakeoutDetectionSensitivity;
   CFG.recovery.fakeoutSLAdjATR = InpFakeoutSLAdjustmentATR;

   // Exit & Trailing
   CFG.exit.useTrailing = InpUseTrailing;
   CFG.exit.usePartial = InpUsePartialClose;
   CFG.exit.exitOnOpposite = InpExitOnOpposite;
   CFG.exit.tpBufferATR = InpTPBufferATR;
   CFG.exit.slBufferATR = InpSLBufferATR;
   CFG.exit.minTPDistATR = InpMinTPDistanceATR;
   CFG.exit.maxTPDistATR = InpMaxTPDistanceATR;
   CFG.exit.trailingStartATR = InpTrailingStartATR;
   CFG.exit.trailingBufferATR = InpTrailingBufferATR;
   CFG.exit.trailActivationATR = InpTrailActivationATR;
   CFG.exit.trailStepATR = InpTrailStepATR;
   CFG.exit.lockProfitATR = InpLockProfitATR;
   CFG.exit.lockOffsetATR = InpLockOffsetATR;
   CFG.exit.partialLotPct = InpPartialCloseLotPct;
   CFG.exit.partialATR = InpPartialCloseATR;

   // AI
   CFG.ai.use = InpUseAI;
   CFG.ai.trainingWindow = InpAITrainingWindowBars;
   CFG.ai.minConfidence = InpAIMinConfidence;
   CFG.ai.patternBonus = InpAIPatternBonus;

   // System
   CFG.system.debug = InpDebugMode;
   CFG.system.safe = InpSafeMode;
   CFG.system.orderThrottleMs = InpOrderThrottleMs;
}

void PrintConfigSummary()
{
   if (!CFG.system.debug)
      return;

   Print("=== PASR CONFIG ACTIVE ===");
   Print("ATR Period       : ", CFG.market.atrPeriod);
   Print("ATR Range        : ", DoubleToString(CFG.market.atrMin, 1), " - ", DoubleToString(CFG.market.atrMax, 1));
   Print("SR Mode          : ", (string)CFG.sr.mode);
   Print("Signal Lookback  : ", CFG.pattern.lookback);
   Print("Use MTF          : ", (CFG.risk.useMTF ? "true" : "false"));
   Print("Use Trailing     : ", (CFG.exit.useTrailing ? "true" : "false"));
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
      string p = "PASR_" + (string)CFG.risk.magic + "_" + (string)mainTicket + "_";
      GlobalVariablesDeleteAll(p);
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

   void LoadState(ulong ticket) // Removed magic parameter
   {
      string p = "PASR_" + (string)CFG.risk.magic + "_" + (string)ticket + "_";
      if (GlobalVariableCheck(p + "v2"))
      {
         mainTicket = ticket;
         state = (ENUM_TRADE_STATE)((int)GlobalVariableGet(p + "st"));
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