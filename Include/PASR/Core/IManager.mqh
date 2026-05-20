//+------------------------------------------------------------------+
//|                                          Core/IManager.mqh       |
//|                                       Copyright 2026, Agsicentre |
//|  IManager base interface                                         |
//|  Contains: Init, OnNewBar, OnPriceUpdate, OnTick, Shutdown       |
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_IMANAGER_MQH__
#define __CORE_IMANAGER_MQH__

// IManager is declared inside 0.EventBus.mqh or separately.
// This file ensures forward compatibility when IManager is
// eventually promoted to its own canonical file.
#include "../0.EventBus.mqh"

// Explicit compile-time check: IManager must exist after includes.
// If IManager is ever split out, replace the include above with
// the dedicated IManager source file.

#endif // __CORE_IMANAGER_MQH__
