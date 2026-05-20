//+------------------------------------------------------------------+
//|                                             ExecutionManager.mqh |
//|                                       Copyright 2026, Agsicentre |
//|            Order Execution & Trade Management Module             |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "2.02"
#property strict

#ifndef __EXECUTION_MANAGER_MQH__
#define __EXECUTION_MANAGER_MQH__

#include <Trade/Trade.mqh>
#include "../Core/IManager.mqh"
#include "../Infrastructure/10.DataManager.mqh"
// #include "../Data/3.ZoneManager.mqh"  // Removed - ZoneManager not needed for ExecutionManager
// If zone functionality is required, inject via interface or use SRManager directly

//+------------------------------------------------------------------+
//| Trade Plan — data passed from signal to execution               |
//+------------------------------------------------------------------+
struct TradePlan
{
   double   entry;
   double   sl;
   double   tp;
   double   lot;
   int      direction;   ///< +1 = BUY, -1 = SELL
   string   label;
   bool     isPending;
   datetime expiry;

   void Reset() { ZeroMemory(this); }
};

//+------------------------------------------------------------------+
//| ExecutionManager                                                 |
//+------------------------------------------------------------------+
class ExecutionManager : public IManager
{
private:
   CTrade   m_trade;
   string   m_symbol;
   bool     m_tradingAllowed;

   // EX-PERF-3: guard to ensure Scavenge runs at most once per bar
   datetime m_lastScavengeBar;

   // EX-PERF-4: dashboard throttle — render at most 1 Hz
   ulong    m_lastRenderUs;

   //--- Pending-state helpers (GlobalVariable persistence)
   string MakePendingPrefix(ulong tsID) const
   {
      return "PASR_PEND_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_"
             + IntegerToString(Config().magic) + "_" + m_symbol + "_"
             + IntegerToString(tsID) + "_";
   }

   void SavePendingState(ulong tsID, const TradePlan &plan, double zonePrice, double slMult) const
   {
      string p = MakePendingPrefix(tsID);
      GlobalVariableSet(p + "ts",  (double)TimeCurrent());
      GlobalVariableSet(p + "tp",  plan.tp);
      GlobalVariableSet(p + "zp",  zonePrice);
      GlobalVariableSet(p + "sm",  slMult);
   }

   // EX-BUG-FIX-2: Safe per-key deletion (no GlobalVariablesDeleteAll on shared terminal)
   void DeletePendingStateById(ulong tsID) const
   {
      string prefix = MakePendingPrefix(tsID);
      for(int i = GlobalVariablesTotal() - 1; i >= 0; i--)
      {
         string varName = GlobalVariableName(i);
         if(StringFind(varName, prefix) == 0)
            GlobalVariableDel(varName);
      }
   }

   // EX-PERF-1/2/3: two-pass deferred-delete; runs once per bar
   void ScavengePendingGVs()
   {
      datetime currentBar = iTime(m_symbol, _Period, 0);
      if(currentBar == m_lastScavengeBar) return;   // EX-PERF-3
      m_lastScavengeBar = currentBar;

      string pattern = "PASR_PEND_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_"
                     + IntegerToString(Config().magic) + "_" + m_symbol + "_";

      // EX-PERF-2: snapshot total once — no redundant calls inside loop
      int total = GlobalVariablesTotal();

      // --- Pass 1: collect unique tsID values + identify stale ones ---
      string liveIDs[];
      string staleKeys[];
      int    liveCount  = 0;
      int    staleCount = 0;

      for(int i = 0; i < total; i++)
      {
         string gvName = GlobalVariableName(i);
         if(StringFind(gvName, pattern) != 0) continue;

         string rest    = StringSubstr(gvName, StringLen(pattern));
         int    sepPos  = StringFind(rest, "_");
         string tsID_str = (sepPos >= 0) ? StringSubstr(rest, 0, sepPos) : rest;

         // De-dup tsID
         bool already = false;
         for(int j = 0; j < liveCount; j++)
            if(liveIDs[j] == tsID_str) { already = true; break; }
         for(int j = 0; j < staleCount; j++)
         {
            string stalePrefix = pattern + tsID_str;
            if(StringFind(staleKeys[j], stalePrefix) == 0) { already = true; break; }
         }
         if(already) continue;

         datetime ts = (datetime)GlobalVariableGet(pattern + tsID_str + "_ts");
         if(ts > 0 && TimeCurrent() - ts > 86400)
         {
            // Collect all keys belonging to this stale tsID in this same pass
            for(int k = i; k < total; k++)
            {
               string kName   = GlobalVariableName(k);
               string kPrefix = pattern + tsID_str + "_";
               if(StringFind(kName, kPrefix) == 0)
               {
                  ArrayResize(staleKeys, staleCount + 1);
                  staleKeys[staleCount++] = kName;
               }
            }
         }
         else
         {
            ArrayResize(liveIDs, liveCount + 1);
            liveIDs[liveCount++] = tsID_str;
         }
      }

      // --- Pass 2: delete stale keys (deferred, no re-scan) ---
      for(int i = 0; i < staleCount; i++)
      {
         GlobalVariableDel(staleKeys[i]);
         if(m_debugMode)
            PrintFormat("[Execution] Scavenged stale GV: %s", staleKeys[i]);
      }
   }

   bool PlaceOrder(const TradePlan &plan, ulong &outTicket)
   {
      outTicket = 0;
      if(!m_tradingAllowed) return false;

      m_trade.SetExpertMagicNumber(Config().magic);
      m_trade.SetDeviationInPoints(Config().max_slippage_points);

      bool ok = false;
      if(plan.direction == 1)
      {
         if(plan.isPending)
            ok = m_trade.BuyLimit(plan.lot, plan.entry, m_symbol, plan.sl, plan.tp,
                                   ORDER_TIME_SPECIFIED, plan.expiry, plan.label);
         else
            ok = m_trade.Buy(plan.lot, m_symbol, plan.entry, plan.sl, plan.tp, plan.label);
      }
      else
      {
         if(plan.isPending)
            ok = m_trade.SellLimit(plan.lot, plan.entry, m_symbol, plan.sl, plan.tp,
                                    ORDER_TIME_SPECIFIED, plan.expiry, plan.label);
         else
            ok = m_trade.Sell(plan.lot, m_symbol, plan.entry, plan.sl, plan.tp, plan.label);
      }

      if(ok)
      {
         outTicket = m_trade.ResultOrder();
         if(m_debugMode)
            PrintFormat("[Execution] Order placed: ticket=%d dir=%d lot=%.2f entry=%.5f sl=%.5f tp=%.5f",
                        outTicket, plan.direction, plan.lot, plan.entry, plan.sl, plan.tp);
      }
      else if(m_debugMode)
      {
         PrintFormat("[Execution] Order FAILED: retcode=%d %s",
                     m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
      }
      return ok;
   }

   double CalcLotSize(double riskPct, double slPoints) const
   {
      if(slPoints <= 0) return 0;
      double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
      double tickValue  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize   = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickSize <= 0 || tickValue <= 0) return 0;

      double riskAmount = balance * (riskPct / 100.0);
      double slValue    = (slPoints * _Point / tickSize) * tickValue;
      if(slValue <= 0) return 0;

      double rawLot = riskAmount / slValue;
      return m_data.NormalizeVolume(m_symbol, rawLot);
   }

   // EX-PERF-4: 1 Hz dashboard status line — avoid string heap churn per tick
   string PrepareStatusLine()
   {
      ulong nowUs = GetMicrosecondCount();
      if(nowUs - m_lastRenderUs < 1000000UL)   // 1 second
         return "";
      m_lastRenderUs = nowUs;

      int openPos = 0, pendOrd = 0;
      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong t = PositionGetTicket(i);
         if(PositionGetInteger(POSITION_MAGIC) == Config().magic &&
            PositionGetString(POSITION_SYMBOL) == m_symbol)
            openPos++;
      }
      for(int i = 0; i < OrdersTotal(); i++)
      {
         ulong t = OrderGetTicket(i);
         if(OrderGetInteger(ORDER_MAGIC) == Config().magic &&
            OrderGetString(ORDER_SYMBOL) == m_symbol)
            pendOrd++;
      }
      return StringFormat("[Execution] Positions:%d Pending:%d Trading:%s",
                          openPos, pendOrd, m_tradingAllowed ? "ON" : "OFF");
   }

private:
   virtual void RefreshConfigCache() override { IManager::RefreshConfigCache(); }

public:
   ExecutionManager()
      : IManager("ExecutionManager", 50),
        m_tradingAllowed(true),
        m_lastScavengeBar(0),
        m_lastRenderUs(0)
   {
      m_symbol = _Symbol;
   }

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

   void SetTradingAllowed(bool allowed) { m_tradingAllowed = allowed; }
   bool IsTradingAllowed()        const { return m_tradingAllowed; }

   virtual void OnSignalGenerated(SignalGeneratedEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID || !m_tradingAllowed) return;

      TradePlan plan;
      plan.direction  = e.direction;
      plan.entry      = e.entryPrice;
      plan.sl         = e.slPrice;
      plan.tp         = e.tpPrice;
      plan.isPending  = (e.entryPrice > 0 &&
                         MathAbs(e.entryPrice - SymbolInfoDouble(m_symbol, SYMBOL_ASK)) > _Point);
      plan.expiry     = TimeCurrent() + (Config().pending_order_expiry_bars * PeriodSeconds(_Period));
      plan.label      = StringFormat("PASR_%d", Config().magic);

      double slPoints = MathAbs(plan.entry - plan.sl) / _Point;
      plan.lot        = CalcLotSize(Config().risk_pct, slPoints);
      if(plan.lot <= 0)
      {
         if(m_debugMode) Log("Lot size calculation failed — signal skipped");
         return;
      }

      ulong ticket = 0;
      if(PlaceOrder(plan, ticket) && ticket > 0)
      {
         if(plan.isPending)
            SavePendingState(ticket, plan, e.zonePrice, e.slMult);

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
      if(e.isClosed)
         DeletePendingStateById(e.ticket);
   }

   virtual void OnNewBar(NewBarEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      // EX-PERF-3: Scavenge is internally guarded; safe to call here
      ScavengePendingGVs();

      // EX-PERF-4: update dashboard once per bar (minimum)
      string status = PrepareStatusLine();
      if(StringLen(status) > 0 && m_debugMode)
         Print(status);
   }

   virtual void OnEmergencyStop(EmergencyStopEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      m_tradingAllowed = false;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(PositionGetInteger(POSITION_MAGIC) != Config().magic) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol)       continue;
         m_trade.PositionClose(ticket);
      }

      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(OrderGetInteger(ORDER_MAGIC) != Config().magic)  continue;
         if(OrderGetString(ORDER_SYMBOL) != m_symbol)         continue;
         m_trade.OrderDelete(ticket);
      }

      GlobalVariablesDeleteAll("PASR_PEND_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_"
                              + IntegerToString(Config().magic) + "_" + m_symbol + "_");

      if(m_debugMode) Log("Emergency stop executed — all positions/orders closed.");
   }

   virtual void OnPauseToggle(PauseToggleEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      m_tradingAllowed = !e.isPaused;
      if(m_debugMode)
         PrintFormat("[Execution] Trading %s", m_tradingAllowed ? "RESUMED" : "PAUSED");
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

      ulong  tsID    = e.zoneID;
      string prefix  = MakePendingPrefix(tsID);
      if(!GlobalVariableCheck(prefix + "ts")) return;

      TradePlan plan;
      plan.tp          = GlobalVariableGet(prefix + "tp");
      double zonePrice = GlobalVariableGet(prefix + "zp");
      double slMult    = GlobalVariableGet(prefix + "sm");
      (void)zonePrice; (void)slMult;

      if(m_debugMode)
         PrintFormat("[Execution] Zone update for pending tsID=%d, stored tp=%.5f", tsID, plan.tp);
   }
};

#endif // __EXECUTION_MANAGER_MQH__
