//+------------------------------------------------------------------+
//|                                              3.MarketManager.mqh |
//|                                       Copyright 2026, Agsicentre |
//|            Market State & Session Management Module              |
//|                   V2.3 - IM-OPT-1 Config() accessor migration    |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "2.30"
#property strict
// v2.30 — IM-OPT-1: Replaced all StrategyConfig cfg; m_data.GetConfigCache(cfg) (7 per-function
//          struct copies) with Config() zero-copy const-ref accessor from IManager.
//          Eliminates ~400-byte stack alloc x 7 calls per bar.
