//+------------------------------------------------------------------+
//|                                   LatencyOptimizer.mqh           |
//|                        Copyright 2024, PASR Architecture         |
//|                              Ultra-Low Latency Execution Engine  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, PASR Architecture"
#property link      "https://pasr.quant"
#property version   "1.00"
#property description "Optimizes execution path for sub-10ms latency"

//--- Bitfield flags for ultra-fast state checking
struct SExecutionFlags
{
   ulong flags;
   
   void SetFlag(int bit) { flags |= (1ULL << bit); }
   void ClearFlag(int bit) { flags &= ~(1ULL << bit); }
   bool IsSet(int bit) const { return (flags & (1ULL << bit)) != 0; }
   
   // Flag definitions
   enum EFlags
   {
      FLAG_INITIALIZED    = 0,
      FLAG_TRADING_ACTIVE = 1,
      FLAG_ASYNCH_MODE    = 2,
      FLAG_LOW_LATENCY    = 3,
      FLAG_BUFFER_FULL    = 4,
      FLAG_PENDING_FLUSH  = 5
   };
};

//--- Pre-allocated order buffer to avoid runtime allocation
struct SOrderBuffer
{
   MqlTradeRequest request;
   MqlTradeResult result;
   datetime timestamp;
   int ticket;
   bool is_pending;
};

//+------------------------------------------------------------------+
//| Class CLatencyOptimizer                                          |
//+------------------------------------------------------------------+
class CLatencyOptimizer
{
private:
   SExecutionFlags m_flags;
   SOrderBuffer* m_order_buffer;
   int m_buffer_size;
   int m_current_index;
   
   // Performance metrics
   long m_total_ops;
   long m_total_time_ns;
   datetime m_last_tick_time;
   
public:
   CLatencyOptimizer() : m_buffer_size(100), m_current_index(0), m_total_ops(0), m_total_time_ns(0)
   {
      m_order_buffer = new SOrderBuffer[m_buffer_size];
      ZeroMemory(m_order_buffer, m_buffer_size * sizeof(SOrderBuffer));
      m_last_tick_time = TimeCurrent();
   }
   
   ~CLatencyOptimizer()
   {
      if(m_order_buffer != NULL)
         delete[] m_order_buffer;
   }
   
   bool Initialize(int buffer_size = 100)
   {
      if(m_flags.IsSet(SExecutionFlags::FLAG_INITIALIZED))
         return true;
      
      if(buffer_size > 0)
      {
         if(m_order_buffer != NULL) delete[] m_order_buffer;
         m_buffer_size = buffer_size;
         m_order_buffer = new SOrderBuffer[m_buffer_size];
         ZeroMemory(m_order_buffer, m_buffer_size * sizeof(SOrderBuffer));
      }
      
      m_flags.SetFlag(SExecutionFlags::FLAG_INITIALIZED);
      m_flags.SetFlag(SExecutionFlags::FLAG_LOW_LATENCY);
      
      Print("[LatencyOptimizer] Initialized with buffer size: ", m_buffer_size);
      return true;
   }
   
   // Get pre-allocated order slot (zero-allocation)
   SOrderBuffer* GetOrderSlot()
   {
      if(!m_flags.IsSet(SExecutionFlags::FLAG_INITIALIZED))
         return NULL;
      
      SOrderBuffer* slot = &m_order_buffer[m_current_index];
      m_current_index = (m_current_index + 1) % m_buffer_size;
      
      if(m_current_index == 0)
         m_flags.SetFlag(SExecutionFlags::FLAG_BUFFER_FULL);
      
      return slot;
   }
   
   // Start timing for profiling
   void StartTimer()
   {
      m_total_ops++;
   }
   
   // End timing and record metrics
   void EndTimer()
   {
      // In MQL5 we can't get nanosecond precision easily, 
      // but we track tick-level timing
      datetime now = TimeCurrent();
      if(now != m_last_tick_time)
      {
         m_total_time_ns += 1000000; // Assume 1ms minimum resolution
         m_last_tick_time = now;
      }
   }
   
   // Enable async mode
   void EnableAsyncMode()
   {
      m_flags.SetFlag(SExecutionFlags::FLAG_ASYNCH_MODE);
   }
   
   bool IsAsyncMode() const
   {
      return m_flags.IsSet(SExecutionFlags::FLAG_ASYNCH_MODE);
   }
   
   // Quick check if trading is active (bitwise operation - very fast)
   bool IsTradingActive() const
   {
      return m_flags.IsSet(SExecutionFlags::FLAG_TRADING_ACTIVE);
   }
   
   void SetTradingActive(bool active)
   {
      if(active)
         m_flags.SetFlag(SExecutionFlags::FLAG_TRADING_ACTIVE);
      else
         m_flags.ClearFlag(SExecutionFlags::FLAG_TRADING_ACTIVE);
   }
   
   // Get average latency (simulated)
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
      m_flags.ClearFlag(SExecutionFlags::FLAG_BUFFER_FULL);
      ZeroMemory(m_order_buffer, m_buffer_size * sizeof(SOrderBuffer));
   }
};

//+------------------------------------------------------------------+
//| Helper: Fast Math Functions (Branchless where possible)          |
//+------------------------------------------------------------------+
inline double FastMin(double a, double b)
{
   return a < b ? a : b;
}

inline double FastMax(double a, double b)
{
   return a > b ? a : b;
}

inline int FastAbs(int x)
{
   return (x ^ (x >> 31)) - (x >> 31);
}
