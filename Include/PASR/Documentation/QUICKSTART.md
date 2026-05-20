# PASR Framework - Quick Start Guide

**Version:** 1.00  
**Last Updated:** 2026

---

## 🚀 Getting Started dalam 5 Menit

### Step 1: Include PASR di EA Anda

```mql5
//+------------------------------------------------------------------+
//|                                                MyPASREA.mq5      |
//+------------------------------------------------------------------+
#include <PASR/PASR.mqh>

// Global instance
PASR_Framework *g_pasr;

int OnInit()
{
   // Initialize PASR framework
   g_pasr = new PASR_Framework();
   
   if(!g_pasr.Initialize())
   {
      Print("ERROR: Failed to initialize PASR framework");
      return(INIT_FAILED);
   }
   
   Print("PASR Framework initialized successfully!");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(g_pasr != NULL)
   {
      g_pasr.Shutdown();
      delete g_pasr;
   }
}

void OnTick()
{
   if(g_pasr == NULL) return;
   
   // Process tick through PASR event system
   g_pasr.OnTick();
}

void OnTimer()
{
   if(g_pasr == NULL) return;
   
   // Periodic tasks (event batch processing, cleanup, etc.)
   g_pasr.OnTimer();
}
```

---

## 📁 Struktur Folder PASR

```
Include/PASR/
├── Core Layer (Layer 0-1)
│   ├── 0.EventBus.mqh          # Event-driven messaging system
│   ├── 1.Events.mqh            # Event type definitions
│   ├── Globals.mqh             # Global constants & utilities
│   ├── IManager.mqh            # Base manager interface
│   ├── 2.Config.Types.mqh      # Configuration structures
│   └── 2.Config.Manager.mqh    # Configuration management
│
├── Data & Market Layer (Layer 2)
│   ├── 3.MarketManager.mqh     # Market data handling
│   ├── 3.ZoneManager.mqh       # Supply/demand zones
│   ├── 4.SRManager.mqh         # Support/resistance levels
│   ├── 10.DataManager.mqh      # Indicator data caching
│   └── 12.MarketRegime.mqh     # Market regime detection
│
├── Analysis Layer (Layer 3)
│   ├── 9.PatternManager.mqh    # Pattern recognition
│
├── Signal & AI Layer (Layer 4)
│   ├── 5.SignalManager.mqh     # Signal generation
│   ├── 7.AIManager.mqh         # AI/ML integration
│   └── AI/                     # AI sub-modules
│       ├── AITypes.mqh
│       ├── AIFeatureBuilder.mqh
│       ├── AIInference.mqh
│       ├── AIOrchestrator.mqh
│       └── AITrainer.mqh
│
├── Execution Layer (Layer 5)
│   ├── 6.ExecutionManager.mqh  # Order execution
│   ├── 8.RecoveryManager.mqh   # Error recovery
│
├── UI Layer (Layer 6)
│   └── 11.DashboardManager.mqh # Dashboard & visualization
│
├── Tools & Documentation
│   ├── PASR.Audit.mqh          # Automated code audit tool
│   ├── PASR.Test.mqh           # Unit testing framework
│   ├── DOCUMENTATION.md        # Detailed documentation
│   ├── IMPROVEMENT_ROADMAP.md  # 90-day improvement plan
│   └── PERFORMANCE_OPTIMIZATION.md # Performance guide
│
└── Main Entry Point
    └── PASR.mqh                # Main framework orchestrator
```

---

## 🎯 Komponen Utama

### 1. EventBus (Publish-Subscribe Pattern)

```mql5
// Subscribe to price updates
class MyPriceHandler : public IEventHandler {
public:
   void HandleEvent(Event *e) override
   {
      if(e.GetType() == EVENT_PRICE_UPDATE)
      {
         PriceUpdateEvent *priceEvent = (PriceUpdateEvent*)e;
         Print("New tick: ", priceEvent.tick.symbol, 
               " Bid=", priceEvent.tick.bid);
      }
   }
};

// Register handler
MyPriceHandler *handler = new MyPriceHandler();
EventBus::Instance().Subscribe(EVENT_PRICE_UPDATE, handler);
```

### 2. Config Manager

```mql5
// Get configuration
StrategyConfig cfg;
ConfigManager::Instance().GetConfig(cfg);

// Access cached values (fast!)
Print("ATR Period: ", cfg.atr_period);
Print("Max Spread: ", cfg.max_spread);
Print("Risk %: ", cfg.risk_pct);
```

### 3. DataManager

```mql5
// Get indicator values (with caching)
double atr = DataManager::Instance().GetIndicatorValue(INDICATOR_ATR, 0);
double rsi = DataManager::Instance().GetIndicatorValue(INDICATOR_RSI, 0);

// Check if bar changed
if(DataManager::Instance().IsNewBar())
{
   // Update indicators only on new bar
   DataManager::Instance().RefreshIndicators();
}
```

### 4. Signal Manager

```mql5
// Get current signals
Signal *signal = SignalManager::Instance().GetCurrentSignal();

if(signal != NULL)
{
   Print("Signal: ", EnumToString(signal.direction));
   Print("Strength: ", signal.strength);
   Print("Entry Price: ", signal.entryPrice);
}
```

---

## 🔧 Customization

### Mengatur Parameter Strategy

Buat file config `Config/PASR_Config.mqh`:

```mql5
//+------------------------------------------------------------------+
//|                                             PASR_Config.mqh      |
//+------------------------------------------------------------------+

#define CFG_ATR_PERIOD         14
#define CFG_MAX_SPREAD         30
#define CFG_RISK_PERCENT       1.0
#define CFG_SYMBOL             "EURUSD"
#define CFG_TIMEFRAME          PERIOD_H1

// Enable/disable modules
#define CFG_ENABLE_AI          true
#define CFG_ENABLE_PATTERN     true
#define CFG_ENABLE_RECOVERY    true
```

### Membuat Custom Signal Handler

```mql5
#include <PASR/5.SignalManager.mqh>

class MyCustomSignalHandler : public ISignalHandler {
public:
   bool ShouldEnter(Signal *signal) override
   {
      // Add your custom entry logic
      if(signal.direction == SIGNAL_BUY && 
         signal.strength > 0.8 &&
         IsLowSpread() &&
         IsTrendingUp())
      {
         return true;
      }
      return false;
   }
   
   double CalculatePositionSize(Signal *signal) override
   {
      // Custom position sizing logic
      double riskAmount = AccountInfoInteger(ACCOUNT_BALANCE) * 0.01;
      double stopLoss = signal.entryPrice - signal.stopLoss;
      
      return riskAmount / stopLoss;
   }
   
private:
   bool IsLowSpread()
   {
      return (MarketInfo(Symbol(), MODE_SPREAD) < 20);
   }
   
   bool IsTrendingUp()
   {
      // Your trend detection logic
      return true;
   }
};
```

---

## 🧪 Testing & Debugging

### Running Unit Tests

```mql5
#include <PASR/PASR.Test.mqh>

int OnInit()
{
   TestRunner runner;
   
   // Register test suites
   Test_ConfigManager configTest;
   Test_EventBus eventTest;
   
   runner.RegisterTest(configTest);
   runner.RegisterTest(eventTest);
   
   // Run all tests
   TestSuiteReport report = runner.RunAll();
   report.LogReport();
   
   if(report.AllPassed())
      Print("All tests PASSED!");
   else
      Print("Some tests FAILED!");
   
   return(INIT_SUCCEEDED);
}
```

### Running Performance Audit

```mql5
#include <PASR/PASR.Audit.mqh>

void OnTesterInit()
{
   PASRAuditor auditor;
   auditor.RunFullAudit();
}
```

---

## 📊 Monitoring & Metrics

### Accessing Runtime Metrics

```mql5
// Get performance metrics
ulong eventCount = g_pasr.GetMetric("events_processed");
double avgLatency = g_pasr.GetMetric("avg_event_latency");
ulong memoryUsage = g_pasr.GetMetric("memory_usage_bytes");

Print("Events Processed: ", eventCount);
Print("Avg Latency: ", avgLatency, " µs");
Print("Memory Usage: ", memoryUsage / 1024.0, " KB");
```

### Enabling Debug Logging

```mql5
// In initialization
Globals::SetLogLevel(LOG_DEBUG);

// Now all debug messages will be printed
LogDebug("DataManager", "Indicator cache refreshed");
LogInfo("SignalManager", "New buy signal detected");
LogWarning("ExecutionManager", "High spread detected");
LogError("RecoveryManager", "Order execution failed");
```

---

## ⚡ Performance Tips

### 1. Use Event Batching

```mql5
// Instead of dispatching events immediately
void OnTick()
{
   // Dispatch deferred, process in batch
   EventBus::Instance().DispatchDeferred(new PriceUpdateEvent(tick));
}

void OnTimer()
{
   // Process all deferred events every 100ms
   EventBus::Instance().ProcessBatch();
}
```

### 2. Leverage Indicator Caching

```mql5
// BAD: Call CopyBuffer every tick
double atr = iATR(Symbol(), Period(), 14, 1);

// GOOD: Use cached values
double atr = DataManager::Instance().GetIndicatorValue(INDICATOR_ATR, 1);
```

### 3. Pre-allocate Objects

```mql5
// Object pool for events
EventPool g_pool(100);

void OnTick()
{
   PriceUpdateEvent *e = (PriceUpdateEvent*)g_pool.Acquire();
   // ... use event
   g_pool.Release(e); // Returns to pool, no deletion
}
```

---

## 🐛 Troubleshooting

### Common Issues

**Issue:** "Event not being received"
- **Solution:** Check if handler is properly registered with `Subscribe()`
- Verify event type matches

**Issue:** "High memory usage"
- **Solution:** Enable object pooling
- Check for memory leaks with `PASR.Audit.mqh`

**Issue:** "Slow tick processing"
- **Solution:** Use lazy indicator updates
- Implement tick batching
- Profile with built-in profiler

**Issue:** "Circular dependency error"
- **Solution:** Use forward declarations
- Follow layer architecture (higher layers can depend on lower layers only)

---

## 📚 Next Steps

1. **Read DOCUMENTATION.md** - Deep dive into architecture
2. **Review IMPROVEMENT_ROADMAP.md** - 90-day enhancement plan
3. **Study PERFORMANCE_OPTIMIZATION.md** - Advanced optimization techniques
4. **Run PASR.Audit.mqh** - Automated code quality check
5. **Write unit tests** - Use PASR.Test.mqh framework

---

## 🤝 Support & Contribution

**Documentation:** See `DOCUMENTATION.md` for detailed API reference  
**Issues:** Check `IMPROVEMENT_ROADMAP.md` for known issues  
**Performance:** Refer to `PERFORMANCE_OPTIMIZATION.md` for tuning guide  

---

**Happy Trading with PASR! 📈**
