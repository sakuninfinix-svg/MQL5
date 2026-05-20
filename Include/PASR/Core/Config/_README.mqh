//+------------------------------------------------------------------+
//| PASR LAYER 1 — CORE/CONFIG SUBLAYER                             |
//|                                                                  |
//| PURPOSE:                                                         |
//|   Configuration type definitions and management.                 |
//|   Split into two files to separate data from behaviour:         |
//|                                                                  |
//|   Types.mqh   — Pure data: StrategyConfig struct and all        |
//|                 nested sub-structs (RiskConfig, MarketConfig,   |
//|                 ExitConfig, SessionConfig, etc.).               |
//|                 No methods that depend on indicator or account  |
//|                 state. A Validate() method IS allowed here      |
//|                 because it only inspects its own fields.        |
//|                                                                  |
//|   Manager.mqh — Behaviour: reads EA input parameters, builds   |
//|                 StrategyConfig, validates it, and distributes   |
//|                 it to all managers via EventBus ConfigReload.   |
//|                 Also handles hot-reload from file.              |
//|                                                                  |
//| DEPENDENCY RULES:                                               |
//|   Types.mqh   : no includes at all (pure struct file)           |
//|   Manager.mqh : may include Types.mqh + Core/IManager.mqh only |
//+------------------------------------------------------------------+
//
// Migration status:
//   [ ] Types.mqh   — pending (source: ../../2.Config.Types.mqh)
//   [ ] Manager.mqh — pending (source: ../../2.Config.Manager.mqh)
