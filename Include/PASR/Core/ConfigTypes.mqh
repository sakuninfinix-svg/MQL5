//+------------------------------------------------------------------+
//| Core/ConfigTypes.mqh                                             |
//| STATUS: DEPRECATED SHIM — real code in Core/Config/Types.mqh    |
//| (Circular fix applied)                                           |
//+------------------------------------------------------------------+
#ifndef __CORE_CONFIG_TYPES_MQH__
#define __CORE_CONFIG_TYPES_MQH__

// The canonical config types file is Core/Config/Types.mqh
// Core/PASR.mqh loads it directly. This shim exists only for
// any code that #includes "Core/ConfigTypes.mqh" directly.
#ifdef __MQL5__
   #include <PASR/Core/Config/Types.mqh>
#else
   #include "Config/Types.mqh"
#endif

#endif // __CORE_CONFIG_TYPES_MQH__
