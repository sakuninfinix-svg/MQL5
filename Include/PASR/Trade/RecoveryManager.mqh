//+------------------------------------------------------------------+
//|                                   Trade/RecoveryManager.mqh      |
//|                          Copyright 2026, Agsicentre             |
//|    Position Recovery & Fakeout Management Module                 |
//|    Canonical production location — migrated from 8.RecoveryManager|
//|                                                                  |
//| MIGRATION STATUS: ✅ COMPLETE (v2.05)                            |
//|                                                                  |
//| BUG FIX HISTORY:                                                 |
//| v2.05 (this file):                                               |
//|  * RM-BUG-007 [HIGH]  engines[] unbounded growth → MAX_ENGINES cap|
//|  * RM-BUG-008 [HIGH]  OnPositionUpdate: engine created without    |
//|                       PositionSelectByTicket guard                |
//|  * RM-BUG-009 [MEDIUM] GetPartialCloseInfo double-close on tick → |
//|                       throttle guard added                        |
//|  * RM-BUG-010 [LOW]   include 10.DataManager.mqh → Infra/         |
//|  * RM-OPT-1   engine array compaction on OnNewBar                |
//|  * RM-OPT-2   trailing throttle now configurable                 |
//|                                                                  |
//| v2.04 (8.RecoveryManager.mqh — legacy source):                   |
//|  * RM-BUG-001 [CRITICAL] ClearEngineGVs cfg undeclared → fixed   |
//|  * RM-BUG-002 [HIGH]     GV keys missing ACCOUNT_LOGIN prefix     |
//|  * RM-BUG-003 [CRITICAL] CFG macro undefined → Config() accessor  |
//|  * RM-BUG-004 [MEDIUM]   Init() magic via CFG → Config().magic    |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "2.05"
#property strict

#ifndef __TRADE_RECOVERY_MANAGER_MQH__
#define __TRADE_RECOVERY_MANAGER_MQH__

#include <Trade/Trade.mqh>
#include "../Core/IManager.mqh"
// RM-BUG-010: was 10.DataManager.mqh — use Infra/ production file
#include "../Infra/DataManager.mqh"
#include "../Pattern/PatternManager.mqh"
#include "../12.MarketRegime.mqh"

//+------------------------------------------------------------------+
//| Constants                                                        |
//+------------------------------------------------------------------+
#define RECOVERY_MAX_ENGINES 64    // RM-BUG-007: hard cap, prevent unbounded growth

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

   void Init() { ZeroMemory(this); }

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

//+------------------------------------------------------------------+
//| RecoveryManager                                                  |
//+------------------------------------------------------------------+
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

   // RM-BUG-009: per-ticket partial close debounce (prevent double-close on tick)
   ulong  m_lastPartialCloseMs;
   int    m_partialCloseThrottleMs;

   bool   m_regimeAware;
   double m_minRegimeScore;

private:
   virtual void RefreshConfigCache() override { IManager::RefreshConfigCache(); }

   int FindEngineIndex(ulong ticket) const
   {
      int sz = ArraySize(engines);
      for(int i = 0; i < sz; i++)
      {
         RecoveryEngine *r = engines[i];
         if(CheckPointer(r) != POINTER_INVALID && r.active && r.mainTicket == ticket)
            return i;
      }
      return -1;
   }

   // RM-BUG-001+002: cfg from GetConfigCache(); ACCOUNT_LOGIN in GV prefix.
   void ClearEngineGVs(ulong ticket)
   {
      StrategyConfig cfg;
      m_data.GetConfigCache(cfg);
      string prefix = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))
                    + "_PASR_"
                    + IntegerToString(cfg.magic)
                    + "_" + IntegerToString(ticket) + "_";
      for(int i = GlobalVariablesTotal() - 1; i >= 0; i--)
      {
         string gv = GlobalVariableName(i);
         if(StringFind(gv, prefix) == 0)
            GlobalVariableDel(gv);
      }
   }

   // RM-OPT-1: compact engines[] — remove DONE/inactive slots to prevent growth.
   // Call on OnNewBar (low-frequency). O(n) but n is capped at RECOVERY_MAX_ENGINES.
   void CompactEngines()
   {
      int keep = 0;
      int sz   = ArraySize(engines);
      for(int i = 0; i < sz; i++)
      {
         RecoveryEngine *r = engines[i];
         if(CheckPointer(r) != POINTER_INVALID && r.active)
         {
            engines[keep] = r;
            keep++;
         }
         else
         {
            if(CheckPointer(r) != POINTER_INVALID) delete r;
            engines[i] = NULL;
         }
      }
      ArrayResize(engines, keep);
   }

   void CloseActivePosition(RecoveryEngine *r, const string reason)
   {
      if(CheckPointer(r) == POINTER_INVALID || r.state == TRADE_STATE_DONE)
         return;

      bool   wasRecovered = (r.recoveryAttempts > 0 && r.state == TRADE_STATE_RECOVERY);
      double profitPoints = 0.0;

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
                  double recovMin = (double)(TimeCurrent() - r.entryTime) / 60.0;
                  m_avgRecoveryTime =
                     ((m_avgRecoveryTime * (m_stats.totalRecoveries - 1)) + recovMin)
                     / m_stats.totalRecoveries;
                  m_stats.avgRecoveryTimeMin = m_avgRecoveryTime;
               }
            }
            if(m_debugMode)
               PrintFormat("[Recovery] Closed %d: %s | profit=%.2fpts | recovered=%s",
                           r.mainTicket, reason, profitPoints, wasRecovered ? "yes" : "no");
         }
         else if(m_debugMode)
            PrintFormat("[Recovery] Close FAILED %d: err=%d (%s)",
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
         if(m_debugMode) Log("[Recovery] CopyRates failed for fakeout detection");
         return false;
      }

      FakeoutResult signal;
      if(!PatternManager::DetectFakeout(ctx, signal)) return false;

      if(m_debugMode)
         PrintFormat("[Fakeout] ticket=%d reason=%s conf=%.2f level=%d",
                     r.mainTicket, signal.reason, signal.confidence, signal.level);

      if(signal.level < 2) return false;
      if(!PositionSelectByTicket(r.mainTicket)) return false;

      ENUM_POSITION_TYPE type      = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double             currentSL = PositionGetDouble(POSITION_SL);
      double             currentTP = PositionGetDouble(POSITION_TP);
      double             atr       = atrvalue * _Point;
      double             slAdjust  = atr * Config().fakeout_sl_adjustment_atr;
      double             newSL     = (type == POSITION_TYPE_BUY)
         ? NormalizeDouble(currentSL - slAdjust, _Digits)
         : NormalizeDouble(currentSL + slAdjust, _Digits);

      double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      double curPrice  = (type == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
      bool   slValid   = (type == POSITION_TYPE_BUY)
         ? (curPrice - newSL) > stopLevel
         : (newSL - curPrice) > stopLevel;

      if(!slValid)
      {
         if(m_debugMode) Print("[Fakeout] SL adjust rejected: too close to price");
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
            PrintFormat("[Fakeout] SL adjusted %d: %.5f->%.5f conf=%.2f attempt#%d",
                        r.mainTicket, currentSL, newSL, signal.confidence, r.recoveryAttempts);
         return true;
      }
      if(m_debugMode)
         PrintFormat("[Fakeout] Modify FAILED %d: err=%d (%s)",
                     r.mainTicket, GetLastError(), m_trade.ResultRetcodeDescription());
      return false;
   }

   void ProcessTrailingAndPartial(RecoveryEngine *r, const MqlTick &tick, double atrvalue)
   {
      if(!Config().use_trailing || !r.active) return;
      if(!PositionSelectByTicket(r.mainTicket)) return;

      ENUM_POSITION_TYPE type      = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double             openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double             curLot    = PositionGetDouble(POSITION_VOLUME);
      double             slPrice   = PositionGetDouble(POSITION_SL);
      double             tpPrice   = PositionGetDouble(POSITION_TP);
      double             curPrice  = (type == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
      double             atr       = atrvalue * _Point;
      double             profitATR = (atr > 0)
         ? ((type == POSITION_TYPE_BUY)
              ? (curPrice - openPrice) / atr
              : (openPrice - curPrice) / atr)
         : 0.0;

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
         double lockBase = openPrice - atr * Config().lock_offset_atr;
         if(profitATR >= Config().lock_profit_atr)
            newSL = (newSL == 0) ? lockBase : MathMin(newSL, lockBase);
         if(profitATR >= Config().trail_activation_atr)
         {
            double dynSL = NormalizeDouble(curPrice + atr * Config().trail_step_atr, _Digits);
            newSL = (newSL == 0) ? dynSL : MathMin(newSL, dynSL);
         }
      }

      // Partial close (RM-BUG-009: throttled to prevent double-close on same tick)
      if(Config().partial_close_lot_pct > 0 &&
         profitATR >= Config().partial_close_atr &&
         !r.partialClosed)
      {
         ulong nowMs = GetTickCount64();
         if(nowMs - m_lastPartialCloseMs >= (ulong)m_partialCloseThrottleMs)
         {
            double closeLot = m_data.NormalizeVolume(_Symbol, curLot * Config().partial_close_lot_pct);
            if(closeLot > 0 && m_trade.PositionClosePartial(r.mainTicket, closeLot))
            {
               r.partialClosed        = true;
               m_lastPartialCloseMs   = nowMs;
               if(m_debugMode)
                  PrintFormat("[Trailing] Partial close %d: %.2f lots", r.mainTicket, closeLot);
            }
         }
      }

      if(newSL != slPrice && newSL != 0)
      {
         if(m_trade.PositionModify(r.mainTicket, newSL, tpPrice))
         {
            if(m_debugMode)
               PrintFormat("[Trailing] SL moved %d: %.5f->%.5f", r.mainTicket, slPrice, newSL);
         }
      }
   }

   bool AttemptRecovery(RecoveryEngine *r)
   {
      if(r.recoveryAttempts >= Config().max_recovery_attempts)
      {
         if(m_debugMode)
            PrintFormat("[Recovery] Max attempts (%d/%d) for %d",
                        r.recoveryAttempts, Config().max_recovery_attempts, r.mainTicket);
         return false;
      }

      r.state = TRADE_STATE_RECOVERY;
      r.recoveryAttempts++;
      r.recoveryCooldownExpiry = TimeCurrent()
         + (Config().recovery_cooldown_bars * PeriodSeconds(_Period));
      r.SaveState();

      if(m_debugMode)
         PrintFormat("[Recovery] Attempt %d/%d ticket=%d",
                     r.recoveryAttempts, Config().max_recovery_attempts, r.mainTicket);

      RecoverySignalEvent *ev = new RecoverySignalEvent(
         r.mainTicket, r.direction, r.entryPrice, r.lastKnownATR, r.recoveryAttempts);
      DispatchEvent(ev);
      return true;
   }

   void CheckRecoveryTimeout(RecoveryEngine *r)
   {
      if(r.recoveryAttempts >= Config().max_recovery_attempts)
      {
         PrintFormat("[Recovery] Max attempts %d/%d ticket=%d",
                     r.recoveryAttempts, Config().max_recovery_attempts, r.mainTicket);
         ClearEngineGVs(r.mainTicket);
         r.Reset();
         return;
      }
      if(r.state != TRADE_STATE_NORMAL) return;
      if(!PositionSelectByTicket(r.mainTicket)) return;

      ENUM_POSITION_TYPE type    = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double             slPrice = PositionGetDouble(POSITION_SL);
      double             curPrice = (type == POSITION_TYPE_BUY)
         ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
         : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      bool slHit = (type == POSITION_TYPE_BUY)
         ? (slPrice > 0 && curPrice <= slPrice)
         : (slPrice > 0 && curPrice >= slPrice);
      if(!slHit) return;

      bool cooldownActive = (r.recoveryCooldownExpiry > 0 &&
                             TimeCurrent() < r.recoveryCooldownExpiry);
      if(cooldownActive) return;

      if(Config().recovery_use && r.recoveryAttempts < Config().max_recovery_attempts)
      {
         r.recoveryCooldownExpiry = TimeCurrent()
            + (Config().recovery_cooldown_bars * PeriodSeconds(_Period));
         r.lastKnownATR = m_data.GetATRPoints();
         r.SaveState();
         AttemptRecovery(r);
      }
      else
      {
         PrintFormat("[Recovery] SL hit ticket=%d, no recovery. Closing.", r.mainTicket);
         ClearEngineGVs(r.mainTicket);
         r.state = TRADE_STATE_DONE;
         r.Reset();
      }
   }

   void CheckExpiryAndForcedClose(RecoveryEngine *r)
   {
      if(Config().max_trade_duration_days > 0 && r.entryTime > 0)
      {
         if(TimeCurrent() > r.entryTime + ((datetime)Config().max_trade_duration_days * 86400))
         {
            PrintFormat("[Recovery] Trade %d expired (%d days). Force closing.",
                        r.mainTicket, Config().max_trade_duration_days);
            CloseActivePosition(r, "MaxDurationExpiry");
         }
      }
   }

public:
   RecoveryManager()
      : IManager("RecoveryManager", 60),
        m_recoveryScore(0), m_avgRecoveryTime(0.0), m_totalRecoveredLoss(0.0),
        m_lastTrailingUpdate(0), m_trailingThrottleMs(100),
        m_lastPartialCloseMs(0), m_partialCloseThrottleMs(500),
        m_regimeAware(false), m_minRegimeScore(0.0)
   {
      ArrayResize(engines, 0);
      m_stats.Init();
   }

   ~RecoveryManager()
   {
      int sz = ArraySize(engines);
      for(int i = 0; i < sz; i++)
      {
         if(CheckPointer(engines[i]) != POINTER_INVALID)
            delete engines[i];
      }
      ArrayResize(engines, 0);
   }

   virtual bool Init() override
   {
      if(!IManager::Init()) return false;
      m_trade.SetExpertMagicNumber(Config().magic);
      return true;
   }

   // Configurable trailing/partial throttle for high-frequency instruments
   void SetTrailingThrottle(int ms)      { if(ms > 0) m_trailingThrottleMs = ms; }
   void SetPartialCloseThrottle(int ms)  { if(ms > 0) m_partialCloseThrottleMs = ms; }

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
               PrintFormat("[Recovery] Engine deactivated for closed ticket=%d", e.ticket);
         }
         return;
      }

      // RM-BUG-008: validate position actually exists before creating engine
      if(!PositionSelectByTicket(e.ticket))
      {
         if(m_debugMode)
            PrintFormat("[Recovery] OnPositionUpdate: ticket=%d not found on broker, skipping", e.ticket);
         return;
      }

      int idx = FindEngineIndex(e.ticket);
      if(idx >= 0) return; // engine already exists

      // RM-BUG-007: cap engine count before allocating
      if(ArraySize(engines) >= RECOVERY_MAX_ENGINES)
      {
         PrintFormat("[Recovery] WARNING: MAX_ENGINES (%d) reached. ticket=%d not tracked.",
                     RECOVERY_MAX_ENGINES, e.ticket);
         return;
      }

      int sz = ArraySize(engines);
      ArrayResize(engines, sz + 1);
      engines[sz]              = new RecoveryEngine();
      engines[sz].mainTicket   = e.ticket;
      engines[sz].active       = true;
      engines[sz].entryPrice   = e.price;
      engines[sz].direction    = (e.type == POSITION_TYPE_BUY) ? 1 : -1;
      engines[sz].entryTime    = TimeCurrent();
      engines[sz].state        = TRADE_STATE_NORMAL;
      if(m_debugMode)
         PrintFormat("[Recovery] Engine created ticket=%d dir=%d",
                     e.ticket, engines[sz].direction);
   }

   virtual void OnPriceUpdate(PriceUpdateEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;

      ulong nowMs = GetTickCount64();
      if(nowMs - m_lastTrailingUpdate < (ulong)m_trailingThrottleMs) return;
      m_lastTrailingUpdate = nowMs;

      double atrValue = m_data.GetATRPoints();
      int sz = ArraySize(engines);

      for(int i = sz - 1; i >= 0; i--)
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

      int sz = ArraySize(engines);
      for(int i = 0; i < sz; i++)
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

         double  atrValue = m_data.GetATRPoints();
         MqlTick tick;
         SymbolInfoTick(_Symbol, tick);
         if(!DetectAndHandleFakeout(r, tick, atrValue))
            CheckRecoveryTimeout(r);
      }

      // RM-OPT-1: compact array after per-bar processing
      CompactEngines();
   }

   virtual void OnEmergencyStop(EmergencyStopEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      int sz = ArraySize(engines);
      for(int i = 0; i < sz; i++)
      {
         RecoveryEngine *r = engines[i];
         if(CheckPointer(r) != POINTER_INVALID && r.active)
            CloseActivePosition(r, "EmergencyStop");
      }
   }

   virtual void OnConfigReload(ConfigReloadEvent *e) override
   {
      IManager::OnConfigReload(e);
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
         PrintFormat("[Recovery] Max recovery reached ticket=%d. Closing.", r.mainTicket);
         CloseActivePosition(r, "MaxRecoveryAttempts");
         return;
      }

      r.lastKnownATR = m_data.GetATRPoints();
      r.SaveState();

      PositionUpdateEvent *update = new PositionUpdateEvent(r.mainTicket, e.price, e.atr, false);
      DispatchEvent(update);
   }

   virtual void OnSignalGenerated(SignalGeneratedEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID || !Config().exit_on_opposite) return;

      int sz = ArraySize(engines);
      for(int i = 0; i < sz; i++)
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

      double             curLot    = PositionGetDouble(POSITION_VOLUME);
      double             pcDist    = r.lastKnownATR * Config().partial_close_atr * _Point;
      ENUM_POSITION_TYPE type      = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double             openPrice = PositionGetDouble(POSITION_PRICE_OPEN);

      targetPrice = (type == POSITION_TYPE_BUY) ? openPrice + pcDist : openPrice - pcDist;
      closeLot    = m_data.NormalizeVolume(_Symbol, curLot * Config().partial_close_lot_pct);
      if(closeLot <= 0) return false;

      double curPrice = (type == POSITION_TYPE_BUY)
         ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
         : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      bool atTarget = (type == POSITION_TYPE_BUY)
         ? curPrice >= targetPrice
         : curPrice <= targetPrice;

      // RM-BUG-009: throttle prevents double-close in same tick window
      ulong nowMs = GetTickCount64();
      if(atTarget && !r.partialClosed &&
         (nowMs - m_lastPartialCloseMs >= (ulong)m_partialCloseThrottleMs))
      {
         if(m_trade.PositionClosePartial(ticket, closeLot))
         {
            r.partialClosed      = true;
            m_lastPartialCloseMs = nowMs;
            ClearEngineGVs(ticket);
            return true;
         }
      }
      return false;
   }

   RecoveryStats GetStats()             const { return m_stats; }
   int           GetActiveEngineCount() const
   {
      int cnt = 0;
      int sz  = ArraySize(engines);
      for(int i = 0; i < sz; i++)
      {
         RecoveryEngine *r = engines[i];
         if(CheckPointer(r) != POINTER_INVALID && r.active) cnt++;
      }
      return cnt;
   }
   int           GetTotalEngineCount()  const { return ArraySize(engines); }
};

#endif // __TRADE_RECOVERY_MANAGER_MQH__
