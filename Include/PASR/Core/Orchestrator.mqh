//+------------------------------------------------------------------+
//| Core/Orchestrator.mqh - v3.11                                    |
//| Compatibility wrapper for Central/BackendAdapter.mqh              |
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_ORCHESTRATOR_WRAPPER_MQH__
#define __CORE_ORCHESTRATOR_WRAPPER_MQH__

#include <PASR/Central/BackendAdapter.mqh>

class COrchestrator : public CBackendAdapter
  {
public:
   COrchestrator() : CBackendAdapter() {}
   ~COrchestrator() {}
  };

#endif // __CORE_ORCHESTRATOR_WRAPPER_MQH__
