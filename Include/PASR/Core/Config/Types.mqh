//+------------------------------------------------------------------+
//|                                        Core/Config/Types.mqh     |
//|                                       Copyright 2026, Agsicentre |
//|            Config Type Definitions - forwarded from root         |
//+------------------------------------------------------------------+
//| This file is a clean re-include shim.                            |
//| Full type definitions live in Include/PASR/2.Config.Types.mqh   |
//| until that file is fully migrated here.                          |
//+------------------------------------------------------------------+

#property strict

#ifndef __CORE_CONFIG_TYPES_MQH__
#define __CORE_CONFIG_TYPES_MQH__

// Re-include the root file that contains the full StrategyConfig struct
// and all associated config types (SignalDecision, etc.).
// Once migration of 2.Config.Types.mqh is complete, move all content here
// and delete the root file.
#include "../../2.Config.Types.mqh"

#endif // __CORE_CONFIG_TYPES_MQH__
