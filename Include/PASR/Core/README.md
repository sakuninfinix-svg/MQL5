//+------------------------------------------------------------------+
//| PASR LAYER 0 — CORE                                             |
//|                                                                  |
//| PURPOSE:                                                         |
//|   Foundation layer. No dependencies on any other PASR layer.    |
//|   All other layers depend on Core, never the reverse.            |
//|                                                                  |
//| CONTENTS:                                                        |
//|   EventBus.mqh     — CEventBus priority queue dispatcher        |
//|   Events.mqh       — All IEvent subclass definitions             |
//|   ConfigTypes.mqh  — StrategyConfig + all sub-structs            |
//|   IManager.mqh     — Abstract base class for all managers        |
//|   Globals.mqh      — Global singleton declarations               |
//|                                                                  |
//| DEPENDENCY RULES:                                                |
//|   ✅ MAY include   : <stdlib>, <Trade/Trade.mqh>                 |
//|   ❌ MUST NOT include: any other PASR layer                      |
//|                                                                  |
//| MIGRATION STATUS:                                                |
//|   Forwarding shims created for all 5 files.                      |
//|   Legacy root files (0.EventBus, 1.Events, etc.) now deprecated. |
//|   Remove legacy files in v3.0 after all consumers migrated.      |
//+------------------------------------------------------------------+
//
// This file is a layer documentation stub — never included.
