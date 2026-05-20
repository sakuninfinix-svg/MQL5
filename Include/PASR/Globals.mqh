//+------------------------------------------------------------------+
//|                                                     Globals.mqh  |
//|                                       Copyright 2026, Agsicentre |
//|            Single-Source-of-Truth for all extern declarations    |
//+------------------------------------------------------------------+
//| PURPOSE                                                          |
//| Previously, extern pointers (e.g. g_regimeFilter, g_recorder)   |
//| were declared in multiple .mqh files, causing linker ambiguity   |
//| and undefined ownership. This file centralises ALL extern/global |
//| declarations. Every other file includes this instead of          |
//| re-declaring.                                                    |
//|                                                                  |
//| USAGE                                                            |
//|   In your EA .mq5 entry file:                                    |
//|     #include <PASR/PASR.mqh>   (or #include <PASR/Globals.mqh>) |
//|   Then in OnInit():                                              |
//|     g_recorder     = new EventRecorder();                        |
//|     g_regimeFilter = new MarketRegimeFilter();                   |
//|     g_dashboard    = new DashboardManager();                     |
//|   And in OnDeinit():                                             |
//|     PASR_GLOBALS_DEINIT();                                       |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "1.00"
#property strict

#ifndef __GLOBALS_MQH__
#define __GLOBALS_MQH__

// Forward declarations — full types defined in their own headers
class EventRecorder;
class MarketRegimeFilter;
class DashboardManager;
class DataManager;

//--- EventBus recorder (defined once here; 0.EventBus.mqh uses extern)
EventRecorder       *g_recorder      = NULL;

//--- Market regime filter (owned by main EA file)
MarketRegimeFilter  *g_regimeFilter  = NULL;

//--- Dashboard (owned by main EA file)
DashboardManager    *g_dashboard     = NULL;

//--- Shared DataManager instance (owned by main EA file)
DataManager         *g_dataManager   = NULL;

//+------------------------------------------------------------------+
//| Convenience macro: safe delete + NULL reset                      |
//+------------------------------------------------------------------+
#define SAFE_DELETE(ptr)  do { if(CheckPointer(ptr) != POINTER_INVALID) { delete ptr; ptr = NULL; } } while(false)

//+------------------------------------------------------------------+
//| PASR_GLOBALS_DEINIT — call once in OnDeinit()                    |
//| Deletes all global objects in safe dependency order.             |
//+------------------------------------------------------------------+
#define PASR_GLOBALS_DEINIT() \
   do { \
      SAFE_DELETE(g_dashboard);    \
      SAFE_DELETE(g_regimeFilter); \
      SAFE_DELETE(g_recorder);     \
      SAFE_DELETE(g_dataManager);  \
   } while(false)

#endif // __GLOBALS_MQH__
