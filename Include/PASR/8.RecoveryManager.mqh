//+------------------------------------------------------------------+
//|                                              RecoveryManager.mqh |
//|                                       Copyright 2026, Agsicentre |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "1.00"

#ifndef __RECOVERY_MANAGER_MQH__
#define __RECOVERY_MANAGER_MQH__

#property strict
#include <Trade/Trade.mqh>
#include "IManager.mqh"
#include "10.DataManager.mqh"
#include "9.PatternManager.mqh"

//+------------------------------------------------------------------+
//| RecoveryManager - Event-Driven Position Lifecycle Manager       |
//| Subscribes: PriceUpdate, OrderExecution, SignalGenerated,       |
//|             EmergencyStop, Heartbeat, ConfigReload              |
//| Lightweight: Cached config access, static fakeout detection      |
//+------------------------------------------------------------------+
class RecoveryManager : public IManager
{
   //+------------------------------------------------------------------+
   //| PRIVATE: State & Cache                                          |
   //+------------------------------------------------------------------+
private:
   RecoveryEngine *engines[];
   CTrade m_trade;

   // Event-Driven State
   ulong m_lastTrailingUpdate; // Throttle trailing modifications (dalam mikrosekon)
   int m_trailingThrottleMs;   // Min interval between trailing updates

   struct RecoveryConfigCache
   {
      ulong magicNum;
      bool useRecovery;
      int maxRecoveryAttempts;
      int recoveryCooldownBars;
      double fakeoutSLAdjustmentATR;
      bool exitOnOpposite;
      bool useTrailing;
      bool usePartialClose;
      double partialCloseLotPct;
      double partialCloseATR;
      int maxTradeDurationDays;
      double lockProfitATR;
      double lockOffsetATR;
      double trailActivationATR;
      double trailStepATR;
   } m_cfgCache;

   //+------------------------------------------------------------------+
   //| PRIVATE: Core Logic (Extracted & Optimized)                     |
   //+------------------------------------------------------------------+
private:
   virtual void RefreshConfigCache() override
   {
      IManager::RefreshConfigCache(); // Update inherited m_debugMode
      
      m_cfgCache.magicNum = (ulong)CFG.risk.magic;
      m_cfgCache.useRecovery = CFG.recovery.use;
      m_cfgCache.maxRecoveryAttempts = CFG.recovery.maxAttempts;
      m_cfgCache.recoveryCooldownBars = CFG.recovery.cooldownBars;
      m_cfgCache.fakeoutSLAdjustmentATR = CFG.recovery.fakeoutSLAdjATR;
      m_cfgCache.exitOnOpposite = CFG.exit.exitOnOpposite;
      m_cfgCache.useTrailing = CFG.exit.useTrailing;
      m_cfgCache.usePartialClose = CFG.exit.usePartial;
      m_cfgCache.partialCloseLotPct = CFG.exit.partialLotPct;
      m_cfgCache.partialCloseATR = CFG.exit.partialATR;
      m_cfgCache.maxTradeDurationDays = CFG.risk.maxTradeDurationDays;
      m_cfgCache.lockProfitATR = CFG.exit.lockProfitATR;
      m_cfgCache.lockOffsetATR = CFG.exit.lockOffsetATR;
      m_cfgCache.trailActivationATR = CFG.exit.trailActivationATR;
      m_cfgCache.trailStepATR = CFG.exit.trailStepATR;
   }

   int FindEngineIndex(ulong ticket)
   {
      for (int i = 0; i < ArraySize(engines); i++)
      {
         if (CheckPointer(engines[i]) != POINTER_INVALID && engines[i].active && engines[i].mainTicket == ticket)
            return i;
      }
      return -1;
   }

   void ClearEngineGVs(ulong ticket)
   {
      string prefix = "PASR_" + (string)CFG.risk.magic + "_" + (string)ticket + "_";
      GlobalVariablesDeleteAll(prefix);
   }

   void CloseActivePosition(RecoveryEngine *r, const string reason)
   {
      if (CheckPointer(r) == POINTER_INVALID || r.state == TRADE_STATE_DONE)
         return;
      r.state = TRADE_STATE_DONE;

      bool closed = false;
      if (PositionSelectByTicket(r.mainTicket))
      {
         if (m_trade.PositionClose(r.mainTicket))
         {
            closed = true;
            if (m_debugMode)
               PrintFormat("[Recovery] Position %d closed: %s", r.mainTicket, reason);
         }
         else
         {
            if (m_debugMode)
               PrintFormat("[Recovery] Failed to close %d: Error %d", r.mainTicket, GetLastError());
         }
      }

      ClearEngineGVs(r.mainTicket);
      r.Reset();
      r.active = false;

      // Notify other modules
      PositionUpdateEvent *notify = new PositionUpdateEvent(r.mainTicket, 0, 0, true);
      DispatchEvent(notify);
   }

   //+------------------------------------------------------------------+
   //| DetectAndHandleFakeout - Multi-level fakeout detection & recovery |
   //| Returns: true if fakeout detected and SL adjusted (position held) |
   //| Returns: false if no fakeout or adjustment failed (enter recovery)|
   //+------------------------------------------------------------------+
   bool DetectAndHandleFakeout(RecoveryEngine *r, const MqlTick &tick, double atrPoints)
   {
      if (CheckPointer(r) == POINTER_INVALID || !r.active)
         return false;

      // Use integrated PatternManager context
      PatternManager::FakeoutContext ctx;
      ctx.originalTicket = r.mainTicket;
      ctx.direction = r.direction;
      ctx.slHitPrice = tick.bid; // Current price at SL hit
      ctx.entryPrice = r.entryPrice;
      ctx.atrPoints = atrPoints;
      ctx.slMultiplier = r.slMultiplier;
      ctx.currentTick = tick;

      // Fetch recent candles for pattern analysis
      ArraySetAsSeries(ctx.rates, true);
      if (CopyRates(_Symbol, _Period, 0, 3, ctx.rates) < 3)
      {
         if (m_debugMode)
            Log("Failed to fetch candles for fakeout detection");
         return false;
      }

      // Run fakeout detection
      FakeoutResult signal;
      if (!PatternManager::DetectFakeout(ctx, signal))
      {
         return false;
      }

      if (m_debugMode)
         PrintFormat("[Fakeout] Position %d: %s (Confidence: %.2f, Level: %d)",
                     r.mainTicket, signal.reason, signal.confidence, signal.level);

      // If we have multi-level confirmation, try to adjust SL/TP
      if (signal.level < 2)
      {
         if (m_debugMode)
            Log(StringFormat("Fakeout detected but low confidence (%.2f). Continuing to recovery mode.", signal.confidence));
         return false; // Not enough confidence, proceed to recovery
      }

      // Try to adjust SL/TP to recover from fakeout
      if (!PositionSelectByTicket(r.mainTicket))
         return false;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      double atr = atrPoints * _Point;

      // Calculate new SL further away to avoid fakeout
      double slAdjustmentPoints = atr * m_cfgCache.fakeoutSLAdjustmentATR;
      double newSL = 0;
      double newTP = currentTP;

      if (type == POSITION_TYPE_BUY)
      {
         newSL = NormalizeDouble(currentSL - slAdjustmentPoints, _Digits);
      }
      else
      {
         newSL = NormalizeDouble(currentSL + slAdjustmentPoints, _Digits);
      }

      // Validate new SL meets broker requirements
      double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      double curPrice = (type == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
      bool slValid = false;

      if (type == POSITION_TYPE_BUY)
         slValid = (curPrice - newSL) > stopLevel;
      else
         slValid = (newSL - curPrice) > stopLevel;

      if (!slValid)
      {
         if (m_debugMode)
            PrintFormat("[Fakeout] Cannot adjust SL: Too close to current price");
         return false;
      }

      // Execute modification using integrated pattern logic
      if (m_trade.PositionModify(r.mainTicket, newSL, newTP))
      {
         r.lastKnownATR = atrPoints;
         r.recoveryAttempts++;
         r.SaveState();

         if (m_debugMode)
            PrintFormat("[Fakeout] ✓ SL adjusted for %d: %.5f -> %.5f (Confidence: %.2f)",
                        r.mainTicket, currentSL, newSL, signal.confidence);
         return true; // Fakeout handled, position held
      }
      else
      {
         if (m_debugMode)
            PrintFormat("[Fakeout] ✗ Failed to adjust SL for %d: Error %d", r.mainTicket, GetLastError());
         return false;
      }
   }

   void ProcessTrailingAndPartial(RecoveryEngine *r, const MqlTick &tick, double atrPoints)
   {
      if (CheckPointer(r) == POINTER_INVALID || !r.active)
         return;
      if (!PositionSelectByTicket(r.mainTicket))
      {
         // Position no longer exists - clean up engine
         r.active = false;
         ClearEngineGVs(r.mainTicket);
         r.Reset();
         return;
      }
      if (r.state != TRADE_STATE_NORMAL)
         return;

      // Check if SL was hit
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double slPrice = PositionGetDouble(POSITION_SL);
      double tpPrice = PositionGetDouble(POSITION_TP);
      double curLot = PositionGetDouble(POSITION_VOLUME);
      double atr = atrPoints * _Point;
      double curPrice = (type == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
      double profitATR = (type == POSITION_TYPE_BUY) ? (curPrice - openPrice) / atr : (openPrice - curPrice) / atr;

      bool slHit = false;
      if (slPrice > 0)
      {
         if (type == POSITION_TYPE_BUY && curPrice <= slPrice)
            slHit = true;
         else if (type == POSITION_TYPE_SELL && curPrice >= slPrice)
            slHit = true;
      }

      if (slHit)
      {
         // FIRST: Try to detect and handle fakeout
         if (m_cfgCache.useRecovery && r.recoveryAttempts < m_cfgCache.maxRecoveryAttempts)
         {
            if (DetectAndHandleFakeout(r, tick, atrPoints))
            {
               Log(StringFormat("Position %d: Fakeout detected and handled! SL/TP adjusted. Attempt %d of %d.",
                                r.mainTicket, r.recoveryAttempts, m_cfgCache.maxRecoveryAttempts));
               return;
            }

            // No fakeout detected - enter RECOVERY mode
            r.state = TRADE_STATE_RECOVERY;
            r.slHitPrice = curPrice;
            r.slHitTime = TimeCurrent();
            r.recoveryAttempts++;
            r.recoveryCooldownExpiry = TimeCurrent() + (m_cfgCache.recoveryCooldownBars * PeriodSeconds(_Period));
            r.SaveState(m_cfgCache.magicNum);

            Log(StringFormat("Position %d entered TRADE_STATE_RECOVERY. Attempt %d of %d.",
                             r.mainTicket, r.recoveryAttempts, m_cfgCache.maxRecoveryAttempts));
            DispatchEvent(new RecoveryOpportunityEvent(r.mainTicket, r.slHitPrice, r.direction, atrPoints, r.originalLot));
            return;
         }

         CloseActivePosition(r, "SL Hit - Max recovery attempts");
         return;
      }

      // === PARTIAL CLOSE LOGIC ===
      if (m_cfgCache.usePartialClose && !r.partialClosed && curLot > 0)
      {
         bool touchPartial = (type == POSITION_TYPE_BUY) ? (curPrice >= r.partialTP) : (curPrice <= r.partialTP);
         if (touchPartial && !r.partialArmedNormal)
         {
            r.partialArmedNormal = true;
            r.SaveState(m_cfgCache.magicNum);
         }
         if (r.partialArmedNormal)
         {
            bool recross = (type == POSITION_TYPE_BUY) ? (curPrice <= r.partialTP + atr * 0.1) : (curPrice >= r.partialTP - atr * 0.1);
            if (recross)
            {
               double closeLot = m_data.NormalizeVolume(_Symbol, curLot * m_cfgCache.partialCloseLotPct);

               double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
               if (closeLot >= minVol && closeLot < curLot)
               {
                  if (m_trade.PositionClosePartial(r.mainTicket, closeLot))
                  {
                     r.partialArmedNormal = false;
                     r.partialClosed = true;

                     // Automatic Break-Even after Partial Close
                     double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
                     bool canMoveBE = (type == POSITION_TYPE_BUY) ? (curPrice - openPrice > stopLevel) : (openPrice - curPrice > stopLevel);

                     if (canMoveBE && m_trade.PositionModify(r.mainTicket, openPrice, tpPrice))
                     {
                        if (m_debugMode)
                           PrintFormat("[Recovery] Partial Close Success. SL moved to Break-Even for %d", r.mainTicket);
                     }

                     r.lastActionTick = GetTickCount64();
                     r.SaveState();
                  }
               }
            }
         }
      }

      // === TRAILING STOP LOGIC (Throttled) ===
      if (!m_cfgCache.useTrailing || !r.active)
         return;

      ulong now = GetMicrosecondCount();
      if (now - m_lastTrailingUpdate < (ulong)m_trailingThrottleMs * 1000)
         return;

      m_lastTrailingUpdate = now;

      double newSL = slPrice;
      double stopLevel = MathMax(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
                                 SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL)) *
                         _Point;

      double minModifyStep = atr * 0.12;
      int modifyError = 0;

      if (type == POSITION_TYPE_BUY)
      {
         if (profitATR >= m_cfgCache.lockProfitATR)
            newSL = MathMax(newSL, openPrice + atr * m_cfgCache.lockOffsetATR);
         if (profitATR >= m_cfgCache.trailActivationATR)
            newSL = MathMax(newSL, curPrice - atr * m_cfgCache.trailStepATR);

         if (newSL > slPrice + minModifyStep && (curPrice - newSL) > stopLevel)
         {
            newSL = NormalizeDouble(newSL, _Digits);
            if (m_trade.PositionModify(r.mainTicket, newSL, tpPrice)) // This is fine
            {
               r.SaveState();
               m_lastTrailingUpdate = GetMicrosecondCount();
               if (m_debugMode)
                  PrintFormat("[Recovery] ✓ Trailing BUY %d: SL %.5f (Profit: %.2f ATR)", r.mainTicket, newSL, profitATR);
            }
            else
            {
               modifyError = GetLastError();
               if (m_debugMode)
                  PrintFormat("[Recovery] ✗ Trailing BUY %d failed: Error %d", r.mainTicket, modifyError);
            }
         }
      }
      else
      {
         if (profitATR >= m_cfgCache.lockProfitATR)
         {
            double trailBase = openPrice - atr * m_cfgCache.lockOffsetATR;
            if (newSL == 0 || trailBase < newSL)
               newSL = trailBase;
         }
         if (profitATR >= m_cfgCache.trailActivationATR)
         {
            double dynamicSL = curPrice + atr * m_cfgCache.trailStepATR;
            if (newSL == 0 || dynamicSL < newSL)
               newSL = dynamicSL;
         }
         if (newSL > 0 && (slPrice <= 0 || newSL < slPrice - minModifyStep) && (newSL - curPrice) > stopLevel)
         {
            newSL = NormalizeDouble(newSL, _Digits);
            if (m_trade.PositionModify(r.mainTicket, newSL, tpPrice)) // This is fine
            {
               r.SaveState();
               m_lastTrailingUpdate = GetMicrosecondCount();
               if (m_debugMode)
                  PrintFormat("[Recovery] ✓ Trailing SELL %d: SL %.5f (Profit: %.2f ATR)", r.mainTicket, newSL, profitATR);
            }
            else
            {
               modifyError = GetLastError();
               if (m_debugMode)
                  PrintFormat("[Recovery] ✗ Trailing SELL %d failed: Error %d", r.mainTicket, modifyError);
            }
         }
      }
   }

   // NEW: Process positions in TRADE_STATE_RECOVERY with sophisticated logic
   void ProcessRecovery(RecoveryEngine *r, double atrPoints)
   {
      if (CheckPointer(r) == POINTER_INVALID || r.state != TRADE_STATE_RECOVERY)
         return;

      // Check if recovery cooldown is active
      if (TimeCurrent() < r.recoveryCooldownExpiry)
      {
         int remainingSeconds = (int)(r.recoveryCooldownExpiry - TimeCurrent());
         if (m_debugMode && remainingSeconds % 10 == 0) // Log every 10 seconds
            Log(StringFormat("Position %d in RECOVERY cooldown. Remaining: %d sec", r.mainTicket, remainingSeconds));
         return;
      }

      // Check if max recovery attempts reached
      if (r.recoveryAttempts >= m_cfgCache.maxRecoveryAttempts)
      {
         CloseActivePosition(r, StringFormat("Max recovery attempts reached (%d/%d)",
                                             r.recoveryAttempts, m_cfgCache.maxRecoveryAttempts));
         return;
      }

      // Position is in recovery mode and cooldown is over.
      // SignalManager will listen for RecoveryOpportunityEvent and provide recovery signals.
      // This method just manages state timeouts and validates position still exists.
      if (m_debugMode)
         Log(StringFormat("Position %d ready for recovery signal. Attempts: %d/%d", // Updated
                          r.mainTicket, r.recoveryAttempts, CFG.recovery.maxAttempts)); // Updated
   }

   void VerifyAndCleanupEngines()
   {
      for (int i = ArraySize(engines) - 1; i >= 0; i--)
      {
         RecoveryEngine *r = engines[i];
         if (CheckPointer(r) == POINTER_INVALID || !r.active)
            continue;

         // Process positions in RECOVERY state
         if (r.state == TRADE_STATE_RECOVERY)
         {
            ProcessRecovery(r, m_data.GetATRPoints());
         }

         // Check if position still exists on broker
         if (!PositionSelectByTicket(r.mainTicket))
         {
            if (m_debugMode)
               PrintFormat("[Recovery] Position %d closed externally or no longer exists. Cleaning engine.", r.mainTicket);
            r.active = false;
            ClearEngineGVs(r.mainTicket); // Uses CFG.risk.magic now
            r.Reset();
            continue;
         }

         // Check max trade duration
         if (CFG.risk.maxTradeDurationDays > 0 && r.entryTime > 0)
         {
            if (TimeCurrent() > r.entryTime + (m_cfgCache.maxTradeDurationDays * 86400))
            {
               CloseActivePosition(r, StringFormat("Max trade duration exceeded (%d days)",
                                                   m_cfgCache.maxTradeDurationDays));
               continue;
            }
         }

         // Update peak equity for tracking
         r.peakEquity = MathMax(r.peakEquity, AccountInfoDouble(ACCOUNT_EQUITY));
      }
   }

   //+------------------------------------------------------------------+
   //| PUBLIC: Event Handler Implementation                            |
   //+------------------------------------------------------------------+
public:
   RecoveryManager() : IManager("RecoveryManager", 25)
   {
      m_lastTrailingUpdate = 0;
      m_trailingThrottleMs = 500; // Max 2 trailing updates/sec per engine
      ArrayResize(engines, 0);
   }

   virtual void DeclareEvents() override
   {
      AddEvent(EVENT_ID_PRICE_UPDATE);
      AddEvent(EVENT_ID_ORDER_EXECUTION);
      AddEvent(EVENT_ID_RECOVERY_SIGNAL);
      AddEvent(EVENT_ID_SIGNAL_GENERATED);
   }

   ~RecoveryManager()
   {
      for (int i = ArraySize(engines) - 1; i >= 0; i--)
      {
         if (CheckPointer(engines[i]) == POINTER_DYNAMIC)
         {
            delete engines[i];
            engines[i] = NULL;
         }
      }
      ArrayResize(engines, 0);
   }

   //+------------------------------------------------------------------+
   //| PUBLIC: Event Handler Methods                                   |
   //+------------------------------------------------------------------+
public:
   virtual void OnPriceUpdate(PriceUpdateEvent *e) override
   {
      if (CheckPointer(e) == POINTER_INVALID || ArraySize(engines) == 0 || !m_initialized)
         return;

      double atrPoints = 0;
      if (CheckPointer(m_data) != POINTER_INVALID)
         atrPoints = m_data.GetATRPoints();
      if (atrPoints <= 0)
         return;

      for (int i = 0; i < ArraySize(engines); i++)
      {
         RecoveryEngine *r = engines[i];
         if (CheckPointer(r) != POINTER_INVALID && r.active)
         {
            ProcessTrailingAndPartial(r, e.tick, atrPoints);
         }
      }
   }

   virtual void OnOrderExecution(OrderExecutionEvent *e) override
   {
      if (CheckPointer(e) == POINTER_INVALID || !e.success)
         return;

      // Only register if magic & symbol match
      if (e.orderType != ORDER_TYPE_BUY && e.orderType != ORDER_TYPE_SELL)
         return;
      if (e.ticket > 0)
      {
         Register(e.ticket, e.orderType, e.entryPrice, e.tp, e.sl,
                  0.0, e.volume, 0.0);
      }
   }

   virtual void OnSignalGenerated(SignalGeneratedEvent *e) override
   {
      if (CheckPointer(e) == POINTER_INVALID || !m_cfgCache.exitOnOpposite)
         return;
      CloseOppositePositions(e.signal.orderType);
   }

   // NEW: Handle RecoverySignalEvent from SignalManager
   virtual void OnRecoverySignal(RecoverySignalEvent *e) override
   {
      if (CheckPointer(e) == POINTER_INVALID)
         return;

      RecoveryEngine *r = GetEngine(e.originalTicket);
      if (CheckPointer(r) == POINTER_INVALID || r.state != TRADE_STATE_RECOVERY)
      {
         Log(StringFormat("Received recovery signal for non-recovery/non-existent position %d. Ignoring.", e.originalTicket));
         return;
      }
      // SignalManager has found a re-entry opportunity. ExecutionManager will handle placing the order.
      // We just need to ensure this engine is ready for the new trade to be linked.
      Log(StringFormat("Recovery signal received for original trade %d. Signal: %s", e.originalTicket, e.signal.reason));
   }

   virtual void OnEmergencyStop(EmergencyStopEvent *e) override
   {
      if (CheckPointer(e) == POINTER_INVALID)
         return;
      Log("EMERGENCY STOP triggered: " + e.reason);

      for (int i = ArraySize(engines) - 1; i >= 0; i--)
      {
         RecoveryEngine *r = engines[i];
         if (CheckPointer(r) != POINTER_INVALID)
         {
            if (r.active)
               CloseActivePosition(r, "Emergency: " + e.reason);
            delete r;
            engines[i] = NULL;
         }
      }
      ArrayResize(engines, 0);
   }

   virtual void OnHeartbeat(HeartbeatEvent *e) override
   {
      VerifyAndCleanupEngines();
   }

   virtual void OnConfigReload(ConfigReloadEvent *e) override
   {
      IManager::OnConfigReload(e);
      if (m_debugMode)
         Print("[Recovery] Config cache refreshed.");
   }

   //+------------------------------------------------------------------+
   //| PUBLIC: Integration Methods (Backward Compatible)               |
   //+------------------------------------------------------------------+
public:
   virtual bool Init() override
   {
      if (!IManager::Init())
         return false;
      m_trade.SetExpertMagicNumber(m_cfgCache.magicNum);
      return true;
   }

   RecoveryEngine *GetEngine(ulong ticket)
   {
      int idx = FindEngineIndex(ticket);
      return (idx != -1) ? engines[idx] : NULL;
   }

   void Register(ulong ticket, ENUM_ORDER_TYPE type, double entry, double tp,
                 double brokerSL, double atr, double lot, double zonePrice, double slMult = 1.0)
   {
      // Store original trade details for potential recovery
      double originalEntry = entry;
      double originalSL = brokerSL;
      double originalTP = tp;
      if (FindEngineIndex(ticket) >= 0)
         return;

      int targetIdx = -1;
      int total = ArraySize(engines);
      for (int i = 0; i < total; i++)
      {
         if (CheckPointer(engines[i]) == POINTER_INVALID || !engines[i].active)
         {
            targetIdx = i;
            break;
         }
      }

      if (targetIdx == -1)
      {
         targetIdx = total;
         ArrayResize(engines, total + 1);
         engines[targetIdx] = new RecoveryEngine();
         if (CheckPointer(engines[targetIdx]) == POINTER_INVALID)
         {
            if (m_debugMode)
               PrintFormat("[Recovery] CRITICAL: Failed to allocate engine for %d", ticket);
            ArrayResize(engines, total);
            return;
         }
      }

      RecoveryEngine *target = engines[targetIdx];
      target.Reset();
      target.active = true;
      target.mainTicket = ticket;
      target.direction = (type == ORDER_TYPE_BUY ? 1 : -1);
      target.state = TRADE_STATE_NORMAL;
      target.entryPrice = entry;
      target.initialTP = tp;
      target.brokerSL = brokerSL;
      target.lastKnownATR = (atr > 0) ? atr : m_data.GetATRPoints();
      target.zonePrice = zonePrice;
      target.lot = lot;
      target.slMultiplier = slMult;
      target.peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      target.entryTime = TimeCurrent();

      target.originalEntry = originalEntry;
      target.originalSL = originalSL;
      target.originalTP = originalTP;
      target.originalLot = lot;
      // Partial TP setup
      double pcDist = target.lastKnownATR * CFG.exit.partialATR * _Point;
      target.partialTP = NormalizeDouble(entry + ((type == ORDER_TYPE_BUY ? 1.0 : -1.0) * pcDist), _Digits);
      target.SaveState();

      if (m_debugMode)
         PrintFormat("[Recovery] Registered position %d | Type: %s | Lot: %.2f", ticket, (type == ORDER_TYPE_BUY ? "BUY" : "SELL"), lot);
   }

   void CloseOppositePositions(ENUM_ORDER_TYPE signalType)
   {
      int oppositeDir = (signalType == ORDER_TYPE_BUY) ? -1 : 1;
      for (int i = ArraySize(engines) - 1; i >= 0; i--)
      {
         RecoveryEngine *r = engines[i];
         if (CheckPointer(r) != POINTER_INVALID && r.active && r.direction == oppositeDir)
            CloseActivePosition(r, "Opposite Signal Triggered");
      }
   }

   // Handle notification when a recovery sequence is finished
   void NotifyRecoverySuccess(ulong originalTicket)
   {
      int idx = FindEngineIndex(originalTicket);
      if (idx != -1)
      {
         RecoveryEngine *r = engines[idx];
         r.state = TRADE_STATE_DONE; // This is a state change, not a CFG parameter
         r.active = false; // This is a state change, not a CFG parameter
         ClearEngineGVs(originalTicket); // Uses CFG.risk.magic now
         if (m_debugMode)
            PrintFormat("[Recovery] Original position %d recovery cycle completed.", originalTicket);
      }
   }
};

#endif
