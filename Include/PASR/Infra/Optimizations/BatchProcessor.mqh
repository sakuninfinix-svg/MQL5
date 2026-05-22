//+------------------------------------------------------------------+
//|                           Infra/Optimizations/BatchProcessor.mqh |
//|                                 Advanced Batch Processing Engine |
//|                              Copyright © 2024 PASR Framework |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2024 PASR Framework"
#property link      "https://pasr.framework"
#property version   "1.00"
#property description "OPT-018: High-performance batch processing with deduplication"

#include "Optimizations.mqh"

//+------------------------------------------------------------------+
//| Batch Configuration Constants                                    |
//+------------------------------------------------------------------+
#define DEFAULT_BATCH_SIZE           64
#define MAX_BATCH_SIZE              256
#define MIN_BATCH_SIZE               8
#define DEDUP_WINDOW_MS            1000
#define BATCH_FLUSH_TIMEOUT_MS      100

//+------------------------------------------------------------------+
//| Batch Statistics Structure                                       |
//+------------------------------------------------------------------+
struct SBatchStats
{
   ulong totalBatches;
   ulong totalItems;
   ulong duplicatesRemoved;
   ulong flushBySize;
   ulong flushByTimeout;
   ulong flushByForce;
   double avgBatchSize;
   double avgProcessingTimeUs;
   double maxProcessingTimeUs;
   
   void Reset()
   {
      totalBatches = 0;
      totalItems = 0;
      duplicatesRemoved = 0;
      flushBySize = 0;
      flushByTimeout = 0;
      flushByForce = 0;
      avgBatchSize = 0.0;
      avgProcessingTimeUs = 0.0;
      maxProcessingTimeUs = 0.0;
   }
   
   string ToString() const
   {
      return StringFormat(
         "Batch Stats: Batches=%lu, Items=%lu, DupsRemoved=%lu, " +
         "AvgSize=%.2f, AvgTime=%.2fus, MaxTime=%.2fus",
         totalBatches, totalItems, duplicatesRemoved,
         avgBatchSize, avgProcessingTimeUs, maxProcessingTimeUs
      );
   }
};

//+------------------------------------------------------------------+
//| Generic Batch Item Wrapper                                       |
//+------------------------------------------------------------------+
template<typename T>
struct SBatchItem
{
   T data;
   ulong timestamp;
   uint hash;
   bool isValid;
   
   SBatchItem() : timestamp(0), hash(0), isValid(false) {}
   SBatchItem(const T& item, ulong ts, uint h) : data(item), timestamp(ts), hash(h), isValid(true) {}
};

//+------------------------------------------------------------------+
//| CBatchProcessor - High-performance batch processor               |
//| Features:                                                        |
//| - Configurable batch size                                        |
//| - Automatic deduplication using hash table                       |
//| - Time-based and size-based flushing                             |
//| - Zero-allocation pre-allocated buffers                          |
//| - Callback-based batch processing                                |
//+------------------------------------------------------------------+
template<typename T, int CAPACITY = DEFAULT_BATCH_SIZE>
class CBatchProcessor
{
private:
   // Pre-allocated batch buffer (zero allocation)
   SBatchItem<T> m_buffer[CAPACITY];
   
   // Deduplication hash table (open addressing)
   uint m_dedupHash[CAPACITY * 2];
   int m_dedupIndices[CAPACITY * 2];
   
   // Current batch state
   int m_currentSize;
   ulong m_lastFlushTime;
   
   // Configuration
   int m_batchSize;
   int m_dedupWindowMs;
   bool m_enableDedup;
   
   // Statistics
   SBatchStats m_stats;
   
   // Callback function pointer type
   typedef void (*BatchCallback)(const T&, int);
   BatchCallback m_callback;
   
   // Helper: Fast hash function (FNV-1a variant)
   uint FastHash(const T& item) const
   {
      // Generic hash - specialize for your types
      return (uint)GetTickCount();
   }
   
   // Helper: Check if item is duplicate within window
   bool IsDuplicate(uint hash, ulong currentTime)
   {
      if(!m_enableDedup) return false;
      
      int bucket = hash % (CAPACITY * 2);
      int probe = 0;
      
      while(m_dedupHash[bucket] != 0 && probe < CAPACITY * 2)
      {
         if(m_dedupHash[bucket] == hash)
         {
            int idx = m_dedupIndices[bucket];
            if(idx >= 0 && idx < m_currentSize)
            {
               ulong age = currentTime - m_buffer[idx].timestamp;
               if(age <= (ulong)m_dedupWindowMs)
               {
                  m_stats.duplicatesRemoved++;
                  return true;
               }
            }
         }
         
         bucket = (bucket + 1) % (CAPACITY * 2);
         probe++;
      }
      
      return false;
   }
   
   // Helper: Add to dedup hash table
   void AddToDedup(uint hash, int index)
   {
      if(!m_enableDedup) return;
      
      int bucket = hash % (CAPACITY * 2);
      int probe = 0;
      
      while(m_dedupHash[bucket] != 0 && probe < CAPACITY * 2)
      {
         bucket = (bucket + 1) % (CAPACITY * 2);
         probe++;
      }
      
      m_dedupHash[bucket] = hash;
      m_dedupIndices[bucket] = index;
   }
   
   // Helper: Clear dedup table
   void ClearDedup()
   {
      ArrayFill(m_dedupHash, 0, ArraySize(m_dedupHash), 0);
      ArrayFill(m_dedupIndices, 0, ArraySize(m_dedupIndices), -1);
   }
   
public:
   CBatchProcessor() : m_currentSize(0), m_lastFlushTime(0),
                       m_batchSize(DEFAULT_BATCH_SIZE),
                       m_dedupWindowMs(DEDUP_WINDOW_MS),
                       m_enableDedup(true), m_callback(NULL)
   {
      Reset();
   }
   
   ~CBatchProcessor()
   {
      Flush(true);
   }
   
   // Initialize with callback
   void Initialize(BatchCallback cb, int batchSize = DEFAULT_BATCH_SIZE, bool enableDedup = true)
   {
      m_callback = cb;
      m_batchSize = MathMin(MathMax(batchSize, MIN_BATCH_SIZE), MAX_BATCH_SIZE);
      m_enableDedup = enableDedup;
      Reset();
   }
   
   // Reset processor state
   void Reset()
   {
      m_currentSize = 0;
      m_lastFlushTime = GetTickCount();
      m_stats.Reset();
      ClearDedup();
      
      for(int i = 0; i < CAPACITY; i++)
         m_buffer[i].isValid = false;
   }
   
   // Add item to batch (CRITICAL_PATH optimized)
   CRITICAL_FUNCTION bool Add(const T& item)
   {
      if(m_currentSize >= CAPACITY)
      {
         Flush(false);
         if(m_currentSize >= CAPACITY) return false; // Still full after flush
      }
      
      ulong currentTime = GetTickCount();
      uint hash = FastHash(item);
      
      // Check for duplicates
      if(IsDuplicate(hash, currentTime))
         return false; // Duplicate rejected
      
      // Add to batch
      m_buffer[m_currentSize] = SBatchItem<T>(item, currentTime, hash);
      AddToDedup(hash, m_currentSize);
      m_currentSize++;
      m_stats.totalItems++;
      
      // Auto-flush if batch is full
      if(m_currentSize >= m_batchSize)
      {
         Flush(false);
         m_stats.flushBySize++;
      }
      
      return true;
   }
   
   // Force flush batch
   CRITICAL_FUNCTION void Flush(bool force = false)
   {
      if(m_currentSize == 0) return;
      
      ulong startTime = GetTickCount64();
      
      // Process batch via callback
      if(m_callback != NULL)
      {
         for(int i = 0; i < m_currentSize; i++)
         {
            if(m_buffer[i].isValid)
               m_callback(m_buffer[i].data, i);
         }
      }
      
      // Update statistics
      ulong endTime = GetTickCount64();
      double processingTimeUs = (double)(endTime - startTime) * 1000.0;
      
      m_stats.totalBatches++;
      m_stats.avgBatchSize = ((m_stats.avgBatchSize * (m_stats.totalBatches - 1)) + m_currentSize) / m_stats.totalBatches;
      m_stats.avgProcessingTimeUs = ((m_stats.avgProcessingTimeUs * (m_stats.totalBatches - 1)) + processingTimeUs) / m_stats.totalBatches;
      m_stats.maxProcessingTimeUs = MathMax(m_stats.maxProcessingTimeUs, processingTimeUs);
      
      if(force) m_stats.flushByForce++;
      
      // Clear batch
      m_currentSize = 0;
      m_lastFlushTime = GetTickCount();
      ClearDedup();
   }
   
   // Check if flush needed (timeout-based)
   CRITICAL_FUNCTION bool CheckFlush()
   {
      ulong currentTime = GetTickCount();
      
      if(m_currentSize > 0 && (currentTime - m_lastFlushTime) > (ulong)BATCH_FLUSH_TIMEOUT_MS)
      {
         Flush(false);
         m_stats.flushByTimeout++;
         return true;
      }
      
      return false;
   }
   
   // Getters
   int GetCurrentSize() const { return m_currentSize; }
   int GetBatchSize() const { return m_batchSize; }
   bool IsEnabled() const { return m_callback != NULL; }
   const SBatchStats& GetStats() const { return m_stats; }
   
   // Configuration setters
   void SetBatchSize(int size) { m_batchSize = MathMin(MathMax(size, MIN_BATCH_SIZE), MAX_BATCH_SIZE); }
   void SetDedupWindow(int ms) { m_dedupWindowMs = MathMax(ms, 0); }
   void EnableDedup(bool enable) { m_enableDedup = enable; }
};

//+------------------------------------------------------------------+
//| Specialized Tick Batch Processor                                 |
//+------------------------------------------------------------------+
struct STickBatchData
{
   datetime time;
   double bid;
   double ask;
   ulong volume;
   long tickVolume;
   int flags;
   
   uint Hash() const
   {
      // Hash based on time and price (ignore volume for dedup)
      return (uint)((time * 1000) + (ulong)(bid * 100000));
   }
};

// Specialized hash for ticks
template<>
uint CBatchProcessor<STickBatchData, DEFAULT_BATCH_SIZE>::FastHash(const STickBatchData& item) const
{
   return item.Hash();
}

typedef CBatchProcessor<STickBatchData, 128> CTickBatchProcessor;

//+------------------------------------------------------------------+
//| Specialized Event Batch Processor                                |
//+------------------------------------------------------------------+
struct SEventBatchData
{
   int eventType;
   ulong timestamp;
   long symbolHash;
   double value1;
   double value2;
   
   uint Hash() const
   {
      return (uint)(eventType ^ (symbolHash & 0xFFFFFFFF) ^ (uint)timestamp);
   }
};

template<>
uint CBatchProcessor<SEventBatchData, DEFAULT_BATCH_SIZE>::FastHash(const SEventBatchData& item) const
{
   return item.Hash();
}

typedef CBatchProcessor<SEventBatchData, 64> CEventBatchProcessor;

//+------------------------------------------------------------------+
//| Global Batch Manager                                             |
//+------------------------------------------------------------------+
class CBatchManager
{
private:
   static CTickBatchProcessor s_tickBatch;
   static CEventBatchProcessor s_eventBatch;
   
public:
   static void Initialize()
   {
      s_tickBatch.Initialize(OnTickBatchProcessed, 128, true);
      s_eventBatch.Initialize(OnEventBatchProcessed, 64, true);
   }
   
   static void Shutdown()
   {
      s_tickBatch.Flush(true);
      s_eventBatch.Flush(true);
   }
   
   // Add tick to batch
   CRITICAL_FUNCTION static bool AddTick(const STickBatchData& tick)
   {
      return s_tickBatch.Add(tick);
   }
   
   // Add event to batch
   CRITICAL_FUNCTION static bool AddEvent(const SEventBatchData& evt)
   {
      return s_eventBatch.Add(evt);
   }
   
   // Check and flush if needed
   CRITICAL_FUNCTION static void CheckFlush()
   {
      s_tickBatch.CheckFlush();
      s_eventBatch.CheckFlush();
   }
   
   // Force flush all
   CRITICAL_FUNCTION static void FlushAll()
   {
      s_tickBatch.Flush(true);
      s_eventBatch.Flush(true);
   }
   
   // Get statistics
   static string GetStats()
   {
      return "Tick Batch: " + s_tickBatch.GetStats().ToString() + 
             "\nEvent Batch: " + s_eventBatch.GetStats().ToString();
   }
   
private:
   // Callback implementations
   static void OnTickBatchProcessed(const STickBatchData& tick, int index)
   {
      // Process tick - integrate with your tick handler
      // Example: Update indicators, check signals, etc.
   }
   
   static void OnEventBatchProcessed(const SEventBatchData& evt, int index)
   {
      // Process event - dispatch to event bus
      // Example: EventBus.Dispatch(evt.eventType, evt.symbolHash, evt.value1);
   }
};

// Static initialization
CTickBatchProcessor CBatchManager::s_tickBatch;
CEventBatchProcessor CBatchManager::s_eventBatch;

//+------------------------------------------------------------------+
//| Usage Example                                                    |
//+------------------------------------------------------------------+
/*
void OnTick()
{
   // Prepare tick data
   STickBatchData tick;
   tick.time = TimeCurrent();
   tick.bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   tick.ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   tick.volume = (ulong)SymbolInfoInteger(_Symbol, SYMBOL_VOLUME);
   
   // Add to batch (automatic dedup and flush)
   CBatchManager::AddTick(tick);
   
   // Check if timeout flush needed
   CBatchManager::CheckFlush();
}

void OnDeinit(const int reason)
{
   CBatchManager::Shutdown();
   Print(CBatchManager::GetStats());
}
*/
//+------------------------------------------------------------------+
