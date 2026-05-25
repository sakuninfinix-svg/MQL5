//+------------------------------------------------------------------+
//| Core/Events.mqh — CANONICAL v2.15                                |
//| All event type definitions for the PASR framework                |
//+------------------------------------------------------------------+
#pragma once
#ifndef CORE_EVENTS_MQH
#define CORE_EVENTS_MQH

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
   EVENT_ID_SYSTEM_INFO      = 12,
   EVENT_ID_SYSTEM_WARNING   = 13,
   EVENT_ID_SYSTEM_CRITICAL  = 14,
   EVENT_ID_PRICE_UPDATE     = 15,
   EVENT_ID_TIMER            = 16,
   EVENT_ID_POSITION_UPDATE  = 17,
   EVENT_ID_SESSION_UPDATED  = 18,
   EVENT_ID_ZONE_UPDATE      = 19,
   EVENT_AI_PREDICTION_READY = 20,
   EVENT_AI_TRAIN_STEP       = 21,
   EVENT_ID_RECOVERY_OPPORTUNITY = 22,
   EVENT_ID_EMERGENCY_STOP       = 23,
   EVENT_ID_HEARTBEAT            = 24,
   EVENT_SIGNAL_GENERATED        = 30,
   EVENT_ID_PIPELINE_STAGE_COMPLETE = 40,
   EVENT_ID_ORDER_EXECUTED          = 41,
   EVENT_ID_ORDER_REQUEST           = 42,
   EVENT_ID_LATENCY_SIMULATION      = 43,
   EVENT_ID_REQUOTE_SIMULATED       = 44,
   EVENT_ID_ADAPTIVE_UPDATE         = 45,
   EVENT_ID_SYSTEM_RECOVER          = 46,
   EVENT_ID_SYSTEM_HALT             = 47,
   EVENT_ID_HEALTH_CHECK            = 48,
   EVENT_ID_SNAPSHOT_SAVE           = 49,
   EVENT_ID_SNAPSHOT_LOAD           = 50,
   EVENT_ID_DEFERRED                = 99
  };

struct PASREvent
  {
   ENUM_EVENT_ID     id;
   int               priority;
   datetime          timestamp;
   double            data1;
   double            data2;
   string            tag;
   string            comment;
   ulong             ticket;
   double            profit;

   PASREvent() : id(EVENT_ID_NONE), priority(99), timestamp(0),
                 data1(0), data2(0), tag(""), comment(""),
                 ticket(0), profit(0.0) {}

   PASREvent(ENUM_EVENT_ID eid, int prio = 50,
             double d1 = 0, double d2 = 0, const string t = "")
     {
      id        = eid;
      priority  = prio;
      timestamp = TimeCurrent();
      data1     = d1;
      data2     = d2;
      tag       = t;
      comment   = t;
      ticket    = 0;
      profit    = 0.0;
     }
  };

#endif // CORE_EVENTS_MQH
