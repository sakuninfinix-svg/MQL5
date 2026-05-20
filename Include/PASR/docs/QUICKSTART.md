# PASR Framework — Quick Start

## 1. Include dalam EA Kamu

```mql5
// Satu baris — semua layer tersedia
#include <PASR/PASR.mqh>
```

Atau hanya layer tertentu:

```mql5
#include <PASR/Core/EventBus.mqh>          // Event system saja
#include <PASR/Core/Config/Types.mqh>       // Config types saja
#include <PASR/Signal/SignalManager.mqh>    // Signal layer saja
```

## 2. Init dalam OnInit()

```mql5
CExecutionManager *g_exec = NULL;

int OnInit() {
    g_exec = new CExecutionManager(GetPointer(g_data));
    if (!g_exec.Init()) {
        Print("[PASR] ExecutionManager init failed");
        return INIT_FAILED;
    }
    return INIT_SUCCEEDED;
}
```

## 3. Gunakan GVKey() untuk GlobalVariables

```mql5
// JANGAN: GlobalVariableSet("TRADE_STATE", 1.0);
// BENAR:
#include <PASR/Globals.mqh>
GVSet("TRADE_STATE", 1.0);  // auto-prefix dengan account+symbol+magic
```

## 4. Cleanup di OnDeinit()

```mql5
void OnDeinit(const int reason) {
    if (g_exec != NULL) { g_exec.Shutdown(); delete g_exec; g_exec = NULL; }
}
```

## Tips

- `PASR.mqh` enforce load order — jangan include manual file numbered
- Enable debug logs: add `#define PASR_DEBUG` sebelum `#include <PASR/PASR.mqh>`
- Gunakan `CPerfTimer` dari `Globals.mqh` untuk profiling tick handler
