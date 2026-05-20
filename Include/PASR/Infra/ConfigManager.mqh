//+------------------------------------------------------------------+
//| Infra/ConfigManager.mqh                                          |
//| Canonical alias — forwards to Core/Config/Manager.mqh           |
//| (matches Core/PASR.mqh L1 Config load)                         |
//+------------------------------------------------------------------+
#ifndef __INFRA_CONFIG_MANAGER_MQH__
#define __INFRA_CONFIG_MANAGER_MQH__
#ifdef __MQL5__
   #include <PASR/Core/Config/Manager.mqh>
#else
   #include "../Core/Config/Manager.mqh"
#endif
#endif
