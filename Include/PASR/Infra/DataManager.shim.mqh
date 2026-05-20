//+------------------------------------------------------------------+
//|                                  Infra/DataManager.shim.mqh    |
//|                          Copyright 2026, Agsicentre             |
//|   Backward-compatibility shim for legacy includes               |
//|                                                                  |
//|   If your EA or module uses:                                     |
//|       #include "10.DataManager.mqh"                             |
//|   Replace with:                                                  |
//|       #include "Infra/DataManager.mqh"                          |
//|                                                                  |
//|   This shim is a TEMPORARY bridge and will be REMOVED in v4.0.  |
//|   Migration deadline: PASR v4.0                                  |
//+------------------------------------------------------------------+

#property strict

#ifndef __INFRA_DATA_MANAGER_SHIM_MQH__
#define __INFRA_DATA_MANAGER_SHIM_MQH__

#pragma message("[PASR] WARNING: 10.DataManager.mqh shim used. " \
                "Migrate to #include \"Infra/DataManager.mqh\"")

#include "DataManager.mqh"

#endif // __INFRA_DATA_MANAGER_SHIM_MQH__
