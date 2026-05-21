//+------------------------------------------------------------------+
//| Core/ConfigTypes.mqh                                             |
//+------------------------------------------------------------------+
//  MIGRATION STATUS: DEPRECATED SHIM
//  ────────────────────────────────────────────────────────────────────
//  Canonical file : Core/Config/Types.mqh
//  This shim      : ONLY for legacy N.*.mqh files not yet migrated
//  Removal plan   : Delete after all legacy files migrated to
//                   #include "Config/Types.mqh" directly
//  DO NOT add new #includes of this file. Use Config/Types.mqh.
//+------------------------------------------------------------------+

// Emit a compile-time notice so any direct includer is visible in build log.
// Change to #error after all legacy N.*.mqh are migrated.
#ifdef PASR_STRICT_INCLUDES
   #error "ConfigTypes.mqh is deprecated. Use Core/Config/Types.mqh directly."
#endif

#ifndef __CORE_CONFIG_TYPES_SHIM_MQH__
#define __CORE_CONFIG_TYPES_SHIM_MQH__

// Forward all consumers to the canonical file.
// Header guard in Config/Types.mqh ensures no double-definition.
#include "Config/Types.mqh"

#endif // __CORE_CONFIG_TYPES_SHIM_MQH__
