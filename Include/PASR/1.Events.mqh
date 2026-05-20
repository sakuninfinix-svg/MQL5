//+------------------------------------------------------------------+
//|                                                  1.Events.mqh    |
//|                                       Copyright 2026, Agsicentre |
//|            Event Class Definitions Module - V2.00                |
//|                                                                  |
//| REFACTORING v2.00 IMPROVEMENTS:                                  |
//| - Reduced coupling: Removed direct Config.Manager.mqh include    |
//| - Performance: Optimized ReplayRecordedEvents with early-exit    |
//| - Safety: Enhanced null checks and memory management             |
//| - Code Quality: Consistent formatting, better comments           |
//| - Maintainability: Separated concerns, reduced function size     |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "2.00"
#property strict

#ifndef __EVENTS_MQH__
#define __EVENTS_MQH__

#include "0.EventBus.mqh"
#include "2.Config.Types.mqh"
// Forward declaration to reduce coupling - Config.Manager.mqh not needed directly
// class ConfigManager; // Uncomment if ConfigManager is used in this file

//--- Type-safe cast macro with null checking
#define CAST_EVENT_SAFE(className, eventPtr) \
   ((CheckPointer(eventPtr) == POINTER_DYNAMIC) ? ((className *)eventPtr) : NULL)

//--- Event group aliases for readability
#define EVENT_GROUP_MARKET_EVENTS (EVENT_GROUP_MARKET)
#define EVENT_GROUP_SIGNAL_EVENTS (EVENT_GROUP_SIGNAL)
#define EVENT_GROUP_ORDER_EVENTS  (EVENT_GROUP_ORDER)
#define EVENT_GROUP_SYSTEM_EVENTS (EVENT_GROUP_SYSTEM)

//+------------------------------------------------------------------+
//| PRICE EVENTS                                                     |
//+------------------------------------------------------------------+
class PriceUpdateEvent : public Event
{
public:
   MqlTick tick;

   PriceUpdateEvent(const MqlTick &t)
      : Event(EVENT_ID_PRICE_UPDATE, EVENT_GROUP_MARKET, "PriceUpdateEvent")
   {
      tick = t;
   }
   virtual int ID() const override { return EVENT_ID_PRICE_UPDATE; }
};

class NewBarEvent : public Event
{
public:
   datetime barOpenTime;
   double open, high, low, close;
   int period;

   NewBarEvent(datetime time, double o, double h, double l, double c, int tf)
       : Event(EVENT_ID_NEW_BAR, EVENT_GROUP_MARKET, "NewBarEvent"),
         barOpenTime(time), open(o), high(h), low(l), close(c), period(tf) {}

   virtual int ID() const override { return EVENT_ID_NEW_BAR; }
};

//+------------------------------------------------------------------+
//| MARKET STATE EVENTS                                              |
//+------------------------------------------------------------------+
class SessionChangeEvent : public Event
{
public:
   bool sessionActive;
   string sessionName;

   SessionChangeEvent(bool active, const string name)
       : Event(EVENT_ID_SESSION_CHANGE, EVENT_GROUP_SYSTEM, "SessionChangeEvent"),
         sessionActive(active), sessionName(name) {}

   virtual int ID() const override { return EVENT_ID_SESSION_CHANGE; }
};

class NewsAlertEvent : public Event
{
public:
   string newsTitle;
   datetime eventTime;
   int impact;

   NewsAlertEvent(const string title, datetime time, int lvl)
       : Event(EVENT_ID_NEWS_ALERT, EVENT_GROUP_SYSTEM, "NewsAlertEvent"),
         newsTitle(title), eventTime(time), impact(lvl) {}

   virtual int ID() const override { return EVENT_ID_NEWS_ALERT; }
};

class ZoneUpdateEvent : public Event
{
public:
   double support, resistance;
   double htfSupport, htfResistance;
   bool isSupBroken, isResBroken;
   double supBufferMult, resBufferMult;
   int supHtfAlign, resHtfAlign;
   int supStrength, resStrength;
   double atrPoints;
   double supScore, resScore;

   ZoneUpdateEvent(double sup, double res, double htfSup, double htfRes,
                   bool supBroken, bool resBroken, double supMult, double resMult,
                   int supAlign, int resAlign, int supStr, int resStr, double atr,
                   double supSc = 50.0, double resSc = 50.0)
       : Event(EVENT_ID_ZONE_UPDATE, EVENT_GROUP_SIGNAL, "ZoneUpdateEvent"),
         support(sup), resistance(res), htfSupport(htfSup), htfResistance(htfRes),
         isSupBroken(supBroken), isResBroken(resBroken), supBufferMult(supMult), resBufferMult(resMult),
         supHtfAlign(supAlign), resHtfAlign(resAlign), supStrength(supStr), resStrength(resStr),
         atrPoints(atr), supScore(supSc), resScore(resSc) {}

   virtual int ID() const override { return EVENT_ID_ZONE_UPDATE; }
};

class SignalGeneratedEvent : public Event
{
public:
   SignalDecision signal;
   double atrPoints;
   double support, resistance;

   SignalGeneratedEvent(const SignalDecision &sig, double atr, double sup, double res)
       : Event(EVENT_ID_SIGNAL_GENERATED, EVENT_GROUP_SIGNAL, "SignalGeneratedEvent"),
         signal(sig), atrPoints(atr), support(sup), resistance(res) {}

   virtual int ID() const override { return EVENT_ID_SIGNAL_GENERATED; }
};

class RecoveryOpportunityEvent : public Event
{
public:
   ulong originalTicket;
   double slHitPrice;
   int direction;
   double atrPoints;
   double originalLot;

   RecoveryOpportunityEvent(ulong ticket, double slPrice, int dir, double atr, double lot)
       : Event(EVENT_ID_RECOVERY_OPPORTUNITY, EVENT_GROUP_ORDER, "RecoveryOpportunityEvent"),
         originalTicket(ticket), slHitPrice(slPrice), direction(dir), atrPoints(atr), originalLot(lot) {}

   virtual int ID() const override { return EVENT_ID_RECOVERY_OPPORTUNITY; }
};

class RecoverySignalEvent : public Event
{
public:
   ulong originalTicket;
   SignalDecision signal;
   double atrPoints;
   double support, resistance;

   RecoverySignalEvent(ulong originalT, const SignalDecision &sig, double atr, double sup, double res)
       : Event(EVENT_ID_RECOVERY_SIGNAL, EVENT_GROUP_ORDER, "RecoverySignalEvent"),
         originalTicket(originalT), signal(sig), atrPoints(atr), support(sup), resistance(res) {}

   virtual int ID() const override { return EVENT_ID_RECOVERY_SIGNAL; }
};

class ConfigReloadEvent : public Event
{
public:
   ConfigReloadEvent()
      : Event(EVENT_ID_CONFIG_RELOAD, EVENT_GROUP_SYSTEM, "ConfigReloadEvent") {}
   virtual int ID() const override { return EVENT_ID_CONFIG_RELOAD; }
};

class OrderExecutionEvent : public Event
{
public:
   bool success;
   ulong ticket;
   ENUM_ORDER_TYPE orderType;
   double entryPrice, sl, tp, volume;
   string rejectionReason;
   string orderComment;

   OrderExecutionEvent(bool ok, ulong t, ENUM_ORDER_TYPE type,
                       double entry, double stopLoss, double takeProfit, double vol,
                       const string reason = "", const string comment = "")
       : Event(EVENT_ID_ORDER_EXECUTION, EVENT_GROUP_ORDER, "OrderExecutionEvent"),
         success(ok), ticket(t), orderType(type),
         entryPrice(entry), sl(stopLoss), tp(takeProfit), volume(vol),
         rejectionReason(reason), orderComment(comment) {}

   virtual int ID() const override { return EVENT_ID_ORDER_EXECUTION; }
};

class PositionUpdateEvent : public Event
{
public:
   ulong ticket;
   double currentPrice;
   double unrealizedPnL;
   bool isClosing;

   PositionUpdateEvent(ulong t, double price, double pnl, bool closing = false)
       : Event(EVENT_ID_POSITION_UPDATE, EVENT_GROUP_ORDER, "PositionUpdateEvent"),
         ticket(t), currentPrice(price),
         unrealizedPnL(pnl), isClosing(closing) {}

   virtual int ID() const override { return EVENT_ID_POSITION_UPDATE; }
};

class PauseToggleEvent : public Event
{
public:
   bool isBuy;
   bool newState;

   PauseToggleEvent(bool buy, bool state)
      : Event(EVENT_ID_PAUSE_TOGGLE, EVENT_GROUP_SYSTEM, "PauseToggleEvent"),
        isBuy(buy), newState(state) {}
   virtual int ID() const override { return EVENT_ID_PAUSE_TOGGLE; }
};

class HeartbeatEvent : public Event
{
public:
   int intervalSeconds;

   HeartbeatEvent(int secs = 5)
      : Event(EVENT_ID_HEARTBEAT, EVENT_GROUP_SYSTEM, "HeartbeatEvent"),
        intervalSeconds(secs) {}
   virtual int ID() const override { return EVENT_ID_HEARTBEAT; }
};

class EmergencyStopEvent : public Event
{
public:
   string reason;

   EmergencyStopEvent(const string r = "Manual Trigger")
      : Event(EVENT_ID_EMERGENCY_STOP, EVENT_GROUP_SYSTEM, "EmergencyStopEvent"),
        reason(r) {}
   virtual int ID() const override { return EVENT_ID_EMERGENCY_STOP; }
};

class MarketGateEvent : public Event
{
public:
   bool gateOpen;
   bool entryAllowed;
   double spread;
   double atrPoints;

   MarketGateEvent(bool open, double spreadValue, double atrValue, bool allowed)
       : Event(EVENT_ID_MARKET_GATE, EVENT_GROUP_SYSTEM, "MarketGateEvent"),
         gateOpen(open), entryAllowed(allowed), spread(spreadValue), atrPoints(atrValue) {}

   virtual int ID() const override { return EVENT_ID_MARKET_GATE; }
};

//+------------------------------------------------------------------+
//| Replay Helper - Optimized                                        |
//| v2.00 Improvements:                                              |
//| - Early-exit pattern for better performance                      |
//| - Enhanced null checking and memory safety                       |
//| - Better error handling with detailed logging                    |
//| - Removed unnecessary includes                                   |
//+------------------------------------------------------------------+

#ifndef REPLAY_MAX_AGE_SECONDS
#define REPLAY_MAX_AGE_SECONDS 3600
#endif

//--- Helper function to create event from type
static Event* CreateEventFromType(int eventType)
{
   Event* event = NULL;
   
   switch(eventType)
   {
      case EVENT_ID_HEARTBEAT:
         event = new HeartbeatEvent(5);
         break;
         
      case EVENT_ID_EMERGENCY_STOP:
         event = new EmergencyStopEvent("Replay");
         break;
         
      case EVENT_ID_PRICE_UPDATE:
      {
         const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         
         if(bid <= 0 || ask <= 0)
            return NULL;
            
         MqlTick tick;
         ZeroMemory(tick);
         tick.time     = TimeCurrent();
         tick.time_msc = (long)tick.time * 1000;
         tick.bid      = bid;
         tick.ask      = ask;
         
         event = new PriceUpdateEvent(tick);
         break;
      }
      
      case EVENT_ID_NEW_BAR:
      {
         MqlRates rates[];
         ArraySetAsSeries(rates, true);
         
         // Use rates[1] = last closed bar (not forming bar rates[0])
         if(CopyRates(_Symbol, _Period, 0, 2, rates) < 2)
            return NULL;
            
         if(rates[1].time <= 0 || rates[1].open <= 0)
            return NULL;
            
         event = new NewBarEvent(
            rates[1].time, 
            rates[1].open, 
            rates[1].high,
            rates[1].low, 
            rates[1].close, 
            _Period
         );
         break;
      }
      
      default:
         return NULL;
   }
   
   return event;
}

//--- Main replay function
void ReplayRecordedEvents()
{
   // Early exit: Check recorder validity
   if(CheckPointer(g_recorder) == POINTER_INVALID)
   {
      LOG_EVENT(EVENT_LOG_LEVEL_WARNING, "EventRecorder is null, skipping replay");
      return;
   }

   // Early exit: No history to replay
   const int historySize = g_recorder.HistorySize();
   if(historySize == 0)
   {
      LOG_EVENT(EVENT_LOG_LEVEL_INFO, "No events recorded, skipping replay");
      return;
   }

   Print("[Replay] Starting replay of ", historySize, " events...");

   int successCount = 0;
   int failCount    = 0;
   const datetime replayStart = TimeCurrent();
   EventBus *bus = EventBus::Instance();

   for(int i = 0; i < historySize; i++)
   {
      // TTL guard: Stop if replay takes too long
      if((TimeCurrent() - replayStart) > REPLAY_MAX_AGE_SECONDS)
      {
         LOG_EVENT(EVENT_LOG_LEVEL_WARNING,
            "[Replay] TTL exceeded at event ", i, ", stopping replay.");
         failCount += (historySize - i);
         break;
      }

      // Get event type and create event
      const int eventType = g_recorder.GetHistoryType(i);
      Event* e = CreateEventFromType(eventType);

      // Skip if event creation failed
      if(CheckPointer(e) == POINTER_INVALID)
      {
         LOG_EVENT(EVENT_LOG_LEVEL_VERBOSE,
            "[Replay] Failed to create event type ", eventType);
         failCount++;
         continue;
      }

      // Temporarily stop recording during replay
      const bool wasRecording = g_recorder.IsRecording();
      if(wasRecording) 
         g_recorder.Stop();

      // Dispatch event
      if(CheckPointer(bus) != POINTER_INVALID)
      {
         ResetLastError();
         bus.Dispatch(e);
         
         const int errorCode = GetLastError();
         if(errorCode != 0)
         {
            LOG_EVENT(EVENT_LOG_LEVEL_ERROR,
               "[Replay] Error ", errorCode,
               " dispatching event type ", eventType);
            ResetLastError();
            failCount++;
         }
         else
         {
            successCount++;
         }
      }
      else
      {
         LOG_EVENT(EVENT_LOG_LEVEL_ERROR, "[Replay] EventBus instance is null");
         failCount++;
      }

      // Cleanup event object
      if(CheckPointer(e) == POINTER_DYNAMIC)
         delete e;

      // Resume recording if it was active
      if(wasRecording) 
         g_recorder.Start();
   }

   Print("[Replay] Completed: ", successCount, " successful, ", failCount, " failed");
}

#endif
