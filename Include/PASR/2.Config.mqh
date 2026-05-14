//+------------------------------------------------------------------+
//|                                                       2.Config.mqh |
//|                                       Copyright 2026, Agsicentre |
//|            Core Configuration & System Definitions               |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "1.21"
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
//| Configuration Snapshot for Centralized Caching                   |
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
      // SAFEGUARD: Maximum recovery positions per initial position
      int maxRecoveryPositions;          // Max 2 recovery positions per initial trade
      double maxExposureMultiplier;      // Max total exposure (e.g., 2x initial lot)
      int recoveryTimeoutBars;           // Close all if still losing after N bars
      double hardStopLossPct;            // Hard stop per group (e.g., 3% of balance)
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

// Global instance of StrategyConfig.
// In MQL5, include files are typically included once in the main EA file,
// making this acceptable. It serves as the primary configuration source
// for all managers after SetCommonDefaults() is called.
StrategyConfig CFG;

struct ConfigSnapshot
  {
   // Market
   int atr_period;
   double atr_min;
   double atr_max;
   double max_spread;
   string sessions[7];
   
   // Market Regime
   bool use_regime;
   double min_trend_strength;
   bool allow_sideways;
   double regime_lot_mult_strong;
   double regime_lot_mult_weak;
   double regime_lot_mult_side;
   double regime_lot_mult_chop;
   
   // News
   bool news_use;
   ENUM_NEWS_LEVEL news_level;
   int news_freeze;
   string news_url;
   
   // Risk
   bool auto_lot;
   double risk_pct;
   double lot_size;
   double max_daily_loss;
   ulong magic;
   ENUM_ENTRY_MODE entry_mode;
   ENUM_TPSL_MODE tpsl_mode;
   bool use_mtf;
   ENUM_TIMEFRAMES htf;
   int htf_lookback;
   double quality_lot_mult;
   int max_positions;
   int max_consecutive_loss;
   int max_trade_duration_days;
   int entry_cooldown_bars;
   int signal_cooldown_bars;
   int loss_cooldown_bars;
   
   // SR
   ENUM_SR_MODE sr_mode;
   int sr_lookback;
   int swing_lookback;
   double touch_buffer_atr;
   int min_touches_strong;
   double min_range_atr;
   double atr_buffer_mult;
   double buffer_mult_strong;
   double buffer_mult_weak;
   double zone_reuse_atr;
   
   // Pattern
   int pattern_lookback;
   double mtf_confluence_bonus;
   double strong_zone_bonus;
   double strong_zone_threshold;
   double max_signal_atr;
   double momentum_threshold_atr;
   bool use_weights;
   double anti_breakout_pct;
   double marubozu_min_body_pct;
   double engulfing_body_mult;
   double min_dominance_gap;
   double strong_zone_buffer_mult;
   bool use_adaptive_zone_buffer;
   double sensitivity_atr;
   double star_middle_body_mult;
   double railroad_min_body_ratio;
   int failure_cooldown_bars;
   double hq_threshold;
   bool use_dynamic_cooldown;
   int reduced_cooldown_bars;
   double base_score;
   double bonus_strong_atr;
   double bonus_strong_body;
   double bonus_strong_wick;
   double bonus_follow_through;
   double bonus_gap_confirm;
   double bonus_breakout_confirm;
   double bonus_small;
   double atr_range_threshold;
   double body_ratio_threshold;
   double wick_ratio_threshold;
   double pinbar_wick_ratio;
   double inside_bar_range_max;
   double star_close_min;
   double three_inside_body_min;
   double railroad_avg_body_min;
   double railroad_wick_mult;
   double marubozu_min_atr_mult;
   double marubozu_strong_atr_min;
   double default_sl_mult;
   double pinbar_sl_mult;
   double inside_bar_sl_mult;
   
   // Recovery
   bool recovery_use;
   int recovery_cooldown_bars;
   int max_recovery_attempts;
   double recovery_lot_mult;
   double recovery_pattern_score_threshold;
   double recovery_zone_tolerance_atr;
   double fakeout_sensitivity;
   double fakeout_sl_adjustment_atr;
   // SAFEGUARD fields
   int recovery_max_positions;
   double recovery_max_exposure_mult;
   int recovery_timeout_bars;
   double recovery_hard_stop_pct;
   
   // Exit
   int order_throttle_ms;
   bool use_trailing;
   bool use_partial_close;
   bool exit_on_opposite;
   double tp_buffer_atr;
   double sl_buffer_atr;
   double min_tp_distance_atr;
   double max_tp_distance_atr;
   double trailing_start_atr;
   double trailing_buffer_atr;
   double trail_activation_atr;
   double trail_step_atr;
   double lock_profit_atr;
   double lock_offset_atr;
   double partial_close_lot_pct;
   double partial_close_atr;
   
   // AI
   bool use_ai;
   int ai_training_window_bars;
   double ai_min_confidence;
   double ai_pattern_bonus;
   
   // System
   bool debug;
   bool safe;
   
   // Copy from StrategyConfig
   void CopyFrom(const StrategyConfig &cfg)
     {
      // Market
      atr_period = cfg.market.atrPeriod;
      atr_min = cfg.market.atrMin;
      atr_max = cfg.market.atrMax;
      max_spread = cfg.market.maxSpread;
      for(int i=0; i<7; i++) sessions[i] = cfg.market.sessions[i];
      
      // Market Regime
      use_regime = cfg.market.useRegime;
      min_trend_strength = cfg.market.minTrendStrength;
      allow_sideways = cfg.market.allowSideways;
      regime_lot_mult_strong = cfg.market.regimeLotMultStrong;
      regime_lot_mult_weak = cfg.market.regimeLotMultWeak;
      regime_lot_mult_side = cfg.market.regimeLotMultSide;
      regime_lot_mult_chop = cfg.market.regimeLotMultChop;
      
      // News
      news_use = cfg.news.use;
      news_level = cfg.news.level;
      news_freeze = cfg.news.freeze;
      news_url = cfg.news.url;
      
      // Risk
      auto_lot = cfg.risk.autoLot;
      risk_pct = cfg.risk.pct;
      lot_size = cfg.risk.lot;
      max_daily_loss = cfg.risk.maxDailyLoss;
      magic = cfg.risk.magic;
      entry_mode = cfg.risk.entryMode;
      tpsl_mode = cfg.risk.tpslMode;
      use_mtf = cfg.risk.useMTF;
      htf = cfg.risk.htf;
      htf_lookback = cfg.risk.htfLookback;
      quality_lot_mult = cfg.risk.qualityLotMult;
      max_positions = cfg.risk.maxPositions;
      max_consecutive_loss = cfg.risk.maxConsecutiveLoss;
      max_trade_duration_days = cfg.risk.maxTradeDurationDays;
      entry_cooldown_bars = cfg.risk.entryCooldownBars;
      signal_cooldown_bars = cfg.risk.signalCooldownBars;
      loss_cooldown_bars = cfg.risk.lossCooldownBars;
      
      // SR
      sr_mode = cfg.sr.mode;
      sr_lookback = cfg.sr.lookback;
      swing_lookback = cfg.sr.swingLookback;
      touch_buffer_atr = cfg.sr.touchBufferATR;
      min_touches_strong = cfg.sr.minTouchesStrong;
      min_range_atr = cfg.sr.minRangeATR;
      atr_buffer_mult = cfg.sr.atrBufferMult;
      buffer_mult_strong = cfg.sr.bufferMultStrong;
      buffer_mult_weak = cfg.sr.bufferMultWeak;
      zone_reuse_atr = cfg.sr.zoneReuseATR;
      
      // Pattern
      pattern_lookback = cfg.pattern.lookback;
      mtf_confluence_bonus = cfg.pattern.mtfConfluenceBonus;
      strong_zone_bonus = cfg.pattern.strongZoneBonus;
      strong_zone_threshold = cfg.pattern.strongZoneThreshold;
      max_signal_atr = cfg.pattern.maxSignalATR;
      momentum_threshold_atr = cfg.pattern.momentumThresholdATR;
      use_weights = cfg.pattern.useWeights;
      anti_breakout_pct = cfg.pattern.antiBreakoutPct;
      marubozu_min_body_pct = cfg.pattern.marubozuMinBodyPct;
      engulfing_body_mult = cfg.pattern.engulfingBodyMult;
      min_dominance_gap = cfg.pattern.minDominanceGap;
      strong_zone_buffer_mult = cfg.pattern.strongZoneBufferMult;
      use_adaptive_zone_buffer = cfg.pattern.useAdaptiveZoneBuffer;
      sensitivity_atr = cfg.pattern.sensitivityATR;
      star_middle_body_mult = cfg.pattern.starMiddleBodyMult;
      railroad_min_body_ratio = cfg.pattern.railroadMinBodyRatio;
      failure_cooldown_bars = cfg.pattern.failureCooldownBars;
      hq_threshold = cfg.pattern.hqThreshold;
      use_dynamic_cooldown = cfg.pattern.useDynamicCooldown;
      reduced_cooldown_bars = cfg.pattern.reducedCooldownBars;
      base_score = cfg.pattern.baseScore;
      bonus_strong_atr = cfg.pattern.bonusStrongATR;
      bonus_strong_body = cfg.pattern.bonusStrongBody;
      bonus_strong_wick = cfg.pattern.bonusStrongWick;
      bonus_follow_through = cfg.pattern.bonusFollowThrough;
      bonus_gap_confirm = cfg.pattern.bonusGapConfirm;
      bonus_breakout_confirm = cfg.pattern.bonusBreakoutConfirm;
      bonus_small = cfg.pattern.bonusSmall;
      atr_range_threshold = cfg.pattern.atrRangeThreshold;
      body_ratio_threshold = cfg.pattern.bodyRatioThreshold;
      wick_ratio_threshold = cfg.pattern.wickRatioThreshold;
      pinbar_wick_ratio = cfg.pattern.pinbarWickRatio;
      inside_bar_range_max = cfg.pattern.insideBarRangeMax;
      star_close_min = cfg.pattern.starCloseMin;
      three_inside_body_min = cfg.pattern.threeInsideBodyMin;
      railroad_avg_body_min = cfg.pattern.railroadAvgBodyMin;
      railroad_wick_mult = cfg.pattern.railroadWickMult;
      marubozu_min_atr_mult = cfg.pattern.marubozuMinATRMult;
      marubozu_strong_atr_min = cfg.pattern.marubozuStrongATRMin;
      default_sl_mult = cfg.pattern.defaultSLMult;
      pinbar_sl_mult = cfg.pattern.pinbarSLMult;
      inside_bar_sl_mult = cfg.pattern.insideBarSLMult;
      
      // Recovery
      recovery_use = cfg.recovery.use;
      recovery_cooldown_bars = cfg.recovery.cooldownBars;
      max_recovery_attempts = cfg.recovery.maxAttempts;
      recovery_lot_mult = cfg.recovery.lotMult;
      recovery_pattern_score_threshold = cfg.recovery.scoreThreshold;
      recovery_zone_tolerance_atr = cfg.recovery.zoneToleranceATR;
      fakeout_sensitivity = cfg.recovery.fakeoutSensitivity;
      fakeout_sl_adjustment_atr = cfg.recovery.fakeoutSLAdjATR;
      // SAFEGUARD fields
      recovery_max_positions = cfg.recovery.maxRecoveryPositions;
      recovery_max_exposure_mult = cfg.recovery.maxExposureMultiplier;
      recovery_timeout_bars = cfg.recovery.recoveryTimeoutBars;
      recovery_hard_stop_pct = cfg.recovery.hardStopLossPct;
      
      // Exit
      order_throttle_ms = cfg.system.orderThrottleMs;
      use_trailing = cfg.exit.useTrailing;
      use_partial_close = cfg.exit.usePartial;
      exit_on_opposite = cfg.exit.exitOnOpposite;
      tp_buffer_atr = cfg.exit.tpBufferATR;
      sl_buffer_atr = cfg.exit.slBufferATR;
      min_tp_distance_atr = cfg.exit.minTPDistATR;
      max_tp_distance_atr = cfg.exit.maxTPDistATR;
      trailing_start_atr = cfg.exit.trailingStartATR;
      trailing_buffer_atr = cfg.exit.trailingBufferATR;
      trail_activation_atr = cfg.exit.trailActivationATR;
      trail_step_atr = cfg.exit.trailStepATR;
      lock_profit_atr = cfg.exit.lockProfitATR;
      lock_offset_atr = cfg.exit.lockOffsetATR;
      partial_close_lot_pct = cfg.exit.partialLotPct;
      partial_close_atr = cfg.exit.partialATR;
      
      // AI
      use_ai = cfg.ai.use;
      ai_training_window_bars = cfg.ai.trainingWindow;
      ai_min_confidence = cfg.ai.minConfidence;
      ai_pattern_bonus = cfg.ai.patternBonus;
      
      // System
      debug = cfg.system.debug;
      safe = cfg.system.safe;
     }
     
   // Copy to StrategyConfig
   void CopyTo(StrategyConfig &cfg) const
     {
      // Market
      cfg.market.atrPeriod = atr_period;
      cfg.market.atrMin = atr_min;
      cfg.market.atrMax = atr_max;
      cfg.market.maxSpread = max_spread;
      for(int i=0; i<7; i++) cfg.market.sessions[i] = sessions[i];
      
      // News
      cfg.news.use = news_use;
      cfg.news.level = news_level;
      cfg.news.freeze = news_freeze;
      cfg.news.url = news_url;
      
      // Risk
      cfg.risk.autoLot = auto_lot;
      cfg.risk.pct = risk_pct;
      cfg.risk.lot = lot_size;
      cfg.risk.maxDailyLoss = max_daily_loss;
      cfg.risk.magic = magic;
      cfg.risk.entryMode = entry_mode;
      cfg.risk.tpslMode = tpsl_mode;
      cfg.risk.useMTF = use_mtf;
      cfg.risk.htf = htf;
      cfg.risk.htfLookback = htf_lookback;
      cfg.risk.qualityLotMult = quality_lot_mult;
      cfg.risk.maxPositions = max_positions;
      cfg.risk.maxConsecutiveLoss = max_consecutive_loss;
      cfg.risk.maxTradeDurationDays = max_trade_duration_days;
      cfg.risk.entryCooldownBars = entry_cooldown_bars;
      cfg.risk.signalCooldownBars = signal_cooldown_bars;
      cfg.risk.lossCooldownBars = loss_cooldown_bars;
      
      // SR
      cfg.sr.mode = sr_mode;
      cfg.sr.lookback = sr_lookback;
      cfg.sr.swingLookback = swing_lookback;
      cfg.sr.touchBufferATR = touch_buffer_atr;
      cfg.sr.minTouchesStrong = min_touches_strong;
      cfg.sr.minRangeATR = min_range_atr;
      cfg.sr.atrBufferMult = atr_buffer_mult;
      cfg.sr.bufferMultStrong = buffer_mult_strong;
      cfg.sr.bufferMultWeak = buffer_mult_weak;
      cfg.sr.zoneReuseATR = zone_reuse_atr;
      
      // Pattern
      cfg.pattern.lookback = pattern_lookback;
      cfg.pattern.mtfConfluenceBonus = mtf_confluence_bonus;
      cfg.pattern.strongZoneBonus = strong_zone_bonus;
      cfg.pattern.strongZoneThreshold = strong_zone_threshold;
      cfg.pattern.maxSignalATR = max_signal_atr;
      cfg.pattern.momentumThresholdATR = momentum_threshold_atr;
      cfg.pattern.useWeights = use_weights;
      cfg.pattern.antiBreakoutPct = anti_breakout_pct;
      cfg.pattern.marubozuMinBodyPct = marubozu_min_body_pct;
      cfg.pattern.engulfingBodyMult = engulfing_body_mult;
      cfg.pattern.minDominanceGap = min_dominance_gap;
      cfg.pattern.strongZoneBufferMult = strong_zone_buffer_mult;
      cfg.pattern.useAdaptiveZoneBuffer = use_adaptive_zone_buffer;
      cfg.pattern.sensitivityATR = sensitivity_atr;
      cfg.pattern.starMiddleBodyMult = star_middle_body_mult;
      cfg.pattern.railroadMinBodyRatio = railroad_min_body_ratio;
      cfg.pattern.failureCooldownBars = failure_cooldown_bars;
      cfg.pattern.hqThreshold = hq_threshold;
      cfg.pattern.useDynamicCooldown = use_dynamic_cooldown;
      cfg.pattern.reducedCooldownBars = reduced_cooldown_bars;
      cfg.pattern.baseScore = base_score;
      cfg.pattern.bonusStrongATR = bonus_strong_atr;
      cfg.pattern.bonusStrongBody = bonus_strong_body;
      cfg.pattern.bonusStrongWick = bonus_strong_wick;
      cfg.pattern.bonusFollowThrough = bonus_follow_through;
      cfg.pattern.bonusGapConfirm = bonus_gap_confirm;
      cfg.pattern.bonusBreakoutConfirm = bonus_breakout_confirm;
      cfg.pattern.bonusSmall = bonus_small;
      cfg.pattern.atrRangeThreshold = atr_range_threshold;
      cfg.pattern.bodyRatioThreshold = body_ratio_threshold;
      cfg.pattern.wickRatioThreshold = wick_ratio_threshold;
      cfg.pattern.pinbarWickRatio = pinbar_wick_ratio;
      cfg.pattern.insideBarRangeMax = inside_bar_range_max;
      cfg.pattern.starCloseMin = star_close_min;
      cfg.pattern.threeInsideBodyMin = three_inside_body_min;
      cfg.pattern.railroadAvgBodyMin = railroad_avg_body_min;
      cfg.pattern.railroadWickMult = railroad_wick_mult;
      cfg.pattern.marubozuMinATRMult = marubozu_min_atr_mult;
      cfg.pattern.marubozuStrongATRMin = marubozu_strong_atr_min;
      cfg.pattern.defaultSLMult = default_sl_mult;
      cfg.pattern.pinbarSLMult = pinbar_sl_mult;
      cfg.pattern.insideBarSLMult = inside_bar_sl_mult;
      
      // Recovery
      cfg.recovery.use = recovery_use;
      cfg.recovery.cooldownBars = recovery_cooldown_bars;
      cfg.recovery.maxAttempts = max_recovery_attempts;
      cfg.recovery.lotMult = recovery_lot_mult;
      cfg.recovery.scoreThreshold = recovery_pattern_score_threshold;
      cfg.recovery.zoneToleranceATR = recovery_zone_tolerance_atr;
      cfg.recovery.fakeoutSensitivity = fakeout_sensitivity;
      cfg.recovery.fakeoutSLAdjATR = fakeout_sl_adjustment_atr;
      // SAFEGUARD fields
      cfg.recovery.maxRecoveryPositions = recovery_max_positions;
      cfg.recovery.maxExposureMultiplier = recovery_max_exposure_mult;
      cfg.recovery.recoveryTimeoutBars = recovery_timeout_bars;
      cfg.recovery.hardStopLossPct = recovery_hard_stop_pct;
      
      // Exit
      cfg.system.orderThrottleMs = order_throttle_ms;
      cfg.exit.useTrailing = use_trailing;
      cfg.exit.usePartial = use_partial_close;
      cfg.exit.exitOnOpposite = exit_on_opposite;
      cfg.exit.tpBufferATR = tp_buffer_atr;
      cfg.exit.slBufferATR = sl_buffer_atr;
      cfg.exit.minTPDistATR = min_tp_distance_atr;
      cfg.exit.maxTPDistATR = max_tp_distance_atr;
      cfg.exit.trailingStartATR = trailing_start_atr;
      cfg.exit.trailingBufferATR = trailing_buffer_atr;
      cfg.exit.trailActivationATR = trail_activation_atr;
      cfg.exit.trailStepATR = trail_step_atr;
      cfg.exit.lockProfitATR = lock_profit_atr;
      cfg.exit.lockOffsetATR = lock_offset_atr;
      cfg.exit.partialLotPct = partial_close_lot_pct;
      cfg.exit.partialATR = partial_close_atr;
      
      // System
      cfg.system.debug = debug;
      cfg.system.safe = safe;
     }
  };

void SetCommonDefaults()
{
// Market & Sessions
   CFG.market.sessions[0] = InpSessionSun;
   CFG.market.sessions[1] = InpSessionMon;
   CFG.market.sessions[2] = InpSessionTue;
   CFG.market.sessions[3] = InpSessionWed;
   CFG.market.sessions[4] = InpSessionThu;
   CFG.market.sessions[5] = InpSessionFri;
   CFG.market.sessions[6] = InpSessionSat;
   
   // Market Regime Filter
   CFG.market.useRegime = InpUseMarketRegime;
   CFG.market.minTrendStrength = InpMinTrendStrength;
   CFG.market.allowSideways = InpAllowSidewaysTrading;
   CFG.market.regimeLotMultStrong = InpRegimeLotMultStrong;
   CFG.market.regimeLotMultWeak = InpRegimeLotMultWeak;
   CFG.market.regimeLotMultSide = InpRegimeLotMultSide;
   CFG.market.regimeLotMultChop = InpRegimeLotMultChop;

   // --- Input Validation & Assignment ---
   CFG.market.atrPeriod = (InpATRPeriod > 0) ? InpATRPeriod : 14;
   if (InpATRPeriod <= 0) Print("WARNING: InpATRPeriod must be > 0. Using default 14.");

   CFG.market.atrMin = (InpATRMin >= 0) ? InpATRMin : 0.0;
   if (InpATRMin < 0) Print("WARNING: InpATRMin must be >= 0. Using default 0.0.");

   CFG.market.atrMax = (InpATRMax >= CFG.market.atrMin) ? InpATRMax : CFG.market.atrMin;
   if (InpATRMax < CFG.market.atrMin) Print("WARNING: InpATRMax must be >= InpATRMin. Adjusting InpATRMax to InpATRMin.");

   CFG.market.maxSpread = (InpMaxSpread >= 0) ? InpMaxSpread : 0.0;
   if (InpMaxSpread < 0) Print("WARNING: InpMaxSpread must be >= 0. Using default 0.0.");

   // News
   CFG.news.use = (InpNewsLevel != NEWS_OFF); // Assigned here
   CFG.news.level = InpNewsLevel;
   CFG.news.freeze = (InpNewsFreezeMinutes >= 0) ? InpNewsFreezeMinutes : 30;
   if (InpNewsFreezeMinutes < 0) Print("WARNING: InpNewsFreezeMinutes must be >= 0. Using default 30.");
   CFG.news.url = InpNewsWebURL;

   // Risk & Account
   CFG.risk.autoLot = InpUseAutoLot;
   CFG.risk.pct = (InpRiskPct > 0 && InpRiskPct <= 100) ? InpRiskPct : 1.0;
   if (InpRiskPct <= 0 || InpRiskPct > 100) Print("WARNING: InpRiskPct must be between 0 and 100. Using default 1.0.");

   CFG.risk.lot = (InpLotSize > 0) ? InpLotSize : 0.01;
   if (InpLotSize <= 0) Print("WARNING: InpLotSize must be > 0. Using default 0.01.");

   CFG.risk.maxDailyLoss = (InpMaxDailyLossPct >= 0) ? InpMaxDailyLossPct : 0.0;
   if (InpMaxDailyLossPct < 0) Print("WARNING: InpMaxDailyLossPct must be >= 0. Using default 0.0.");

   CFG.risk.magic = InpMagicNum;
   CFG.risk.entryMode = InpEntryMode;
   CFG.risk.tpslMode = InpTPSLMode;
   CFG.risk.useMTF = InpUseMTF;
   CFG.risk.htf = InpHTF;
   CFG.risk.htfLookback = InpHTFLookback;
   CFG.risk.qualityLotMult = InpQualityLotMult;

   CFG.risk.maxPositions = (InpMaxOpenPositions >= 0) ? InpMaxOpenPositions : 0;
   if (InpMaxOpenPositions < 0) Print("WARNING: InpMaxOpenPositions must be >= 0. Using default 0.");

   CFG.risk.maxConsecutiveLoss = (InpMaxConsecutiveLoss >= 0) ? InpMaxConsecutiveLoss : 0;
   if (InpMaxConsecutiveLoss < 0) Print("WARNING: InpMaxConsecutiveLoss must be >= 0. Using default 0.");

   CFG.risk.maxTradeDurationDays = (InpMaxTradeDurationDays >= 0) ? InpMaxTradeDurationDays : 0;
   if (InpMaxTradeDurationDays < 0) Print("WARNING: InpMaxTradeDurationDays must be >= 0. Using default 0.");

   CFG.risk.entryCooldownBars = (InpEntryCooldownBars >= 0) ? InpEntryCooldownBars : 0;
   if (InpEntryCooldownBars < 0) Print("WARNING: InpEntryCooldownBars must be >= 0. Using default 0.");

   CFG.risk.signalCooldownBars = (InpSignalCooldownBars >= 0) ? InpSignalCooldownBars : 0;
   if (InpSignalCooldownBars < 0) Print("WARNING: InpSignalCooldownBars must be >= 0. Using default 0.");

   CFG.risk.lossCooldownBars = (InpLossCooldownBars >= 0) ? InpLossCooldownBars : 0;
   if (InpLossCooldownBars < 0) Print("WARNING: InpLossCooldownBars must be >= 0. Using default 0.");

   // SR Engine
   CFG.sr.mode = InpSRMode;
   CFG.sr.lookback = (InpSRLookback > 0) ? InpSRLookback : 100;
   if (InpSRLookback <= 0) Print("WARNING: InpSRLookback must be > 0. Using default 100.");

   CFG.sr.swingLookback = (InpSwingLookback > 0) ? InpSwingLookback : 20;
   if (InpSwingLookback <= 0) Print("WARNING: InpSwingLookback must be > 0. Using default 20.");

   CFG.sr.touchBufferATR = InpSRTouchBufferATR;
   CFG.sr.minTouchesStrong = InpSRMinTouchesStrong;
   CFG.sr.minRangeATR = InpMinSRRangeATR;
   CFG.sr.atrBufferMult = InpATRBufferMult;
   CFG.sr.bufferMultStrong = InpBufferMultStrong;
   CFG.sr.bufferMultWeak = InpBufferMultWeak;
   CFG.sr.zoneReuseATR = InpZoneReuseATR;

   // Patterns
   CFG.pattern.lookback = (InpSignalLookback > 0) ? InpSignalLookback : 5;
   if (InpSignalLookback <= 0) Print("WARNING: InpSignalLookback must be > 0. Using default 5.");

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
   CFG.recovery.use = InpUseRecoveryMode; // Boolean, no validation needed

   CFG.recovery.cooldownBars = (InpRecoveryCooldownBars >= 0) ? InpRecoveryCooldownBars : 3;
   if (InpRecoveryCooldownBars < 0) Print("WARNING: InpRecoveryCooldownBars must be >= 0. Using default 3.");

   CFG.recovery.maxAttempts = (InpMaxRecoveryAttempts >= 0) ? InpMaxRecoveryAttempts : 2;
   if (InpMaxRecoveryAttempts < 0) Print("WARNING: InpMaxRecoveryAttempts must be >= 0. Using default 2.");

   CFG.recovery.lotMult = (InpRecoveryLotMult >= 0) ? InpRecoveryLotMult : 1.0;
   if (InpRecoveryLotMult < 0) Print("WARNING: InpRecoveryLotMult must be >= 0. Using default 1.0.");

   CFG.recovery.scoreThreshold = InpRecoveryPatternScoreThreshold;
   CFG.recovery.zoneToleranceATR = InpRecoveryZoneToleranceATR;

   CFG.recovery.fakeoutSensitivity = (InpFakeoutDetectionSensitivity > 0) ? InpFakeoutDetectionSensitivity : 0.3;
   if (InpFakeoutDetectionSensitivity <= 0) Print("WARNING: InpFakeoutDetectionSensitivity must be > 0. Using default 0.3.");

   CFG.recovery.fakeoutSLAdjATR = InpFakeoutSLAdjustmentATR;
   
   // SAFEGUARD: Recovery limits
   CFG.recovery.maxRecoveryPositions = (InpMaxRecoveryPositions >= 0) ? InpMaxRecoveryPositions : 2;
   if (InpMaxRecoveryPositions < 0) Print("WARNING: InpMaxRecoveryPositions must be >= 0. Using default 2.");
   
   CFG.recovery.maxExposureMultiplier = (InpMaxRecoveryExposureMult >= 0) ? InpMaxRecoveryExposureMult : 2.0;
   if (InpMaxRecoveryExposureMult < 0) Print("WARNING: InpMaxRecoveryExposureMult must be >= 0. Using default 2.0.");
   
   CFG.recovery.recoveryTimeoutBars = (InpRecoveryTimeoutBars >= 0) ? InpRecoveryTimeoutBars : 20;
   if (InpRecoveryTimeoutBars < 0) Print("WARNING: InpRecoveryTimeoutBars must be >= 0. Using default 20.");
   
   CFG.recovery.hardStopLossPct = (InpRecoveryHardStopPct >= 0 && InpRecoveryHardStopPct <= 100) ? InpRecoveryHardStopPct : 3.0;
   if (InpRecoveryHardStopPct < 0 || InpRecoveryHardStopPct > 100) Print("WARNING: InpRecoveryHardStopPct must be 0-100. Using default 3.0.");

   // Exit & Trailing
   CFG.exit.useTrailing = InpUseTrailing;
   CFG.exit.usePartial = InpUsePartialClose;
   CFG.exit.exitOnOpposite = InpExitOnOpposite;
   CFG.exit.tpBufferATR = InpTPBufferATR;
   CFG.exit.slBufferATR = InpSLBufferATR;
   CFG.exit.minTPDistATR = InpMinTPDistanceATR;
   CFG.exit.maxTPDistATR = InpMaxTPDistanceATR;
   CFG.exit.trailingStartATR = (InpTrailingStartATR >= 0) ? InpTrailingStartATR : 1.5;
   CFG.exit.trailingBufferATR = InpTrailingBufferATR;
   CFG.exit.trailActivationATR = InpTrailActivationATR;
   CFG.exit.trailStepATR = InpTrailStepATR;
   CFG.exit.lockProfitATR = InpLockProfitATR;
   CFG.exit.lockOffsetATR = InpLockOffsetATR;
   
   CFG.exit.partialLotPct = (InpPartialCloseLotPct > 0 && InpPartialCloseLotPct <= 100) ? InpPartialCloseLotPct : 50.0;
   if(InpPartialCloseLotPct <= 0 || InpPartialCloseLotPct > 100) Print("WARNING: InpPartialCloseLotPct must be 1-100. Using 50.0");

   CFG.exit.partialATR = InpPartialCloseATR;

   // AI
   CFG.ai.use = InpUseAI;
   CFG.ai.trainingWindow = (InpAITrainingWindowBars > 10) ? InpAITrainingWindowBars : 200;
   if(InpUseAI && InpAITrainingWindowBars <= 10) Print("WARNING: AI Training Window too small. Using default 200.");

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
   Print("Risk %           : ", DoubleToString(CFG.risk.pct, 2));
   Print("Magic Number     : ", CFG.risk.magic);
   Print("Signal Lookback  : ", CFG.pattern.lookback);
   Print("Recovery Mode    : ", (CFG.recovery.use ? "Enabled" : "Disabled"));
   if (CFG.recovery.use) {
      Print("  Fakeout Sensitivity: ", DoubleToString(CFG.recovery.fakeoutSensitivity, 2));
   }
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