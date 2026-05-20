//+------------------------------------------------------------------+
//|                                              RecoveryManager.mqh |
//|                                       Copyright 2026, Agsicentre |
//|            Position Recovery & Fakeout Management Module         |
//+------------------------------------------------------------------+
//| V2.03 FIXES:                                                     |
//| - RM-BUG-FIX-3 [CRITICAL]: Replaced undefined CFG macro with    |
//|   Config() accessor (IManager v2.11 m_cfg cached field).        |
//|   CFG.risk.magic / CFG.risk.exit_on_opposite were never defined  |
//|   anywhere — caused compile error / undefined behaviour.         |
//| - RM-BUG-FIX-4 [MEDIUM]: Init() CFG.risk.magic fixed same way.  |
//|                                                                  |
//| V2.02 FIXES (previous):                                         |
//| - RM-BUG-FIX-1 [CRITICAL]: ClearEngineGVs() cfg undeclared.    |
//| - RM-BUG-FIX-2 [HIGH]: GV keys now include ACCOUNT_LOGIN prefix.|
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "2.03"
#property strict

#ifndef __RECOVERY_MANAGER_MQH__
#define __RECOVERY_MANAGER_MQH__

#include <Trade/Trade.mqh>
#include "../Core/IManager.mqh"
#include "10.DataManager.mqh"
#include "9.PatternManager.mqh"
#include "12.MarketRegime.mqh"

//+------------------------------------------------------------------+
//| Recovery Statistics                                              |
//+------------------------------------------------------------------+
struct RecoveryStats
{
   int    totalRecoveries;
   int    successfulRecoveries;
   int    failedRecoveries;
   int    fakeoutsDetected;
   int    fakeoutsRecovered;
   double avgRecoveryProfit;
   double maxDrawdownRecovered;
   double avgRecoveryTimeMin;
   ulong  lastRecoveryTime;

   void Init() { ZeroMemory(this); maxDrawdownRecovered = 0; }

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
      double s = GetSuccessRate()         * 40.0;
      double f = GetFakeoutRecoveryRate() * 30.0;
      double p = MathMin(30.0, (avgRecoveryProfit > 0 ? avgRecoveryProfit : 0) * 3.0);
      return MathMin(100.0, s + f + p);
   }
};

class RecoveryManager : public IManager
{
private:
   RecoveryEngine *engines[];
   CTrade          m_trade;

   int    m_recoveryScore;
   double m_avgRecoveryTime;
   double m_totalRecoveredLoss;
   RecoveryStats m_stats;

   ulong m_lastTrailingUpdate;
   int   m_trailingThrottleMs;

   bool   m_regimeAware;
   double m_minRegimeScore;

private:
   // Override to ensure m_cfg is always fresh before subclass methods use it
   virtual void RefreshConfigCache() override { IManager::RefreshConfigCache(); }

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

   // RM-BUG-FIX-1+2: cfg fetched from DataManager; account login in GV key.
   void ClearEngineGVs(ulong ticket)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      string prefix = "PASR_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_"
                    + IntegerToString(cfg.magic) + "_" + IntegerToString(ticket) + "_";
      for(int i = GlobalVariablesTotal() - 1; i >= 0; i--)
      {
         string varName = GlobalVariableName(i);
         if(StringFind(varName, prefix) == 0)
            GlobalVariableDel(varName);
      }
   }

   void CloseActivePosition(RecoveryEngine *r, const string reason)
   {
      if(CheckPointer(r) == POINTER_INVALID || r.state == TRADE_STATE_DONE)
         return;

      bool   wasRecovered = (r.recoveryAttempts > 0 && r.state == TRADE_STATE_RECOVERY);
      double profitPoints = 0;

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
               if(profitPoints > 0) m_stats.successfulRecoveries++;
               else                 m_stats.failedRecoveries++;

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
            PrintFormat("[Recovery] Failed to close %d: Error %d (%s)",
                        r.mainTicket, GetLastError(), m_trade.ResultRetcodeDescription());
      }

      ClearEngineGVs(r.mainTicket);
      r.Reset();
      r.active = false;

      PositionUpdateEvent *notify = new PositionUpdateEvent(r.mainTicket, 0, 0, true);
      DispatchEvent(notify);
   }

   bool DetectAndHandleFakeout(RecoveryEngine *r, const MqlTick &tick, double atrvalue)
   {
      if(CheckPointer(r) == POINTER_INVALID || !r.active) return false;
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
      if(!PatternManager::DetectFakeout(ctx, signal)) return false;

      if(m_debugMode)
         PrintFormat("[Fakeout] Position %d: %s (Confidence: %.2f, Level: %d)",
                     r.mainTicket, signal.reason, signal.confidence, signal.level);

      if(signal.level < 2)
      {
         if(m_debugMode)
            Log(StringFormat("Fakeout low confidence (%.2f). Continuing to recovery.", signal.confidence));
         return false;
      }

      if(!PositionSelectByTicket(r.mainTicket)) return false;

      ENUM_POSITION_TYPE type      = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double             currentSL = PositionGetDouble(POSITION_SL);
      double             currentTP = PositionGetDouble(POSITION_TP);
      double             atr       = atrvalue * _Point;
      double slAdjust = atr * cfg.fakeout_sl_adjustment_atr;
      double newSL    = 0;

      if(type == POSITION_TYPE_BUY)
         newSL = NormalizeDouble(currentSL - slAdjust, _Digits);
      else
         newSL = NormalizeDouble(currentSL + slAdjust, _Digits);

      double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      double curPrice  = (type == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
      bool   slValid   = (type == POSITION_TYPE_BUY)
         ? (curPrice - newSL) > stopLevel
         : (newSL - curPrice) > stopLevel;

      if(!slValid)
      {
         if(m_debugMode) PrintFormat("[Fakeout] Cannot adjust SL: too close to price");
         return false;
      }

      if(m_trade.PositionModify(r.mainTicket, newSL, currentTP))
      {
         r.lastKnownATR     = atrvalue;
         r.recoveryAttempts++;
         m_stats.fakeoutsDetected++;
         m_stats.fakeoutsRecovered++;
         r.SaveState();
         if(m_debugMode)
            PrintFormat("[Fakeout] OK SL adjusted %d: %.5f->%.5f (conf:%.2f) #%d",
                        r.mainTicket, currentSL, newSL, signal.confidence, r.recoveryAttempts);
         return true;
      }
      else if(m_debugMode)
         PrintFormat("[Fakeout] FAIL %d: Error %d (%s)",
                     r.mainTicket, GetLastError(), m_trade.ResultRetcodeDescription());

      return false;
   }

   void ProcessTrailingAndPartial(RecoveryEngine *r, const MqlTick &tick, double atrvalue)
   {
      // Use cached m_cfg — no extra struct copy (IM-OPT-1)
      if(!Config().use_trailing || !r.active) return;
      if(!PositionSelectByTicket(r.mainTicket)) return;

      ENUM_POSITION_TYPE type      = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double             openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double             curLot    = PositionGetDouble(POSITION_VOLUME);
      double             slPrice   = PositionGetDouble(POSITION_SL);
      double             tpPrice   = PositionGetDouble(POSITION_TP);
      double             curPrice  = (type == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
      double             atr       = atrvalue * _Point;
      double             profitATR = (type == POSITION_TYPE_BUY)
         ? (curPrice - openPrice) / atr
         : (openPrice - curPrice) / atr;

      double newSL = slPrice;

      if(type == POSITION_TYPE_BUY)
      {
         if(profitATR >= Config().lock_profit_atr)
            newSL = MathMax(newSL, openPrice + atr * Config().lock_offset_atr);
         if(profitATR >= Config().trail_activation_atr)
            newSL = MathMax(newSL, curPrice - atr * Config().trail_step_atr);
      }
      else
      {
         double trailBase = openPrice - atr * Config().lock_offset_atr;
         if(profitATR >= Config().lock_profit_atr)
            newSL = MathMin(newSL == 0 ? trailBase : newSL, trailBase);
         if(profitATR >= Config().trail_activation_atr)
         {
            double dynamicSL = NormalizeDouble(curPrice + atr * Config().trail_step_atr, _Digits);
            newSL = (newSL == 0) ? dynamicSL : MathMin(newSL, dynamicSL);
         }
      }

      if(Config().partial_close_lot_pct > 0 && profitATR >= Config().partial_close_atr && !r.partialClosed)
      {
         double closeLot = m_data.NormalizeVolume(_Symbol, curLot * Config().partial_close_lot_pct);
         if(closeLot > 0 && m_trade.PositionClosePartial(r.mainTicket, closeLot))
         {
            r.partialClosed = true;
            if(m_debugMode)
               PrintFormat("[Trailing] Partial close %d: %.2f lots", r.mainTicket, closeLot);
         }
      }

      if(newSL != slPrice && newSL != 0)
      {
         if(m_trade.PositionModify(r.mainTicket, newSL, tpPrice))
         {
            if(m_debugMode)
               PrintFormat("[Trailing] SL moved %d: %.5f -> %.5f", r.mainTicket, slPrice, newSL);
         }
      }
   }

   bool AttemptRecovery(RecoveryEngine *r)
   {
      if(r.recoveryAttempts >= Config().max_recovery_attempts)
      {
         if(m_debugMode)
            PrintFormat("[Recovery] Max attempts (%d/%d) reached for %d",
                        r.recoveryAttempts, Config().max_recovery_attempts, r.mainTicket);
         return false;
      }

      r.state = TRADE_STATE_RECOVERY;
      r.recoveryAttempts++;
      r.recoveryCooldownExpiry = TimeCurrent()
         + (Config().recovery_cooldown_bars * PeriodSeconds(_Period));
      r.SaveState();

      if(m_debugMode)
         PrintFormat("[Recovery] Attempt %d/%d for ticket %d",
                     r.recoveryAttempts, Config().max_recovery_attempts, r.mainTicket);

      RecoverySignalEvent *ev = new RecoverySignalEvent(r.mainTicket, r.direction, r.entryPrice,
                                                         r.lastKnownATR, r.recoveryAttempts);
      DispatchEvent(ev);
      return true;
   }

   void CheckRecoveryTimeout(RecoveryEngine *r)
   {
      if(r.recoveryAttempts >= Config().max_recovery_attempts)
      {
         PrintFormat("[Recovery] Timeout: max attempts %d/%d for %d",
                     r.recoveryAttempts, Config().max_recovery_attempts, r.mainTicket);
         ClearEngineGVs(r.mainTicket);
         r.Reset();
         return;
      }
      if(r.state != TRADE_STATE_NORMAL) return;

      ENUM_POSITION_TYPE type      = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double             slPrice   = PositionGetDouble(POSITION_SL);
      double             curPrice  = (type == POSITION_TYPE_BUY)
         ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
         : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      bool slHit = (type == POSITION_TYPE_BUY)
         ? (slPrice > 0 && curPrice <= slPrice)
         : (slPrice > 0 && curPrice >= slPrice);
      if(!slHit) return;

      bool cooldownActive = (r.recoveryCooldownExpiry > 0 && TimeCurrent() < r.recoveryCooldownExpiry);
      if(cooldownActive) return;

      if(Config().recovery_use && r.recoveryAttempts < Config().max_recovery_attempts)
      {
         PrintFormat("[Recovery] SL hit on %d, recovery attempt %d/%d",
                     r.mainTicket, r.recoveryAttempts + 1, Config().max_recovery_attempts);
         r.recoveryCooldownExpiry = TimeCurrent()
            + (Config().recovery_cooldown_bars * PeriodSeconds(_Period));
         r.lastKnownATR = m_data.GetATRPoints();
         r.SaveState();
         AttemptRecovery(r);
      }
      else
      {
         PrintFormat("[Recovery] SL hit on %d, no recovery configured. Closing.", r.mainTicket);
         ClearEngineGVs(r.mainTicket);
         r.state = TRADE_STATE_DONE;
         r.Reset();
      }
   }

   void CheckExpiryAndForcedClose(RecoveryEngine *r)
   {
      if(Config().max_trade_duration_days > 0 && r.entryTime > 0)
      {
         if(TimeCurrent() > r.entryTime + (Config().max_trade_duration_days * 86400))
         {
            PrintFormat("[Recovery] Trade %d expired after %d days. Force closing.",
                        r.mainTicket, Config().max_trade_duration_days);
            CloseActivePosition(r, "MaxDurationExpiry");
         }
      }
   }

public:
   RecoveryManager()
      : IManager("RecoveryManager", 60),
        m_recoveryScore(0), m_avgRecoveryTime(0), m_totalRecoveredLoss(0),
        m_lastTrailingUpdate(0), m_trailingThrottleMs(100),
        m_regimeAware(false), m_minRegimeScore(0.0)
   {
      ArrayResize(engines, 0);
      m_stats.Init();
   }

   ~RecoveryManager()
   {
      for(int i = 0; i < ArraySize(engines); i++)
      {
         if(CheckPointer(engines[i]) != POINTER_INVALID)
            delete engines[i];
      }
      ArrayResize(engines, 0);
   }

   virtual bool Init() override
   {
      if(!IManager::Init()) return false;
      // RM-BUG-FIX-3: use Config() accessor — CFG macro never existed
      m_trade.SetExpertMagicNumber(Config().magic);
      return true;
   }

   virtual void DeclareEvents() override
   {
      AddEvent(EVENT_ID_POSITION_UPDATE);
      AddEvent(EVENT_ID_PRICE_UPDATE);
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_RECOVERY_OPPORTUNITY);
      AddEvent(EVENT_ID_EMERGENCY_STOP);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
      AddEvent(EVENT_ID_SIGNAL_GENERATED);
   }

   virtual void OnPositionUpdate(PositionUpdateEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      if(e.isClosed)
      {
         int idx = FindEngineIndex(e.ticket);
         if(idx >= 0)
         {
            ClearEngineGVs(e.ticket);
            engines[idx].Reset();
            engines[idx].active = false;
            if(m_debugMode)
               PrintFormat("[Recovery] Engine removed for closed ticket %d", e.ticket);
         }
         return;
      }

      int idx = FindEngineIndex(e.ticket);
      if(idx < 0)
      {
         int sz = ArraySize(engines);
         ArrayResize(engines, sz + 1);
         engines[sz] = new RecoveryEngine();
         engines[sz].mainTicket = e.ticket;
         engines[sz].active     = true;
         engines[sz].entryPrice = e.price;
         engines[sz].direction  = (e.type == POSITION_TYPE_BUY) ? 1 : -1;
         engines[sz].entryTime  = TimeCurrent();
         engines[sz].state      = TRADE_STATE_NORMAL;
         if(m_debugMode)
            PrintFormat("[Recovery] Engine created for ticket %d", e.ticket);
      }
   }

   virtual void OnPriceUpdate(PriceUpdateEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;

      ulong nowMs = GetTickCount64();
      if(nowMs - m_lastTrailingUpdate < (ulong)m_trailingThrottleMs) return;
      m_lastTrailingUpdate = nowMs;

      double atrValue = m_data.GetATRPoints();

      for(int i = ArraySize(engines) - 1; i >= 0; i--)
      {
         RecoveryEngine *r = engines[i];
         if(CheckPointer(r) == POINTER_INVALID || !r.active) continue;

         if(!PositionSelectByTicket(r.mainTicket))
         {
            ClearEngineGVs(r.mainTicket);
            r.Reset();
            r.active = false;
            continue;
         }

         if(r.state == TRADE_STATE_NORMAL)
            CheckRecoveryTimeout(r);

         ProcessTrailingAndPartial(r, e.tick, atrValue);
         CheckExpiryAndForcedClose(r);
      }
   }

   virtual void OnNewBar(NewBarEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      for(int i = 0; i < ArraySize(engines); i++)
      {
         RecoveryEngine *r = engines[i];
         if(CheckPointer(r) == POINTER_INVALID || !r.active) continue;
         if(r.state != TRADE_STATE_NORMAL) continue;

         if(!PositionSelectByTicket(r.mainTicket))
         {
            ClearEngineGVs(r.mainTicket);
            r.Reset();
            r.active = false;
            continue;
         }

         double atrValue = m_data.GetATRPoints();
         MqlTick tick;
         SymbolInfoTick(_Symbol, tick);
         if(!DetectAndHandleFakeout(r, tick, atrValue))
            CheckRecoveryTimeout(r);
      }
   }

   virtual void OnEmergencyStop(EmergencyStopEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      for(int i = 0; i < ArraySize(engines); i++)
      {
         RecoveryEngine *r = engines[i];
         if(CheckPointer(r) != POINTER_INVALID && r.active)
            CloseActivePosition(r, "EmergencyStop");
      }
   }

   virtual void OnConfigReload(ConfigReloadEvent *e) override
   {
      IManager::OnConfigReload(e);
      // Config() now returns refreshed m_cfg after IManager::OnConfigReload
      m_trade.SetExpertMagicNumber(Config().magic);
   }

   virtual void OnRecoveryOpportunity(RecoveryOpportunityEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      int idx = FindEngineIndex(e.ticket);
      if(idx < 0) return;
      RecoveryEngine *r = engines[idx];
      if(CheckPointer(r) == POINTER_INVALID || !r.active) return;
      if(r.state != TRADE_STATE_RECOVERY) return;

      if(r.recoveryAttempts >= Config().max_recovery_attempts)
      {
         PrintFormat("[Recovery] Max recovery attempts reached for %d. Closing.", r.mainTicket);
         CloseActivePosition(r, "MaxRecoveryAttempts");
         return;
      }

      r.lastKnownATR = m_data.GetATRPoints();
      r.SaveState();

      PositionUpdateEvent *update = new PositionUpdateEvent(r.mainTicket, e.price, e.atr, false);
      DispatchEvent(update);
   }

   // RM-BUG-FIX-3: was CFG.risk.exit_on_opposite — CFG undefined, use Config()
   virtual void OnSignalGenerated(SignalGeneratedEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID || !Config().exit_on_opposite) return;

      for(int i = 0; i < ArraySize(engines); i++)
      {
         RecoveryEngine *r = engines[i];
         if(CheckPointer(r) == POINTER_INVALID || !r.active) continue;

         bool isOpposite = (r.direction ==  1 && e.direction == -1) ||
                           (r.direction == -1 && e.direction ==  1);
         if(isOpposite)
            CloseActivePosition(r, "OppositeSignal");
      }
   }

   bool GetPartialCloseInfo(ulong ticket, double &closeLot, double &targetPrice)
   {
      int idx = FindEngineIndex(ticket);
      if(idx < 0) return false;
      RecoveryEngine *r = engines[idx];
      if(CheckPointer(r) == POINTER_INVALID || !r.active) return false;
      if(!PositionSelectByTicket(ticket)) return false;

      double curLot  = PositionGetDouble(POSITION_VOLUME);
      double pcDist  = r.lastKnownATR * Config().partial_close_atr * _Point;

      ENUM_POSITION_TYPE type      = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double             openPrice = PositionGetDouble(POSITION_PRICE_OPEN);

      targetPrice = (type == POSITION_TYPE_BUY)
         ? openPrice + pcDist
         : openPrice - pcDist;
      closeLot = m_data.NormalizeVolume(_Symbol, curLot * Config().partial_close_lot_pct);

      if(closeLot <= 0) return false;

      double curPrice = (type == POSITION_TYPE_BUY)
         ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
         : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      bool atTarget = (type == POSITION_TYPE_BUY)
         ? curPrice >= targetPrice
         : curPrice <= targetPrice;

      if(atTarget && !r.partialClosed)
      {
         if(m_trade.PositionClosePartial(ticket, closeLot))
         {
            r.partialClosed = true;
            ClearEngineGVs(ticket);
            return true;
         }
      }
      return false;
   }

   RecoveryStats GetStats()          const { return m_stats; }
   int           GetActiveEngineCount() const
   {
      int cnt = 0;
      for(int i = 0; i < ArraySize(engines); i++)
      {
         RecoveryEngine *r = engines[i];
         if(CheckPointer(r) != POINTER_INVALID && r.active) cnt++;
      }
      return cnt;
   }
};

#endif // __RECOVERY_MANAGER_MQH__
