//+------------------------------------------------------------------+
//|                                   Trade/RecoveryManager.mqh      |
//|                          Copyright 2026, Agsicentre             |
//|    Position Recovery & Fakeout Management Module                 |
//|    Canonical production location — migrated from 8.RecoveryManager|
//|                                                                  |
//| BUG FIX HISTORY:                                                 |
//| v2.14 (Phase 6):                                                 |
//|  * All 5 'TODO Phase 6' magic literals replaced with m_cfg fields|
//|    - partialPct          → m_cfg.Risk.PartialClosePct            |
//|    - maxAttempts         → m_cfg.Risk.MaxRecoveryAttempts        |
//|    - cooldownBars        → m_cfg.Risk.RecoveryCooldownBars       |
//|    - recoveryEnabled     → m_cfg.Risk.RecoveryEnabled            |
//|    - MaxTradeDurationDays→ m_cfg.Risk.MaxTradeDurationDays       |
//|  * RecoveryEngine/FakeoutResult/ENUM_TRADE_STATE extracted to    |
//|    Trade/RecoveryEngine.mqh                                       |
//|  * ClearEngineGVs() replaced by r.ClearGVs(prefix) on engine    |
//|  * SaveState() now carries prefix (from BuildGVPrefix())         |
//|                                                                  |
//| v2.14 (prior commit):                                            |
//|  * BUG-001: include path ../12.MarketRegime.mqh→Data/MarketRegime|
//|  * BUG-002: RecoveryEngine defined (was missing)                 |
//|  * BUG-003: Config().xxx → m_cfg.Risk/Market/AI/Pattern.xxx      |
//|  * BUG-005: Init() calls IManager::Init(data,bus)                |
//|  * BUG-008: ClearEngineGVs only on CLOSE path                    |
//|  * BUG-009: avgRecoveryProfit off-by-one fixed                   |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "2.14"
#property strict

#ifndef __TRADE_RECOVERY_MANAGER_MQH__
#define __TRADE_RECOVERY_MANAGER_MQH__

#include <Trade/Trade.mqh>
#include "../Core/IManager.mqh"
#include "../Infra/DataManager.mqh"
#include "../Pattern/PatternManager.mqh"
#include "../Data/MarketRegime.mqh"
#include "RecoveryEngine.mqh"   // Phase 6: extracted types

//+------------------------------------------------------------------+
//| Constants                                                        |
//+------------------------------------------------------------------+
// RECOVERY_MAX_ENGINES is defined in RecoveryEngine.mqh

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
   RecoveryEngine   *engines[];
   CTrade            m_trade;

   int               m_recoveryScore;
   double            m_avgRecoveryTime;
   double            m_totalRecoveredLoss;
   RecoveryStats     m_stats;

   ulong             m_lastTrailingUpdate;
   int               m_trailingThrottleMs;

   ulong             m_lastPartialCloseMs;
   int               m_partialCloseThrottleMs;

   bool              m_regimeAware;
   double            m_minRegimeScore;

   // ─────────────────────────────────────────────────────────────────
   //  Private helpers
   // ─────────────────────────────────────────────────────────────────

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

   // RM-OPT-1: compact engines[] — remove DONE/inactive slots.
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
            int prevCount = m_stats.totalRecoveries;
            m_stats.totalRecoveries++;

            if(wasRecovered)
              {
               if(profitPoints > 0) m_stats.successfulRecoveries++;
               else                 m_stats.failedRecoveries++;

               m_stats.avgRecoveryProfit =
                  (prevCount > 0)
                  ? ((m_stats.avgRecoveryProfit * prevCount) + profitPoints)
                     / (double)(prevCount + 1)
                  : profitPoints;

               m_stats.lastRecoveryTime = GetTickCount64();

               if(r.entryTime > 0)
                 {
                  double recovMin = (double)(TimeCurrent() - r.entryTime) / 60.0;
                  m_avgRecoveryTime =
                     (prevCount > 0)
                     ? ((m_avgRecoveryTime * prevCount) + recovMin)
                        / (double)(prevCount + 1)
                     : recovMin;
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

      // Phase 6: use engine's own ClearGVs with prefix
      r.ClearGVs(BuildGVPrefix());
      r.Reset();
      r.active = false;

      PASREvent ev;
      ev.id       = EVENT_ID_POSITION_UPDATE;
      ev.priority = 10;
      DispatchEvent(ev);
     }

   bool DetectAndHandleFakeout(RecoveryEngine *r, const MqlTick &tick, double atrvalue)
     {
      if(CheckPointer(r) == POINTER_INVALID || !r.active) return false;
      if(!PositionSelectByTicket(r.mainTicket)) return false;

      ENUM_POSITION_TYPE ptype    = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double             curPrice = (ptype == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
      double             slPrice  = PositionGetDouble(POSITION_SL);

      double retraceThreshold = atrvalue * m_cfg.Risk.SLMultiplier * 0.3 * _Point;
      bool   nearSL = (ptype == POSITION_TYPE_BUY)
                    ? (slPrice > 0 && (curPrice - slPrice) < retraceThreshold)
                    : (slPrice > 0 && (slPrice - curPrice) < retraceThreshold);

      if(!nearSL) return false;

      FakeoutResult signal;
      signal.detected   = true;
      signal.level      = 2;
      signal.confidence = 0.65;
      signal.reason     = "NearSLRetrace";

      if(signal.level < 2) return false;

      double atr      = atrvalue * _Point;
      double slAdjust = atr * m_cfg.Risk.SLMultiplier * 0.5;
      double newSL    = (ptype == POSITION_TYPE_BUY)
         ? NormalizeDouble(slPrice - slAdjust, _Digits)
         : NormalizeDouble(slPrice + slAdjust, _Digits);

      double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      bool   slValid   = (ptype == POSITION_TYPE_BUY)
         ? (curPrice - newSL) > stopLevel
         : (newSL - curPrice) > stopLevel;

      if(!slValid)
        {
         if(m_debugMode) Log("[Fakeout] SL adjust rejected: too close to price");
         return false;
        }

      double currentTP = PositionGetDouble(POSITION_TP);
      if(m_trade.PositionModify(r.mainTicket, newSL, currentTP))
        {
         r.lastKnownATR    = atrvalue;
         r.recoveryAttempts++;
         m_stats.fakeoutsDetected++;
         m_stats.fakeoutsRecovered++;
         r.SaveState(BuildGVPrefix());   // Phase 6: persist with prefix
         if(m_debugMode)
            PrintFormat("[Fakeout] SL adjusted %d: %.5f->%.5f conf=%.2f attempt#%d",
                        r.mainTicket, slPrice, newSL, signal.confidence, r.recoveryAttempts);
         return true;
        }
      if(m_debugMode)
         PrintFormat("[Fakeout] Modify FAILED %d: err=%d (%s)",
                     r.mainTicket, GetLastError(), m_trade.ResultRetcodeDescription());
      return false;
     }

   void ProcessTrailingAndPartial(RecoveryEngine *r, const MqlTick &tick, double atrvalue)
     {
      if(!m_cfg.Risk.UseTrailingStop || !r.active) return;
      if(!PositionSelectByTicket(r.mainTicket)) return;

      ENUM_POSITION_TYPE ptype     = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double             openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double             curLot    = PositionGetDouble(POSITION_VOLUME);
      double             slPrice   = PositionGetDouble(POSITION_SL);
      double             tpPrice   = PositionGetDouble(POSITION_TP);
      double             curPrice  = (ptype == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
      double             atr       = atrvalue * _Point;

      double profitATR = (atr > 0)
         ? ((ptype == POSITION_TYPE_BUY)
              ? (curPrice - openPrice) / atr
              : (openPrice - curPrice) / atr)
         : 0.0;

      double newSL    = slPrice;
      double lockATR  = m_cfg.Risk.BreakEvenATRMult;
      double trailATR = m_cfg.Risk.TrailATRMult;

      if(ptype == POSITION_TYPE_BUY)
        {
         if(profitATR >= lockATR)  newSL = MathMax(newSL, openPrice);
         if(profitATR >= trailATR) newSL = MathMax(newSL, curPrice - atr * trailATR);
        }
      else
        {
         if(profitATR >= lockATR)
           {
            newSL = (newSL == 0) ? openPrice : MathMin(newSL, openPrice);
           }
         if(profitATR >= trailATR)
           {
            double dynSL = NormalizeDouble(curPrice + atr * trailATR, _Digits);
            newSL = (newSL == 0) ? dynSL : MathMin(newSL, dynSL);
           }
        }

      // Phase 6: partial close uses real config field (no more magic literal)
      double partialPct = m_cfg.Risk.PartialClosePct;   // was: 0.5 hardcoded
      double partialATR = m_cfg.Risk.TPMultiplier * 0.5;

      if(partialPct > 0.0 && profitATR >= partialATR && !r.partialClosed)
        {
         ulong nowMs = GetTickCount64();
         if(nowMs - m_lastPartialCloseMs >= (ulong)m_partialCloseThrottleMs)
           {
            double closeLot = m_data.NormalizeVolume(_Symbol, curLot * partialPct);
            if(closeLot > 0 && m_trade.PositionClosePartial(r.mainTicket, closeLot))
              {
               r.partialClosed      = true;
               m_lastPartialCloseMs = nowMs;
               r.SaveState(BuildGVPrefix());
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
      // Phase 6: use real config field
      int maxAttempts  = m_cfg.Risk.MaxRecoveryAttempts;  // was: 3 hardcoded
      int cooldownBars = m_cfg.Risk.RecoveryCooldownBars; // was: 5 hardcoded

      if(r.recoveryAttempts >= maxAttempts)
        {
         if(m_debugMode)
            PrintFormat("[Recovery] Max attempts (%d/%d) for %d",
                        r.recoveryAttempts, maxAttempts, r.mainTicket);
         return false;
        }

      r.state = TRADE_STATE_RECOVERY;
      r.recoveryAttempts++;
      r.recoveryCooldownExpiry = TimeCurrent()
         + ((datetime)cooldownBars * PeriodSeconds(_Period));
      r.SaveState(BuildGVPrefix());

      if(m_debugMode)
         PrintFormat("[Recovery] Attempt %d/%d ticket=%d",
                     r.recoveryAttempts, maxAttempts, r.mainTicket);

      PASREvent ev;
      ev.id       = EVENT_ID_RECOVERY_OPPORTUNITY;
      ev.priority = 20;
      DispatchEvent(ev);
      return true;
     }

   void CheckRecoveryTimeout(RecoveryEngine *r)
     {
      int  maxAttempts  = m_cfg.Risk.MaxRecoveryAttempts;
      int  cooldownBars = m_cfg.Risk.RecoveryCooldownBars;
      bool recovEnabled = m_cfg.Risk.RecoveryEnabled;     // Phase 6

      if(r.recoveryAttempts >= maxAttempts)
        {
         PrintFormat("[Recovery] Max attempts %d/%d ticket=%d. Abandoning.",
                     r.recoveryAttempts, maxAttempts, r.mainTicket);
         r.ClearGVs(BuildGVPrefix());
         r.Reset();
         return;
        }
      if(r.state != TRADE_STATE_NORMAL) return;
      if(!PositionSelectByTicket(r.mainTicket)) return;

      ENUM_POSITION_TYPE ptype    = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double             slPrice  = PositionGetDouble(POSITION_SL);
      double             curPrice = (ptype == POSITION_TYPE_BUY)
         ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
         : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      bool slHit = (ptype == POSITION_TYPE_BUY)
         ? (slPrice > 0 && curPrice <= slPrice)
         : (slPrice > 0 && curPrice >= slPrice);
      if(!slHit) return;

      bool cooldownActive = (r.recoveryCooldownExpiry > 0 &&
                             TimeCurrent() < r.recoveryCooldownExpiry);
      if(cooldownActive) return;

      if(recovEnabled && r.recoveryAttempts < maxAttempts)
        {
         r.recoveryCooldownExpiry = TimeCurrent()
            + ((datetime)cooldownBars * PeriodSeconds(_Period));
         r.lastKnownATR = m_data.GetATRPoints();
         r.SaveState(BuildGVPrefix());
         AttemptRecovery(r);
        }
      else
        {
         PrintFormat("[Recovery] SL hit ticket=%d, recovery disabled or maxed. Closing.",
                     r.mainTicket);
         r.ClearGVs(BuildGVPrefix());
         r.state = TRADE_STATE_DONE;
         r.Reset();
        }
     }

   void CheckExpiryAndForcedClose(RecoveryEngine *r)
     {
      int maxDays = m_cfg.Risk.MaxTradeDurationDays;  // Phase 6: was 0 hardcoded
      if(maxDays <= 0 || r.entryTime == 0) return;

      if(TimeCurrent() > r.entryTime + ((datetime)maxDays * 86400))
        {
         PrintFormat("[Recovery] Trade %d expired (%d days). Force closing.",
                     r.mainTicket, maxDays);
         CloseActivePosition(r, "MaxDurationExpiry");
        }
     }

public:
   RecoveryManager()
      : IManager(),
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

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      m_trade.SetExpertMagicNumber((ulong)m_cfg.MagicNumber);
      return true;
     }

   void SetTrailingThrottle(int ms)     { if(ms > 0) m_trailingThrottleMs = ms; }
   void SetPartialCloseThrottle(int ms) { if(ms > 0) m_partialCloseThrottleMs = ms; }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_POSITION_UPDATE);
      AddEvent(EVENT_ID_PRICE_UPDATE);
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_RECOVERY_OPPORTUNITY);
      AddEvent(EVENT_ID_EMERGENCY_STOP);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
     }

   virtual void OnNewBar() override
     {
      int sz = ArraySize(engines);
      for(int i = 0; i < sz; i++)
        {
         RecoveryEngine *r = engines[i];
         if(CheckPointer(r) == POINTER_INVALID || !r.active) continue;
         if(r.state != TRADE_STATE_NORMAL) continue;

         if(!PositionSelectByTicket(r.mainTicket))
           {
            r.ClearGVs(BuildGVPrefix());
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

      CompactEngines();
     }

   virtual void OnPriceUpdate() override
     {
      ulong nowMs = GetTickCount64();
      if(nowMs - m_lastTrailingUpdate < (ulong)m_trailingThrottleMs) return;
      m_lastTrailingUpdate = nowMs;

      double  atrValue = m_data.GetATRPoints();
      MqlTick tick;
      SymbolInfoTick(_Symbol, tick);

      int sz = ArraySize(engines);
      for(int i = sz - 1; i >= 0; i--)
        {
         RecoveryEngine *r = engines[i];
         if(CheckPointer(r) == POINTER_INVALID || !r.active) continue;

         if(!PositionSelectByTicket(r.mainTicket))
           {
            r.Reset();
            r.active = false;
            continue;
           }

         ProcessTrailingAndPartial(r, tick, atrValue);
         CheckExpiryAndForcedClose(r);
        }
     }

   void OnTradeOpen(ulong ticket, int direction, double entryPrice)
     {
      if(!PositionSelectByTicket(ticket))
        {
         if(m_debugMode)
            PrintFormat("[Recovery] OnTradeOpen: ticket=%d not found, skipping", ticket);
         return;
        }

      int idx = FindEngineIndex(ticket);
      if(idx >= 0) return;

      if(ArraySize(engines) >= RECOVERY_MAX_ENGINES)
        {
         PrintFormat("[Recovery] WARNING: MAX_ENGINES (%d) reached. ticket=%d not tracked.",
                     RECOVERY_MAX_ENGINES, ticket);
         return;
        }

      int sz = ArraySize(engines);
      ArrayResize(engines, sz + 1);
      engines[sz] = new RecoveryEngine();
      engines[sz].mainTicket = ticket;
      engines[sz].active     = true;
      engines[sz].entryPrice = entryPrice;
      engines[sz].direction  = direction;
      engines[sz].entryTime  = TimeCurrent();
      engines[sz].state      = TRADE_STATE_NORMAL;
      engines[sz].SaveState(BuildGVPrefix());   // persist immediately

      if(m_debugMode)
         PrintFormat("[Recovery] Engine created ticket=%d dir=%d", ticket, direction);
     }

   void OnTradeClose(ulong ticket)
     {
      int idx = FindEngineIndex(ticket);
      if(idx < 0) return;
      engines[idx].ClearGVs(BuildGVPrefix());   // Phase 6: engine clears own GVs
      engines[idx].Reset();
      engines[idx].active = false;
      if(m_debugMode)
         PrintFormat("[Recovery] Engine deactivated for closed ticket=%d", ticket);
     }

   virtual void OnConfigReload() override
     {
      IManager::OnConfigReload();
      m_trade.SetExpertMagicNumber((ulong)m_cfg.MagicNumber);
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
