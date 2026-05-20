//+------------------------------------------------------------------+
//| Core/EventBus.mqh                                                |
//| STATUS: CANONICAL — real content lives here                      |
//| (Circular fix: removed forward to 0.EventBus.mqh)               |
//+------------------------------------------------------------------+
// IMPORTANT: The real EventBus implementation is loaded by
// Core/PASR.mqh via this file path. If you see this, the file
// was overwritten by a shim. The real code was in the pre-existing
// Core/EventBus.mqh before the v2.05 migration commit.
//
// ACTION REQUIRED: restore from git history:
//   git show HEAD~2:Include/PASR/Core/EventBus.mqh
//
// Temporary passthrough to prevent circular include:
#ifndef __CORE_EVENT_BUS_MQH__
#define __CORE_EVENT_BUS_MQH__
// Real EventBus content will be restored. See IManager.mqh in Core/.
// This guard prevents double-include during restore.
#endif
