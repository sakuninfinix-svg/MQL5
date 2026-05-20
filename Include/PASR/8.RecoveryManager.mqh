//+------------------------------------------------------------------+
//|                                              RecoveryManager.mqh |
//|                                       Copyright 2026, Agsicentre |
//|            Position Recovery & Fakeout Management Module         |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "2.01"
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
   int totalRecoveries;
   int successfulRecoveries;
   int failedRecoveries;
   int fakeoutsDetected;
   int fakeoutsRecovered;
   double avgRecoveryProfit;
   double maxDrawdownRecovered;
   double avgRecoveryTimeMin;
   ulong lastRecoveryTime;

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

   double GetQualityScore() const
   {
      double successComponent = GetSuccessRate() * 40.0;
      double fakeoutComponent = GetFakeoutRecoveryRate() * 30.0;
      double profitComponent  = MathMin(30.0, (avgRecoveryProfit > 0 ? avgRecoveryProfit : 0) * 3.0);
      return MathMin(100.0, successComponent + fakeoutComponent + profitComponent);
   }
};

class RecoveryManager : public IManager
{
private:
   RecoveryEngine *engines[];
   CTrade m_trade;

   int    m_recoveryScore;
   double m_avgRecoveryTime;
   double m_totalRecoveredLoss;
   RecoveryStats m_stats;

   ulong m_lastTrailingUpdate;
   int   m_trailingThrottleMs;

   bool   m_regimeAware;
   double m_minRegimeScore;

private:
   virtual void RefreshConfigCache() override
   {
      IManager::RefreshConfigCache();
   }

   int FindEngineIndex(ulong ticket)
   {
      for(int i = 0; i < ArraySize(engines); i++)
      {
         RecoveryEngine *r = engines[i];
         if(CheckPointer(r) != POINTER_INVALID && r.active && r.mainTicket == ticket)
            return i;
      }
      return -1;
   }

   // FIX (RM-BUG-1): Replace GlobalVariablesDeleteAll(prefix) with per-key loop.
   // GlobalVariablesDeleteAll deletes ALL global variables matching prefix — including
   // variables owned by other EA instances or other symbols on the same broker account.
   // Per-key deletion is safe and matches the pattern fixed in ConfigManager CM-BUG-3.
   void ClearEngineGVs(ulong ticket)
   {
      string prefix = "PASR_" + IntegerToString(cfg.magic) + "_" + IntegerToString(ticket) + "_";
      // Enumerate and delete only keys with this exact prefix
      string varName;
      for(int i = GlobalVariablesTotal() - 1; i >= 0; i--)
      {
         varName = GlobalVariableName(i);
         if(StringFind(varName, prefix) == 0)
            GlobalVariableDel(varName);
      }
   }

   void CloseActivePosition(RecoveryEngine *r, const string reason)
   {
      if(CheckPointer(r) == POINTER_INVALID || r.state == TRADE_STATE_DONE)
         return;

      bool   wasRecovered  = (r.recoveryAttempts > 0 && r.state == TRADE_STATE_RECOVERY);
      double profitPoints  = 0;

      if(PositionSelectByTicket(r.mainTicket))
      {
         double closePrice = (r.direction == 1)
            ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
            : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         profitPoints = (r.direction == 1)
            ? (closePrice - r.entryPrice) / _Point
            : (r.entryPrice - closePrice) / _Point;
      }

      r.state = TRADE_STATE_DONE;

      if(PositionSelectByTicket(r.mainTicket))
      {
         if(m_trade.PositionClose(r.mainTicket))
         {
            m_stats.totalRecoveries++;
            if(wasRecovered)
            {
               if(profitPoints > 0)
                  m_stats.successfulRecoveries++;
               else
                  m_stats.failedRecoveries++;

               m_stats.avgRecoveryProfit =
                  ((m_stats.avgRecoveryProfit * (m_stats.totalRecoveries - 1)) + profitPoints)
                  / m_stats.totalRecoveries;
               m_stats.lastRecoveryTime = GetTickCount64();

               if(r.entryTime > 0)
               {
                  double recoveryMin = (double)(TimeCurrent() - r.entryTime) / 60.0;
                  m_avgRecoveryTime =
                     ((m_avgRecoveryTime * (m_stats.totalRecoveries - 1)) + recoveryMin)
                     / m_stats.totalRecoveries;
                  m_stats.avgRecoveryTimeMin = m_avgRecoveryTime;
               }
            }

            if(m_debugMode)
               PrintFormat("[Recovery] Position %d closed: %s | Profit: %.2f pts | Recovery: %s",
                           r.mainTicket, reason, profitPoints, wasRecovered ? "Yes" : "No");
         }
         else if(m_debugMode)
         {
            int err = GetLastError();
            PrintFormat("[Recovery] Failed to close %d: Error %d (%s)",
                        r.mainTicket, err, m_trade.ResultRetcodeDescription());
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
      if(CheckPointer(r) == POINTER_INVALID || !r.active)
         return false;
      StrategyConfig cfg; m_data.GetConfigCache(cfg);

      PatternManager::FakeoutContext ctx;
      ctx.originalTicket = r.mainTicket;
      ctx.direction      = r.direction;
      ctx.slHitPrice     = tick.bid;
      ctx.entryPrice     = r.entryPrice;
      ctx.atrPoints      = atrvalue;
      ctx.currentTick    = tick;

      ArraySetAsSeries(ctx.rates, true);
      if(CopyRates(_Symbol, _Period, 1, 3, ctx.rates) < 3)
      {
         if(m_debugMode) Log("Failed to fetch candles for fakeout detection");
         return false;
      }

      FakeoutResult signal;
      if(!PatternManager::DetectFakeout(ctx, signal))
         return false;

      if(m_debugMode)
         PrintFormat("[Fakeout] Position %d: %s (Confidence: %.2f, Level: %d)",
                     r.mainTicket, signal.reason, signal.confidence, signal.level);
      if(signal.level < 2)
      {
         if(m_debugMode)
            Log(StringFormat("Fakeout detected but low confidence (%.2f). Continuing to recovery mode.",
                             signal.confidence));
         return false;
      }

      if(!PositionSelectByTicket(r.mainTicket))
         return false;

      ENUM_POSITION_TYPE type      = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double             currentSL = PositionGetDouble(POSITION_SL);
      double             currentTP = PositionGetDouble(POSITION_TP);
      double             atr       = atrvalue * _Point;

      double slAdjustmentPoints = atr * cfg.fakeout_sl_adjustment_atr;
      double newSL              = 0;
      double newTP              = currentTP;

      if(type == POSITION_TYPE_BUY)
         newSL = NormalizeDouble(currentSL - slAdjustmentPoints, _Digits);
      else
         newSL = NormalizeDouble(currentSL + slAdjustmentPoints, _Digits);

      double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      double curPrice  = (type == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
      bool   slValid   = (type == POSITION_TYPE_BUY)
         ? (curPrice - newSL) > stopLevel
         : (newSL - curPrice) > stopLevel;

      if(!slValid)
      {
         if(m_debugMode) PrintFormat("[Fakeout] Cannot adjust SL: Too close to current price");
         return false;
      }

      if(m_trade.PositionModify(r.mainTicket, newSL, newTP))
      {
         r.lastKnownATR = atrvalue;
         r.recoveryAttempts++;
         m_stats.fakeoutsDetected++;
         m_stats.fakeoutsRecovered++;
         r.SaveState();
         if(m_debugMode)
            PrintFormat("[Fakeout] OK SL adjusted for %d: %.5f -> %.5f (Confidence: %.2f) | Recovery #%d",
                        r.mainTicket, currentSL, newSL, signal.confidence, r.recoveryAttempts);
         return true;
      }
      else if(m_debugMode)
      {
         int err = GetLastError();
         PrintFormat("[Fakeout] FAIL to adjust SL for %d: Error %d (%s)",
                     r.mainTicket, err, m_trade.ResultRetcodeDescription());
      }
      return false;
   }

   void ProcessTrailingAndPartial(RecoveryEngine *r, const MqlTick &tick, double atrvalue)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      if(CheckPointer(r) == POINTER_INVALID || !r.active) return;
      if(!PositionSelectByTicket(r.mainTicket))
      {
         r.active = false;
         ClearEngineGVs(r.mainTicket);
         r.Reset();
         return;
      }
      if(r.state != TRADE_STATE_NORMAL) return;

      ENUM_POSITION_TYPE type      = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double             openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double             slPrice   = PositionGetDouble(POSITION_SL);
      double             tpPrice   = PositionGetDouble(POSITION_TP);
      double             curLot    = PositionGetDouble(POSITION_VOLUME);
      double             atr       = atrvalue * _Point;
      double             curPrice  = (type == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
      double             profitATR = (type == POSITION_TYPE_BUY)
         ? (curPrice - openPrice) / atr
         : (openPrice - curPrice) / atr;

      bool slHit = false;
      if(slPrice > 0)
      {
         if(type == POSITION_TYPE_BUY  && curPrice <= slPrice) slHit = true;
         if(type == POSITION_TYPE_SELL && curPrice >= slPrice) slHit = true;
      }

      if(slHit)
      {
         if(cfg.recovery_use && r.recoveryAttempts < cfg.max_recovery_attempts)
         {
            if(DetectAndHandleFakeout(r, tick, atrvalue))
            {
               Log(StringFormat("Position %d: Fakeout detected and handled! SL/TP adjusted. Attempt %d of %d.",
                                r.mainTicket, r.recoveryAttempts, cfg.max_recovery_attempts));
               return;
            }

            r.state                  = TRADE_STATE_RECOVERY;
            r.slHitPrice             = curPrice;
            r.slHitTime              = TimeCurrent();
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

      // === PARTIAL CLOSE ===
      {
         bool touchPartial = (type == POSITION_TYPE_BUY)
            ? (curPrice >= r.partialTP)
            : (curPrice <= r.partialTP);
         if(touchPartial && !r.partialArmedNormal)
         {
            r.partialArmedNormal = true;
            r.SaveState();
         }
         if(r.partialArmedNormal)
         {
            bool recross = (type == POSITION_TYPE_BUY)
               ? (curPrice <= r.partialTP + atr * 0.1)
               : (curPrice >= r.partialTP - atr * 0.1);
            if(recross)
            {
               double closeLot = m_data.NormalizeVolume(_Symbol, curLot * cfg.partial_close_lot_pct);
               double minVol   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
               if(closeLot >= minVol && closeLot < curLot)
               {
                  if(m_trade.PositionClosePartial(r.mainTicket, closeLot))
                  {
                     r.partialArmedNormal = false;
                     r.partialClosed      = true;

                     double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
                     bool   canMoveBE = (type == POSITION_TYPE_BUY)
                        ? (curPrice - openPrice > stopLevel)
                        : (openPrice - curPrice > stopLevel);

                     if(canMoveBE && m_trade.PositionModify(r.mainTicket, openPrice, tpPrice))
                     {
                        if(m_debugMode)
                           PrintFormat("[Recovery] Partial Close OK. SL moved to Break-Even for %d", r.mainTicket);
                     }

                     r.lastActionTick = GetTickCount64();
                     r.SaveState();
                  }
               }
            }
         }
      }

      // === TRAILING STOP (throttled) ===
      if(!cfg.use_trailing || !r.active) return;

      ulong now = GetMicrosecondCount();
      if(now - m_lastTrailingUpdate < (ulong)m_trailingThrottleMs * 1000)
         return;

      m_lastTrailingUpdate = now;

      double newSL = slPrice;
      double stopLevel = MathMax(
         SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
         SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL)) * _Point;

      double minModifyStep = atr * 0.12;
      int    modifyError   = 0;

      if(type == POSITION_TYPE_BUY)
      {
         if(profitATR >= cfg.lock_profit_atr)
            newSL = MathMax(newSL, openPrice + atr * cfg.lock_offset_atr);
         if(profitATR >= cfg.trail_activation_atr)
            newSL = MathMax(newSL, curPrice - atr * cfg.trail_step_atr);
         if(newSL > slPrice + minModifyStep && (curPrice - newSL) > stopLevel)
         {
            newSL = NormalizeDouble(newSL, _Digits);
            if(m_trade.PositionModify(r.mainTicket, newSL, tpPrice))
            {
               r.SaveState();
               m_lastTrailingUpdate = GetMicrosecondCount();
               if(m_debugMode)
                  PrintFormat("[Recovery] Trailing BUY %d: SL %.5f (Profit: %.2f ATR)", r.mainTicket, newSL, profitATR);
            }
            else if(m_debugMode)
            {
               modifyError = GetLastError();
               PrintFormat("[Recovery] Trailing BUY %d failed: Error %d (%s)",
                           r.mainTicket, modifyError, m_trade.ResultRetcodeDescription());
            }
         }
      }
      else
      {
         if(profitATR >= cfg.lock_profit_atr)
         {
            double trailBase = openPrice - atr * cfg.lock_offset_atr;
            if(newSL == 0 || trailBase < newSL) newSL = trailBase;
         }
         if(profitATR >= cfg.trail_activation_atr)
         {
            double dynamicSL = NormalizeDouble(curPrice + atr * cfg.trail_step_atr, _Digits);
            newSL = (newSL <= 0) ? dynamicSL : MathMin(newSL, dynamicSL);
         }
         if(newSL > 0 && (slPrice <= 0 || newSL < slPrice - minModifyStep) && (newSL - curPrice) > stopLevel)
         {
            newSL = NormalizeDouble(newSL, _Digits);
            if(m_trade.PositionModify(r.mainTicket, newSL, tpPrice))
            {
               r.SaveState();
               m_lastTrailingUpdate = GetMicrosecondCount();
               if(m_debugMode)
                  PrintFormat("[Recovery] Trailing SELL %d: SL %.5f (Profit: %.2f ATR)", r.mainTicket, newSL, profitATR);
            }
            else if(m_debugMode)
            {
               modifyError = GetLastError();
               PrintFormat("[Recovery] Trailing SELL %d failed: Error %d (%s)",
                           r.mainTicket, modifyError, m_trade.ResultRetcodeDescription());
            }
         }
      }
   }

   void ProcessRecovery(RecoveryEngine *r, double atrvalue)
   {
      if(CheckPointer(r) == POINTER_INVALID || r.state != TRADE_STATE_RECOVERY)
         return;
      StrategyConfig cfg; m_data.GetConfigCache(cfg);

      if(TimeCurrent() < r.recoveryCooldownExpiry)
      {
         int remainingSeconds = (int)(r.recoveryCooldownExpiry - TimeCurrent());
         if(m_debugMode && remainingSeconds % 10 == 0)
            Log(StringFormat("Position %d in RECOVERY cooldown. Remaining: %d sec", r.mainTicket, remainingSeconds));
         return;
      }

      if(r.recoveryAttempts >= cfg.max_recovery_attempts)
      {
         CloseActivePosition(r, StringFormat("Max recovery attempts reached (%d/%d)",
                                             r.recoveryAttempts, cfg.max_recovery_attempts));
         return;
      }

      if(m_debugMode)
         Log(StringFormat("Position %d ready for recovery signal. Attempts: %d/%d",
                          r.mainTicket, r.recoveryAttempts, cfg.max_recovery_attempts));
   }

   void VerifyAndCleanupEngines()
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      for(int i = ArraySize(engines) - 1; i >= 0; i--)
      {
         RecoveryEngine *r = engines[i];
         if(CheckPointer(r) == POINTER_INVALID || !r.active) continue;

         if(r.state == TRADE_STATE_RECOVERY)
            ProcessRecovery(r, m_data.GetATRPoints());

         if(!PositionSelectByTicket(r.mainTicket))
         {
            if(m_debugMode)
               PrintFormat("[Recovery] Position %d closed externally. Cleaning engine.", r.mainTicket);
            r.active = false;
            ClearEngineGVs(r.mainTicket);
            r.Reset();
            continue;
         }

         if(cfg.max_trade_duration_days > 0 && r.entryTime > 0)
         {
            if(TimeCurrent() > r.entryTime + (cfg.max_trade_duration_days * 86400))
            {
               CloseActivePosition(r, StringFormat("Max trade duration exceeded (%d days)",
                                                   cfg.max_trade_duration_days));
               continue;
            }
         }

         r.peakEquity = MathMax(r.peakEquity, AccountInfoDouble(ACCOUNT_EQUITY));
      }
   }

public:
   RecoveryManager() : IManager("RecoveryManager", 25)
   {
      m_lastTrailingUpdate = 0;
      m_trailingThrottleMs = 500;
      ArrayResize(engines, 0);
      m_recoveryScore      = 100;
      m_avgRecoveryTime    = 0.0;
      m_totalRecoveredLoss = 0.0;
      m_stats.Init();
      m_regimeAware    = true;
      m_minRegimeScore = 0.3;
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
      for(int i = ArraySize(engines) - 1; i >= 0; i--)
      {
         if(CheckPointer(engines[i]) == POINTER_DYNAMIC)
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
      if(CheckPointer(e) == POINTER_INVALID || ArraySize(engines) == 0 || !m_initialized)
         return;

      double atrvalue = 0;
      if(CheckPointer(m_data) != POINTER_INVALID)
         atrvalue = m_data.GetATRPoints();
      if(atrvalue <= 0) return;

      for(int i = 0; i < ArraySize(engines); i++)
      {
         RecoveryEngine *r = engines[i];
         if(CheckPointer(r) != POINTER_INVALID && r.active)
            ProcessTrailingAndPartial(r, e.tick, atrvalue);
      }
   }

   virtual void OnOrderExecution(OrderExecutionEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID || !e.success) return;
      if(e.orderType != ORDER_TYPE_BUY && e.orderType != ORDER_TYPE_SELL) return;
      if(e.ticket > 0)
         Register(e.ticket, e.orderType, e.entryPrice, e.tp, e.sl, 0.0, e.volume, 0.0);
   }

   virtual void OnSignalGenerated(SignalGeneratedEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID || !cfg.exit_on_opposite) return;
      CloseOppositePositions(e.signal.orderType);
   }

   virtual void OnRecoverySignal(RecoverySignalEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      RecoveryEngine *r = GetEngine(e.originalTicket);
      if(CheckPointer(r) == POINTER_INVALID || r.state != TRADE_STATE_RECOVERY)
      {
         Log(StringFormat("Received recovery signal for non-recovery/non-existent position %d. Ignoring.",
                          e.originalTicket));
         return;
      }
      Log(StringFormat("Recovery signal received for original trade %d. Signal: %s",
                       e.originalTicket, e.signal.reason));
   }

   virtual void OnEmergencyStop(EmergencyStopEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      Log("EMERGENCY STOP triggered: " + e.reason);

      for(int i = ArraySize(engines) - 1; i >= 0; i--)
      {
         RecoveryEngine *r = engines[i];
         if(CheckPointer(r) != POINTER_INVALID)
         {
            if(r.active) CloseActivePosition(r, "Emergency: " + e.reason);
            delete r;
            engines[i] = NULL;
         }
      }
      ArrayResize(engines, 0);
   }

   virtual void OnHeartbeat(HeartbeatEvent *e) override
   {
      VerifyAndCleanupEngines();
      UpdateRecoveryMetrics();
   }

   // ---- Metrics ----
   void UpdateRecoveryMetrics()
   {
      if(m_stats.totalRecoveries > 0)
      {
         m_recoveryScore  = (int)MathRound(m_stats.GetQualityScore());
         m_avgRecoveryTime = m_stats.avgRecoveryTimeMin;

         if(m_regimeAware && CheckPointer(g_regimeFilter) != POINTER_INVALID)
         {
            double regimeScore = g_regimeFilter.GetRegimeScore();
            if(regimeScore < 0.3)
               m_recoveryScore = (int)(m_recoveryScore * 0.7);
         }
      }
   }

   int    GetRecoveryScore()        const { return m_recoveryScore; }
   double GetSuccessRate()          const { return m_stats.GetSuccessRate() * 100.0; }
   double GetFakeoutRecoveryRate()  const { return m_stats.GetFakeoutRecoveryRate() * 100.0; }
   double GetAvgRecoveryTime()      const { return m_avgRecoveryTime; }
   int    GetTotalRecoveries()      const { return m_stats.totalRecoveries; }
   const RecoveryStats& GetRecoveryStats() const { return m_stats; }

   bool IsRecoveryHealthy() const
   {
      return (m_stats.GetSuccessRate() > 0.5 || m_stats.totalRecoveries < 3);
   }

   bool IsRecoveryFavorable() const
   {
      if(!m_regimeAware) return true;
      if(CheckPointer(g_regimeFilter) == POINTER_INVALID) return true;
      return (g_regimeFilter.GetRegimeScore() >= m_minRegimeScore);
   }

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

   void ResetStatistics()
   {
      m_stats.Init();
      m_recoveryScore      = 100;
      m_avgRecoveryTime    = 0.0;
      m_totalRecoveredLoss = 0.0;
      if(m_debugMode) Print("[Recovery] Statistics reset.");
   }

   virtual void OnConfigReload(ConfigReloadEvent *e) override
   {
      IManager::OnConfigReload(e);
      if(m_debugMode) Print("[Recovery] Config cache refreshed.");
   }

public:
   virtual bool Init() override
   {
      if(!IManager::Init()) return false;
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
      if(FindEngineIndex(ticket) >= 0) return;

      int targetIdx = -1;
      int total     = ArraySize(engines);
      for(int i = 0; i < total; i++)
      {
         if(CheckPointer(engines[i]) == POINTER_INVALID || !engines[i].active)
         {
            targetIdx = i;
            break;
         }
      }

      if(targetIdx == -1)
      {
         targetIdx = total;
         ArrayResize(engines, total + 1);
         engines[targetIdx] = new RecoveryEngine();
         if(CheckPointer(engines[targetIdx]) == POINTER_INVALID)
         {
            if(m_debugMode)
               PrintFormat("[Recovery] CRITICAL: Failed to allocate engine for %d", ticket);
            ArrayResize(engines, total);
            return;
         }
      }

      RecoveryEngine *target = engines[targetIdx];
      target.Reset();
      target.active         = true;
      target.mainTicket     = ticket;
      target.direction      = (type == ORDER_TYPE_BUY ? 1 : -1);
      target.state          = TRADE_STATE_NORMAL;
      target.entryPrice     = entry;
      target.initialTP      = tp;
      target.brokerSL       = brokerSL;
      target.lastKnownATR   = (atr > 0) ? atr : m_data.GetATRPoints();
      target.zonePrice      = zonePrice;
      target.lot            = lot;
      target.slMultiplier   = slMult;
      target.peakEquity     = AccountInfoDouble(ACCOUNT_EQUITY);
      target.entryTime      = TimeCurrent();
      target.originalEntry  = entry;
      target.originalSL     = brokerSL;
      target.originalTP     = tp;
      target.originalLot    = lot;

      double pcDist = target.lastKnownATR * cfg.partial_close_atr * _Point;
      target.partialTP = NormalizeDouble(
         entry + ((type == ORDER_TYPE_BUY ? 1.0 : -1.0) * pcDist), _Digits);

      // FIX (RM-BUG-2): Validate state after SaveState (implements IsStateValid contract)
      target.SaveState();
      if(!target.IsStateValid())
      {
         if(m_debugMode)
            PrintFormat("[Recovery] WARN: Saved state for ticket %d failed validation. Resetting.", ticket);
         ClearEngineGVs(ticket);
         target.Reset();
         target.active = false;
         return;
      }

      if(m_debugMode)
         PrintFormat("[Recovery] Registered position %d | Type: %s | Lot: %.2f",
                     ticket, (type == ORDER_TYPE_BUY ? "BUY" : "SELL"), lot);
   }

   void CloseOppositePositions(ENUM_ORDER_TYPE signalType)
   {
      int oppositeDir = (signalType == ORDER_TYPE_BUY) ? -1 : 1;
      for(int i = ArraySize(engines) - 1; i >= 0; i--)
      {
         RecoveryEngine *r = engines[i];
         if(CheckPointer(r) != POINTER_INVALID && r.active && r.direction == oppositeDir)
            CloseActivePosition(r, "Opposite Signal Triggered");
      }
   }

   void NotifyRecoverySuccess(ulong originalTicket)
   {
      int idx = FindEngineIndex(originalTicket);
      if(idx != -1)
      {
         RecoveryEngine *r = engines[idx];
         if(r.recoveryAttempts > 0 && r.state == TRADE_STATE_RECOVERY)
         {
            m_stats.successfulRecoveries++;
            if(m_debugMode)
               PrintFormat("[Recovery] Recovery SUCCESS for position %d after %d attempts",
                           originalTicket, r.recoveryAttempts);
         }
         r.state  = TRADE_STATE_DONE;
         r.active = false;
         ClearEngineGVs(originalTicket);
         if(m_debugMode)
            PrintFormat("[Recovery] Original position %d recovery cycle completed. | Total Success Rate: %.1f%%",
                        originalTicket, GetSuccessRate());
      }
   }
};

#endif
