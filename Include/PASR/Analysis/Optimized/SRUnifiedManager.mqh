//+------------------------------------------------------------------+
//| Analysis/Optimized/SRUnifiedManager.mqh                          |
//| Refactored SR Manager - Modular & Optimized                      |
//|                                                                  |
//| REFACTORING APPROACH:                                            |
//|  - Splits monolithic SRManager.mqh into focused modules          |
//|  - Delegates to high-performance components                      |
//|  - Maintains backward compatibility                              |
//|  - Provides unified interface for legacy code                    |
//|                                                                  |
//| MODULES:                                                         |
//|  - PerformanceUtils: Batch data fetching                         |
//|  - SRZoneCache: Advanced caching                                 |
//|  - SRMemoryPool: Memory optimization                             |
//|  - SRBatchScanner: High-speed scanning                           |
//+------------------------------------------------------------------+
#property strict
#ifndef __ANALYSIS_OPTIMIZED_SR_UNIFIED_MANAGER_MQH__
#define __ANALYSIS_OPTIMIZED_SR_UNIFIED_MANAGER_MQH__

#include "../Data/SRStruct.mqh"
#include "PerformanceUtils.mqh"
#include "SRZoneCache.mqh"
#include "SRMemoryPool.mqh"
#include "SRBatchScanner.mqh"

//+------------------------------------------------------------------+
//| Configuration for unified manager                                |
//+------------------------------------------------------------------+
struct SRUnifiedConfig
{
   int    maxZones;           // Maximum zones to track
   int    lookback;           // Default lookback bars
   int    leftBars;           // Pivot left confirmation
   int    rightBars;          // Pivot right confirmation
   double minStrength;        // Minimum zone strength
   double clusterTolerance;   // Zone clustering ATR multiplier
   bool   enableCache;        // Enable caching
   bool   enableMemoryPool;   // Use memory pool
   bool   batchScan;          // Use batch scanning
   
   void SetDefaults()
   {
      maxZones         = 60;
      lookback         = 300;
      leftBars         = 3;
      rightBars        = 3;
      minStrength      = 15.0;
      clusterTolerance = 0.3;
      enableCache      = true;
      enableMemoryPool = true;
      batchScan        = true;
   }
   
   void SetConservative()
   {
      maxZones         = 40;
      lookback         = 200;
      leftBars         = 5;
      rightBars        = 5;
      minStrength      = 25.0;
      clusterTolerance = 0.2;
   }
   
   void SetAggressive()
   {
      maxZones         = 80;
      lookback         = 500;
      leftBars         = 2;
      rightBars        = 2;
      minStrength      = 10.0;
      clusterTolerance = 0.4;
   }
};

//+------------------------------------------------------------------+
//| CSRUnifiedManager — Main refactored SR manager                   |
//+------------------------------------------------------------------+
class CSRUnifiedManager
{
private:
   SRUnifiedConfig  m_config;
   CSRBatchScanner  m_scanner;
   CSRZoneCache     m_cache;
   CSRMemoryPool    m_memoryPool;
   
   SRZoneExtended   m_zones[];
   int              m_zoneCount;
   
   double           m_atrCurrent;
   datetime         m_lastScanTime;
   int              m_lastScanBar;
   
   bool             m_initialized;
   
   // Statistics
   ulong            m_scanCount;
   ulong            m_zoneHits;
   ulong            m_zoneMisses;
   
public:
   CSRUnifiedManager() : m_zoneCount(0), m_atrCurrent(0),
                         m_lastScanTime(0), m_lastScanBar(-1),
                         m_initialized(false),
                         m_scanCount(0), m_zoneHits(0), m_zoneMisses(0)
   {
      m_config.SetDefaults();
   }
   
   ~CSRUnifiedManager() { Cleanup(); }
   
   // Initialize manager
   bool Initialize(const string symbol, ENUM_TIMEFRAMES tf, 
                  const SRUnifiedConfig &config)
   {
      m_config = config;
      
      if(m_config.enableMemoryPool)
      {
         if(!m_memoryPool.Initialize(m_config.maxZones * 2))
            return false;
      }
      
      if(m_config.batchScan)
      {
         if(!m_scanner.Initialize(m_config.lookback + 100, m_config.maxZones * 2))
            return false;
         
         ScanConfig scanCfg;
         scanCfg.lookback         = m_config.lookback;
         scanCfg.leftBars         = m_config.leftBars;
         scanCfg.rightBars        = m_config.rightBars;
         scanCfg.minStrength      = m_config.minStrength;
         scanCfg.clusterTolerance = m_config.clusterTolerance;
         m_scanner.SetConfig(scanCfg);
      }
      
      if(m_config.enableCache)
      {
         if(!m_cache.Initialize(symbol, tf))
            return false;
      }
      
      ArrayResize(m_zones, m_config.maxZones);
      m_zoneCount = 0;
      
      m_initialized = true;
      return true;
   }
   
   void Cleanup()
   {
      m_scanner.Cleanup();
      m_cache.Cleanup();
      m_memoryPool.Cleanup();
      ArrayFree(m_zones);
      m_zoneCount = 0;
      m_initialized = false;
   }
   
   // Main scan function
   bool Scan(const string symbol, ENUM_TIMEFRAMES tf)
   {
      if(!m_initialized)
         return false;
      
      // Check cache first
      if(m_config.enableCache && m_cache.IsValid(symbol, tf))
      {
         int cachedCount = 0;
         if(m_cache.GetCachedZones(m_zones, cachedCount))
         {
            m_zoneCount = cachedCount;
            m_zoneHits++;
            return true;
         }
      }
      
      m_zoneMisses++;
      
      // Perform batch scan
      if(m_config.batchScan)
      {
         ScanResult result;
         
         if(m_scanner.Scan(symbol, tf, result))
         {
            // Copy results to internal array
            m_zoneCount = MathMin(result.zoneCount, m_config.maxZones);
            
            for(int i = 0; i < m_zoneCount; i++)
            {
               m_zones[i] = result.zones[i];
            }
            
            // Cache results
            if(m_config.enableCache)
            {
               m_cache.CacheZones(m_zones, m_zoneCount);
            }
            
            m_lastScanTime = TimeCurrent();
            m_lastScanBar  = 0;
            m_scanCount++;
            
            return true;
         }
      }
      
      return false;
   }
   
   // Get zones
   int GetZones(SRZoneExtended &result[]) const
   {
      if(m_zoneCount == 0)
         return 0;
      
      if(ArraySize(result) < m_zoneCount)
         ArrayResize(result, m_zoneCount);
      
      ArrayCopy(result, m_zones, 0, 0, m_zoneCount);
      return m_zoneCount;
   }
   
   // Find nearest support
   SRZoneExtended* FindNearestSupport(double currentPrice) const
   {
      SRZoneExtended* bestZone = NULL;
      double bestDistance = DBL_MAX;
      
      for(int i = 0; i < m_zoneCount; i++)
      {
         if(!m_zones[i].isSupport)
            continue;
         
         if(m_zones[i].high >= currentPrice)
            continue;  // Zone is above price
         
         double distance = currentPrice - m_zones[i].high;
         
         if(distance < bestDistance)
         {
            bestDistance = distance;
            bestZone = &m_zones[i];
         }
      }
      
      return bestZone;
   }
   
   // Find nearest resistance
   SRZoneExtended* FindNearestResistance(double currentPrice) const
   {
      SRZoneExtended* bestZone = NULL;
      double bestDistance = DBL_MAX;
      
      for(int i = 0; i < m_zoneCount; i++)
      {
         if(m_zones[i].isSupport)
            continue;
         
         if(m_zones[i].low <= currentPrice)
            continue;  // Zone is below price
         
         double distance = m_zones[i].low - currentPrice;
         
         if(distance < bestDistance)
         {
            bestDistance = distance;
            bestZone = &m_zones[i];
         }
      }
      
      return bestZone;
   }
   
   // Check if price is in zone
   bool IsPriceInZone(double price, SRZoneExtended &out) const
   {
      for(int i = 0; i < m_zoneCount; i++)
      {
         if(price >= m_zones[i].low && price <= m_zones[i].high)
         {
            out = m_zones[i];
            return true;
         }
      }
      return false;
   }
   
   // Get ATR
   double GetATR() const { return m_atrCurrent; }
   
   // Update on new bar
   void OnNewBar(const string symbol, ENUM_TIMEFRAMES tf)
   {
      if(m_config.enableCache)
      {
         m_cache.UpdateOnNewBar(symbol, tf);
      }
      
      m_lastScanBar = -1;  // Force rescan
   }
   
   // Statistics
   ulong GetScanCount() const { return m_scanCount; }
   int GetZoneCount() const { return m_zoneCount; }
   
   string GetStatsString() const
   {
      string stats = StringFormat("SRUnified[Zones=%d|Scans=%d|CacheHit=%.1f%%]",
                                 m_zoneCount, m_scanCount,
                                 (m_zoneHits + m_zoneMisses > 0) ? 
                                 (double)m_zoneHits / (m_zoneHits + m_zoneMisses) * 100.0 : 0.0);
      
      if(m_config.batchScan)
         stats += "|" + m_scanner.GetStatsString();
      
      if(m_config.enableMemoryPool)
         stats += "|" + m_memoryPool.GetStatsString();
      
      if(m_config.enableCache)
         stats += "|" + m_cache.GetStatsString();
      
      return stats;
   }
   
   // Configuration accessors
   const SRUnifiedConfig& GetConfig() const { return m_config; }
   void SetConfig(const SRUnifiedConfig &config) { m_config = config; }
   
   bool IsInitialized() const { return m_initialized; }
};

#endif // __ANALYSIS_OPTIMIZED_SR_UNIFIED_MANAGER_MQH__
