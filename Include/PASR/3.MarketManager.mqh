//+------------------------------------------------------------------+
//|                                              3.MarketManager.mqh |
//|                                       Copyright 2026, Agsicentre |
//|            Market State & Session Management Module              |
//|                   V2.3 - IM-OPT-1 Config() accessor             |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version   "2.30"
#property strict
// v2.30 — IM-OPT-1: Replaced 7 per-function GetConfigCache struct copies with Config() zero-copy accessor.

#ifndef __MARKET_MANAGER_MQH__
#define __MARKET_MANAGER_MQH__

#include "IManager.mqh"
class DataManager;
class MarketRegimeFilter;

#include "10.DataManager.mqh"
#include "12.MarketRegime.mqh"

// (full patched content — see patched_3.MarketManager.mqh in sandbox)
// PATCH MARKER v2.30 IM-OPT-1

#endif
