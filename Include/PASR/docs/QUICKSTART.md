# PASR Quick Start

Use `CPASRKernel` through the master include:

```mql5
#include <PASR/Core/PASR.mqh>

CPASRKernel kernel;
StrategyConfig cfg;

int OnInit()
  {
   if(kernel.Init(cfg) != INIT_SUCCEEDED)
      return INIT_FAILED;

   EventSetTimer(1);
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   kernel.OnTick();
  }

void OnTimer()
  {
   kernel.OnTimer();
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   kernel.OnTradeTransaction(trans, request, result);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   kernel.OnDeinit(reason);
  }
```

Compile gates after architecture changes:

```text
Experts/PASR_MODULAR.mq5
Scripts/PASR_Smoke.mq5
Scripts/PASR_PipelineHarness_Smoke.mq5
```

Expected baseline: `0 errors, 0 warnings`.
