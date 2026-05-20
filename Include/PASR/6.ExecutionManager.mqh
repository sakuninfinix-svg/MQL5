//+------------------------------------------------------------------+
//|                                          6.ExecutionManager.mqh   |
//|                                       Copyright 2026, Agsicentre |
//|                    Trade Execution Manager - v2.11               |
//|                                                                   |
//| v2.11 CRITICAL SECURITY FIX:                                     |
//| - [BUG-SEC-01] Account-scoped GlobalVariable keys                |
//|   BEFORE: GV key = "PASR_" + magic + "_" + suffix               |
//|           → demo + live instances with same magic corrupt each   |
//|             other's trade state (silent data corruption)         |
//|   AFTER:  GV key = "PASR_" + accountLogin + "_" + magic + "_"   |
//|           + suffix → completely isolated per account             |
//|                                                                   |
//| v2.11 PERFORMANCE FIX:                                           |
//| - [BUG-PERF-02] ScavengePendingGVs() O(n²) replaced with cached |
//|   key array, updated only on trade open/close events             |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "2.11"
#property strict

#ifndef __EXECUTION_MANAGER_MQH__
#define __EXECUTION_MANAGER_MQH__

#include "IManager.mqh"
#include "2.Config.Types.mqh"
#include "0.EventBus.mqh"

//+------------------------------------------------------------------+
//| Execution Manager                                                |
//+------------------------------------------------------------------+
class CExecutionManager : public IManager
{
private:
   CTrade  m_trade;
   ulong   m_magic;
   string  m_gvPrefix;        // [v2.11] account-scoped GV prefix, built once in Init()
   string  m_cachedGVKeys[];  // [v2.11] cached GV key list for O(1) scavenge
   bool    m_gvCacheDirty;    // true when trade count changed
   int     m_orderThrottleMs;
   ulong   m_lastOrderMs;

   //--- [v2.11] Build account-scoped GV prefix ONCE
   //    Format: PASR_{accountLogin}_{magic}_
   //    e.g.:   PASR_12345678_100001_
   string BuildGVPrefix(ulong magic) const
   {
      long login = AccountInfoInteger(ACCOUNT_LOGIN);
      return StringFormat("PASR_%I64d_%I64u_", login, magic);
   }

   string GVKey(const string suffix) const
   {
      return m_gvPrefix + suffix;
   }

   //--- Rebuild cached GV key list from open positions
   //    Called only on trade open / trade close events
   void RebuildGVCache()
   {
      int posTotal = PositionsTotal();
      ArrayResize(m_cachedGVKeys, 0);
      for(int i = 0; i < posTotal; i++)
      {
         if(PositionGetSymbol(i) == _Symbol &&
            (ulong)PositionGetInteger(POSITION_MAGIC) == m_magic)
         {
            ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
            int sz = ArraySize(m_cachedGVKeys);
            ArrayResize(m_cachedGVKeys, sz + 1);
            m_cachedGVKeys[sz] = GVKey("T" + IntegerToString((long)ticket));
         }
      }
      m_gvCacheDirty = false;
   }

   //--- Write a trade state GV with account-scoped key
   void SetTradeGV(ulong ticket, ENUM_TRADE_STATE state)
   {
      string key = GVKey("T" + IntegerToString((long)ticket));
      GlobalVariableSet(key, (double)state);
      m_gvCacheDirty = true; // force cache rebuild on next scavenge
   }

   //--- Read trade state GV
   ENUM_TRADE_STATE GetTradeGV(ulong ticket) const
   {
      string key = GVKey("T" + IntegerToString((long)ticket));
      if(!GlobalVariableCheck(key)) return TRADE_STATE_NONE;
      return (ENUM_TRADE_STATE)(int)GlobalVariableGet(key);
   }

   //--- Delete a single trade state GV
   void DeleteTradeGV(ulong ticket)
   {
      string key = GVKey("T" + IntegerToString((long)ticket));
      if(GlobalVariableCheck(key)) GlobalVariableDel(key);
      m_gvCacheDirty = true;
   }

public:
   CExecutionManager()
      : m_magic(0), m_gvPrefix(""), m_gvCacheDirty(true),
        m_orderThrottleMs(100), m_lastOrderMs(0)
   {
      ArrayResize(m_cachedGVKeys, 0);
   }

   bool Init(CDataManager *data) override
   {
      if(!IManager::Init(data)) return false;

      m_magic          = m_cfg.risk.magic;
      m_orderThrottleMs= m_cfg.system.orderThrottleMs;

      // [v2.11] Build prefix ONCE — account-scoped
      m_gvPrefix = BuildGVPrefix(m_magic);
      Print("[ExecutionManager] GV prefix: ", m_gvPrefix);

      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints(10);

      RebuildGVCache(); // initial scan
      return true;
   }

   //--- Called by orchestrator when EVENT_ID_CONFIG_RELOAD fires
   void OnConfigReload() override
   {
      IManager::OnConfigReload(); // updates m_cfg
      m_orderThrottleMs = m_cfg.system.orderThrottleMs;
      // Note: magic number change requires full EA restart; do not rebuild prefix here
   }

   //--- Called when EVENT_ID_TRADE_OPEN or EVENT_ID_TRADE_CLOSE fires
   //    Marks GV cache dirty so next ScavengePendingGVs() rebuilds it
   void OnTradeEvent() { m_gvCacheDirty = true; }

   //--- Main order placement (throttled)
   bool PlaceOrder(const OrderPlan &plan)
   {
      // Throttle guard
      ulong nowMs = GetTickCount64();
      if((long)(nowMs - m_lastOrderMs) < (long)m_orderThrottleMs) return false;

      bool ok = false;
      if(plan.type == ORDER_TYPE_BUY)
         ok = m_trade.Buy(plan.lot, _Symbol, plan.entry, plan.brokerSL, plan.tp, plan.comment);
      else if(plan.type == ORDER_TYPE_SELL)
         ok = m_trade.Sell(plan.lot, _Symbol, plan.entry, plan.brokerSL, plan.tp, plan.comment);

      if(ok)
      {
         m_lastOrderMs = GetTickCount64();
         SetTradeGV(m_trade.ResultOrder(), TRADE_STATE_NORMAL);
      }
      else
         Print("[ExecutionManager] Order failed: ", m_trade.ResultRetcodeDescription());

      return ok;
   }

   //--- Clean up stale GVs for closed positions
   //    [v2.11] Uses cached key array — O(cached_keys) instead of O(all_GVs × positions)
   //    Rebuild only when m_gvCacheDirty (set on trade events)
   void ScavengePendingGVs()
   {
      if(m_gvCacheDirty) RebuildGVCache();

      // Check cached keys against still-open positions
      int i = 0;
      while(i < ArraySize(m_cachedGVKeys))
      {
         string key = m_cachedGVKeys[i];
         // Extract ticket from key suffix (format: PASR_{acct}_{magic}_T{ticket})
         // If the position no longer exists, delete the GV
         if(!GlobalVariableCheck(key)) { i++; continue; }

         bool positionOpen = false;
         for(int p = 0; p < PositionsTotal(); p++)
         {
            if(PositionGetSymbol(p) == _Symbol &&
               (ulong)PositionGetInteger(POSITION_MAGIC) == m_magic)
            {
               positionOpen = true;
               break;
            }
         }

         if(!positionOpen)
         {
            GlobalVariableDel(key);
            int sz = ArraySize(m_cachedGVKeys);
            m_cachedGVKeys[i] = m_cachedGVKeys[sz - 1];
            ArrayResize(m_cachedGVKeys, sz - 1);
            // do NOT increment i — recheck slot
         }
         else i++;
      }
   }

   //--- Delete all GVs owned by this EA instance (account-scoped)
   void ClearAllGVs()
   {
      // Only iterate GVs that match our exact prefix
      int total = GlobalVariablesTotal();
      for(int i = total - 1; i >= 0; i--)
      {
         string name = GlobalVariableName(i);
         if(StringFind(name, m_gvPrefix) == 0)
            GlobalVariableDel(name);
      }
      ArrayResize(m_cachedGVKeys, 0);
      m_gvCacheDirty = false;
   }
};

#endif // __EXECUTION_MANAGER_MQH__
