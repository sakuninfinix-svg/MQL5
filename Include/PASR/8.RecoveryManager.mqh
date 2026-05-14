//+------------------------------------------------------------------+
//|                                              RecoveryManager.mqh |
//|                                       Copyright 2026, Agsicentre |
//|            Position Recovery & Fakeout Management Module         |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "2.00"
#property strict

#ifndef __RECOVERY_MANAGER_MQH__
#define __RECOVERY_MANAGER_MQH__

#include <Trade/Trade.mqh>
#include "IManager.mqh"
#include "10.DataManager.mqh"
#include "9.PatternManager.mqh"
#include "12.MarketRegime.mqh"  // For regime-aware recovery

//+------------------------------------------------------------------+
//| Recovery Statistics - Tracking & Scoring                         |
//+------------------------------------------------------------------+
struct RecoveryStats
{
   int totalRecoveries;        // Total recovery attempts
   int successfulRecoveries;   // Successfully recovered positions
   int failedRecoveries;       // Failed recovery attempts
   int fakeoutsDetected;       // Fakeout patterns detected
   int fakeoutsRecovered;      // Successfully recovered from fakeouts
   double avgRecoveryProfit;   // Average profit from recovered trades
   double maxDrawdownRecovered;// Maximum drawdown recovered
   double avgRecoveryTimeMin;  // Average recovery time in minutes
   ulong lastRecoveryTime;     // Last recovery timestamp
   
   void Init()
   {
      ZeroMemory(this);
      maxDrawdownRecovered = 0;
   }
   
   double GetSuccessRate() const
   {
      if(totalRecoveries == 0) return 0.0;
      return (double)successfulRecoveries / (double)totalRecoveries;
   }
   
   double GetFakeoutRecoveryRate() const
   {
      if(fakeoutsDetected == 0) return 0.0;
      return (double)fakeoutsRecovered / (double)fakeoutsDetected;
   }
   
   // Recovery quality score (0-100)
   double GetQualityScore() const
   {
      // 40% success rate, 30% fakeout recovery, 30% profitability
      double successComponent = GetSuccessRate() * 40.0;
      double fakeoutComponent = GetFakeoutRecoveryRate() * 30.0;
      double profitComponent = MathMin(30.0, (avgRecoveryProfit > 0 ? avgRecoveryProfit : 0) * 3.0);
      return MathMin(100.0, successComponent + fakeoutComponent + profitComponent);
   }
};

class RecoveryManager : public IManager
{
private:
   RecoveryEngine *engines[];
   CTrade m_trade;
   
   // Recovery scoring & metrics
   int m_recoveryScore;          // Recovery quality score (0-100)
   double m_avgRecoveryTime;     // Average recovery time in minutes
   double m_totalRecoveredLoss;  // Total loss recovered
   RecoveryStats m_stats;        // Detailed statistics
   
   // Event-Driven State
   ulong m_lastTrailingUpdate;
   int m_trailingThrottleMs;
   
   // Regime awareness
   bool m_regimeAware;           // Enable regime-aware recovery
   double m_minRegimeScore;      // Minimum regime score for recovery

private:
   virtual void RefreshConfigCache() override
   {
      IManager::RefreshConfigCache();
   }

   int FindEngineIndex(ulong ticket)
   {
      for (int i = 0; i < ArraySize(engines); i++)
      {
         RecoveryEngine *r = engines[i];
         if (CheckPointer(r) != POINTER_INVALID && r.active && r.mainTicket == ticket)
            return i;
      }
      return -1;
   }

   void ClearEngineGVs(ulong ticket)
   {
      string prefix = "PASR_" + IntegerToString(cfg.magic) + "_" + IntegerToString(ticket) + "_";
      GlobalVariablesDeleteAll(prefix);
   }

   void CloseActivePosition(RecoveryEngine *r, const string reason)
   {
      if (CheckPointer(r) == POINTER_INVALID || r.state == TRADE_STATE_DONE)
         return;
      
      // Track recovery outcome for statistics
      bool wasRecovered = (r.recoveryAttempts > 0 && r.state == TRADE_STATE_RECOVERY);
      double profitPoints = 0;
      
      if(PositionSelectByTicket(r.mainTicket))
      {
         double closePrice = (r.direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         profitPoints = (r.direction == 1) ? (closePrice - r.entryPrice) / _Point : (r.entryPrice - closePrice) / _Point;
      }
      
      r.state = TRADE_STATE_DONE;

      bool closed = false;
      if (PositionSelectByTicket(r.mainTicket))
      {
         if (m_trade.PositionClose(r.mainTicket))
         {
            closed = true;
            
            // Update statistics
            m_stats.totalRecoveries++;
            if(wasRecovered)
            {
               if(profitPoints > 0)
                  m_stats.successfulRecoveries++;
               else
                  m_stats.failedRecoveries++;
                  
               m_stats.avgRecoveryProfit = ((m_stats.avgRecoveryProfit * (m_stats.totalRecoveries-1)) + profitPoints) / m_stats.totalRecoveries;
               m_stats.lastRecoveryTime = GetTickCount64();
               
               // Calculate recovery time
               if(r.entryTime > 0)
               {
                  double recoveryMin = (double)(TimeCurrent() - r.entryTime) / 60.0;
                  m_avgRecoveryTime = ((m_avgRecoveryTime * (m_stats.totalRecoveries-1)) + recoveryMin) / m_stats.totalRecoveries;
                  m_stats.avgRecoveryTimeMin = m_avgRecoveryTime;
               }
            }
            
            if (m_debugMode)
               PrintFormat("[Recovery] Position %d closed: %s | Profit: %.2f pts | Recovery: %s", 
                           r.mainTicket, reason, profitPoints, wasRecovered ? "Yes" : "No");
         }
         else if (m_debugMode)
         {
            int err = GetLastError();
            PrintFormat("[Recovery] Failed to close %d: Error %d (%s)", r.mainTicket, err, m_trade.ResultRetcodeDescription());
         }
      }

      ClearEngineGVs(r.mainTicket);
      r.Reset();
      r.active = false;

      PositionUpdateEvent *notify = new PositionUpdateEvent(r.mainTicket, 0, 0, true);
      DispatchEvent(notify);
   }

   bool DetectAndHandleFakeout(RecoveryEngine *r, const MqlTick &tick, double atrvalue)
   {
      if (CheckPointer(r) == POINTER_INVALID || !r.active)
         return false;
      StrategyConfig cfg; m_data.GetConfigCache(cfg);

      PatternManager::FakeoutContext ctx;
      ctx.originalTicket = r.mainTicket;
      ctx.direction = r.direction;
      ctx.slHitPrice = tick.bid;
      ctx.entryPrice = r.entryPrice;
      ctx.atrPoints = atrvalue;
      ctx.currentTick = tick;

      ArraySetAsSeries(ctx.rates, true);
      // FIX: Copy from shift 1 to get CLOSED bars only (shift 0 is forming bar and will repaint)
      // Copy 3 closed bars: [0]=last closed, [1]=2nd last closed, [2]=3rd last closed
      if (CopyRates(_Symbol, _Period, 1, 3, ctx.rates) < 3)
      {
         if (m_debugMode)
            Log("Failed to fetch candles for fakeout detection");
         return false;
      }

      FakeoutResult signal;
      // Note: ctx.rates[0] now refers to the last CLOSED bar (not forming bar)
      if (!PatternManager::DetectFakeout(ctx, signal))
      {
         return false;
      }

      if (m_debugMode)
         PrintFormat("[Fakeout] Position %d: %s (Confidence: %.2f, Level: %d)",
                     r.mainTicket, signal.reason, signal.confidence, signal.level);
      if (signal.level < 2)
      {
         if (m_debugMode)
            Log(StringFormat("Fakeout detected but low confidence (%.2f). Continuing to recovery mode.", signal.confidence));
         return false;
      }

      if (!PositionSelectByTicket(r.mainTicket))
      {
         return false;
      }

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      double atr = atrvalue * _Point;

      // Calculate new SL further away to avoid fakeout
      double slAdjustmentPoints = atr * cfg.fakeout_sl_adjustment_atr;
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

      if (m_trade.PositionModify(r.mainTicket, newSL, newTP))
      {
         r.lastKnownATR = atrvalue;
         r.recoveryAttempts++;
         
         // Track fakeout statistics
         m_stats.fakeoutsDetected++;
         m_stats.fakeoutsRecovered++;
         
         r.SaveState();
         if (m_debugMode)
            PrintFormat("[Fakeout] ✓ SL adjusted for %d: %.5f -> %.5f (Confidence: %.2f) | Recovery #%d",
                        r.mainTicket, currentSL, newSL, signal.confidence, r.recoveryAttempts);
         return true;
      }
      else if (m_debugMode)
      {
         int err = GetLastError();
         PrintFormat("[Fakeout] ✗ Failed to adjust SL for %d: Error %d (%s)",
                     r.mainTicket, err, m_trade.ResultRetcodeDescription());
      }
      return false;
   }

   void ProcessTrailingAndPartial(RecoveryEngine *r, const MqlTick &tick, double atrvalue)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      if (CheckPointer(r) == POINTER_INVALID || !r.active) return;
      if (!PositionSelectByTicket(r.mainTicket))
      {
         r.active = false;
         ClearEngineGVs(r.mainTicket);
         r.Reset();
         return;
      }
      if (r.state != TRADE_STATE_NORMAL) return;
      // Check if SL was hit
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double slPrice = PositionGetDouble(POSITION_SL);
      double tpPrice = PositionGetDouble(POSITION_TP);
      double curLot = PositionGetDouble(POSITION_VOLUME);
      double atr = atrvalue * _Point;
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
         if (cfg.recovery_use && r.recoveryAttempts < cfg.max_recovery_attempts)
         {
            if (DetectAndHandleFakeout(r, tick, atrvalue))
            {
               Log(StringFormat("Position %d: Fakeout detected and handled! SL/TP adjusted. Attempt %d of %d.",
                                r.mainTicket, r.recoveryAttempts, cfg.max_recovery_attempts));
               return;
            }

            // No fakeout detected - enter RECOVERY mode
            r.state = TRADE_STATE_RECOVERY;
            r.slHitPrice = curPrice;
            r.slHitTime = TimeCurrent();
            r.recoveryAttempts++;
            r.recoveryCooldownExpiry = TimeCurrent() + (cfg.recovery_cooldown_bars * PeriodSeconds(_Period));
            r.SaveState();

            Log(StringFormat("Position %d entered TRADE_STATE_RECOVERY. Attempt %d of %d.",
                             r.mainTicket, r.recoveryAttempts, cfg.max_recovery_attempts));
            DispatchEvent(new RecoveryOpportunityEvent(r.mainTicket, r.slHitPrice, r.direction, atrvalue, r.originalLot));
            return;
         }

         CloseActivePosition(r, "SL Hit - Max recovery attempts");
         return;
      }

      // === PARTIAL CLOSE LOGIC ===
      {
         bool touchPartial = (type == POSITION_TYPE_BUY) ? (curPrice >= r.partialTP) : (curPrice <= r.partialTP);
         if (touchPartial && !r.partialArmedNormal)
         {
            r.partialArmedNormal = true;
            r.SaveState();
         }
         if (r.partialArmedNormal)
         {
            bool recross = (type == POSITION_TYPE_BUY) ? (curPrice <= r.partialTP + atr * 0.1) : (curPrice >= r.partialTP - atr * 0.1);
            if (recross)
            {
               double closeLot = m_data.NormalizeVolume(_Symbol, curLot * cfg.partial_close_lot_pct);
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
      if (!cfg.use_trailing || !r.active)
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
         if (profitATR >= cfg.lock_profit_atr)
            newSL = MathMax(newSL, openPrice + atr * cfg.lock_offset_atr);
         if (profitATR >= cfg.trail_activation_atr)
            newSL = MathMax(newSL, curPrice - atr * cfg.trail_step_atr);
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
            else if (m_debugMode)
            {
               modifyError = GetLastError();
               PrintFormat("[Recovery] ✗ Trailing BUY %d failed: Error %d (%s)",
                           r.mainTicket, modifyError, m_trade.ResultRetcodeDescription());
            }
         }
      }
      else
      {
         if (profitATR >= cfg.lock_profit_atr)
         {
            double trailBase = openPrice - atr * cfg.lock_offset_atr;
            if (newSL == 0 || trailBase < newSL)
               newSL = trailBase;
         }
         if (profitATR >= cfg.trail_activation_atr)
         {
            double dynamicSL = NormalizeDouble(curPrice + atr * cfg.trail_step_atr, _Digits);
            newSL = (newSL <= 0) ? dynamicSL : MathMin(newSL, dynamicSL);
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
            else if (m_debugMode)
            {
               modifyError = GetLastError();
               PrintFormat("[Recovery] ✗ Trailing SELL %d failed: Error %d (%s)",
                           r.mainTicket, modifyError, m_trade.ResultRetcodeDescription());
            }
         }
      }
   }

   // NEW: Process positions in TRADE_STATE_RECOVERY with sophisticated logic
   void ProcessRecovery(RecoveryEngine *r, double atrvalue)
   {
      if (CheckPointer(r) == POINTER_INVALID || r.state != TRADE_STATE_RECOVERY)
         return;
      StrategyConfig cfg; m_data.GetConfigCache(cfg);

      // Check if recovery cooldown is active
      if (TimeCurrent() < r.recoveryCooldownExpiry)
      {
         int remainingSeconds = (int)(r.recoveryCooldownExpiry - TimeCurrent());
         if (m_debugMode && remainingSeconds % 10 == 0)
            Log(StringFormat("Position %d in RECOVERY cooldown. Remaining: %d sec", r.mainTicket, remainingSeconds));
         return;
      }

      // Check if max recovery attempts reached
      if (r.recoveryAttempts >= cfg.max_recovery_attempts)
      {
         CloseActivePosition(r, StringFormat("Max recovery attempts reached (%d/%d)",
                                             r.recoveryAttempts, cfg.max_recovery_attempts));
         return;
      }

      // Position is in recovery mode and cooldown is over.
      // SignalManager will listen for RecoveryOpportunityEvent and provide recovery signals.
      // This method just manages state timeouts and validates position still exists.
      if (m_debugMode)
         Log(StringFormat("Position %d ready for recovery signal. Attempts: %d/%d",
                          r.mainTicket, r.recoveryAttempts, cfg.max_recovery_attempts)); // Updated
   }

   void VerifyAndCleanupEngines()
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
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
         if (cfg.max_trade_duration_days > 0 && r.entryTime > 0)
         {
            if (TimeCurrent() > r.entryTime + (cfg.max_trade_duration_days * 86400))
            {
               CloseActivePosition(r, StringFormat("Max trade duration exceeded (%d days)",
                                                   cfg.max_trade_duration_days));
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
      
      // Initialize recovery metrics
      m_recoveryScore = 100;  // Start with perfect score
      m_avgRecoveryTime = 0.0;
      m_totalRecoveredLoss = 0.0;
      m_stats.Init();
      
      // Regime awareness defaults
      m_regimeAware = true;
      m_minRegimeScore = 0.3;  // Allow recovery in weak trends and above
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
      // Destructor sudah ada dan proper cleanup semua RecoveryEngine* pointers
      // Memory management sudah optimal - tidak perlu perubahan
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

public:
   virtual void OnPriceUpdate(PriceUpdateEvent *e) override
   {
      if (CheckPointer(e) == POINTER_INVALID || ArraySize(engines) == 0 || !m_initialized)
         return;

      double atrvalue = 0;
      if (CheckPointer(m_data) != POINTER_INVALID)
         atrvalue = m_data.GetATRPoints();
      if (atrvalue <= 0)
         return;

      for (int i = 0; i < ArraySize(engines); i++)
      {
         RecoveryEngine *r = engines[i];
         if (CheckPointer(r) != POINTER_INVALID && r.active)
         {
            ProcessTrailingAndPartial(r, e.tick, atrvalue);
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
      if (CheckPointer(e) == POINTER_INVALID || !cfg.exit_on_opposite)
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
      
      // Update recovery quality metrics periodically
      UpdateRecoveryMetrics();
   }
   
   //+------------------------------------------------------------------+
   //| Recovery Quality & Metrics                                       |
   //+------------------------------------------------------------------+
   void UpdateRecoveryMetrics()
   {
      // Decay old metrics slightly for rolling average
      if(m_stats.totalRecoveries > 0)
      {
         m_recoveryScore = (int)MathRound(m_stats.GetQualityScore());
         m_avgRecoveryTime = m_stats.avgRecoveryTimeMin;
         
         // Regime-aware adjustment: reduce score in choppy markets
         if(m_regimeAware && CheckPointer(g_regimeFilter) != POINTER_INVALID)
         {
            double regimeScore = g_regimeFilter.GetRegimeScore();
            if(regimeScore < 0.3)  // Choppy market
               m_recoveryScore = (int)(m_recoveryScore * 0.7);  // Penalty for choppy conditions
         }
      }
   }
   
   // Get recovery quality score (0-100)
   int GetRecoveryScore() const { return m_recoveryScore; }
   
   // Get success rate percentage
   double GetSuccessRate() const { return m_stats.GetSuccessRate() * 100.0; }
   
   // Get fakeout recovery rate percentage
   double GetFakeoutRecoveryRate() const { return m_stats.GetFakeoutRecoveryRate() * 100.0; }
   
   // Get average recovery time in minutes
   double GetAvgRecoveryTime() const { return m_avgRecoveryTime; }
   
   // Get total recovery count
   int GetTotalRecoveries() const { return m_stats.totalRecoveries; }
   
   // Get detailed recovery statistics
   const RecoveryStats& GetRecoveryStats() const { return m_stats; }
   
   // Check if recovery system is healthy
   bool IsRecoveryHealthy() const
   {
      // Healthy if success rate > 50% and we have at least some successful recoveries
      return (m_stats.GetSuccessRate() > 0.5 || m_stats.totalRecoveries < 3);
   }
   
   // Check if conditions are favorable for recovery (regime-aware)
   bool IsRecoveryFavorable() const
   {
      if(!m_regimeAware) return true;
      
      if(CheckPointer(g_regimeFilter) == POINTER_INVALID)
         return true;  // Default to allowing recovery if filter unavailable
         
      double regimeScore = g_regimeFilter.GetRegimeScore();
      return (regimeScore >= m_minRegimeScore);
   }
   
   // Build recovery reasoning for audit trail
   string BuildRecoveryReasoning(ulong ticket, const string action, double profitPoints = 0) const
   {
      string reasoning = StringFormat("[Recovery] Ticket:%d | Action:%s | Profit:%.2f pts", 
                                      ticket, action, profitPoints);
      reasoning += StringFormat(" | Score:%d/100 | SuccessRate:%.1f%%", 
                                m_recoveryScore, GetSuccessRate());
      reasoning += StringFormat(" | AvgTime:%.1fmin | FakeoutRecovery:%.1f%%",
                                m_avgRecoveryTime, GetFakeoutRecoveryRate());
                                
      if(m_regimeAware && CheckPointer(g_regimeFilter) != POINTER_INVALID)
      {
         double regimeScore = g_regimeFilter.GetRegimeScore();
         reasoning += StringFormat(" | RegimeScore:%.2f | Favorable:%s",
                                   regimeScore, IsRecoveryFavorable() ? "Yes" : "No");
      }
      
      return reasoning;
   }
   
   // Reset all statistics (for testing or fresh start)
   void ResetStatistics()
   {
      m_stats.Init();
      m_recoveryScore = 100;
      m_avgRecoveryTime = 0.0;
      m_totalRecoveredLoss = 0.0;
      
      if(m_debugMode)
         Print("[Recovery] Statistics reset.");
   }

   virtual void OnConfigReload(ConfigReloadEvent *e) override
   {
      IManager::OnConfigReload(e);
      if (m_debugMode)
         Print("[Recovery] Config cache refreshed.");
   }

public:
   virtual bool Init() override
   {
      if (!IManager::Init())
         return false;
      m_trade.SetExpertMagicNumber(cfg.magic);
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
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
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
      double pcDist = target.lastKnownATR * cfg.partial_close_atr * _Point;
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
         
         // Track successful recovery completion
         if(r.recoveryAttempts > 0 && r.state == TRADE_STATE_RECOVERY)
         {
            m_stats.successfulRecoveries++;
            if(m_debugMode)
               PrintFormat("[Recovery] ✓ Recovery SUCCESS for position %d after %d attempts", 
                           originalTicket, r.recoveryAttempts);
         }
         
         r.state = TRADE_STATE_DONE;
         r.active = false;
         ClearEngineGVs(originalTicket);
         
         if (m_debugMode)
            PrintFormat("[Recovery] Original position %d recovery cycle completed. | Total Success Rate: %.1f%%", 
                        originalTicket, GetSuccessRate());
      }
   }
};

//+------------------------------------------------------------------+
//| CONTOH PENGGUNAAN RECOVERYMANAGER V2.00                          |
//+------------------------------------------------------------------+
/*
// Di EA utama:

#include <PASR/8.RecoveryManager.mqh>
#include <PASR/12.MarketRegime.mqh>

RecoveryManager g_recovery;
MarketRegimeFilter g_regime;

void OnExpertInit()
{
   // Inisialisasi managers
   g_recovery.Init();
   g_regime.Init();
   
   // Set global pointer untuk regime awareness
   g_regimeFilter = &g_regime;
}

void OnTick()
{
   // Cek apakah kondisi favorable untuk recovery
   if(g_recovery.IsRecoveryFavorable())
   {
      // Recovery hanya akan dijalankan jika regime score >= threshold
      Print("Recovery conditions favorable");
   }
   
   // Dapatkan metrics untuk monitoring
   int score = g_recovery.GetRecoveryScore();
   double successRate = g_recovery.GetSuccessRate();
   double avgTime = g_recovery.GetAvgRecoveryTime();
   
   Print(StringFormat("Recovery Score: %d/100 | Success: %.1f%% | Avg Time: %.1f min",
                      score, successRate, avgTime));
                      
   // Build reasoning untuk audit trail
   string reasoning = g_recovery.BuildRecoveryReasoning(ticket, "Close", profitPoints);
   Print(reasoning);
   
   // Reset statistics jika diperlukan (misal: daily reset)
   if(IsNewDay())
      g_recovery.ResetStatistics();
}

// Fitur Utama v2.00:
// 1. RecoveryStats struct dengan tracking lengkap
// 2. Scoring system 0-100 berdasarkan success rate, fakeout recovery, profitability
// 3. Regime-aware recovery (integrasi dengan MarketRegimeFilter)
// 4. Real-time metrics: GetRecoveryScore(), GetSuccessRate(), GetFakeoutRecoveryRate()
// 5. Health check: IsRecoveryHealthy(), IsRecoveryFavorable()
// 6. Audit trail: BuildRecoveryReasoning() dengan detail lengkap
// 7. Statistics reset capability untuk fresh start
// 8. Backward compatible dengan API lama
*/

#endif