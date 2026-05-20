# PASR EA Framework — Quick Start

> v2.13 | All 14 modules canonical or scaffolded

## Single Include

```cpp
// Only ONE line needed in your EA:
#include <PASR/Core/PASR.mqh>
```

This loads all modules in the correct dependency order.

## Minimum EA Skeleton

```cpp
#include <PASR/Core/PASR.mqh>

CPASREngine engine;

int OnInit()
  {
   EventSetTimer(1);  // required for deferred AI training
   return engine.Init() ? INIT_SUCCEEDED : INIT_FAILED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   engine.Deinit();
  }

void OnTick()   { engine.OnTick();  }
void OnTimer()  { engine.OnTimer(); }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &req,
                        const MqlTradeResult  &res)
  {
   engine.OnTradeTransaction(trans, req, res);
  }
```

## Legacy Includes (still work)

All numbered files (`0.EventBus.mqh`, `1.Events.mqh`, etc.) are thin forwarders.
They still compile but should be migrated at your convenience.

## Module Paths (v2.13)

| Module | Canonical Path |
|---|---|
| EventBus | `Core/EventBus.mqh` |
| Events | `Core/Events.mqh` |
| IManager | `Core/IManager.mqh` |
| Globals | `Core/Globals.mqh` |
| Config Types | `Core/Config/Types.mqh` |
| Config Manager | `Core/Config/Manager.mqh` |
| DataManager | `Infra/DataManager.mqh` |
| MarketManager | `Data/MarketManager.mqh` |
| ZoneManager | `Data/ZoneManager.mqh` |
| SRManager | `Data/SRManager.mqh` |
| MarketRegime | `Data/MarketRegime.mqh` |
| PatternManager | `Pattern/PatternManager.mqh` |
| SignalManager | `Signal/SignalManager.mqh` |
| ExecutionManager | `Trade/ExecutionManager.mqh` |
| RecoveryManager | `Trade/RecoveryManager.mqh` |
| AIManager | `AI/AIManager.mqh` |
| DashboardManager | `UI/DashboardManager.mqh` |

## AI Training Note

`CAITrainer::TrainStep()` runs on `OnTimer()` only — **never** on `OnTick()`.
Always enable `EventSetTimer(1)` in `OnInit()` to activate training.

## See Also

- `README.md` — full architecture + event flow diagram
- `MIGRATION_MAP.md` — migration status + remaining v3.0 work
- `QA/` + `PASR.Test.mqh` — unit test runner
