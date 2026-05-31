//+------------------------------------------------------------------+
//| Core/IManager.mqh - CANONICAL v2.22                              |
//| Base class for all PASR managers                                 |
//+------------------------------------------------------------------+
#ifndef CORE_IMANAGER_MQH
#define CORE_IMANAGER_MQH
#include "IDataManager.mqh"
#define PASR_MAX_EVENT_ID 100

class IManager : public IEventHandler
  {
protected:
   IDataManager     *m_data;
   CEventBus        *m_bus;
   StrategyConfig    m_cfg;
   bool              m_cfgDirty;
   bool              m_debugMode;
   bool              m_eventSubscribed[PASR_MAX_EVENT_ID];
   bool              m_hasExplicitSubscriptions;
   bool              m_initialized;

   void RefreshConfig()
     {
      if(m_data == NULL) return;
      m_data.GetConfigCache(m_cfg);
      m_cfgDirty = false;
     }

   void DispatchImmediate(const PASREvent &ev)
     {
      if(m_bus == NULL) return;
      if(CheckPointer(m_bus) == POINTER_INVALID) return;
      m_bus.DispatchImmediate(ev);
     }

   void DispatchEvent(const PASREvent &ev)
     {
      DispatchImmediate(ev);
     }

   void QueueEvent(const PASREvent &ev)
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
      int idx = (int)id;
      if(idx < 0 || idx >= PASR_MAX_EVENT_ID) return;
      m_eventSubscribed[idx] = true;
      m_hasExplicitSubscriptions = true;
     }

   string BuildGVPrefix()
     {
      long login = AccountInfoInteger(ACCOUNT_LOGIN);
      long magic = m_cfg.MagicNumber;
      return "PASR_" + IntegerToString(login) + "_" + IntegerToString(magic) + "_";
     }

public:
   IManager() : m_data(NULL), m_bus(NULL), m_cfgDirty(true),
                m_debugMode(false), m_hasExplicitSubscriptions(false),
                m_initialized(false)
     { ArrayInitialize(m_eventSubscribed, false); }

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
      ArrayInitialize(m_eventSubscribed, false);
      m_hasExplicitSubscriptions = false;
     }

   virtual void OnEvent(const PASREvent &ev) {}
   virtual void OnNewBar()      {}
   virtual void OnPriceUpdate() {}
   virtual void DeclareEvents() {}

   virtual bool IsListening(ENUM_EVENT_ID id) const
     {
      int idx = (int)id;
      if(idx < 0 || idx >= PASR_MAX_EVENT_ID) return false;
      if(!m_hasExplicitSubscriptions)
         return (id != EVENT_ID_TICK && id != EVENT_ID_PRICE_UPDATE);
      return m_eventSubscribed[idx];
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