//+------------------------------------------------------------------+
//|                                             LatencySimulator.mqh  |
//|                                  Copyright 2024, PASR Architecture |
//|                                             https://pasr.quant.id |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, PASR Architecture"
#property link      "https://pasr.quant.id"
#property version   "1.00"
#property description "Network Latency & Execution Delay Simulator for Backtesting (Fase 4)"

#include "../Core/EventBus.mqh"
#include "../Core/IManager.mqh"
#include <Math\Stat\Normal.mqh>

//+------------------------------------------------------------------+
//| Configuration Constants                                          |
//+------------------------------------------------------------------+
#define DEFAULT_LATENCY_MS        50    // Default network latency
#define DEFAULT_JITTER_MS         20    // Random variation
#define DEFAULT_REQUOTE_PROB      0.05  // 5% chance of requote in volatile market

//+------------------------------------------------------------------+
//| CLatencySimulator Class                                          |
//+------------------------------------------------------------------+
class CLatencySimulator : public IManager
{
private:
   bool                     m_is_active;
   double                   m_base_latency_ms;
   double                   m_jitter_ms;
   double                   m_requote_probability;
   
   // Statistics
   ulong                    m_total_delays;
   double                   m_total_delay_added;
   ulong                    m_requotes_simulated;
   datetime                 m_last_simulation_time;
   
   // Input parameters
   input bool               INP_EnableLatencySimulation = true;
   input int                INP_BaseLatencyMS = DEFAULT_LATENCY_MS;
   input int                INP_JitterMS = DEFAULT_JITTER_MS;
   input double             INP_RequoteProbability = DEFAULT_REQUOTE_PROB;

public:
   CLatencySimulator() : m_is_active(false), 
                         m_base_latency_ms(DEFAULT_LATENCY_MS),
                         m_jitter_ms(DEFAULT_JITTER_MS),
                         m_requote_probability(DEFAULT_REQUOTE_PROB),
                         m_total_delays(0), m_total_delay_added(0),
                         m_requotes_simulated(0), m_last_simulation_time(0)
   {
   }
   
   ~CLatencySimulator()
   {
      PrintStats();
   }
   
   //--- IManager Interface
   virtual bool Initialize() override
   {
      // Hanya aktif dalam mode testing
      if(!IsTesting())
      {
         Print("[LatencySim] Disabled - Not in backtest mode");
         return true;
      }
      
      m_is_active = INP_EnableLatencySimulation;
      m_base_latency_ms = (double)INP_BaseLatencyMS;
      m_jitter_ms = (double)INP_JitterMS;
      m_requote_probability = INP_RequoteProbability;
      
      if(m_is_active)
      {
         Print("[LatencySim] ENABLED - Base: ", m_base_latency_ms, "ms, Jitter: ±", m_jitter_ms, "ms");
         EventSubscribe(EVENT_ID_ORDER_REQUEST);
      }
      
      return true;
   }
   
   virtual void Shutdown() override
   {
      PrintStats();
   }
   
   virtual void OnEvent(const SEvent &event) override
   {
      if(!m_is_active || event.event_id != EVENT_ID_ORDER_REQUEST)
         return;
      
      // Simulasi delay sebelum order diproses
      double simulated_delay = CalculateDelay();
      
      // Tambahkan delay ke event untuk diproses oleh ExecutionManager
      SEvent delay_event;
      delay_event.event_id = EVENT_ID_LATENCY_SIMULATION;
      delay_event.timestamp = TimeCurrent();
      delay_event.data.double_value = simulated_delay;
      delay_event.data.string_value = "LATENCY_ADDED";
      
      EventSend(delay_event);
      
      m_total_delays++;
      m_total_delay_added += simulated_delay;
      
      // Simulasi requote acak berdasarkan volatilitas
      if(MathRand() / 32767.0 < m_requote_probability)
      {
         SimulateRequote(event);
      }
   }
   
   virtual string GetName() const override { return "LatencySimulator"; }
   
   //--- Public API
   double CalculateDelay()
   {
      // Distribusi normal untuk jitter yang realistis
      double jitter = MathMax(0, MathRandomNormal(0, m_jitter_ms));
      return m_base_latency_ms + jitter;
   }
   
   void ApplyDelay(double delay_ms)
   {
      if(!m_is_active || !IsTesting())
         return;
      
      // Dalam backtest, kita tidak bisa Sleep() secara nyata,
      // tapi kita bisa mensimulasikan efeknya dengan menggeser waktu eksekusi
      m_last_simulation_time = TimeCurrent();
      
      // Catat bahwa delay telah diterapkan
      Print("[LatencySim] Applied delay: ", DoubleToString(delay_ms, 2), "ms");
   }
   
   bool ShouldSimulateRequote() const
   {
      return m_is_active && (MathRand() / 32767.0 < m_requote_probability);
   }
   
private:
   void SimulateRequote(const SEvent &original_event)
   {
      m_requotes_simulated++;
      
      SEvent requote_event;
      requote_event.event_id = EVENT_ID_REQUOTE_SIMULATED;
      requote_event.timestamp = TimeCurrent();
      requote_event.data.string_value = "REQUOTE_SIM";
      requote_event.data.long_value = m_requotes_simulated;
      
      EventSend(requote_event);
      
      Print("[LatencySim] REQUOTE SIMULATED (#", m_requotes_simulated, ")");
   }
   
   void PrintStats()
   {
      if(!m_is_active || m_total_delays == 0)
         return;
      
      double avg_delay = m_total_delay_added / m_total_delays;
      
      Print("========== LATENCY SIMULATION STATS ==========");
      Print("Total Delays Applied: ", m_total_delays);
      Print("Average Delay: ", DoubleToString(avg_delay, 2), "ms");
      Print("Total Requotes Simulated: ", m_requotes_simulated);
      Print("Requote Rate: ", DoubleToString(100.0 * m_requotes_simulated / m_total_delays, 2), "%");
      Print("================================================");
   }
};
//+------------------------------------------------------------------+

// Helper function untuk distribusi normal (MQL5 compatibility)
double MathRandomNormal(double mean, double stddev)
{
   // Box-Muller transform untuk distribusi normal sederhana
   double u1 = (double)MathRand() / 32767.0;
   double u2 = (double)MathRand() / 32767.0;
   
   if(u1 < 1e-10) u1 = 1e-10;
   
   double z0 = MathSqrt(-2.0 * MathLog(u1)) * MathCos(2.0 * M_PI * u2);
   return mean + z0 * stddev;
}
//+------------------------------------------------------------------+
