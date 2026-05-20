//+------------------------------------------------------------------+
//|                                           8.RecoveryManager.mqh   |
//|                                       Copyright 2026, Agsicentre |
//|                    Recovery Mode Manager - v2.11                 |
//|                                                                   |
//| v2.11 CRITICAL BUG FIX:                                          |
//| - [BUG-CRASH-01] ClearEngineGVs() used `cfg` variable that was  |
//|   never declared in scope → guaranteed runtime crash / undefined  |
//|   behaviour on recovery reset                                    |
//|   FIX: obtain config from m_cfg (IManager base cache)           |
//|                                                                   |
//| v2.11 SECURITY FIX:                                              |
//| - [BUG-SEC-01] All GV keys use account-scoped prefix inherited   |
//|   from CExecutionManager pattern (same BuildGVPrefix logic)      |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "2.11"
#property strict

#ifndef __RECOVERY_MANAGER_MQH__
#define __RECOVERY_MANAGER_MQH__

#include "IManager.mqh"
#include "2.Config.Types.mqh"
#include "0.EventBus.mqh"

class CRecoveryManager : public IManager
{
private:
   // Recovery state
   int            m_attemptCount;
   int            m_cooldownBarsLeft;
   datetime       m_lastLossTime;
   bool           m_active;
   ENUM_TRADE_STATE m_state;

   // Account-scoped GV prefix (same pattern as ExecutionManager)
   string         m_gvPrefix;

   string BuildGVPrefix() const
   {
      long login = AccountInfoInteger(ACCOUNT_LOGIN);
      return StringFormat("PASR_%I64d_%I64u_REC_", login, m_cfg.risk.magic);
   }

   string GVKey(const string suffix) const { return m_gvPrefix + suffix; }

   void SaveState()
   {
      GlobalVariableSet(GVKey("attempts"),  (double)m_attemptCount);
      GlobalVariableSet(GVKey("cooldown"),  (double)m_cooldownBarsLeft);
      GlobalVariableSet(GVKey("active"),    (double)(m_active ? 1 : 0));
      GlobalVariableSet(GVKey("state"),     (double)m_state);
      GlobalVariableSet(GVKey("lossTime"),  (double)m_lastLossTime);
   }

   void LoadState()
   {
      if(GlobalVariableCheck(GVKey("attempts")))
         m_attemptCount     = (int)GlobalVariableGet(GVKey("attempts"));
      if(GlobalVariableCheck(GVKey("cooldown")))
         m_cooldownBarsLeft = (int)GlobalVariableGet(GVKey("cooldown"));
      if(GlobalVariableCheck(GVKey("active")))
         m_active           = (int)GlobalVariableGet(GVKey("active")) != 0;
      if(GlobalVariableCheck(GVKey("state")))
         m_state            = (ENUM_TRADE_STATE)(int)GlobalVariableGet(GVKey("state"));
      if(GlobalVariableCheck(GVKey("lossTime")))
         m_lastLossTime     = (datetime)GlobalVariableGet(GVKey("lossTime"));
   }

public:
   CRecoveryManager()
      : m_attemptCount(0), m_cooldownBarsLeft(0), m_lastLossTime(0),
        m_active(false), m_state(TRADE_STATE_NONE), m_gvPrefix("")
   {}

   bool Init(CDataManager *data) override
   {
      if(!IManager::Init(data)) return false; // loads m_cfg

      m_gvPrefix = BuildGVPrefix(); // safe: m_cfg already populated by IManager::Init
      LoadState();

      Print("[RecoveryManager] Initialized. GV prefix: ", m_gvPrefix,
            " | Attempts: ", m_attemptCount,
            " | Active: ",   m_active);
      return true;
   }

   void Deinit() override
   {
      SaveState(); // persist on EA shutdown
   }

   //--- [BUG-CRASH-01 FIX]
   //    BEFORE (v2.10):
   //       void ClearEngineGVs()
   //       {
   //          ulong magic = cfg.risk.magic;  // ERROR: `cfg` never declared here
   //          ...                            // → crash / UB on every recovery reset
   //       }
   //
   //    AFTER (v2.11): use m_cfg from IManager base — always valid after Init()
   void ClearEngineGVs()
   {
      // m_cfg is guaranteed valid here (populated in IManager::Init before we reach this)
      ulong magic = m_cfg.risk.magic;
      long  login = AccountInfoInteger(ACCOUNT_LOGIN);

      // Delete all recovery GVs for this account+magic combination
      string prefix = StringFormat("PASR_%I64d_%I64u_REC_", login, magic);
      int total = GlobalVariablesTotal();
      for(int i = total - 1; i >= 0; i--)
      {
         string name = GlobalVariableName(i);
         if(StringFind(name, prefix) == 0)
            GlobalVariableDel(name);
      }

      // Reset in-memory state
      m_attemptCount     = 0;
      m_cooldownBarsLeft = 0;
      m_lastLossTime     = 0;
      m_active           = false;
      m_state            = TRADE_STATE_NONE;

      Print("[RecoveryManager] Engine GVs cleared for account ", login,
            " magic ", magic);
   }

   //--- Notify recovery manager of a loss event
   void OnLoss()
   {
      m_attemptCount++;
      m_lastLossTime     = TimeCurrent();
      m_cooldownBarsLeft = m_cfg.recovery.cooldownBars;

      if(m_attemptCount >= m_cfg.recovery.maxAttempts)
      {
         m_active = false;
         m_state  = TRADE_STATE_DONE;
         Print("[RecoveryManager] Max recovery attempts reached. Disabling recovery.");
      }
      else
      {
         m_active = true;
         m_state  = TRADE_STATE_RECOVERY;
      }
      SaveState();
   }

   //--- Call once per bar (decrements cooldown)
   void OnNewBar()
   {
      if(m_cooldownBarsLeft > 0)
      {
         m_cooldownBarsLeft--;
         SaveState();
      }
   }

   //--- Query
   bool     IsActive()      const { return m_active && m_cfg.recovery.use; }
   bool     InCooldown()    const { return m_cooldownBarsLeft > 0; }
   int      AttemptCount()  const { return m_attemptCount; }
   ENUM_TRADE_STATE State() const { return m_state; }

   void Reset()
   {
      ClearEngineGVs();
      Print("[RecoveryManager] State fully reset.");
   }
};

#endif // __RECOVERY_MANAGER_MQH__
