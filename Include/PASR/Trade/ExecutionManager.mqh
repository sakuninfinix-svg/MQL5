//+------------------------------------------------------------------+
//| Trade/ExecutionManager.mqh  — CANONICAL v2.13                    |
//|                                                                  |
//| CHANGES v2.13 (2026-05-21):                                      |
//|   - REMOVED global BuildGVPrefix() free function                 |
//|     Was duplicate of IManager::BuildGVPrefix() — linker risk.   |
//|     CExecutionManager inherits it from IManager.                 |
//|   - REMOVED direct #include "../Core/Globals.mqh"                |
//|     Globals.mqh must be included ONCE via Core/PASR.mqh.         |
//|     Double-include causes extern re-declaration errors.          |
//|   - Init() now uses inherited BuildGVPrefix() for GV prefix.     |
//|                                                                  |
//| INVARIANTS:                                                      |
//|   ALL GlobalVariable keys MUST use prefix from BuildGVPrefix()   |
//|   Format: PASR_{account_login}_{magic}_T{ticket}_SL / _TP        |
//|   This prevents state corruption between live+demo instances     |
//|   sharing the same magic number.                                 |
//+------------------------------------------------------------------+
#pragma once
#ifndef TRADE_EXECUTION_MANAGER_MQH
#define TRADE_EXECUTION_MANAGER_MQH

#include "../Core/IManager.mqh"
#include "../Core/Events.mqh"
// NOTE: Do NOT include Globals.mqh here.
//       It is already included ONCE by Core/PASR.mqh (master include).
//       Globals.mqh uses extern declarations — double-include = linker error.

//--- max concurrent tracked positions
#define EXEC_MAX_POSITIONS 64

//+------------------------------------------------------------------+
//| Cached GV key registry — rebuilt only on trade events            |
//| O(1) add/remove, O(n) rebuild triggered only by OnTradeOpen/Close|
//+------------------------------------------------------------------+
class CGVKeyCache
  {
public:
   string            m_keys[EXEC_MAX_POSITIONS];
   long              m_tickets[EXEC_MAX_POSITIONS];
   int               m_count;
   string            m_prefix;

   void              Init(const string prefix)
     {
      m_prefix = prefix;
      m_count  = 0;
     }

   //--- Full rebuild from PositionsTotal() — O(n), call only on trade events
   void              Rebuild()
     {
      m_count = 0;
      int total = PositionsTotal();
      for(int i = 0; i < total && m_count < EXEC_MAX_POSITIONS; i++)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         m_tickets[m_count] = (long)ticket;
         m_keys[m_count]    = m_prefix + "T" + IntegerToString((long)ticket);
         m_count++;
        }
     }

   //--- O(n) lookup — n <= EXEC_MAX_POSITIONS (64), effectively O(1) in practice
   string            GetKey(long ticket) const
     {
      for(int i = 0; i < m_count; i++)
         if(m_tickets[i] == ticket) return m_keys[i];
      return "";
     }

   //--- O(n) remove with left-shift — called only on trade close event
   void              Remove(long ticket)
     {
      for(int i = 0; i < m_count; i++)
        {
         if(m_tickets[i] == ticket)
           {
            for(int j = i; j < m_count - 1; j++)
              {
               m_keys[j]    = m_keys[j + 1];
               m_tickets[j] = m_tickets[j + 1];
              }
            m_count--;
            return;
           }
        }
     }

   //--- O(1) append — called only on trade open event
   void              Add(long ticket)
     {
      if(m_count >= EXEC_MAX_POSITIONS) return;
      m_tickets[m_count] = ticket;
      m_keys[m_count]    = m_prefix + "T" + IntegerToString(ticket);
      m_count++;
     }
  };

//+------------------------------------------------------------------+
//| CExecutionManager — canonical production implementation          |
//+------------------------------------------------------------------+
class CExecutionManager : public IManager
  {
private:
   CGVKeyCache       m_gvCache;      // O(1) ticket → GV key mapping
   bool              m_cacheValid;   // false = needs Rebuild() on next access

   void              InvalidateCache() { m_cacheValid = false; }

   //--- Lazy rebuild: only triggers if cache was invalidated
   void              EnsureCache()
     {
      if(!m_cacheValid)
        {
         m_gvCache.Rebuild();
         m_cacheValid = true;
        }
     }

public:
   CExecutionManager() : m_cacheValid(false) {}

   bool              Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      // BuildGVPrefix() inherited from IManager — account+magic safe
      // Format: PASR_{login}_{magic}_
      m_gvCache.Init(BuildGVPrefix());
      m_gvCache.Rebuild();
      m_cacheValid = true;
      return true;
     }

   //--- Call from EA OnTradeTransaction to keep cache in sync
   void              OnTradeOpen(long ticket)
     {
      m_gvCache.Add(ticket);
      m_cacheValid = true;
     }

   void              OnTradeClose(long ticket)
     {
      m_gvCache.Remove(ticket);
      m_cacheValid = true;
     }

   //--- Persist SL/TP to GlobalVariable (survives terminal restart)
   //--- Key format: PASR_{login}_{magic}_T{ticket}_SL / _TP
   void              SaveTradeState(long ticket, double sl, double tp)
     {
      EnsureCache();
      string key = m_gvCache.GetKey(ticket);
      if(key == "") return;
      GlobalVariableSet(key + "_SL", sl);
      GlobalVariableSet(key + "_TP", tp);
     }

   //--- Restore SL/TP from GlobalVariable (e.g. after terminal restart)
   bool              LoadTradeState(long ticket, double &sl, double &tp)
     {
      EnsureCache();
      string key = m_gvCache.GetKey(ticket);
      if(key == "") return false;
      sl = GlobalVariableGet(key + "_SL");
      tp = GlobalVariableGet(key + "_TP");
      return true;
     }

   //--- Delete all GVs belonging to this EA instance (account-isolated)
   //--- Safe to call on Deinit() or on explicit user reset
   void              ClearAllGVs()
     {
      string prefix = BuildGVPrefix();
      int total = (int)GlobalVariablesTotal();
      for(int i = total - 1; i >= 0; i--)
        {
         string name = GlobalVariableName(i);
         if(StringFind(name, prefix) == 0)
            GlobalVariableDel(name);
        }
      m_gvCache.Init(prefix);
      m_cacheValid = false;
     }

   void              OnNewBar()        override {}
   void              OnPriceUpdate()   override {}
   bool              IsHealthy()  const override { return true; }
  };

#endif // TRADE_EXECUTION_MANAGER_MQH
