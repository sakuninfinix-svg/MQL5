//+------------------------------------------------------------------+
//| Central/ModuleRegistry.mqh — v0.10                               |
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

   void Clear(const bool deinitFirst = true)
     {
      for(int i = m_count - 1; i >= 0; i--)
        {
         if(m_modules[i] != NULL && m_owned[i])
           {
            if(deinitFirst)
               m_modules[i].Deinit();
            delete m_modules[i];
           }
         m_modules[i] = NULL;
         m_names[i]   = "";
         m_owned[i]   = false;
        }
      m_count = 0;
     }
  };

#endif // __PASR_CENTRAL_MODULE_REGISTRY_MQH__
