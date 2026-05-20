//+------------------------------------------------------------------+
//|                                                    Globals.mqh   |
//|                                       Copyright 2026, Agsicentre |
//|  Global utilities, singleton registry, GV key helpers            |
//|                                                                   |
//|  CRITICAL: All GlobalVariable keys MUST use GVKey() helper       |
//|  to prevent state corruption between live+demo instances         |
//|  sharing the same magic number on the same terminal.             |
//+------------------------------------------------------------------+
#property strict

#ifndef __GLOBALS_MQH__
#define __GLOBALS_MQH__

// =================================================================
// ACCOUNT-SAFE GLOBAL VARIABLE KEY HELPER
// =================================================================
// Prevents GV key collision between:
//   - Same EA running on live + demo account simultaneously
//   - Two EA instances with same magic number on different symbols
//
// Usage:
//   string key = GVKey("TRADE_STATE", magicNumber);
//   GlobalVariableSet(key, value);
//
// Result example:
//   "123456789_EURUSD_12345_TRADE_STATE"
//   ^login     ^symbol ^magic ^purpose
// =================================================================
string GVKey(const string purpose, const long magic = 0,
             const string symbol = "") {
    string acct   = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
    string sym    = (symbol == "") ? _Symbol : symbol;
    string mag    = (magic  == 0)  ? IntegerToString(_MagicNumber) :
                                     IntegerToString(magic);
    return acct + "_" + sym + "_" + mag + "_" + purpose;
}

// =================================================================
// ACCOUNT-SAFE GLOBAL VARIABLE HELPERS
// =================================================================

bool GVSet(const string purpose, const double value,
           const long magic = 0, const string symbol = "") {
    return GlobalVariableSet(GVKey(purpose, magic, symbol), value) > 0;
}

double GVGet(const string purpose, const double defaultVal = 0.0,
             const long magic = 0, const string symbol = "") {
    string key = GVKey(purpose, magic, symbol);
    if (!GlobalVariableCheck(key)) return defaultVal;
    return GlobalVariableGet(key);
}

bool GVDelete(const string purpose, const long magic = 0,
              const string symbol = "") {
    return GlobalVariableDelete(GVKey(purpose, magic, symbol));
}

bool GVExists(const string purpose, const long magic = 0,
              const string symbol = "") {
    return GlobalVariableCheck(GVKey(purpose, magic, symbol));
}

// =================================================================
// LOGGING HELPERS
// =================================================================

void PASRLog(const string module, const string msg,
             const bool verbose = false) {
#ifdef PASR_DEBUG
    PrintFormat("[PASR][%s] %s", module, msg);
#else
    if (verbose) return; // suppress in release unless verbose=false
    PrintFormat("[PASR][%s] %s", module, msg);
#endif
}

void PASRLogError(const string module, const string msg,
                  const int errorCode = 0) {
    if (errorCode != 0)
        PrintFormat("[PASR][ERROR][%s] %s | Code: %d", module, msg, errorCode);
    else
        PrintFormat("[PASR][ERROR][%s] %s", module, msg);
}

// =================================================================
// VALIDATION HELPERS
// =================================================================

bool IsValidPrice(const double price) {
    return (price > 0.0 && !MathIsValidNumber(price) == false);
}

bool IsValidVolume(const double volume) {
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    return (volume >= minLot && volume <= maxLot);
}

bool IsMarketOpen() {
    MqlTick lastTick;
    if (!SymbolInfoTick(_Symbol, lastTick)) return false;
    return ((TimeCurrent() - lastTick.time) < 60); // stale > 60s = closed
}

// =================================================================
// PERF TIMER (microsecond resolution)
// =================================================================

class CPerfTimer {
private:
    ulong m_start;
public:
    void   Start()  { m_start = GetMicrosecondCount(); }
    ulong  Elapsed() const { return GetMicrosecondCount() - m_start; }
    void   Log(const string label) const {
        PrintFormat("[PASR][PERF] %s: %dµs", label, Elapsed());
    }
};

#endif // __GLOBALS_MQH__
