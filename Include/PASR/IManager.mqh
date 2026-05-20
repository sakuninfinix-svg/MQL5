//+------------------------------------------------------------------+
//|                                                      IManager.mqh |
//|                                       Copyright 2026, Agsicentre |
//|                     Base Manager Interface - v2.11               |
//|                                                                   |
//| v2.11 FIXES:                                                      |
//| - [QUICK-WIN-03] Add m_cfg cached config to IManager base class  |
//|   → eliminates per-function StrategyConfig copy (~400 copies/sec)|
//|   → all subclasses call RefreshConfig() once on ConfigReloadEvent|
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "2.11"
#property strict

#ifndef __IMANAGER_MQH__
#define __IMANAGER_MQH__

// Forward-declare to avoid circular include; concrete type provided
// by 2.Config.Types.mqh which every manager already includes.
struct StrategyConfig;
class  CDataManager;

class IManager
{
protected:
   CDataManager *m_data;     // shared data bus (injected)
   StrategyConfig m_cfg;     // [v2.11] CACHED config — refresh on ConfigReloadEvent only
   bool           m_cfgDirty; // true until first RefreshConfig() call

   //--- Call once on init and again whenever EVENT_ID_CONFIG_RELOAD fires
   //    BEFORE (v2.10): every method did:
   //       StrategyConfig cfg;
   //       m_data.GetConfigCache(cfg);   // heap copy on every tick
   //    AFTER (v2.11): call RefreshConfig() once; use m_cfg everywhere
   void RefreshConfig()
   {
      if(CheckPointer(m_data) == POINTER_INVALID) return;
      m_data.GetConfigCache(m_cfg);
      m_cfgDirty = false;
   }

public:
   IManager() : m_data(NULL), m_cfgDirty(true) { ZeroMemory(m_cfg); }

   virtual bool   Init(CDataManager *data)
   {
      if(CheckPointer(data) == POINTER_INVALID) return false;
      m_data = data;
      RefreshConfig();   // eager load on init
      return true;
   }

   virtual void   Deinit()       {}
   virtual bool   IsReady() const { return CheckPointer(m_data) != POINTER_INVALID; }

   //--- Called by orchestrator when EVENT_ID_CONFIG_RELOAD is processed
   virtual void   OnConfigReload() { RefreshConfig(); }
};

#endif // __IMANAGER_MQH__
