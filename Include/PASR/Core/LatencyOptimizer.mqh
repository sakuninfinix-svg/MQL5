//+------------------------------------------------------------------+
//| Core/LatencyOptimizer.mqh                                        |
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_LATENCY_OPTIMIZER_MQH__
#define __CORE_LATENCY_OPTIMIZER_MQH__

struct SExecutionFlags
  {
   ulong flags;

   void Reset() { flags = 0; }
   void SetFlag(int bit) { flags |= ((ulong)1 << bit); }
   void ClearFlag(int bit) { flags &= ~((ulong)1 << bit); }
   bool IsSet(int bit) const { return (flags & ((ulong)1 << bit)) != 0; }
  };

#define PASR_FLAG_INITIALIZED     0
#define PASR_FLAG_TRADING_ACTIVE  1
#define PASR_FLAG_ASYNC_MODE      2
#define PASR_FLAG_LOW_LATENCY     3
#define PASR_FLAG_BUFFER_FULL     4
#define PASR_FLAG_PENDING_FLUSH   5

struct SOrderBuffer
  {
   MqlTradeRequest request;
   MqlTradeResult  result;
   datetime        timestamp;
   ulong           ticket;
   bool            is_pending;

   void Reset()
     {
      ZeroMemory(request);
      ZeroMemory(result);
      timestamp = 0;
      ticket = 0;
      is_pending = false;
     }
  };

class CLatencyOptimizer
  {
private:
   SExecutionFlags m_flags;
   SOrderBuffer    m_order_buffer[];
   int             m_buffer_size;
   int             m_current_index;
   long            m_total_ops;
   long            m_total_time_ns;
   datetime        m_last_tick_time;

   void ResetBuffer()
     {
      for(int i = 0; i < ArraySize(m_order_buffer); i++)
         m_order_buffer[i].Reset();
     }

public:
   CLatencyOptimizer()
      : m_buffer_size(100), m_current_index(0), m_total_ops(0), m_total_time_ns(0),
        m_last_tick_time(0)
     {
      m_flags.Reset();
      ArrayResize(m_order_buffer, m_buffer_size);
      ResetBuffer();
      m_last_tick_time = TimeCurrent();
     }

   bool Initialize(int buffer_size = 100)
     {
      if(m_flags.IsSet(PASR_FLAG_INITIALIZED))
         return true;

      if(buffer_size > 0 && buffer_size != m_buffer_size)
        {
         m_buffer_size = buffer_size;
         ArrayResize(m_order_buffer, m_buffer_size);
         ResetBuffer();
         m_current_index = 0;
        }

      m_flags.SetFlag(PASR_FLAG_INITIALIZED);
      m_flags.SetFlag(PASR_FLAG_LOW_LATENCY);
      Print("[LatencyOptimizer] Initialized with buffer size: ", m_buffer_size);
      return true;
     }

   bool GetOrderSlot(SOrderBuffer &slot)
     {
      if(!m_flags.IsSet(PASR_FLAG_INITIALIZED))
         return false;
      if(m_buffer_size <= 0 || ArraySize(m_order_buffer) <= 0)
         return false;

      slot = m_order_buffer[m_current_index];
      m_current_index = (m_current_index + 1) % m_buffer_size;
      if(m_current_index == 0)
         m_flags.SetFlag(PASR_FLAG_BUFFER_FULL);
      return true;
     }

   bool PutOrderSlot(const SOrderBuffer &slot)
     {
      if(m_buffer_size <= 0 || ArraySize(m_order_buffer) <= 0)
         return false;
      int idx = m_current_index - 1;
      if(idx < 0) idx = m_buffer_size - 1;
      m_order_buffer[idx] = slot;
      return true;
     }

   void StartTimer()
     {
      m_total_ops++;
     }

   void EndTimer()
     {
      datetime now = TimeCurrent();
      if(now != m_last_tick_time)
        {
         m_total_time_ns += 1000000;
         m_last_tick_time = now;
        }
     }

   void EnableAsyncMode()
     {
      m_flags.SetFlag(PASR_FLAG_ASYNC_MODE);
     }

   bool IsAsyncMode() const
     {
      return m_flags.IsSet(PASR_FLAG_ASYNC_MODE);
     }

   bool IsTradingActive() const
     {
      return m_flags.IsSet(PASR_FLAG_TRADING_ACTIVE);
     }

   void SetTradingActive(bool active)
     {
      if(active) m_flags.SetFlag(PASR_FLAG_TRADING_ACTIVE);
      else       m_flags.ClearFlag(PASR_FLAG_TRADING_ACTIVE);
     }

   double GetAvgLatencyMicros() const
     {
      if(m_total_ops == 0) return 0.0;
      return (double)m_total_time_ns / (double)m_total_ops / 1000.0;
     }

   void Reset()
     {
      m_current_index = 0;
      m_total_ops = 0;
      m_total_time_ns = 0;
      m_flags.ClearFlag(PASR_FLAG_BUFFER_FULL);
      ResetBuffer();
     }
  };

inline double FastMin(double a, double b) { return a < b ? a : b; }
inline double FastMax(double a, double b) { return a > b ? a : b; }
inline int FastAbs(int x) { return (x < 0) ? -x : x; }

#endif // __CORE_LATENCY_OPTIMIZER_MQH__
