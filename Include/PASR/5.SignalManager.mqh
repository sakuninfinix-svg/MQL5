//+------------------------------------------------------------------+
//|                                                SignalManager.mqh |
//|                              Event-Driven Version for PASR EA    |
//|                                     Copyright 2026, Agsicentre   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "1.00"

#ifndef __SIGNAL_MANAGER_MQH__
#define __SIGNAL_MANAGER_MQH__

#property strict
#include "IManager.mqh"
#include "9.PatternManager.mqh"

//+------------------------------------------------------------------+
//| Handles: PriceUpdate, NewBar, ConfigReload, EmergencyStop      |
//+------------------------------------------------------------------+
class SignalManager : public IManager
{
   //+------------------------------------------------------------------+
   //| PRIVATE: Internal State & Cache                                 |
   //+------------------------------------------------------------------+
private:
   PatternManager m_patterns;

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

   // --- Failure Cooldown ---
   struct FailedZone
   {
      double price;
      datetime expiry;
   };
   FailedZone m_failedZones[];

   // --- Event-Driven State Flags ---
   bool m_hasNewTick;
   bool m_hasNewBar;
   MqlTick m_cachedTick;
   datetime m_lastProcessedBar;
   SignalDecision m_pendingSignal;
   bool m_signalPending;
   bool m_marketGateOpen;
   bool m_marketEntryAllowed;
   double m_marketSpread;
   double m_marketATR;

   // --- Cached Market Data from Events ---
   struct CachedMarketData
   {
      double atrPoints;
      double support, resistance;
      double htfSupport, htfResistance;
      bool isSupBroken, isResBroken;
      double supBufferMult, resBufferMult;
      int supHtfAlign, resHtfAlign;
      int supStrength, resStrength; // NEW: Zone strength for adaptive filtering

      void Reset() { ZeroMemory(this); }
   } m_marketData;

   // --- Config Cache (hindari repeated CFG access) ---
   struct CachedConfig
   {
      int signalLookback;
      bool useMTF;
      bool exitOnOpposite;
      ENUM_TPSL_MODE tpslMode;
      double strongZoneBonus;
      double strongZoneThreshold;
      double zoneReuseATR;
      int patternFailureCooldownBars;
      ENUM_ENTRY_MODE entryMode;
      double maxSignalATR;
      double antiBreakoutPct;
      double momentumThresholdATR;
      double minTPDistanceATR;
      double slBufferATR;
      double tpBufferATR;
      int signalCooldownBars;
      double atrBufferMult;
      bool debugMode;
      // NEW: High Quality Entry Settings
      double highQualityThreshold;
      bool useDynamicCooldown;
      int reducedCooldownBars;
      double mtfConfluenceBonus;
      bool usePatternWeights;
      double recoveryPatternScoreThreshold;
      double recoveryZoneToleranceATR;
      bool useRecoveryMode;
      double strongZoneBufferMult;
      bool useAdaptiveZoneBuffer;
      int srMinTouchesStrong;
   } m_cfgCache;

   //+------------------------------------------------------------------+
   //| PRIVATE: Helper Methods                                         |
   //+------------------------------------------------------------------+
private:
   virtual void RefreshConfigCache() override
   {
      m_cfgCache.signalLookback = CFG.SignalLookback;
      m_cfgCache.useMTF = CFG.UseMTF;
      m_cfgCache.exitOnOpposite = CFG.ExitOnOpposite;
      m_cfgCache.tpslMode = CFG.TPSLMode;
      m_cfgCache.strongZoneBonus = CFG.StrongZoneBonus;
      m_cfgCache.strongZoneThreshold = CFG.StrongZoneThreshold;
      m_cfgCache.zoneReuseATR = CFG.ZoneReuseATR;
      m_cfgCache.patternFailureCooldownBars = CFG.PatternFailureCooldownBars;
      m_cfgCache.entryMode = CFG.EntryMode;
      m_cfgCache.maxSignalATR = CFG.MaxSignalATR;
      m_cfgCache.antiBreakoutPct = CFG.AntiBreakoutPct;
      m_cfgCache.momentumThresholdATR = CFG.MomentumThresholdATR;
      m_cfgCache.minTPDistanceATR = CFG.MinTPDistanceATR;
      m_cfgCache.slBufferATR = CFG.SLBufferATR;
      m_cfgCache.tpBufferATR = CFG.TPBufferATR;
      m_cfgCache.signalCooldownBars = CFG.SignalCooldownBars;
      m_cfgCache.atrBufferMult = CFG.ATRBufferMult;
      m_cfgCache.debugMode = CFG.DebugMode;
      // NEW: High Quality Entry Settings
      m_cfgCache.highQualityThreshold = CFG.HighQualityThreshold;
      m_cfgCache.useDynamicCooldown = CFG.UseDynamicCooldown;
      m_cfgCache.reducedCooldownBars = CFG.ReducedCooldownBars;
      m_cfgCache.mtfConfluenceBonus = CFG.MTFConfluenceBonus;
      m_cfgCache.usePatternWeights = CFG.UsePatternWeights;
      m_cfgCache.recoveryPatternScoreThreshold = CFG.RecoveryPatternScoreThreshold;
      m_cfgCache.recoveryZoneToleranceATR = CFG.RecoveryZoneToleranceATR;
      m_cfgCache.useRecoveryMode = CFG.UseRecoveryMode;
      m_cfgCache.strongZoneBufferMult = CFG.StrongZoneBufferMult;
      m_cfgCache.useAdaptiveZoneBuffer = CFG.UseAdaptiveZoneBuffer;
      m_cfgCache.srMinTouchesStrong = CFG.SRMinTouchesStrong;
   }

   bool FetchCandleBatch(int shiftStart, int count, MqlRates &outRates[])
   {
      ArraySetAsSeries(outRates, true);
      int copied = CopyRates(_Symbol, _Period, shiftStart, count, outRates);
      return (copied > 0);
   }

   // --- Zone Reuse Check ---
   bool IsZoneReuseBlocked(bool isBuy, double zonePrice, double atrPoints)
   {
      datetime times[];
      if (CopyTime(_Symbol, _Period, 0, 1, times) <= 0)
         return false;
      datetime currBar = times[0];

      double tol = atrPoints * m_cfgCache.zoneReuseATR * _Point;

      if (isBuy)
         return (m_lastBuyZoneBar == currBar && MathAbs(zonePrice - m_lastBuyZonePrice) <= tol);
      return (m_lastSellZoneBar == currBar && MathAbs(zonePrice - m_lastSellZonePrice) <= tol);
   }

   void RegisterZoneUse(bool isBuy, double zonePrice)
   {
      datetime times[];
      if (CopyTime(_Symbol, _Period, 0, 1, times) <= 0)
         return;
      datetime currBar = times[0];

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
   bool IsPatternFailureBlocked(bool isBuy, double zonePrice, double atrPoints)
   {
      datetime now = TimeCurrent();
      double tol = atrPoints * m_cfgCache.zoneReuseATR * _Point;

      for (int i = ArraySize(m_failedZones) - 1; i >= 0; i--)
      {
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
         {
            for (int j = i; j < ArraySize(m_failedZones) - 1; j++)
               m_failedZones[j] = m_failedZones[j + 1];
            ArrayResize(m_failedZones, ArraySize(m_failedZones) - 1);
         }
      }
   }

   void RegisterFailure(bool isBuy, double zonePrice)
   {
      int sz = ArraySize(m_failedZones);
      ArrayResize(m_failedZones, sz + 1);
      m_failedZones[sz].price = zonePrice;
      m_failedZones[sz].expiry = TimeCurrent() + (m_cfgCache.patternFailureCooldownBars * PeriodSeconds(_Period));

      if (m_cfgCache.debugMode)
         PrintFormat("[PASR Signal] Level %.5f registered as FAILED. Cooldown %d candles.",
                     zonePrice, m_cfgCache.patternFailureCooldownBars);
   }

   // --- Signal Cooldown Management ---
   bool IsSignalCooldownActive(double price, ENUM_ORDER_TYPE orderType, double atrPoints)
   {
      return IsSignalCooldownActiveWithCustomBars(price, orderType, atrPoints, m_cfgCache.signalCooldownBars);
   }
   
   // NEW: Signal Cooldown dengan custom bars untuk dynamic cooldown
   bool IsSignalCooldownActiveWithCustomBars(double price, ENUM_ORDER_TYPE orderType, double atrPoints, int cooldownBars)
   {
      datetime now = TimeCurrent();
      datetime expiryTime = now + (cooldownBars * PeriodSeconds(_Period));
      
      for (int i = ArraySize(m_signalCooldowns) - 1; i >= 0; i--)
      {
         if (now > m_signalCooldowns[i].expiry)
            continue;
         double tol = atrPoints * m_cfgCache.zoneReuseATR * _Point;
         if (MathAbs(price - m_signalCooldowns[i].price) <= tol)
         {
            // Any signal in the zone within cooldown period blocks new signals
            return true;
         }
      }
      return false;
   }

   void RegisterSignalCooldown(double price, ENUM_ORDER_TYPE orderType)
   {
      int sz = ArraySize(m_signalCooldowns);
      ArrayResize(m_signalCooldowns, sz + 1);
      m_signalCooldowns[sz].price = price;
      m_signalCooldowns[sz].expiry = TimeCurrent() + (m_cfgCache.signalCooldownBars * PeriodSeconds(_Period));

      if (m_cfgCache.debugMode)
         PrintFormat("[PASR Signal] Signal cooldown registered @ %.5f for %d bars.",
                     price, m_cfgCache.signalCooldownBars);
   }

   void CleanupSignalCooldowns()
   {
      datetime now = TimeCurrent();
      for (int i = ArraySize(m_signalCooldowns) - 1; i >= 0; i--)
      {
         if (now > m_signalCooldowns[i].expiry)
         {
            for (int j = i; j < ArraySize(m_signalCooldowns) - 1; j++)
               m_signalCooldowns[j] = m_signalCooldowns[j + 1];
            ArrayResize(m_signalCooldowns, ArraySize(m_signalCooldowns) - 1);
         }
      }
   }

   // --- MTF Bias Helper ---
   int GetMTFBias(double price, double htfSupport, double htfResistance, double atrPoints)
   {
      if (!m_cfgCache.useMTF)
         return 0;

      double zone = (atrPoints * m_cfgCache.atrBufferMult) * _Point;
      bool nearHtfSupport = (price <= htfSupport + zone);
      bool nearHtfResistance = (price >= htfResistance - zone);

      if (nearHtfSupport && !nearHtfResistance)
         return 1;
      if (nearHtfResistance && !nearHtfSupport)
         return -1;
      return 0;
   }

   //+------------------------------------------------------------------+
   //| PRIVATE: Signal Detection Logic (Core Business)                 |
   //+------------------------------------------------------------------+
private:
   // === FILTER METHODS (dipisah agar mudah di-test) ===

   bool PassZoneTouchFilter(int shift, int dir, double zonePrice,
                            double atrPoints, double dynamicMult, string &reason,
                            const MqlRates &rates[], int zoneStrength = 0)
   {
      double extreme = (dir == 1) ? rates[shift].low : rates[shift].high;
      double zoneWidth = (atrPoints * dynamicMult) * _Point;
      double multiplier = (m_cfgCache.entryMode == MODE_SAFE) ? 0.5 : 1.0;
      
      if (m_cfgCache.useAdaptiveZoneBuffer && zoneStrength >= m_cfgCache.srMinTouchesStrong)
      {
         multiplier *= m_cfgCache.strongZoneBufferMult; 
      }

      bool ok = (dir == 1) ? (extreme <= zonePrice + (zoneWidth * multiplier)) : (extreme >= zonePrice - (zoneWidth * multiplier));

      if (!ok)
         reason = "Not touching zone";
      return ok;
   }

   bool PassContextFilter(int shift, double atrPoints, string &reason,
                          const MqlRates &rates[], int dir)
   {
      double o = rates[shift].open, h = rates[shift].high;
      double l = rates[shift].low, c = rates[shift].close;
      double range = h - l;
      double body = MathAbs(o - c);

      // Pastikan range tidak 0 untuk menghindari division by zero
      if (range <= 0) return false;

      double maxAllowedRange = m_cfgCache.maxSignalATR * atrPoints * _Point;
      if (range > maxAllowedRange)
      {
         reason = "Signal too large";
         return false;
      }
      if ((body / range) > m_cfgCache.antiBreakoutPct)
      {
         reason = "Body too long";
         return false;
      }

      double threshold = atrPoints * m_cfgCache.momentumThresholdATR * _Point;
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
      bias = GetMTFBias(referencePrice, htfSupport, htfResistance, atrPoints);

      if (!m_cfgCache.useMTF)
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
      double entryPrice = rates[shift].close;
      double target = (dir == 1) ? resistance : support;
      
      // 1. Hitung Proyeksi TP (Selalu ke SR lawan dengan buffer)
      double tpBuffer = m_cfgCache.tpBufferATR * atrPoints * _Point;
      double projectedTP = (dir == 1) ? (target - tpBuffer) : (target + tpBuffer);
      double profitDist = MathAbs(entryPrice - projectedTP);

      // 2. Hitung Proyeksi SL berdasarkan Mode
      double slBuffer = m_cfgCache.slBufferATR * atrPoints * _Point;
      double baseSL = (m_cfgCache.tpslMode == TPSL_PATTERN) ? patternExtreme : ((dir == 1) ? support : resistance);
      double projectedSL = (dir == 1) ? (baseSL - slBuffer) : (baseSL + slBuffer);
      
      // Pastikan riskDist minimal 1 point untuk menghindari pembagian nol
      double riskDist = MathMax(MathAbs(entryPrice - projectedSL), _Point);

      // 3. Validasi Jarak minimum TP
      double minTPDist = (atrPoints * m_cfgCache.minTPDistanceATR) * _Point;
      if (profitDist < minTPDist)
      {
         reason = "TP distance < Min ATR";
         return false;
      }

      // 4. Validasi Risk:Reward (Minimal 1:1)
      if (profitDist < riskDist * 1.0) 
      {
         reason = StringFormat("Poor R:R (Risk:%.1fpt TP:%.1fpt)", riskDist/_Point, profitDist/_Point);
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
      ZeroMemory(decision);
      string reason = "No pattern detected";

      // Validate data availability
      if (Bars(_Symbol, _Period) < m_cfgCache.signalLookback + 5)
      {
         decision.reason = "Insufficient history data";
         return false;
      }

      // === OPTIMIZATION: Batch fetch candles once ===
      MqlRates rates[];
      if (!FetchCandleBatch(1, m_cfgCache.signalLookback + 4, rates))
      {
         decision.reason = "Failed to fetch candle data";
         return false;
      }

      // Scan patterns in lookback window
      // Prinsip MQL5: shift 0 pada array hasil CopyRates(pos 1) adalah Bar 1 (Last Closed Bar)
      for (int shift = 0; shift < m_cfgCache.signalLookback; shift++)
      {
         string currentFilterReason = "";
         int dir = 0;
         double signalPrice = 0;
         ENUM_PATTERN_TYPE pType = PATTERN_NONE;
         string patternReason = "";
         double pScore = 0;
         double pSLMult = 1.0;

         if (!m_patterns.Detect(rates, shift, atrPoints, pType, dir, signalPrice, pScore, patternReason))
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
         if (m_cfgCache.useMTF)
         {
            if (((dir == 1 && bias > 0) || (dir == -1 && bias < 0)) ||
                ((dir == 1 && supHtfAlign == 1) || (dir == -1 && resHtfAlign == 1)))
               finalConfluenceScore += m_cfgCache.mtfConfluenceBonus;
         }

         // Bonus jika selaras dengan HTF zone alignment
         if (currentBufferMult < m_cfgCache.strongZoneThreshold)
            finalConfluenceScore += m_cfgCache.strongZoneBonus;

         // 9. Signal Cooldown Filter - NEW: Dynamic Cooldown untuk HQ Setup
         bool isHighQualitySetup = (finalConfluenceScore >= m_cfgCache.highQualityThreshold);
         int effectiveCooldownBars = m_cfgCache.signalCooldownBars;
         
         if (m_cfgCache.useDynamicCooldown && isHighQualitySetup)
         {
            effectiveCooldownBars = m_cfgCache.reducedCooldownBars; // Bypass cooldown normal untuk HQ setup
         }
         
         if (IsSignalCooldownActiveWithCustomBars(signalPrice, currentOrderType, atrPoints, effectiveCooldownBars))
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

         if (m_cfgCache.debugMode)
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
      ZeroMemory(decision);
      string reason = "No recovery pattern detected";

      if (!m_cfgCache.useRecoveryMode)
         return false;

      // Fetch candles around the SL hit price
      MqlRates rates[];
      // Look for patterns on the last closed bar (shift 0)
      if (!FetchCandleBatch(1, 4, rates)) // Need at least 3-4 bars for most patterns
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

      if (!m_patterns.Detect(rates, shift, atrPoints, pType, dir, signalPrice, pScore, pSLMult, patternReason))
         return false;

      // Ensure pattern is in the target reversal direction
      if (dir != targetDir)
         return false;

      // Check if pattern score meets recovery threshold
      if (pScore < m_cfgCache.recoveryPatternScoreThreshold)
      {
         reason = StringFormat("Recovery pattern score too low (%.2f < %.2f)", pScore, m_cfgCache.recoveryPatternScoreThreshold);
         return false;
      }

      // Check if the signal is near the SL hit price (within tolerance)
      double tolerance = atrPoints * m_cfgCache.recoveryZoneToleranceATR * _Point;
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
      m_hasNewTick = false;
      m_hasNewBar = false;
      m_signalPending = false;
      m_marketGateOpen = true;
      m_marketEntryAllowed = true;
      m_marketSpread = 0.0;
      m_marketATR = 0.0;
   }

   virtual void Deinit() override
   {
      ArrayFree(m_failedZones);
      ArrayFree(m_signalCooldowns); // FIX: Free signal cooldowns
      m_signalPending = false;
      IManager::Deinit();
   }

   virtual void DeclareEvents() override
   {
      AddEvent("PriceUpdate");
      AddEvent("NewBar");
      AddEvent("ZoneUpdate");
      AddEvent("RecoveryOpportunity"); // Listen for recovery opportunities
      AddEvent("MarketGate");
   }

   //+------------------------------------------------------------------+
   //| PUBLIC: Event Handler Methods                                   |
   //+------------------------------------------------------------------+
public:
   // --- PriceUpdate Event: Cache tick, don't process yet ---
   virtual void OnPriceUpdate(PriceUpdateEvent *e) override
   {
      if (CheckPointer(e) == POINTER_INVALID)
         return;
      m_cachedTick = e.tick;
      m_hasNewTick = true;
   }

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
         if (m_cfgCache.debugMode)
            PrintFormat("[SignalManager] Market gate closed or cooldown active. gateOpen=%s entryAllowed=%s",
                        m_marketGateOpen ? "true" : "false",
                        m_marketEntryAllowed ? "true" : "false");
         m_lastProcessedBar = e.barOpenTime;
         m_hasNewTick = false;
         return;
      }

      // === SIGNAL DETECTION EXECUTION ===
      ProcessSignalOnNewBar(e);
      m_lastProcessedBar = e.barOpenTime;
      m_hasNewTick = false; // Reset for next cycle
   }

   // --- ConfigReload Event ---
   virtual void OnConfigReload(ConfigReloadEvent *e) override
   {
      RefreshConfigCache();
   }

   // --- EmergencyStop Event ---
   virtual void OnEmergencyStop(EmergencyStopEvent *e) override
   {
      m_signalPending = false;
      if (m_cfgCache.debugMode)
         Log("Emergency Stop: Clearing pending signals.");
   }

   // --- Heartbeat Event ---
   virtual void OnHeartbeat(HeartbeatEvent *e) override
   {
      CleanupFailedZones();
      CleanupSignalCooldowns(); // FIX: Call cleanup for signal cooldowns
   }

   virtual void OnCustomEvent(Event *e) override
   {
      if (e.Type() == "ZoneUpdate")
      {
         ZoneUpdateEvent *ze = dynamic_cast<ZoneUpdateEvent *>(e);
         if (CheckPointer(ze) == POINTER_INVALID)
            return;

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
         m_marketData.supStrength = ze.supStrength; // NEW: Zone strength
         m_marketData.resStrength = ze.resStrength;
      }
      else if (e.Type() == "MarketGate")
      {
         MarketGateEvent *mg = dynamic_cast<MarketGateEvent *>(e);
         if (CheckPointer(mg) == POINTER_INVALID)
            return;

         m_marketGateOpen = mg.gateOpen;
         m_marketEntryAllowed = mg.entryAllowed;
         m_marketSpread = mg.spread;
         m_marketATR = mg.atrPoints;
      }
      else if (e.Type() == "RecoveryOpportunity")
      {
         RecoveryOpportunityEvent *roe = dynamic_cast<RecoveryOpportunityEvent *>(e);
         if (CheckPointer(roe) == POINTER_INVALID)
            return;

         if (!m_cfgCache.useRecoveryMode)
            return;

         // Attempt to detect a recovery signal immediately
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
            // Signal found! Dispatch to ExecutionManager via event
            RecoverySignalEvent *recSigEvent = new RecoverySignalEvent(
                roe.originalTicket, recoveryDecision, roe.atrPoints, m_marketData.support, m_marketData.resistance);
            EventBus::Instance().Dispatch(recSigEvent);
            Log(StringFormat("Recovery signal detected for original trade %d: %s", roe.originalTicket, recoveryDecision.reason));
         } else {
            Log(StringFormat("No immediate recovery signal found for original trade %d.", roe.originalTicket));
         }
      }
   }
   //+------------------------------------------------------------------+
   //| PUBLIC: Integration Methods (for other modules)                 |
   //+------------------------------------------------------------------+
public:
   // Called by SRManager or similar to trigger signal check
   // This is the "pull" interface for backward compatibility
   bool TryGenerateSignal(SignalDecision &outDecision,
                          double atrPoints,
                          double support, double resistance,
                          double htfSupport, double htfResistance,
                          bool isSupBroken, bool isResBroken,
                          double supBufferMult, double resBufferMult,
                          int supHtfAlign, int resHtfAlign)
   {
      // Direct call to core detection logic
      bool found = DetectSignalCore(outDecision, atrPoints, support, resistance,
                                    htfSupport, htfResistance, isSupBroken, isResBroken,
                                    supBufferMult, resBufferMult, supHtfAlign, resHtfAlign);

      // If signal found, also dispatch event for other modules
      if (found && outDecision.valid)
      {
         SignalGeneratedEvent *sigEvent = new SignalGeneratedEvent(
             outDecision, atrPoints, support, resistance);
         EventBus::Instance().Dispatch(sigEvent); // Auto-cleanup after dispatch
      }

      return found;
   }

   // Register a failed zone externally (e.g., from TradeManager on loss)
   void NotifyPatternFailure(bool isBuy, double zonePrice)
   {
      RegisterFailure(isBuy, zonePrice);
   }

   // Get pending signal (if any) - for polling-style integration
   bool HasPendingSignal(SignalDecision &outSignal)
   {
      if (m_signalPending)
      {
         outSignal = m_pendingSignal;
         m_signalPending = false; // Consume the signal
         return true;
      }
      return false;
   }

   //+------------------------------------------------------------------+
   //| PRIVATE: Core Processing Logic                                  |
   //+------------------------------------------------------------------+
private:
   // Main processing method called on NewBar event
   void ProcessSignalOnNewBar(NewBarEvent *e)
   {
      // Use cached data from ZoneUpdateEvent
      double atrPoints = m_marketData.atrPoints;
      double support = m_marketData.support;
      double resistance = m_marketData.resistance;
      double htfSupport = m_marketData.htfSupport;
      double htfResistance = m_marketData.htfResistance;
      bool isSupBroken = m_marketData.isSupBroken;
      bool isResBroken = m_marketData.isResBroken;
      double supBufferMult = m_marketData.supBufferMult;
      double resBufferMult = m_marketData.resBufferMult;
      int supHtfAlign = m_marketData.supHtfAlign;
      int resHtfAlign = m_marketData.resHtfAlign;

      if (atrPoints <= 0 || support <= 0 || resistance <= 0)
      {
         if (m_cfgCache.debugMode)
            Print("[SignalManager] Missing data for signal detection");
         return;
      }

      // Run core detection
      SignalDecision decision;
      if (DetectSignalCore(decision, atrPoints, support, resistance,
                           htfSupport, htfResistance, isSupBroken, isResBroken,
                           supBufferMult, resBufferMult, supHtfAlign, resHtfAlign))
      {
         // Signal found! Dispatch to ExecutionManager via event
         SignalGeneratedEvent *sigEvent = new SignalGeneratedEvent(
             decision, atrPoints, support, resistance);
         EventBus::Instance().Dispatch(sigEvent); // Memory auto-managed

         RegisterSignalCooldown(decision.signalPrice, decision.orderType); // FIX: Register cooldown
         // Also buffer for polling-style access (backward compat)
         m_pendingSignal = decision;
         m_signalPending = true;
      }
   }
};

#endif