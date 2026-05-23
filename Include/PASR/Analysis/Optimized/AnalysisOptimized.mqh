//+------------------------------------------------------------------+
//| Analysis/Optimized/AnalysisOptimized.mqh                         |
//| Master Include - Optimized Analysis Module                       |
//|                                                                  |
//| Single include file that provides all optimized components       |
//|                                                                  |
//| USAGE:                                                           |
//|   #include "../Analysis/Optimized/AnalysisOptimized.mqh"        |
//|                                                                  |
//| PROVIDES:                                                        |
//|   - CSRUnifiedManager (main SR manager)                          |
//|   - CSRBatchScanner (high-speed scanning)                        |
//|   - CSRZoneCache (advanced caching)                              |
//|   - CSRMemoryPool (memory optimization)                          |
//|   - CPerformanceOptimizer (batch data utilities)                 |
//+------------------------------------------------------------------+
#property strict
#ifndef __ANALYSIS_OPTIMIZED_MASTER_MQH__
#define __ANALYSIS_OPTIMIZED_MASTER_MQH__

// Core dependencies
#include "../Data/SRStruct.mqh"

// Optimized components
#include "PerformanceUtils.mqh"
#include "SRZoneCache.mqh"
#include "SRMemoryPool.mqh"
#include "SRBatchScanner.mqh"
#include "SRUnifiedManager.mqh"

//+------------------------------------------------------------------+
//| Quick Start Helper Class                                         |
//+------------------------------------------------------------------+
class CAnalysisOptimized
{
private:
   static CSRUnifiedManager* s_manager;
   static bool               s_initialized;
   
public:
   // Initialize the optimized analysis module
   static bool Initialize(const string symbol, ENUM_TIMEFRAMES tf, 
                         bool useAggressive = false)
   {
      if(s_initialized && s_manager != NULL)
         return true;
      
      s_manager = new CSRUnifiedManager();
      
      SRUnifiedConfig config;
      if(useAggressive)
         config.SetAggressive();
      else
         config.SetDefaults();
      
      bool result = s_manager->Initialize(symbol, tf, config);
      s_initialized = result;
      
      return result;
   }
   
   // Cleanup
   static void Cleanup()
   {
      if(s_manager != NULL)
      {
         delete s_manager;
         s_manager = NULL;
      }
      s_initialized = false;
   }
   
   // Get manager instance
   static CSRUnifiedManager* GetManager()
   {
      return s_manager;
   }
   
   // Quick scan function
   static bool Scan(const string symbol, ENUM_TIMEFRAMES tf)
   {
      if(!s_initialized || s_manager == NULL)
         return false;
      
      return s_manager->Scan(symbol, tf);
   }
   
   // Quick zone query
   static int GetZones(SRZoneExtended &zones[])
   {
      if(!s_initialized || s_manager == NULL)
         return 0;
      
      return s_manager->GetZones(zones);
   }
   
   // Find nearest support
   static SRZoneExtended* FindSupport(double price)
   {
      if(!s_initialized || s_manager == NULL)
         return NULL;
      
      return s_manager->FindNearestSupport(price);
   }
   
   // Find nearest resistance
   static SRZoneExtended* FindResistance(double price)
   {
      if(!s_initialized || s_manager == NULL)
         return NULL;
      
      return s_manager->FindNearestResistance(price);
   }
   
   // Check if price in zone
   static bool IsInZone(double price, SRZoneExtended &zone)
   {
      if(!s_initialized || s_manager == NULL)
         return false;
      
      return s_manager->IsPriceInZone(price, zone);
   }
   
   // Get statistics
   static string GetStats()
   {
      if(!s_initialized || s_manager == NULL)
         return "Not initialized";
      
      return s_manager->GetStatsString();
   }
   
   // Check initialization
   static bool IsInitialized() { return s_initialized; }
};

// Static member initialization
CSRUnifiedManager* CAnalysisOptimized::s_manager = NULL;
bool CAnalysisOptimized::s_initialized = false;

#endif // __ANALYSIS_OPTIMIZED_MASTER_MQH__
