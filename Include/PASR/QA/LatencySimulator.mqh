//+------------------------------------------------------------------+
//| QA/LatencySimulator.mqh                                          |
//| Backtest-only latency and requote simulator.                     |
//+------------------------------------------------------------------+
#property strict
#ifndef __QA_LATENCY_SIMULATOR_MQH__
#define __QA_LATENCY_SIMULATOR_MQH__

#include "../Core/IManager.mqh"

#define DEFAULT_LATENCY_MS        50
#define DEFAULT_JITTER_MS         20
#define DEFAULT_REQUOTE_PROB      0.05

class CLatencySimulator : public IManager
  {
private:
   bool     m_is_active;
   double   m_base_latency_ms;
   double   m_jitter_ms;
   double   m_requote_probability;
   ulong    m_total_delays;
   double   m_total_delay_added;
   ulong    m_requotes_simulated;
   datetime m_last_simulation_time;

   double RandomNormal(double mean, double stddev)
     {
      double u1 = (double)MathRand() / 32767.0;
      double u2 = (double)MathRand() / 32767.0;
      if(u1 < 1e-10) u1 = 1e-10;
      double z0 = MathSqrt(-2.0 * MathLog(u1)) * MathCos(2.0 * M_PI * u2);
      return mean + z0 * stddev;
     }

   void SimulateRequote()
     {
      m_requotes_simulated++;
      PASREvent ev;
      ev.id = EVENT_ID_SYSTEM_WARNING;
      ev.priority = 70;
      ev.comment = "REQUOTE_SIM";
      ev.data1 = (double)m_requotes_simulated;
      QueueEvent(ev);
      if(m_debugMode) Print("[LatencySim] REQUOTE SIMULATED (#", m_requotes_simulated, ")");
     }

public:
   CLatencySimulator()
      : IManager(), m_is_active(false),
        m_base_latency_ms(DEFAULT_LATENCY_MS),
        m_jitter_ms(DEFAULT_JITTER_MS),
        m_requote_probability(DEFAULT_REQUOTE_PROB),
        m_total_delays(0), m_total_delay_added(0.0),
        m_requotes_simulated(0), m_last_simulation_time(0)
     {}

   ~CLatencySimulator()
     {
      PrintStats();
     }

   virtual string HandlerName() const override { return "LatencySimulator"; }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_ORDER_REQUEST);
     }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      if(!MQLInfoInteger(MQL_TESTER))
        {
         m_is_active = false;
         if(m_debugMode) Print("[LatencySim] Disabled - not in tester mode");
         return true;
        }
      m_is_active = true;
      Print("[LatencySim] ENABLED - Base: ", m_base_latency_ms, "ms, Jitter: ±", m_jitter_ms, "ms");
      return true;
     }

   virtual void Deinit() override
     {
      PrintStats();
      IManager::Deinit();
     }

   virtual void OnEvent(const PASREvent &event) override
     {
      if(!m_is_active || event.id != EVENT_ID_ORDER_REQUEST) return;
      double simulated_delay = CalculateDelay();
      ApplyDelay(simulated_delay);
      m_total_delays++;
      m_total_delay_added += simulated_delay;
      if(ShouldSimulateRequote()) SimulateRequote();
     }

   double CalculateDelay()
     {
      double jitter = MathMax(0.0, RandomNormal(0.0, m_jitter_ms));
      return m_base_latency_ms + jitter;
     }

   void ApplyDelay(double delay_ms)
     {
      if(!m_is_active || !MQLInfoInteger(MQL_TESTER)) return;
      m_last_simulation_time = TimeCurrent();
      if(m_debugMode) Print("[LatencySim] Applied delay: ", DoubleToString(delay_ms, 2), "ms");
     }

   bool ShouldSimulateRequote() const
     {
      return m_is_active && ((double)MathRand() / 32767.0 < m_requote_probability);
     }

   void PrintStats()
     {
      if(!m_is_active || m_total_delays == 0) return;
      double avg_delay = m_total_delay_added / (double)m_total_delays;
      Print("========== LATENCY SIMULATION STATS ==========");
      Print("Total Delays Applied: ", m_total_delays);
      Print("Average Delay: ", DoubleToString(avg_delay, 2), "ms");
      Print("Total Requotes Simulated: ", m_requotes_simulated);
      Print("Requote Rate: ", DoubleToString(100.0 * (double)m_requotes_simulated / (double)m_total_delays, 2), "%");
      Print("================================================");
     }
  };

#endif // __QA_LATENCY_SIMULATOR_MQH__
