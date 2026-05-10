//+------------------------------------------------------------------+
//|                                                   Events.mqh     |
//|                                       Copyright 2026, Agsicentre |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"

#ifndef __EVENTS_MQH__
#define __EVENTS_MQH__

#property link "agsicentre.wordpress.com"
#property version "1.00"
#property strict

#include "0.EventBus.mqh"
#include "2.Config.mqh"
#define CAST_EVENT(className, eventPtr) (dynamic_cast<className *>(eventPtr))

//+------------------------------------------------------------------+
//| PRICE EVENTS                                                     |
//+------------------------------------------------------------------+
class PriceUpdateEvent : public Event
{
public:
   MqlTick tick;

   PriceUpdateEvent(const MqlTick &t) : Event("PriceFeed") { tick = t; }
   virtual int ID() const override { return EVENT_ID_PRICE_UPDATE; }
   virtual string Type() const override { return "PriceUpdate"; }

   virtual string Serialize() const override
   {
      return StringFormat("%I64d;%f;%f;%f;%f",
                          tick.time_msc, tick.bid, tick.ask, tick.last, tick.volume);
   }
};

class NewBarEvent : public Event
{
public:
   datetime barOpenTime;
   double open, high, low, close;
   int period;

   NewBarEvent(datetime time, double o, double h, double l, double c, int tf)
       : Event("BarMonitor"), barOpenTime(time), open(o), high(h), low(l), close(c), period(tf) {}

   virtual int ID() const override { return EVENT_ID_NEW_BAR; }
   virtual string Type() const override { return "NewBar"; }
   virtual string Serialize() const override
   {
      return StringFormat("%I64d;%f;%f;%f;%f;%d",
                          (long)barOpenTime, open, high, low, close, period);
   }
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
       : Event("MarketManager"), sessionActive(active), sessionName(name) {}

   virtual int ID() const override { return EVENT_ID_SESSION_CHANGE; }
   virtual string Type() const override { return "SessionChange"; }
};

class NewsAlertEvent : public Event
{
public:
   string newsTitle;
   datetime eventTime;
   int impact; // 1=High, 2=Medium, 3=Low

   NewsAlertEvent(const string title, datetime time, int lvl)
       : Event("NewsFilter"), newsTitle(title), eventTime(time), impact(lvl) {}

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
   int supStrength, resStrength; // NEW: Zone strength for adaptive filtering
   double atrPoints;

   ZoneUpdateEvent(double sup, double res, double htfSup, double htfRes,
                   bool supBroken, bool resBroken, double supMult, double resMult,
                   int supAlign, int resAlign, int supStr, int resStr, double atr)
       : Event("SRManager"), support(sup), resistance(res), htfSupport(htfSup), htfResistance(htfRes),
         isSupBroken(supBroken), isResBroken(resBroken), supBufferMult(supMult), resBufferMult(resMult),
         supHtfAlign(supAlign), resHtfAlign(resAlign), supStrength(supStr), resStrength(resStr), atrPoints(atr) {}

   virtual int ID() const override { return EVENT_ID_ZONE_UPDATE; }
   virtual string Type() const override { return "ZoneUpdate"; }
};

//+------------------------------------------------------------------+
//| TRADING EVENTS                                                   |
//+------------------------------------------------------------------+
class SignalGeneratedEvent : public Event
{
public:
   SignalDecision signal;
   double atrPoints;
   double support, resistance;

   SignalGeneratedEvent(const SignalDecision &sig, double atr, double sup, double res)
       : Event("SignalManager"), signal(sig), atrPoints(atr), support(sup), resistance(res) {}

   virtual int ID() const override { return EVENT_ID_SIGNAL_GENERATED; }
   virtual string Type() const override { return "SignalGenerated"; }
};

// NEW: Recovery Opportunity Event
class RecoveryOpportunityEvent : public Event
{
public:
   ulong originalTicket;
   double slHitPrice;
   int direction;
   double atrPoints;
   double originalLot;

   RecoveryOpportunityEvent(ulong ticket, double slPrice, int dir, double atr, double lot)
       : Event("RecoveryManager"), originalTicket(ticket), slHitPrice(slPrice), direction(dir), atrPoints(atr), originalLot(lot) {}

   virtual int ID() const override { return EVENT_ID_RECOVERY_OPPORTUNITY; }
   virtual string Type() const override { return "RecoveryOpportunity"; }
};

// NEW: Recovery Signal Event
class RecoverySignalEvent : public Event
{
public:
   ulong originalTicket; // Link back to the original trade
   SignalDecision signal;
   double atrPoints;
   double support, resistance;

   RecoverySignalEvent(ulong originalT, const SignalDecision &sig, double atr, double sup, double res)
       : Event("SignalManager"), originalTicket(originalT), signal(sig), atrPoints(atr), support(sup), resistance(res) {}

   virtual int ID() const override { return EVENT_ID_RECOVERY_SIGNAL; }
   virtual string Type() const override { return "RecoverySignal"; }
};

class ConfigReloadEvent : public Event
{
public:
   ConfigReloadEvent() : Event("System") {}
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
       : Event("ExecutionManager"), success(ok), ticket(t), orderType(type),
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
       : Event("RecoveryManager"), ticket(t), currentPrice(price),
         unrealizedPnL(pnl), isClosing(closing) {}

   virtual int ID() const override { return EVENT_ID_POSITION_UPDATE; }
   virtual string Type() const override { return "PositionUpdate"; }
};

class PauseToggleEvent : public Event
{
public:
   bool isBuy;
   bool newState;
   PauseToggleEvent(bool buy, bool state) : Event("Dashboard"), isBuy(buy), newState(state) {}
   virtual int ID() const override { return EVENT_ID_PAUSE_TOGGLE; }
   virtual string Type() const override { return "PauseToggle"; }
};

//+------------------------------------------------------------------+
//| SYSTEM EVENTS                                                    |
//+------------------------------------------------------------------+
class HeartbeatEvent : public Event
{
public:
   int intervalSeconds;

   HeartbeatEvent(int secs = 5) : Event("System"), intervalSeconds(secs) {}
   virtual int ID() const override { return EVENT_ID_HEARTBEAT; }
   virtual string Type() const override { return "Heartbeat"; }

   virtual string Serialize() const override
   {
      return (string)intervalSeconds;
   }
};

class EmergencyStopEvent : public Event
{ // NEW EVENT
public:
   string reason;

   EmergencyStopEvent(const string r = "Manual Trigger") : Event("System"), reason(r) {}
   virtual int ID() const override { return EVENT_ID_EMERGENCY_STOP; }
   virtual string Type() const override { return "EmergencyStop"; }

   virtual string Serialize() const override { return reason; }
};

class MarketGateEvent : public Event
{
public:
   bool gateOpen;
   bool entryAllowed;
   double spread;
   double atrPoints;

   MarketGateEvent(bool open, double spreadValue, double atrValue, bool allowed)
       : Event("MarketManager"), gateOpen(open), entryAllowed(allowed), spread(spreadValue), atrPoints(atrValue) {}

   virtual int ID() const override { return EVENT_ID_MARKET_GATE; }
   virtual string Type() const override { return "MarketGate"; }
};

//+------------------------------------------------------------------+
//| EVENT UTILITIES                                                  |
//+------------------------------------------------------------------+
template <typename T>
void DispatchEvent(T *event)
{
   EventBus *bus = EventBus::Instance();
   if (CheckPointer(bus) != POINTER_INVALID)
      bus.Dispatch(event);
   else if (CheckPointer(event) == POINTER_DYNAMIC)
      delete event;
}

//+------------------------------------------------------------------+
//| Replay Helper - Converts strings back to objects                 |
//+------------------------------------------------------------------+
void ReplayRecordedEvents()
{
   if (g_recorder == NULL)
      return;

   Print("Replaying ", g_recorder.HistorySize(), " events...");
   for (int i = 0; i < g_recorder.HistorySize(); i++)
   {
      string type = g_recorder.GetHistoryType(i);
      string data = g_recorder.GetHistoryData(i);
      Event *e = NULL;

      if (type == "PriceUpdate")
      {
         string parts[];
         if (StringSplit(data, ';', parts) >= 5)
         {
            MqlTick t;
            t.time_msc = StringToInteger(parts[0]);
            t.bid = StringToDouble(parts[1]);
            t.ask = StringToDouble(parts[2]);
            t.last = StringToDouble(parts[3]);
            t.volume = (ulong)StringToDouble(parts[4]);
            e = new PriceUpdateEvent(t);
         }
      }
      else if (type == "NewBar")
      {
         string parts[];
         if (StringSplit(data, ';', parts) >= 6)
         {
            e = new NewBarEvent((datetime)StringToInteger(parts[0]), StringToDouble(parts[1]), StringToDouble(parts[2]),
                                StringToDouble(parts[3]), StringToDouble(parts[4]), (int)StringToInteger(parts[5]));
         }
      }
      else if (type == "Heartbeat")
      {
         e = new HeartbeatEvent((int)StringToInteger(data));
      }
      else if (type == "EmergencyStop")
      { // NEW: Deserialize EmergencyStopEvent
         e = new EmergencyStopEvent(data);
      }

      if (CheckPointer(e) != POINTER_INVALID)
      {
         // Dispatch without re-recording
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