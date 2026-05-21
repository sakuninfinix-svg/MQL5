//+------------------------------------------------------------------+
//| Trade/RecoveryEngine.mqh — v1.00                                 |
//| RecoveryEngine struct + GV persistence + ENUM_TRADE_STATE.       |
//| Extracted from RecoveryManager to break the 800-line God Class.  |
//+------------------------------------------------------------------+
#property strict
#ifndef __TRADE_RECOVERY_ENGINE_MQH__
#define __TRADE_RECOVERY_ENGINE_MQH__

#define RECOVERY_MAX_ENGINES 20

enum ENUM_TRADE_STATE
  {
   TRADE_STATE_NORMAL   = 0,
   TRADE_STATE_RECOVERY = 1,
   TRADE_STATE_DONE     = 2
  };

struct FakeoutResult
  {
   bool   detected;
   int    level;       // 1-3 escalation level
   double confidence;  // 0.0-1.0
   string reason;

   void Clear() { detected=false; level=0; confidence=0.0; reason=""; }
  };

//+------------------------------------------------------------------+
//| RecoveryEngine — per-position state + GV persistence             |
//+------------------------------------------------------------------+
struct RecoveryEngine
  {
   bool             active;
   ulong            mainTicket;
   ENUM_TRADE_STATE state;
   int              direction;          // +1 buy, -1 sell
   double           entryPrice;
   datetime         entryTime;
   int              recoveryAttempts;
   datetime         recoveryCooldownExpiry;
   bool             partialClosed;
   double           lastKnownATR;

   void Init()
     {
      active                 = false;
      mainTicket             = 0;
      state                  = TRADE_STATE_NORMAL;
      direction              = 0;
      entryPrice             = 0.0;
      entryTime              = 0;
      recoveryAttempts       = 0;
      recoveryCooldownExpiry = 0;
      partialClosed          = false;
      lastKnownATR           = 0.0;
     }

   void Reset() { Init(); }

   // Save state to Global Variables (survives EA restart)
   void SaveState(const string prefix) const
     {
      if(mainTicket == 0) return;
      string p = prefix + IntegerToString((long)mainTicket) + "_";
      GlobalVariableSet(p+"dir",   (double)direction);
      GlobalVariableSet(p+"entry", entryPrice);
      GlobalVariableSet(p+"etime",(double)entryTime);
      GlobalVariableSet(p+"att",  (double)recoveryAttempts);
      GlobalVariableSet(p+"pcl",  (double)partialClosed ? 1 : 0);
      GlobalVariableSet(p+"atr",  lastKnownATR);
      GlobalVariableSet(p+"st",   (double)state);
      GlobalVariableSet(p+"cool", (double)recoveryCooldownExpiry);
     }

   // Load state from Global Variables
   bool LoadState(ulong ticket, const string prefix)
     {
      string p = prefix + IntegerToString((long)ticket) + "_";
      if(!GlobalVariableCheck(p+"dir")) return false;
      mainTicket             = ticket;
      direction              = (int)GlobalVariableGet(p+"dir");
      entryPrice             = GlobalVariableGet(p+"entry");
      entryTime              = (datetime)GlobalVariableGet(p+"etime");
      recoveryAttempts       = (int)GlobalVariableGet(p+"att");
      partialClosed          = (GlobalVariableGet(p+"pcl") > 0.5);
      lastKnownATR           = GlobalVariableGet(p+"atr");
      state                  = (ENUM_TRADE_STATE)(int)GlobalVariableGet(p+"st");
      recoveryCooldownExpiry = (datetime)GlobalVariableGet(p+"cool");
      active = true;
      return true;
     }

   void ClearGVs(const string prefix) const
     {
      if(mainTicket == 0) return;
      string p = prefix + IntegerToString((long)mainTicket) + "_";
      string keys[] = {"dir","entry","etime","att","pcl","atr","st","cool"};
      for(int i=0; i<ArraySize(keys); i++)
         GlobalVariableDel(p + keys[i]);
     }
  };

#endif
