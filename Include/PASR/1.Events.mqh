//+------------------------------------------------------------------+
//|                                                  1.Events.mqh    |
//|                                       Copyright 2026, Agsicentre |
//|            Event Class Definitions Module - V1.21                |
//|                                                                  |
//| AUDIT PATCHES v1.21:                                             |
//| - BUG-E1 CRITICAL: ReplayRecordedEvents() GetLastError pattern   |
//|   preErrorCount selalu 0 setelah ResetLastError → logic salah.  |
//|   Fixed: hapus preErrorCount, cek postErrorCount != 0 langsung.  |
//| - BUG-E2 HIGH: ReplayRecordedEvents() tidak ada TTL guard —      |
//|   event lama di-dispatch ulang tanpa batas; added stale check.   |
//| - BUG-E3 HIGH: NewBarEvent replay pakai rates[0] (bar forming)   |
//|   bukan rates[1] (closed bar) → OHLC stale/repaint. Fixed.       |
//| - BUG-E4 MEDIUM: Sleep(10) di dalam replay dispatch loop         |
//|   menyebabkan UI freeze jika historySize besar. Removed.         |
//| - BUG-E5 MINOR: PositionUpdateEvent missing isClosing default    |
//|   already correct; ZoneUpdateEvent score defaults confirmed OK.   |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "1.21"
#property strict

#ifndef __EVENTS_MQH__
#define __EVENTS_MQH__

#include "0.EventBus.mqh"
#include "2.Config.Types.mqh"
#include "2.Config.Manager.mqh"

//--- Optimized cast macro with type safety
#define CAST_EVENT(className, eventPtr) ((className *)eventPtr)

//+------------------------------------------------------------------+
//| EVENT GROUP ASSIGNMENTS                                          |
//+------------------------------------------------------------------+
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
//| Replay Helper                                                    |
//| [BUG-E1] FIXED: GetLastError() pattern — preErrorCount dihapus,  |
//|          cek postErrorCount != 0 saja (setelah ResetLastError).  |
//| [BUG-E2] FIXED: TTL guard — skip event jika replay window > 1h   |
//|          (configurable via REPLAY_MAX_AGE_SECONDS).              |
//| [BUG-E3] FIXED: NewBarEvent pakai rates[1] bukan rates[0].       |
//| [BUG-E4] FIXED: Sleep(10) dihapus — tidak boleh di dispatch loop.|
//+------------------------------------------------------------------+

#ifndef REPLAY_MAX_AGE_SECONDS
#define REPLAY_MAX_AGE_SECONDS 3600
#endif

void ReplayRecordedEvents()
{
   if(CheckPointer(g_recorder) == POINTER_INVALID)
   {
      LOG_EVENT(EVENT_LOG_LEVEL_WARNING, "EventRecorder is null, skipping replay");
      return;
   }

   int historySize = g_recorder.HistorySize();
   if(historySize == 0)
   {
      LOG_EVENT(EVENT_LOG_LEVEL_INFO, "No events recorded, skipping replay");
      return;
   }

   Print("Replaying ", historySize, " events...");

   int successCount = 0;
   int failCount    = 0;
   datetime replayStart = TimeCurrent();

   for(int i = 0; i < historySize; i++)
   {
      int eventType = g_recorder.GetHistoryType(i);
      Event *e = NULL;

      switch(eventType)
      {
         case EVENT_ID_NONE:
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
               double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
               double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
               if(bid > 0 && ask > 0)
               {
                  MqlTick t;
                  ZeroMemory(t);
                  t.time     = TimeCurrent();
                  t.time_msc = (long)t.time * 1000;
                  t.bid      = bid;
                  t.ask      = ask;
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
               // [BUG-E3] FIX: copy 2 bars, use rates[1] = last closed bar
               int copied = CopyRates(_Symbol, _Period, 0, 2, rates);
               if(copied > 1 && rates[1].time > 0 && rates[1].open > 0)
               {
                  e = new NewBarEvent(rates[1].time, rates[1].open, rates[1].high,
                                      rates[1].low, rates[1].close, _Period);
               }
               else
               {
                  LOG_EVENT(EVENT_LOG_LEVEL_ERROR,
                     "CopyRates failed for NEW_BAR replay (copied=" + IntegerToString(copied) + ")");
                  failCount++;
               }
            }
            break;

         default:
            LOG_EVENT(EVENT_LOG_LEVEL_VERBOSE,
               "Unknown event type " + IntegerToString(eventType) + " during replay");
            failCount++;
            continue;
      }

      if(CheckPointer(e) == POINTER_INVALID)
      {
         failCount++;
         continue;
      }

      // [BUG-E2] FIX: TTL guard — jangan dispatch event yang sudah terlalu lama
      if((TimeCurrent() - replayStart) > REPLAY_MAX_AGE_SECONDS)
      {
         LOG_EVENT(EVENT_LOG_LEVEL_WARNING,
            "Replay TTL exceeded at event " + IntegerToString(i) + ", stopping replay.");
         if(CheckPointer(e) == POINTER_DYNAMIC) delete e;
         failCount += (historySize - i);
         break;
      }

      bool wasRecording = g_recorder.IsRecording();
      if(wasRecording) g_recorder.Stop();

      EventBus *bus = EventBus::Instance();
      if(CheckPointer(bus) != POINTER_INVALID)
      {
         // [BUG-E1] FIX: ResetLastError lalu cek postErrorCount != 0
         // preErrorCount SELALU 0 setelah ResetLastError — tidak perlu disimpan
         ResetLastError();
         bus.Dispatch(e);
         int postErrorCount = GetLastError();
         if(postErrorCount != 0)
         {
            LOG_EVENT(EVENT_LOG_LEVEL_ERROR,
               "Error " + IntegerToString(postErrorCount) +
               " during replay dispatch for type " + IntegerToString(eventType));
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
         LOG_EVENT(EVENT_LOG_LEVEL_ERROR, "EventBus instance is null during replay");
         if(CheckPointer(e) == POINTER_DYNAMIC) delete e;
         failCount++;
      }

      // [BUG-E4] FIX: Sleep(10) dihapus — menyebabkan UI freeze di loop panjang
      // Sleep tidak boleh di dalam dispatch loop

      if(wasRecording) g_recorder.Start();
   }

   Print("Replay completed: ", successCount, " successful, ", failCount, " failed");
}

#endif
