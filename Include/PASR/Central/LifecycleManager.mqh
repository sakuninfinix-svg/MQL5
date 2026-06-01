//+------------------------------------------------------------------+
//| Central/LifecycleManager.mqh — v0.10                              |
//| Uniform init/deinit helper for registered PASR modules             |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_CENTRAL_LIFECYCLE_MANAGER_MQH__
#define __PASR_CENTRAL_LIFECYCLE_MANAGER_MQH__

class CLifecycleManager
  {
private:
   CModuleRegistry *m_registry;
   CDataManager    *m_data;
   CEventBus       *m_bus;
   bool             m_debug;

public:
   CLifecycleManager()
      : m_registry(NULL), m_data(NULL), m_bus(NULL), m_debug(false)
     {}

   void Bind(CModuleRegistry *registry, CDataManager *data, CEventBus *bus)
     {
      m_registry = registry;
      m_data     = data;
      m_bus      = bus;
     }

   void SetDebugMode(const bool enabled)
     {
      m_debug = enabled;
     }

   bool InitOne(IManager *module, const string name)
     {
      if(module == NULL)
        {
         PrintFormat("[Lifecycle] %s is NULL", name);
         return false;
        }

      if(m_debug)
         module.SetDebugMode(true);

      if(!module.Init(m_data, m_bus))
        {
         PrintFormat("[Lifecycle] %s.Init failed", name);
         return false;
        }

      if(m_bus != NULL && !m_bus.Register(module))
         PrintFormat("[Lifecycle] EventBus register failed for %s", name);

      return true;
     }

   bool InitCritical(IManager *module, const string name)
     {
      if(!InitOne(module, name))
        {
         PrintFormat("[Lifecycle] CRITICAL module failed: %s", name);
         return false;
        }
      return true;
     }

   bool InitOptional(IManager *module, const string name)
     {
      if(!InitOne(module, name))
        {
         PrintFormat("[Lifecycle] OPTIONAL module disabled: %s", name);
         return false;
        }
      return true;
     }

   void DeinitOne(IManager *module, const string name)
     {
      if(module == NULL)
         return;
      if(m_debug)
         PrintFormat("[Lifecycle] Deinit %s", name);
      module.Deinit();
     }

   bool InitRegistered()
     {
      if(m_registry == NULL)
        {
         Print("[Lifecycle] Registry not bound");
         return false;
        }

      for(int i = 0; i < m_registry.Count(); i++)
        {
         IManager *module = m_registry.ModuleAt(i);
         string name = m_registry.NameAt(i);
         if(module == NULL)
           {
            PrintFormat("[Lifecycle] %s is NULL", name);
            return false;
           }
         if(!InitOne(module, name))
            return false;
        }
      return true;
     }

   void DeinitRegistered()
     {
      if(m_registry == NULL)
         return;

      for(int i = m_registry.Count() - 1; i >= 0; i--)
        {
         IManager *module = m_registry.ModuleAt(i);
         if(module != NULL)
            module.Deinit();
        }
     }
  };

#endif // __PASR_CENTRAL_LIFECYCLE_MANAGER_MQH__
