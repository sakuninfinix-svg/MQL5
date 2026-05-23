//+------------------------------------------------------------------+
//| AI/ModelRegistry.mqh                                             |
//| Model registration, versioning and lifecycle management          |
//+------------------------------------------------------------------+
#property strict
#ifndef __MODEL_REGISTRY_MQH__
#define __MODEL_REGISTRY_MQH__

#include "AITypes.mqh"

#define REGISTRY_MAX_MODELS 8

//--- Model descriptor
struct SModelDescriptor
{
   string            id;           // Unique model ID
   ENUM_AI_MODEL_TYPE type;        // Model type
   string            file_path;    // File path for ONNX/weights
   double            version;      // Version number
   bool              active;       // Is this model active?
   bool              loaded;       // Is it loaded in memory?
   datetime          created_at;
   datetime          last_used;
   SAIModelPerf      perf;         // Performance tracking
   
   void Reset()
   {
      id          = "";
      type        = AI_MODEL_NONE;
      file_path   = "";
      version     = 1.0;
      active      = false;
      loaded      = false;
      created_at  = 0;
      last_used   = 0;
      perf.Reset();
   }
};

//+------------------------------------------------------------------+
//| CModelRegistry                                                   |
//| Tracks all registered AI models with their descriptors           |
//| Supports activation/deactivation and performance queries         |
//+------------------------------------------------------------------+
class CModelRegistry
{
private:
   SModelDescriptor m_models[REGISTRY_MAX_MODELS];
   int              m_count;
   string           m_active_id;    // currently active model ID
   
public:
   CModelRegistry() : m_count(0), m_active_id("")
   {
      for(int i=0; i<REGISTRY_MAX_MODELS; i++) m_models[i].Reset();
   }
   
   //--- Register a model
   bool Register(const SModelDescriptor &desc)
   {
      if(m_count >= REGISTRY_MAX_MODELS) return false;
      if(Find(desc.id) >= 0) return false;  // already registered
      
      m_models[m_count] = desc;
      m_models[m_count].created_at = TimeCurrent();
      m_count++;
      PrintFormat("ModelRegistry: Registered '%s' (type=%d, v%.1f)",
                  desc.id, (int)desc.type, desc.version);
      return true;
   }
   
   //--- Find by ID, return index or -1
   int Find(const string &id) const
   {
      for(int i=0; i<m_count; i++)
         if(m_models[i].id == id) return i;
      return -1;
   }
   
   //--- Get descriptor reference
   bool Get(const string &id, SModelDescriptor &out) const
   {
      int idx = Find(id);
      if(idx < 0) return false;
      out = m_models[idx];
      return true;
   }
   
   //--- Activate a model
   bool Activate(const string &id)
   {
      int idx = Find(id);
      if(idx < 0) return false;
      // Deactivate current
      int cur = Find(m_active_id);
      if(cur >= 0) m_models[cur].active = false;
      // Activate new
      m_models[idx].active = true;
      m_active_id          = id;
      PrintFormat("ModelRegistry: Activated '%s'", id);
      return true;
   }
   
   //--- Deactivate a model
   bool Deactivate(const string &id)
   {
      int idx = Find(id);
      if(idx < 0) return false;
      m_models[idx].active = false;
      if(m_active_id == id) m_active_id = "";
      return true;
   }
   
   //--- Update performance
   void UpdatePerf(const string &id, bool correct, double conf, double drift)
   {
      int idx = Find(id);
      if(idx < 0) return;
      m_models[idx].perf.Update(correct, conf, drift);
      m_models[idx].last_used = TimeCurrent();
   }
   
   //--- Auto-select best model by accuracy
   string GetBestModelId() const
   {
      int best_idx = -1;
      double best_acc = -1.0;
      for(int i=0; i<m_count; i++)
      {
         if(!m_models[i].loaded) continue;
         if(m_models[i].perf.accuracy > best_acc)
         {
            best_acc = m_models[i].perf.accuracy;
            best_idx = i;
         }
      }
      return (best_idx >= 0) ? m_models[best_idx].id : m_active_id;
   }
   
   //--- Stats
   int    GetCount()          const { return m_count;     }
   string GetActiveId()       const { return m_active_id; }
   bool   IsRegistered(const string &id) const { return Find(id) >= 0; }
};

#endif // __MODEL_REGISTRY_MQH__
