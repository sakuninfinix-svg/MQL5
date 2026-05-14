//+------------------------------------------------------------------+
//|                                                SignalManager.mqh |
//|                                       Copyright 2026, Agsicentre |
//|     Advanced Signal Scoring & Context-Aware Filtering Module     |
//|                    Version 2.0 - Intelligent Scoring System      |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "2.00"
#property strict

#ifndef __SIGNAL_MANAGER_MQH__
#define __SIGNAL_MANAGER_MQH__

#include "IManager.mqh"
#include "10.DataManager.mqh"
#include "9.PatternManager.mqh"
#include "3.MarketManager.mqh"
#include "12.MarketRegime.mqh"

//+------------------------------------------------------------------+
//| ENUM: Confidence Levels for Signal Quality                       |
//+------------------------------------------------------------------+
enum ENUM_CONFIDENCE_LEVEL
{
   CONFIDENCE_NONE = 0,        // No signal / Invalid
   CONFIDENCE_LOW,             // Score 0.0 - 0.49
   CONFIDENCE_MEDIUM,          // Score 0.50 - 0.69
   CONFIDENCE_HIGH,            // Score 0.70 - 0.84
   CONFIDENCE_VERY_HIGH        // Score 0.85 - 1.0
};

//+------------------------------------------------------------------+
//| STRUCT: Signal Result with Scoring & Reasoning                   |
//+------------------------------------------------------------------+
struct SignalResult
{
   ENUM_SIGNAL_TYPE type;           // BUY, SELL, or NONE
   double score;                    // Normalized score 0.0 - 1.0
   ENUM_CONFIDENCE_LEVEL confidence;// Confidence level based on score
   string reasoning;                // Detailed explanation of signal decision
   datetime timestamp;              // When signal was generated
   
   // Component scores for transparency
   double patternScore;             // 40% weight - Pattern strength
   double regimeScore;              // 20% weight - Market regime compatibility
   double volatilityScore;          // 15% weight - ATR normalization
   double newsScore;                // 15% weight - News impact (low = good)
   double mtfScore;                 // 10% weight - Multi-timeframe confluence
   
   // Additional context
   double dynamicThreshold;         // Current dynamic threshold
   bool isStable;                   // Whether signal passed debouncing
   int stabilityCount;              // Current stability counter
   
   // Constructor
   SignalResult()
   {
      ZeroMemory(this);
      type = SIGNAL_NONE;
      score = 0.0;
      confidence = CONFIDENCE_NONE;
      timestamp = TimeCurrent();
      dynamicThreshold = 0.65;  // Default threshold
   }
   
   // Get human-readable confidence string
   string ConfidenceToString() const
   {
      switch(confidence)
      {
         case CONFIDENCE_LOW: return "LOW";
         case CONFIDENCE_MEDIUM: return "MEDIUM";
         case CONFIDENCE_HIGH: return "HIGH";
         case CONFIDENCE_VERY_HIGH: return "VERY_HIGH";
         default: return "NONE";
      }
   }
   
   // Check if signal is actionable (above threshold and stable)
   bool IsActionable() const
   {
      return (type != SIGNAL_NONE && 
              score >= dynamicThreshold && 
              isStable &&
              confidence >= CONFIDENCE_MEDIUM);
   }
};

//+------------------------------------------------------------------+
//| Handles: PriceUpdate, NewBar, ConfigReload, EmergencyStop      |
//+------------------------------------------------------------------+
class SignalManager : public IManager
{
   //+------------------------------------------------------------------+
   //| PRIVATE: Internal State & Cache                                 |
   //+------------------------------------------------------------------+
private:
   // OPTIMIZATION V1.20: Removed instance - PatternManager is now static utility class
   // No need to instantiate PatternManager anymore

   // --- Zone Tracking ---
   double m_lastBuyZonePrice;
   double m_lastSellZonePrice;
   datetime m_lastBuyZoneBar;
   datetime m_lastSellZoneBar;

   // --- Signal Cooldown ---
   struct SignalCooldown
   {
      double price;
      datetime expiry;
   };
   SignalCooldown m_signalCooldowns[];

   struct FailedZone
   {
      double price;
      datetime expiry;
   };
   FailedZone m_failedZones[];

   // --- Event-Driven State Flags ---
   datetime m_lastProcessedBar;
   bool m_marketGateOpen;
   bool m_marketEntryAllowed;

   // --- Cached Market Data from Events ---
   struct CachedMarketData
   {
      double atrPoints;
      double support, resistance;
      double htfSupport, htfResistance;
      bool isSupBroken, isResBroken;
      double supBufferMult, resBufferMult;
      int supHtfAlign, resHtfAlign;
      int supStrength, resStrength;
      void Reset() { ZeroMemory(this); }
   } m_marketData;

   // ==================================================================
   // ADVANCED FEATURE #1-5: NEW STATE VARIABLES
   // ==================================================================
   
   // --- Feature #4: Signal Persistence & Debouncing ---
   ENUM_SIGNAL_TYPE m_lastSignalType;        // Previous signal type for comparison
   int m_signalStabilityCount;               // Counter for consecutive same signals
   int m_requiredStabilityTicks;             // Required stable ticks (default 3)
   SignalResult m_lastValidSignal;           // Last validated signal
   
   // --- Feature #2: Dynamic Threshold ---
   double m_dynamicThreshold;                // Current dynamic threshold
   double m_baseThreshold;                   // Base threshold (default 0.65)
   datetime m_lastThresholdUpdate;           // Last time threshold was recalculated
   
   // --- Feature #3: MTF Confluence ---
   int m_handleMA_H1;                        // MA handle for H1 timeframe
   int m_handleMA_H4;                        // MA handle for H4 timeframe
   double m_maH1_Buffer[];                   // Buffer for H1 MA values
   double m_maH4_Buffer[];                   // Buffer for H4 MA values
   bool m_mtfHandlesInitialized;             // Whether MTF handles are created
   
   // --- Feature #5: Reasoning Cache ---
   string m_lastReasoning;                   // Last generated reasoning string

   //+------------------------------------------------------------------+
   //| PRIVATE: Helper Methods                                         |
   //+------------------------------------------------------------------+
private:
   virtual void RefreshConfigCache() override
   {
      IManager::RefreshConfigCache();
   }

   bool FetchCandleBatch(int shiftStart, int count, MqlRates &outRates[])
   {
      ArraySetAsSeries(outRates, true); // Ensure array is set as series for CopyRates
      int copied = CopyRates(m_symbol, m_period, shiftStart, count, outRates);
      return (copied > 0);
   }

   // --- Zone Reuse Check ---
   bool IsZoneReuseBlocked(bool isBuy, double zonePrice, double atrPoints)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      MqlRates rates[];
      // FIX: Use closed bar (shift 1) to prevent repainting - only check against confirmed bar time
      if (CopyRates(m_symbol, m_period, 1, 1, rates) <= 0)
         return false;
      datetime currBar = rates[0].time;

      double tol = atrPoints * cfg.zone_reuse_atr * SymbolInfoDouble(m_symbol, SYMBOL_POINT);

      if (isBuy)
         return (m_lastBuyZoneBar == currBar && MathAbs(zonePrice - m_lastBuyZonePrice) <= tol);
      return (m_lastSellZoneBar == currBar && MathAbs(zonePrice - m_lastSellZonePrice) <= tol);
   }

   void RegisterZoneUse(bool isBuy, double zonePrice)
   {
      MqlRates rates[];
      // FIX: Use closed bar (shift 1) to prevent repainting - register zone on confirmed bar
      if (CopyRates(m_symbol, m_period, 1, 1, rates) <= 0)
         return;
      datetime currBar = rates[0].time;

      if (isBuy)
      {
         m_lastBuyZonePrice = zonePrice;
         m_lastBuyZoneBar = currBar;
      }
      else
      {
         m_lastSellZonePrice = zonePrice;
         m_lastSellZoneBar = currBar;
      }
   }

   // --- Pattern Failure Cooldown ---
   bool IsPatternFailureBlocked(double zonePrice, double atrPoints)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      datetime now = TimeCurrent();
      double tol = atrPoints * cfg.zone_reuse_atr * SymbolInfoDouble(m_symbol, SYMBOL_POINT);

      for (int i = ArraySize(m_failedZones) - 1; i >= 0; i--)
      {
         if (now > m_failedZones[i].expiry) continue;
         if (MathAbs(zonePrice - m_failedZones[i].price) <= tol)
            return true;
      }
      return false;
   }

   void CleanupFailedZones()
   {
      datetime now = TimeCurrent();
      int count = ArraySize(m_failedZones);
      if (count <= 0)
         return;

      for (int i = ArraySize(m_failedZones) - 1; i >= 0; i--)
      {
         if (now > m_failedZones[i].expiry)
            ArrayRemove(m_failedZones, i, 1);
      }
   }

   void RegisterFailure(double zonePrice)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      int sz = ArraySize(m_failedZones);
      ArrayResize(m_failedZones, sz + 1);
      m_failedZones[sz].price = zonePrice;
      m_failedZones[sz].expiry = TimeCurrent() + (cfg.failure_cooldown_bars * PeriodSeconds(m_period));

      if (m_debugMode)
         PrintFormat("[PASR Signal] Level %.5f registered as FAILED. Cooldown %d candles.",
                     zonePrice, cfg.failure_cooldown_bars);
   }

   // --- Signal Cooldown Management ---
   bool IsSignalCooldownActive(double price, double atrPoints)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      return IsSignalCooldownActiveWithCustomBars(price, atrPoints, cfg.signal_cooldown_bars);
   }

   // NEW: Signal Cooldown dengan custom bars untuk dynamic cooldown
   bool IsSignalCooldownActiveWithCustomBars(double price, double atrPoints, int cooldownBars)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      datetime now = TimeCurrent();

      for (int i = ArraySize(m_signalCooldowns) - 1; i >= 0; i--)
      {
         if (now > m_signalCooldowns[i].expiry)
            continue;
         double tol = atrPoints * cfg.zone_reuse_atr * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
         if (MathAbs(price - m_signalCooldowns[i].price) <= tol)
         {
            // Any signal in the zone within cooldown period blocks new signals
            return true;
         }
      }
      return false;
   }

   void RegisterSignalCooldown(double price)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      int sz = ArraySize(m_signalCooldowns);
      ArrayResize(m_signalCooldowns, sz + 1);
      m_signalCooldowns[sz].price = price;
      m_signalCooldowns[sz].expiry = TimeCurrent() + (cfg.signal_cooldown_bars * PeriodSeconds(m_period));

      if (m_debugMode)
         PrintFormat("[PASR Signal] Signal cooldown registered @ %.5f for %d bars.",
                     price, cfg.signal_cooldown_bars);
   }

   void CleanupSignalCooldowns()
   {
      datetime now = TimeCurrent();
      for (int i = ArraySize(m_signalCooldowns) - 1; i >= 0; i--)
      {
         if (now > m_signalCooldowns[i].expiry)
            ArrayRemove(m_signalCooldowns, i, 1);
      }
   }

   // --- MTF Bias Helper ---
   int GetMTFBias(double price, double htfSupport, double htfResistance, double atrPoints)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      if (!cfg.use_mtf)
         return 0;

      double zone = (atrPoints * cfg.atr_buffer_mult) * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      bool nearHtfSupport = (price <= htfSupport + zone);
      bool nearHtfResistance = (price >= htfResistance - zone);

      if (nearHtfSupport && !nearHtfResistance)
         return 1;
      if (nearHtfResistance && !nearHtfSupport)
         return -1;
      return 0;
   }

   // ==================================================================
   // ADVANCED FEATURE #3: MULTI-TIMEFRAME CONFLUENCE FILTER
   // ==================================================================
   
   // Initialize MTF indicator handles for H1 and H4
   bool InitializeMTFHandles()
   {
      if(m_mtfHandlesInitialized)
         return true;  // Already initialized
         
      // Release any existing handles first
      ReleaseMTFHandles();
      
      // Create MA handle for H1 timeframe (Period 50)
      m_handleMA_H1 = iMA(m_symbol, PERIOD_H1, 50, 0, MODE_SMA, PRICE_CLOSE);
      if(m_handleMA_H1 == INVALID_HANDLE)
      {
         if(m_debugMode)
            PrintFormat("[SignalManager] Failed to create MA H1 handle");
         return false;
      }
      
      // Create MA handle for H4 timeframe (Period 50)
      m_handleMA_H4 = iMA(m_symbol, PERIOD_H4, 50, 0, MODE_SMA, PRICE_CLOSE);
      if(m_handleMA_H4 == INVALID_HANDLE)
      {
         if(m_debugMode)
            PrintFormat("[SignalManager] Failed to create MA H4 handle");
         IndicatorRelease(m_handleMA_H1);
         m_handleMA_H1 = INVALID_HANDLE;
         return false;
      }
      
      // Set arrays as series
      ArraySetAsSeries(m_maH1_Buffer, true);
      ArraySetAsSeries(m_maH4_Buffer, true);
      
      m_mtfHandlesInitialized = true;
      
      if(m_debugMode)
         Print("[SignalManager] MTF Handles initialized successfully (H1 MA50, H4 MA50)");
      
      return true;
   }
   
   // Release MTF indicator handles
   void ReleaseMTFHandles()
   {
      if(m_handleMA_H1 != INVALID_HANDLE)
      {
         IndicatorRelease(m_handleMA_H1);
         m_handleMA_H1 = INVALID_HANDLE;
      }
      if(m_handleMA_H4 != INVALID_HANDLE)
      {
         IndicatorRelease(m_handleMA_H4);
         m_handleMA_H4 = INVALID_HANDLE;
      }
      m_mtfHandlesInitialized = false;
   }
   
   // Get current price relative to MA on higher timeframe
   // Returns: 1 = above MA (bullish), -1 = below MA (bearish), 0 = neutral/error
   int GetPriceVsMA(ENUM_TIMEFRAMES tf, int handle, double &maValue)
   {
      if(handle == INVALID_HANDLE)
         return 0;
      
      // Copy latest MA value
      if(CopyBuffer(handle, 0, 0, 1, m_maH1_Buffer) < 1)
      {
         maValue = 0;
         return 0;  // Error getting data
      }
      
      maValue = m_maH1_Buffer[0];
      if(maValue <= 0)
         return 0;  // Invalid MA value
      
      // Get current price
      double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      if(currentPrice <= 0)
         return 0;
      
      // Determine position relative to MA
      double threshold = maValue * 0.001;  // 0.1% tolerance
      if(currentPrice > maValue + threshold)
         return 1;   // Above MA (bullish)
      else if(currentPrice < maValue - threshold)
         return -1;  // Below MA (bearish)
      else
         return 0;   // Near MA (neutral)
   }
   
   // Calculate MTF Confluence Score (Feature #3)
   // Returns score 0.0 - 1.0 based on alignment with higher timeframes
   double CalculateMTFScore(ENUM_SIGNAL_TYPE signalType)
   {
      // Ensure MTF handles are initialized
      if(!InitializeMTFHandles())
      {
         if(m_debugMode)
            Print("[SignalManager] MTF Score: Handles not available, returning neutral score");
         return 0.5;  // Neutral score if MTF unavailable
      }
      
      double maH1_Value = 0, maH4_Value = 0;
      
      // Get H1 MA position
      int h1Position = GetPriceVsMA(PERIOD_H1, m_handleMA_H1, maH1_Value);
      
      // Get H4 MA position  
      int h4Position = GetPriceVsMA(PERIOD_H4, m_handleMA_H4, maH4_Value);
      
      if(m_debugMode)
      {
         PrintFormat("[SignalManager] MTF Analysis: H1 MA=%.5f (pos=%d), H4 MA=%.5f (pos=%d)", 
                     maH1_Value, h1Position, maH4_Value, h4Position);
      }
      
      // Scoring logic:
      // - Both H1 and H4 aligned with signal: 1.0 (full score)
      // - One aligned, one neutral: 0.75
      // - Both neutral: 0.5
      // - One contra: 0.25
      // - Both contra: 0.0
      
      int alignmentScore = 0;
      
      if(signalType == SIGNAL_BUY)
      {
         if(h1Position == 1) alignmentScore++;    // H1 bullish
         else if(h1Position == -1) alignmentScore--;  // H1 bearish
         
         if(h4Position == 1) alignmentScore++;    // H4 bullish
         else if(h4Position == -1) alignmentScore--;  // H4 bearish
      }
      else if(signalType == SIGNAL_SELL)
      {
         if(h1Position == -1) alignmentScore++;   // H1 bearish
         else if(h1Position == 1) alignmentScore--;   // H1 bullish
         
         if(h4Position == -1) alignmentScore++;   // H4 bearish
         else if(h4Position == 1) alignmentScore--;   // H4 bullish
      }
      
      // Convert alignment score to 0.0 - 1.0 range
      double mtfScore = 0.5;  // Default neutral
      
      if(alignmentScore >= 2)
         mtfScore = 1.0;      // Perfect alignment
      else if(alignmentScore == 1)
         mtfScore = 0.75;     // Good alignment
      else if(alignmentScore == 0)
         mtfScore = 0.5;      // Neutral
      else if(alignmentScore == -1)
         mtfScore = 0.25;     // Poor alignment
      else if(alignmentScore <= -2)
         mtfScore = 0.0;      // Complete contra
      
      return mtfScore;
   }

   // ==================================================================
   // ADVANCED FEATURE #1: SIGNAL SCORING SYSTEM
   // ==================================================================
   
   // Calculate Pattern Strength Score (40% weight)
   double CalculatePatternScore(ENUM_PATTERN_TYPE patternType, double patternRawScore)
   {
      // Normalize pattern score to 0.0 - 1.0 range
      // Pattern scores typically range 0-100, normalize to 0-1
      double normalizedScore = MathMin(1.0, MathMax(0.0, patternRawScore / 100.0));
      
      // Apply pattern type bonus
      double typeBonus = 0.0;
      switch(patternType)
      {
         case PATTERN_ENGULFING:
            typeBonus = 0.1;  // Strong reversal pattern
            break;
         case PATTERN_PINBAR:
            typeBonus = 0.08;  // Good rejection signal
            break;
         case PATTERN_INSIDE_BAR:
            typeBonus = 0.05;  // Consolidation breakout
            break;
         case PATTERN_DOJI:
            typeBonus = 0.03;  // Indecision, weaker signal
            break;
         default:
            typeBonus = 0.0;
            break;
      }
      
      return MathMin(1.0, normalizedScore + typeBonus);
   }
   
   // Calculate Market Regime Compatibility Score (20% weight)
   double CalculateRegimeScore(ENUM_SIGNAL_TYPE signalType)
   {
      // Use MarketRegimeFilter if available through MarketManager
      // For now, use simplified regime detection based on price action
      
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(m_symbol, m_period, 1, 50, rates) < 50)
         return 0.5;  // Neutral if can't get data
      
      // Simple trend detection using linear regression slope
      double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
      int n = 20;  // Use last 20 bars
      
      for(int i = 0; i < n; i++)
      {
         sumX += i;
         sumY += rates[i].close;
         sumXY += i * rates[i].close;
         sumX2 += i * i;
      }
      
      double slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
      
      // Determine regime based on slope
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double slopeInPoints = slope / point;
      
      ENUM_MARKET_REGIME regime = REGIME_NONE;
      
      if(MathAbs(slopeInPoints) < 5)
         regime = REGIME_RANGING_SIDEWAYS;
      else if(slopeInPoints > 15 || slopeInPoints < -15)
         regime = REGIME_TRENDING_STRONG;
      else if(slopeInPoints > 5 || slopeInPoints < -5)
         regime = REGIME_TRENDING_WEAK;
      else
         regime = REGIME_TRANSITION;
      
      // Score based on signal type vs regime
      double regimeScore = 0.5;  // Default neutral
      
      if(signalType == SIGNAL_BUY)
      {
         if(regime == REGIME_TRENDING_STRONG && slopeInPoints > 0)
            regimeScore = 1.0;   // Strong uptrend - best for buy
         else if(regime == REGIME_TRENDING_WEAK && slopeInPoints > 0)
            regimeScore = 0.75;  // Weak uptrend - good for buy
         else if(regime == REGIME_RANGING_SIDEWAYS)
            regimeScore = 0.5;   // Ranging - neutral
         else
            regimeScore = 0.25;  // Downtrend or transition - bad for buy
      }
      else if(signalType == SIGNAL_SELL)
      {
         if(regime == REGIME_TRENDING_STRONG && slopeInPoints < 0)
            regimeScore = 1.0;   // Strong downtrend - best for sell
         else if(regime == REGIME_TRENDING_WEAK && slopeInPoints < 0)
            regimeScore = 0.75;  // Weak downtrend - good for sell
         else if(regime == REGIME_RANGING_SIDEWAYS)
            regimeScore = 0.5;   // Ranging - neutral
         else
            regimeScore = 0.25;  // Uptrend or transition - bad for sell
      }
      
      return regimeScore;
   }
   
   // Calculate Volatility Score based on ATR normalization (15% weight)
   double CalculateVolatilityScore(double currentATR, double avgATR)
   {
      if(avgATR <= 0)
         return 0.5;  // Neutral if can't calculate
      
      double atrRatio = currentATR / avgATR;
      
      // Optimal volatility: ratio between 0.8 and 1.2
      // Too low (< 0.5): lack of momentum
      // Too high (> 2.0): erratic movement, risky
      
      if(atrRatio >= 0.8 && atrRatio <= 1.2)
         return 1.0;   // Optimal volatility
      else if((atrRatio >= 0.6 && atrRatio < 0.8) || (atrRatio > 1.2 && atrRatio <= 1.5))
         return 0.75;  // Acceptable volatility
      else if((atrRatio >= 0.4 && atrRatio < 0.6) || (atrRatio > 1.5 && atrRatio <= 2.0))
         return 0.5;   // Moderate concern
      else if(atrRatio < 0.4)
         return 0.25;  // Very low volatility - lack of momentum
      else
         return 0.0;   // Extremely high volatility - too risky
   }
   
   // Calculate News Impact Score (15% weight)
   // Low news impact = good for trading = high score
   double CalculateNewsScore()
   {
      // Try to get news impact from MarketManager if available
      // For now, use simplified approach based on time
      
      datetime now = TimeCurrent();
      MqlDateTime dtNow;
      TimeToStruct(now, dtNow);
      
      int hour = dtNow.hour;
      int dayOfWeek = dtNow.day_of_week;
      
      // Check if near major news times (simplified)
      // Major news often at 8:30, 10:00, 14:30 EST
      
      bool nearNewsTime = false;
      
      // London session open (2:00-4:00 GMT)
      if(hour >= 2 && hour <= 4)
         nearNewsTime = true;
      
      // NY session open (13:00-15:00 GMT)  
      if(hour >= 13 && hour <= 15)
         nearNewsTime = true;
      
      // Friday afternoon (avoid weekend risk)
      if(dayOfWeek == 5 && hour >= 18)
         nearNewsTime = true;
      
      // Sunday night (market open volatility)
      if(dayOfWeek == 0 && hour < 2)
         nearNewsTime = true;
      
      if(nearNewsTime)
         return 0.3;  // Higher news risk = lower score
      else
         return 1.0;  // Normal conditions = full score
   }

   //+------------------------------------------------------------------+\n   //| PRIVATE: Signal Detection Logic (Core Business)                 |\n   //+------------------------------------------------------------------+\nprivate:
   // === DATA VALIDATION - FIX: Prevent look-ahead bias and outlier/stale data ===
   bool ValidateCandleData(const MqlRates &rates[], int shift)
   {
      if(shift >= ArraySize(rates) || shift < 0) return false;
      
      // LOOK-AHEAD BIAS FIX: Ensure we only use confirmed closed bars
      // Shift 0 in our array = last CLOSED bar (already shifted by 1 in FetchCandleBatch)
      double currentRange = rates[shift].high - rates[shift].low;
      double prevRange = (shift + 1 < ArraySize(rates)) ? rates[shift + 1].high - rates[shift + 1].low : currentRange;
      
      // Outlier detection: Range > 5x previous candle (spike/wick anomaly)
      if(prevRange > 0 && currentRange > (prevRange * 5.0))
      {
         if(m_debugMode)
            PrintFormat("[SignalManager] Outlier candle at shift %d: Range %.2f vs Prev %.2f", shift, currentRange, prevRange);
         return false;
      }
      
      // Stale data: Zero range or invalid OHLC
      if(currentRange <= 0 || 
         rates[shift].high < rates[shift].low ||
         rates[shift].open <= 0 || rates[shift].close <= 0)
      {
         if(m_debugMode)
            PrintFormat("[SignalManager] Invalid/stale data at shift %d: Range=%.2f O=%.5f H=%.5f L=%.5f C=%.5f", 
                       shift, currentRange, rates[shift].open, rates[shift].high, rates[shift].low, rates[shift].close);
         return false;
      }
      
      // Volume validation (if available)
      if(rates[shift].tick_volume <= 0)
      {
         if(m_debugMode)
            PrintFormat("[SignalManager] Zero volume at shift %d - possible data gap", shift);
         // Don't reject - some brokers have zero volume on historical data
      }
      
      // Gap detection: Large gap from previous close (risky but not rejected)
      if(shift + 1 < ArraySize(rates))
      {
         double gap = MathAbs(rates[shift].open - rates[shift + 1].close);
         if(gap > (prevRange * 2.0))
         {
            if(m_debugMode)
               PrintFormat("[SignalManager] Large gap detected at shift %d: Gap=%.2f (%.1fx prev range)", 
                          shift, gap, gap / prevRange);
            // Don't reject - gaps are valid market behavior, just log for awareness
         }
      }
      
      // DOJI detection: Very small body relative to range (indecision candle)
      double body = MathAbs(rates[shift].close - rates[shift].open);
      if(currentRange > 0 && (body / currentRange) < 0.1)
      {
         if(m_debugMode)
            PrintFormat("[SignalManager] Doji candle at shift %d - indecision, lower confidence", shift);
         // Don't reject, but could be used for signal scoring
      }
      
      return true;
   }
   
   // === ENHANCED DATA VALIDATION with ATR normalization ===
   bool ValidateCandleDataWithATR(const MqlRates &rates[], int shift, double atrPoints)
   {
      if(!ValidateCandleData(rates, shift)) return false;
      
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double atrPrice = atrPoints * point;
      
      // Normalize range by ATR to detect abnormal candles
      double rangeInATR = (rates[shift].high - rates[shift].low) / atrPrice;
      
      // Reject candles that are too large (> 3x ATR) - potential spike/anomaly
      if(rangeInATR > cfg.max_signal_atr * 1.5)
      {
         if(m_debugMode)
            PrintFormat("[SignalManager] Candle too large: %.2f ATR (max %.2f)", rangeInATR, cfg.max_signal_atr * 1.5);
         return false;
      }
      
      // Warn on very small candles (< 0.2x ATR) - low momentum
      if(rangeInATR < 0.2)
      {
         if(m_debugMode)
            PrintFormat("[SignalManager] Candle very small: %.2f ATR - low momentum", rangeInATR);
         // Don't reject, but affects scoring
      }
      
      return true;
   }

   // === FILTER METHODS (dipisah agar mudah di-test) ===

   bool PassZoneTouchFilter(int shift, int dir, double zonePrice,
                            double atrPoints, double dynamicMult, string &reason,
                            const MqlRates &rates[], int zoneStrength = 0)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      double extreme = (dir == 1) ? rates[shift].low : rates[shift].high;
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double zoneWidth = (atrPoints * dynamicMult) * point;
      double multiplier = (cfg.entry_mode == MODE_SAFE) ? 0.5 : 1.0;

      if (cfg.use_adaptive_zone_buffer && zoneStrength >= cfg.min_touches_strong)
      {
         multiplier *= cfg.strong_zone_buffer_mult;
      }

      bool ok = (dir == 1) ? (extreme <= zonePrice + (zoneWidth * multiplier)) : (extreme >= zonePrice - (zoneWidth * multiplier));

      if (!ok)
         reason = "Not touching zone";
      return ok;
   }

   bool PassContextFilter(int shift, double atrPoints, string &reason,
                          const MqlRates &rates[], int dir)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      double o = rates[shift].open, h = rates[shift].high;
      double l = rates[shift].low, c = rates[shift].close;
      double range = h - l;
      double body = MathAbs(o - c);

      // Pastikan range tidak 0 untuk menghindari division by zero
      if (range <= 0) return false;

      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double maxAllowedRange = cfg.max_signal_atr * atrPoints * point;
      if (range > maxAllowedRange)
      {
         reason = "Signal too large";
         return false;
      }
      if ((body / range) > cfg.anti_breakout_pct)
      {
         reason = "Body too long";
         return false;
      }

      double threshold = atrPoints * cfg.momentum_threshold_atr * point;
      int pushCount = 0;

      for (int i = 1; i <= 3; i++)
      {
         if (shift + i + 1 >= ArraySize(rates))
            break;

         double curO = rates[shift + i].open, curC = rates[shift + i].close;
         double curH = rates[shift + i].high, curL = rates[shift + i].low;
         double prevH = rates[shift + i + 1].high, prevL = rates[shift + i + 1].low;
         double curBody = MathAbs(curO - curC);

         bool isPush = (dir == 1) ? (curH < prevH || (curC < curO && curBody > threshold)) : (curL > prevL || (curC > curO && curBody > threshold));

         if (isPush)
            pushCount++;
         else
            break;
      }

      if (pushCount < 1)
      {
         reason = "No momentum push to zone";
         return false;
      }
      return true;
   }

   bool PassMTFFilter(int dir, double referencePrice,
                      double htfSupport, double htfResistance,
                      double atrPoints, int supHtfAlign, int resHtfAlign,
                      int &bias, string &reason)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      bias = GetMTFBias(referencePrice, htfSupport, htfResistance, atrPoints);

      if (!cfg.use_mtf)
         return true;

      // Block trades that are contra to HTF zone alignment
      if ((dir == 1 && supHtfAlign == -1) || (dir == -1 && resHtfAlign == -1))
      {
         reason = "Blocked by HTF zone contra-alignment";
         return false;
      }

      int qualityScore = dir * bias;

      if (qualityScore == 1)
      {
         reason = "High Quality Signal (MTF Aligned)";
         return true;
      }
      if (qualityScore == 0)
      {
         if ((dir == 1 && supHtfAlign == 1) || (dir == -1 && resHtfAlign == 1))
            reason = "Standard Quality Signal (HTF support confirmed)";
         else
            reason = "Standard Quality Signal (MTF Neutral)";
         return true;
      }

      reason = "Low Quality (Blocked by MTF Contra-Bias)";
      return false;
   }

   bool PassOpportunityFilter(int dir, int shift, double atrPoints,
                              double support, double resistance,
                              double patternExtreme, string &reason,
                              const MqlRates &rates[])
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      double entryPrice = rates[shift].close;
      double target = (dir == 1) ? resistance : support;

      // 1. Hitung Proyeksi TP (Selalu ke SR lawan dengan buffer)
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double tpBuffer = cfg.tp_buffer_atr * atrPoints * point;
      double projectedTP = (dir == 1) ? (target - tpBuffer) : (target + tpBuffer);
      double profitDist = MathAbs(entryPrice - projectedTP);

      // 2. Hitung Proyeksi SL
      double slBuffer = cfg.sl_buffer_atr * atrPoints * point;
      double baseSL = (cfg.tpsl_mode == TPSL_PATTERN) ? patternExtreme : ((dir == 1) ? support : resistance);
      double projectedSL = (dir == 1) ? (baseSL - slBuffer) : (baseSL + slBuffer);

      // Pastikan riskDist minimal 1 point untuk menghindari pembagian nol
      double riskDist = MathMax(MathAbs(entryPrice - projectedSL), point);

      // 3. Validasi Jarak minimum TP
      double minTPDist = (atrPoints * cfg.min_tp_distance_atr) * point;
      if (profitDist < minTPDist)
      {
         reason = "TP distance < Min ATR";
         return false;
      }

      // 4. Validasi Risk:Reward (Minimal 1:1)
      if (profitDist < riskDist * 1.0)
      {
         reason = StringFormat("Poor R:R (Risk:%.1fpt TP:%.1fpt)", riskDist/point, profitDist/point);
         return false;
      }

      return true;
   }

   // === MAIN DETECTION ENGINE ===

   bool DetectSignalCore(SignalDecision &decision,
                         double atrPoints,
                         double support, double resistance,
                         double htfSupport, double htfResistance,
                         bool isSupBroken, bool isResBroken,
                         double supBufferMult, double resBufferMult,
                         int supHtfAlign, int resHtfAlign)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      ZeroMemory(decision);
      string reason = "No pattern detected";

      // Validate data availability
      if (Bars(m_symbol, m_period) < cfg.pattern_lookback + 5)
      {
         decision.reason = "Insufficient history data";
         return false;
      }

      // === OPTIMIZATION: Batch fetch candles once ===
      // FIX: Start from shift 1 to skip currently forming bar (rates[0])
      // Only use CLOSED bars for signal detection to prevent repainting
      MqlRates rates[];
      if (!FetchCandleBatch(1, cfg.pattern_lookback + 5, rates))  // +5 for safety margin
      {
         decision.reason = "Failed to fetch candle data";
         return false;
      }

      // Validate candle data - reject outliers and stale data
      if(!ValidateCandleData(rates, 0))  // Check first closed bar (shift 1 in absolute terms)
      {
         decision.reason = "Invalid/outlier candle data detected";
         return false;
      }

      // Loop through CLOSED bars only (shift 0 in our array = rates[1] in absolute terms)
      for (int shift = 0; shift < cfg.pattern_lookback; shift++)
      {
         string currentFilterReason = "";
         int dir = 0;
         double signalPrice = 0;
         ENUM_PATTERN_TYPE pType = PATTERN_NONE;
         string patternReason = "";
         double pScore = 0;
         double pSLMult = 1.0;

         // OPTIMIZATION V1.20: Call static method directly instead of instance method
         if (!PatternManager::Detect(pType, cfg, rates, shift, atrPoints, dir, signalPrice, pScore, pSLMult, patternReason))
            continue;

         double zonePrice = (dir == 1) ? support : resistance;
         double currentBufferMult = (dir == 1) ? supBufferMult : resBufferMult;
         int currentHtfAlign = (dir == 1) ? supHtfAlign : resHtfAlign;
         ENUM_ORDER_TYPE currentOrderType = (dir == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

         // === FILTER PIPELINE ===
         // 1. Zone Broken Filter
         if ((dir == 1 && isSupBroken) || (dir == -1 && isResBroken))
         {
            reason = "Zone broken (Price closed outside)";
            continue;
         }

         // 3. Zone Touch Filter
         int zoneStrength = (dir == 1) ? m_marketData.supStrength : m_marketData.resStrength;
         if (!PassZoneTouchFilter(shift, dir, zonePrice, atrPoints, currentBufferMult, currentFilterReason, rates, zoneStrength))
         {
            reason = currentFilterReason;
            continue;
         }

         // 4. Context/Momentum Filter
         if (!PassContextFilter(shift, atrPoints, currentFilterReason, rates, dir))
         {
            reason = currentFilterReason;
            continue;
         }

         // 4. MTF Quality & Alignment Filter (Digabung)
         int bias = 0;
         if (!PassMTFFilter(dir, rates[shift].close, htfSupport, htfResistance, atrPoints,
                            supHtfAlign, resHtfAlign, bias, currentFilterReason))
         {
            reason = currentFilterReason;
            continue;
         }

         // === DYNAMIC CONFLUENCE SCORING ===
         double finalConfluenceScore = pScore;

         // Bonus jika searah MTF
         if (cfg.use_mtf)
         {
            if (((dir == 1 && bias > 0) || (dir == -1 && bias < 0)) ||
                ((dir == 1 && supHtfAlign == 1) || (dir == -1 && resHtfAlign == 1)))
               finalConfluenceScore += cfg.mtf_confluence_bonus;
         }

         // Bonus jika selaras dengan HTF zone alignment
         if (currentBufferMult < cfg.strong_zone_threshold)
            finalConfluenceScore += cfg.strong_zone_bonus;

         // 9. Signal Cooldown Filter - NEW: Dynamic Cooldown untuk HQ Setup
         bool isHighQualitySetup = (finalConfluenceScore >= cfg.hq_threshold);
         int effectiveCooldownBars = cfg.signal_cooldown_bars;

         if (cfg.use_dynamic_cooldown && isHighQualitySetup)
         {
            effectiveCooldownBars = cfg.reduced_cooldown_bars; // Bypass cooldown normal untuk HQ setup
         }

         if (IsSignalCooldownActiveWithCustomBars(signalPrice, atrPoints, effectiveCooldownBars))
         {
            reason = "Signal cooldown active";
            continue;
         }

         // === SIGNAL FOUND: Populate decision struct ===
         decision.valid = true;
         decision.orderType = currentOrderType;
         decision.signalPrice = signalPrice;
         decision.patternType = pType;
         decision.zonePrice = zonePrice;
         decision.signalShift = shift;
         decision.slMultiplier = pSLMult;
         decision.bias = bias;
         decision.reason = patternReason + (currentFilterReason != "" ? " | " + currentFilterReason : "");

         // Register zone usage to prevent duplicate signals
         RegisterZoneUse(dir == 1, zonePrice);

         if (m_debugMode)
            PrintFormat("[PASR Signal] ✓ %s @ %.5f | Pattern: %s | %s",
                        (dir == 1 ? "BUY" : "SELL"), signalPrice, EnumToString(pType), decision.reason);

         return true; // Early return on first valid signal
      }

      // No signal found
      decision.reason = (reason == "") ? "No signal" : reason;
      return false;
   }

   // NEW: Detect signal specifically for recovery
   bool DetectRecoverySignal(SignalDecision &decision,
                             ulong originalTicket,
                             double slHitPrice,
                             int originalDirection,
                             double atrPoints,
                             double support, double resistance,
                             double htfSupport, double htfResistance,
                             bool isSupBroken, bool isResBroken,
                             double supBufferMult, double resBufferMult,
                             int supHtfAlign, int resHtfAlign)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      ZeroMemory(decision);
      string reason = "No recovery pattern detected";

      if (!cfg.recovery_use)
         return false;

      // Fetch candles around the SL hit price
      MqlRates rates[];
      // Look for patterns on the last closed bar (shift 0) and subsequent bars for context
      if (!FetchCandleBatch(0, 5, rates)) // Need at least 5 bars for patterns that look at shift+4
      {
         decision.reason = "Failed to fetch candle data for recovery";
         return false;
      }

      // We are looking for a reversal pattern in the opposite direction of the original trade
      int targetDir = -originalDirection;

      // Check last closed bar (shift 0) for a reversal pattern
      int shift = 0;
      // string currentFilterReason = ""; // Not used here, patternReason is enough
      int dir = 0;
      double signalPrice = 0;
      ENUM_PATTERN_TYPE pType = PATTERN_NONE;
      string patternReason = "";
      double pScore = 0;
      double pSLMult = 1.0;

      // OPTIMIZATION V1.20: Call static method directly instead of instance method
      if (!PatternManager::Detect(pType, cfg, rates, shift, atrPoints, dir, signalPrice, pScore, pSLMult, patternReason))
         return false;

      // Ensure pattern is in the target reversal direction
      if (dir != targetDir)
         return false;

      // Check if pattern score meets recovery threshold
      if (pScore < cfg.recovery_pattern_score_threshold)
      {
         reason = StringFormat("Recovery pattern score too low (%.2f < %.2f)", pScore, cfg.recovery_pattern_score_threshold);
         return false;
      }

      // Check if the signal is near the SL hit price (within tolerance)
      double tolerance = atrPoints * cfg.recovery_zone_tolerance_atr * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if (MathAbs(signalPrice - slHitPrice) > tolerance)
      {
         reason = StringFormat("Recovery signal too far from SL hit price (%.5f vs %.5f)", signalPrice, slHitPrice);
         return false;
      }

      // All checks passed, this is a valid recovery signal
      decision.valid = true;
      decision.orderType = (targetDir == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      decision.signalPrice = signalPrice;
      decision.patternType = pType;
      decision.slMultiplier = pSLMult;
      decision.bias = targetDir; // Bias is the direction of the recovery signal
      decision.reason = "RECOVERY SIGNAL: " + patternReason;
      return true;
   }

   //+------------------------------------------------------------------+
   //| PUBLIC: Event Handler Implementation (IEventHandler)           |
   //+------------------------------------------------------------------+
public:
   // Constructor: Auto-subscribe to relevant events
   SignalManager() : IManager("SignalManager", 30)
   {
      m_lastBuyZonePrice = 0.0;
      m_lastSellZonePrice = 0.0;
      m_lastBuyZoneBar = 0;
      m_lastSellZoneBar = 0;
      m_marketGateOpen = true;
      m_marketEntryAllowed = true;
      
      // Initialize advanced feature state variables
      m_lastSignalType = SIGNAL_NONE;
      m_signalStabilityCount = 0;
      m_requiredStabilityTicks = 3;  // Default: 3 stable ticks
      m_dynamicThreshold = 0.65;     // Default threshold
      m_baseThreshold = 0.65;
      m_mtfHandlesInitialized = false;
      m_handleMA_H1 = INVALID_HANDLE;
      m_handleMA_H4 = INVALID_HANDLE;
      ArraySetAsSeries(m_maH1_Buffer, true);
      ArraySetAsSeries(m_maH4_Buffer, true);
   }

   virtual void Deinit() override
   {
      ArrayFree(m_failedZones);
      ArrayFree(m_signalCooldowns); // FIX: Free signal cooldowns
      ReleaseMTFHandles();          // Release MTF indicator handles
      IManager::Deinit();
   }

   virtual void DeclareEvents() override
   {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_ZONE_UPDATE);
      AddEvent(EVENT_ID_RECOVERY_OPPORTUNITY);
      AddEvent(EVENT_ID_MARKET_GATE);
   }

   //+------------------------------------------------------------------+
   //| PUBLIC: Event Handler Methods                                   |
   //+------------------------------------------------------------------+
public:
   // --- NewBar Event: MAIN SIGNAL DETECTION TRIGGER ---
   virtual void OnNewBar(NewBarEvent *e) override
   {
      if (CheckPointer(e) == POINTER_INVALID || !m_initialized)
         return;
      if (e.barOpenTime == m_lastProcessedBar)
         return;
      if (CheckPointer(m_data) == POINTER_INVALID)
         return;

      if (!m_marketGateOpen || !m_marketEntryAllowed)
      {
         if (m_debugMode)
            PrintFormat("[SignalManager] Market gate closed or cooldown active. gateOpen=%s entryAllowed=%s",
                        m_marketGateOpen ? "true" : "false",
                        m_marketEntryAllowed ? "true" : "false");
         m_lastProcessedBar = e.barOpenTime;
         return;
      }

      // === SIGNAL DETECTION EXECUTION ===
      ProcessSignalOnNewBar(e);
      m_lastProcessedBar = e.barOpenTime;
   }

   // --- ConfigReload Event ---
   virtual void OnConfigReload(ConfigReloadEvent *e) override
   {
      RefreshConfigCache();
   }

   // --- EmergencyStop Event ---
   virtual void OnEmergencyStop(EmergencyStopEvent *e) override
   {
      if (m_debugMode)
         Log("Emergency Stop: Clearing pending signals.");
      m_marketGateOpen = false;
      m_marketEntryAllowed = false;
   }

   // --- Heartbeat Event ---
   virtual void OnHeartbeat(HeartbeatEvent *e) override
   {
      CleanupFailedZones();
      CleanupSignalCooldowns(); // FIX: Call cleanup for signal cooldowns
   }

   virtual void OnZoneUpdate(ZoneUpdateEvent *ze) override
   {
      m_marketData.atrPoints = ze.atrPoints;
      m_marketData.support = ze.support;
      m_marketData.resistance = ze.resistance;
      m_marketData.htfSupport = ze.htfSupport;
      m_marketData.htfResistance = ze.htfResistance;
      m_marketData.isSupBroken = ze.isSupBroken;
      m_marketData.isResBroken = ze.isResBroken;
      m_marketData.supBufferMult = ze.supBufferMult;
      m_marketData.resBufferMult = ze.resBufferMult;
      m_marketData.supHtfAlign = ze.supHtfAlign;
      m_marketData.resHtfAlign = ze.resHtfAlign;
      m_marketData.supStrength = ze.supStrength;
      m_marketData.resStrength = ze.resStrength;
   }

   virtual void OnMarketGate(MarketGateEvent *mg) override
   {
      m_marketGateOpen = mg.gateOpen;
      m_marketEntryAllowed = mg.entryAllowed;
   }

   virtual void OnRecoveryOpportunity(RecoveryOpportunityEvent *roe) override
   {
      if (CheckPointer(roe) == POINTER_INVALID || !m_initialized)
         return;
      if (CheckPointer(m_data) == POINTER_INVALID)
         return;
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      if (!cfg.recovery_use || !m_marketEntryAllowed)
         return;

      // Pastikan data zona SR sudah tersedia
      if (m_marketData.support <= 0 || m_marketData.resistance <= 0)
      {
         if (m_debugMode)
            Log(StringFormat("Recovery search aborted for ticket %d: Missing SR data.", roe.originalTicket));
         return;
      }

      SignalDecision recoveryDecision;
      if (DetectRecoverySignal(recoveryDecision,
                               roe.originalTicket,
                               roe.slHitPrice,
                               roe.direction,
                               roe.atrPoints,
                               m_marketData.support, m_marketData.resistance,
                               m_marketData.htfSupport, m_marketData.htfResistance,
                               m_marketData.isSupBroken, m_marketData.isResBroken,
                               m_marketData.supBufferMult, m_marketData.resBufferMult,
                               m_marketData.supHtfAlign, m_marketData.resHtfAlign))
      {
         RecoverySignalEvent *recSigEvent = new RecoverySignalEvent(
             roe.originalTicket, recoveryDecision, roe.atrPoints, m_marketData.support, m_marketData.resistance);
         DispatchEvent(recSigEvent);
         
         if (m_debugMode)
            Log(StringFormat("Recovery signal detected for original trade %d: %s", roe.originalTicket, recoveryDecision.reason));
      }
      else if (m_debugMode)
      {
         Log(StringFormat("No immediate recovery signal found for original trade %d.", roe.originalTicket));
      }
   }

   virtual void OnCustomEvent(Event *e) override
   {
      // Placeholder for other custom signals
   }
   //+------------------------------------------------------------------+
   //| PUBLIC: Integration Methods (for other modules)                 |
   //+------------------------------------------------------------------+
public:
   // Register a failed zone externally (e.g., from TradeManager on loss)
   void NotifyPatternFailure(double zonePrice)
   {
      RegisterFailure(zonePrice);
   }

   // ==================================================================
   // ADVANCED FEATURE #2: DYNAMIC THRESHOLD CALCULATION
   // ==================================================================
   
   // Calculate dynamic score threshold based on market conditions
   double CalculateDynamicThreshold()
   {
      datetime now = TimeCurrent();
      
      // Only recalculate every bar to avoid excessive computation
      if(now - m_lastThresholdUpdate < PeriodSeconds(m_period))
         return m_dynamicThreshold;
      
      m_lastThresholdUpdate = now;
      
      double threshold = m_baseThreshold;  // Start with base (0.65)
      
      // Get current spread
      double currentSpread = (SymbolInfoInteger(m_symbol, SYMBOL_SPREAD) * SymbolInfoDouble(m_symbol, SYMBOL_POINT));
      double avgSpread = m_avgSpread > 0 ? m_avgSpread : currentSpread;
      
      // Factor 1: Market Regime (from MarketRegime or simplified detection)
      // If CHOPPY or HIGH_VOL: increase threshold
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(m_symbol, m_period, 1, 30, rates) >= 30)
      {
         // Simple volatility check using recent range
         double highestHigh = 0, lowestLow = DBL_MAX;
         for(int i = 0; i < 30; i++)
         {
            if(rates[i].high > highestHigh) highestHigh = rates[i].high;
            if(rates[i].low < lowestLow) lowestLow = rates[i].low;
         }
         double range = highestHigh - lowestLow;
         double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
         double rangeInPoints = range / point;
         
         // High volatility regime (large range)
         if(rangeInPoints > 100)  // Adjust based on symbol
         {
            threshold += 0.10;  // Choppy/high vol = higher threshold
            if(m_debugMode)
               PrintFormat("[SignalManager] Dynamic Threshold: +0.10 (High Volatility regime)");
         }
         else if(rangeInPoints < 30)
         {
            // Very low volatility - might be ranging/choppy
            threshold += 0.05;
            if(m_debugMode)
               PrintFormat("[SignalManager] Dynamic Threshold: +0.05 (Low Volatility regime)");
         }
         
         // Trending detection using slope
         double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
         int n = 20;
         for(int i = 0; i < n; i++)
         {
            sumX += i;
            sumY += rates[i].close;
            sumXY += i * rates[i].close;
            sumX2 += i * i;
         }
         double slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
         double slopeInPoints = slope / point;
         
         // Strong trend = lower threshold (more opportunities)
         if(MathAbs(slopeInPoints) > 15)
         {
            threshold -= 0.10;  // Strong trend = easier to trade
            if(m_debugMode)
               PrintFormat("[SignalManager] Dynamic Threshold: -0.10 (Strong Trending regime)");
         }
      }
      
      // Factor 2: Spread widening
      if(avgSpread > 0 && currentSpread > (avgSpread * 2.0))
      {
         threshold += 0.10;  // Spread > 2x average = higher threshold
         if(m_debugMode)
            PrintFormat("[SignalManager] Dynamic Threshold: +0.10 (Spread widened: %.2f vs avg %.2f)", 
                        currentSpread, avgSpread);
      }
      
      // Ensure threshold stays within reasonable bounds
      m_dynamicThreshold = MathMax(0.45, MathMin(0.85, threshold));
      
      if(m_debugMode)
         PrintFormat("[SignalManager] Dynamic Threshold calculated: %.3f", m_dynamicThreshold);
      
      return m_dynamicThreshold;
   }

   // ==================================================================
   // ADVANCED FEATURE #4: SIGNAL PERSISTENCE & DEBOUNCING
   // ==================================================================
   
   // Check if signal is stable (passed debouncing)
   bool IsSignalStable(ENUM_SIGNAL_TYPE currentType)
   {
      // If signal type changed, reset counter
      if(currentType != m_lastSignalType)
      {
         m_signalStabilityCount = 1;  // Start counting for new type
         m_lastSignalType = currentType;
         
         if(m_debugMode && currentType != SIGNAL_NONE)
            PrintFormat("[SignalManager] Signal type changed to %s, stability count reset to 1", 
                        EnumToString(currentType));
         
         return false;  // Not stable yet
      }
      
      // Same signal type - increment counter
      if(currentType != SIGNAL_NONE)
      {
         m_signalStabilityCount++;
         
         if(m_debugMode)
            PrintFormat("[SignalManager] Signal %s stable for %d ticks (need %d)", 
                        EnumToString(currentType), m_signalStabilityCount, m_requiredStabilityTicks);
         
         // Check if reached required stability
         if(m_signalStabilityCount >= m_requiredStabilityTicks)
         {
            if(m_debugMode)
               PrintFormat("[SignalManager] Signal %s PASSED debouncing (%d >= %d ticks)", 
                           EnumToString(currentType), m_signalStabilityCount, m_requiredStabilityTicks);
            return true;
         }
      }
      else
      {
         // No signal - reset
         m_signalStabilityCount = 0;
      }
      
      return false;  // Not yet stable
   }
   
   // Set required stability ticks (configurable)
   void SetRequiredStabilityTicks(int ticks)
   {
      m_requiredStabilityTicks = MathMax(1, ticks);
   }

   // ==================================================================
   // ADVANCED FEATURE #5: SIGNAL REASONING & EXPLAINABILITY
   // ==================================================================
   
   // Build detailed reasoning string for signal decision
   string BuildReasoning(SignalResult &result, ENUM_PATTERN_TYPE patternType, 
                         ENUM_MARKET_REGIME regime, int mtfAlignment)
   {
      string reasoning = "";
      
      if(result.type == SIGNAL_NONE)
      {
         // Signal rejected
         if(result.score < result.dynamicThreshold)
         {
            reasoning = StringFormat("Signal rejected. Score %.2f below dynamic threshold %.2f. ", 
                                     result.score, result.dynamicThreshold);
            
            // Add specific reason for low score
            if(result.patternScore < 0.4)
               reasoning += "Reason: Weak pattern strength. ";
            if(result.regimeScore < 0.3)
               reasoning += "Reason: Unfavorable market regime. ";
            if(result.mtfScore < 0.3)
               reasoning += "Reason: MTF contra-alignment. ";
            if(result.volatilityScore < 0.3)
               reasoning += "Reason: Extreme volatility. ";
            if(result.newsScore < 0.5)
               reasoning += "Reason: High news impact period. ";
         }
         else if(!result.isStable)
         {
            reasoning = StringFormat("Signal pending stability (%d/%d ticks). ", 
                                     result.stabilityCount, m_requiredStabilityTicks);
         }
         else
         {
            reasoning = "No valid pattern detected. ";
         }
         
         // Add regime info
         switch(regime)
         {
            case REGIME_CHOPPY_HIGH_VOL:
               reasoning += "Market: Choppy high volatility. ";
               break;
            case REGIME_RANGING_SIDEWAYS:
               reasoning += "Market: Ranging/sideways. ";
               break;
            case REGIME_TRENDING_STRONG:
               reasoning += "Market: Strong trending. ";
               break;
            default:
               reasoning += "Market: Transitional. ";
               break;
         }
      }
      else
      {
         // Valid signal
         string typeStr = (result.type == SIGNAL_BUY) ? "BUY" : "SELL";
         
         reasoning = StringFormat("%s Signal (Score: %.2f, Confidence: %s). ", 
                                  typeStr, result.score, result.ConfidenceToString());
         
         // Pattern info
         reasoning += StringFormat("Pattern: %s (strength: %.2f). ", 
                                   EnumToString(patternType), result.patternScore);
         
         // Regime info
         switch(regime)
         {
            case REGIME_TRENDING_STRONG:
               reasoning += "Regime: Strong Trend (compatible). ";
               break;
            case REGIME_TRENDING_WEAK:
               reasoning += "Regime: Weak Trend (neutral). ";
               break;
            case REGIME_RANGING_SIDEWAYS:
               reasoning += "Regime: Ranging (caution). ";
               break;
            case REGIME_CHOPPY_HIGH_VOL:
               reasoning += "Regime: Choppy High Vol (avoid). ";
               break;
            default:
               reasoning += "Regime: Transition (uncertain). ";
               break;
         }
         
         // MTF info
         if(mtfAlignment >= 2)
            reasoning += "MTF H1/H4: Aligned (strong confluence). ";
         else if(mtfAlignment == 1)
            reasoning += "MTF H1/H4: Partially aligned. ";
         else if(mtfAlignment == 0)
            reasoning += "MTF H1/H4: Neutral. ";
         else if(mtfAlignment == -1)
            reasoning += "MTF H1/H4: Partially contra (weakness). ";
         else
            reasoning += "MTF H1/H4: Contra-aligned (warning). ";
         
         // Volatility & News
         if(result.volatilityScore >= 0.75)
            reasoning += "Volatility: Optimal. ";
         else if(result.volatilityScore >= 0.5)
            reasoning += "Volatility: Acceptable. ";
         else
            reasoning += "Volatility: Suboptimal. ";
            
         if(result.newsScore >= 0.8)
            reasoning += "News: Low impact. ";
         else
            reasoning += "News: Elevated risk period. ";
         
         // Stability status
         if(result.isStable)
            reasoning += StringFormat("Stability: Confirmed (%d ticks). ", result.stabilityCount);
         else
            reasoning += StringFormat("Stability: Pending (%d/%d ticks). ", 
                                      result.stabilityCount, m_requiredStabilityTicks);
      }
      
      m_lastReasoning = reasoning;
      return reasoning;
   }

   // ==================================================================
   // MAIN EVALUATION METHOD - Feature #1 Integration
   // ==================================================================
   
   // Main signal evaluation method returning SignalResult struct
   SignalResult Evaluate()
   {
      SignalResult result;
      result.timestamp = TimeCurrent();
      
      // Step 1: Calculate dynamic threshold (Feature #2)
      result.dynamicThreshold = CalculateDynamicThreshold();
      
      // Step 2: Run existing signal detection
      SignalDecision decision;
      double atrPoints = m_marketData.atrPoints;
      
      if(atrPoints <= 0 || m_marketData.support <= 0 || m_marketData.resistance <= 0)
      {
         result.type = SIGNAL_NONE;
         result.reasoning = "Missing market data (ATR/SR levels)";
         return result;
      }
      
      bool signalFound = DetectSignalCore(decision, 
                                          atrPoints,
                                          m_marketData.support, 
                                          m_marketData.resistance,
                                          m_marketData.htfSupport, 
                                          m_marketData.htfResistance,
                                          m_marketData.isSupBroken, 
                                          m_marketData.isResBroken,
                                          m_marketData.supBufferMult, 
                                          m_marketData.resBufferMult,
                                          m_marketData.supHtfAlign, 
                                          m_marketData.resHtfAlign);
      
      // Step 3: Determine signal type
      if(signalFound)
      {
         result.type = (decision.orderType == ORDER_TYPE_BUY) ? SIGNAL_BUY : SIGNAL_SELL;
      }
      else
      {
         result.type = SIGNAL_NONE;
         result.reasoning = "No pattern detected meeting criteria";
         return result;
      }
      
      // Step 4: Calculate component scores (Feature #1)
      ENUM_PATTERN_TYPE patternType = decision.patternType;
      
      // Pattern Score (40% weight)
      result.patternScore = CalculatePatternScore(patternType, 75.0);  // Assume 75 base score
      \n      // Regime Score (20% weight)\n      result.regimeScore = CalculateRegimeScore(result.type);\n      \n      // Volatility Score (15% weight)\n      double currentATR = atrPoints * SymbolInfoDouble(m_symbol, SYMBOL_POINT);\n      double avgATR = iATR(m_symbol, m_period, 14, 50) * SymbolInfoDouble(m_symbol, SYMBOL_POINT);\n      result.volatilityScore = CalculateVolatilityScore(currentATR, avgATR);\n      \n      // News Score (15% weight)\n      result.newsScore = CalculateNewsScore();\n      \n      // MTF Score (10% weight) (Feature #3)\n      result.mtfScore = CalculateMTFScore(result.type);\n      \n      // Step 5: Calculate weighted final score\n      result.score = (result.patternScore * 0.40) +\n                     (result.regimeScore * 0.20) +\n                     (result.volatilityScore * 0.15) +\n                     (result.newsScore * 0.15) +\n                     (result.mtfScore * 0.10);\n      \n      // Step 6: Determine confidence level\n      if(result.score >= 0.85)\n         result.confidence = CONFIDENCE_VERY_HIGH;\n      else if(result.score >= 0.70)\n         result.confidence = CONFIDENCE_HIGH;\n      else if(result.score >= 0.50)\n         result.confidence = CONFIDENCE_MEDIUM;\n      else\n         result.confidence = CONFIDENCE_LOW;\n      \n      // Step 7: Apply debouncing (Feature #4)\n      result.isStable = IsSignalStable(result.type);\n      result.stabilityCount = m_signalStabilityCount;\n      \n      // Step 8: Check against dynamic threshold\n      if(result.score < result.dynamicThreshold)\n      {\n         result.type = SIGNAL_NONE;  // Reject signal below threshold\n         result.reasoning = StringFormat("Score %.2f below threshold %.2f", 
                                         result.score, result.dynamicThreshold);\n         return result;\n      }\n      \n      // Step 9: Build detailed reasoning (Feature #5)\n      ENUM_MARKET_REGIME regime = REGIME_NONE;\n      int mtfAlign = 0;\n      \n      // Quick regime estimate\n      if(result.regimeScore >= 0.75) regime = REGIME_TRENDING_STRONG;\n      else if(result.regimeScore >= 0.5) regime = REGIME_RANGING_SIDEWAYS;\n      else regime = REGIME_CHOPPY_HIGH_VOL;\n      \n      // MTF alignment from score\n      if(result.mtfScore >= 0.75) mtfAlign = 2;\n      else if(result.mtfScore >= 0.5) mtfAlign = 0;\n      else mtfAlign = -1;\n      \n      result.reasoning = BuildReasoning(result, patternType, regime, mtfAlign);\n      \n      // Store last valid signal\n      if(result.type != SIGNAL_NONE && result.isStable)\n         m_lastValidSignal = result;\n      \n      if(m_debugMode)\n      {\n         PrintFormat(\"[SignalManager] Evaluate: Type=%s Score=%.2f Threshold=%.2f Confidence=%s Stable=%s\",\n                     result.type == SIGNAL_BUY ? \"BUY\" : (result.type == SIGNAL_SELL ? \"SELL\" : "NONE"),\n                     result.score, result.dynamicThreshold, \n                     result.ConfidenceToString(), result.isStable ? "YES" : "NO");\n         PrintFormat(\"[SignalManager] Components: Pattern=%.2f Regime=%.2f Vol=%.2f News=%.2f MTF=%.2f\",\n                     result.patternScore, result.regimeScore, result.volatilityScore,\n                     result.newsScore, result.mtfScore);\n      }\n      \n      return result;\n   }\n\n   // Backward compatibility wrapper - returns simple boolean\n   // Use this if old code calls the original signal method\n   bool HasValidSignal()\n   {\n      SignalResult result = Evaluate();\n      return result.IsActionable();\n   }\n\n   // Get last evaluated signal result\n   const SignalResult& GetLastSignalResult() const\n   {\n      return m_lastValidSignal;\n   }\n\n   //+------------------------------------------------------------------+\n   //| PRIVATE: Core Processing Logic                                  |\n   //+------------------------------------------------------------------+\nprivate:\n   // Main processing method called on NewBar event\n   void ProcessSignalOnNewBar(NewBarEvent *e)\n   {\n      // Use cached data from ZoneUpdateEvent\n      double atrPoints = m_marketData.atrPoints;\n      double support = m_marketData.support;\n      double resistance = m_marketData.resistance;\n      double htfSupport = m_marketData.htfSupport;\n      double htfResistance = m_marketData.htfResistance;\n      bool isSupBroken = m_marketData.isSupBroken;\n      bool isResBroken = m_marketData.isResBroken;\n      double supBufferMult = m_marketData.supBufferMult;\n      double resBufferMult = m_marketData.resBufferMult;\n      int supHtfAlign = m_marketData.supHtfAlign;\n      int resHtfAlign = m_marketData.resHtfAlign;\n\n      if (atrPoints <= 0 || support <= 0 || resistance <= 0)\n      {\n         if (m_debugMode)\n            Print("[SignalManager] Missing data for signal detection");\n         return;\n      }\n\n      // NEW: Use advanced scoring system\n      SignalResult result = Evaluate();\n      \n      // Only dispatch if signal is actionable (above threshold AND stable)\n      if(result.IsActionable())\n      {\n         // Convert SignalResult back to SignalDecision for backward compatibility\n         SignalDecision decision;\n         ZeroMemory(decision);\n         decision.valid = true;\n         decision.orderType = (result.type == SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;\n         decision.signalPrice = support;  // Will be refined by execution manager\n         decision.zonePrice = (result.type == SIGNAL_BUY) ? support : resistance;\n         decision.patternType = PATTERN_ENGULFING;  // Default\n         decision.reason = result.reasoning;\n         decision.bias = (result.type == SIGNAL_BUY) ? 1 : -1;\n         \n         // Dispatch event\n         SignalGeneratedEvent *sigEvent = new SignalGeneratedEvent(\n             decision, atrPoints, support, resistance);\n         DispatchEvent(sigEvent);\n         \n         RegisterSignalCooldown(decision.signalPrice);\n         \n         if(m_debugMode)\n            PrintFormat(\"[SignalManager] Actionable signal dispatched: %s | Reason: %s\",\n                        result.type == SIGNAL_BUY ? \"BUY\" : "SELL", result.reasoning);\n      }\n      else if(m_debugMode && result.type != SIGNAL_NONE)\n      {\n         PrintFormat(\"[SignalManager] Signal filtered out: %s | Score=%.2f | Stable=%s | Reason: %s\",\n                     result.type == SIGNAL_BUY ? "BUY" : "SELL",\n                     result.score, result.isStable ? "YES" : "NO", result.reasoning);\n      }\n   }\n};

#endif
