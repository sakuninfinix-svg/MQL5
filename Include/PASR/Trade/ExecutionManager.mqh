//+------------------------------------------------------------------+
//|                                   Trade/ExecutionManager.mqh    |
//|                          Copyright 2026, Agsicentre             |
//|   PASR Layer 5 — Trade: Order Execution & Trade Management      |
//|   Migrated from: 6.ExecutionManager.mqh v2.02                   |
//|                                                                  |
//|   LAYER RULES (enforced):                                        |
//|     ✅ Depends on: Core/, Infra/ only                            |
//|     ❌ Must NOT include: Signal/, Analysis/, AI/, UI/            |
//|     ✅ GV keys include ACCOUNT_LOGIN (PASR-BUG-001 fix)          |
//|     ✅ ScavengePendingGVs() runs once per bar (PASR-BUG-002 fix) |
//|     ✅ Dashboard throttled to 1 Hz (PASR-BUG-004 fix)            |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "3.00"
#property strict

#ifndef __TRADE_EXECUTION_MANAGER_MQH__
#define __TRADE_EXECUTION_MANAGER_MQH__

#include <Trade/Trade.mqh>
#include "../IManager.mqh"
#include "../Infra/DataManager.mqh"
#include "TradePlan.mqh"

//+------------------------------------------------------------------+
//| ExecutionManager — L5 Trade                                     |
//+------------------------------------------------------------------+
class ExecutionManager : public IManager
{
private:
   CTrade   m_trade;
   string   m_symbol;
   bool     m_tradingAllowed;
   datetime m_lastScavengeBar;   // FIX PASR-BUG-002: once-per-bar guard
   ulong    m_lastRenderUs;      // FIX PASR-BUG-004: 1 Hz dashboard throttle

   //--- GV key helpers (account-scoped: PASR-BUG-001)
   string MakePendingPrefix(ulong tsID) const
   {
      return "PASR_PEND_"
           + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_"
           + IntegerToString(Config().magic) + "_"
           + m_symbol + "_"
           + IntegerToString(tsID) + "_";
   }

   void SavePendingState(ulong tsID, const TradePlan &plan, double zonePrice, double slMult) const
   {
      string p = MakePendingPrefix(tsID);
      GlobalVariableSet(p + "ts", (double)TimeCurrent());
      GlobalVariableSet(p + "tp", plan.tp);
      GlobalVariableSet(p + "zp", zonePrice);
      GlobalVariableSet(p + "sm", slMult);
   }

   // FIX EX-BUG-FIX-2: safe per-key deletion, no GlobalVariablesDeleteAll
   void DeletePendingStateById(ulong tsID) const
   {
      string prefix = MakePendingPrefix(tsID);
      for(int i = GlobalVariablesTotal() - 1; i >= 0; i--)
      {
         string name = GlobalVariableName(i);
         if(StringFind(name, prefix) == 0) GlobalVariableDel(name);
      }
   }

   // FIX PASR-BUG-002: two-pass deferred delete, runs once per bar
   void ScavengePendingGVs()
   {
      datetime bar = iTime(m_symbol, _Period, 0);
      if(bar == m_lastScavengeBar) return;
      m_lastScavengeBar = bar;

      string pattern = "PASR_PEND_"
                     + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_"
                     + IntegerToString(Config().magic) + "_"
                     + m_symbol + "_";
      int total = GlobalVariablesTotal();

      string liveIDs[];  string staleKeys[];
      int    liveCount = 0, staleCount = 0;

      for(int i = 0; i < total; i++)
      {
         string gvName = GlobalVariableName(i);
         if(StringFind(gvName, pattern) != 0) continue;
         string rest    = StringSubstr(gvName, StringLen(pattern));
         int    sepPos  = StringFind(rest, "_");
         string tsID_s  = (sepPos >= 0) ? StringSubstr(rest, 0, sepPos) : rest;

         bool skip = false;
         for(int j = 0; j < liveCount  && !skip; j++) if(liveIDs[j] == tsID_s) skip = true;
         for(int j = 0; j < staleCount && !skip; j++)
            if(StringFind(staleKeys[j], pattern + tsID_s) == 0) skip = true;
         if(skip) continue;

         datetime ts = (datetime)GlobalVariableGet(pattern + tsID_s + "_ts");
         if(ts > 0 && TimeCurrent() - ts > 86400)
         {
            for(int k = i; k < total; k++)
            {
               string kn = GlobalVariableName(k);
               if(StringFind(kn, pattern + tsID_s + "_") == 0)
               { ArrayResize(staleKeys, staleCount + 1); staleKeys[staleCount++] = kn; }
            }
         }
         else { ArrayResize(liveIDs, liveCount + 1); liveIDs[liveCount++] = tsID_s; }
      }
      for(int i = 0; i < staleCount; i++)
      {
         GlobalVariableDel(staleKeys[i]);
         if(m_debugMode) PrintFormat("[Execution] Scavenged stale GV: %s", staleKeys[i]);
      }
   }

   bool PlaceOrder(const TradePlan &plan, ulong &outTicket)
   {
      outTicket = 0;
      if(!m_tradingAllowed) return false;
      if(!plan.IsValid()) { if(m_debugMode) Log("PlaceOrder: invalid TradePlan rejected"); return false; }

      m_trade.SetExpertMagicNumber(Config().magic);
      m_trade.SetDeviationInPoints(Config().max_slippage_points);

      bool ok = false;
      if(plan.direction == 1)
      {
         ok = plan.isPending
            ? m_trade.BuyLimit(plan.lot,  plan.entry, m_symbol, plan.sl, plan.tp,
                               ORDER_TIME_SPECIFIED, plan.expiry, plan.label)
            : m_trade.Buy(plan.lot, m_symbol, plan.entry, plan.sl, plan.tp, plan.label);
      }
      else
      {
         ok = plan.isPending
            ? m_trade.SellLimit(plan.lot, plan.entry, m_symbol, plan.sl, plan.tp,
                                ORDER_TIME_SPECIFIED, plan.expiry, plan.label)
            : m_trade.Sell(plan.lot, m_symbol, plan.entry, plan.sl, plan.tp, plan.label);
      }

      if(ok)
      {
         outTicket = m_trade.ResultOrder();
         if(m_debugMode)
            PrintFormat("[Execution] Order placed: ticket=%d dir=%d lot=%.2f e=%.5f sl=%.5f tp=%.5f",
                        outTicket, plan.direction, plan.lot, plan.entry, plan.sl, plan.tp);
      }
      else if(m_debugMode)
         PrintFormat("[Execution] Order FAILED: retcode=%d %s",
                     m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
      return ok;
   }

   double CalcLotSize(double riskPct, double slPoints) const
   {
      if(slPoints <= 0) return 0.0;
      double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
      double tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickSize <= 0 || tickValue <= 0 || balance <= 0) return 0.0;
      double slValue = (slPoints * _Point / tickSize) * tickValue;
      if(slValue <= 0) return 0.0;
      return m_data.NormalizeVolume(m_symbol, (balance * riskPct / 100.0) / slValue);
   }

   // FIX PASR-BUG-004: 1 Hz throttled status line
   string PrepareStatusLine()
   {
      ulong now = GetMicrosecondCount();
      if(now - m_lastRenderUs < 1000000UL) return "";
      m_lastRenderUs = now;
      int openPos = 0, pendOrd = 0;
      for(int i = 0; i < PositionsTotal(); i++)
         if(PositionGetInteger(POSITION_MAGIC) == Config().magic &&
            PositionGetString(POSITION_SYMBOL) == m_symbol) openPos++;
      for(int i = 0; i < OrdersTotal(); i++)
         if(OrderGetInteger(ORDER_MAGIC) == Config().magic &&
            OrderGetString(ORDER_SYMBOL) == m_symbol)  pendOrd++;
      return StringFormat("[Execution] Pos:%d Pend:%d Trading:%s",
                          openPos, pendOrd, m_tradingAllowed ? "ON" : "OFF");
   }

public:
   ExecutionManager()
      : IManager("ExecutionManager", 50),
        m_tradingAllowed(true), m_lastScavengeBar(0), m_lastRenderUs(0)
   { m_symbol = _Symbol; }

   virtual bool Init() override
   {
      if(!IManager::Init()) return false;
      m_trade.SetExpertMagicNumber(Config().magic);
      m_trade.SetDeviationInPoints(Config().max_slippage_points);
      ScavengePendingGVs();
      return true;
   }

   virtual void DeclareEvents() override
   {
      AddEvent(EVENT_ID_SIGNAL_GENERATED);
      AddEvent(EVENT_ID_ZONE_UPDATE);
      AddEvent(EVENT_ID_EMERGENCY_STOP);
      AddEvent(EVENT_ID_PAUSE_TOGGLE);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_POSITION_UPDATE);
   }

   void SetTradingAllowed(bool v) { m_tradingAllowed = v; }
   bool IsTradingAllowed()  const { return m_tradingAllowed; }

   virtual void OnSignalGenerated(SignalGeneratedEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID || !m_tradingAllowed) return;

      TradePlan plan;
      plan.direction = e.direction;
      plan.entry     = e.entryPrice;
      plan.sl        = e.slPrice;
      plan.tp        = e.tpPrice;
      plan.isPending = (e.entryPrice > 0 &&
                        MathAbs(e.entryPrice - SymbolInfoDouble(m_symbol, SYMBOL_ASK)) > _Point);
      plan.expiry    = TimeCurrent() + (Config().pending_order_expiry_bars * PeriodSeconds(_Period));
      plan.label     = StringFormat("PASR_%d", Config().magic);
      plan.lot       = CalcLotSize(Config().risk_pct,
                                   MathAbs(plan.entry - plan.sl) / _Point);
      if(!plan.IsValid()) { if(m_debugMode) Log("Signal rejected: invalid TradePlan"); return; }

      ulong ticket = 0;
      if(PlaceOrder(plan, ticket) && ticket > 0)
      {
         if(plan.isPending) SavePendingState(ticket, plan, e.zonePrice, e.slMult);

         OrderExecutionEvent *ev = new OrderExecutionEvent(ticket, plan.direction,
                                                           plan.lot, plan.entry,
                                                           plan.sl, plan.tp);
         DispatchEvent(ev);

         PositionUpdateEvent *pu = new PositionUpdateEvent(ticket, plan.entry, e.atr, false);
         pu.type = (plan.direction == 1) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
         DispatchEvent(pu);
      }
   }

   virtual void OnPositionUpdate(PositionUpdateEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      if(e.isClosed) DeletePendingStateById(e.ticket);
   }

   virtual void OnNewBar(NewBarEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      ScavengePendingGVs();
      string status = PrepareStatusLine();
      if(StringLen(status) > 0 && m_debugMode) Print(status);
   }

   virtual void OnEmergencyStop(EmergencyStopEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      m_tradingAllowed = false;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(PositionGetInteger(POSITION_MAGIC) != Config().magic) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol)       continue;
         m_trade.PositionClose(t);
      }
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong t = OrderGetTicket(i);
         if(OrderGetInteger(ORDER_MAGIC) != Config().magic) continue;
         if(OrderGetString(ORDER_SYMBOL) != m_symbol)        continue;
         m_trade.OrderDelete(t);
      }
      // Safe scoped GV cleanup (account + magic + symbol scoped)
      string prefix = "PASR_PEND_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))
                    + "_" + IntegerToString(Config().magic) + "_" + m_symbol + "_";
      GlobalVariablesDeleteAll(prefix);
      if(m_debugMode) Log("Emergency stop: all positions/orders closed.");
   }

   virtual void OnPauseToggle(PauseToggleEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      m_tradingAllowed = !e.isPaused;
      if(m_debugMode) PrintFormat("[Execution] Trading %s", m_tradingAllowed ? "RESUMED" : "PAUSED");
   }

   virtual void OnConfigReload(ConfigReloadEvent *e) override
   {
      IManager::OnConfigReload(e);
      m_trade.SetExpertMagicNumber(Config().magic);
      m_trade.SetDeviationInPoints(Config().max_slippage_points);
   }

   virtual void OnZoneUpdate(ZoneUpdateEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID || !m_tradingAllowed) return;
      if(!Config().use_pending_orders) return;
      string prefix = MakePendingPrefix(e.zoneID);
      if(!GlobalVariableCheck(prefix + "ts")) return;
      if(m_debugMode)
         PrintFormat("[Execution] ZoneUpdate tsID=%d tp=%.5f", e.zoneID, GlobalVariableGet(prefix + "tp"));
   }
};

#endif // __TRADE_EXECUTION_MANAGER_MQH__
