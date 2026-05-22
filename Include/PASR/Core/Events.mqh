//+------------------------------------------------------------------+
//| Core/Events.mqh — CANONICAL v2.13                                |
//| All event type definitions for the PASR framework                |
//+------------------------------------------------------------------+
#pragma once
#ifndef CORE_EVENTS_MQH
#define CORE_EVENTS_MQH

//+------------------------------------------------------------------+
//| Event IDs — type-safe enum (replaces legacy #define macros)      |
//+------------------------------------------------------------------+
enum ENUM_EVENT_ID
  {
   EVENT_ID_NONE             = 0,
   EVENT_ID_TICK             = 1,
   EVENT_ID_NEW_BAR          = 2,
   EVENT_ID_SIGNAL           = 3,
   EVENT_ID_TRADE_OPEN       = 4,
   EVENT_ID_TRADE_CLOSE      = 5,
   EVENT_ID_TRADE_MODIFY     = 6,
   EVENT_ID_CONFIG_RELOAD    = 7,
   EVENT_ID_NEWS             = 8,
   EVENT_ID_RECOVERY         = 9,
   EVENT_ID_RISK_LIMIT       = 10,
   EVENT_ID_SESSION          = 11,
   // System & Sanity Events (New v13.01)
   EVENT_ID_SYSTEM_INFO      = 12,
   EVENT_ID_SYSTEM_WARNING   = 13,
   EVENT_ID_SYSTEM_CRITICAL  = 14,
   // AI-specific
   EVENT_AI_PREDICTION_READY = 20,
   EVENT_AI_TRAIN_STEP       = 21,
   // Signal-specific
   EVENT_SIGNAL_GENERATED    = 30,
   // Deferred / async
   EVENT_ID_DEFERRED         = 99
  };

//+------------------------------------------------------------------+
//| PASREvent — lightweight event struct (no heap alloc)             |
//+------------------------------------------------------------------+
struct PASREvent
  {
   ENUM_EVENT_ID     id;
   int               priority;   // lower = higher priority
   datetime          timestamp;
   double            data1;
   double            data2;
   string            tag;

   PASREvent() : id(EVENT_ID_NONE), priority(99), timestamp(0),
                 data1(0), data2(0), tag("") {}

   PASREvent(ENUM_EVENT_ID eid, int prio = 50,
             double d1 = 0, double d2 = 0, const string t = "")
     {
      id        = eid;
      priority  = prio;
      timestamp = TimeCurrent();
      data1     = d1;
      data2     = d2;
      tag       = t;
     }
  };

#endif // CORE_EVENTS_MQH
