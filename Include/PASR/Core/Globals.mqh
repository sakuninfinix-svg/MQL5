//+------------------------------------------------------------------+
//| Core/Globals.mqh — CANONICAL v2.15                               |
//| Account-safe GV helpers, logging, validation, perf timer         |
//|                                                                   |
//| CHANGELOG:                                                        |
//|   v2.15 (2026-05-24):                                             |
//|     - Added PASRLogWarn() — warning level was missing.            |
//|     - Added IsSpreadAcceptable(maxPips) — used by Stage_RiskCheck. |
//|       Centralised here so broker point-size differences are handled|
//|       in one place.                                               |
//|   v2.14 (2026-05-23) — BUG-001 + BUG-012:                        |
//|     - REMOVED DispatchEvent(PASREvent*) — used fake singleton     |
//|       CEventBus::Instance() which does not exist.                 |
//|       Replace all callers with: bus->Push(ev) directly.           |
//|     - FIXED GVKey(): _MagicNumber is NOT a built-in MQL5 var.     |
//|       Caller MUST pass explicit magic (e.g. InpMagic).            |
//|       magic=0 default is intentional for scripts without magic.   |
//+------------------------------------------------------------------+
#pragma once
#ifndef CORE_GLOBALS_MQH
#define CORE_GLOBALS_MQH

//+------------------------------------------------------------------+
//| ACCOUNT-SAFE GLOBALVARIABLE KEY HELPER                           |
//| Format: {login}_{symbol}_{magic}_{purpose}                       |
//| Prevents collision: live+demo same magic on same terminal        |
//|                                                                   |
//| USAGE: GVKey("peak_equity", InpMagic)                            |
//|   Always pass your EA's magic number explicitly.                 |
//|   magic=0 is allowed for utility scripts with no magic number.   |
//+------------------------------------------------------------------+
string GVKey(const string purpose, const long magic = 0,
             const string symbol = "")
  {
   string acct = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   string sym  = (symbol == "") ? _Symbol : symbol;
   // BUG-012 FIX: _MagicNumber is NOT a MQL5 built-in.
   // Caller must supply the magic explicitly (default 0 for scripts).
   string mag  = IntegerToString(magic);
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

void PASRLogWarn(const string module, const string msg)
  { PrintFormat("[PASR][WARN][%s] %s", module, msg); }

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

// IsSpreadAcceptable: returns true if current spread <= maxPips.
// Handles both 4-digit and 5-digit brokers via _Digits normalisation.
// Use in Stage_RiskCheck before any trade entry evaluation.
bool IsSpreadAcceptable(const double maxPips)
  {
   double pointsPerPip = (_Digits == 3 || _Digits == 5) ? 10.0 : 1.0;
   double spreadPoints = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double spreadPips   = spreadPoints / pointsPerPip;
   return (spreadPips <= maxPips);
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
   void              Stop(const string label) const
     { PrintFormat("[PASR][PERF] %s: %dµs", label, Elapsed()); }
   // Legacy alias
   void              Log(const string label) const { Stop(label); }
  };

//+------------------------------------------------------------------+
//| EVENT DISPATCH — EXPLICIT BUS PARAMETER                          |
//+------------------------------------------------------------------+
// BUG-001 FIX: Removed DispatchEvent(PASREvent*) that used the fake
// singleton CEventBus::Instance(). CEventBus has NO static Instance().
//
// MIGRATION: Replace all DispatchEvent(&ev) calls with:
//   m_bus->Push(ev);    // inside a class that holds m_bus pointer
//   bus->Push(ev);      // in functions that receive bus as parameter
//
// This helper is for utility/script contexts where bus is explicit.
void PASRDispatchEvent(PASREvent &ev, CEventBus *bus)
  {
   if(bus == NULL) return;
   if(CheckPointer(bus) == POINTER_INVALID) return;
   bus.Push(ev);
  }

#endif // CORE_GLOBALS_MQH
