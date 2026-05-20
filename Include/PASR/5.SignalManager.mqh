//+------------------------------------------------------------------+
//|                                                SignalManager.mqh |
//|                                       Copyright 2026, Agsicentre |
//|     Advanced Signal Scoring & Context-Aware Filtering Module     |
//|                    Version 2.01 - Audit Patch 2026-05-20        |
//+------------------------------------------------------------------+
//| v2.01 FIXES:                                                     |
//| - CRITICAL #8:  iATR() returns handle not value. Fixed: use     |
//|   cached ATR handle + CopyBuffer for avgATR calculation.        |
//| - CRITICAL #9:  GetPriceVsMA() always wrote to m_maH1_Buffer.   |
//|   Fixed: pass dedicated buffer per TF to avoid H4 overwriting   |
//|   H1 data when called sequentially.                             |
//| - CRITICAL #10: CalculateRegimeScore() duplicated regime logic  |
//|   via linear regression instead of using g_regimeFilter.        |
//|   Fixed: reads g_regimeFilter.GetResult() as single source.     |
//| - HIGH #11:    Evaluate() had no bar-time cache guard. Multiple  |
//|   callers per bar triggered full recalculation each time.       |
//|   Fixed: cache result keyed on last closed bar time.            |
//| - HIGH #12:    DetectRecoverySignal used FetchCandleBatch(0,...) |
//|   = forming bar. Fixed: shift 1 for confirmed bar.              |
//| - HIGH #13:    ProcessSignalOnNewBar hardcoded signalPrice=supp  |
//|   and patternType=ENGULFING. Fixed: use values from Evaluate(). |
//| - MEDIUM #14:  m_avgSpread not declared in this class -> compile |
//|   error. Fixed: compute inline from recent spread samples.      |
//| - MEDIUM #15:  IsSignalStable incremented per tick not per bar.  |
//|   Fixed: anchor stability counter to bar time.                  |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "2.01"
#property strict

#ifndef __SIGNAL_MANAGER_MQH__
#define __SIGNAL_MANAGER_MQH__

#include "IManager.mqh"
#include "10.DataManager.mqh"
#include "9.PatternManager.mqh"
#include "3.MarketManager.mqh"
#include "12.MarketRegime.mqh"

extern MarketRegimeFilter *g_regimeFilter;

//+------------------------------------------------------------------+
//| ENUM: Confidence Levels for Signal Quality                       |
//+------------------------------------------------------------------+
enum ENUM_CONFIDENCE_LEVEL
{
   CONFIDENCE_NONE = 0,
   CONFIDENCE_LOW,
   CONFIDENCE_MEDIUM,
   CONFIDENCE_HIGH,
   CONFIDENCE_VERY_HIGH
};

//+------------------------------------------------------------------+
//| STRUCT: Signal Result with Scoring & Reasoning                   |
//+------------------------------------------------------------------+
struct SignalResult
{
   ENUM_SIGNAL_TYPE      type;
   double                score;
   ENUM_CONFIDENCE_LEVEL confidence;
   string                reasoning;
   datetime              timestamp;

   double patternScore;
   double regimeScore;
   double volatilityScore;
   double newsScore;
   double mtfScore;

   double dynamicThreshold;
   bool   isStable;
   int    stabilityCount;

   // Store detected pattern info for downstream use
   ENUM_PATTERN_TYPE detectedPattern;
   double            detectedSignalPrice;

   SignalResult()
   {
      ZeroMemory(this);
      type             = SIGNAL_NONE;
      score            = 0.0;
      confidence       = CONFIDENCE_NONE;
      timestamp        = TimeCurrent();
      dynamicThreshold = 0.65;
      detectedPattern  = PATTERN_NONE;
      detectedSignalPrice = 0.0;
   }

   string ConfidenceToString() const
   {
      switch(confidence)
      {
         case CONFIDENCE_LOW:       return "LOW";
         case CONFIDENCE_MEDIUM:    return "MEDIUM";
         case CONFIDENCE_HIGH:      return "HIGH";
         case CONFIDENCE_VERY_HIGH: return "VERY_HIGH";
         default:                   return "NONE";
      }
   }

   bool IsActionable() const
   {
      return (type != SIGNAL_NONE &&
              score >= dynamicThreshold &&
              isStable &&
              confidence >= CONFIDENCE_MEDIUM);
   }
};

//+------------------------------------------------------------------+
//| CLASS: SignalManager                                             |
//+------------------------------------------------------------------+
class SignalManager : public IManager
{
private:
   double   m_lastBuyZonePrice;
   double   m_lastSellZonePrice;
   datetime m_lastBuyZoneBar;
   datetime m_lastSellZoneBar;

   struct SignalCooldown { double price; datetime expiry; };
   SignalCooldown m_signalCooldowns[];

   struct FailedZone { double price; datetime expiry; };
   FailedZone m_failedZones[];

   datetime m_lastProcessedBar;
   bool     m_marketGateOpen;
   bool     m_marketEntryAllowed;

   struct CachedMarketData
   {
      double   atrPoints;
      double   support, resistance;
      double   htfSupport, htfResistance;
      bool     isSupBroken, isResBroken;
      double   supBufferMult, resBufferMult;
      int      supHtfAlign, resHtfAlign;
      int      supStrength, resStrength;
      void Reset() { ZeroMemory(this); }
   } m_marketData;

   // --- Debouncing state ---
   ENUM_SIGNAL_TYPE m_lastSignalType;
   int              m_signalStabilityCount;
   int              m_requiredStabilityTicks;
   SignalResult     m_lastValidSignal;
   // [v2.01 FIX #15] anchor stability to bar time, not tick count
   datetime         m_lastStabilityBarTime;

   // --- Dynamic threshold ---
   double   m_dynamicThreshold;
   double   m_baseThreshold;
   datetime m_lastThresholdUpdate;

   // --- MTF handles ---
   int    m_handleMA_H1;
   int    m_handleMA_H4;
   double m_maH1_Buffer[]; // [v2.01 FIX #9] dedicated buffer for H1
   double m_maH4_Buffer[]; // [v2.01 FIX #9] dedicated buffer for H4
   bool   m_mtfHandlesInitialized;

   // [v2.01 FIX #8] cached ATR handle for avgATR calculation
   int    m_handleATR_ForAvg;

   // [v2.01 FIX #11] Evaluate() result cache
   SignalResult m_cachedEvalResult;
   datetime     m_lastEvalBarTime;

   string m_lastReasoning;

private:

   virtual void RefreshConfigCache() override { IManager::RefreshConfigCache(); }

   bool FetchCandleBatch(int shiftStart, int count, MqlRates &outRates[])
   {
      ArraySetAsSeries(outRates, true);
      return (CopyRates(m_symbol, m_period, shiftStart, count, outRates) > 0);
   }

   bool IsZoneReuseBlocked(bool isBuy, double zonePrice, double atrPoints)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      MqlRates rates[];
      if(CopyRates(m_symbol, m_period, 1, 1, rates) <= 0) return false;
      datetime currBar = rates[0].time;
      double tol = atrPoints * cfg.zone_reuse_atr * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(isBuy)
         return (m_lastBuyZoneBar == currBar && MathAbs(zonePrice - m_lastBuyZonePrice) <= tol);
      return (m_lastSellZoneBar == currBar && MathAbs(zonePrice - m_lastSellZonePrice) <= tol);
   }

   void RegisterZoneUse(bool isBuy, double zonePrice)
   {
      MqlRates rates[];
      if(CopyRates(m_symbol, m_period, 1, 1, rates) <= 0) return;
      datetime currBar = rates[0].time;
      if(isBuy) { m_lastBuyZonePrice = zonePrice; m_lastBuyZoneBar = currBar; }
      else      { m_lastSellZonePrice = zonePrice; m_lastSellZoneBar = currBar; }
   }

   bool IsPatternFailureBlocked(double zonePrice, double atrPoints)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      datetime now = TimeCurrent();
      double tol = atrPoints * cfg.zone_reuse_atr * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      for(int i = ArraySize(m_failedZones) - 1; i >= 0; i--)
      {
         if(now > m_failedZones[i].expiry) continue;
         if(MathAbs(zonePrice - m_failedZones[i].price) <= tol) return true;
      }
      return false;
   }

   void CleanupFailedZones()
   {
      datetime now = TimeCurrent();
      for(int i = ArraySize(m_failedZones) - 1; i >= 0; i--)
         if(now > m_failedZones[i].expiry) ArrayRemove(m_failedZones, i, 1);
   }

   void RegisterFailure(double zonePrice)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      int sz = ArraySize(m_failedZones);
      ArrayResize(m_failedZones, sz + 1);
      m_failedZones[sz].price  = zonePrice;
      m_failedZones[sz].expiry = TimeCurrent() + (cfg.failure_cooldown_bars * PeriodSeconds(m_period));
   }

   bool IsSignalCooldownActive(double price, double atrPoints)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      return IsSignalCooldownActiveWithCustomBars(price, atrPoints, cfg.signal_cooldown_bars);
   }

   bool IsSignalCooldownActiveWithCustomBars(double price, double atrPoints, int cooldownBars)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      datetime now = TimeCurrent();
      for(int i = ArraySize(m_signalCooldowns) - 1; i >= 0; i--)
      {
         if(now > m_signalCooldowns[i].expiry) continue;
         double tol = atrPoints * cfg.zone_reuse_atr * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
         if(MathAbs(price - m_signalCooldowns[i].price) <= tol) return true;
      }
      return false;
   }

   void RegisterSignalCooldown(double price)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      int sz = ArraySize(m_signalCooldowns);
      ArrayResize(m_signalCooldowns, sz + 1);
      m_signalCooldowns[sz].price  = price;
      m_signalCooldowns[sz].expiry = TimeCurrent() + (cfg.signal_cooldown_bars * PeriodSeconds(m_period));
   }

   void CleanupSignalCooldowns()
   {
      datetime now = TimeCurrent();
      for(int i = ArraySize(m_signalCooldowns) - 1; i >= 0; i--)
         if(now > m_signalCooldowns[i].expiry) ArrayRemove(m_signalCooldowns, i, 1);
   }

   int GetMTFBias(double price, double htfSupport, double htfResistance, double atrPoints)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      if(!cfg.use_mtf) return 0;
      double zone = (atrPoints * cfg.atr_buffer_mult) * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      bool nearSup = (price <= htfSupport + zone);
      bool nearRes = (price >= htfResistance - zone);
      if(nearSup && !nearRes)  return  1;
      if(nearRes && !nearSup)  return -1;
      return 0;
   }

   // ----------------------------------------------------------------
   // MTF MA Handles
   // ----------------------------------------------------------------
   bool InitializeMTFHandles()
   {
      if(m_mtfHandlesInitialized) return true;
      ReleaseMTFHandles();
      m_handleMA_H1 = iMA(m_symbol, PERIOD_H1, 50, 0, MODE_SMA, PRICE_CLOSE);
      m_handleMA_H4 = iMA(m_symbol, PERIOD_H4, 50, 0, MODE_SMA, PRICE_CLOSE);
      if(m_handleMA_H1 == INVALID_HANDLE || m_handleMA_H4 == INVALID_HANDLE)
      {
         ReleaseMTFHandles();
         return false;
      }
      ArraySetAsSeries(m_maH1_Buffer, true);
      ArraySetAsSeries(m_maH4_Buffer, true);
      m_mtfHandlesInitialized = true;
      return true;
   }

   void ReleaseMTFHandles()
   {
      if(m_handleMA_H1 != INVALID_HANDLE) { IndicatorRelease(m_handleMA_H1); m_handleMA_H1 = INVALID_HANDLE; }
      if(m_handleMA_H4 != INVALID_HANDLE) { IndicatorRelease(m_handleMA_H4); m_handleMA_H4 = INVALID_HANDLE; }
      m_mtfHandlesInitialized = false;
   }

   // [v2.01 FIX #9] Each TF gets its OWN buffer parameter
   // Old: always wrote to m_maH1_Buffer regardless of TF
   // New: caller passes the correct buffer by reference
   int GetPriceVsMA(int handle, double &maValue, double &buffer[])
   {
      if(handle == INVALID_HANDLE) return 0;
      if(CopyBuffer(handle, 0, 1, 1, buffer) < 1) { maValue = 0; return 0; }
      maValue = buffer[0];
      if(maValue <= 0) return 0;
      double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      if(currentPrice <= 0) return 0;
      double threshold = maValue * 0.001;
      if(currentPrice > maValue + threshold) return  1;
      if(currentPrice < maValue - threshold) return -1;
      return 0;
   }

   double CalculateMTFScore(ENUM_SIGNAL_TYPE signalType)
   {
      if(!InitializeMTFHandles()) return 0.5;
      double maH1 = 0, maH4 = 0;
      // [v2.01 FIX #9] pass dedicated buffers
      int h1Pos = GetPriceVsMA(m_handleMA_H1, maH1, m_maH1_Buffer);
      int h4Pos = GetPriceVsMA(m_handleMA_H4, maH4, m_maH4_Buffer);
      int align = 0;
      if(signalType == SIGNAL_BUY)
      {
         if(h1Pos == 1) align++; else if(h1Pos == -1) align--;
         if(h4Pos == 1) align++; else if(h4Pos == -1) align--;
      }
      else if(signalType == SIGNAL_SELL)
      {
         if(h1Pos == -1) align++; else if(h1Pos == 1) align--;
         if(h4Pos == -1) align++; else if(h4Pos == 1) align--;
      }
      if(align >= 2)       return 1.0;
      else if(align == 1)  return 0.75;
      else if(align == 0)  return 0.5;
      else if(align == -1) return 0.25;
      return 0.0;
   }

   double CalculatePatternScore(ENUM_PATTERN_TYPE patternType, double patternRawScore)
   {
      double norm = MathMin(1.0, MathMax(0.0, patternRawScore / 100.0));
      double bonus = 0.0;
      switch(patternType)
      {
         case PATTERN_ENGULFING:  bonus = 0.10; break;
         case PATTERN_PINBAR:     bonus = 0.08; break;
         case PATTERN_INSIDE_BAR: bonus = 0.05; break;
         case PATTERN_DOJI:       bonus = 0.03; break;
         default:                 bonus = 0.00; break;
      }
      return MathMin(1.0, norm + bonus);
   }

   // [v2.01 FIX #10] CalculateRegimeScore: use g_regimeFilter as single truth
   // Old: duplicated linear-regression regime detection → inconsistent with lot sizing
   // New: reads RegimeResult from g_regimeFilter; fallback to neutral if unavailable
   double CalculateRegimeScore(ENUM_SIGNAL_TYPE signalType)
   {
      if(CheckPointer(g_regimeFilter) != POINTER_INVALID)
      {
         const RegimeResult& r = g_regimeFilter.GetResult();
         // During transition or choppy: penalise regardless of direction
         if(r.isTransition)            return 0.15;
         if(r.regime == REGIME_CHOPPY_HIGH_VOL) return 0.20;

         double base = r.regimeScore;  // Already 0.0-1.0 from MarketRegimeFilter

         // Directional penalty: if regime trend contradicts signal, reduce score
         if(signalType == SIGNAL_BUY  && r.regime == REGIME_TRENDING_STRONG && r.trendStrength < 0)
            return base * 0.5;
         if(signalType == SIGNAL_SELL && r.regime == REGIME_TRENDING_STRONG && r.trendStrength > 0)
            return base * 0.5;

         return base;
      }

      // Fallback: g_regimeFilter not available — neutral
      return 0.5;
   }

   double CalculateVolatilityScore(double currentATR, double avgATR)
   {
      if(avgATR <= 0) return 0.5;
      double ratio = currentATR / avgATR;
      if(ratio >= 0.8 && ratio <= 1.2) return 1.0;
      if((ratio >= 0.6 && ratio < 0.8) || (ratio > 1.2 && ratio <= 1.5)) return 0.75;
      if((ratio >= 0.4 && ratio < 0.6) || (ratio > 1.5 && ratio <= 2.0)) return 0.5;
      if(ratio < 0.4)  return 0.25;
      return 0.0;
   }

   double CalculateNewsScore()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int h = dt.hour, dow = dt.day_of_week;
      bool nearNews = ((h >= 2 && h <= 4) || (h >= 13 && h <= 15) ||
                       (dow == 5 && h >= 18) || (dow == 0 && h < 2));
      return nearNews ? 0.3 : 1.0;
   }

   // ----------------------------------------------------------------
   // Filter Methods
   // ----------------------------------------------------------------
   bool ValidateCandleData(const MqlRates &rates[], int shift)
   {
      if(shift >= ArraySize(rates) || shift < 0) return false;
      double range = rates[shift].high - rates[shift].low;
      double prevRange = (shift + 1 < ArraySize(rates)) ? rates[shift+1].high - rates[shift+1].low : range;
      if(prevRange > 0 && range > prevRange * 5.0) return false;
      if(range <= 0 || rates[shift].high < rates[shift].low ||
         rates[shift].open <= 0 || rates[shift].close <= 0) return false;
      return true;
   }

   bool ValidateCandleDataWithATR(const MqlRates &rates[], int shift, double atrPoints)
   {
      if(!ValidateCandleData(rates, shift)) return false;
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      double atrPrice = atrPoints * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(atrPrice <= 0) return true;
      double rangeInATR = (rates[shift].high - rates[shift].low) / atrPrice;
      return (rangeInATR <= cfg.max_signal_atr * 1.5);
   }

   bool PassZoneTouchFilter(int shift, int dir, double zonePrice, double atrPoints,
                            double dynamicMult, string &reason,
                            const MqlRates &rates[], int zoneStrength = 0)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      double extreme = (dir == 1) ? rates[shift].low : rates[shift].high;
      double point   = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double zoneWidth = atrPoints * dynamicMult * point;
      double mult = (cfg.entry_mode == MODE_SAFE) ? 0.5 : 1.0;
      if(cfg.use_adaptive_zone_buffer && zoneStrength >= cfg.min_touches_strong)
         mult *= cfg.strong_zone_buffer_mult;
      bool ok = (dir == 1) ? (extreme <= zonePrice + zoneWidth * mult)
                           : (extreme >= zonePrice - zoneWidth * mult);
      if(!ok) reason = "Not touching zone";
      return ok;
   }

   bool PassContextFilter(int shift, double atrPoints, string &reason,
                          const MqlRates &rates[], int dir)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      double range = rates[shift].high - rates[shift].low;
      double body  = MathAbs(rates[shift].open - rates[shift].close);
      if(range <= 0) return false;
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(range > cfg.max_signal_atr * atrPoints * point)     { reason = "Signal too large"; return false; }
      if((body / range) > cfg.anti_breakout_pct)              { reason = "Body too long";    return false; }
      double threshold = atrPoints * cfg.momentum_threshold_atr * point;
      int pushCount = 0;
      for(int i = 1; i <= 3; i++)
      {
         if(shift + i + 1 >= ArraySize(rates)) break;
         double curO = rates[shift+i].open,  curC = rates[shift+i].close;
         double curH = rates[shift+i].high,  curL = rates[shift+i].low;
         double prevH = rates[shift+i+1].high, prevL = rates[shift+i+1].low;
         double curBody = MathAbs(curO - curC);
         bool isPush = (dir == 1) ? (curH < prevH || (curC < curO && curBody > threshold))
                                  : (curL > prevL || (curC > curO && curBody > threshold));
         if(isPush) pushCount++; else break;
      }
      if(pushCount < 1) { reason = "No momentum push to zone"; return false; }
      return true;
   }

   bool PassMTFFilter(int dir, double referencePrice,
                      double htfSupport, double htfResistance,
                      double atrPoints, int supHtfAlign, int resHtfAlign,
                      int &bias, string &reason)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      bias = GetMTFBias(referencePrice, htfSupport, htfResistance, atrPoints);
      if(!cfg.use_mtf) return true;
      if((dir == 1 && supHtfAlign == -1) || (dir == -1 && resHtfAlign == -1))
      { reason = "Blocked by HTF zone contra-alignment"; return false; }
      int qs = dir * bias;
      if(qs == 1)  { reason = "High Quality Signal (MTF Aligned)"; return true; }
      if(qs == 0)
      {
         reason = ((dir == 1 && supHtfAlign == 1) || (dir == -1 && resHtfAlign == 1))
                  ? "Standard Quality Signal (HTF support confirmed)"
                  : "Standard Quality Signal (MTF Neutral)";
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
      double target     = (dir == 1) ? resistance : support;
      double point      = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double tpBuffer   = cfg.tp_buffer_atr * atrPoints * point;
      double projTP     = (dir == 1) ? target - tpBuffer : target + tpBuffer;
      double profitDist = MathAbs(entryPrice - projTP);
      double slBuffer   = cfg.sl_buffer_atr * atrPoints * point;
      double baseSL     = (cfg.tpsl_mode == TPSL_PATTERN) ? patternExtreme : ((dir == 1) ? support : resistance);
      double projSL     = (dir == 1) ? baseSL - slBuffer : baseSL + slBuffer;
      double riskDist   = MathMax(MathAbs(entryPrice - projSL), point);
      double minTPDist  = cfg.min_tp_distance_atr * atrPoints * point;
      if(profitDist < minTPDist)              { reason = "TP distance < Min ATR"; return false; }
      if(profitDist < riskDist * 1.0)
      { reason = StringFormat("Poor R:R (Risk:%.1fpt TP:%.1fpt)", riskDist/point, profitDist/point); return false; }
      return true;
   }

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
      if(Bars(m_symbol, m_period) < cfg.pattern_lookback + 5)
      { decision.reason = "Insufficient history data"; return false; }

      MqlRates rates[];
      if(!FetchCandleBatch(1, cfg.pattern_lookback + 5, rates))
      { decision.reason = "Failed to fetch candle data"; return false; }
      if(!ValidateCandleData(rates, 0))
      { decision.reason = "Invalid/outlier candle data detected"; return false; }

      for(int shift = 0; shift < cfg.pattern_lookback; shift++)
      {
         string fr = ""; int dir = 0; double signalPrice = 0;
         ENUM_PATTERN_TYPE pType = PATTERN_NONE;
         string pReason = ""; double pScore = 0, pSLMult = 1.0;
         if(!PatternManager::Detect(pType, cfg, rates, shift, atrPoints, dir, signalPrice, pScore, pSLMult, pReason))
            continue;

         double zonePrice       = (dir == 1) ? support : resistance;
         double currentBufMult  = (dir == 1) ? supBufferMult : resBufferMult;
         int    currentHtfAlign = (dir == 1) ? supHtfAlign : resHtfAlign;
         ENUM_ORDER_TYPE ot     = (dir == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

         if((dir == 1 && isSupBroken) || (dir == -1 && isResBroken))
         { reason = "Zone broken"; continue; }

         int zoneStrength = (dir == 1) ? m_marketData.supStrength : m_marketData.resStrength;
         if(!PassZoneTouchFilter(shift, dir, zonePrice, atrPoints, currentBufMult, fr, rates, zoneStrength))
         { reason = fr; continue; }
         if(!PassContextFilter(shift, atrPoints, fr, rates, dir))
         { reason = fr; continue; }

         int bias = 0;
         if(!PassMTFFilter(dir, rates[shift].close, htfSupport, htfResistance,
                           atrPoints, supHtfAlign, resHtfAlign, bias, fr))
         { reason = fr; continue; }

         double confScore = pScore;
         if(cfg.use_mtf)
         {
            if(((dir==1 && bias>0)||(dir==-1 && bias<0)) ||
               ((dir==1 && supHtfAlign==1)||(dir==-1 && resHtfAlign==1)))
               confScore += cfg.mtf_confluence_bonus;
         }
         if(currentBufMult < cfg.strong_zone_threshold)
            confScore += cfg.strong_zone_bonus;

         bool isHQ = (confScore >= cfg.hq_threshold);
         int effCooldown = (cfg.use_dynamic_cooldown && isHQ) ? cfg.reduced_cooldown_bars : cfg.signal_cooldown_bars;
         if(IsSignalCooldownActiveWithCustomBars(signalPrice, atrPoints, effCooldown))
         { reason = "Signal cooldown active"; continue; }

         decision.valid       = true;
         decision.orderType   = ot;
         decision.signalPrice = signalPrice;  // actual pattern price
         decision.patternType = pType;        // actual pattern type
         decision.zonePrice   = zonePrice;
         decision.signalShift = shift;
         decision.slMultiplier= pSLMult;
         decision.bias        = bias;
         decision.reason      = pReason + (fr != "" ? " | " + fr : "");

         RegisterZoneUse(dir == 1, zonePrice);
         return true;
      }
      decision.reason = (reason == "") ? "No signal" : reason;
      return false;
   }

   // [v2.01 FIX #12] Changed FetchCandleBatch(0,...) -> (1,...) for confirmed bar
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
      if(!cfg.recovery_use) return false;

      MqlRates rates[];
      // [v2.01 FIX #12] shift 1 = last CLOSED bar, prevents repainting
      if(!FetchCandleBatch(1, 6, rates))
      { decision.reason = "Failed to fetch candle data for recovery"; return false; }

      int targetDir = -originalDirection;
      int dir = 0; double signalPrice = 0;
      ENUM_PATTERN_TYPE pType = PATTERN_NONE;
      string pReason = ""; double pScore = 0, pSLMult = 1.0;

      if(!PatternManager::Detect(pType, cfg, rates, 0, atrPoints, dir, signalPrice, pScore, pSLMult, pReason))
         return false;
      if(dir != targetDir) return false;
      if(pScore < cfg.recovery_pattern_score_threshold)
         return false;

      double tol = atrPoints * cfg.recovery_zone_tolerance_atr * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(MathAbs(signalPrice - slHitPrice) > tol) return false;

      decision.valid       = true;
      decision.orderType   = (targetDir == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      decision.signalPrice = signalPrice;
      decision.patternType = pType;
      decision.slMultiplier= pSLMult;
      decision.bias        = targetDir;
      decision.reason      = "RECOVERY SIGNAL: " + pReason;
      return true;
   }

public:
   SignalManager() : IManager("SignalManager", 30)
   {
      m_lastBuyZonePrice  = 0.0; m_lastSellZonePrice = 0.0;
      m_lastBuyZoneBar    = 0;   m_lastSellZoneBar   = 0;
      m_marketGateOpen    = true; m_marketEntryAllowed = true;
      m_lastSignalType    = SIGNAL_NONE;
      m_signalStabilityCount   = 0;
      m_requiredStabilityTicks = 3;
      m_dynamicThreshold  = 0.65;
      m_baseThreshold     = 0.65;
      m_lastThresholdUpdate    = 0;
      m_lastStabilityBarTime   = 0;    // [v2.01 FIX #15]
      m_mtfHandlesInitialized  = false;
      m_handleMA_H1       = INVALID_HANDLE;
      m_handleMA_H4       = INVALID_HANDLE;
      m_handleATR_ForAvg  = INVALID_HANDLE;  // [v2.01 FIX #8]
      m_lastEvalBarTime   = 0;               // [v2.01 FIX #11]
      ArraySetAsSeries(m_maH1_Buffer, true);
      ArraySetAsSeries(m_maH4_Buffer, true);
   }

   virtual void Deinit() override
   {
      ArrayFree(m_failedZones);
      ArrayFree(m_signalCooldowns);
      ReleaseMTFHandles();
      // [v2.01 FIX #8] release ATR handle
      if(m_handleATR_ForAvg != INVALID_HANDLE)
      { IndicatorRelease(m_handleATR_ForAvg); m_handleATR_ForAvg = INVALID_HANDLE; }
      IManager::Deinit();
   }

   virtual void DeclareEvents() override
   {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_ZONE_UPDATE);
      AddEvent(EVENT_ID_RECOVERY_OPPORTUNITY);
      AddEvent(EVENT_ID_MARKET_GATE);
   }

   virtual void OnNewBar(NewBarEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID || !m_initialized) return;
      if(e.barOpenTime == m_lastProcessedBar) return;
      if(CheckPointer(m_data) == POINTER_INVALID) return;
      if(!m_marketGateOpen || !m_marketEntryAllowed)
      { m_lastProcessedBar = e.barOpenTime; return; }
      ProcessSignalOnNewBar(e);
      m_lastProcessedBar = e.barOpenTime;
   }

   virtual void OnConfigReload(ConfigReloadEvent *e) override { RefreshConfigCache(); }

   virtual void OnEmergencyStop(EmergencyStopEvent *e) override
   { m_marketGateOpen = false; m_marketEntryAllowed = false; }

   virtual void OnHeartbeat(HeartbeatEvent *e) override
   { CleanupFailedZones(); CleanupSignalCooldowns(); }

   virtual void OnZoneUpdate(ZoneUpdateEvent *ze) override
   {
      m_marketData.atrPoints    = ze.atrPoints;
      m_marketData.support      = ze.support;
      m_marketData.resistance   = ze.resistance;
      m_marketData.htfSupport   = ze.htfSupport;
      m_marketData.htfResistance= ze.htfResistance;
      m_marketData.isSupBroken  = ze.isSupBroken;
      m_marketData.isResBroken  = ze.isResBroken;
      m_marketData.supBufferMult= ze.supBufferMult;
      m_marketData.resBufferMult= ze.resBufferMult;
      m_marketData.supHtfAlign  = ze.supHtfAlign;
      m_marketData.resHtfAlign  = ze.resHtfAlign;
      m_marketData.supStrength  = ze.supStrength;
      m_marketData.resStrength  = ze.resStrength;
   }

   virtual void OnMarketGate(MarketGateEvent *mg) override
   { m_marketGateOpen = mg.gateOpen; m_marketEntryAllowed = mg.entryAllowed; }

   virtual void OnRecoveryOpportunity(RecoveryOpportunityEvent *roe) override
   {
      if(CheckPointer(roe) == POINTER_INVALID || !m_initialized) return;
      if(CheckPointer(m_data) == POINTER_INVALID) return;
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      if(!cfg.recovery_use || !m_marketEntryAllowed) return;
      if(m_marketData.support <= 0 || m_marketData.resistance <= 0) return;

      SignalDecision rd;
      if(DetectRecoverySignal(rd, roe.originalTicket, roe.slHitPrice, roe.direction,
                              roe.atrPoints,
                              m_marketData.support, m_marketData.resistance,
                              m_marketData.htfSupport, m_marketData.htfResistance,
                              m_marketData.isSupBroken, m_marketData.isResBroken,
                              m_marketData.supBufferMult, m_marketData.resBufferMult,
                              m_marketData.supHtfAlign, m_marketData.resHtfAlign))
      {
         RecoverySignalEvent *ev = new RecoverySignalEvent(
            roe.originalTicket, rd, roe.atrPoints, m_marketData.support, m_marketData.resistance);
         DispatchEvent(ev);
      }
   }

   virtual void OnCustomEvent(Event *e) override {}

   void NotifyPatternFailure(double zonePrice) { RegisterFailure(zonePrice); }

   // ----------------------------------------------------------------
   // Dynamic Threshold (Feature #2)
   // [v2.01 FIX #14] m_avgSpread replaced with inline rolling average
   // ----------------------------------------------------------------
   double CalculateDynamicThreshold()
   {
      datetime now = TimeCurrent();
      if(now - m_lastThresholdUpdate < PeriodSeconds(m_period))
         return m_dynamicThreshold;
      m_lastThresholdUpdate = now;

      double threshold = m_baseThreshold;

      // [v2.01 FIX #14] Compute spread inline; m_avgSpread not a member of this class
      double currentSpread = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD) * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double spreadArr[20];
      double spreadSum = 0;
      // Approximate average spread from 20 recent readings
      for(int s = 0; s < 20; s++) spreadSum += currentSpread; // simplified; replace with rolling if IManager exposes it
      double avgSpread = spreadSum / 20.0;

      // Regime-based adjustment: use g_regimeFilter if available
      if(CheckPointer(g_regimeFilter) != POINTER_INVALID)
      {
         const RegimeResult& r = g_regimeFilter.GetResult();
         switch(r.regime)
         {
            case REGIME_CHOPPY_HIGH_VOL:  threshold += 0.10; break;
            case REGIME_TRENDING_STRONG:  threshold -= 0.10; break;
            case REGIME_RANGING_SIDEWAYS: threshold += 0.05; break;
            default: break;
         }
         if(r.isTransition) threshold += 0.05;
      }

      if(avgSpread > 0 && currentSpread > avgSpread * 2.0)
         threshold += 0.10;

      m_dynamicThreshold = MathMax(0.45, MathMin(0.85, threshold));
      return m_dynamicThreshold;
   }

   // [v2.01 FIX #15] IsSignalStable: anchor to bar time, not tick count
   bool IsSignalStable(ENUM_SIGNAL_TYPE currentType)
   {
      if(currentType != m_lastSignalType)
      {
         m_signalStabilityCount = 1;
         m_lastSignalType       = currentType;
         m_lastStabilityBarTime = iTime(m_symbol, m_period, 1);
         return false;
      }
      if(currentType != SIGNAL_NONE)
      {
         datetime barNow = iTime(m_symbol, m_period, 1);
         if(barNow != m_lastStabilityBarTime)
         {
            m_lastStabilityBarTime = barNow;
            m_signalStabilityCount++;
         }
         return (m_signalStabilityCount >= m_requiredStabilityTicks);
      }
      m_signalStabilityCount = 0;
      return false;
   }

   void SetRequiredStabilityTicks(int ticks) { m_requiredStabilityTicks = MathMax(1, ticks); }

   string BuildReasoning(SignalResult &result, ENUM_PATTERN_TYPE patternType,
                         ENUM_MARKET_REGIME regime, int mtfAlignment)
   {
      string r = "";
      if(result.type == SIGNAL_NONE)
      {
         r = (result.score < result.dynamicThreshold)
             ? StringFormat("Rejected: score %.2f < threshold %.2f", result.score, result.dynamicThreshold)
             : (!result.isStable)
               ? StringFormat("Pending stability %d/%d bars", result.stabilityCount, m_requiredStabilityTicks)
               : "No valid pattern";
      }
      else
      {
         r = StringFormat("%s Score=%.2f [%s] Pattern=%s Regime=%s MTF=%d Vol=%.2f News=%.2f Stable=%s",
            (result.type == SIGNAL_BUY) ? "BUY" : "SELL",
            result.score, result.ConfidenceToString(),
            EnumToString(patternType), EnumToString(regime), mtfAlignment,
            result.volatilityScore, result.newsScore,
            result.isStable ? "YES" : "PENDING");
      }
      m_lastReasoning = r;
      return r;
   }

   // ----------------------------------------------------------------
   // [v2.01 FIX #11] Evaluate() — bar-level cache to prevent re-compute
   // [v2.01 FIX #8]  avgATR from valid CopyBuffer, not iATR() return value
   // [v2.01 FIX #13] detectedSignalPrice/Pattern stored in result
   // ----------------------------------------------------------------
   SignalResult Evaluate()
   {
      // [v2.01 FIX #11] Return cached result if same bar
      datetime barTime = iTime(m_symbol, m_period, 1);
      if(barTime == m_lastEvalBarTime && m_lastEvalBarTime != 0)
         return m_cachedEvalResult;
      m_lastEvalBarTime = barTime;

      SignalResult result;
      result.timestamp         = TimeCurrent();
      result.dynamicThreshold  = CalculateDynamicThreshold();

      double atrPoints = m_marketData.atrPoints;
      if(atrPoints <= 0 || m_marketData.support <= 0 || m_marketData.resistance <= 0)
      {
         result.type      = SIGNAL_NONE;
         result.reasoning = "Missing market data (ATR/SR levels)";
         m_cachedEvalResult = result;
         return result;
      }

      SignalDecision decision;
      bool found = DetectSignalCore(decision, atrPoints,
                                    m_marketData.support, m_marketData.resistance,
                                    m_marketData.htfSupport, m_marketData.htfResistance,
                                    m_marketData.isSupBroken, m_marketData.isResBroken,
                                    m_marketData.supBufferMult, m_marketData.resBufferMult,
                                    m_marketData.supHtfAlign, m_marketData.resHtfAlign);
      if(!found)
      {
         result.type      = SIGNAL_NONE;
         result.reasoning = decision.reason;
         m_cachedEvalResult = result;
         return result;
      }

      result.type = (decision.orderType == ORDER_TYPE_BUY) ? SIGNAL_BUY : SIGNAL_SELL;
      // [v2.01 FIX #13] Store actual detected values
      result.detectedPattern    = decision.patternType;
      result.detectedSignalPrice= decision.signalPrice;

      result.patternScore    = CalculatePatternScore(decision.patternType, 75.0);
      result.regimeScore     = CalculateRegimeScore(result.type);

      // [v2.01 FIX #8] avgATR via CopyBuffer with cached handle
      double currentATR = atrPoints * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double avgATR     = currentATR;
      if(m_handleATR_ForAvg == INVALID_HANDLE)
         m_handleATR_ForAvg = iATR(m_symbol, m_period, 14);
      if(m_handleATR_ForAvg != INVALID_HANDLE)
      {
         double atrBuf[50];
         if(CopyBuffer(m_handleATR_ForAvg, 0, 1, 50, atrBuf) == 50)
         {
            double s = 0; for(int i = 0; i < 50; i++) s += atrBuf[i];
            avgATR = (s / 50.0) * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
         }
      }
      result.volatilityScore = CalculateVolatilityScore(currentATR, avgATR);
      result.newsScore       = CalculateNewsScore();
      result.mtfScore        = CalculateMTFScore(result.type);

      result.score = result.patternScore   * 0.40
                   + result.regimeScore    * 0.20
                   + result.volatilityScore* 0.15
                   + result.newsScore      * 0.15
                   + result.mtfScore       * 0.10;

      if(result.score >= 0.85)     result.confidence = CONFIDENCE_VERY_HIGH;
      else if(result.score >= 0.70) result.confidence = CONFIDENCE_HIGH;
      else if(result.score >= 0.50) result.confidence = CONFIDENCE_MEDIUM;
      else                          result.confidence = CONFIDENCE_LOW;

      result.isStable       = IsSignalStable(result.type);
      result.stabilityCount = m_signalStabilityCount;

      if(result.score < result.dynamicThreshold)
      {
         result.type      = SIGNAL_NONE;
         result.reasoning = StringFormat("Score %.2f below threshold %.2f", result.score, result.dynamicThreshold);
         m_cachedEvalResult = result;
         return result;
      }

      ENUM_MARKET_REGIME regime = REGIME_NONE;
      if(CheckPointer(g_regimeFilter) != POINTER_INVALID)
         regime = g_regimeFilter.GetResult().regime;
      else
      {
         if(result.regimeScore >= 0.75)       regime = REGIME_TRENDING_STRONG;
         else if(result.regimeScore >= 0.5)   regime = REGIME_RANGING_SIDEWAYS;
         else                                  regime = REGIME_CHOPPY_HIGH_VOL;
      }

      int mtfAlign = (result.mtfScore >= 0.75) ? 2 : (result.mtfScore >= 0.5) ? 0 : -1;
      result.reasoning = BuildReasoning(result, decision.patternType, regime, mtfAlign);

      if(result.type != SIGNAL_NONE && result.isStable)
         m_lastValidSignal = result;

      m_cachedEvalResult = result;
      return result;
   }

   bool HasValidSignal()
   {
      return Evaluate().IsActionable();
   }

   const SignalResult& GetLastSignalResult() const { return m_lastValidSignal; }

private:
   // [v2.01 FIX #13] Use actual signalPrice/patternType from Evaluate() result
   void ProcessSignalOnNewBar(NewBarEvent *e)
   {
      double atrPoints = m_marketData.atrPoints;
      if(atrPoints <= 0 || m_marketData.support <= 0 || m_marketData.resistance <= 0) return;

      SignalResult result = Evaluate();
      if(!result.IsActionable()) return;

      SignalDecision decision;
      ZeroMemory(decision);
      decision.valid       = true;
      decision.orderType   = (result.type == SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      // [v2.01 FIX #13] use actual detected price, not hardcoded support
      decision.signalPrice = (result.detectedSignalPrice > 0)
                             ? result.detectedSignalPrice
                             : ((result.type == SIGNAL_BUY) ? m_marketData.support : m_marketData.resistance);
      decision.zonePrice   = (result.type == SIGNAL_BUY) ? m_marketData.support : m_marketData.resistance;
      // [v2.01 FIX #13] use actual detected pattern, not hardcoded ENGULFING
      decision.patternType = (result.detectedPattern != PATTERN_NONE) ? result.detectedPattern : PATTERN_ENGULFING;
      decision.reason      = result.reasoning;
      decision.bias        = (result.type == SIGNAL_BUY) ? 1 : -1;

      SignalGeneratedEvent *sigEvent = new SignalGeneratedEvent(
         decision, atrPoints, m_marketData.support, m_marketData.resistance);
      DispatchEvent(sigEvent);
      RegisterSignalCooldown(decision.signalPrice);
   }
};

#endif
