//+------------------------------------------------------------------+
//| Infra/SanityManager.mqh — v2.02                                  |
//| Runtime tick sanity and circuit breaker                          |
//+------------------------------------------------------------------+
#property strict
#ifndef __INFRA_SANITY_MANAGER_MQH__
#define __INFRA_SANITY_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "../Core/EventBus.mqh"
#include "../Core/Events.mqh"
#include "../Core/Globals.mqh"

enum ENUM_CIRCUIT_STATE
  {
   CIRCUIT_CLOSED,
   CIRCUIT_OPEN,
   CIRCUIT_HALF_OPEN
  };

struct SSanityConfig
  {
   int      max_stale_sec;
   int      max_spread_points;
   double   max_price_gap_pct;
   int      trip_threshold;
   int      reset_timeout_sec;
  };

class CSanityManager : public IManager
  {
private:
   SSanityConfig      m_config;
   ENUM_CIRCUIT_STATE m_state;
   int                m_consecutive_errors;
   datetime           m_last_tick_time;
   datetime           m_trip_time;
   datetime           m_last_report_time;
   string             m_last_report_key;
   int                m_log_throttle_sec;
   double             m_last_bid;

public:
   CSanityManager() : IManager()
     {
      m_state = CIRCUIT_CLOSED;
      m_consecutive_errors = 0;
      m_last_tick_time = 0;
      m_trip_time = 0;
      m_last_report_time = 0;
      m_last_report_key = "";
      m_log_throttle_sec = 300;
      m_last_bid = 0.0;
      m_config.max_stale_sec = 30;
      m_config.max_spread_points = 20;
      m_config.max_price_gap_pct = 0.5;
      m_config.trip_threshold = 3;
      m_config.reset_timeout_sec = 60;
     }

   virtual string HandlerName() const override { return "SanityManager"; }

   virtual void DeclareEvents() override
     { AddEvent(EVENT_ID_SYSTEM_INFO); }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      double max_spread_points = PipToPoints(m_cfg.Market.SpreadFilterPips);
      if(max_spread_points > 0.0)
         m_config.max_spread_points = (int)MathRound(max_spread_points);

      PASRLogInfo("SANITY", StringFormat("v2.02 — trip=%d reset=%ds stale=%ds spread=%dpts",
                              m_config.trip_threshold,
                              m_config.reset_timeout_sec,
                              m_config.max_stale_sec,
                              m_config.max_spread_points));
      return true;
     }

   virtual void OnEvent(const PASREvent &event) override
     {
      if(event.id == EVENT_ID_SYSTEM_INFO && StringFind(event.comment, "CIRCUIT_RESET") >= 0)
        {
         ResetCircuit();
         PASRLogInfo("SANITY", "External circuit reset received.");
        }
     }

   bool Configure(SSanityConfig &cfg)
     { m_config = cfg; return true; }

   bool ValidateTick(MqlTick &tick)
     {
      if(m_state == CIRCUIT_OPEN)
        {
         if(!TryResetBreaker()) return false;
        }

      bool is_valid = true;
      string reason = "";

      if(!CheckFreshness(tick.time))
        { reason = "STALE_DATA"; is_valid = false; }

      if(is_valid && !CheckSpread(tick.ask, tick.bid))
        { reason = "WIDE_SPREAD"; is_valid = false; }

      if(is_valid && !CheckPriceGap(tick.bid))
        { reason = "PRICE_GAP"; is_valid = false; }

      if(is_valid) { OnSuccess(); return true; }
      OnFailure(reason);
      return false;
     }

   ENUM_CIRCUIT_STATE GetState() const { return m_state; }
   bool IsTradingAllowed() const
     { return (m_state == CIRCUIT_CLOSED || m_state == CIRCUIT_HALF_OPEN); }

   string GetStateString() const
     {
      switch(m_state)
        {
         case CIRCUIT_CLOSED:    return "CLOSED";
         case CIRCUIT_OPEN:      return "OPEN";
         case CIRCUIT_HALF_OPEN: return "HALF-OPEN";
         default:                return "UNKNOWN";
        }
     }

   void ResetCircuit()
     { m_state = CIRCUIT_CLOSED; m_consecutive_errors = 0; }

private:
   bool CheckFreshness(datetime tick_time)
     {
      if(tick_time == 0) return false;
      m_last_tick_time = tick_time;
      datetime elapsed = TimeCurrent() - tick_time;
      if(elapsed > m_config.max_stale_sec)
        {
         PASRLogWarn("SANITY", StringFormat("Stale tick: %ds old", (int)elapsed));
         return false;
        }
      return true;
     }

   bool CheckSpread(double ask, double bid)
     {
      if(ask <= 0 || bid <= 0 || ask <= bid) return false;
      long spread = (long)((ask - bid) / _Point);
      return (spread <= m_config.max_spread_points);
     }

   double PipToPoints(const double pips) const
     {
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double factor = (digits == 3 || digits == 5) ? 10.0 : 1.0;
      return MathMax(0.0, pips) * factor;
     }

   bool CheckPriceGap(double bid)
     {
      if(m_last_bid == 0.0) { m_last_bid = bid; return true; }
      if(bid <= 0.0) return false;
      double change_pct = MathAbs((bid - m_last_bid) / m_last_bid) * 100.0;
      m_last_bid = bid;
      return (change_pct <= m_config.max_price_gap_pct);
     }

   void OnSuccess()
     {
      m_consecutive_errors = 0;
      if(m_state == CIRCUIT_HALF_OPEN)
        { m_state = CIRCUIT_CLOSED; NotifyStateChange("CLOSED"); }
     }

   void OnFailure(string reason)
     {
      m_consecutive_errors++;
      string msg = StringFormat("reason=%s errors=%d/%d",
                                reason, m_consecutive_errors, m_config.trip_threshold);
      SendEvt(EVENT_ID_SYSTEM_WARNING, msg);
      if(m_consecutive_errors >= m_config.trip_threshold)
         TripBreaker(reason);
     }

   void TripBreaker(string reason)
     {
      if(m_state == CIRCUIT_OPEN) return;
      m_state = CIRCUIT_OPEN;
      m_trip_time = TimeCurrent();
      string msg = StringFormat("[CIRCUIT TRIPPED] %s — pausing %ds",
                                reason, m_config.reset_timeout_sec);
      if(ShouldReport("TRIP:" + reason))
        {
         SendEvt(EVENT_ID_SYSTEM_CRITICAL, msg);
         PASRLogError("SANITY", msg);
        }
     }

   bool TryResetBreaker()
     {
      if(m_state != CIRCUIT_OPEN) return true;
      if(TimeCurrent() - m_trip_time >= m_config.reset_timeout_sec)
        { m_state = CIRCUIT_HALF_OPEN; NotifyStateChange("HALF-OPEN"); return true; }
      return false;
     }

   void NotifyStateChange(string state_name)
     {
      string msg = "Circuit -> " + state_name;
      if(ShouldReport("STATE:" + state_name))
        {
         SendEvt(EVENT_ID_SYSTEM_INFO, msg);
         PASRLogInfo("SANITY", msg);
        }
     }

   bool ShouldReport(const string key)
     {
      datetime now = TimeCurrent();
      if(key != m_last_report_key ||
         m_last_report_time == 0 ||
         now - m_last_report_time >= m_log_throttle_sec)
        {
         m_last_report_key = key;
         m_last_report_time = now;
         return true;
        }
      return false;
     }

   void SendEvt(ENUM_EVENT_ID id, string msg)
     {
      if(m_bus == NULL) return;
      PASREvent evt;
      evt.id = id;
      evt.priority = 50;
      evt.comment = msg;
      m_bus.Push(evt);
     }
  };

#endif // __INFRA_SANITY_MANAGER_MQH__
