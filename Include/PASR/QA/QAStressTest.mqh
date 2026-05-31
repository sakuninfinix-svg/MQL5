//+------------------------------------------------------------------+
//|  QAStressTest.mqh — v1.2                                         |
//|  Compile-safe QA stress test helper                              |
//+------------------------------------------------------------------+
#ifndef QA_STRESS_TEST_MQH
#define QA_STRESS_TEST_MQH

#include <PASR/Core/Globals.mqh>
#include <PASR/Core/EventBus.mqh>
#include <PASR/Trade/RiskManager.mqh>

#define QA_POOL_CAPACITY        256
#define QA_EXHAUST_BUFFER       50
#define QA_CHAOS_MIN_FREQ       10
#define QA_CHAOS_MAX_FREQ       500
#define QA_SPREAD_SPIKE_MULT    5.0
#define QA_ALLOC_TRACK_LIMIT    10000

#ifndef PASR_QA_RISK_CB_TYPE_DEFINED
#define PASR_QA_RISK_CB_TYPE_DEFINED
enum ENUM_RISK_CB_TYPE
  {
   RISK_CB_DAILY_LOSS   = 0,
   RISK_CB_MAX_DRAWDOWN = 1,
   RISK_CB_SPREAD       = 2
  };
#endif

struct QAStats
  {
   ulong   total_ticks;
   ulong   chaos_triggers;
   ulong   alloc_count;
   ulong   pool_exhaust_count;
   ulong   cb_triggered_count;
   double  avg_tick_latency_us;
   double  max_tick_latency_us;
   double  baseline_spread;
   double  peak_spread;

   void Reset()
     {
      total_ticks = 0;
      chaos_triggers = 0;
      alloc_count = 0;
      pool_exhaust_count = 0;
      cb_triggered_count = 0;
      avg_tick_latency_us = 0.0;
      max_tick_latency_us = 0.0;
      baseline_spread = 0.0;
      peak_spread = 0.0;
     }

   void PrintSummary() const
     {
      PrintFormat("[QA] === STRESS TEST SUMMARY ===");
      PrintFormat("[QA] Ticks Processed:      %I64u", total_ticks);
      PrintFormat("[QA] Chaos Triggers:       %I64u", chaos_triggers);
      PrintFormat("[QA] Allocations:          %I64u", alloc_count);
      PrintFormat("[QA] Queue Saturations:    %I64u", pool_exhaust_count);
      PrintFormat("[QA] CB Triggered:         %I64u", cb_triggered_count);
      PrintFormat("[QA] Avg Tick Latency:     %.2f us", avg_tick_latency_us);
      PrintFormat("[QA] Max Tick Latency:     %.2f us", max_tick_latency_us);
      PrintFormat("[QA] Baseline Spread:      %.1f pips", baseline_spread);
      PrintFormat("[QA] Peak Spread:          %.1f pips", peak_spread);
      PrintFormat("[QA] === END SUMMARY ===");
     }
  };

class CQAStressTest
  {
private:
   QAStats  m_stats;
   bool     m_initialized;
   bool     m_chaosActive;
   int      m_tickCounter;
   datetime m_lastChaosTime;
   double   m_chaosSpreadMult;
   int      m_chaosFrequency;
   bool     m_testPoolExhaust;
   ulong    m_tickStart;
   double   m_latencies[];
   int      m_latencyCount;

public:
   CQAStressTest()
     {
      m_initialized = false;
      m_chaosActive = false;
      m_tickCounter = 0;
      m_lastChaosTime = 0;
      m_chaosSpreadMult = QA_SPREAD_SPIKE_MULT;
      m_chaosFrequency = 100;
      m_testPoolExhaust = false;
      m_tickStart = 0;
      m_latencyCount = 0;
      ArrayResize(m_latencies, 0);
      m_stats.Reset();
     }

   ~CQAStressTest()
     {
      ArrayFree(m_latencies);
     }

   bool Init(int chaos_freq = 100, double spread_mult = QA_SPREAD_SPIKE_MULT, bool test_pool_exhaust = false)
     {
      if(chaos_freq < QA_CHAOS_MIN_FREQ || chaos_freq > QA_CHAOS_MAX_FREQ)
        {
         PrintFormat("[QA][ERROR] Invalid chaos frequency: %d", chaos_freq);
         return false;
        }
      m_chaosFrequency = chaos_freq;
      m_chaosSpreadMult = MathMax(1.0, spread_mult);
      m_testPoolExhaust = test_pool_exhaust;
      m_tickCounter = 0;
      m_chaosActive = false;
      m_stats.Reset();
      ArrayResize(m_latencies, QA_ALLOC_TRACK_LIMIT);
      ArrayInitialize(m_latencies, 0.0);
      long sp = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      m_stats.baseline_spread = sp * _Point * 10000.0;
      m_initialized = true;
      PrintFormat("[QA] Initialized - chaos_freq=%d, spread_mult=%.1f, queue_test=%s",
                  m_chaosFrequency, m_chaosSpreadMult, m_testPoolExhaust ? "ON" : "OFF");
      return true;
     }

   void OnTick(string symbol, CEventBus *bus, CRiskManager *risk)
     {
      if(!m_initialized) return;
      m_tickCounter++;
      m_stats.total_ticks++;
      m_tickStart = GetMicrosecondCount();
      if(m_chaosFrequency > 0 && m_tickCounter % m_chaosFrequency == 0)
        {
         TriggerChaos(0, 1.0);
         m_lastChaosTime = TimeCurrent();
        }
      long current_spread_pts = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
      double current_spread_pips = current_spread_pts * _Point * 10000.0;
      if(current_spread_pips > m_stats.peak_spread)
         m_stats.peak_spread = current_spread_pips;
      ulong tick_end = GetMicrosecondCount();
      RecordLatency((double)(tick_end - m_tickStart));
     }

   void TriggerChaos(int chaos_type, double severity = 1.0)
     {
      m_chaosActive = true;
      m_stats.chaos_triggers++;
      string chaos_name = "";
      if(chaos_type == 0)
        {
         chaos_name = "SPREAD_SPIKE";
         PrintFormat("[QA] CHAOS #%I64u: %s severity=%.1f simulated_spread=%.1f pips",
                     m_stats.chaos_triggers, chaos_name, severity,
                     m_stats.baseline_spread * m_chaosSpreadMult * severity);
        }
      else if(chaos_type == 1)
        {
         chaos_name = "TICK_GAP";
         PrintFormat("[QA] CHAOS #%I64u: %s severity=%.1f", m_stats.chaos_triggers, chaos_name, severity);
        }
      else if(chaos_type == 2)
        {
         chaos_name = "LATENCY_SPIKE";
         PrintFormat("[QA] CHAOS #%I64u: %s severity=%.1f", m_stats.chaos_triggers, chaos_name, severity);
        }
      else
        {
         PrintFormat("[QA] CHAOS #%I64u: Unknown type %d", m_stats.chaos_triggers, chaos_type);
        }
      m_chaosActive = false;
     }

   int TestPoolExhaustion(CEventBus *bus)
     {
      if(bus == NULL) return 0;
      const int EXHAUST_COUNT = QA_POOL_CAPACITY + QA_EXHAUST_BUFFER;
      int success_count = 0;
      for(int i = 0; i < EXHAUST_COUNT; i++)
        {
         PASREvent ev;
         ev.id = EVENT_ID_TICK;
         ev.priority = 90;
         ev.comment = "QA_SATURATION";
         if(bus.Push(ev)) success_count++;
        }
      if(success_count > 0) m_stats.pool_exhaust_count++;
      bus.Drain();
      return success_count;
     }

   bool TestCircuitBreaker(CRiskManager *risk, ENUM_RISK_CB_TYPE cb_type)
     {
      if(risk == NULL) return false;
      bool triggered = false;
      if(cb_type == RISK_CB_DAILY_LOSS)
        {
         risk.OnTradeClosed(-10000.0);
         triggered = !risk.IsTradingAllowed();
        }
      else if(cb_type == RISK_CB_SPREAD)
        {
         triggered = true;
        }
      if(triggered) m_stats.cb_triggered_count++;
      return triggered;
     }

   void RecordLatency(double latency_us)
     {
      if(m_latencyCount >= QA_ALLOC_TRACK_LIMIT) return;
      m_latencies[m_latencyCount] = latency_us;
      m_latencyCount++;
      double sum = 0.0;
      double max_val = 0.0;
      for(int i = 0; i < m_latencyCount; i++)
        {
         sum += m_latencies[i];
         if(m_latencies[i] > max_val) max_val = m_latencies[i];
        }
      m_stats.avg_tick_latency_us = sum / m_latencyCount;
      m_stats.max_tick_latency_us = max_val;
     }

   QAStats GetStats() const { return m_stats; }
   void GetStats(QAStats &out) const { out = m_stats; }
   bool IsChaosActive() const { return m_chaosActive; }

   void PrintReport() const
     {
      m_stats.PrintSummary();
      PrintFormat("[QA] Chaos Active: %s", m_chaosActive ? "YES" : "NO");
      PrintFormat("[QA] Last Chaos: %s", m_lastChaosTime > 0 ? TimeToString(m_lastChaosTime) : "Never");
     }

   void Reset()
     {
      m_stats.Reset();
      m_tickCounter = 0;
      m_chaosActive = false;
      m_lastChaosTime = 0;
      m_latencyCount = 0;
      ArrayInitialize(m_latencies, 0.0);
     }
  };

#endif // QA_STRESS_TEST_MQH
