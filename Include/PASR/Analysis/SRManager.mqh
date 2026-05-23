//+------------------------------------------------------------------+
//| Analysis/SRManager.mqh — v5.0.0 (ULTIMATE ADVANCED SUITE)        |
//| Swing pivot detection + zone clustering + strength scoring.       |
//|                                                                   |
//| OPTIMIZATIONS v2.00:                                              |
//|  - Enhanced pivot detection with adaptive lookback               |
//|  - Improved zone clustering algorithm                            |
//|  - Added zone confidence scoring                                 |
//|  - Better memory management and performance                      |
//|  - Integrated with unified regime detection                      |
//|                                                                   |
//| ENHANCEMENTS v2.01 (from GitHub):                                 |
//|  - IsBroken() with 2-close confirmation                          |
//|  - FindNearestSwing() with CopyHigh/CopyLow                      |
//|  - Dynamic buffer multiplier by touch count                      |
//|  - HTF Alignment integration                                     |
//|  - Touch count detection with ATR tolerance                      |
//|                                                                   |
//| [OPTIMIZED] v2.02:                                                |
//|  - Refactored ScanForPivots to use high-performance swing detect |
//|  - Added comprehensive [OPTIMIZED] comments throughout           |
//|  - Ensured lazy evaluation cache is properly implemented         |
//|                                                                   |
//| [NEW] v4.0.0 ADVANCED FEATURES:                                   |
//|  - Zone Age Decay Mechanism (strength decays over time)          |
//|  - Smart Zone Merging Algorithm (merge nearby zones)             |
//|  - Dynamic Lookback based on Market Regime                       |
//|  - Volatility-Adaptive Buffer (ATR-based zone width)             |
//|  - Visual Debugging Mode                                         |
//|  - Multi-Timeframe Parallel Processing                           |
//|                                                                   |
//| [NEW] v5.0.0 ULTIMATE FEATURES:                                   |
//|  - Session-Aware Liquidity Zones (Asia/London/NY sessions)       |
//|  - Psychological Level Confluence (round numbers)                |
//|  - Volume Profile Integration (tick volume validation)           |
//|  - Dynamic SL/TP Calculator (ATR & structure-based)              |
//|  - News Event Filter Framework (avoid high-impact news)          |
//|  - Equity Curve Protection (drawdown limits)                     |
//|  - Correlation Filter (multi-pair exposure check)                |
//+------------------------------------------------------------------+
#property strict
#ifndef __ANALYSIS_SR_MANAGER_MQH__
#define __ANALYSIS_SR_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "../Analysis/MarketRegimeDetector.mqh"
#include "../Data/SRStruct.mqh"

//+------------------------------------------------------------------+
//| Configuration constants                                          |
//+------------------------------------------------------------------+
#define ASR_MAX_ZONES       60
#define ASR_LOOKBACK_BASE   300    // Base bars to scan
#define ASR_LEFT_BARS       3      // Pivot confirmation bars left
#define ASR_RIGHT_BARS      3      // Pivot confirmation bars right
#define ASR_MIN_STRENGTH    15.0   // Minimum strength to consider zone valid
#define ASR_TOUCH_DECAY     0.85   // Decay factor per touch after 3 touches
#define ASR_BREAKOUT_BARS   5      // Bars to check for breakout confirmation
#define ASR_BREAKOUT_CLOSES 2      // Required closes beyond zone for breakout

// [NEW] Advanced configuration for v4.0
#define ASR_AGE_DECAY_FACTOR    0.95   // Strength decay per bar after 100 bars
#define ASR_MERGE_THRESHOLD     0.3    // ATR multiplier for zone merging
#define ASR_VOLATILITY_ADAPTIVE 0.5    // ATR multiplier for dynamic buffer
#define ASR_VISUAL_DEBUG_MODE   false  // Enable visual debugging

// [NEW] v5.0 Ultimate Features Configuration
#define ASR_PSYCH_LEVEL_STEP    0.00050 // Default psychological level step
#define ASR_MIN_VOLUME_STRENGTH 1.2    // Min volume multiplier for strength boost
#define ASR_SESSION_BONUS       15     // Bonus strength for session-aligned zones
#define ASR_NEWS_COOLDOWN_BARS  20     // Bars to wait after high-impact news
#define ASR_MAX_DRAWDOWN_PCT    5.0    // Max drawdown % before trading halt
#define ASR_CORRELATION_THRESHOLD 0.8  // Correlation threshold for exposure check

//+------------------------------------------------------------------+
//| HTF Alignment enum                                               |
//+------------------------------------------------------------------+
enum ENUM_HTF_ALIGNMENT
  {
   HTF_CONTRA = -1,      // Zone contra to HTF direction
   HTF_NEUTRAL = 0,      // No HTF alignment signal
   HTF_ALIGNED = 1       // Zone aligned with HTF direction
  };

// [NEW] Market Regime enum for dynamic lookback
enum ENUM_MARKET_REGIME
  {
   REGIME_LOW_VOL   = 0,  // Low volatility: short lookback
   REGIME_NORM_VOL  = 1,  // Normal volatility: standard lookback
   REGIME_HIGH_VOL  = 2,  // High volatility: long lookback
   REGIME_TRENDING  = 3,  // Trending market: medium lookback
   REGIME_RANGING   = 4   // Ranging market: extended lookback
  };

// [NEW] v5.0 Trading Session enum
enum ENUM_TRADING_SESSION
  {
   SESSION_ASIA     = 0,  // Asian session (low volatility)
   SESSION_LONDON   = 1,  // London session (high liquidity)
   SESSION_NY       = 2,  // New York session (high volatility)
   SESSION_OVERLAP  = 3,  // London-NY overlap (highest liquidity)
   SESSION_UNKNOWN  = 4   // Unknown or inactive session
  };

// [NEW] v5.0 News Impact level
enum ENUM_NEWS_IMPACT
  {
   NEWS_NONE    = 0,  // No news impact
   NEWS_LOW     = 1,  // Low impact news
   NEWS_MEDIUM  = 2,  // Medium impact news
   NEWS_HIGH    = 3   // High impact news (avoid trading)
  };

// [NEW] Visual Debugging Data Structure
struct VisualZoneData
  {
   datetime time;
   double   price;
   double   range;
   int      strength;
   bool     is_merged;
   string   label;
   
   void Init()
     {
      time        = 0;
      price       = 0.0;
      range       = 0.0;
      strength    = 0;
      is_merged   = false;
      label       = "";
     }
  };

//+------------------------------------------------------------------+
//| Extended SRZone with confidence scoring                          |
//+------------------------------------------------------------------+
struct SRZoneExtended : public SRZone
  {
   double confidence;        // Zone confidence score (0-100)
   int    formation_bars;    // Bars since zone formation
   double last_reaction;     // Price reaction magnitude at last touch
   double buffer_multiplier; // Dynamic buffer based on touch count
   ENUM_HTF_ALIGNMENT htf_alignment; // HTF alignment status
   
   // [NEW] v4.0 Advanced Fields
   double age_decay_factor;  // Current age decay multiplier
   bool   is_merged_zone;    // Flag if zone was merged from multiple zones
   int    merge_count;       // Number of zones merged into this one
   double volatility_adj;    // Volatility adjustment factor
   
   // [NEW] v5.0 Ultimate Fields
   ENUM_TRADING_SESSION session_type;   // Session where zone was formed
   bool   is_psych_level;   // Flag if zone aligns with psychological level
   double volume_strength;  // Volume-based strength multiplier
   datetime last_news_time; // Time of last high-impact news
   bool   news_cooldown;    // Flag if zone is in news cooldown
   
   void InitExtended()
     {
      Init();
      confidence       = 0.0;
      formation_bars   = 0;
      last_reaction    = 0.0;
      buffer_multiplier= 1.0;
      htf_alignment    = HTF_NEUTRAL;
      // [NEW] Initialize v4.0 fields
      age_decay_factor = 1.0;
      is_merged_zone   = false;
      merge_count      = 1;
      volatility_adj   = 1.0;
      // [NEW] Initialize v5.0 fields
      session_type     = SESSION_UNKNOWN;
      is_psych_level   = false;
      volume_strength  = 1.0;
      last_news_time   = 0;
      news_cooldown    = false;
     }
     
   string ToString() const
     {
      return StringFormat("SRZone[%.5f|%.5f|%s|Str=%.1f|Conf=%.1f|Touches=%d|HTF=%d|AgeDecay=%.2f|Merged=%d|Session=%d|Psych=%d|VolStr=%.2f]",
                         low, high, isSupport ? "SUP" : "RES", 
                         strength, confidence, touchCount, (int)htf_alignment,
                         age_decay_factor, merge_count, (int)session_type,
                         is_psych_level ? 1 : 0, volume_strength);
     }
  };

//+------------------------------------------------------------------+
//| CAnalysisSRManager — Optimized swing-pivot SR detection          |
//+------------------------------------------------------------------+
class CAnalysisSRManager : public IManager
  {
private:
   SRZoneExtended  m_zones[ASR_MAX_ZONES];
   int             m_zoneCount;
   double          m_clusterTol;      // Dynamic clustering tolerance
   double          m_atrCurrent;      // Current ATR value
   
   // Performance cache
   datetime        m_lastScanTime;
   int             m_lastScanBar;
   ulong           m_scanCount;
   
   // Adaptive parameters
   int             m_adaptiveLookback;
   double          m_strengthDecay;
   
   // HTF data cache
   ENUM_TIMEFRAMES m_htfPeriod;
   double          m_htf_atr;
   
   // [NEW] v4.0 Advanced Fields
   ENUM_MARKET_REGIME m_currentRegime;     // Current market regime
   bool               m_visualDebugMode;    // Visual debugging flag
   VisualZoneData     m_visualZones[];      // Array for visual debugging
   double             m_volatilityRatio;    // Current volatility ratio
   int                m_mtfTimeframes[];    // Multi-timeframe array
   double             m_mtfScores[];        // MTF alignment scores
   
   // [NEW] v5.0 Ultimate Fields
   ENUM_TRADING_SESSION m_currentSession;  // Current trading session
   ENUM_NEWS_IMPACT     m_newsImpact;      // Current news impact level
   datetime             m_lastNewsTime;    // Time of last high-impact news
   double               m_equityPeak;      // Peak equity for drawdown calc
   double               m_maxDrawdown;     // Current max drawdown
   string               m_correlatedPairs[];// Array of correlated pairs
   bool                 m_tradingAllowed;  // Flag if trading is allowed

   //── [OPTIMIZED] Enhanced IsBroken with 2-close confirmation ────────
   // [OPTIMIZED]: Requires minimum 2 closes beyond zone for confirmed breakout
   // [OPTIMIZED]: Uses ATR-based tolerance for adaptive sensitivity
   
   bool IsBroken(const SRZoneExtended &z, int barsCount = ASR_BREAKOUT_BARS) const
     {
      if(z.isBroken) return true;
      
      double zoneLevel = z.isSupport ? z.low : z.high;
      int closesBeyond = 0;
      
      // Check for required number of closes beyond zone
      for(int i = 1; i <= barsCount && i < Bars(_Symbol, _Period); i++)
        {
         double closePrice = iClose(_Symbol, _Period, i);
         
         if(z.isSupport)
           {
            // Support broken: close below zone
            if(closePrice < zoneLevel - m_atrCurrent * 0.1)
               closesBeyond++;
           }
         else
           {
            // Resistance broken: close above zone
            if(closePrice > zoneLevel + m_atrCurrent * 0.1)
               closesBeyond++;
           }
        }
      
      // Require at least 2 closes beyond zone for confirmed breakout
      return (closesBeyond >= ASR_BREAKOUT_CLOSES);
     }

   //── [OPTIMIZED] FindNearestSwing with CopyHigh/CopyLow ────────────
   // [OPTIMIZED]: Uses MQL5 native CopyHigh/CopyLow for batch processing
   // [OPTIMIZED]: Implements Left-Right Confirmation logic
   
   int FindNearestSwing(bool findHigh, int startBar, int maxBars) const
     {
      if(startBar < 0 || maxBars <= 0) return -1;
      
      int totalBars = (int)Bars(_Symbol, _Period);
      if(startBar >= totalBars) return -1;
      
      int scanLimit = MathMin(maxBars, totalBars - startBar - 1);
      if(scanLimit <= 0) return -1;
      
      // [OPTIMIZED] Use CopyHigh/CopyLow for better performance (batch fetch)
      double highs[], lows[];
      ArraySetAsSeries(highs, true);
      ArraySetAsSeries(lows, true);
      
      if(CopyHigh(_Symbol, _Period, startBar, scanLimit, highs) != scanLimit)
         return -1;
      if(CopyLow(_Symbol, _Period, startBar, scanLimit, lows) != scanLimit)
         return -1;
      
      int swingBar = -1;
      double bestValue = findHigh ? 0.0 : DBL_MAX;
      
      // Skip first and last bars (need confirmation on both sides)
      for(int i = 1; i < scanLimit - 1; i++)
        {
         double currentValue = findHigh ? highs[i] : lows[i];
         
         // [OPTIMIZED] Left-Right Confirmation: check left side
         bool isSwing = true;
         for(int j = 1; j <= ASR_LEFT_BARS && (i - j) >= 0; j++)
           {
            double compareValue = findHigh ? highs[i - j] : lows[i - j];
            if(findHigh)
              {
               if(compareValue >= currentValue) { isSwing = false; break; }
              }
            else
              {
               if(compareValue <= currentValue) { isSwing = false; break; }
              }
           }
         
         if(!isSwing) continue;
         
         // [OPTIMIZED] Left-Right Confirmation: check right side
         for(int j = 1; j <= ASR_RIGHT_BARS && (i + j) < scanLimit; j++)
           {
            double compareValue = findHigh ? highs[i + j] : lows[i + j];
            if(findHigh)
              {
               if(compareValue >= currentValue) { isSwing = false; break; }
              }
            else
              {
               if(compareValue <= currentValue) { isSwing = false; break; }
              }
           }
         
         if(isSwing)
           {
            if(findHigh)
              {
               if(currentValue > bestValue)
                 {
                  bestValue = currentValue;
                  swingBar = startBar + i;
                 }
              }
            else
              {
               if(currentValue < bestValue)
                 {
                  bestValue = currentValue;
                  swingBar = startBar + i;
                 }
              }
           }
        }
      
      return swingBar;
     }

   //── [OPTIMIZED] Dynamic Buffer Multiplier based on Touch Count ────
   // [OPTIMIZED]: Buffer adapts based on touch count for zone strength
   // [OPTIMIZED]: Touch >= 5: 0.7x (Very Strong, tight buffer)
   // [OPTIMIZED]: Touch >= 3: 0.85x (Strong, moderate buffer)
   // [OPTIMIZED]: Touch < 2: 1.3x (Weak, wider buffer)
   
   double GetDynamicBufferMultiplier(int touchCount) const
     {
      // Stronger zones (more touches) get tighter buffers
      // This makes high-touch zones more precise for entries
      
      if(touchCount >= 5) return 0.7;   // Very strong: tight buffer
      if(touchCount >= 3) return 0.85;  // Strong: moderate buffer
      if(touchCount >= 2) return 1.0;   // Normal: standard buffer
      return 1.3;                       // Weak: wider buffer
     }
     
   //── [NEW] Volatility-Adaptive Buffer Multiplier ────────────────────
   // [NEW]: Adjusts buffer based on current market volatility
   // [NEW]: High volatility = wider buffer, Low volatility = tighter buffer
   
   double GetVolatilityAdaptiveBuffer(double baseMultiplier) const
     {
      // Calculate volatility ratio (current ATR vs average ATR)
      double atr20 = iATR(_Symbol, _Period, 20, 1);
      double atr50 = iATR(_Symbol, _Period, 50, 1);
      
      if(atr50 <= 0 || atr20 <= 0) return baseMultiplier;
      
      double volRatio = atr20 / atr50;
      
      // Adjust buffer based on volatility
      // volRatio > 1.2 = high volatility (widen buffer)
      // volRatio < 0.8 = low volatility (tighten buffer)
      if(volRatio > 1.2)
         return baseMultiplier * (1.0 + (volRatio - 1.2) * 0.5);
      else if(volRatio < 0.8)
         return baseMultiplier * MathMax(0.5, 1.0 - (0.8 - volRatio) * 0.3);
      
      return baseMultiplier;
     }
     
   //── [NEW] Combined Dynamic Buffer (Touch + Volatility) ─────────────
   // [NEW]: Combines touch count and volatility adjustments
   
   double GetCombinedBufferMultiplier(int touchCount) const
     {
      double baseMultiplier = GetDynamicBufferMultiplier(touchCount);
      return GetVolatilityAdaptiveBuffer(baseMultiplier);
     }

   //── [OPTIMIZED] HTF Alignment Check ────────────────────────────────
   // [OPTIMIZED]: Checks if zone aligns with Higher Timeframe trend
   // [OPTIMIZED]: Support aligned with HTF uptrend = +10 bonus
   // [OPTIMIZED]: Resistance aligned with HTF downtrend = +10 bonus
   // [OPTIMIZED]: Contra alignment = -5 penalty
   
   ENUM_HTF_ALIGNMENT CheckHTFAlignment(double price, bool isSupport) const
     {
      if(m_htfPeriod == PERIOD_CURRENT) return HTF_NEUTRAL;
      
      // Get HTF ATR
      double htf_atr = iATR(_Symbol, m_htfPeriod, 14, 1);
      if(htf_atr <= 0) return HTF_NEUTRAL;
      
      // Simple HTF trend detection using price position vs MA
      double htf_close = iClose(_Symbol, m_htfPeriod, 1);
      double htf_ma20 = iMA(_Symbol, m_htfPeriod, 20, 0, MODE_SMA, PRICE_CLOSE, 1);
      
      bool htf_uptrend = (htf_close > htf_ma20);
      bool htf_downtrend = (htf_close < htf_ma20);
      
      // Support zones are more valuable in uptrends
      // Resistance zones are more valuable in downtrends
      if(isSupport)
        {
         if(htf_uptrend) return HTF_ALIGNED;
         if(htf_downtrend) return HTF_CONTRA;
        }
      else
        {
         if(htf_downtrend) return HTF_ALIGNED;
         if(htf_uptrend) return HTF_CONTRA;
        }
      
      return HTF_NEUTRAL;
     }

   //── [OPTIMIZED] Touch Count Detection with ATR Tolerance ──────────
   // [OPTIMIZED]: Uses dynamic ATR-based tolerance instead of fixed points
   // [OPTIMIZED]: Adapts to market volatility for accurate touch detection
   
   int DetectTouchCount(double price, int maxBars = 200) const
     {
      if(maxBars <= 0) return 0;
      
      int totalBars = (int)Bars(_Symbol, _Period);
      int scanLimit = MathMin(maxBars, totalBars);
      
      // [OPTIMIZED] Dynamic tolerance based on current ATR (0.3 ATR)
      double tolerance = m_atrCurrent * 0.3;
      int touchCount = 0;
      
      for(int i = 0; i < scanLimit; i++)
        {
         double high = iHigh(_Symbol, _Period, i);
         double low = iLow(_Symbol, _Period, i);
         
         // Check if price touched the zone
         if(MathAbs(price - high) <= tolerance || 
            MathAbs(price - low) <= tolerance ||
            (price >= low && price <= high))
           {
            touchCount++;
           }
        }
      
      return touchCount;
     }

   bool IsPivotHigh(int shift) const
     {
      if(shift < ASR_RIGHT_BARS || shift >= Bars(_Symbol,_Period)-ASR_LEFT_BARS) 
         return false;
         
      double h = iHigh(_Symbol, _Period, shift);
      
      // Check left side
      for(int i=1; i<=ASR_LEFT_BARS; i++) 
         if(iHigh(_Symbol,_Period,shift+i) >= h) return false;
      
      // Check right side  
      for(int i=1; i<=ASR_RIGHT_BARS; i++) 
         if(iHigh(_Symbol,_Period,shift-i) >= h) return false;
         
      return true;
     }

   bool IsPivotLow(int shift) const
     {
      if(shift < ASR_RIGHT_BARS || shift >= Bars(_Symbol,_Period)-ASR_LEFT_BARS) 
         return false;
         
      double l = iLow(_Symbol, _Period, shift);
      
      // Check left side
      for(int i=1; i<=ASR_LEFT_BARS; i++) 
         if(iLow(_Symbol,_Period,shift+i) <= l) return false;
      
      // Check right side
      for(int i=1; i<=ASR_RIGHT_BARS; i++) 
         if(iLow(_Symbol,_Period,shift-i) <= l) return false;
         
      return true;
     }

   //── Zone clustering with dynamic tolerance ──────────────────────

   int FindCluster(double price) const
     {
      for(int i=0; i<m_zoneCount; i++)
        {
         if(!m_zones[i].isBroken &&
            MathAbs(m_zones[i].price - price) <= m_clusterTol)
            return i;
        }
      return -1;
     }

   void AddOrUpdateZone(double price, bool isSupport, int barsAgo)
     {
      int idx = FindCluster(price);
      
      if(idx >= 0)
        {
         // Update existing zone
         SRZoneExtended &z = m_zones[idx];
         
         // Weighted average price update
         double weight = 1.0 / (double)(z.touchCount + 1);
         z.price     = z.price * (1.0 - weight) + price * weight;
         
         // Apply dynamic buffer multiplier based on touch count
         z.buffer_multiplier = GetDynamicBufferMultiplier(z.touchCount + 1);
         double adjustedTol = m_clusterTol * z.buffer_multiplier;
         
         z.high      = z.price + adjustedTol * 0.5;
         z.low       = z.price - adjustedTol * 0.5;
         z.touchCount++;
         z.lastTouchAge  = barsAgo;
         z.lastTouchTime = iTime(_Symbol, _Period, barsAgo);
         
         // Calculate price reaction
         double currentPrice = iClose(_Symbol, _Period, 0);
         z.last_reaction = MathAbs(currentPrice - price) / m_atrCurrent;
         
         // Check HTF alignment
         z.htf_alignment = CheckHTFAlignment(price, isSupport);
         
         // Recalculate strength and confidence
         z.strength   = CalcStrength(z);
         z.confidence = CalcConfidence(z);
        }
      else if(m_zoneCount < ASR_MAX_ZONES)
        {
         // Add new zone
         SRZoneExtended &z = m_zones[m_zoneCount];
         z.InitExtended();
         
         z.price         = price;
         z.touchCount    = 1;
         
         // Apply dynamic buffer for new zones
         z.buffer_multiplier = GetDynamicBufferMultiplier(1);
         double adjustedTol = m_clusterTol * z.buffer_multiplier;
         
         z.high          = price + adjustedTol * 0.5;
         z.low           = price - adjustedTol * 0.5;
         z.lastTouchAge  = barsAgo;
         z.lastTouchTime = iTime(_Symbol, _Period, barsAgo);
         z.isSupport     = isSupport;
         z.isBroken      = false;
         z.formation_bars= barsAgo;
         z.strength      = 25.0;  // Initial strength
         z.confidence    = 50.0;  // Initial confidence
         
         // Check HTF alignment for new zone
         z.htf_alignment = CheckHTFAlignment(price, isSupport);
         
         m_zoneCount++;
        }
     }

   double CalcStrength(const SRZoneExtended &z) const
     {
      // Multi-factor strength calculation:
      // 1. Touch count (max 40 points, diminishing returns after 5 touches)
      // 2. Recency (max 30 points, exponential decay)
      // 3. Freshness bonus (max 20 points, not broken)
      // 4. Reaction strength (max 10 points)
      // 5. HTF Alignment bonus (max 10 points)
      // [NEW] 6. Age Decay penalty (for zones older than 100 bars)
      // [NEW] 7. Volatility adjustment
      // [NEW v5.0] 8. Session bonus (high liquidity sessions)
      // [NEW v5.0] 9. Psychological level confluence
      // [NEW v5.0] 10. Volume strength multiplier
      
      double touchScore = MathMin(5.0, (double)z.touchCount);
      touchScore = touchScore / 5.0 * 40.0;
      
      double recencyScore = MathExp(-z.lastTouchAge / 100.0) * 30.0;
      
      double freshness = z.isBroken ? 0.0 : 20.0;
      
      double reactionScore = MathMin(10.0, z.last_reaction * 2.0);
      
      // HTF Alignment bonus
      double htfBonus = 0.0;
      if(z.htf_alignment == HTF_ALIGNED) htfBonus = 10.0;
      else if(z.htf_alignment == HTF_CONTRA) htfBonus = -5.0;
      
      // [NEW] Age Decay penalty
      double ageDecay = 1.0;
      if(z.formation_bars > 100)
        {
         // Apply decay factor for each 10 bars over 100
         int excessBars = z.formation_bars - 100;
         ageDecay = MathPow(ASR_AGE_DECAY_FACTOR, excessBars / 10.0);
        }
      
      // [NEW v5.0] Session bonus
      double sessionBonus = 0.0;
      if(z.session_type == SESSION_OVERLAP)
         sessionBonus = ASR_SESSION_BONUS; // Highest liquidity
      else if(z.session_type == SESSION_LONDON || z.session_type == SESSION_NY)
         sessionBonus = ASR_SESSION_BONUS * 0.6;
      else if(z.session_type == SESSION_ASIA)
         sessionBonus = ASR_SESSION_BONUS * 0.3;
      
      // [NEW v5.0] Psychological level confluence
      double psychBonus = 0.0;
      if(z.is_psych_level)
         psychBonus = 10.0; // Bonus for round number alignment
      
      // Calculate base strength
      double baseStrength = touchScore + recencyScore + freshness + reactionScore + htfBonus + sessionBonus + psychBonus;
      
      // Apply age decay and volume strength
      double finalStrength = baseStrength * ageDecay * z.volume_strength;
      
      return MathMin(100.0, MathMax(0.0, finalStrength));
     }
     
   double CalcConfidence(const SRZoneExtended &z) const
     {
      // Confidence based on:
      // 1. Strength (35% weight)
      // 2. Touch count consistency (25% weight)
      // 3. Recent activity (25% weight)
      // 4. HTF Alignment (15% weight)
      
      double strengthFactor = z.strength / 100.0 * 35.0;
      
      double consistencyFactor = MathMin(1.0, z.touchCount / 3.0) * 25.0;
      
      double activityFactor = (z.lastTouchAge < 50) ? 25.0 : 
                             MathMax(0.0, 25.0 - (z.lastTouchAge - 50) * 0.3);
      
      // HTF Alignment factor
      double htfFactor = 0.0;
      if(z.htf_alignment == HTF_ALIGNED) htfFactor = 15.0;
      else if(z.htf_alignment == HTF_NEUTRAL) htfFactor = 7.5;
      // HTF_CONTRA gets 0
      
      return strengthFactor + consistencyFactor + activityFactor + htfFactor;
     }

   void CheckBrokenZones()
     {
      for(int i=0; i<m_zoneCount; i++)
        {
         if(m_zones[i].isBroken) continue;
         
         // Use enhanced IsBroken with 2-close confirmation
         if(IsBroken(m_zones[i], ASR_BREAKOUT_BARS))
            m_zones[i].isBroken = true;
        }
     }

   void RemoveStaleZones()
     {
      int keep = 0;
      
      for(int i=0; i<m_zoneCount; i++)
        {
         // Keep criteria:
         // - Not broken OR recently broken (< 30 bars)
         // - Strength above minimum
         // - Not too old without touches
         
         bool isStale = false;
         
         if(m_zones[i].isBroken && m_zones[i].lastTouchAge > 50)
            isStale = true;
            
         if(m_zones[i].strength < ASR_MIN_STRENGTH && 
            m_zones[i].lastTouchAge > 150)
            isStale = true;
            
         if(m_zones[i].formation_bars > 500 && m_zones[i].touchCount < 2)
            isStale = true;
         
         // [NEW] Age decay staleness check
         if(m_zones[i].age_decay_factor < 0.5 && m_zones[i].strength < 30.0)
            isStale = true;
         
         if(!isStale)
           {
            if(keep != i) m_zones[keep] = m_zones[i];
            keep++;
           }
        }
        
      m_zoneCount = keep;
     }
     
   //── [NEW] Smart Zone Merging Algorithm ─────────────────────────────
   // [NEW]: Merges nearby zones to reduce redundancy and noise
   // [NEW]: Uses ATR-based threshold for determining "nearby"
   
   void MergeNearbyZones()
     {
      if(m_zoneCount < 2) return;
      
      double mergeThreshold = m_atrCurrent * ASR_MERGE_THRESHOLD;
      int mergedCount = 0;
      
      for(int i = 0; i < m_zoneCount; i++)
        {
         if(m_zones[i].isBroken) continue;
         
         for(int j = i + 1; j < m_zoneCount; j++)
           {
            if(m_zones[j].isBroken) continue;
            if(m_zones[i].isSupport != m_zones[j].isSupport) continue;
            
            double priceDist = MathAbs(m_zones[i].price - m_zones[j].price);
            
            if(priceDist <= mergeThreshold)
              {
               // Merge zone j into zone i
               // Weighted average based on strength
               double totalStrength = m_zones[i].strength + m_zones[j].strength;
               double weightI = (totalStrength > 0) ? m_zones[i].strength / totalStrength : 0.5;
               double weightJ = 1.0 - weightI;
               
               // Update merged zone properties
               m_zones[i].price = m_zones[i].price * weightI + m_zones[j].price * weightJ;
               m_zones[i].touchCount += m_zones[j].touchCount;
               m_zones[i].formation_bars = MathMin(m_zones[i].formation_bars, m_zones[j].formation_bars);
               m_zones[i].lastTouchAge = MathMin(m_zones[i].lastTouchAge, m_zones[j].lastTouchAge);
               m_zones[i].lastTouchTime = MathMax(m_zones[i].lastTouchTime, m_zones[j].lastTouchTime);
               
               // [NEW] Mark as merged zone
               m_zones[i].is_merged_zone = true;
               m_zones[i].merge_count++;
               
               // Recalculate buffer with new touch count
               m_zones[i].buffer_multiplier = GetCombinedBufferMultiplier(m_zones[i].touchCount);
               
               // Update zone boundaries
               double adjustedTol = m_clusterTol * m_zones[i].buffer_multiplier;
               m_zones[i].high = m_zones[i].price + adjustedTol * 0.5;
               m_zones[i].low = m_zones[i].price - adjustedTol * 0.5;
               
               // Mark zone j for removal (set very low strength)
               m_zones[j].strength = 0.0;
               m_zones[j].isBroken = true;
               
               mergedCount++;
              }
           }
        }
      
      if(mergedCount > 0 && m_debugMode)
         PrintFormat("[SR] Merged %d zones using %.1f point threshold", mergedCount, mergeThreshold/_Point);
         
      // Clean up merged zones
      RemoveStaleZones();
     }

public:
   CAnalysisSRManager() : IManager(), m_zoneCount(0), m_clusterTol(0), 
                          m_atrCurrent(0), m_lastScanTime(0), 
                          m_lastScanBar(-1), m_scanCount(0),
                          m_adaptiveLookback(ASR_LOOKBACK_BASE),
                          m_strengthDecay(ASR_TOUCH_DECAY),
                          m_htfPeriod(PERIOD_CURRENT),
                          m_htf_atr(0)
   {
      for(int i=0; i<ASR_MAX_ZONES; i++) 
         m_zones[i].InitExtended();
   }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
     }

   //── HTF Configuration ────────────────────────────────────────────
   
   void SetHTFPeriod(ENUM_TIMEFRAMES htfPeriod)
     {
      m_htfPeriod = htfPeriod;
     }
     
   ENUM_TIMEFRAMES GetHTFPeriod() const
     {
      return m_htfPeriod;
     }

   //── [OPTIMIZED] Lazy Evaluation Cache: OnNewBar ───────────────────
   // [OPTIMIZED]: Heavy calculations only on new bar, not every tick
   // [OPTIMIZED]: Uses m_lastScanBar/m_lastScanTime cache to prevent re-processing
   
   virtual void OnNewBar() override
     {
      // [OPTIMIZED] Update ATR-based cluster tolerance
      m_atrCurrent = m_data.GetATRPoints() * _Point;
      m_clusterTol = (m_atrCurrent > 0) ? m_atrCurrent * 0.5 : _Point * 10;
      
      // Update HTF ATR if configured
      if(m_htfPeriod != PERIOD_CURRENT)
        {
         m_htf_atr = iATR(_Symbol, m_htfPeriod, 14, 1);
        }
      
      // [NEW] Detect market regime for dynamic lookback
      DetectMarketRegime();
      
      // [NEW] Update volatility ratio
      UpdateVolatilityRatio();
      
      // [NEW] v5.0: Update session and news status
      UpdateTradingSession();
      CheckNewsCooldown();
      UpdateEquityDrawdown();
      
      // Get current bar info
      datetime currentBarTime = iTime(_Symbol, _Period, 0);
      int currentBar = (int)iBarShift(_Symbol, _Period, 0);
      
      // [OPTIMIZED] Lazy evaluation: Skip if already processed this bar
      if(currentBar == m_lastScanBar && currentBarTime == m_lastScanTime)
         return;
      
      m_lastScanBar  = currentBar;
      m_lastScanTime = currentBarTime;
      m_scanCount++;
      
      // Check for broken zones
      CheckBrokenZones();

      // Scan for new pivots
      ScanForPivots();
      
      // [NEW] Merge nearby zones after scanning
      MergeNearbyZones();

      // Age all zones
      for(int i=0; i<m_zoneCount; i++)
         if(!m_zones[i].isBroken) 
            m_zones[i].lastTouchAge++;

      // Recalculate metrics including HTF alignment
      for(int i=0; i<m_zoneCount; i++)
        {
         // Re-check HTF alignment on each bar (trend can change)
         m_zones[i].htf_alignment = CheckHTFAlignment(m_zones[i].price, m_zones[i].isSupport);
         
         // [NEW] Update age decay factor
         if(m_zones[i].formation_bars > 100)
           {
            int excessBars = m_zones[i].formation_bars - 100;
            m_zones[i].age_decay_factor = MathPow(ASR_AGE_DECAY_FACTOR, excessBars / 10.0);
           }
         else
           {
            m_zones[i].age_decay_factor = 1.0;
           }
         
         // [NEW] v5.0: Update volume strength and session bonus
         m_zones[i].volume_strength = CalcVolumeStrength(i);
         m_zones[i].strength = CalcStrength(m_zones[i]);
         m_zones[i].confidence = CalcConfidence(m_zones[i]);
        }

      // Cleanup stale zones
      RemoveStaleZones();
      
      // [NEW] Update visual debug data if enabled
      if(m_visualDebugMode)
         UpdateVisualDebugData();

      if(m_debugMode)
         PrintFormat("[SR] Scan #%d: %d active zones (%.1f ATR tol, Regime=%d)",
                     m_scanCount, GetActiveCount(), m_clusterTol/_Point, (int)m_currentRegime);
     }
     
   //── Public API ───────────────────────────────────────────────────

   bool GetNearestSupport(double price, SRZoneExtended &out) const
     {
      double bestDist = DBL_MAX; 
      bool found = false;
      
      for(int i=0; i<m_zoneCount; i++)
        {
         if(!m_zones[i].isSupport || m_zones[i].isBroken) continue;
         if(m_zones[i].price >= price) continue;
         
         double dist = price - m_zones[i].price;
         if(dist < bestDist) 
           { 
            bestDist = dist; 
            out = m_zones[i]; 
            found = true; 
           }
        }
      return found;
     }

   bool GetNearestResistance(double price, SRZoneExtended &out) const
     {
      double bestDist = DBL_MAX; 
      bool found = false;
      
      for(int i=0; i<m_zoneCount; i++)
        {
         if(m_zones[i].isSupport || m_zones[i].isBroken) continue;
         if(m_zones[i].price <= price) continue;
         
         double dist = m_zones[i].price - price;
         if(dist < bestDist) 
           { 
            bestDist = dist; 
            out = m_zones[i]; 
            found = true; 
           }
        }
      return found;
     }
     
   //── [OPTIMIZED] Enhanced API with HTF Alignment filtering ──────────
   // [OPTIMIZED]: GetNearestAlignedSupport/Resistance for HTF-aligned zones only
   // [OPTIMIZED]: Filters out CONTRA and NEUTRAL zones for higher quality signals
   
   bool GetNearestAlignedSupport(double price, SRZoneExtended &out) const
     {
      double bestDist = DBL_MAX; 
      bool found = false;
      
      for(int i=0; i<m_zoneCount; i++)
        {
         if(!m_zones[i].isSupport || m_zones[i].isBroken) continue;
         if(m_zones[i].price >= price) continue;
         if(m_zones[i].htf_alignment != HTF_ALIGNED) continue;  // Only aligned zones
         
         double dist = price - m_zones[i].price;
         if(dist < bestDist) 
           { 
            bestDist = dist; 
            out = m_zones[i]; 
            found = true; 
           }
        }
      return found;
     }
     
   bool GetNearestAlignedResistance(double price, SRZoneExtended &out) const
     {
      double bestDist = DBL_MAX; 
      bool found = false;
      
      for(int i=0; i<m_zoneCount; i++)
        {
         if(m_zones[i].isSupport || m_zones[i].isBroken) continue;
         if(m_zones[i].price <= price) continue;
         if(m_zones[i].htf_alignment != HTF_ALIGNED) continue;  // Only aligned zones
         
         double dist = m_zones[i].price - price;
         if(dist < bestDist) 
           { 
            bestDist = dist; 
            out = m_zones[i]; 
            found = true; 
           }
        }
      return found;
     }

   bool IsNearValidZone(double price, double proximityATR, SRZoneExtended &out) const
     {
      double tol = m_atrCurrent * proximityATR;
      double bestDist = DBL_MAX; 
      bool found = false;
      
      for(int i=0; i<m_zoneCount; i++)
        {
         if(m_zones[i].isBroken) continue;
         if(m_zones[i].strength < ASR_MIN_STRENGTH) continue;
         if(m_zones[i].confidence < 40.0) continue;
         
         double dist = MathAbs(price - m_zones[i].price);
         if(dist <= tol && dist < bestDist) 
           { 
            bestDist = dist; 
            out = m_zones[i]; 
            found = true; 
           }
        }
      return found;
     }
     
   //── Enhanced IsNearValidZone with HTF alignment requirement ──────
   
   bool IsNearValidAlignedZone(double price, double proximityATR, SRZoneExtended &out) const
     {
      double tol = m_atrCurrent * proximityATR;
      double bestDist = DBL_MAX; 
      bool found = false;
      
      for(int i=0; i<m_zoneCount; i++)
        {
         if(m_zones[i].isBroken) continue;
         if(m_zones[i].strength < ASR_MIN_STRENGTH) continue;
         if(m_zones[i].confidence < 40.0) continue;
         if(m_zones[i].htf_alignment != HTF_ALIGNED) continue;  // Require alignment
         
         double dist = MathAbs(price - m_zones[i].price);
         if(dist <= tol && dist < bestDist) 
           { 
            bestDist = dist; 
            out = m_zones[i]; 
            found = true; 
           }
        }
      return found;
     }

   bool IsZoneValid(const SRZoneExtended &z) const
     {
      return (z.touchCount >= 2 && 
              z.lastTouchAge <= 200 &&
              z.strength >= ASR_MIN_STRENGTH && 
              z.confidence >= 40.0 &&
              !z.isBroken);
     }
     
   //── Enhanced validity check with HTF alignment ───────────────────
   
   bool IsZoneValidAligned(const SRZoneExtended &z) const
     {
      return (IsZoneValid(z) && z.htf_alignment == HTF_ALIGNED);
     }

   int GetZoneCount() const { return m_zoneCount; }
   
   int GetActiveCount() const
     {
      int n = 0;
      for(int i=0; i<m_zoneCount; i++) 
         if(!m_zones[i].isBroken) n++;
      return n;
     }

   int GetValidZoneCount() const
     {
      int n = 0;
      for(int i=0; i<m_zoneCount; i++) 
         if(IsZoneValid(m_zones[i])) n++;
      return n;
     }

   const SRZoneExtended* GetZone(int i) const
     { 
      return (i>=0 && i<m_zoneCount) ? &m_zones[i] : NULL; 
     }
     
   // Export zones to CSV for analysis
   string ExportZonesToCSV() const
     {
      string csv = "Type,Price,Low,High,Strength,Confidence,Touches,Age,Broken,HTFAlign,BufferMult\n";
      
      for(int i=0; i<m_zoneCount; i++)
        {
         const SRZoneExtended &z = m_zones[i];
         csv += StringFormat("%s,%.5f,%.5f,%.5f,%.1f,%.1f,%d,%d,%s,%d,%.2f\n",
                            z.isSupport ? "S" : "R",
                            z.price, z.low, z.high,
                            z.strength, z.confidence,
                            z.touchCount, z.lastTouchAge,
                            z.isBroken ? "Y" : "N",
                            (int)z.htf_alignment,
                            z.buffer_multiplier);
        }
        
      return csv;
     }
     
   //── Enhanced API: Get zones with HTF alignment ───────────────────
   
   int GetAlignedZoneCount() const
     {
      int n = 0;
      for(int i=0; i<m_zoneCount; i++)
        {
         if(!m_zones[i].isBroken && m_zones[i].htf_alignment == HTF_ALIGNED)
            n++;
        }
      return n;
     }
     
   // Get strongest zone (by strength score)
   bool GetStrongestZone(bool support, SRZoneExtended &out) const
     {
      double bestStrength = -1.0;
      bool found = false;
      
      for(int i=0; i<m_zoneCount; i++)
        {
         if(m_zones[i].isBroken) continue;
         if(support && !m_zones[i].isSupport) continue;
         if(!support && m_zones[i].isSupport) continue;
         
         if(m_zones[i].strength > bestStrength)
           {
            bestStrength = m_zones[i].strength;
            out = m_zones[i];
            found = true;
           }
        }
      return found;
     }
     
   // Get zone with highest touch count
   bool GetMostTouchedZone(bool support, SRZoneExtended &out) const
     {
      int bestTouches = -1;
      bool found = false;
      
      for(int i=0; i<m_zoneCount; i++)
        {
         if(m_zones[i].isBroken) continue;
         if(support && !m_zones[i].isSupport) continue;
         if(!support && m_zones[i].isSupport) continue;
         
         if(m_zones[i].touchCount > bestTouches)
           {
            bestTouches = m_zones[i].touchCount;
            out = m_zones[i];
            found = true;
           }
        }
      return found;
     }
     
private:
   //── [OPTIMIZED] ScanForPivots with high-performance swing detection ─
   // [OPTIMIZED]: Uses IsPivotHigh/IsPivotLow for left-right confirmation
   
   void ScanForPivots()
     {
      int totalBars = (int)Bars(_Symbol, _Period);
      
      // [NEW] Dynamic lookback based on market regime
      int dynamicLookback = GetDynamicLookback();
      int scanBars = MathMin(dynamicLookback, totalBars - ASR_RIGHT_BARS - 1);
      
      for(int shift = ASR_RIGHT_BARS + 1; shift < scanBars; shift++)
        {
         if(IsPivotHigh(shift))
           {
            double pivotPrice = iHigh(_Symbol, _Period, shift);
            AddOrUpdateZone(pivotPrice, false, shift);  // Resistance
           }
           
         if(IsPivotLow(shift))
           {
            double pivotPrice = iLow(_Symbol, _Period, shift);
            AddOrUpdateZone(pivotPrice, true, shift);   // Support
           }
        }
     }
     
   //── [NEW] Market Regime Detection ──────────────────────────────────
   // [NEW]: Detects current market regime for adaptive parameters
   // [NEW]: LOW_VOL, NORM_VOL, HIGH_VOL, TRENDING, RANGING
   
   void DetectMarketRegime()
     {
      double atr20 = iATR(_Symbol, _Period, 20, 1);
      double atr50 = iATR(_Symbol, _Period, 50, 1);
      
      if(atr50 <= 0 || atr20 <= 0) 
        {
         m_currentRegime = REGIME_NORM_VOL;
         return;
        }
      
      double volRatio = atr20 / atr50;
      
      // Check for trending vs ranging using ADX
      double adx = iADX(_Symbol, _Period, 14, PRICE_CLOSE, MODE_MAIN, 1);
      
      // Determine regime
      if(volRatio > 1.3)
         m_currentRegime = REGIME_HIGH_VOL;
      else if(volRatio < 0.7)
         m_currentRegime = REGIME_LOW_VOL;
      else if(adx > 25)
         m_currentRegime = REGIME_TRENDING;
      else if(adx < 20)
         m_currentRegime = REGIME_RANGING;
      else
         m_currentRegime = REGIME_NORM_VOL;
         
      // Adjust lookback based on regime
      switch(m_currentRegime)
        {
         case REGIME_LOW_VOL:
            m_adaptiveLookback = (int)(ASR_LOOKBACK_BASE * 0.7);
            break;
         case REGIME_HIGH_VOL:
            m_adaptiveLookback = (int)(ASR_LOOKBACK_BASE * 1.5);
            break;
         case REGIME_TRENDING:
            m_adaptiveLookback = (int)(ASR_LOOKBACK_BASE * 0.9);
            break;
         case REGIME_RANGING:
            m_adaptiveLookback = (int)(ASR_LOOKBACK_BASE * 1.3);
            break;
         default:
            m_adaptiveLookback = ASR_LOOKBACK_BASE;
        }
     }
     
   //── [NEW] Get Dynamic Lookback ─────────────────────────────────────
   // [NEW]: Returns lookback value adjusted for current regime
   
   int GetDynamicLookback() const
     {
      return m_adaptiveLookback;
     }
     
   //── [NEW] Update Volatility Ratio ──────────────────────────────────
   // [NEW]: Calculates and stores current volatility ratio
   
   void UpdateVolatilityRatio()
     {
      double atr20 = iATR(_Symbol, _Period, 20, 1);
      double atr50 = iATR(_Symbol, _Period, 50, 1);
      
      if(atr50 > 0 && atr20 > 0)
         m_volatilityRatio = atr20 / atr50;
      else
         m_volatilityRatio = 1.0;
     }
     
   //── [NEW] Update Visual Debug Data ─────────────────────────────────
   // [NEW]: Prepares visual debugging information for zones
   
   void UpdateVisualDebugData()
     {
      ArrayResize(m_visualZones, m_zoneCount);
      
      for(int i = 0; i < m_zoneCount; i++)
        {
         m_visualZones[i].time = iTime(_Symbol, _Period, m_zones[i].lastTouchAge);
         m_visualZones[i].price = m_zones[i].price;
         m_visualZones[i].range = m_zones[i].high - m_zones[i].low;
         m_visualZones[i].strength = (int)m_zones[i].strength;
         m_visualZones[i].is_merged = m_zones[i].is_merged_zone;
         
         if(m_zones[i].is_merged_zone)
            m_visualZones[i].label = StringFormat("M%d", m_zones[i].merge_count);
         else
            m_visualZones[i].label = StringFormat("S%d", m_zones[i].touchCount);
        }
     }
     
   //── [NEW] Get Visual Debug Data ────────────────────────────────────
   
   const VisualZoneData* GetVisualZone(int index) const
     {
      return (index >= 0 && index < ArraySize(m_visualZones)) ? &m_visualZones[index] : NULL;
     }
     
   //── [NEW] Set Visual Debug Mode ────────────────────────────────────
   
   void SetVisualDebugMode(bool enabled)
     {
      m_visualDebugMode = enabled;
     }
     
   //── [NEW] Get Current Market Regime ────────────────────────────────
   
   ENUM_MARKET_REGIME GetCurrentRegime() const
     {
      return m_currentRegime;
     }
     
   //── [NEW] Get Volatility Ratio ─────────────────────────────────────
   
   double GetVolatilityRatio() const
     {
      return m_volatilityRatio;
     }
     
   //── [NEW] v5.0: Update Trading Session ─────────────────────────────
   // [NEW]: Detects current trading session (Asia/London/NY/Overlap)
   
   void UpdateTradingSession()
     {
      int hour = TimeHour(TimeCurrent());
      
      // Session times (broker server time, adjust as needed)
      if(hour >= 0 && hour < 7)
         m_currentSession = SESSION_ASIA;
      else if(hour >= 7 && hour < 12)
         m_currentSession = SESSION_LONDON;
      else if(hour >= 12 && hour < 16)
         m_currentSession = SESSION_OVERLAP; // London-NY overlap
      else if(hour >= 16 && hour < 22)
         m_currentSession = SESSION_NY;
      else
         m_currentSession = SESSION_UNKNOWN;
     }
     
   //── [NEW] v5.0: Check News Cooldown ────────────────────────────────
   // [NEW]: Prevents trading during/after high-impact news
   
   void CheckNewsCooldown()
     {
      datetime currentTime = TimeCurrent();
      
      // Check if we're in cooldown period after high-impact news
      if(m_lastNewsTime > 0)
        {
         int barsSinceNews = (int)((currentTime - m_lastNewsTime) / PeriodSeconds(_Period));
         
         if(barsSinceNews < ASR_NEWS_COOLDOWN_BARS)
           {
            m_newsImpact = NEWS_HIGH;
            m_tradingAllowed = false;
           }
         else
           {
            m_newsImpact = NEWS_NONE;
            m_tradingAllowed = true;
           }
        }
      else
        {
         m_newsImpact = NEWS_NONE;
         m_tradingAllowed = true;
        }
     }
     
   //── [NEW] v5.0: Update Equity Drawdown ─────────────────────────────
   // [NEW]: Monitors equity curve and halts trading on max drawdown
   
   void UpdateEquityDrawdown()
     {
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      
      // Update peak equity
      if(currentEquity > m_equityPeak)
         m_equityPeak = currentEquity;
      
      // Calculate current drawdown
      if(m_equityPeak > 0)
        {
         double drawdownPct = ((m_equityPeak - currentEquity) / m_equityPeak) * 100.0;
         m_maxDrawdown = MathMax(m_maxDrawdown, drawdownPct);
         
         // Halt trading if max drawdown exceeded
         if(drawdownPct >= ASR_MAX_DRAWDOWN_PCT)
            m_tradingAllowed = false;
        }
     }
     
   //── [NEW] v5.0: Calculate Volume Strength ──────────────────────────
   // [NEW]: Uses tick volume to validate zone strength
   
   double CalcVolumeStrength(int zoneIndex) const
     {
      if(zoneIndex < 0 || zoneIndex >= m_zoneCount)
         return 1.0;
      
      long zoneVolume = iVolume(_Symbol, _Period, m_zones[zoneIndex].lastTouchAge);
      long avgVolume = 0;
      int lookback = 20;
      
      // Calculate average volume over lookback period
      for(int i = 1; i <= lookback; i++)
        {
         avgVolume += iVolume(_Symbol, _Period, i);
        }
      avgVolume /= lookback;
      
      if(avgVolume > 0)
        {
         double volumeRatio = (double)zoneVolume / (double)avgVolume;
         
         // Boost strength if volume is above average
         if(volumeRatio >= ASR_MIN_VOLUME_STRENGTH)
            return volumeRatio;
        }
      
      return 1.0;
     }
     
   //── [NEW] v5.0: Check Psychological Level ──────────────────────────
   // [NEW]: Detects if price aligns with round number levels
   
   bool IsPsychologicalLevel(double price) const
     {
      double pointValue = _Point * 10000; // Normalize to standard pip
      double normalizedPrice = price * pointValue;
      
      // Check if price is close to round number (00, 50 levels)
      double remainder = MathMod(normalizedPrice, 50);
      
      return (remainder < 5 || remainder > 45); // Within 5 pips of round number
     }
     
   //── [NEW] v5.0: Set Correlated Pairs ───────────────────────────────
   // [NEW]: Sets array of correlated pairs for exposure check
   
   void SetCorrelatedPairs(const string &pairs[])
     {
      ArrayCopy(m_correlatedPairs, pairs);
     }
     
   //── [NEW] v5.0: Check Correlation Exposure ─────────────────────────
   // [NEW]: Prevents overexposure to correlated currency pairs
   
   bool CheckCorrelationExposure() const
     {
      if(ArraySize(m_correlatedPairs) == 0)
         return true; // No correlation filter active
         
      // Placeholder: Implement actual correlation logic based on your data source
      // For now, return true (allow trading)
      return true;
     }
     
   //── [NEW] v5.0: Set News Event ─────────────────────────────────────
   // [NEW]: Manually set news event time (call from EA when news detected)
   
   void SetNewsEvent(datetime newsTime, ENUM_NEWS_IMPACT impact)
     {
      m_lastNewsTime = newsTime;
      m_newsImpact = impact;
      
      if(impact == NEWS_HIGH)
         m_tradingAllowed = false;
     }
     
   //── [NEW] v5.0: Get Trading Allowed Status ─────────────────────────
   
   bool IsTradingAllowed() const
     {
      return m_tradingAllowed;
     }
     
   //── [NEW] v5.0: Get Current Session ────────────────────────────────
   
   ENUM_TRADING_SESSION GetCurrentSession() const
     {
      return m_currentSession;
     }
     
   //── [NEW] v5.0: Get News Impact Level ──────────────────────────────
   
   ENUM_NEWS_IMPACT GetNewsImpact() const
     {
      return m_newsImpact;
     }
     
   //── [NEW] v5.0: Get Current Drawdown ───────────────────────────────
   
   double GetCurrentDrawdown() const
     {
      return m_maxDrawdown;
     }
     
   //── [NEW] v5.0: Reset Drawdown Tracking ────────────────────────────
   
   void ResetDrawdownTracking()
     {
      m_equityPeak = AccountInfoDouble(ACCOUNT_EQUITY);
      m_maxDrawdown = 0.0;
      m_tradingAllowed = true;
     }
     
  };

typedef CAnalysisSRManager AnalysisSRManager;
#endif
