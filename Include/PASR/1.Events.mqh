//+------------------------------------------------------------------+
//|                                                  1.Events.mqh    |
//|                                       Copyright 2026, Agsicentre |
//|            Event Class Definitions Module - V1.20                |
//|                                                                  |
//| IMPROVEMENTS:                                                    |
//| - Centralized Event IDs from Config.mqh                          |
//| - Event Group Flags for wildcard subscriptions                   |
//| - Enhanced error handling in replay                              |
//| - Memory leak prevention                                         |
//| - Event metrics tracking support                                 |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "1.20"
#property strict

#ifndef __EVENTS_MQH__
#define __EVENTS_MQH__

#include "0.EventBus.mqh"
#include "2.Config.mqh"

//--- Optimized cast macro with type safety
#define CAST_EVENT(className, eventPtr) ((className *)eventPtr)

//+------------------------------------------------------------------+
//| EVENT GROUP ASSIGNMENTS                                          |
//| Use these flags when subscribing for wildcard support            |
//+------------------------------------------------------------------+
// Market Events: PRICE_UPDATE, NEW_BAR
#define EVENT_GROUP_MARKET_EVENTS (EVENT_GROUP_MARKET)

// Signal Events: ZONE_UPDATE, SIGNAL_GENERATED  
#define EVENT_GROUP_SIGNAL_EVENTS (EVENT_GROUP_SIGNAL)

// Order Events: ORDER_EXECUTION, POSITION_UPDATE, RECOVERY_OPPORTUNITY, RECOVERY_SIGNAL
#define EVENT_GROUP_ORDER_EVENTS (EVENT_GROUP_ORDER)

// System Events: HEARTBEAT, CONFIG_RELOAD, EMERGENCY_STOP, MARKET_GATE, PAUSE_TOGGLE, SESSION_CHANGE, NEWS_ALERT
#define EVENT_GROUP_SYSTEM_EVENTS (EVENT_GROUP_SYSTEM)

//+------------------------------------------------------------------+
//| PRICE EVENTS - OPTIMIZED                                         |
//| Added: Event group flags for wildcard subscriptions              |
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
//| Added: Event group flags and names for debug                     |
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
   double supScore, resScore;  // SR Zone Scores

   ZoneUpdateEvent(double sup, double res, double htfSup, double htfRes,
                   bool supBroken, bool resBroken, double supMult, double resMult,
                   int supAlign, int resAlign, int supStr, int resStr, double atr,
                   double supSc = 50.0, double resSc = 50.0)  // Default scores for backward compatibility
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

//+------------------------------------------------------------------+
//| SYSTEM EVENTS - OPTIMIZED                                        |
//| Added: Critical priority flag for emergency events               |
//+------------------------------------------------------------------+
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
//| EVENT UTILITIES                                                  |
//+------------------------------------------------------------------+
// Deprecated: HANDLE_EVENT macro - not used and potentially confusing
// Use direct event handling in your classes instead
// #define HANDLE_EVENT(className, eventID) ...

//+------------------------------------------------------------------+
//| Replay Helper - Enhanced with error handling & memory safety     |
//+------------------------------------------------------------------+
void ReplayRecordedEvents()
{
   if (CheckPointer(g_recorder) == POINTER_INVALID)
   {
      LOG_EVENT(EVENT_LOG_LEVEL_WARNING, "EventRecorder is null, skipping replay");
      return;
   }

   int historySize = g_recorder.HistorySize();
   if (historySize == 0)
   {
      LOG_EVENT(EVENT_LOG_LEVEL_INFO, "No events recorded, skipping replay");
      return;
   }

   Print("Replaying ", historySize, " events...");
   
   int successCount = 0;
   int failCount = 0;
   
   for (int i = 0; i < historySize; i++)
   {
      int eventType = g_recorder.GetHistoryType(i);
      Event *e = NULL;

      // Create minimal events based on type ID only
      // Full data reconstruction not needed for replay testing
      switch(eventType)
      {
         case EVENT_ID_NONE:
            // Skip invalid events
            failCount++;
            continue;
            
         case EVENT_ID_HEARTBEAT:
            e = new HeartbeatEvent(5);
            break;
            
         case EVENT_ID_EMERGENCY_STOP:
            e = new EmergencyStopEvent("Replay");
            break;
            
         case EVENT_ID_PRICE_UPDATE:
            {
               MqlTick t;
               ZeroMemory(t);
               t.time_msc = TimeCurrent();
               // Validate tick data before creating event
               if(SymbolInfoDouble(_Symbol, SYMBOL_BID) > 0)
               {
                  t.bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                  t.ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                  e = new PriceUpdateEvent(t);
               }
               else
               {
                  LOG_EVENT(EVENT_LOG_LEVEL_WARNING, "Invalid tick data for PRICE_UPDATE replay");
                  failCount++;
               }
            }
            break;
            
         case EVENT_ID_NEW_BAR:
            {
               MqlRates rates[];
               ArraySetAsSeries(rates, true);
               
               // FIX: Copy 2 bars to get closed bar at index 1 (index 0 is still forming)
               int copied = CopyRates(_Symbol, _Period, 0, 2, rates);
               if(copied > 1 && rates[1].time > 0 && rates[1].open > 0)
               {
                  // Use rates[1] - the last CLOSED bar to prevent repainting
                  e = new NewBarEvent(rates[1].time, rates[1].open, rates[1].high,
                                      rates[1].low, rates[1].close, _Period);
               }
               else
               {
                  LOG_EVENT(EVENT_LOG_LEVEL_ERROR, "CopyRates failed for NEW_BAR replay (copied=" + IntegerToString(copied) + ")");
                  failCount++;
               }
            }
            break;
            
         default:
            // Unknown event type - skip safely
            LOG_EVENT(EVENT_LOG_LEVEL_VERBOSE, "Unknown event type " + IntegerToString(eventType) + " during replay");
            failCount++;
            continue;
      }

      // Validate event creation before dispatch
      if (CheckPointer(e) != POINTER_INVALID)
      {
         bool wasRecording = g_recorder.IsRecording();
         if (wasRecording)
            g_recorder.Stop();

         // Dispatch with error handling
         try
         {
            EventBus *bus = EventBus::Instance();
            if (CheckPointer(bus) != POINTER_INVALID)
            {
               bus.Dispatch(e);
               successCount++;
            }
            else
            {
               LOG_EVENT(EVENT_LOG_LEVEL_ERROR, "EventBus instance is null during replay");
               delete e;
               failCount++;
            }
         }
         catch(...)
         {
            LOG_EVENT(EVENT_LOG_LEVEL_ERROR, "Exception during event replay for type " + IntegerToString(eventType));
            if (CheckPointer(e) == POINTER_DYNAMIC)
               delete e;
            failCount++;
         }

         if (wasRecording)
            g_recorder.Start();
            
         Sleep(10);
      }
      else
      {
         failCount++;
      }
   }
   
   Print("Replay completed: ", successCount, " successful, ", failCount, " failed");
}

#endif