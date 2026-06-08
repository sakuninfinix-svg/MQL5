//+------------------------------------------------------------------+
//| Central/LifecycleManager.mqh - v1.00                              |
//| Uniform init/deinit helper with explicit lifecycle state tracking |
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
   string           m_initialized[PASR_CENTRAL_MAX_MODULES];
   int              m_initialized_count;
   string           m_last_error;

   int FindInitialized(const string name) const
     {
      for(int i = 0; i < m_initialized_count; i++)
         if(m_initialized[i] == name)
            return i;
      return -1;
     }

   bool MarkInitialized(const string name)
     {
      if(name == "")
         return false;
      if(FindInitialized(name) >= 0)
         return true;
      if(m_initialized_count >= PASR_CENTRAL_MAX_MODULES)
        {
         m_last_error = "Lifecycle initialized list full";
         return false;
        }
      m_initialized[m_initialized_count++] = name;
      return true;
     }

   void MarkDeinitialized(const string name)
     {
      int idx = FindInitialized(name);
      if(idx < 0)
         return;
      for(int i = idx; i < m_initialized_count - 1; i++)
         m_initialized[i] = m_initialized[i + 1];
      m_initialized_count--;
      if(m_initialized_count >= 0 && m_initialized_count < PASR_CENTRAL_MAX_MODULES)
         m_initialized[m_initialized_count] = "";
     }

public:
   CLifecycleManager()
      : m_registry(NULL), m_data(NULL), m_bus(NULL), m_debug(false),
        m_initialized_count(0), m_last_error("")
     {
      for(int i = 0; i < PASR_CENTRAL_MAX_MODULES; i++)
         m_initialized[i] = "";
     }

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
         m_last_error = name + " is NULL";
         Print("[Lifecycle] ", m_last_error);
         return false;
        }

      if(IsInitialized(name))
        {
         if(m_debug)
            PrintFormat("[Lifecycle] %s already initialized; skip duplicate init", name);
         return true;
        }

      if(module.IsInitialized())
        {
         MarkInitialized(name);
         if(m_debug)
            PrintFormat("[Lifecycle] %s already module-initialized; state recorded", name);
         return true;
        }

      if(m_debug)
         module.SetDebugMode(true);

      if(!module.Init(m_data, m_bus))
        {
         m_last_error = name + ".Init failed";
         Print("[Lifecycle] ", m_last_error);
         return false;
        }

      if(m_bus != NULL && !m_bus.Register(module))
         PrintFormat("[Lifecycle] EventBus register failed for %s", name);

      MarkInitialized(name);
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
      MarkDeinitialized(name);
     }

   bool InitRegistered()
     {
      if(m_registry == NULL)
        {
         m_last_error = "Registry not bound";
         Print("[Lifecycle] ", m_last_error);
         return false;
        }

      for(int i = 0; i < m_registry.Count(); i++)
        {
         IManager *module = m_registry.ModuleAt(i);
         string name = m_registry.NameAt(i);
         if(module == NULL)
           {
            m_last_error = name + " is NULL";
            Print("[Lifecycle] ", m_last_error);
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
        {
         ResetState();
         return;
        }

      for(int i = m_registry.Count() - 1; i >= 0; i--)
        {
         IManager *module = m_registry.ModuleAt(i);
         string name = m_registry.NameAt(i);
         if(module != NULL)
            DeinitOne(module, name);
        }
      ResetState();
     }

   bool IsInitialized(const string name) const
     {
      return FindInitialized(name) >= 0;
     }

   int InitializedCount() const
     {
      return m_initialized_count;
     }

   string LastError() const
     {
      return m_last_error;
     }

   void ResetState()
     {
      for(int i = 0; i < PASR_CENTRAL_MAX_MODULES; i++)
         m_initialized[i] = "";
      m_initialized_count = 0;
      m_last_error = "";
     }
  };

#endif // __PASR_CENTRAL_LIFECYCLE_MANAGER_MQH__
