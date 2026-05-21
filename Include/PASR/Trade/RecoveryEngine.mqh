//+------------------------------------------------------------------+
//|                                    Trade/RecoveryEngine.mqh      |
//|                          Copyright 2026, Agsicentre             |
//|                                                                  |
//|  PURPOSE: Per-position recovery state + fakeout detection types. |
//|    Extracted from RecoveryManager.mqh Phase 6 refactor.         |
//|                                                                  |
//|  TYPES DEFINED HERE:                                             |
//|    ENUM_TRADE_STATE  — position lifecycle states                 |
//|    RecoveryEngine    — per-position recovery state + GV persist  |
//|    FakeoutResult     — output of fakeout detection logic         |
//|    RECOVERY_MAX_ENGINES — hard cap constant                      |
//|                                                                  |
//|  PERSISTENCE DESIGN:                                             |
//|    SaveState() writes every engine field to GlobalVariables.     |
//|    LoadState() restores them — survives terminal restart and EA  |
//|    re-attach without losing in-flight recovery state.            |
//|    Key format: PASR_{login}_{magic}_T{ticket}_{fieldname}        |
//|    Built by caller (RecoveryManager) using BuildGVPrefix().      |
//|                                                                  |
//|  CHANGE LOG:                                                     |
//|  v2.14 (2026-05-21) — new file (extracted from RecoveryManager)  |
//|    + SaveState() fully implemented (was stub)                    |
//|    + LoadState() added (survives restart)                        |
//|    + Reset() clears all new Phase 6 fields                       |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "2.14"
#property strict

#ifndef __TRADE_RECOVERY_ENGINE_MQH__
#define __TRADE_RECOVERY_ENGINE_MQH__

//+------------------------------------------------------------------+
//| Trade state machine                                              |
//+------------------------------------------------------------------+
enum ENUM_TRADE_STATE
  {
   TRADE_STATE_NORMAL   = 0,  // position open, no action needed
   TRADE_STATE_RECOVERY = 1,  // SL was hit, recovery attempt active
   TRADE_STATE_DONE     = 2,  // position closed; engine pending compaction
  };

//+------------------------------------------------------------------+
//| Constant: hard cap on tracked positions per EA instance          |
//+------------------------------------------------------------------+
#define RECOVERY_MAX_ENGINES 64

//+------------------------------------------------------------------+
//| RecoveryEngine — per-position state container                   |
//|                                                                  |
//| LIFECYCLE:                                                       |
//|   1. Allocated by RecoveryManager::OnTradeOpen()                 |
//|   2. Updated on every relevant event via RecoveryManager methods |
//|   3. Compacted (deleted) by RecoveryManager::CompactEngines()    |
//|      when state == TRADE_STATE_DONE                              |
//|                                                                  |
//| GV PERSISTENCE:                                                  |
//|   SaveState(prefix) / LoadState(prefix) use the key pattern:     |
//|   {prefix}T{ticket}_{field}                                      |
//|   where prefix = BuildGVPrefix() from IManager.                  |
//+------------------------------------------------------------------+
struct RecoveryEngine
  {
   ulong              mainTicket;
   int                direction;            // +1 = buy, -1 = sell
   double             entryPrice;
   datetime           entryTime;
   ENUM_TRADE_STATE   state;
   int                recoveryAttempts;
   double             lastKnownATR;
   bool               partialClosed;
   bool               active;
   datetime           recoveryCooldownExpiry;

   //--- Constructor: safe zero-state defaults
   RecoveryEngine()
      : mainTicket(0), direction(0), entryPrice(0.0), entryTime(0),
        state(TRADE_STATE_NORMAL), recoveryAttempts(0), lastKnownATR(0.0),
        partialClosed(false), active(false), recoveryCooldownExpiry(0) {}

   //--- Reset to initial state (called on close/compact)
   void Reset()
     {
      mainTicket             = 0;
      direction              = 0;
      entryPrice             = 0.0;
      entryTime              = 0;
      state                  = TRADE_STATE_NORMAL;
      recoveryAttempts       = 0;
      lastKnownATR           = 0.0;
      partialClosed          = false;
      active                 = false;
      recoveryCooldownExpiry = 0;
     }

   //--- Persist all state fields to GlobalVariable
   // prefix = BuildGVPrefix() from the owning RecoveryManager
   // Call after every state mutation that must survive terminal restart.
   void SaveState(const string prefix)
     {
      string k = prefix + "T" + IntegerToString((long)mainTicket) + "_";
      GlobalVariableSet(k + "dir",      (double)direction);
      GlobalVariableSet(k + "entry",    entryPrice);
      GlobalVariableSet(k + "etime",    (double)entryTime);
      GlobalVariableSet(k + "state",    (double)state);
      GlobalVariableSet(k + "attempts", (double)recoveryAttempts);
      GlobalVariableSet(k + "atr",      lastKnownATR);
      GlobalVariableSet(k + "partial",  partialClosed  ? 1.0 : 0.0);
      GlobalVariableSet(k + "active",   active         ? 1.0 : 0.0);
      GlobalVariableSet(k + "cooldown", (double)recoveryCooldownExpiry);
     }

   //--- Restore state fields from GlobalVariable
   // Returns true if the GV set existed (i.e. data was found).
   // Returns false if GVs were absent — caller should treat as new engine.
   bool LoadState(const string prefix)
     {
      string k   = prefix + "T" + IntegerToString((long)mainTicket) + "_";
      string key = k + "dir";
      if(!GlobalVariableCheck(key)) return false;

      direction              = (int)GlobalVariableGet(k + "dir");
      entryPrice             =      GlobalVariableGet(k + "entry");
      entryTime              = (datetime)GlobalVariableGet(k + "etime");
      state                  = (ENUM_TRADE_STATE)(int)GlobalVariableGet(k + "state");
      recoveryAttempts       = (int)GlobalVariableGet(k + "attempts");
      lastKnownATR           =      GlobalVariableGet(k + "atr");
      partialClosed          = GlobalVariableGet(k + "partial")  > 0.5;
      active                 = GlobalVariableGet(k + "active")   > 0.5;
      recoveryCooldownExpiry = (datetime)GlobalVariableGet(k + "cooldown");
      return true;
     }

   //--- Clear all GV keys for this engine (call on close/compact)
   void ClearGVs(const string prefix)
     {
      string k = prefix + "T" + IntegerToString((long)mainTicket) + "_";
      string fields[] = {"dir","entry","etime","state","attempts",
                         "atr","partial","active","cooldown"};
      int n = ArraySize(fields);
      for(int i = 0; i < n; i++)
         GlobalVariableDel(k + fields[i]);
     }
  };

//+------------------------------------------------------------------+
//| FakeoutResult — output of fakeout detection pass                 |
//+------------------------------------------------------------------+
struct FakeoutResult
  {
   bool   detected;
   string reason;
   double confidence;   // [0.0 – 1.0]
   int    level;        // 1=weak, 2=medium, 3=strong

   FakeoutResult() : detected(false), reason(""), confidence(0.0), level(0) {}
  };

#endif // __TRADE_RECOVERY_ENGINE_MQH__
