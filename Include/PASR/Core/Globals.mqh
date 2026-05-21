//+------------------------------------------------------------------+
//| Core/Globals.mqh — CANONICAL v2.13                               |
//| Account-safe GV helpers, logging, validation, perf timer         |
//+------------------------------------------------------------------+
#pragma once
#ifndef CORE_GLOBALS_MQH
#define CORE_GLOBALS_MQH

//+------------------------------------------------------------------+
//| ACCOUNT-SAFE GLOBALVARIABLE KEY HELPER                           |
//| Format: {login}_{symbol}_{magic}_{purpose}                       |
//| Prevents collision: live+demo same magic on same terminal        |
//+------------------------------------------------------------------+
string GVKey(const string purpose, const long magic = 0,
             const string symbol = "")
  {
   string acct = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   string sym  = (symbol == "") ? _Symbol : symbol;
   string mag  = (magic  == 0)  ? IntegerToString(_MagicNumber)
                                 : IntegerToString(magic);
   return acct + "_" + sym + "_" + mag + "_" + purpose;
  }

bool GVSet(const string purpose, const double value,
           const long magic = 0, const string symbol = "")
  { return GlobalVariableSet(GVKey(purpose, magic, symbol), value) > 0; }

double GVGet(const string purpose, const double defaultVal = 0.0,
             const long magic = 0, const string symbol = "")
  {
   string key = GVKey(purpose, magic, symbol);
   if(!GlobalVariableCheck(key)) return defaultVal;
   return GlobalVariableGet(key);
  }

bool GVDelete(const string purpose, const long magic = 0,
              const string symbol = "")
  { return GlobalVariableDelete(GVKey(purpose, magic, symbol)); }

bool GVExists(const string purpose, const long magic = 0,
              const string symbol = "")
  { return GlobalVariableCheck(GVKey(purpose, magic, symbol)); }

//+------------------------------------------------------------------+
//| LOGGING HELPERS                                                   |
//+------------------------------------------------------------------+
void PASRLog(const string module, const string msg)
  { PrintFormat("[PASR][%s] %s", module, msg); }

void PASRLogError(const string module, const string msg,
                  const int errorCode = 0)
  {
   if(errorCode != 0)
      PrintFormat("[PASR][ERROR][%s] %s | Code: %d", module, msg, errorCode);
   else
      PrintFormat("[PASR][ERROR][%s] %s", module, msg);
  }

//+------------------------------------------------------------------+
//| VALIDATION HELPERS                                                |
//+------------------------------------------------------------------+
bool IsValidPrice(const double price)
  { return (price > 0.0 && MathIsValidNumber(price)); }

bool IsValidVolume(const double volume)
  {
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   return (volume >= minLot && volume <= maxLot);
  }

bool IsMarketOpen()
  {
   MqlTick lastTick;
   if(!SymbolInfoTick(_Symbol, lastTick)) return false;
   return ((TimeCurrent() - lastTick.time) < 60);
  }

//+------------------------------------------------------------------+
//| PERF TIMER (microsecond resolution)                              |
//+------------------------------------------------------------------+
class CPerfTimer
  {
private:
   ulong             m_start;
public:
   void              Start()  { m_start = GetMicrosecondCount(); }
   ulong             Elapsed() const { return GetMicrosecondCount() - m_start; }
   void              Log(const string label) const
     { PrintFormat("[PASR][PERF] %s: %dµs", label, Elapsed()); }
  };

//+------------------------------------------------------------------+
//| GLOBAL EVENT DISPATCHER HELPER                                   |
//+------------------------------------------------------------------+
// Helper function for EA scripts to dispatch events to EventBus
// This wraps the EventBus::Push() call for convenience
void DispatchEvent(PASREvent *ev)
  {
   if(CheckPointer(ev) == POINTER_INVALID) return;
   
   CEventBus *bus = CEventBus::Instance();
   if(CheckPointer(bus) != POINTER_INVALID)
      bus.Push(*ev);
   else
   {
      // Event deleted after push in Push() method, but if bus is invalid, delete here
      delete ev;
   }
  }

#endif // CORE_GLOBALS_MQH
