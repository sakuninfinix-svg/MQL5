//+------------------------------------------------------------------+
//| Core/IManager.mqh — CANONICAL v2.18                              |
//| Base class for all PASR managers                                 |
//|                                                                  |
//| CHANGES v2.18 (2026-05-24):                                      |
//|   S21-003: Uses canonical IDataManager.mqh instead of forward    |
//|            declaring an incomplete data-provider contract.       |
//|                                                                  |
//| CHANGES v2.17 (2026-05-24):                                      |
//|   BUG-C02 — Added HandlerName() contract used by EventBus and    |
//|             Orchestrator logging.                                |
//|   BUG-C03 — Added m_initialized lifecycle guard to base manager. |
//|   BUG-NEW-06 — Init() now sets m_initialized=true; Deinit()      |
//|                resets it.                                        |
//|   BUG-C04 — IManager explicitly extends IEventHandler so         |
//|             EventBus can call IsListening() polymorphically.     |
//+------------------------------------------------------------------+
#pragma once
#ifndef CORE_IMANAGER_MQH
#define CORE_IMANAGER_MQH

#include "IDataManager.mqh"

static const uint PASR_MASK_NOISY_EVENTS = (1u << (uint)EVENT_ID_TICK) |
                                           (1u << (uint)EVENT_ID_PRICE_UPDATE);

class IManager : public IEventHandler
  {
protected:
   IDataManager     *m_data;
   CEventBus        *m_bus;
   StrategyConfig    m_cfg;
   bool              m_cfgDirty;
   bool              m_debugMode;
   uint              m_eventMask;
   bool              m_initialized;

   void RefreshConfig()
     {
      if(m_data == NULL) return;
      m_data.GetConfigCache(m_cfg);
      m_cfgDirty = false;
     }

   void DispatchEvent(const PASREvent &ev)
     {
      if(m_bus == NULL) return;
      if(CheckPointer(m_bus) == POINTER_INVALID) return;
      m_bus.Push(ev);
     }

   void Log(const string msg)
     {
      if(m_debugMode) Print(msg);
     }

   void AddEvent(ENUM_EVENT_ID id)
     {
      if((int)id >= 0 && (int)id < 32)
         m_eventMask |= (1u << (uint)id);
     }

   string BuildGVPrefix()
     {
      long login = AccountInfoInteger(ACCOUNT_LOGIN);
      long magic = m_cfg.MagicNumber;
      return "PASR_" + IntegerToString(login) + "_" + IntegerToString(magic) + "_";
     }

public:
   IManager() : m_data(NULL), m_bus(NULL), m_cfgDirty(true),
                m_debugMode(false), m_eventMask(0), m_initialized(false)
     {}

   virtual string HandlerName() const { return "IManager"; }

   virtual bool Init(IDataManager *data, CEventBus *bus)
     {
      if(m_initialized) return true;
      if(data == NULL) return false;

      m_data = data;
      m_bus  = bus;

      RefreshConfig();
      DeclareEvents();
      m_initialized = true;
      return true;
     }

   virtual void Deinit()
     {
      m_initialized = false;
      m_eventMask   = 0;
     }

   virtual void OnEvent(const PASREvent &ev) {}
   virtual void OnNewBar()      {}
   virtual void OnPriceUpdate() {}
   virtual void DeclareEvents() {}

   virtual bool IsListening(ENUM_EVENT_ID id) const
     {
      if(m_eventMask == 0)
        {
         if((int)id >= 0 && (int)id < 32)
            return (PASR_MASK_NOISY_EVENTS & (1u << (uint)id)) == 0;
         return true;
        }
      if((int)id < 0 || (int)id >= 32) return false;
      return (m_eventMask & (1u << (uint)id)) != 0;
     }

   virtual bool IsHealthy() const
     {
      return (m_initialized && m_data != NULL);
     }

   virtual void OnConfigReload() { RefreshConfig(); }

   void SetDebugMode(bool enable) { m_debugMode = enable; }
   bool IsInitialized() const { return m_initialized; }
  };

#endif // CORE_IMANAGER_MQH
