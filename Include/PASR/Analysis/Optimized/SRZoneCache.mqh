//+------------------------------------------------------------------+
//| Analysis/Optimized/SRZoneCache.mqh                               |
//| Advanced Cache System with Lazy Evaluation                       |
//|                                                                  |
//| OPTIMIZATION FEATURES:                                           |
//|  - Bar-based cache invalidation (not time-based)                 |
//|  - Lazy evaluation for expensive calculations                    |
//|  - Multi-level caching (L1: Price, L2: Zones, L3: Strength)      |
//|  - Memory-efficient zone storage                                 |
//|                                                                  |
//| CACHE HIERARCHY:                                                 |
//|  L1: Current bar hash - detect new bar instantly                 |
//|  L2: Zone array cache - avoid re-scanning                        |
//|  L3: Computed strengths - avoid re-calculation                   |
//+------------------------------------------------------------------+
#property strict
#ifndef __ANALYSIS_OPTIMIZED_SR_ZONE_CACHE_MQH__
#define __ANALYSIS_OPTIMIZED_SR_ZONE_CACHE_MQH__

#include "../Data/SRStruct.mqh"
#include "PerformanceUtils.mqh"

//+------------------------------------------------------------------+
//| CacheEntry — Generic cached data with validity check             |
//+------------------------------------------------------------------+
template<typename T>
struct CacheEntry
{
   T        value;
   datetime barTime;
   int      barIndex;
   bool     isValid;
   ulong    accessCount;
   datetime lastAccess;
   
   void Init()
   {
      value       = T();
      barTime     = 0;
      barIndex    = -1;
      isValid     = false;
      accessCount = 0;
      lastAccess  = 0;
   }
   
   void Invalidate()
   {
      isValid = false;
   }
   
   void Touch()
   {
      accessCount++;
      lastAccess = TimeCurrent();
   }
};

//+------------------------------------------------------------------+
//| SRZoneCacheEntry — Specialized cache for SR zones                |
//+------------------------------------------------------------------+
struct SRZoneCacheEntry : public CacheEntry<SRZone[]>
{
   int    zoneCount;
   double cacheStrength;  // Pre-computed total strength
   bool   strengthValid;  // Flag if strength is cached
   
   void Init()
   {
      CacheEntry<SRZone[]>::Init();
      zoneCount      = 0;
      cacheStrength  = 0.0;
      strengthValid  = false;
   }
   
   void SetZones(const SRZone zones[], int count)
   {
      ArrayResize(value, count);
      ArrayCopy(value, zones, 0, 0, count);
      zoneCount = count;
      isValid   = true;
      strengthValid = false;  // Invalidate strength cache
   }
   
   double GetTotalStrength()
   {
      if(!strengthValid && isValid)
      {
         cacheStrength = 0.0;
         for(int i = 0; i < zoneCount; i++)
            cacheStrength += value[i].strength;
         strengthValid = true;
      }
      return cacheStrength;
   }
};

//+------------------------------------------------------------------+
//| BarCacheKey — Unique identifier for bar-based caching            |
//+------------------------------------------------------------------+
struct BarCacheKey
{
   datetime barTime;
   int      barIndex;
   string   symbol;
   ENUM_TIMEFRAMES timeframe;
   
   void Set(datetime time, int index, const string sym, ENUM_TIMEFRAMES tf)
   {
      barTime     = time;
      barIndex    = index;
      symbol      = sym;
      timeframe   = tf;
   }
   
   ulong GetHashCode() const
   {
      // Simple hash combining all fields
      return (ulong)barTime ^ (ulong)barIndex * 31 ^ 
             StringLen(symbol) * 37 ^ (ulong)timeframe * 41;
   }
   
   bool operator==(const BarCacheKey &other) const
   {
      return (barTime == other.barTime && 
              barIndex == other.barIndex &&
              symbol == other.symbol &&
              timeframe == other.timeframe);
   }
};

//+------------------------------------------------------------------+
//| CSRZoneCache — Main cache manager class                          |
//+------------------------------------------------------------------+
class CSRZoneCache
{
private:
   SRZoneCacheEntry m_zoneCache;           // L2 cache: zones
   CacheEntry<double> m_atrCache;          // L1 cache: ATR
   CacheEntry<double> m_maCache;           // L1 cache: MA
   BarCacheKey      m_currentKey;          // Current bar key
   BarCacheKey      m_lastValidKey;        // Last valid bar key
   ulong            m_cacheHits;
   ulong            m_cacheMisses;
   ulong            m_cacheInvalidations;
   bool             m_initialized;
   
   // Configuration
   int              m_maxCacheAge;         // Max bars to keep cache
   bool             m_lazyEvaluation;      // Enable lazy eval
   
public:
   CSRZoneCache() : m_cacheHits(0), m_cacheMisses(0), 
                    m_cacheInvalidations(0), m_initialized(false),
                    m_maxCacheAge(10), m_lazyEvaluation(true)
   {
      m_zoneCache.Init();
      m_atrCache.Init();
      m_maCache.Init();
      m_currentKey.Set(0, -1, "", PERIOD_CURRENT);
      m_lastValidKey.Set(0, -1, "", PERIOD_CURRENT);
   }
   
   ~CSRZoneCache() { Cleanup(); }
   
   void Cleanup()
   {
      m_zoneCache.Init();
      m_atrCache.Init();
      m_maCache.Init();
      m_initialized = false;
   }
   
   // Initialize cache system
   bool Initialize(const string symbol, ENUM_TIMEFRAMES tf)
   {
      datetime currentBarTime = iTime(symbol, tf, 0);
      int currentBarIndex = 0;
      
      m_currentKey.Set(currentBarTime, currentBarIndex, symbol, tf);
      m_lastValidKey = m_currentKey;
      
      m_initialized = true;
      return true;
   }
   
   // Check if cache is valid for current bar
   bool IsValid(const string symbol, ENUM_TIMEFRAMES tf)
   {
      if(!m_initialized)
         return false;
      
      datetime currentBarTime = iTime(symbol, tf, 0);
      
      // Cache valid if same bar time
      if(currentBarTime == m_lastValidKey.barTime)
      {
         m_cacheHits++;
         return true;
      }
      
      // New bar detected - invalidate cache
      m_cacheInvalidations++;
      m_cacheMisses++;
      
      return false;
   }
   
   // Invalidate all caches
   void Invalidate()
   {
      m_zoneCache.Invalidate();
      m_atrCache.Invalidate();
      m_maCache.Invalidate();
      m_cacheInvalidations++;
   }
   
   // Update cache key on new bar
   void UpdateOnNewBar(const string symbol, ENUM_TIMEFRAMES tf)
   {
      datetime currentBarTime = iTime(symbol, tf, 0);
      m_currentKey.Set(currentBarTime, 0, symbol, tf);
      
      if(currentBarTime != m_lastValidKey.barTime)
      {
         // New bar - shift last valid key
         m_lastValidKey = m_currentKey;
         Invalidate();
      }
   }
   
   // Zone cache operations
   bool GetCachedZones(SRZone zones[], int &count)
   {
      if(!m_zoneCache.isValid)
      {
         m_cacheMisses++;
         return false;
      }
      
      m_zoneCache.Touch();
      count = m_zoneCache.zoneCount;
      
      if(ArraySize(zones) < count)
         ArrayResize(zones, count);
      
      ArrayCopy(zones, m_zoneCache.value, 0, 0, count);
      m_cacheHits++;
      
      return true;
   }
   
   void CacheZones(const SRZone zones[], int count)
   {
      m_zoneCache.SetZones(zones, count);
      m_zoneCache.barTime = m_currentKey.barTime;
      m_zoneCache.barIndex = m_currentKey.barIndex;
   }
   
   // ATR cache operations with lazy evaluation
   double GetOrFetchATR(const string symbol, ENUM_TIMEFRAMES tf, int period)
   {
      // Check if cache is valid
      if(m_atrCache.isValid)
      {
         m_cacheHits++;
         return m_atrCache.value;
      }
      
      m_cacheMisses++;
      
      // Lazy evaluation: fetch only when needed
      double atr = iATR(symbol, tf, period, 1);
      
      if(atr > 0)
      {
         m_atrCache.value = atr;
         m_atrCache.barTime = m_currentKey.barTime;
         m_atrCache.barIndex = m_currentKey.barIndex;
         m_atrCache.isValid = true;
      }
      
      return atr;
   }
   
   // MA cache operations with lazy evaluation
   double GetOrFetchMA(const string symbol, ENUM_TIMEFRAMES tf, 
                      int period, int maMethod, int priceType)
   {
      if(m_maCache.isValid)
      {
         m_cacheHits++;
         return m_maCache.value;
      }
      
      m_cacheMisses++;
      
      // Lazy evaluation
      double ma = iMA(symbol, tf, period, 0, maMethod, priceType, 1);
      
      if(ma > 0)
      {
         m_maCache.value = ma;
         m_maCache.barTime = m_currentKey.barTime;
         m_maCache.barIndex = m_currentKey.barIndex;
         m_maCache.isValid = true;
      }
      
      return ma;
   }
   
   // Statistics
   ulong GetCacheHits() const { return m_cacheHits; }
   ulong GetCacheMisses() const { return m_cacheMisses; }
   ulong GetCacheInvalidations() const { return m_cacheInvalidations; }
   
   double GetCacheHitRate() const
   {
      ulong total = m_cacheHits + m_cacheMisses;
      return (total > 0) ? (double)m_cacheHits / total * 100.0 : 0.0;
   }
   
   string GetStatsString() const
   {
      return StringFormat("Cache[Hits=%d|Misses=%d|Invalidations=%d|HitRate=%.1f%%]",
                         m_cacheHits, m_cacheMisses, m_cacheInvalidations,
                         GetCacheHitRate());
   }
   
   // Configuration
   void SetLazyEvaluation(bool enabled) { m_lazyEvaluation = enabled; }
   bool IsLazyEvaluation() const { return m_lazyEvaluation; }
};

#endif // __ANALYSIS_OPTIMIZED_SR_ZONE_CACHE_MQH__
