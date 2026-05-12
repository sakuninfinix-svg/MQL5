//+------------------------------------------------------------------+
//|                                                  1.Events.mqh    |
//|                                       Copyright 2026, Agsicentre |
//|               OPTIMIZED: Lightweight Event Classes               |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "1.10"
#property strict

#ifndef __EVENTS_MQH__
#define __EVENTS_MQH__

#include "0.EventBus.mqh"
#include "2.Config.mqh"

//--- Optimized cast macro with type safety
#define CAST_EVENT(className, eventPtr) ((className *)eventPtr)

//+------------------------------------------------------------------+
//| PRICE EVENTS - OPTIMIZED                                         |
//+------------------------------------------------------------------+
class PriceUpdateEvent : public Event
{
public:
   MqlTick tick;

   PriceUpdateEvent(const MqlTick &t) : Event(1) { tick = t; }
   virtual int ID() const override { return EVENT_ID_PRICE_UPDATE; }
   virtual string Type() const override { return "PriceUpdate"; }
};

class NewBarEvent : public Event
{
public:
   datetime barOpenTime;
   double open, high, low, close;
   int period;

   NewBarEvent(datetime time, double o, double h, double l, double c, int tf)
       : Event(2), barOpenTime(time), open(o), high(h), low(l), close(c), period(tf) {}

   virtual int ID() const override { return EVENT_ID_NEW_BAR; }
   virtual string Type() const override { return "NewBar"; }
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
       : Event(3), sessionActive(active), sessionName(name) {}

   virtual int ID() const override { return EVENT_ID_SESSION_CHANGE; }
   virtual string Type() const override { return "SessionChange"; }
};

class NewsAlertEvent : public Event
{
public:
   string newsTitle;
   datetime eventTime;
   int impact;

   NewsAlertEvent(const string title, datetime time, int lvl)
       : Event(4), newsTitle(title), eventTime(time), impact(lvl) {}

   virtual int ID() const override { return EVENT_ID_NEWS_ALERT; }
   virtual string Type() const override { return "NewsAlert"; }
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

   ZoneUpdateEvent(double sup, double res, double htfSup, double htfRes,
                   bool supBroken, bool resBroken, double supMult, double resMult,
                   int supAlign, int resAlign, int supStr, int resStr, double atr)
       : Event(5), support(sup), resistance(res), htfSupport(htfSup), htfResistance(htfRes),
         isSupBroken(supBroken), isResBroken(resBroken), supBufferMult(supMult), resBufferMult(resMult),
         supHtfAlign(supAlign), resHtfAlign(resAlign), supStrength(supStr), resStrength(resStr), atrPoints(atr) {}

   virtual int ID() const override { return EVENT_ID_ZONE_UPDATE; }
   virtual string Type() const override { return "ZoneUpdate"; }
};

class SignalGeneratedEvent : public Event
{
public:
   SignalDecision signal;
   double atrPoints;
   double support, resistance;

   SignalGeneratedEvent(const SignalDecision &sig, double atr, double sup, double res)
       : Event(6), signal(sig), atrPoints(atr), support(sup), resistance(res) {}

   virtual int ID() const override { return EVENT_ID_SIGNAL_GENERATED; }
   virtual string Type() const override { return "SignalGenerated"; }
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
       : Event(7), originalTicket(ticket), slHitPrice(slPrice), direction(dir), atrPoints(atr), originalLot(lot) {}

   virtual int ID() const override { return EVENT_ID_RECOVERY_OPPORTUNITY; }
   virtual string Type() const override { return "RecoveryOpportunity"; }
};

class RecoverySignalEvent : public Event
{
public:
   ulong originalTicket;
   SignalDecision signal;
   double atrPoints;
   double support, resistance;

   RecoverySignalEvent(ulong originalT, const SignalDecision &sig, double atr, double sup, double res)
       : Event(8), originalTicket(originalT), signal(sig), atrPoints(atr), support(sup), resistance(res) {}

   virtual int ID() const override { return EVENT_ID_RECOVERY_SIGNAL; }
   virtual string Type() const override { return "RecoverySignal"; }
};

class ConfigReloadEvent : public Event
{
public:
   ConfigReloadEvent() : Event(9) {}
   virtual int ID() const override { return EVENT_ID_CONFIG_RELOAD; }
   virtual string Type() const override { return "ConfigReload"; }
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
       : Event(13), success(ok), ticket(t), orderType(type),
         entryPrice(entry), sl(stopLoss), tp(takeProfit), volume(vol),
         rejectionReason(reason), orderComment(comment) {}

   virtual int ID() const override { return EVENT_ID_ORDER_EXECUTION; }
   virtual string Type() const override { return "OrderExecution"; }
};

class PositionUpdateEvent : public Event
{
public:
   ulong ticket;
   double currentPrice;
   double unrealizedPnL;
   bool isClosing;

   PositionUpdateEvent(ulong t, double price, double pnl, bool closing = false)
       : Event(14), ticket(t), currentPrice(price),
         unrealizedPnL(pnl), isClosing(closing) {}

   virtual int ID() const override { return EVENT_ID_POSITION_UPDATE; }
   virtual string Type() const override { return "PositionUpdate"; }
};

class PauseToggleEvent : public Event
{
public:
   bool isBuy;
   bool newState;
   
   PauseToggleEvent(bool buy, bool state) : Event(15), isBuy(buy), newState(state) {}
   virtual int ID() const override { return EVENT_ID_PAUSE_TOGGLE; }
   virtual string Type() const override { return "PauseToggle"; }
};

//+------------------------------------------------------------------+
//| SYSTEM EVENTS - OPTIMIZED                                        |
//+------------------------------------------------------------------+
class HeartbeatEvent : public Event
{
public:
   int intervalSeconds;

   HeartbeatEvent(int secs = 5) : Event(10), intervalSeconds(secs) {}
   virtual int ID() const override { return EVENT_ID_HEARTBEAT; }
   virtual string Type() const override { return "Heartbeat"; }
};

class EmergencyStopEvent : public Event
{
public:
   string reason;

   EmergencyStopEvent(const string r = "Manual Trigger") : Event(11), reason(r) {}
   virtual int ID() const override { return EVENT_ID_EMERGENCY_STOP; }
   virtual string Type() const override { return "EmergencyStop"; }
};

class MarketGateEvent : public Event
{
public:
   bool gateOpen;
   bool entryAllowed;
   double spread;
   double atrPoints;

   MarketGateEvent(bool open, double spreadValue, double atrValue, bool allowed)
       : Event(12), gateOpen(open), entryAllowed(allowed), spread(spreadValue), atrPoints(atrValue) {}

   virtual int ID() const override { return EVENT_ID_MARKET_GATE; }
   virtual string Type() const override { return "MarketGate"; }
};

//+------------------------------------------------------------------+
//| EVENT UTILITIES                                                  |
//+------------------------------------------------------------------+
//template <typename T>
//void DispatchEvent(T *event)
//{
//   EventBus *bus = EventBus::Instance();
//   if (CheckPointer(bus) != POINTER_INVALID)
//      bus.Dispatch(event);
//   else if (CheckPointer(event) == POINTER_DYNAMIC)
//      delete event;
//}

//+------------------------------------------------------------------+
//| Replay Helper - Converts event IDs back to objects               |
//+------------------------------------------------------------------+
void ReplayRecordedEvents()
{
   if (g_recorder == NULL)
      return;

   Print("Replaying ", g_recorder.HistorySize(), " events...");
   for (int i = 0; i < g_recorder.HistorySize(); i++)
   {
      int eventType = g_recorder.GetHistoryType(i);
      Event *e = NULL;

      // Create minimal events based on type ID only
      // Full data reconstruction not needed for replay testing
      switch(eventType)
      {
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
               e = new PriceUpdateEvent(t);
            }
            break;
         case EVENT_ID_NEW_BAR:
            {
               MqlRates rates[];
               if(CopyRates(_Symbol, _Period, 0, 1, rates) > 0)
               {
                  e = new NewBarEvent(rates[0].time, rates[0].open, rates[0].high, 
                                      rates[0].low, rates[0].close, _Period);
               }
            }
            break;
      }

      if (CheckPointer(e) != POINTER_INVALID)
      {
         bool wasRecording = g_recorder.IsRecording();
         if (wasRecording)
            g_recorder.Stop();

         DispatchEvent(e);

         if (wasRecording)
            g_recorder.Start();
         Sleep(10);
      }
   }
}

#define HANDLE_EVENT(className, eventType)                \
   virtual void HandleEvent(Event *e) override            \
   {                                                      \
      if (e.Type() == eventType)                          \
      {                                                   \
         className *typed = dynamic_cast<className *>(e); \
         if (CheckPointer(typed) != POINTER_INVALID)      \
            On##eventType(typed);                         \
      }                                                   \
   }                                                      \
   virtual void On##eventType(className *e) = 0;

#endif