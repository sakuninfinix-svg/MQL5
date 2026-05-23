//+------------------------------------------------------------------+
//| Core/Events.mqh — CANONICAL v2.14                                |
//| All event type definitions for the PASR framework                |
//+------------------------------------------------------------------+
//| CHANGELOG:                                                       |
//|  v2.14 (2026-05-23) — Sprint 8:                                 |
//|    S8-001: Added EVENT_ID_PRICE_UPDATE (missing, compile error) |
//|    S8-001: Added EVENT_ID_TIMER (missing, compile error)        |
//|    S8-001: Added EVENT_ID_POSITION_UPDATE (was implicitly used) |
//|    S8-002: Added EVENT_ID_SESSION_UPDATED (CSessionState bcast) |
//|    S8-005: Removed data_i[]; use data1/data2 for int payloads   |
//|            e.g. health status → ev.data1=(double)status         |
//|    S8-004: Confirmed SYSTEM_RECOVER/HALT/CRITICAL exist (ok)    |
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
   // System & Sanity Events
   EVENT_ID_SYSTEM_INFO      = 12,
   EVENT_ID_SYSTEM_WARNING   = 13,
   EVENT_ID_SYSTEM_CRITICAL  = 14,
   // --- S8-001 NEW: were undefined, caused compile error in OnTick/OnTimer ---
   EVENT_ID_PRICE_UPDATE     = 15,   // pushed every tick in OnTick()
   EVENT_ID_TIMER            = 16,   // pushed by OnTimer() fallback branch
   EVENT_ID_POSITION_UPDATE  = 17,   // pushed by OnTradeTransaction on close
   // --- S8-002 NEW: broadcast by CSessionState after RecordTrade() ---
   EVENT_ID_SESSION_UPDATED  = 18,
   // AI-specific
   EVENT_AI_PREDICTION_READY = 20,
   EVENT_AI_TRAIN_STEP       = 21,
   // Signal-specific
   EVENT_SIGNAL_GENERATED    = 30,
   // Pipeline & Execution
   EVENT_ID_PIPELINE_STAGE_COMPLETE = 40,
   EVENT_ID_ORDER_EXECUTED          = 41,
   EVENT_ID_ORDER_REQUEST           = 42,
   EVENT_ID_LATENCY_SIMULATION      = 43,
   EVENT_ID_REQUOTE_SIMULATED       = 44,
   // Adaptive Parameters
   EVENT_ID_ADAPTIVE_UPDATE         = 45,
   // Phase 7: Self-Healing
   EVENT_ID_SYSTEM_RECOVER          = 46,
   EVENT_ID_SYSTEM_HALT             = 47,
   EVENT_ID_HEALTH_CHECK            = 48,
   EVENT_ID_SNAPSHOT_SAVE           = 49,
   EVENT_ID_SNAPSHOT_LOAD           = 50,
   // Deferred / async
   EVENT_ID_DEFERRED         = 99
  };

//+------------------------------------------------------------------+
//| PASREvent — lightweight event struct (no heap alloc)             |
//|                                                                  |
//| S8-005 FIX: Removed non-existent data_i[] integer array.        |
//|   OnTimer() was writing evHealth.data_i[0] = m_health->Status() |
//|   which caused compile error — field does not exist.            |
//|   Replacement: cast to double and store in data1:               |
//|     evHealth.data1 = (double)m_health->Status();                |
//|                                                                  |
//|   ticket  — position/deal ticket from OnTradeTransaction        |
//|   profit  — deal profit, populated on DEAL_ENTRY_OUT            |
//+------------------------------------------------------------------+
struct PASREvent
  {
   ENUM_EVENT_ID     id;
   int               priority;   // lower = higher priority
   datetime          timestamp;
   double            data1;      // generic payload slot 1 (int cast to double ok)
   double            data2;      // generic payload slot 2
   string            tag;
   ulong             ticket;     // position / deal ticket
   double            profit;     // deal profit (DEAL_ENTRY_OUT)

   PASREvent() : id(EVENT_ID_NONE), priority(99), timestamp(0),
                 data1(0), data2(0), tag(""),
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
      ticket    = 0;
      profit    = 0.0;
     }
  };

#endif // CORE_EVENTS_MQH
