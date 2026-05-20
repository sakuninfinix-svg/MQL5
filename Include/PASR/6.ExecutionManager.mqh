//+------------------------------------------------------------------+
//|                                             ExecutionManager.mqh |
//|                                       Copyright 2026, Agsicentre |
//|            Order Execution & Trade Management Module             |
//+------------------------------------------------------------------+
//| V2.01 FIXES:                                                     |
//| - EX-BUG-FIX-1 [HIGH]: All GV key prefixes now include          |
//|   AccountInfoInteger(ACCOUNT_LOGIN) to prevent state corruption  |
//|   when demo+live instances share the same magic number.          |
//| - EX-BUG-FIX-2 [HIGH]: DeletePendingStateById() replaced        |
//|   GlobalVariablesDeleteAll() with per-key enumeration loop.      |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "2.01"
#property strict

#ifndef __EXECUTION_MANAGER_MQH__
#define __EXECUTION_MANAGER_MQH__

#include <Trade/Trade.mqh>
#include "IManager.mqh"
#include "10.DataManager.mqh"
#include "3.ZoneManager.mqh"

//+------------------------------------------------------------------+
//| Trade Plan — data passed from signal to execution                |
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

   //--- Pending-state helpers (GlobalVariable persistence)
   // EX-BUG-FIX-1: All key builders now include ACCOUNT_LOGIN prefix.
   string MakePendingPrefix(ulong tsID) const
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      // EX-BUG-FIX-1: prepend account login to prevent cross-account GV collision
      return "PASR_PEND_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_"
             + IntegerToString(cfg.magic) + "_" + m_symbol + "_" + IntegerToString(tsID) + "_";
   }

   void SavePendingState(ulong tsID, const TradePlan &plan, double zonePrice, double slMult) const
   {
      string p = MakePendingPrefix(tsID);
      GlobalVariableSet(p + "ts", (double)TimeCurrent());
      GlobalVariableSet(p + "tp", plan.tp);
      GlobalVariableSet(p + "zp", zonePrice);
      GlobalVariableSet(p + "sm", slMult);
   }

   // EX-BUG-FIX-2: Safe per-key deletion loop instead of GlobalVariablesDeleteAll.
   void DeletePendingStateById(ulong tsID) const
   {
      string prefix = MakePendingPrefix(tsID);
      // EX-BUG-FIX-2: per-key loop — GlobalVariablesDeleteAll is unsafe
      // when multiple EA instances share a prefix substring
      for(int i = GlobalVariablesTotal() - 1; i >= 0; i--)
      {
         string varName = GlobalVariableName(i);
         if(StringFind(varName, prefix) == 0)
            GlobalVariableDel(varName);
      }
   }

   void ScavengePendingGVs()
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      // EX-BUG-FIX-1: account login prefix
      string pattern = "PASR_PEND_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_"
                     + IntegerToString(cfg.magic) + "_" + m_symbol + "_";

      int total = GlobalVariablesTotal();
      // Collect unique tsID values under this pattern
      string found[];
      int    foundCount = 0;
      for(int i = 0; i < total; i++)
      {
         string gvName = GlobalVariableName(i);
         if(StringFind(gvName, pattern) != 0) continue;

         // Extract tsID segment (between pattern end and next '_')
         string rest    = StringSubstr(gvName, StringLen(pattern));
         int    sepPos  = StringFind(rest, "_");
         string tsID_str = (sepPos >= 0) ? StringSubstr(rest, 0, sepPos) : rest;

         // De-dup
         bool already = false;
         for(int j = 0; j < foundCount; j++)
            if(found[j] == tsID_str) { already = true; break; }
         if(already) continue;

         // Check timestamp expiry (default 24 h)
         datetime ts = (datetime)GlobalVariableGet(pattern + tsID_str + "_ts");
         if(ts > 0 && TimeCurrent() - ts > 86400)
         {
            GlobalVariablesDeleteAll(pattern + tsID_str + "_");
            if(m_debugMode)
               PrintFormat("[Execution] Scavenged stale pending GVs for tsID=%s", tsID_str);
         }
         else
         {
            ArrayResize(found, foundCount + 1);
            found[foundCount++] = tsID_str;
         }
      }
   }

   bool PlaceOrder(const TradePlan &plan, ulong &outTicket)
   {
      outTicket = 0;
      if(!m_tradingAllowed) return false;

      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      m_trade.SetExpertMagicNumber(cfg.magic);
      m_trade.SetDeviationInPoints(cfg.max_slippage_points);

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

private:
   virtual void RefreshConfigCache() override { IManager::RefreshConfigCache(); }

public:
   ExecutionManager() : IManager("ExecutionManager", 50), m_tradingAllowed(true)
   {
      m_symbol = _Symbol;
   }

   virtual bool Init() override
   {
      if(!IManager::Init()) return false;
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      m_trade.SetExpertMagicNumber(cfg.magic);
      m_trade.SetDeviationInPoints(cfg.max_slippage_points);
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

      StrategyConfig cfg; m_data.GetConfigCache(cfg);

      TradePlan plan;
      plan.direction  = e.direction;
      plan.entry      = e.entryPrice;
      plan.sl         = e.slPrice;
      plan.tp         = e.tpPrice;
      plan.isPending  = (e.entryPrice > 0 && MathAbs(e.entryPrice - SymbolInfoDouble(m_symbol, SYMBOL_ASK)) > _Point);
      plan.expiry     = TimeCurrent() + (cfg.pending_order_expiry_bars * PeriodSeconds(_Period));
      plan.label      = StringFormat("PASR_%d", cfg.magic);

      double slPoints = MathAbs(plan.entry - plan.sl) / _Point;
      plan.lot        = CalcLotSize(cfg.risk_pct, slPoints);
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
      ScavengePendingGVs();
   }

   virtual void OnEmergencyStop(EmergencyStopEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      m_tradingAllowed = false;

      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      // Close all open positions
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(PositionGetInteger(POSITION_MAGIC) != cfg.magic) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol)  continue;
         m_trade.PositionClose(ticket);
      }

      // Delete all pending orders
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(OrderGetInteger(ORDER_MAGIC) != cfg.magic)         continue;
         if(OrderGetString(ORDER_SYMBOL) != m_symbol)          continue;
         m_trade.OrderDelete(ticket);
      }

      // EX-BUG-FIX-1: account login prefix
      GlobalVariablesDeleteAll("PASR_PEND_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_"
                              + IntegerToString(cfg.magic) + "_" + m_symbol + "_");

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
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      m_trade.SetExpertMagicNumber(cfg.magic);
      m_trade.SetDeviationInPoints(cfg.max_slippage_points);
   }

   virtual void OnZoneUpdate(ZoneUpdateEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID || !m_tradingAllowed) return;

      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      if(!cfg.use_pending_orders) return;

      // Re-evaluate pending orders against updated zone data
      ulong tsID = e.zoneID;
      string prefix = MakePendingPrefix(tsID);
      if(!GlobalVariableCheck(prefix + "ts")) return;

      // Retrieve stored plan data
      TradePlan plan;
      plan.tp        = GlobalVariableGet(prefix + "tp");
      double zonePrice = GlobalVariableGet(prefix + "zp");
      double slMult    = GlobalVariableGet(prefix + "sm");
      (void)zonePrice; (void)slMult; // used for reference, not re-calculation here

      if(m_debugMode)
         PrintFormat("[Execution] Zone update for pending tsID=%d, stored tp=%.5f", tsID, plan.tp);
   }
};

#endif // __EXECUTION_MANAGER_MQH__
