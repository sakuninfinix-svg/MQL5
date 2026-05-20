# PASR Framework — Quick Start Guide

## 1. Installation

Copy the entire `PASR/` folder into your MetaTrader 5 `Include/` directory:

```
MQL5/
└── Include/
    └── PASR/          ← paste here
        ├── Core/
        ├── Infra/
        ├── Trade/
        └── ...
```

## 2. Include in Your EA

```mql5
// MyExpertAdvisor.mq5
#property copyright "Your Name"
#property version   "1.00"
#property strict

// ── Single line replaces all old numeric includes ──
#include <PASR/Core/PASR.mqh>

// Your input parameters
input int    MagicNumber  = 12345;
input double LotSize      = 0.01;
// ... etc
```

## 3. Initialize the Framework

```mql5
CDataManager*       g_data     = NULL;
CExecutionManager*  g_exec     = NULL;

int OnInit()
  {
   g_data = new CDataManager(MagicNumber);
   g_exec = new CExecutionManager(MagicNumber);

   if(!CheckPointer(g_data) || !CheckPointer(g_exec))
     {
      Print("[PASR] CRITICAL: Manager allocation failed");
      return INIT_FAILED;
     }

   // Load config from EA inputs
   StrategyConfig cfg;
   // ... populate cfg fields from input parameters ...
   g_data.SetConfigCache(cfg);

   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(CheckPointer(g_data))  { delete g_data;  g_data  = NULL; }
   if(CheckPointer(g_exec))  { delete g_exec;  g_exec  = NULL; }
  }
```

## 4. Wire Up Event Handlers

```mql5
void OnTick()
  {
   if(CheckPointer(g_exec))  g_exec.OnPriceUpdate();
  }

void OnTimer()
  {
   // Deferred AI training, config reload checks, etc.
  }
```

## 5. GlobalVariable Key Convention

All GV keys **must** include `AccountInfoInteger(ACCOUNT_LOGIN)` as a prefix.  
This is already handled automatically by `Infra/DataManager.mqh` and `Trade/ExecutionManager.mqh`.

If you create custom GV keys in your EA:

```mql5
// CORRECT
string myKey = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))
             + "_PASR_" + IntegerToString(MagicNumber) + "_MyKey";

// WRONG — causes live/demo cross-contamination
string myKey = "PASR_" + IntegerToString(MagicNumber) + "_MyKey";
```

## 6. QA / Debug Build

```mql5
// Enable full audit + test suite (development only)
#define PASR_QA_BUILD
#include <PASR/Core/PASR.mqh>
```

## 7. Legacy Migration

If your existing EA uses old numeric includes:

```mql5
// OLD (still compiles via shims — deprecated)
#include <PASR/0.EventBus.mqh>
#include <PASR/1.Events.mqh>
#include <PASR/10.DataManager.mqh>
// ... 12 separate includes in exact numeric order ...

// NEW — replace ALL of the above with:
#include <PASR/Core/PASR.mqh>
```

Shims will be removed in **v4.0**. Migrate before then.

---

Full API reference: see [`DOCUMENTATION.md`](./DOCUMENTATION.md)  
Architecture overview: see [`README.md`](./README.md)  
Refactor backlog: see [`IMPROVEMENT_ROADMAP.md`](./IMPROVEMENT_ROADMAP.md)
