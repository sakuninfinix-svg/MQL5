//+------------------------------------------------------------------+
//|                                                SignalManager.mqh |
//|                                       Copyright 2026, Agsicentre |
//|            Event-Driven Signal Generation Module                 |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "1.00"
#property strict

#ifndef __SIGNAL_MANAGER_MQH__
#define __SIGNAL_MANAGER_MQH__

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
      MqlRates rates[];
      if (CopyRates(m_symbol, m_period, 0, 1, rates) <= 0)
         return false;
      datetime currBar = rates[0].time;

      double tol = atrPoints * CFG.sr.zoneReuseATR * SymbolInfoDouble(m_symbol, SYMBOL_POINT);

      if (isBuy)
         return (m_lastBuyZoneBar == currBar && MathAbs(zonePrice - m_lastBuyZonePrice) <= tol);
      return (m_lastSellZoneBar == currBar && MathAbs(zonePrice - m_lastSellZonePrice) <= tol);
   }

   void RegisterZoneUse(bool isBuy, double zonePrice)
   {
      MqlRates rates[];
      if (CopyRates(m_symbol, m_period, 0, 1, rates) <= 0)
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
      datetime now = TimeCurrent();
      double tol = atrPoints * CFG.sr.zoneReuseATR * SymbolInfoDouble(m_symbol, SYMBOL_POINT);

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
         {
            for (int j = i; j < ArraySize(m_failedZones) - 1; j++)
               m_failedZones[j] = m_failedZones[j + 1];
            ArrayResize(m_failedZones, ArraySize(m_failedZones) - 1);
         }
      }
   }

   void RegisterFailure(double zonePrice)
   {
      int sz = ArraySize(m_failedZones);
      ArrayResize(m_failedZones, sz + 1);
      m_failedZones[sz].price = zonePrice;
      m_failedZones[sz].expiry = TimeCurrent() + (CFG.pattern.failureCooldownBars * PeriodSeconds(m_period));

      if (m_debugMode)
         PrintFormat("[PASR Signal] Level %.5f registered as FAILED. Cooldown %d candles.",
                     zonePrice, CFG.pattern.failureCooldownBars);
   }

   // --- Signal Cooldown Management ---
   bool IsSignalCooldownActive(double price, double atrPoints)
   {
      return IsSignalCooldownActiveWithCustomBars(price, atrPoints, CFG.risk.signalCooldownBars);
   }
   
   // NEW: Signal Cooldown dengan custom bars untuk dynamic cooldown
   bool IsSignalCooldownActiveWithCustomBars(double price, double atrPoints, int cooldownBars)
   {
      datetime now = TimeCurrent();
      
      for (int i = ArraySize(m_signalCooldowns) - 1; i >= 0; i--)
      {
         if (now > m_signalCooldowns[i].expiry)
            continue;
         double tol = atrPoints * CFG.sr.zoneReuseATR * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
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
      int sz = ArraySize(m_signalCooldowns);
      ArrayResize(m_signalCooldowns, sz + 1);
      m_signalCooldowns[sz].price = price;
      m_signalCooldowns[sz].expiry = TimeCurrent() + (CFG.risk.signalCooldownBars * PeriodSeconds(m_period));

      if (m_debugMode)
         PrintFormat("[PASR Signal] Signal cooldown registered @ %.5f for %d bars.",
                     price, CFG.risk.signalCooldownBars);
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
      if (!CFG.risk.useMTF)
         return 0;

      double zone = (atrPoints * CFG.sr.atrBufferMult) * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
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
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double zoneWidth = (atrPoints * dynamicMult) * point;
      double multiplier = (CFG.risk.entryMode == MODE_SAFE) ? 0.5 : 1.0;
      
      if (CFG.pattern.useAdaptiveZoneBuffer && zoneStrength >= CFG.sr.minTouchesStrong)
      {
         multiplier *= CFG.pattern.strongZoneBufferMult; 
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

      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double maxAllowedRange = CFG.pattern.maxSignalATR * atrPoints * point;
      if (range > maxAllowedRange)
      {
         reason = "Signal too large";
         return false;
      }
      if ((body / range) > CFG.pattern.antiBreakoutPct)
      {
         reason = "Body too long";
         return false;
      }

      double threshold = atrPoints * CFG.pattern.momentumThresholdATR * point;
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

      if (!CFG.risk.useMTF)
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
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double tpBuffer = CFG.exit.tpBufferATR * atrPoints * point;
      double projectedTP = (dir == 1) ? (target - tpBuffer) : (target + tpBuffer);
      double profitDist = MathAbs(entryPrice - projectedTP);

      // 2. Hitung Proyeksi SL
      double slBuffer = CFG.exit.slBufferATR * atrPoints * point;
      double baseSL = (CFG.risk.tpslMode == TPSL_PATTERN) ? patternExtreme : ((dir == 1) ? support : resistance);
      double projectedSL = (dir == 1) ? (baseSL - slBuffer) : (baseSL + slBuffer);
      
      // Pastikan riskDist minimal 1 point untuk menghindari pembagian nol
      double riskDist = MathMax(MathAbs(entryPrice - projectedSL), point);

      // 3. Validasi Jarak minimum TP
      double minTPDist = (atrPoints * CFG.exit.minTPDistATR) * point;
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
      ZeroMemory(decision);
      string reason = "No pattern detected";

      // Validate data availability
      if (Bars(m_symbol, m_period) < CFG.pattern.lookback + 5)
      {
         decision.reason = "Insufficient history data";
         return false;
      }

      // === OPTIMIZATION: Batch fetch candles once ===
      MqlRates rates[];
      if (!FetchCandleBatch(1, CFG.pattern.lookback + 4, rates))
      {
         decision.reason = "Failed to fetch candle data";
         return false;
      }

      for (int shift = 0; shift < CFG.pattern.lookback; shift++)
      {
         string currentFilterReason = "";
         int dir = 0;
         double signalPrice = 0;
         ENUM_PATTERN_TYPE pType = PATTERN_NONE;
         string patternReason = "";
         double pScore = 0;
         double pSLMult = 1.0;

         if (!m_patterns.Detect(rates, shift, atrPoints, pType, dir, signalPrice, pScore, pSLMult, patternReason))
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
         if (CFG.risk.useMTF)
         {
            if (((dir == 1 && bias > 0) || (dir == -1 && bias < 0)) ||
                ((dir == 1 && supHtfAlign == 1) || (dir == -1 && resHtfAlign == 1)))
               finalConfluenceScore += CFG.pattern.mtfConfluenceBonus;
         }

         // Bonus jika selaras dengan HTF zone alignment
         if (currentBufferMult < CFG.pattern.strongZoneThreshold)
            finalConfluenceScore += CFG.pattern.strongZoneBonus;

         // 9. Signal Cooldown Filter - NEW: Dynamic Cooldown untuk HQ Setup
         bool isHighQualitySetup = (finalConfluenceScore >= CFG.pattern.hqThreshold);
         int effectiveCooldownBars = CFG.risk.signalCooldownBars;
         
         if (CFG.pattern.useDynamicCooldown && isHighQualitySetup)
         {
            effectiveCooldownBars = CFG.pattern.reducedCooldownBars; // Bypass cooldown normal untuk HQ setup
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
      ZeroMemory(decision);
      string reason = "No recovery pattern detected";

      if (!CFG.recovery.use)
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
      if (pScore < CFG.recovery.scoreThreshold)
      {
         reason = StringFormat("Recovery pattern score too low (%.2f < %.2f)", pScore, CFG.recovery.scoreThreshold);
         return false;
      }

      // Check if the signal is near the SL hit price (within tolerance)
      double tolerance = atrPoints * CFG.recovery.zoneToleranceATR * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
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
   }

   virtual void Deinit() override
   {
      ArrayFree(m_failedZones);
      ArrayFree(m_signalCooldowns); // FIX: Free signal cooldowns
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
   // --- PriceUpdate Event: Cache tick, don't process yet ---
   virtual void OnPriceUpdate(PriceUpdateEvent *e) override
   {
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
   }

   // --- Heartbeat Event ---
   virtual void OnHeartbeat(HeartbeatEvent *e) override
   {
      CleanupFailedZones();
      CleanupSignalCooldowns(); // FIX: Call cleanup for signal cooldowns
   }

   // Handle specific events with static dispatch hooks
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
      if (!CFG.recovery.use)
         return;

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
         Log(StringFormat("Recovery signal detected for original trade %d: %s", roe.originalTicket, recoveryDecision.reason));
      } else {
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
         if (m_debugMode)
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
         DispatchEvent(sigEvent); // Memory auto-managed

         RegisterSignalCooldown(decision.signalPrice);
      }
   }
};

#endif