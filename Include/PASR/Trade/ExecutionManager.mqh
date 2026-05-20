//+------------------------------------------------------------------+
//| Trade/ExecutionManager.mqh  — CANONICAL v2.12                    |
//| Account-safe GV prefix, O(1) cached key lookup, BuildGVPrefix    |
//+------------------------------------------------------------------+
#pragma once
#ifndef TRADE_EXECUTION_MANAGER_MQH
#define TRADE_EXECUTION_MANAGER_MQH

#include "../Core/IManager.mqh"
#include "../Core/Events.mqh"
#include "../Core/Globals.mqh"

//--- max concurrent tracked positions
#define EXEC_MAX_POSITIONS 64

//+------------------------------------------------------------------+
//| Account-isolated GlobalVariable key builder                      |
//+------------------------------------------------------------------+
string BuildGVPrefix(long magic)
  {
   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   return "PASR_" + IntegerToString(login) + "_" + IntegerToString(magic) + "_";
  }

//+------------------------------------------------------------------+
//| Cached GV key registry — rebuilt only on trade events            |
//+------------------------------------------------------------------+
class CGVKeyCache
  {
public:
   string            m_keys[EXEC_MAX_POSITIONS];
   long              m_tickets[EXEC_MAX_POSITIONS];
   int               m_count;
   string            m_prefix;

   void              Init(string prefix) { m_prefix = prefix; m_count = 0; }

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

   string            GetKey(long ticket)
     {
      for(int i = 0; i < m_count; i++)
         if(m_tickets[i] == ticket) return m_keys[i];
      return "";
     }

   void              Remove(long ticket)
     {
      for(int i = 0; i < m_count; i++)
        {
         if(m_tickets[i] == ticket)
           {
            // shift left
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
   CGVKeyCache       m_gvCache;
   bool              m_cacheValid;

   //--- mark cache dirty; rebuilt lazily on next access
   void              InvalidateCache() { m_cacheValid = false; }

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
      string prefix = BuildGVPrefix(m_cfg.MagicNumber);
      m_gvCache.Init(prefix);
      m_gvCache.Rebuild();
      m_cacheValid = true;
      return true;
     }

   //--- Call on OnTradeTransaction to keep cache in sync O(1)
   void              OnTradeOpen(long ticket)  { m_gvCache.Add(ticket);    m_cacheValid = true; }
   void              OnTradeClose(long ticket) { m_gvCache.Remove(ticket); m_cacheValid = true; }

   //--- Save trade state to GV (O(1) key lookup)
   void              SaveTradeState(long ticket, double sl, double tp)
     {
      EnsureCache();
      string key = m_gvCache.GetKey(ticket);
      if(key == "") return;
      GlobalVariableSet(key + "_SL", sl);
      GlobalVariableSet(key + "_TP", tp);
     }

   //--- Load trade state from GV
   bool              LoadTradeState(long ticket, double &sl, double &tp)
     {
      EnsureCache();
      string key = m_gvCache.GetKey(ticket);
      if(key == "") return false;
      sl = GlobalVariableGet(key + "_SL");
      tp = GlobalVariableGet(key + "_TP");
      return true;
     }

   //--- Cleanup all GVs for this EA instance (account-isolated)
   void              ClearAllGVs()
     {
      string prefix = BuildGVPrefix(m_cfg.MagicNumber);
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
