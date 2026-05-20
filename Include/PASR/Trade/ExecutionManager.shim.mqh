//+------------------------------------------------------------------+
//|                             Trade/ExecutionManager.shim.mqh    |
//|                          Copyright 2026, Agsicentre             |
//|   Backward-compatibility shim for legacy includes               |
//|                                                                  |
//|   If your EA or module uses:                                     |
//|       #include "6.ExecutionManager.mqh"                         |
//|   Replace with:                                                  |
//|       #include "Trade/ExecutionManager.mqh"                     |
//|                                                                  |
//|   This shim is TEMPORARY and will be removed in v4.0.           |
//+------------------------------------------------------------------+

#property strict

#ifndef __TRADE_EXECUTION_MANAGER_SHIM_MQH__
#define __TRADE_EXECUTION_MANAGER_SHIM_MQH__

#pragma message("[PASR] WARNING: 6.ExecutionManager.mqh shim used. " \
                "Migrate to #include \"Trade/ExecutionManager.mqh\"")

#include "ExecutionManager.mqh"

#endif // __TRADE_EXECUTION_MANAGER_SHIM_MQH__
