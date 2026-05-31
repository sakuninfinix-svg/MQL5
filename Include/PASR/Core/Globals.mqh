//+------------------------------------------------------------------+
//| Core/Globals.mqh - CANONICAL v2.16                               |
//| Account-safe GV helpers, logging, validation, perf timer         |
//+------------------------------------------------------------------+
#ifndef CORE_GLOBALS_MQH
#define CORE_GLOBALS_MQH

string GVKey(const string purpose, const long magic = 0, const string symbol = "")
  {
   string acct = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   string sym  = (symbol == "") ? _Symbol : symbol;
   string mag  = IntegerToString(magic);
   return acct + "_" + sym + "_" + mag + "_" + purpose;
  }

bool GVSet(const string purpose, const double value, const long magic = 0, const string symbol = "")
  { return GlobalVariableSet(GVKey(purpose, magic, symbol), value) > 0; }

double GVGet(const string purpose, const double defaultVal = 0.0, const long magic = 0, const string symbol = "")
  {
   string key = GVKey(purpose, magic, symbol);
   if(!GlobalVariableCheck(key)) return defaultVal;
   return GlobalVariableGet(key);
  }

bool GVDelete(const string purpose, const long magic = 0, const string symbol = "")
  { return GlobalVariableDelete(GVKey(purpose, magic, symbol)); }

bool GVExists(const string purpose, const long magic = 0, const string symbol = "")
  { return GlobalVariableCheck(GVKey(purpose, magic, symbol)); }

void PASRLog(const string module, const string msg)
  { PrintFormat("[PASR][%s] %s", module, msg); }

void PASRLogInfo(const string module, const string msg)
  { PrintFormat("[PASR][INFO][%s] %s", module, msg); }

void PASRLogWarn(const string module, const string msg)
  { PrintFormat("[PASR][WARN][%s] %s", module, msg); }

void PASRLogError(const string module, const string msg, const int errorCode = 0)
  {
   if(errorCode != 0)
      PrintFormat("[PASR][ERROR][%s] %s | Code: %d", module, msg, errorCode);
   else
      PrintFormat("[PASR][ERROR][%s] %s", module, msg);
  }

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

bool IsSpreadAcceptable(const double maxPips)
  {
   double pointsPerPip = (_Digits == 3 || _Digits == 5) ? 10.0 : 1.0;
   double spreadPoints = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double spreadPips = spreadPoints / pointsPerPip;
   return (spreadPips <= maxPips);
  }

class CPerfTimer
  {
private:
   ulong m_start;
public:
   void Start() { m_start = GetMicrosecondCount(); }
   ulong Elapsed() const { return GetMicrosecondCount() - m_start; }
   void Stop(const string label) const { PrintFormat("[PASR][PERF] %s: %I64u us", label, Elapsed()); }
   void Log(const string label) const { Stop(label); }
  };

#endif // CORE_GLOBALS_MQH