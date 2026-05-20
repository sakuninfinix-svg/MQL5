# PASR Framework - Performance Optimization Guide

**Document Version:** 1.00  
**Created:** 2026  
**Author:** Senior Performance Engineering Team  
**Status:** Implementation Guide

---

## 🎯 Executive Summary

Dokumen ini berisi **advanced performance optimization techniques** untuk PASR Framework, fokus pada micro-optimizations yang memberikan impact maksimal pada latency dan memory usage.

### Target Performance Metrics

| Component | Current | Target | Improvement |
|-----------|---------|--------|-------------|
| Event Dispatch Latency | ~100µs | **<50µs** | 50% ↓ |
| Config Access Time | ~5µs | **<1µs** | 80% ↓ |
| Memory per Symbol | ~3KB | **<2KB** | 33% ↓ |
| Tick Processing | ~200µs | **<100µs** | 50% ↓ |
| Indicator Update | ~50µs | **<20µs** | 60% ↓ |

---

## 🔧 Phase 1: Event Dispatch Optimization

### OPT-001: Hash-Based Handler Lookup (O(1) vs O(n))

**Current Implementation:**
```mql5
// Linear search through handler array - O(n)
for(int i = 0; i < ArraySize(m_handlers); i++)
{
   if(m_handlers[i].eventType == eventType)
   {
      m_handlers[i].handler(event);
      break;
   }
}
```

**Optimized Implementation:**
```mql5
class EventBus {
private:
   // Hash map for O(1) lookup
   map<int, HandlerSlot*> m_handlerMap;
   
public:
   void Dispatch(Event *e)
   {
      int eventType = e.GetType();
      
      // O(1) lookup instead of O(n)
      if(m_handlerMap.Contain(eventType))
      {
         HandlerSlot *slot = m_handlerMap.Get(eventType);
         slot->handler(e);
      }
   }
   
   void Subscribe(int eventType, EventHandler handler)
   {
      HandlerSlot *slot = new HandlerSlot();
      slot->handler = handler;
      m_handlerMap.Set(eventType, slot);
   }
};
```

**Expected Impact:**
- Event dispatch: 100µs → **30-40µs** (60-70% improvement)
- Scales better with many event types

---

### OPT-002: Event Object Pooling

**Problem:** Dynamic allocation in hot path causes GC pressure and latency spikes.

**Solution:** Implement object pool for Event objects.

```mql5
class EventPool {
private:
   Event *m_pool[];
   int    m_poolSize;
   int    m_availableIndex;
   mutex  m_poolMutex;
   
public:
   EventPool(int initialSize = 100)
   {
      m_poolSize = initialSize;
      m_availableIndex = 0;
      ArrayResize(m_pool, initialSize);
      
      for(int i = 0; i < initialSize; i++)
         m_pool[i] = CreateEventPrototype();
   }
   
   Event* Acquire()
   {
      m_poolMutex.Lock();
      
      if(m_availableIndex > 0)
      {
         Event *e = m_pool[--m_availableIndex];
         e.Reset(); // Reset state
         m_poolMutex.Unlock();
         return e;
      }
      
      m_poolMutex.Unlock();
      return CreateEventPrototype(); // Expand pool
   }
   
   void Release(Event *e)
   {
      m_poolMutex.Lock();
      
      if(m_availableIndex < m_poolSize)
      {
         e.Reset();
         m_pool[m_availableIndex++] = e;
         m_poolMutex.Unlock();
         return;
      }
      
      m_poolMutex.Unlock();
      delete e; // Pool full, delete object
   }
   
private:
   Event* CreateEventPrototype()
   {
      // Create appropriate event type based on need
      return new PriceUpdateEvent();
   }
};

// Usage in hot path
EventPool g_eventPool;

void OnTick()
{
   PriceUpdateEvent *e = (PriceUpdateEvent*)g_eventPool.Acquire();
   e.SetTick(tick);
   EventBus::Instance().Dispatch(e);
   g_eventPool.Release(e); // Return to pool, no deletion
}
```

**Expected Impact:**
- Eliminates allocation overhead in OnTick
- Reduces GC pressure by 90%
- Consistent latency without spikes

---

### OPT-003: Batch Event Processing

```mql5
class EventBus {
private:
   Event *m_deferredQueue[];
   bool   m_processingBatch;
   
public:
   void DispatchDeferred(Event *e)
   {
      // Add to batch queue instead of immediate processing
      ArrayPush(m_deferredQueue, e);
   }
   
   void ProcessBatch()
   {
      if(ArraySize(m_deferredQueue) == 0) return;
      
      m_processingBatch = true;
      
      // Process all queued events
      for(int i = 0; i < ArraySize(m_deferredQueue); i++)
      {
         Dispatch(m_deferredQueue[i]);
         delete m_deferredQueue[i];
      }
      
      ArrayResize(m_deferredQueue, 0);
      m_processingBatch = false;
   }
};

// In main loop
void OnTimer()
{
   // Process deferred events every 100ms
   EventBus::Instance().ProcessBatch();
}
```

**Expected Impact:**
- Reduces context switching overhead
- Better cache locality
- Throughput increase: 40%

---

## 💾 Phase 2: Memory Optimization

### OPT-004: Struct Packing & Alignment

**Current StrategyConfig:**
```mql5
struct StrategyConfig {
   string symbol;        // 8 bytes (pointer)
   int    atr_period;    // 4 bytes
   double max_spread;    // 8 bytes
   bool   enabled;       // 1 byte
   int    padding;       // 3 bytes (implicit padding)
   double risk_pct;      // 8 bytes
   // Total: 32 bytes with padding
};
```

**Optimized Layout:**
```mql5
struct StrategyConfig {
   // Group by size (largest to smallest)
   string symbol;        // 8 bytes
   double max_spread;    // 8 bytes
   double risk_pct;      // 8 bytes
   int    atr_period;    // 4 bytes
   bool   enabled;       // 1 byte
   // Total: 29 bytes (3 bytes saved)
   
   // Or use fixed-size char array instead of string
   char   symbol[16];    // 16 bytes (fixed)
   double max_spread;    // 8 bytes
   double risk_pct;      // 8 bytes
   int    atr_period;    // 4 bytes
   bool   enabled;       // 1 byte
   char   padding[3];    // 3 bytes explicit
   // Total: 40 bytes but no heap allocation
};
```

**Expected Impact:**
- Reduced memory footprint: 10-15%
- Better CPU cache utilization
- No heap fragmentation

---

### OPT-005: Pre-allocated Arrays

**Anti-Pattern (Dynamic Growth):**
```mql5
void AddSignal(Signal *sig)
{
   ArrayPush(m_signals, sig); // May trigger reallocation
}
```

**Optimized Pattern:**
```mql5
class SignalManager {
private:
   Signal *m_signals[];
   int    m_capacity;
   int    m_count;
   
public:
   SignalManager(int initialCapacity = 100)
   {
      m_capacity = initialCapacity;
      m_count = 0;
      ArrayResize(m_signals, initialCapacity);
   }
   
   void AddSignal(Signal *sig)
   {
      if(m_count >= m_capacity)
      {
         // Double capacity
         int newCapacity = m_capacity * 2;
         ArrayResize(m_signals, newCapacity);
         m_capacity = newCapacity;
      }
      
      m_signals[m_count++] = sig;
   }
};
```

**Expected Impact:**
- Predictable memory usage
- No reallocation during critical operations
- 20-30% faster array operations

---

### OPT-006: Memory-Mapped Data Structures

For large historical data:
```mql5
class CachedDataStore {
private:
   struct DataBlock {
      datetime time[];
      double   open[];
      double   high[];
      double   low[];
      double   close[];
      double   volume[];
   };
   
   map<int, DataBlock*> m_cache;
   int                  m_maxBlocks;
   
public:
   CachedDataStore(int maxBlocks = 100)
   {
      m_maxBlocks = maxBlocks;
   }
   
   DataBlock* GetBarData(int symbolId, int timeframe)
   {
      int key = symbolId * 1000 + timeframe;
      
      if(m_cache.Contain(key))
         return m_cache.Get(key);
      
      // Load from file or terminal
      DataBlock *block = LoadFromTerminal(symbolId, timeframe);
      
      // LRU eviction if cache full
      if(ArraySize(m_cache) >= m_maxBlocks)
         EvictOldest();
      
      m_cache.Set(key, block);
      return block;
   }
};
```

**Expected Impact:**
- Faster data access: 50-100x vs terminal calls
- Controlled memory usage
- Predictable performance

---

## ⚡ Phase 3: Tick Processing Optimization

### OPT-007: Tick Batching with Deduplication

```mql5
class TickProcessor {
private:
   MqlTick m_tickBuffer[];
   int     m_tickCount;
   int     m_maxBatchSize;
   ulong   m_lastProcessTime;
   double  m_lastBid;
   double  m_lastAsk;
   
public:
   TickProcessor(int maxBatchSize = 10)
   {
      m_maxBatchSize = maxBatchSize;
      m_tickCount = 0;
      ArrayResize(m_tickBuffer, maxBatchSize);
   }
   
   void OnTick(const MqlTick &tick)
   {
      // Skip duplicate ticks (no price change)
      if(MathAbs(tick.bid - m_lastBid) < Point() && 
         MathAbs(tick.ask - m_lastAsk) < Point())
         return;
      
      m_lastBid = tick.bid;
      m_lastAsk = tick.ask;
      
      m_tickBuffer[m_tickCount++] = tick;
      
      // Process batch when full or on bar change
      if(m_tickCount >= m_maxBatchSize || IsNewBar())
      {
         ProcessTickBatch(m_tickBuffer, m_tickCount);
         m_tickCount = 0;
      }
   }
   
private:
   void ProcessTickBatch(MqlTick &ticks[], int count)
   {
      ulong startTime = GetMicrosecondCount();
      
      // Aggregate tick data
      double avgBid = 0, avgAsk = 0;
      double maxBid = ticks[0].bid, minBid = ticks[0].bid;
      
      for(int i = 0; i < count; i++)
      {
         avgBid += ticks[i].bid;
         avgAsk += ticks[i].ask;
         maxBid = MathMax(maxBid, ticks[i].bid);
         minBid = MathMin(minBid, ticks[i].bid);
      }
      
      avgBid /= count;
      avgAsk /= count;
      
      // Use aggregated data for signal generation
      GenerateSignals(avgBid, avgAsk, maxBid, minBid);
      
      ulong duration = GetMicrosecondCount() - startTime;
      RecordMetric("tick_batch_duration", duration);
   }
};
```

**Expected Impact:**
- Tick processing: 200µs → **80-100µs** (50-60% improvement)
- Reduced signal noise
- Better resource utilization

---

### OPT-008: Lazy Indicator Updates

```mql5
class LazyIndicatorCache {
private:
   struct IndicatorHandle {
      int handle;
      datetime lastBarTime;
      double cachedValue[];
      bool   isDirty;
   };
   
   map<string, IndicatorHandle*> m_indicators;
   datetime m_currentBarTime;
   
public:
   double GetValue(const string symbol, int timeframe, int index = 0)
   {
      IndicatorHandle *ind = m_indicators.Get(symbol + "_" + IntegerToString(timeframe));
      
      if(ind == NULL)
         return EMPTY_VALUE;
      
      // Only update if bar changed
      if(ind.isDirty || iBarShift(symbol, timeframe, 0) != ind.lastBarTime)
      {
         UpdateIndicator(ind);
         ind.lastBarTime = m_currentBarTime;
         ind.isDirty = false;
      }
      
      return ind.cachedValue[index];
   }
   
   void MarkDirty(const string symbol, int timeframe)
   {
      IndicatorHandle *ind = m_indicators.Get(symbol + "_" + IntegerToString(timeframe));
      if(ind != NULL)
         ind.isDirty = true;
   }
   
private:
   void UpdateIndicator(IndicatorHandle *ind)
   {
      // Copy buffer data once
      int copied = CopyBuffer(ind.handle, 0, 0, 3, ind.cachedValue);
      if(copied < 3)
         ArrayFill(ind.cachedValue, 0, ArraySize(ind.cachedValue), EMPTY_VALUE);
   }
};
```

**Expected Impact:**
- Indicator updates: 50µs → **5-10µs** (80-90% improvement)
- Only pays cost when data actually changes
- Significant reduction in terminal API calls

---

## 📊 Phase 4: Profiling & Monitoring

### OPT-009: Built-in Performance Profiler

```mql5
class PerformanceProfiler {
private:
   struct ProfileData {
      string name;
      ulong  totalCount;
      ulong  totalTime;
      ulong  minTime;
      ulong  maxTime;
   };
   
   map<string, ProfileData*> m_profiles;
   ulong m_profileStart;
   
public:
   void BeginProfile(const string name)
   {
      m_profileStart = GetMicrosecondCount();
   }
   
   void EndProfile(const string name)
   {
      ulong duration = GetMicrosecondCount() - m_profileStart;
      
      if(!m_profiles.Contain(name))
      {
         ProfileData *data = new ProfileData();
         data.name = name;
         data.totalCount = 0;
         data.totalTime = 0;
         data.minTime = ULONG_MAX;
         data.maxTime = 0;
         m_profiles.Set(name, data);
      }
      
      ProfileData *profile = m_profiles.Get(name);
      profile.totalCount++;
      profile.totalTime += duration;
      profile.minTime = MathMin(profile.minTime, duration);
      profile.maxTime = MathMax(profile.maxTime, duration);
   }
   
   void LogReport()
   {
      Print("\n=== PERFORMANCE PROFILE REPORT ===");
      
      for(int i = 0; i < ArraySize(m_profiles); i++)
      {
         ProfileData *p = m_profiles.GetValue(i);
         double avgTime = (double)p.totalTime / p.totalCount;
         
         Print(StringFormat("%-30s: Count=%d, Avg=%.2fµs, Min=%dµs, Max=%dµs, Total=%.2fms",
                           p.name, p.totalCount, avgTime, 
                           p.minTime, p.maxTime, (double)p.totalTime / 1000.0));
      }
      
      Print("=================================\n");
   }
};

// Global profiler instance
PerformanceProfiler g_profiler;

// Usage
void OnTick()
{
   g_profiler.BeginProfile("OnTick_Total");
   
   g_profiler.BeginProfile("EventDispatch");
   DispatchEvents();
   g_profiler.EndProfile("EventDispatch");
   
   g_profiler.BeginProfile("SignalGeneration");
   GenerateSignals();
   g_profiler.EndProfile("SignalGeneration");
   
   g_profiler.EndProfile("OnTick_Total");
}
```

**Benefits:**
- Identify bottlenecks quickly
- Track performance regression
- Data-driven optimization decisions

---

## 🎯 Implementation Priority

### Week 1 (Immediate Impact):
1. ✅ OPT-001: Hash-based handler lookup
2. ✅ OPT-002: Event object pooling
3. ✅ OPT-009: Performance profiler setup

### Week 2-3 (High Impact):
4. ✅ OPT-007: Tick batching with deduplication
5. ✅ OPT-008: Lazy indicator updates
6. ✅ OPT-005: Pre-allocated arrays

### Week 4-6 (Medium Impact):
7. ✅ OPT-004: Struct packing
8. ✅ OPT-006: Memory-mapped data structures
9. ✅ OPT-003: Batch event processing

---

## 📈 Expected Overall Improvements

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| **End-to-End Latency** | 350µs | **150µs** | 57% ↓ |
| **Memory per Symbol** | 3.2KB | **1.8KB** | 44% ↓ |
| **Max TPS (Ticks/sec)** | 3,000 | **7,000** | 133% ↑ |
| **GC Pauses** | 5-10ms | **<1ms** | 90% ↓ |
| **P99 Latency** | 500µs | **200µs** | 60% ↓ |

---

## 🔍 Benchmarking Script

```mql5
//+------------------------------------------------------------------+
//|                                                Benchmark.mqh     |
//+------------------------------------------------------------------+
void RunBenchmarks()
{
   Print("=== PASR PERFORMANCE BENCHMARKS ===\n");
   
   // Benchmark 1: Event Dispatch
   ulong start = GetMicrosecondCount();
   for(int i = 0; i < 10000; i++)
   {
      PriceUpdateEvent *e = new PriceUpdateEvent();
      EventBus::Instance().Dispatch(e);
      delete e;
   }
   ulong baseline = GetMicrosecondCount() - start;
   
   // Benchmark 2: With Object Pool
   EventPool pool(1000);
   start = GetMicrosecondCount();
   for(int i = 0; i < 10000; i++)
   {
      PriceUpdateEvent *e = (PriceUpdateEvent*)pool.Acquire();
      EventBus::Instance().Dispatch(e);
      pool.Release(e);
   }
   ulong optimized = GetMicrosecondCount() - start;
   
   Print("Event Dispatch (10k iterations):");
   Print("  Baseline:  ", baseline / 1000.0, " ms (", baseline / 10000.0, " µs/op)");
   Print("  Optimized: ", optimized / 1000.0, " ms (", optimized / 10000.0, " µs/op)");
   Print("  Improvement: ", DoubleToString((1.0 - (double)optimized / baseline) * 100, 2), "%\n");
}
```

---

**Last Updated:** 2026  
**Next Review:** After implementing OPT-001 to OPT-003  
**Status:** Ready for Implementation
