//+------------------------------------------------------------------+
//| Core/HighFreqTimer.mqh                                           |
//| High-frequency polling timer                                     |
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_HIGH_FREQ_TIMER_MQH__
#define __CORE_HIGH_FREQ_TIMER_MQH__

class CHighFreqTimer
  {
private:
   int   m_timer_id;
   int   m_interval_ms;
   bool  m_is_active;
   ulong m_last_trigger_ms;
   long  m_trigger_count;

   ulong NowMs() const
     {
      return (ulong)(GetMicrosecondCount() / 1000ULL);
     }

public:
   CHighFreqTimer()
      : m_timer_id(0), m_interval_ms(50), m_is_active(false),
        m_last_trigger_ms(0), m_trigger_count(0)
     {}

   ~CHighFreqTimer()
     {
      Stop();
     }

   bool Start(int interval_ms = 50)
     {
      if(m_is_active) Stop();
      m_interval_ms = MathMax(interval_ms, 1);
      m_timer_id = 1;
      EventSetTimer(1);
      m_is_active = true;
      m_last_trigger_ms = NowMs();
      Print("[HighFreqTimer] Started with interval: ", m_interval_ms, "ms (polling mode)");
      return true;
     }

   void Stop()
     {
      if(m_is_active)
        {
         EventKillTimer();
         m_is_active = false;
         m_timer_id = 0;
        }
     }

   bool ShouldTrigger()
     {
      if(!m_is_active) return false;
      ulong now_ms = NowMs();
      ulong elapsed = now_ms - m_last_trigger_ms;
      if(elapsed >= (ulong)m_interval_ms)
        {
         m_last_trigger_ms = now_ms;
         m_trigger_count++;
         return true;
        }
      return false;
     }

   int  GetInterval() const { return m_interval_ms; }
   void SetInterval(int interval_ms) { m_interval_ms = MathMax(interval_ms, 1); }
   long GetTriggerCount() const { return m_trigger_count; }
   bool IsActive() const { return m_is_active; }

   void ResetCounter()
     {
      m_trigger_count = 0;
      m_last_trigger_ms = NowMs();
     }
  };

class CPerformanceCounter
  {
private:
   ulong m_start_microseconds;
   bool  m_is_running;

public:
   CPerformanceCounter() : m_start_microseconds(0), m_is_running(false) {}

   void Start()
     {
      m_start_microseconds = GetMicrosecondCount();
      m_is_running = true;
     }

   long Stop()
     {
      if(!m_is_running) return 0;
      ulong end_microseconds = GetMicrosecondCount();
      long elapsed = (long)(end_microseconds - m_start_microseconds);
      m_is_running = false;
      return elapsed;
     }

   long Elapsed() const
     {
      if(!m_is_running) return 0;
      return (long)(GetMicrosecondCount() - m_start_microseconds);
     }

   bool IsRunning() const { return m_is_running; }
  };

#endif // __CORE_HIGH_FREQ_TIMER_MQH__
