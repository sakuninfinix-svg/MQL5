//+------------------------------------------------------------------+
//|                            Price Action & Support Ressistance V1 |
//|                                                       Config.mqh |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"

#ifndef __CONFIG_MQH__
#define __CONFIG_MQH__

#property link "agsicentre.wordpress.com"
#property version "1.00"
#property strict

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
input string InpSessionSun = "00:00-24:00";            // Sesi Minggu   (0=Off JAM:MENIT-JJ:MM=on)
input string InpSessionMon = "00:00-24:00";            // Sesi Senin    (0=Off JAM:MENIT-JJ:MM=on)
input string InpSessionTue = "00:00-24:00";            // Sesi Selasa   (0=Off JAM:MENIT-JJ:MM=on)
input string InpSessionWed = "00:00-24:00";            // Sesi Rabu     (0=Off JAM:MENIT-JJ:MM=on)
input string InpSessionThu = "00:00-24:00";            // Sesi Kamis    (0=Off JAM:MENIT-JJ:MM=on)
input string InpSessionFri = "00:00-24:00";            // Sesi Jumat    (0=Off JAM:MENIT-JJ:MM=on)
input string InpSessionSat = "0";                      // Sesi Sabtu    (0=Off JAM:MENIT-JJ:MM=on)
input ENUM_NEWS_LEVEL InpNewsLevel = NEWS_HIGH_MEDIUM; // Filter Berita (NEWS_OFF = Nonaktif)
input int InpNewsFreezeMinutes = 60;                   // News Freeze (Menit sebelum/sesudah)
input string InpNewsWebURL = "https://nfs.faireconomy.media/ff_calendar_thisweek.xml";

// [GROUP] RISK MANAGEMENT
input bool InpUseAutoLot = true;       // Gunakan AutoLot (Risk %)
input double InpRiskPct = 1.0;         // Risiko % per Trade
input double InpLotSize = 0.01;        // Lot Statis (jika AutoLot OFF)
input double InpMaxDailyLossPct = 5.0; // Batas Maksimal Loss Harian (%)
input ulong InpMagicNum = 20260403;    // ID Transaksi Magic

// [GROUP] STRATEGY MODE & MTF
input ENUM_ENTRY_MODE InpEntryMode = MODE_SAFE; // Mode Entry (Safe/Aggressive)
input ENUM_TPSL_MODE InpTPSLMode = TPSL_SR;     // Mode Penentuan TP/SL
input bool InpUseMTF = false;                   // Gunakan Filter Multi-Timeframe (HTF)
input ENUM_TIMEFRAMES InpHTF = PERIOD_H1;       // Higher Timeframe (HTF)
input int InpHTFLookback = 50;                  // HTF Lookback (Candles)
input double InpQualityLotMult = 0.5;           // Multiplier Lot Sinyal Lemah

// [GROUP] SUPPORT & RESISTANCE (SR) ENGINE
input ENUM_SR_MODE InpSRMode = SR_AUTO; // Mode Deteksi SR
input int InpSRLookback = 20;           // SR Lookback (Candles)
input int InpSwingLookback = 50;        // Swing/Fractal Lookback
input double InpSRTouchBufferATR = 0.5; // Toleransi Sentuhan Zona (ATR x)
input int InpSRMinTouchesStrong = 3;    // Min Sentuhan Zona Kuat
input double InpMinSRRangeATR = 0.5;    // Min Range Antar Zona (ATR x)
input double InpATRBufferMult = 0.5;    // Global ATR Buffer Mult
input double InpBufferMultStrong = 0.3; // Strong Zone Buffer Mult
input double InpBufferMultWeak = 0.8;   // Weak Zone Buffer Mult

// [GROUP] SIGNAL DETECTION & PATTERNS
input int InpSignalLookback = 5;             // Scan Pattern (Lookback Bar)
input double InpMTFConfluenceBonus = 0.5;    // Bonus Skor Jika Searah/Aligned HTF
input double InpStrongZoneBonus = 0.2;       // Bonus Skor di Zona Kuat
input double InpStrongZoneThreshold = 0.4;   // Ambang Multiplier Zona Kuat
input double InpMaxSignalATR = 1.8;          // Max Ukuran Candle Sinyal (ATR x)
input double InpMomentumThresholdATR = 0.15; // Threshold Dorongan Momentum (ATR x)
input bool InpUsePatternWeights = true;      // Gunakan Bobot Historis Pattern
input double InpAntiBreakoutPct = 0.85;      // Batas Body Ratio (Anti-Breakout)
input double InpMarubozuMinBodyPct = 0.90;   // Minimal Body Marubozu (0.9 = 90%)
input double InpEngulfingBodyMult = 1.2;     // Rasio Tubuh Engulfing
input double InpMinDominanceGap = 0.2;       // Minimal Selisih Skor Dominansi
input double InpStrongZoneBufferMult = 0.7;  // Buffer multiplier untuk zona kuat
input bool InpUseAdaptiveZoneBuffer = true;  // Buffer zona adaptif berdasarkan strength
input double InpPatternSensitivityATR = 0.2; // Toleransi Gap & Aliansi Pattern (ATR x)
input double InpStarMiddleBodyMult = 0.5;    // Rasio Maksimal Candle Tengah Star
input double InpRailroadMinBodyRatio = 1.5;  // Min ratio body untuk Railroad Tracks
input double InpZoneReuseATR = 0.20;         // Jarak Reuse Zona (ATR x)

// NEW: Generic Pattern Scoring Parameters
input double InpPatternBaseScore = 1.0;                  // Skor dasar untuk setiap pola valid
input double InpPatternBonusStrongATRRange = 0.15;       // Bonus untuk candle dengan range ATR signifikan
input double InpPatternBonusStrongBodyRatio = 0.10;      // Bonus untuk candle dengan rasio body signifikan (misal: body kecil untuk rejection)
input double InpPatternBonusStrongWickRejection = 0.20;  // Bonus untuk candle dengan rejection wick signifikan
input double InpPatternBonusFollowThrough = 0.10;        // Bonus untuk candle follow-through (misal: close searah dengan bias)
input double InpPatternBonusGapConfirmation = 0.20;      // Bonus untuk konfirmasi gap (misal: pola Star)
input double InpPatternBonusBreakoutConfirmation = 0.15; // Bonus untuk konfirmasi breakout (misal: pola Three Inside)
input double InpPatternBonusSmall = 0.05;                // Bonus kecil untuk pengakuan pola dasar

// NEW: Generic Pattern Thresholds
input double InpPatternATRRangeThreshold = 0.6;   // Faktor ATR untuk candle dianggap "range signifikan" (misal: range > 0.6 * ATR)
input double InpPatternBodyRatioThreshold = 0.35; // Rasio Body/Range untuk candle dianggap "body kecil" (misal: untuk rejection)
input double InpPatternWickRatioThreshold = 0.5;  // Rasio Wick/Range untuk candle dianggap "rejection signifikan" (misal: wick > 0.5 * range)

// NEW: Pattern-Specific Thresholds (hanya jika berbeda dari umum atau unik)
input double InpPinbarWickToOppositeWickRatio = 2.0; // Rasio min wick utama terhadap wick berlawanan untuk Pinbar
input double InpInsideBarChildMotherRangeMax = 0.65; // Rasio maks range child bar terhadap mother bar untuk Inside Bar
input double InpStarClosePositionMin = 0.6;          // Posisi close min untuk pola Star (misal: close di 60% atas/bawah range)
input double InpThreeInsideBodyRatioMin = 1.3;       // Rasio min body candle breakout terhadap body mother bar untuk Three Inside
input double InpRailroadAvgBodyMinATR = 0.7;         // Ukuran body rata-rata min relatif terhadap ATR untuk Railroad Tracks
input double InpRailroadWickRejectionMult = 0.3;     // Multiplier min rejection wick relatif terhadap body untuk Railroad Tracks
input double InpMarubozuMinATRRangeMult = 4.0;       // Multiplier untuk MomentumThresholdATR untuk range min Marubozu
input double InpMarubozuStrongATRRangeMin = 1.2;     // Faktor ATR min untuk bonus ekstra pada Marubozu

// [GROUP] RECOVERY MODE & FAKEOUT PROTECTION
input bool InpUseRecoveryMode = true;                // Aktifkan mode recovery setelah SL hit (includes fakeout detection)
input int InpRecoveryCooldownBars = 3;               // Cooldown bars setelah SL hit sebelum mencari re-entry
input int InpMaxRecoveryAttempts = 2;                // Maksimal percobaan re-entry untuk satu posisi
input double InpRecoveryLotMult = 1.0;               // Multiplier lot untuk re-entry
input double InpRecoveryPatternScoreThreshold = 0.8; // Skor minimal pattern untuk re-entry (lowered for more opportunities)
input double InpRecoveryZoneToleranceATR = 0.7;      // Toleransi ATR dari SL hit price untuk mencari re-entry
input double InpFakeoutDetectionSensitivity = 0.3;   // Sensitivitas deteksi fakeout (0.2-0.5, lower = more sensitive)
input double InpFakeoutSLAdjustmentATR = 1.5;        // Adjustment SL saat fakeout terdeteksi (ATR multiplier)

// [GROUP] PATTERN SPECIFIC VOLATILITY (SL MULTIPLIERS)
input double InpDefaultSLMult = 1.0;                  // SL Mult Standar
input double InpPinbarSLMult = 1.5;                   // SL Mult khusus Pinbar
input double InpInsideBarSLMult = 1.2;                // SL Mult khusus Inside Bar

// [GROUP] COOLDOWNS & PROTECTION
input int InpMaxOpenPositions = 3;            // Max Posisi Berjalan
input int InpMaxConsecutiveLoss = 2;          // Batas Loss Beruntun
input int InpMaxTradeDurationDays = 5;        // Durasi Maksimal Trade (Hari)
input int InpEntryCooldownBars = 1;           // Cooldown Antar Entry (Bars)
input int InpSignalCooldownBars = 5;          // Cooldown Sinyal Area (Bars)
input int InpLossCooldownBars = 3;            // Cooldown Setelah Loss (Bars)
input int InpPatternFailureCooldownBars = 10; // Cooldown Level Gagal (Bars)
input double InpHighQualityThreshold = 1.8;   // Skor Setup Premium (Bypass Cooldown)
input bool InpUseDynamicCooldown = true;      // Aktifkan Cooldown Adaptif HQ
input int InpReducedCooldownBars = 2;         // Cooldown untuk HQ Setup

// [GROUP] EXECUTION, TRAILING & RECOVERY
input double InpMaxSpread = 300.0;        // Batas Maksimal Spread (Points)
input int InpOrderThrottleMs = 2000;      // Throttle Eksekusi (ms)
input bool InpUseTrailing = true;         // Aktifkan Trailing Stop
input bool InpUsePartialClose = true;     // Aktifkan Partial Close
input bool InpExitOnOpposite = true;      // Close Jika Muncul Sinyal Lawan
input double InpTPBufferATR = 0.2;        // TP Buffer Dalam Zona (ATR x)
input double InpSLBufferATR = 0.2;        // SL Buffer Luar Zona (ATR x)
input double InpMinTPDistanceATR = 0.3;   // Min Jarak TP (ATR x)
input double InpMaxTPDistanceATR = 3.0;   // Max Jarak TP (ATR x)
input double InpTrailingStartATR = 0.5;   // Trailing Start (ATR x)
input double InpTrailingBufferATR = 0.05; // Jarak Aman Buffer (ATR x)
input double InpTrailActivationATR = 1.8; // Aktivasi Trailing (ATR x)
input double InpTrailStepATR = 0.7;       // Trailing Step (ATR x)
input double InpLockProfitATR = 1.2;      // Lock Profit Activation (ATR x)
input double InpLockOffsetATR = 0.15;     // Profit Terkunci (ATR x)
input double InpPartialCloseLotPct = 0.5; // % Lot Partial Close
input double InpPartialCloseATR = 0.25;   // Target Partial TP (ATR x)

// [GROUP] SYSTEM & DEBUG
input bool InpDebugMode = true;  // Log Debug ke Konsol
input bool InpSafeMode = true;   // Aktifkan Proteksi Safe Mode
input int InpATRPeriod = 14;     // Periode ATR
input double InpATRMin = 150.0;  // Batas Bawah Volatilitas (Points)
input double InpATRMax = 4000.0; // Batas Atas Volatilitas (Points)

//+------------------------------------------------------------------+
//| STRATEGY CONFIG: Global Access Object                            |
//+------------------------------------------------------------------+
struct StrategyConfig
{
   // --- Market & Account ---
   int ATRPeriod;
   double ATRMin;
   double ATRMax;
   string TradingSessions[7];
   bool UseAutoLot;
   double RiskPct;
   double LotSize;
   double MaxDailyLossPct;

   // --- News Filter ---
   bool UseNews;
   int NewsFreeze;
   ENUM_NEWS_LEVEL NewsLevel;
   string NewsWebURL;

   ENUM_ENTRY_MODE EntryMode;
   ENUM_TPSL_MODE TPSLMode;
   int OrderThrottleMs;
   bool UseMTF;
   ENUM_TIMEFRAMES HTF;
   int HTFLookback;
   double QualityLotMult;

   // --- SR Engine ---
   ENUM_SR_MODE SRMode;
   int SRLookback;
   int SwingLookback;
   double SRTouchBufferATR;
   int SRMinTouchesStrong;
   double MinSRRangeATR;
   double ATRBufferMult;
   double BufferMultStrong;
   double BufferMultWeak;

   // --- Signal & Pattern Detection ---
   int SignalLookback;
   double MTFConfluenceBonus;
   double StrongZoneBonus;
   double StrongZoneThreshold;
   double MaxSignalATR;
   double MinDominanceGap;
   double MomentumThresholdATR;
   bool UsePatternWeights;
   double AntiBreakoutPct;
   double EngulfingBodyMult;
   double MarubozuMinBodyPct;
   double StrongZoneBufferMult;
   bool UseAdaptiveZoneBuffer;
   double PatternSensitivityATR;
   double StarMiddleBodyMult;
   // --- Generic Pattern Scoring ---
   double PatternBaseScore;
   double PatternBonusStrongATRRange;
   double PatternBonusStrongBodyRatio;
   double PatternBonusStrongWickRejection;
   double PatternBonusFollowThrough;
   double PatternBonusGapConfirmation;
   double PatternBonusBreakoutConfirmation;
   double PatternBonusSmall;
   double PatternATRRangeThreshold;
   double PatternBodyRatioThreshold;
   double PatternWickRatioThreshold;

   // --- Pattern Specific Thresholds ---
   double PinbarWickToOppositeWickRatio;  
   double InsideBarChildMotherRangeMax;
   double StarClosePositionMin;
   int StarMiddleBarLookback;
   double ThreeInsideBodyRatioMin;
   double RailroadAvgBodyMinATR;
   double RailroadWickRejectionMult;
   double RailroadMinBodyRatio;
   double MarubozuMinATRRangeMult;
   double MarubozuStrongATRRangeMin;

   // --- Recovery & Fakeout ---
   bool UseRecoveryMode;
   int RecoveryCooldownBars;
   int MaxRecoveryAttempts;
   double RecoveryLotMult;
   double RecoveryPatternScoreThreshold;
   double RecoveryZoneToleranceATR;
   double FakeoutDetectionSensitivity;
   double FakeoutSLAdjustmentATR;

   // --- SL Multipliers ---
   double DefaultSLMult;
   double PinbarSLMult;
   double InsideBarSLMult;

   int MaxPositions;
   int MaxTradeDurationDays;
   int EntryCooldownBars;
   int SignalCooldownBars;
   int LossCooldownBars;
   int PatternFailureCooldownBars;
   int MaxConsecutiveLoss;
   double HighQualityThreshold;
   bool UseDynamicCooldown;
   int ReducedCooldownBars;

   // --- Execution & Exit ---
   double MaxSpread;
   bool UseTrailing;
   bool UsePartialClose;
   bool ExitOnOpposite;
   double SLBufferATR;
   double TPBufferATR;
   double MinTPDistanceATR;
   double MaxTPDistanceATR;
   double TrailingStartATR;
   double TrailingBufferATR;
   double TrailActivationATR;
   double TrailStepATR;
   double LockProfitATR;
   double LockOffsetATR;

   double PartialCloseLotPct;
   double PartialCloseATR;
   double ZoneReuseATR;

   // --- System ---
   bool DebugMode;
   bool SafeMode;
   ulong MagicNum;
};

StrategyConfig CFG;

// ------------------------------------------------------------
//| INITIALIZATION: Map Inputs to Config Struct                      |
//+------------------------------------------------------------------+
void SetCommonDefaults()
{
   // --- Market & Risk ---
   CFG.ATRPeriod = InpATRPeriod;
   CFG.ATRMin = InpATRMin;
   CFG.ATRMax = InpATRMax;
   CFG.MaxSpread = InpMaxSpread;
   CFG.UseAutoLot = InpUseAutoLot;
   CFG.RiskPct = InpRiskPct;
   CFG.LotSize = InpLotSize;
   CFG.MaxDailyLossPct = InpMaxDailyLossPct;
   CFG.MagicNum = InpMagicNum;

   // --- Sessions ---
   CFG.TradingSessions[0] = InpSessionSun;
   CFG.TradingSessions[1] = InpSessionMon;
   CFG.TradingSessions[2] = InpSessionTue;
   CFG.TradingSessions[3] = InpSessionWed;
   CFG.TradingSessions[4] = InpSessionThu;
   CFG.TradingSessions[5] = InpSessionFri;
   CFG.TradingSessions[6] = InpSessionSat;

   // --- News Filter ---
   CFG.NewsLevel = InpNewsLevel;
   CFG.UseNews = (InpNewsLevel != NEWS_OFF);
   CFG.NewsFreeze = InpNewsFreezeMinutes;
   CFG.NewsWebURL = InpNewsWebURL;

   // --- Core Strategy ---
   CFG.EntryMode = InpEntryMode;
   CFG.TPSLMode = InpTPSLMode;
   CFG.UseMTF = InpUseMTF;
   CFG.HTF = InpHTF;
   CFG.HTFLookback = InpHTFLookback;
   CFG.QualityLotMult = InpQualityLotMult;

   // --- SR Engine ---
   CFG.SRMode = InpSRMode;
   CFG.SRLookback = InpSRLookback;
   CFG.SwingLookback = InpSwingLookback;
   CFG.SRTouchBufferATR = InpSRTouchBufferATR;
   CFG.SRMinTouchesStrong = InpSRMinTouchesStrong;
   CFG.MinSRRangeATR = InpMinSRRangeATR;
   CFG.ATRBufferMult = InpATRBufferMult;
   CFG.BufferMultStrong = InpBufferMultStrong;
   CFG.BufferMultWeak = InpBufferMultWeak;

   // --- Signal & Pattern Detection ---
   CFG.SignalLookback = InpSignalLookback;
   CFG.MTFConfluenceBonus = InpMTFConfluenceBonus;
   CFG.StrongZoneBonus = InpStrongZoneBonus;
   CFG.StrongZoneThreshold = InpStrongZoneThreshold;
   CFG.MaxSignalATR = InpMaxSignalATR;
   CFG.MomentumThresholdATR = InpMomentumThresholdATR;
   CFG.UsePatternWeights = InpUsePatternWeights;
   CFG.AntiBreakoutPct = InpAntiBreakoutPct;
   CFG.MarubozuMinBodyPct = InpMarubozuMinBodyPct;
   CFG.EngulfingBodyMult = InpEngulfingBodyMult;
   CFG.MinDominanceGap = InpMinDominanceGap;
   CFG.StrongZoneBufferMult = InpStrongZoneBufferMult;
   CFG.UseAdaptiveZoneBuffer = InpUseAdaptiveZoneBuffer;
   CFG.PatternSensitivityATR = InpPatternSensitivityATR;
   CFG.StarMiddleBodyMult = InpStarMiddleBodyMult;

   // --- Generic Pattern Scoring ---
   CFG.PatternBaseScore = InpPatternBaseScore;
   CFG.PatternBonusStrongATRRange = InpPatternBonusStrongATRRange;
   CFG.PatternBonusStrongBodyRatio = InpPatternBonusStrongBodyRatio;
   CFG.PatternBonusStrongWickRejection = InpPatternBonusStrongWickRejection;
   CFG.PatternBonusFollowThrough = InpPatternBonusFollowThrough;
   CFG.PatternBonusGapConfirmation = InpPatternBonusGapConfirmation;
   CFG.PatternBonusBreakoutConfirmation = InpPatternBonusBreakoutConfirmation;
   CFG.PatternBonusSmall = InpPatternBonusSmall;
   CFG.PatternATRRangeThreshold = InpPatternATRRangeThreshold;
   CFG.PatternBodyRatioThreshold = InpPatternBodyRatioThreshold;
   CFG.PatternWickRatioThreshold = InpPatternWickRatioThreshold;

   // --- Pattern Specific Thresholds ---
   CFG.PinbarWickToOppositeWickRatio = InpPinbarWickToOppositeWickRatio;
   CFG.InsideBarChildMotherRangeMax = InpInsideBarChildMotherRangeMax;
   CFG.StarClosePositionMin = InpStarClosePositionMin;
   CFG.StarMiddleBodyMult = InpStarMiddleBodyMult;
   CFG.StarMiddleBarLookback = 3;
   CFG.ThreeInsideBodyRatioMin = InpThreeInsideBodyRatioMin;
   CFG.RailroadAvgBodyMinATR = InpRailroadAvgBodyMinATR;
   CFG.RailroadWickRejectionMult = InpRailroadWickRejectionMult;
   CFG.RailroadMinBodyRatio = InpRailroadMinBodyRatio;
   CFG.MarubozuMinATRRangeMult = InpMarubozuMinATRRangeMult;
   CFG.MarubozuStrongATRRangeMin = InpMarubozuStrongATRRangeMin;

   // --- Recovery & Fakeout ---
   CFG.UseRecoveryMode = InpUseRecoveryMode;
   CFG.RecoveryCooldownBars = InpRecoveryCooldownBars;
   CFG.MaxRecoveryAttempts = InpMaxRecoveryAttempts;
   CFG.RecoveryLotMult = InpRecoveryLotMult;
   CFG.RecoveryPatternScoreThreshold = InpRecoveryPatternScoreThreshold;
   CFG.RecoveryZoneToleranceATR = InpRecoveryZoneToleranceATR;
   CFG.FakeoutDetectionSensitivity = InpFakeoutDetectionSensitivity;
   CFG.FakeoutSLAdjustmentATR = InpFakeoutSLAdjustmentATR;

   // --- SL Multipliers ---
   CFG.DefaultSLMult = InpDefaultSLMult;
   CFG.PinbarSLMult = InpPinbarSLMult;
   CFG.InsideBarSLMult = InpInsideBarSLMult;

   // --- Protection & Cooldowns ---
   CFG.MaxPositions = InpMaxOpenPositions;
   CFG.MaxTradeDurationDays = InpMaxTradeDurationDays;
   CFG.EntryCooldownBars = InpEntryCooldownBars;
   CFG.SignalCooldownBars = InpSignalCooldownBars;
   CFG.LossCooldownBars = InpLossCooldownBars;
   CFG.PatternFailureCooldownBars = InpPatternFailureCooldownBars;
   CFG.MaxConsecutiveLoss = InpMaxConsecutiveLoss;
   CFG.HighQualityThreshold = InpHighQualityThreshold;
   CFG.UseDynamicCooldown = InpUseDynamicCooldown;
   CFG.ReducedCooldownBars = InpReducedCooldownBars;

   // --- Execution & Exit ---
   CFG.OrderThrottleMs = InpOrderThrottleMs;
   CFG.UseTrailing = InpUseTrailing;
   CFG.UsePartialClose = InpUsePartialClose;
   CFG.ExitOnOpposite = InpExitOnOpposite;
   CFG.TPBufferATR = InpTPBufferATR;
   CFG.SLBufferATR = InpSLBufferATR;
   CFG.MinTPDistanceATR = InpMinTPDistanceATR;
   CFG.MaxTPDistanceATR = InpMaxTPDistanceATR;
   CFG.TrailingStartATR = InpTrailingStartATR;
   CFG.TrailingBufferATR = InpTrailingBufferATR;
   CFG.TrailActivationATR = InpTrailActivationATR;
   CFG.TrailStepATR = InpTrailStepATR;
   CFG.LockProfitATR = InpLockProfitATR;
   CFG.LockOffsetATR = InpLockOffsetATR;
   CFG.PartialCloseLotPct = InpPartialCloseLotPct;
   CFG.PartialCloseATR = InpPartialCloseATR;
   CFG.ZoneReuseATR = InpZoneReuseATR;

   // --- System ---
   CFG.DebugMode = InpDebugMode;
   CFG.SafeMode = InpSafeMode;
}

void PrintConfigSummary()
{
   if (!CFG.DebugMode)
      return;

   Print("=== PASR CONFIG ACTIVE ===");
   Print("ATR Period       : ", CFG.ATRPeriod);
   Print("ATR Range        : ", DoubleToString(CFG.ATRMin, 1), " - ", DoubleToString(CFG.ATRMax, 1));
   Print("SR Mode          : ", (string)CFG.SRMode);
   Print("Signal Lookback  : ", CFG.SignalLookback);
   Print("Use MTF          : ", (CFG.UseMTF ? "true" : "false"));
   Print("Use Trailing     : ", (CFG.UseTrailing ? "true" : "false"));
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

   void SaveState(const ulong magic) const
   {
      if (mainTicket <= 0)
         return;
      string p = "PASR_" + (string)magic + "_" + (string)mainTicket + "_";
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

   void LoadState(ulong ticket, ulong magic)
   {
      string p = "PASR_" + (string)magic + "_" + (string)ticket + "_";
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

         double pcDist = lastKnownATR * CFG.PartialCloseATR * _Point;
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