//+------------------------------------------------------------------+
//| PASR LAYER 1 — CORE / FOUNDATION                                |
//|                                                                  |
//| PURPOSE:                                                         |
//|   The lowest layer of the PASR framework. Defines the           |
//|   fundamental building blocks that every other layer depends on. |
//|                                                                  |
//| CONTENTS:                                                        |
//|   IManager.mqh      — Abstract base class for all managers      |
//|   EventBus.mqh      — Event bus engine & priority queue         |
//|   Events.mqh        — All event struct/enum definitions         |
//|   Config/Types.mqh  — StrategyConfig + all sub-structs          |
//|   Config/Manager.mqh — Config validation, reload, distribution  |
//|                                                                  |
//| DEPENDENCY RULES (STRICT):                                       |
//|   ✅ MAY include   : other files within Core/ only              |
//|   ❌ MUST NOT include: Infra/, Analysis/, Signal/, Trade/, UI/  |
//|                                                                  |
//| RATIONALE:                                                       |
//|   Core has zero knowledge of business logic. If a Core file     |
//|   needs to reference a type from another layer, that is a       |
//|   design smell — use forward declarations or interfaces instead. |
//+------------------------------------------------------------------+
//
// This file is a layer documentation stub.
// It is never included by production code.
// Migration status:
//   [ ] IManager.mqh      — pending (source: ../IManager.mqh)
//   [ ] EventBus.mqh      — pending (source: ../0.EventBus.mqh)
//   [ ] Events.mqh        — pending (source: ../1.Events.mqh)
//   [ ] Config/Types.mqh  — pending (source: ../2.Config.Types.mqh)
//   [ ] Config/Manager.mqh — pending (source: ../2.Config.Manager.mqh)
