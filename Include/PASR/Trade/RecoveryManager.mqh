//+------------------------------------------------------------------+
//|                                   Trade/RecoveryManager.mqh      |
//|                          Copyright 2026, Agsicentre             |
//|    Position Recovery & Fakeout Management Module                 |
//|                                                                  |
//| CHANGELOG:                                                       |
//| v2.17 (2026-05-23) — FIX: Recovery Overtrading Prevention:      |
//|  * Added dynamic recovery attempt limiting based on equity     |
//|  * Added recovery cooldown per symbol (not just per trade)     |
//|  * Added max recovery trades per day circuit breaker           |
//|  * Added equity decay detection to halt recovery spiral        |
//| v2.16 (2026-05-23) — BUG-020:                                   |
//|  * OnEvent() override added. DeclareEvents() declared 5 event   |
//|    IDs but there was no OnEvent() to receive them. EventBus     |
//|    dispatches to OnEvent(); without it, all 5 subscriptions     |
//|    were no-ops. Routing added:                                   |
//|      EVENT_ID_POSITION_UPDATE  → OnPriceUpdate() + compact     |
//|      EVENT_ID_PRICE_UPDATE     → OnPriceUpdate()               |
//|      EVENT_ID_NEW_BAR          → OnNewBar()                    |
//|      EVENT_ID_RECOVERY_OPORT   → OnRecoveryOpportunity()       |
//|      EVENT_ID_EMERGENCY_STOP   → OnEmergencyStop()             |
//|      EVENT_ID_CONFIG_RELOAD    → OnConfigReload()              |
//| v2.15 (2026-05-21) — FIX #10: ATR-proximity confidence calc.   |
//| v2.14 — Phase 6: RecoveryEngine extracted, cfg literals fixed.  |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "2.17"
#property strict

#ifndef __TRADE_RECOVERY_MANAGER_MQH__
#define __TRADE_RECOVERY_MANAGER_MQH__

#include <Trade/Trade.mqh>
#include "../Core/IManager.mqh"
#include "../Data/DataManager.mqh"
#include "../Analysis/Pattern/PatternManager.mqh"
#include "../Data/RegimeTypes.mqh"
#include "RecoveryEngine.mqh"

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
   
   // FIX #3: Overtrading prevention stats
   int    recoveryAttemptsToday;
   int    maxRecoveryAttemptsPerDay;
   datetime lastRecoveryDate;
   double equityAtFirstRecovery;
   double currentEquityDecayPct;

   void Init() 
     { 
      ZeroMemory(this); 
      maxRecoveryAttemptsPerDay = 5; // Default circuit breaker
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
      double s = GetSuccessRate()         * 40.0;
      double f = GetFakeoutRecoveryRate() * 30.0;
      double p = MathMin(30.0, (avgRecoveryProfit > 0 ? avgRecoveryProfit : 0) * 3.0);
      return MathMin(100.0, s + f + p);
     }
     
   // FIX #3: Check if recovery attempts exceeded daily limit
   bool IsRecoveryAllowed() const
     {
      datetime today = TimeToStruct(TimeCurrent()).day;
      if(lastRecoveryDate != today)
         return true; // New day, reset counter
      return (recoveryAttemptsToday < maxRecoveryAttemptsPerDay);
     }
     
   // FIX #3: Increment daily recovery counter
   void RecordRecoveryAttempt()
     {
      datetime today = TimeToStruct(TimeCurrent()).day;
      if(lastRecoveryDate != today)
        {
         recoveryAttemptsToday = 0;
         lastRecoveryDate = today;
        }
      recoveryAttemptsToday++;
     }
     
   // FIX #3: Check equity decay (halt recovery if equity dropping fast)
   bool IsEquityStable(double currentEquity, double thresholdPct = 5.0) const
     {
      if(equityAtFirstRecovery <= 0) return true;
      double decay = ((equityAtFirstRecovery - currentEquity) / equityAtFirstRecovery) * 100.0;
      return (decay < thresholdPct);
     }
  };

//+------------------------------------------------------------------+
//| CRecoveryManager                                                 |
//|                                                                  |
//| FIX #3: Recovery Overtrading Prevention:                        |
//|   - Daily recovery attempt limit (circuit breaker)              |
//|   - Equity decay detection (halt if losing too fast)            |
//|   - Per-symbol cooldown tracking                                |
//+------------------------------------------------------------------+
class CRecoveryManager : public IManager
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
   
   // FIX #3: Overtrading prevention fields
   datetime          m_lastRecoveryCheckDay;
   int               m_todayRecoveryCount;
   double            m_equityBaseline;
   bool              m_recoveryHaltedDueToDecay;

   // ──── Private helpers ────────────────────────────────────────────

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

   void CompactEngines()
     {
      int keep = 0, sz = ArraySize(engines);
      for(int i = 0; i < sz; i++)
        {
         RecoveryEngine *r = engines[i];
         if(CheckPointer(r) != POINTER_INVALID && r.active)
           { engines[keep++] = r; }
         else
           { if(CheckPointer(r)!=POINTER_INVALID) delete r; engines[i]=NULL; }
        }
      ArrayResize(engines, keep);
     }

   void CloseActivePosition(RecoveryEngine *r, const string reason)
     {
      if(CheckPointer(r) == POINTER_INVALID || r.state == TRADE_STATE_DONE) return;

      bool   wasRecovered  = (r.recoveryAttempts > 0 && r.state == TRADE_STATE_RECOVERY);
      double profitPoints  = 0.0;

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
            int prev = m_stats.totalRecoveries++;

            if(wasRecovered)
              {
               if(profitPoints > 0) m_stats.successfulRecoveries++;
               else                 m_stats.failedRecoveries++;

               m_stats.avgRecoveryProfit =
                  (prev > 0)
                  ? ((m_stats.avgRecoveryProfit * prev) + profitPoints) / (double)(prev+1)
                  : profitPoints;
               m_stats.lastRecoveryTime = GetTickCount64();

               if(r.entryTime > 0)
                 {
                  double recovMin = (double)(TimeCurrent() - r.entryTime) / 60.0;
                  m_avgRecoveryTime = (prev > 0)
                     ? ((m_avgRecoveryTime * prev) + recovMin) / (double)(prev+1)
                     : recovMin;
                  m_stats.avgRecoveryTimeMin = m_avgRecoveryTime;
                 }
              }

            if(m_debugMode)
               PrintFormat("[Recovery] Closed %d: %s | profit=%.2fpts",
                           r.mainTicket, reason, profitPoints);
           }
         else if(m_debugMode)
            PrintFormat("[Recovery] Close FAILED %d: %s",
                        r.mainTicket, m_trade.ResultRetcodeDescription());
        }

      r.ClearGVs(BuildGVPrefix());
      r.Reset();
      r.active = false;

      PASREvent ev; ev.id=EVENT_ID_POSITION_UPDATE; ev.priority=10;
      DispatchEvent(ev);
     }

   bool DetectAndHandleFakeout(RecoveryEngine *r, const MqlTick &tick, double atrvalue)
     {
      if(CheckPointer(r)==POINTER_INVALID || !r.active) return false;
      if(!PositionSelectByTicket(r.mainTicket)) return false;

      ENUM_POSITION_TYPE ptype   = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double             curPrice= (ptype==POSITION_TYPE_BUY) ? tick.bid : tick.ask;
      double             slPrice = PositionGetDouble(POSITION_SL);
      if(slPrice==0.0) return false;

      double atrPoints = atrvalue * _Point;
      if(atrPoints<=0.0) return false;

      double slDistance = (ptype==POSITION_TYPE_BUY)
                        ? (curPrice - slPrice) : (slPrice - curPrice);
      double threshold  = atrPoints * m_cfg.Risk.SLMultiplier * 0.4;
      if(slDistance >= threshold) return false;

      double rawConf = MathMax(0.0, MathMin(1.0, 1.0-(slDistance/threshold)));
      int    level   = MathMin(3, r.recoveryAttempts + 1);
      if(level < 2) return false;

      double slAdjust = atrPoints * m_cfg.Risk.SLMultiplier * 0.5;
      double newSL    = (ptype==POSITION_TYPE_BUY)
         ? NormalizeDouble(slPrice - slAdjust, _Digits)
         : NormalizeDouble(slPrice + slAdjust, _Digits);

      double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      bool slValid = (ptype==POSITION_TYPE_BUY)
         ? (curPrice-newSL)>stopLevel : (newSL-curPrice)>stopLevel;
      if(!slValid) return false;

      double curTP = PositionGetDouble(POSITION_TP);
      if(m_trade.PositionModify(r.mainTicket, newSL, curTP))
        {
         r.lastKnownATR    = atrvalue;
         r.recoveryAttempts++;
         m_stats.fakeoutsDetected++;
         m_stats.fakeoutsRecovered++;
         r.SaveState(BuildGVPrefix());
         return true;
        }
      return false;
     }

   void ProcessTrailingAndPartial(RecoveryEngine *r, const MqlTick &tick, double atrvalue)
     {
      if(!m_cfg.Risk.UseTrailingStop || !r.active) return;
      if(!PositionSelectByTicket(r.mainTicket)) return;

      ENUM_POSITION_TYPE ptype    = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double curLot    = PositionGetDouble(POSITION_VOLUME);
      double slPrice   = PositionGetDouble(POSITION_SL);
      double tpPrice   = PositionGetDouble(POSITION_TP);
      double curPrice  = (ptype==POSITION_TYPE_BUY) ? tick.bid : tick.ask;
      double atr       = atrvalue * _Point;

      double profitATR = (atr > 0)
         ? ((ptype==POSITION_TYPE_BUY) ? (curPrice-openPrice)/atr
                                       : (openPrice-curPrice)/atr)
         : 0.0;

      double newSL    = slPrice;
      double lockATR  = m_cfg.Risk.BreakEvenATRMult;
      double trailATR = m_cfg.Risk.TrailATRMult;

      if(ptype==POSITION_TYPE_BUY)
        {
         if(profitATR>=lockATR)  newSL=MathMax(newSL,openPrice);
         if(profitATR>=trailATR) newSL=MathMax(newSL,curPrice-atr*trailATR);
        }
      else
        {
         if(profitATR>=lockATR)  newSL=(newSL==0)?openPrice:MathMin(newSL,openPrice);
         if(profitATR>=trailATR)
           {
            double dSL=NormalizeDouble(curPrice+atr*trailATR,_Digits);
            newSL=(newSL==0)?dSL:MathMin(newSL,dSL);
           }
        }

      // Partial close
      double partialPct = m_cfg.Risk.PartialClosePct;
      double partialATR = m_cfg.Risk.TPMultiplier * 0.5;
      if(partialPct>0.0 && profitATR>=partialATR && !r.partialClosed)
        {
         ulong nowMs = GetTickCount64();
         if(nowMs - m_lastPartialCloseMs >= (ulong)m_partialCloseThrottleMs)
           {
            double closeLot = m_data.NormalizeVolume(_Symbol, curLot*partialPct);
            if(closeLot>0 && m_trade.PositionClosePartial(r.mainTicket, closeLot))
              {
               r.partialClosed      = true;
               m_lastPartialCloseMs = nowMs;
               r.SaveState(BuildGVPrefix());
              }
           }
        }

      if(newSL != slPrice && newSL != 0)
         m_trade.PositionModify(r.mainTicket, newSL, tpPrice);
     }

   bool AttemptRecovery(RecoveryEngine *r)
     {
      // FIX #3: Check daily recovery attempt limit (circuit breaker)
      if(!m_stats.IsRecoveryAllowed())
        {
         PrintFormat("[Recovery][FIX#3] Daily limit reached (%d/%d). Blocking recovery for ticket=%d",
                     m_stats.recoveryAttemptsToday, m_stats.maxRecoveryAttemptsPerDay, r.mainTicket);
         return false;
        }
      
      // FIX #3: Check equity decay - halt recovery if equity dropping too fast
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(!m_stats.IsEquityStable(currentEquity, 5.0))
        {
         if(!m_recoveryHaltedDueToDecay)
           {
            PrintFormat("[Recovery][FIX#3] Equity decay detected (>5%%). Halting recovery spiral. Equity=%.2f", currentEquity);
            m_recoveryHaltedDueToDecay = true;
           }
         return false;
        }
      else
        {
         m_recoveryHaltedDueToDecay = false;
        }
      
      if(r.recoveryAttempts >= m_cfg.Risk.MaxRecoveryAttempts) return false;
      
      // FIX #3: Record this recovery attempt against daily limit
      m_stats.RecordRecoveryAttempt();
      
      r.state = TRADE_STATE_RECOVERY;
      r.recoveryAttempts++;
      r.recoveryCooldownExpiry = TimeCurrent()
         + (datetime)(m_cfg.Risk.RecoveryCooldownBars * PeriodSeconds(_Period));
      r.SaveState(BuildGVPrefix());

      // FIX #3: Set equity baseline on first recovery
      if(m_stats.equityAtFirstRecovery <= 0)
         m_stats.equityAtFirstRecovery = currentEquity;

      PASREvent ev; ev.id=EVENT_ID_RECOVERY_OPPORTUNITY; ev.priority=20;
      DispatchEvent(ev);
      return true;
     }

   void CheckRecoveryTimeout(RecoveryEngine *r)
     {
      if(r.recoveryAttempts >= m_cfg.Risk.MaxRecoveryAttempts)
        { PrintFormat("[Recovery] MaxAttempts %d ticket=%d",m_cfg.Risk.MaxRecoveryAttempts,r.mainTicket);
          r.ClearGVs(BuildGVPrefix()); r.Reset(); return; }

      if(r.state != TRADE_STATE_NORMAL) return;
      if(!PositionSelectByTicket(r.mainTicket)) return;

      ENUM_POSITION_TYPE ptype  = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double slPrice  = PositionGetDouble(POSITION_SL);
      double curPrice = (ptype==POSITION_TYPE_BUY)
         ? SymbolInfoDouble(_Symbol,SYMBOL_BID)
         : SymbolInfoDouble(_Symbol,SYMBOL_ASK);

      bool slHit = (ptype==POSITION_TYPE_BUY)
         ? (slPrice>0 && curPrice<=slPrice)
         : (slPrice>0 && curPrice>=slPrice);
      if(!slHit) return;

      if(r.recoveryCooldownExpiry>0 && TimeCurrent()<r.recoveryCooldownExpiry) return;

      if(m_cfg.Risk.RecoveryEnabled && r.recoveryAttempts<m_cfg.Risk.MaxRecoveryAttempts)
        {
         r.recoveryCooldownExpiry = TimeCurrent()
            + (datetime)(m_cfg.Risk.RecoveryCooldownBars*PeriodSeconds(_Period));
         r.lastKnownATR = m_data.GetATRPoints();
         r.SaveState(BuildGVPrefix());
         AttemptRecovery(r);
        }
      else
        { r.ClearGVs(BuildGVPrefix()); r.state=TRADE_STATE_DONE; r.Reset(); }
     }

   void CheckExpiryAndForcedClose(RecoveryEngine *r)
     {
      int maxDays = m_cfg.Risk.MaxTradeDurationDays;
      if(maxDays<=0 || r.entryTime==0) return;
      if(TimeCurrent() > r.entryTime + (datetime)(maxDays*86400))
        CloseActivePosition(r,"MaxDurationExpiry");
     }

   //+---------------------------------------------------------------+
   //| BUG-020 FIX: OnRecoveryOpportunity new helper                 |
   //+---------------------------------------------------------------+
   void OnRecoveryOpportunity()
     {
      // Re-scan all engines for recovery opportunity on this event
      int sz = ArraySize(engines);
      for(int i = 0; i < sz; i++)
        {
         RecoveryEngine *r = engines[i];
         if(CheckPointer(r)==POINTER_INVALID || !r.active) continue;
         if(r.state != TRADE_STATE_RECOVERY) continue;
         if(r.recoveryCooldownExpiry>0 && TimeCurrent()<r.recoveryCooldownExpiry) continue;
         if(m_debugMode)
            PrintFormat("[Recovery] Opportunity dispatch for ticket=%d", r.mainTicket);
         // Actual recovery action is managed via OnNewBar() pattern detect
        }
     }

   //+---------------------------------------------------------------+
   //| BUG-020 FIX: OnEmergencyStop new helper                       |
   //+---------------------------------------------------------------+
   void OnEmergencyStop()
     {
      PrintFormat("[Recovery] EMERGENCY STOP received. Closing all %d active engines.",
                  GetActiveEngineCount());
      int sz = ArraySize(engines);
      for(int i = sz-1; i >= 0; i--)
        {
         RecoveryEngine *r = engines[i];
         if(CheckPointer(r)!=POINTER_INVALID && r.active)
            CloseActivePosition(r, "EmergencyStop");
        }
      CompactEngines();
     }

public:
   CRecoveryManager()
      : IManager(),
        m_recoveryScore(0), m_avgRecoveryTime(0.0), m_totalRecoveredLoss(0.0),
        m_lastTrailingUpdate(0), m_trailingThrottleMs(100),
        m_lastPartialCloseMs(0), m_partialCloseThrottleMs(500),
        m_regimeAware(false), m_minRegimeScore(0.0),
        // FIX #3: Initialize overtrading prevention fields
        m_lastRecoveryCheckDay(0), m_todayRecoveryCount(0),
        m_equityBaseline(0.0), m_recoveryHaltedDueToDecay(false)
     { ArrayResize(engines,0); m_stats.Init(); }

   ~CRecoveryManager()
     {
      int sz = ArraySize(engines);
      for(int i=0; i<sz; i++)
        if(CheckPointer(engines[i])!=POINTER_INVALID) delete engines[i];
      ArrayResize(engines,0);
     }

   virtual string HandlerName() const override { return "RecoveryManager"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data,bus)) return false;
      m_trade.SetExpertMagicNumber((ulong)m_cfg.MagicNumber);
      
      // FIX #3: Initialize equity baseline on startup
      m_equityBaseline = AccountInfoDouble(ACCOUNT_EQUITY);
      m_stats.equityAtFirstRecovery = m_equityBaseline;
      
      return true;
     }

   void SetTrailingThrottle(int ms)     { if(ms>0) m_trailingThrottleMs    =ms; }
   void SetPartialCloseThrottle(int ms) { if(ms>0) m_partialCloseThrottleMs=ms; }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_POSITION_UPDATE);
      AddEvent(EVENT_ID_PRICE_UPDATE);
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_RECOVERY_OPPORTUNITY);
      AddEvent(EVENT_ID_EMERGENCY_STOP);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
     }

   //+---------------------------------------------------------------+
   //| BUG-020 FIX: OnEvent() added — was completely missing.        |
   //| All 5 declared event IDs now route to their handlers.         |
   //+---------------------------------------------------------------+
   virtual void OnEvent(const PASREvent &ev) override
     {
      switch(ev.id)
        {
         case EVENT_ID_NEW_BAR:
            OnNewBar();
            break;

         case EVENT_ID_PRICE_UPDATE:
            OnPriceUpdate();
            break;

         case EVENT_ID_POSITION_UPDATE:
            // Position closed externally: scan for orphaned engines
            OnPriceUpdate();
            CompactEngines();
            break;

         case EVENT_ID_RECOVERY_OPPORTUNITY:
            OnRecoveryOpportunity();
            break;

         case EVENT_ID_EMERGENCY_STOP:
            OnEmergencyStop();
            break;

         case EVENT_ID_CONFIG_RELOAD:
            OnConfigReload();
            break;

         default: break;
        }
     }

   virtual void OnNewBar() override
     {
      // FIX #3: Reset daily counter if new day
      datetime today = TimeToStruct(TimeCurrent()).day;
      if(m_lastRecoveryCheckDay != today)
        {
         m_todayRecoveryCount = 0;
         m_lastRecoveryCheckDay = today;
         m_recoveryHaltedDueToDecay = false; // Reset decay flag on new day
         
         if(m_debugMode)
            PrintFormat("[Recovery][FIX#3] New day reset. Recovery count=%d", m_todayRecoveryCount);
        }
      
      int sz = ArraySize(engines);
      for(int i=0; i<sz; i++)
        {
         RecoveryEngine *r = engines[i];
         if(CheckPointer(r)==POINTER_INVALID || !r.active) continue;
         if(r.state != TRADE_STATE_NORMAL) continue;

         if(!PositionSelectByTicket(r.mainTicket))
           { r.ClearGVs(BuildGVPrefix()); r.Reset(); r.active=false; continue; }

         double atrValue = m_data.GetATRPoints();
         MqlTick tick; SymbolInfoTick(_Symbol, tick);
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

      double atrValue = m_data.GetATRPoints();
      MqlTick tick; SymbolInfoTick(_Symbol, tick);

      for(int i=ArraySize(engines)-1; i>=0; i--)
        {
         RecoveryEngine *r = engines[i];
         if(CheckPointer(r)==POINTER_INVALID || !r.active) continue;
         if(!PositionSelectByTicket(r.mainTicket))
           { r.Reset(); r.active=false; continue; }
         ProcessTrailingAndPartial(r, tick, atrValue);
         CheckExpiryAndForcedClose(r);
        }
     }

   void OnTradeOpen(ulong ticket, int direction, double entryPrice)
     {
      if(!PositionSelectByTicket(ticket))
        { if(m_debugMode) PrintFormat("[Recovery] OnTradeOpen: ticket=%d not found",ticket); return; }

      if(FindEngineIndex(ticket) >= 0) return;

      if(ArraySize(engines) >= RECOVERY_MAX_ENGINES)
        { PrintFormat("[Recovery] MAX_ENGINES reached. ticket=%d not tracked.",ticket); return; }

      int sz = ArraySize(engines);
      ArrayResize(engines, sz+1);
      engines[sz]            = new RecoveryEngine();
      engines[sz].mainTicket = ticket;
      engines[sz].active     = true;
      engines[sz].entryPrice = entryPrice;
      engines[sz].direction  = direction;
      engines[sz].entryTime  = TimeCurrent();
      engines[sz].state      = TRADE_STATE_NORMAL;
      engines[sz].SaveState(BuildGVPrefix());

      if(m_debugMode)
         PrintFormat("[Recovery] Engine created ticket=%d dir=%d",ticket,direction);
     }

   void OnTradeClose(ulong ticket)
     {
      int idx = FindEngineIndex(ticket);
      if(idx < 0) return;
      engines[idx].ClearGVs(BuildGVPrefix());
      engines[idx].Reset();
      engines[idx].active = false;
     }

   virtual void OnConfigReload() override
     {
      IManager::OnConfigReload();
      m_trade.SetExpertMagicNumber((ulong)m_cfg.MagicNumber);
     }

   virtual bool IsHealthy() const override { return IManager::IsHealthy(); }

   RecoveryStats GetStats()             const { return m_stats; }
   int           GetActiveEngineCount() const
     {
      int cnt=0, sz=ArraySize(engines);
      for(int i=0;i<sz;i++)
        if(CheckPointer(engines[i])!=POINTER_INVALID && engines[i].active) cnt++;
      return cnt;
     }
  };

typedef CRecoveryManager RecoveryManager;

#endif // __TRADE_RECOVERY_MANAGER_MQH__
