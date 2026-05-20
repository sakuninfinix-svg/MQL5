//+------------------------------------------------------------------+
//|                                                     PASR.mqh     |
//|                         Copyright 2026, Agsicentre              |
//|                   agsicentre.wordpress.com                       |
//|                                                                  |
//| PASR MASTER INCLUDE — root convenience entry point              |
//|                                                                  |
//| This file is a thin forwarder to Core/PASR.mqh                  |
//| which is the TRUE master include with correct load order.        |
//|                                                                  |
//| Both paths work:                                                 |
//|   #include <PASR/PASR.mqh>        ← legacy EA path              |
//|   #include <PASR/Core/PASR.mqh>   ← canonical path              |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property strict

#ifndef __PASR_ROOT_MQH__
#define __PASR_ROOT_MQH__

#ifdef __MQL5__
   #include <PASR/Core/PASR.mqh>
#else
   #include "Core/PASR.mqh"
#endif

#endif // __PASR_ROOT_MQH__
