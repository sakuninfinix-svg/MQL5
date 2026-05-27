//+------------------------------------------------------------------+
//| Trade/RecoveryEngine.mqh — v2.01                                  |
//| Lightweight recovery state object used by RecoveryManager         |
//+------------------------------------------------------------------+
#property strict
#ifndef __TRADE_RECOVERY_ENGINE_MQH__
#define __TRADE_RECOVERY_ENGINE_MQH__

#define RECOVERY_MAX_ENGINES 16

enum ENUM_RECOVERY_TRADE_STATE
  {
   TRADE_STATE_NORMAL   = 0,
   TRADE_STATE_RECOVERY = 1,
   TRADE_STATE_DONE     = 2
  };

class RecoveryEngine
  {
public:
   bool                      active;
   ulong                     mainTicket;
   int                       direction;   // 1=buy, -1=sell
   double                    entryPrice;
   datetime                  entryTime;
   ENUM_RECOVERY_TRADE_STATE state;
   int                       recoveryAttempts;
   datetime                  recoveryCooldownExpiry;
   double                    lastKnownATR;
   bool                      partialClosed;

   RecoveryEngine()
     {
      Reset();
     }

   void Reset()
     {
      active = false;
      mainTicket = 0;
      direction = 0;
      entryPrice = 0.0;
      entryTime = 0;
      state = TRADE_STATE_NORMAL;
      recoveryAttempts = 0;
      recoveryCooldownExpiry = 0;
      lastKnownATR = 0.0;
      partialClosed = false;
     }

   string KeyPrefix(const string prefix) const
     {
      return prefix + "RECOVERY_" + IntegerToString((long)mainTicket) + "_";
     }

   void SaveState(const string prefix) const
     {
      if(mainTicket == 0) return;
      string k = KeyPrefix(prefix);
      GlobalVariableSet(k + "active", active ? 1.0 : 0.0);
      GlobalVariableSet(k + "ticket", (double)mainTicket);
      GlobalVariableSet(k + "direction", (double)direction);
      GlobalVariableSet(k + "entryPrice", entryPrice);
      GlobalVariableSet(k + "entryTime", (double)entryTime);
      GlobalVariableSet(k + "state", (double)state);
      GlobalVariableSet(k + "attempts", (double)recoveryAttempts);
      GlobalVariableSet(k + "cooldown", (double)recoveryCooldownExpiry);
      GlobalVariableSet(k + "atr", lastKnownATR);
      GlobalVariableSet(k + "partial", partialClosed ? 1.0 : 0.0);
     }

   bool LoadState(const string prefix, const ulong ticket)
     {
      if(ticket == 0) return false;
      mainTicket = ticket;
      string k = KeyPrefix(prefix);
      if(!GlobalVariableCheck(k + "ticket")) return false;
      active = (GlobalVariableGet(k + "active") > 0.5);
      direction = (int)GlobalVariableGet(k + "direction");
      entryPrice = GlobalVariableGet(k + "entryPrice");
      entryTime = (datetime)GlobalVariableGet(k + "entryTime");
      state = (ENUM_RECOVERY_TRADE_STATE)(int)GlobalVariableGet(k + "state");
      recoveryAttempts = (int)GlobalVariableGet(k + "attempts");
      recoveryCooldownExpiry = (datetime)GlobalVariableGet(k + "cooldown");
      lastKnownATR = GlobalVariableGet(k + "atr");
      partialClosed = (GlobalVariableGet(k + "partial") > 0.5);
      return true;
     }

   void ClearGVs(const string prefix) const
     {
      if(mainTicket == 0) return;
      string k = KeyPrefix(prefix);
      GlobalVariableDel(k + "active");
      GlobalVariableDel(k + "ticket");
      GlobalVariableDel(k + "direction");
      GlobalVariableDel(k + "entryPrice");
      GlobalVariableDel(k + "entryTime");
      GlobalVariableDel(k + "state");
      GlobalVariableDel(k + "attempts");
      GlobalVariableDel(k + "cooldown");
      GlobalVariableDel(k + "atr");
      GlobalVariableDel(k + "partial");
     }
  };

#endif // __TRADE_RECOVERY_ENGINE_MQH__
