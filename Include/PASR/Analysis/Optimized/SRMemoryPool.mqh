//+------------------------------------------------------------------+
//| Analysis/Optimized/SRMemoryPool.mqh                              |
//| Memory Pool Allocator for SR Zones                               |
//|                                                                  |
//| OPTIMIZATION FEATURES:                                           |
//|  - Pre-allocated memory blocks (no dynamic allocation)           |
//|  - Object reuse via free list                                    |
//|  - Reduced memory fragmentation                                  |
//|  - O(1) allocation/deallocation                                  |
//|                                                                  |
//| MEMORY LAYOUT:                                                   |
//|  - Fixed-size pool of SRZoneExtended objects                     |
//|  - Free list for quick recycling                                 |
//|  - Bitmap for tracking used slots                                |
//+------------------------------------------------------------------+
#property strict
#ifndef __ANALYSIS_OPTIMIZED_SR_MEMORY_POOL_MQH__
#define __ANALYSIS_OPTIMIZED_SR_MEMORY_POOL_MQH__

#include "../Data/SRStruct.mqh"
#include "SRZoneCache.mqh"

//+------------------------------------------------------------------+
//| SRZoneExtended — Enhanced zone with performance fields           |
//+------------------------------------------------------------------+
struct SRZoneExtended : public SRZone
{
   double confidence;        // Zone confidence score (0-100)
   int    formation_bars;    // Bars since zone formation
   double last_reaction;     // Price reaction magnitude at last touch
   double buffer_multiplier; // Dynamic buffer based on touch count
   int    htf_alignment;     // HTF alignment status (-1, 0, 1)
   
   // Advanced fields
   double age_decay_factor;  // Current age decay multiplier
   bool   is_merged_zone;    // Flag if zone was merged
   int    merge_count;       // Number of zones merged
   double volatility_adj;    // Volatility adjustment factor
   
   // Session and volume fields
   int    session_type;      // Trading session (0-4)
   bool   is_psych_level;    // Psychological level flag
   double volume_strength;   // Volume-based strength multiplier
   datetime last_news_time;  // Time of last high-impact news
   bool   news_cooldown;     // News cooldown flag
   
   // Memory pool management
   int    pool_index;        // Index in memory pool
   bool   is_allocated;      // Allocation flag
   
   void InitExtended()
   {
      Init();
      confidence        = 0.0;
      formation_bars    = 0;
      last_reaction     = 0.0;
      buffer_multiplier = 1.0;
      htf_alignment     = 0;  // HTF_NEUTRAL
      age_decay_factor  = 1.0;
      is_merged_zone    = false;
      merge_count       = 1;
      volatility_adj    = 1.0;
      session_type      = 4;  // SESSION_UNKNOWN
      is_psych_level    = false;
      volume_strength   = 1.0;
      last_news_time    = 0;
      news_cooldown     = false;
      pool_index        = -1;
      is_allocated      = false;
   }
   
   string ToString() const
   {
      return StringFormat("SRZoneExt[%.5f|%.5f|%s|Str=%.1f|Conf=%.1f|Touches=%d|HTF=%d|AgeDecay=%.2f|Merged=%d]",
                         price, low, high, 
                         isSupport ? "SUP" : "RES", 
                         strength, confidence, touchCount, htf_alignment,
                         age_decay_factor, merge_count);
   }
   
   // Reset for reuse in memory pool
   void Reset()
   {
      InitExtended();
   }
};

//+------------------------------------------------------------------+
//| SRMemoryPool — Fixed-size allocator for SRZoneExtended           |
//+------------------------------------------------------------------+
class CSRMemoryPool
{
private:
   SRZoneExtended m_pool[];       // Pre-allocated pool
   int            m_freeList[];   // Free slot indexes
   int            m_freeHead;     // Head of free list
   int            m_poolSize;     // Total pool size
   int            m_allocatedCount;// Currently allocated
   bool           m_initialized;  // Initialization flag
   
   // Statistics
   ulong          m_allocations;
   ulong          m_deallocations;
   ulong          m_peakUsage;
   
public:
   CSRMemoryPool() : m_freeHead(-1), m_poolSize(0), 
                     m_allocatedCount(0), m_initialized(false),
                     m_allocations(0), m_deallocations(0), m_peakUsage(0)
   {
   }
   
   ~CSRMemoryPool() { Cleanup(); }
   
   // Initialize memory pool with fixed size
   bool Initialize(int poolCapacity)
   {
      if(m_initialized && m_poolSize >= poolCapacity)
         return true;  // Already initialized with sufficient size
      
      Cleanup();
      
      m_poolSize = poolCapacity;
      ArrayResize(m_pool, poolCapacity);
      ArrayResize(m_freeList, poolCapacity);
      
      // Initialize all slots and build free list
      for(int i = 0; i < poolCapacity; i++)
      {
         m_pool[i].InitExtended();
         m_pool[i].pool_index = i;
         
         // Link to free list (reverse order)
         m_freeList[i] = m_freeHead;
         m_freeHead = i;
      }
      
      m_initialized = true;
      return true;
   }
   
   void Cleanup()
   {
      ArrayFree(m_pool);
      ArrayFree(m_freeList);
      m_poolSize = 0;
      m_freeHead = -1;
      m_allocatedCount = 0;
      m_initialized = false;
   }
   
   // Allocate a zone from pool - O(1) operation
   SRZoneExtended* Allocate()
   {
      if(!m_initialized || m_freeHead == -1)
         return NULL;  // Pool exhausted
      
      // Get slot from free list head
      int slotIndex = m_freeHead;
      m_freeHead = m_freeList[slotIndex];
      
      // Mark as allocated
      SRZoneExtended* zone = &m_pool[slotIndex];
      zone->Reset();
      zone->is_allocated = true;
      
      m_allocatedCount++;
      m_allocations++;
      
      if(m_allocatedCount > m_peakUsage)
         m_peakUsage = m_allocatedCount;
      
      return zone;
   }
   
   // Deallocate a zone back to pool - O(1) operation
   void Deallocate(SRZoneExtended* zone)
   {
      if(zone == NULL || !m_initialized)
         return;
      
      int slotIndex = zone->pool_index;
      
      if(slotIndex < 0 || slotIndex >= m_poolSize)
         return;  // Invalid slot
      
      // Reset zone
      zone->Reset();
      zone->is_allocated = false;
      
      // Return to free list
      m_freeList[slotIndex] = m_freeHead;
      m_freeHead = slotIndex;
      
      m_allocatedCount--;
      m_deallocations++;
   }
   
   // Get zone by index (for iteration)
   SRZoneExtended* GetZone(int index)
   {
      if(!m_initialized || index < 0 || index >= m_poolSize)
         return NULL;
      
      return &m_pool[index];
   }
   
   const SRZoneExtended* GetZone(int index) const
   {
      if(!m_initialized || index < 0 || index >= m_poolSize)
         return NULL;
      
      return &m_pool[index];
   }
   
   // Check if zone at index is allocated
   bool IsAllocated(int index) const
   {
      if(!m_initialized || index < 0 || index >= m_poolSize)
         return false;
      
      return m_pool[index].is_allocated;
   }
   
   // Get all allocated zones
   int GetAllocatedZones(SRZoneExtended &zones[]) const
   {
      if(!m_initialized)
         return 0;
      
      int count = 0;
      for(int i = 0; i < m_poolSize; i++)
      {
         if(m_pool[i].is_allocated)
         {
            if(count >= ArraySize(zones))
               ArrayResize(zones, count + 10);  // Auto-expand
            
            zones[count] = m_pool[i];
            count++;
         }
      }
      
      return count;
   }
   
   // Statistics
   int GetPoolSize() const { return m_poolSize; }
   int GetAllocatedCount() const { return m_allocatedCount; }
   int GetFreeCount() const { return m_poolSize - m_allocatedCount; }
   ulong GetTotalAllocations() const { return m_allocations; }
   ulong GetTotalDeallocations() const { return m_deallocations; }
   ulong GetPeakUsage() const { return m_peakUsage; }
   
   double GetUtilizationPercent() const
   {
      return (m_poolSize > 0) ? (double)m_allocatedCount / m_poolSize * 100.0 : 0.0;
   }
   
   string GetStatsString() const
   {
      return StringFormat("MemPool[Size=%d|Alloc=%d|Free=%d|Peak=%d|Util=%.1f%%]",
                         m_poolSize, m_allocatedCount, GetFreeCount(),
                         m_peakUsage, GetUtilizationPercent());
   }
   
   bool IsInitialized() const { return m_initialized; }
};

//+------------------------------------------------------------------+
//| SRZoneManager_Pooled — High-performance zone manager             |
//+------------------------------------------------------------------+
class CSRZoneManager_Pooled
{
private:
   CSRMemoryPool    m_memoryPool;
   SRZoneExtended   m_activeZones[];
   int              m_activeCount;
   int              m_poolCapacity;
   
public:
   CSRZoneManager_Pooled() : m_activeCount(0), m_poolCapacity(100)
   {
   }
   
   ~CSRZoneManager_Pooled() { Cleanup(); }
   
   bool Initialize(int capacity = 100)
   {
      m_poolCapacity = capacity;
      return m_memoryPool.Initialize(capacity);
   }
   
   void Cleanup()
   {
      m_memoryPool.Cleanup();
      ArrayFree(m_activeZones);
      m_activeCount = 0;
   }
   
   // Allocate new zone from pool
   SRZoneExtended* CreateZone()
   {
      return m_memoryPool.Allocate();
   }
   
   // Release zone back to pool
   void DestroyZone(SRZoneExtended* zone)
   {
      m_memoryPool.Deallocate(zone);
   }
   
   // Add zone to active list
   bool AddToActive(SRZoneExtended* zone)
   {
      if(zone == NULL || !zone->is_allocated)
         return false;
      
      if(m_activeCount >= ArraySize(m_activeZones))
         ArrayResize(m_activeZones, m_activeCount + 10);
      
      m_activeZones[m_activeCount] = *zone;
      m_activeCount++;
      
      return true;
   }
   
   // Get active zones
   int GetActiveZones(SRZoneExtended &zones[]) const
   {
      if(m_activeCount == 0)
         return 0;
      
      if(ArraySize(zones) < m_activeCount)
         ArrayResize(zones, m_activeCount);
      
      ArrayCopy(zones, m_activeZones, 0, 0, m_activeCount);
      return m_activeCount;
   }
   
   // Find zone by price level
   SRZoneExtended* FindZoneByPrice(double price, double tolerance) const
   {
      for(int i = 0; i < m_activeCount; i++)
      {
         if(MathAbs(m_activeZones[i].price - price) <= tolerance)
            return &m_activeZones[i];
      }
      return NULL;
   }
   
   // Get statistics
   string GetStatsString() const
   {
      return StringFormat("ZoneMgr[Active=%d|%s]",
                         m_activeCount, m_memoryPool.GetStatsString());
   }
   
   int GetActiveCount() const { return m_activeCount; }
   const CSRMemoryPool& GetMemoryPool() const { return m_memoryPool; }
};

#endif // __ANALYSIS_OPTIMIZED_SR_MEMORY_POOL_MQH__
