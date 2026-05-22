//+------------------------------------------------------------------+
//|                                   HighFreqTimer.mqh              |
//|                        Copyright 2024, PASR Architecture         |
//|                              High-Frequency Polling Timer        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, PASR Architecture"
#property link      "https://pasr.quant"
#property version   "1.00"
#property description "Custom high-frequency timer for sub-50ms polling"

//--- Wrapper for high-frequency timer operations
class CHighFreqTimer
{
private:
   int m_timer_id;
   int m_interval_ms;
   bool m_is_active;
   datetime m_last_trigger;
   long m_trigger_count;
   
public:
   CHighFreqTimer() : m_timer_id(0), m_interval_ms(50), m_is_active(false), m_last_trigger(0), m_trigger_count(0)
   {
   }
   
   ~CHighFreqTimer()
   {
      Stop();
   }
   
   // Start custom timer with specified interval (in milliseconds)
   bool Start(int interval_ms = 50)
   {
      if(m_is_active)
         Stop();
      
      m_interval_ms = MathMax(interval_ms, 1); // Minimum 1ms
      m_timer_id = 1; // Use default timer ID
      
      // Set MT5 timer - note: MT5 minimum is 1 second via EventSetTimer
      // For true sub-second timing, we poll in OnTick instead
      EventSetTimer(1); // Fallback to 1 second
      
      m_is_active = true;
      m_last_trigger = TimeCurrent();
      
      Print("[HighFreqTimer] Started with interval: ", m_interval_ms, "ms (polling mode)");
      return true;
   }
   
   // Stop timer
   void Stop()
   {
      if(m_is_active)
      {
         EventKillTimer();
         m_is_active = false;
         m_timer_id = 0;
      }
   }
   
   // Check if timer should trigger (call from OnTick)
   bool ShouldTrigger()
   {
      if(!m_is_active)
         return false;
      
      MqlDateTime now_struct;
      TimeToStruct(TimeCurrent(), now_struct);
      long now_ms = now_struct.sec * 1000 + now_struct.msec;
      
      MqlDateTime last_struct;
      TimeToStruct(m_last_trigger, last_struct);
      long last_ms = last_struct.sec * 1000 + last_struct.msec;
      
      long elapsed = now_ms - last_ms;
      
      if(elapsed >= m_interval_ms)
      {
         m_last_trigger = TimeCurrent();
         m_trigger_count++;
         return true;
      }
      
      return false;
   }
   
   // Get current interval
   int GetInterval() const { return m_interval_ms; }
   
   // Set new interval
   void SetInterval(int interval_ms)
   {
      m_interval_ms = MathMax(interval_ms, 1);
   }
   
   // Get trigger count
   long GetTriggerCount() const { return m_trigger_count; }
   
   // Check if active
   bool IsActive() const { return m_is_active; }
   
   // Reset counter
   void ResetCounter()
   {
      m_trigger_count = 0;
      m_last_trigger = TimeCurrent();
   }
};

//+------------------------------------------------------------------+
//| Performance Counter for measuring execution time                 |
//+------------------------------------------------------------------+
class CPerformanceCounter
{
private:
   datetime m_start_time;
   long m_start_microseconds;
   bool m_is_running;
   
public:
   CPerformanceCounter() : m_is_running(false)
   {
   }
   
   // Start counting
   void Start()
   {
      m_start_time = TimeCurrent();
      m_start_microseconds = GetMicrosecondCount();
      m_is_running = true;
   }
   
   // Stop and return elapsed microseconds
   long Stop()
   {
      if(!m_is_running)
         return 0;
      
      long end_microseconds = GetMicrosecondCount();
      long elapsed = end_microseconds - m_start_microseconds;
      
      m_is_running = false;
      return elapsed;
   }
   
   // Get elapsed time without stopping
   long Elapsed() const
   {
      if(!m_is_running)
         return 0;
      
      return GetMicrosecondCount() - m_start_microseconds;
   }
   
   // Check if running
   bool IsRunning() const { return m_is_running; }
   
private:
   // Get current time in microseconds (simulated - MQL5 doesn't have native microsecond timer)
   long GetMicrosecondCount() const
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      
      // Convert to microseconds from epoch (approximate)
      return (dt.year * 365 + dt.mon * 30 + dt.day) * 86400000000LL +
             dt.hour * 3600000000LL +
             dt.min * 60000000LL +
             dt.sec * 1000000LL +
             dt.msec * 1000LL;
   }
};
