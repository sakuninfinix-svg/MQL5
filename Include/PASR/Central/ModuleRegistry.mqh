//+------------------------------------------------------------------+
//| Central/ModuleRegistry.mqh — v0.20                               |
//| Centralized registry for PASR managers/modules                    |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_CENTRAL_MODULE_REGISTRY_MQH__
#define __PASR_CENTRAL_MODULE_REGISTRY_MQH__

#ifndef PASR_CENTRAL_MAX_MODULES
#define PASR_CENTRAL_MAX_MODULES 64
#endif

class CModuleRegistry
  {
private:
   IManager *m_modules[PASR_CENTRAL_MAX_MODULES];
   string    m_names[PASR_CENTRAL_MAX_MODULES];
   bool      m_owned[PASR_CENTRAL_MAX_MODULES];
   int       m_count;
   bool      m_debug;

   int FindIndexByName(const string name) const
     {
      for(int i = 0; i < m_count; i++)
         if(m_names[i] == name)
            return i;
      return -1;
     }

   void ReleaseSlot(const int idx, const bool deinitFirst)
     {
      if(idx < 0 || idx >= m_count) return;
      if(m_modules[idx] != NULL && m_owned[idx])
        {
         if(deinitFirst)
            m_modules[idx].Deinit();
         delete m_modules[idx];
        }
      m_modules[idx] = NULL;
      m_names[idx]   = "";
      m_owned[idx]   = false;
     }

public:
   CModuleRegistry()
      : m_count(0), m_debug(false)
     {
      for(int i = 0; i < PASR_CENTRAL_MAX_MODULES; i++)
        {
         m_modules[i] = NULL;
         m_names[i]   = "";
         m_owned[i]   = false;
        }
     }

   ~CModuleRegistry()
     {
      Clear(false);
     }

   void SetDebugMode(const bool enabled)
     {
      m_debug = enabled;
     }

   bool Register(const string name, IManager *module, const bool owned = true)
     {
      if(name == "" || module == NULL)
        {
         if(m_debug) Print("[ModuleRegistry] Register rejected: empty name or null module");
         return false;
        }

      if(FindIndexByName(name) >= 0)
        {
         if(m_debug) PrintFormat("[ModuleRegistry] Duplicate module name: %s", name);
         return false;
        }

      if(m_count >= PASR_CENTRAL_MAX_MODULES)
        {
         PrintFormat("[ModuleRegistry] Registry full, cannot register %s", name);
         return false;
        }

      m_names[m_count]   = name;
      m_modules[m_count] = module;
      m_owned[m_count]   = owned;
      m_count++;

      if(m_debug) PrintFormat("[ModuleRegistry] Registered %s", name);
      return true;
     }

   bool RegisterOrReplace(const string name, IManager *module, const bool owned = true, const bool deinitOld = false)
     {
      if(name == "" || module == NULL)
         return false;

      int idx = FindIndexByName(name);
      if(idx < 0)
         return Register(name, module, owned);

      ReleaseSlot(idx, deinitOld);
      m_modules[idx] = module;
      m_names[idx]   = name;
      m_owned[idx]   = owned;
      if(m_debug) PrintFormat("[ModuleRegistry] Replaced %s", name);
      return true;
     }

   bool Unregister(const string name, const bool deinitFirst = false)
     {
      int idx = FindIndexByName(name);
      if(idx < 0) return false;

      ReleaseSlot(idx, deinitFirst);

      for(int i = idx; i < m_count - 1; i++)
        {
         m_modules[i] = m_modules[i + 1];
         m_names[i]   = m_names[i + 1];
         m_owned[i]   = m_owned[i + 1];
        }

      m_count--;
      m_modules[m_count] = NULL;
      m_names[m_count]   = "";
      m_owned[m_count]   = false;
      return true;
     }

   IManager* Get(const string name) const
     {
      int idx = FindIndexByName(name);
      if(idx < 0) return NULL;
      return m_modules[idx];
     }

   bool Contains(const string name) const
     {
      return (FindIndexByName(name) >= 0);
     }

   bool IsReady(const string name) const
     {
      IManager *module = Get(name);
      if(module == NULL) return false;
      return module.IsInitialized();
     }

   int Count() const
     {
      return m_count;
     }

   string NameAt(const int index) const
     {
      if(index < 0 || index >= m_count) return "";
      return m_names[index];
     }

   IManager* ModuleAt(const int index) const
     {
      if(index < 0 || index >= m_count) return NULL;
      return m_modules[index];
     }

   bool OwnedAt(const int index) const
     {
      if(index < 0 || index >= m_count) return false;
      return m_owned[index];
     }

   void PrintSummary() const
     {
      PrintFormat("[ModuleRegistry] modules=%d/%d", m_count, PASR_CENTRAL_MAX_MODULES);
      for(int i = 0; i < m_count; i++)
        {
         string state = (m_modules[i] != NULL && m_modules[i].IsInitialized()) ? "ready" : "bound";
         PrintFormat("[ModuleRegistry] %02d %s owned=%s state=%s", i, m_names[i], m_owned[i] ? "true" : "false", state);
        }
     }

   void Clear(const bool deinitFirst = true)
     {
      for(int i = m_count - 1; i >= 0; i--)
         ReleaseSlot(i, deinitFirst);
      m_count = 0;
     }
  };

#endif // __PASR_CENTRAL_MODULE_REGISTRY_MQH__
