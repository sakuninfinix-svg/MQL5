//+------------------------------------------------------------------+
//|                                             PASR_Executor.mqh      |
//|                        Modular OOP Architecture - Executor Core    |
//|                        (c) 2024 PASR Quant Development             |
//+------------------------------------------------------------------+
#property copyright "PASR Quant Team"
#property link      "https://pasr.quant"
#property version   "8.00"
#property description "Asynchronous Order Executor with Smart Retry & Slippage Control"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Execution Status Enum                                              |
//+------------------------------------------------------------------+
enum EXECUTION_STATUS
  {
   EXEC_NONE      = 0,  // No active execution
   EXEC_PENDING   = 1,  // Order sent, waiting confirmation
   EXEC_SUCCESS   = 2,  // Successfully executed
   EXEC_FAILED    = 3,  // Failed after all retries
   EXEC_RETRYING  = 4   // Currently retrying
  };

//+------------------------------------------------------------------+
//| Execution Request Structure                                        |
//+------------------------------------------------------------------+
struct ExecutionRequest
  {
   ulong          ticket;           // Target ticket (0 for new order)
   ENUM_ORDER_TYPE order_type;      // Order type
   string         symbol;           // Symbol
   double         volume;           // Volume
   double         price;            // Price
   double         sl;               // Stop Loss
   double         tp;               // Take Profit
   string         comment;          // Comment
   ulong          magic;            // Magic number
   int            slippage;         // Max slippage points
   datetime       created_at;       // Request creation time
   int            retry_count;      // Current retry count
   int            max_retries;      // Maximum retries allowed
   EXECUTION_STATUS status;        // Current status
   
   ExecutionRequest()
     {
      ticket = 0;
      order_type = WRONG_VALUE;
      symbol = "";
      volume = 0;
      price = 0;
      sl = 0;
      tp = 0;
      comment = "";
      magic = 0;
      slippage = 10;
      created_at = TimeCurrent();
      retry_count = 0;
      max_retries = 3;
      status = EXEC_NONE;
     }
  };

//+------------------------------------------------------------------+
//| CExecutor Class - Async Order Management                           |
//+------------------------------------------------------------------+
class CExecutor
  {
private:
   CTrade                m_trade;
   ExecutionRequest      m_requests[];        // Queue of requests
   int                   m_request_count;     // Active request count
   int                   m_max_queue_size;    // Max concurrent requests
   bool                  m_async_mode;        // Async mode flag
   
   // Statistics
   int                   m_total_executed;
   int                   m_total_failed;
   int                   m_total_retries;
   double                m_avg_latency_ms;
   
   // Dynamic slippage control
   double                m_volatility_factor;
   int                   m_base_slippage;
   
public:
   CExecutor()
     {
      m_request_count = 0;
      m_max_queue_size = 10;
      m_async_mode = true;
      m_total_executed = 0;
      m_total_failed = 0;
      m_total_retries = 0;
      m_avg_latency_ms = 0;
      m_volatility_factor = 1.0;
      m_base_slippage = 10;
      
      ArrayResize(m_requests, m_max_queue_size);
     }
   
   ~CExecutor()
     {
      // Cleanup pending requests
      for(int i = 0; i < m_request_count; i++)
        {
         if(m_requests[i].status == EXEC_PENDING || m_requests[i].status == EXEC_RETRYING)
           {
            Print("WARNING: Cleaning up pending request #", i);
           }
        }
     }
   
   // Initialize executor
   bool Initialize(const bool async_mode = true, const int max_queue = 10)
     {
      m_async_mode = async_mode;
      m_max_queue_size = MathMax(1, MathMin(max_queue, 50));
      ArrayResize(m_requests, m_max_queue_size);
      
      m_trade.SetExpertMagicNumber(0);
      m_trade.SetDeviationInPoints(m_base_slippage);
      m_trade.SetTypeFilling(ORDER_FILLING_FOK);
      m_trade.SetAsyncMode(m_async_mode);
      
      return true;
     }
   
   // Submit new execution request
   int SubmitOrder(const string symbol, const ENUM_ORDER_TYPE type, const double volume,
                   const double price, const double sl, const double tp,
                   const string comment = "", const ulong magic = 0,
                   const int slippage = -1)
     {
      if(m_request_count >= m_max_queue_size)
        {
         Print("ERROR: Execution queue full (", m_request_count, "/", m_max_queue_size, ")");
         return -1;
        }
      
      // Find free slot
      int slot = -1;
      for(int i = 0; i < m_max_queue_size; i++)
        {
         if(m_requests[i].status == EXEC_NONE || m_requests[i].status == EXEC_SUCCESS || m_requests[i].status == EXEC_FAILED)
           {
            slot = i;
            break;
           }
        }
      
      if(slot == -1)
        {
         Print("ERROR: No available execution slots");
         return -1;
        }
      
      // Prepare request
      ExecutionRequest &req = m_requests[slot];
      ZeroMemory(req);
      
      req.order_type = type;
      req.symbol = symbol;
      req.volume = volume;
      req.price = price;
      req.sl = sl;
      req.tp = tp;
      req.comment = comment;
      req.magic = magic;
      req.created_at = TimeCurrent();
      req.retry_count = 0;
      req.max_retries = 3;
      req.status = EXEC_PENDING;
      
      // Dynamic slippage
      req.slippage = (slippage > 0) ? slippage : CalculateDynamicSlippage(symbol);
      
      // Execute immediately or queue
      if(m_async_mode)
        {
         ExecuteAsync(slot);
        }
      else
        {
         ExecuteSync(slot);
        }
      
      m_request_count++;
      return slot;
     }
   
   // Modify existing order
   int ModifyOrder(const ulong ticket, const double price = 0, const double sl = 0, const double tp = 0)
     {
      if(ticket <= 0)
        {
         Print("ERROR: Invalid ticket for modification");
         return -1;
        }
      
      if(m_request_count >= m_max_queue_size)
        {
         Print("ERROR: Execution queue full");
         return -1;
        }
      
      // Find free slot
      int slot = -1;
      for(int i = 0; i < m_max_queue_size; i++)
        {
         if(m_requests[i].status == EXEC_NONE || m_requests[i].status == EXEC_SUCCESS || m_requests[i].status == EXEC_FAILED)
           {
            slot = i;
            break;
           }
        }
      
      if(slot == -1) return -1;
      
      ExecutionRequest &req = m_requests[slot];
      ZeroMemory(req);
      
      req.ticket = ticket;
      req.symbol = PositionGetSymbol(ticket);
      req.volume = PositionGetDouble(POSITION_VOLUME);
      req.price = price;
      req.sl = sl;
      req.tp = tp;
      req.created_at = TimeCurrent();
      req.retry_count = 0;
      req.max_retries = 2;
      req.status = EXEC_PENDING;
      req.slippage = CalculateDynamicSlippage(req.symbol);
      
      if(m_async_mode)
        {
         ModifyAsync(slot);
        }
      else
        {
         ModifySync(slot);
        }
      
      m_request_count++;
      return slot;
     }
   
   // Process execution queue (call from OnTimer or OnTick)
   void ProcessQueue()
     {
      datetime now = TimeCurrent();
      
      for(int i = 0; i < m_max_queue_size; i++)
        {
         ExecutionRequest &req = m_requests[i];
         
         if(req.status == EXEC_NONE) continue;
         
         // Check timeout for pending orders
         if(req.status == EXEC_PENDING)
           {
            long elapsed = now - req.created_at;
            if(elapsed > 5) // 5 seconds timeout
              {
               // Check if order was filled
               if(CheckOrderFilled(req))
                 {
                  req.status = EXEC_SUCCESS;
                  m_total_executed++;
                  UpdateLatency(now - req.created_at);
                 }
               else if(req.retry_count < req.max_retries)
                 {
                  req.status = EXEC_RETRYING;
                  req.retry_count++;
                  m_total_retries++;
                  Print("RETRY #", req.retry_count, " for request #", i);
                  
                  if(req.ticket > 0)
                    ModifyAsync(i);
                  else
                    ExecuteAsync(i);
                 }
               else
                 {
                  req.status = EXEC_FAILED;
                  m_total_failed++;
                  Print("FAILED: Request #", i, " after ", req.retry_count, " retries");
                 }
              }
           }
         else if(req.status == EXEC_RETRYING)
           {
            // Re-check status
            if(CheckOrderFilled(req))
              {
               req.status = EXEC_SUCCESS;
               m_total_executed++;
               UpdateLatency(now - req.created_at);
              }
            else if(req.retry_count >= req.max_retries)
              {
               req.status = EXEC_FAILED;
               m_total_failed++;
              }
           }
         else if(req.status == EXEC_SUCCESS || req.status == EXEC_FAILED)
           {
            // Auto-cleanup old completed requests (after 60s)
            if(now - req.created_at > 60)
              {
               ZeroMemory(req);
               m_request_count = MathMax(0, m_request_count - 1);
              }
           }
        }
     }
   
   // Get execution statistics
   void GetStatistics(int &total_executed, int &total_failed, int &total_retries, double &avg_latency)
     {
      total_executed = m_total_executed;
      total_failed = m_total_failed;
      total_retries = m_total_retries;
      avg_latency = m_avg_latency_ms;
     }
   
   // Update volatility factor for dynamic slippage
   void UpdateVolatility(const string symbol, const double atr_value, const double point_value)
     {
      if(atr_value <= 0 || point_value <= 0) return;
      
      // Normalize ATR to points
      double atr_points = atr_value / point_value;
      
      // Adjust volatility factor (base: 10 points ATR = factor 1.0)
      m_volatility_factor = MathMax(0.5, MathMin(3.0, atr_points / 10.0));
     }
   
   // Check if queue has capacity
   bool HasCapacity() const
     {
      return (m_request_count < m_max_queue_size);
     }
   
   // Get active request count
   int GetActiveCount() const
     {
      return m_request_count;
     }
   
private:
   // Execute order asynchronously
   void ExecuteAsync(const int slot)
     {
      ExecutionRequest &req = m_requests[slot];
      
      m_trade.SetDeviationInPoints(req.slippage);
      m_trade.SetExpertMagicNumber(req.magic);
      
      bool result = false;
      
      switch(req.order_type)
        {
         case ORDER_TYPE_BUY:
            result = m_trade.Buy(req.volume, req.symbol, req.price, req.sl, req.tp, req.comment);
            break;
         case ORDER_TYPE_SELL:
            result = m_trade.Sell(req.volume, req.symbol, req.price, req.sl, req.tp, req.comment);
            break;
         default:
            req.status = EXEC_FAILED;
            return;
        }
      
      if(!result)
        {
         uint error = GetLastError();
         Print("ASYNC ORDER FAILED: Error ", error, " - ", retcode_description(error));
         
         if(req.retry_count < req.max_retries && IsRetryableError(error))
           {
            req.status = EXEC_RETRYING;
            req.retry_count++;
            m_total_retries++;
            Sleep(100); // Brief pause before retry
            ExecuteAsync(slot);
           }
         else
           {
            req.status = EXEC_FAILED;
            m_total_failed++;
           }
        }
     }
   
   // Execute order synchronously
   void ExecuteSync(const int slot)
     {
      ExecutionRequest &req = m_requests[slot];
      
      m_trade.SetDeviationInPoints(req.slippage);
      m_trade.SetExpertMagicNumber(req.magic);
      
      bool result = false;
      
      switch(req.order_type)
        {
         case ORDER_TYPE_BUY:
            result = m_trade.Buy(req.volume, req.symbol, req.price, req.sl, req.tp, req.comment);
            break;
         case ORDER_TYPE_SELL:
            result = m_trade.Sell(req.volume, req.symbol, req.price, req.sl, req.tp, req.comment);
            break;
        }
      
      if(result)
        {
         req.status = EXEC_SUCCESS;
         m_total_executed++;
        }
      else
        {
         req.status = EXEC_FAILED;
         m_total_failed++;
         Print("SYNC ORDER FAILED: Error ", GetLastError());
        }
     }
   
   // Modify order asynchronously
   void ModifyAsync(const int slot)
     {
      ExecutionRequest &req = m_requests[slot];
      
      m_trade.SetDeviationInPoints(req.slippage);
      
      bool result = m_trade.PositionModify(req.symbol, req.sl, req.tp);
      
      if(!result)
        {
         uint error = GetLastError();
         if(req.retry_count < req.max_retries && IsRetryableError(error))
           {
            req.status = EXEC_RETRYING;
            req.retry_count++;
            m_total_retries++;
            Sleep(50);
            ModifyAsync(slot);
           }
         else
           {
            req.status = EXEC_FAILED;
            m_total_failed++;
           }
        }
     }
   
   // Modify order synchronously
   void ModifySync(const int slot)
     {
      ExecutionRequest &req = m_requests[slot];
      
      m_trade.SetDeviationInPoints(req.slippage);
      
      bool result = m_trade.PositionModify(req.symbol, req.sl, req.tp);
      
      req.status = result ? EXEC_SUCCESS : EXEC_FAILED;
      if(result) m_total_executed++;
      else m_total_failed++;
     }
   
   // Check if order was filled
   bool CheckOrderFilled(const ExecutionRequest &req)
     {
      if(req.ticket > 0)
        {
         return PositionSelectByTicket(req.ticket);
        }
      
      // For new orders, check by comment and magic
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(PositionGetTicket(i) > 0)
           {
            if(PositionGetString(POSITION_COMMENT) == req.comment &&
               PositionGetInteger(POSITION_MAGIC) == req.magic &&
               PositionGetString(POSITION_SYMBOL) == req.symbol)
              {
               return true;
              }
           }
        }
      
      return false;
     }
   
   // Calculate dynamic slippage based on volatility
   int CalculateDynamicSlippage(const string symbol)
     {
      int base = m_base_slippage;
      int dynamic = (int)(base * m_volatility_factor);
      
      // Add spread buffer
      double spread = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
      dynamic += (int)(spread * 0.5);
      
      return MathMax(base, MathMin(dynamic, base * 3));
     }
   
   // Check if error is retryable
   bool IsRetryableError(const uint error_code) const
     {
      switch(error_code)
        {
         case TRADE_RETCODE_TRADE_DISABLED:
         case TRADE_RETCODE_MARKET_CLOSED:
         case TRADE_RETCODE_INVALID_FILL:
         case TRADE_RETCODE_CONNECTION:
         case TRADE_RETCODE_TIMEOUT:
         case TRADE_RETCODE_INVALID:
            return true;
         default:
            return false;
        }
     }
   
   // Update average latency
   void UpdateLatency(const double latency_sec)
     {
      double latency_ms = latency_sec * 1000.0;
      
      if(m_total_executed == 1)
        {
         m_avg_latency_ms = latency_ms;
        }
      else
        {
         m_avg_latency_ms = (m_avg_latency_ms * (m_total_executed - 1) + latency_ms) / m_total_executed;
        }
     }
   
   // Get error description
   string retcode_description(const uint retcode) const
     {
      switch(retcode)
        {
         case TRADE_RETCODE_DONE: return "Done";
         case TRADE_RETCODE_DONE_PARTIAL: return "Partial";
         case TRADE_RETCODE_ERROR: return "Error";
         case TRADE_RETCODE_TIMEOUT: return "Timeout";
         case TRADE_RETCODE_INVALID: return "Invalid";
         case TRADE_RETCODE_INVALID_VOLUME: return "Invalid Volume";
         case TRADE_RETCODE_INVALID_PRICE: return "Invalid Price";
         case TRADE_RETCODE_INVALID_STOPS: return "Invalid Stops";
         case TRADE_RETCODE_TRADE_DISABLED: return "Trade Disabled";
         case TRADE_RETCODE_MARKET_CLOSED: return "Market Closed";
         case TRADE_RETCODE_NO_MONEY: return "No Money";
         case TRADE_RETCODE_PRICE_CHANGED: return "Price Changed";
         case TRADE_RETCODE_PRICE_OFF: return "Price Off";
         case TRADE_RETCODE_INVALID_EXPIRATION: return "Invalid Expiration";
         case TRADE_RETCODE_ORDER_CHANGED: return "Order Changed";
         case TRADE_RETCODE_TOO_MANY_REQUESTS: return "Too Many Requests";
         case TRADE_RETCODE_NO_CHANGES: return "No Changes";
         case TRADE_RETCODE_SERVER_DISABLES_AT: return "Server Disables AT";
         case TRADE_RETCODE_CONNECTION: return "Connection Error";
         case TRADE_RETCODE_ONLY_REAL: return "Only Real";
         case TRADE_RETCODE_LIMIT_ORDERS: return "Limit Orders";
         case TRADE_RETCODE_LIMIT_VOLUME: return "Limit Volume";
         case TRADE_RETCODE_INVALID_ORDER: return "Invalid Order";
         case TRADE_RETCODE_POSITION_CLOSED: return "Position Closed";
         case TRADE_RETCODE_INVALID_CLOSE_VOLUME: return "Invalid Close Volume";
         case TRADE_RETCODE_CLOSE_ORDER_EXIST: return "Close Order Exist";
         case TRADE_RETCODE_LIMIT_POSITIONS: return "Limit Positions";
         case TRADE_RETCODE_REJECT_CANCEL: return "Reject Cancel";
         case TRADE_RETCODE_LONG_ONLY: return "Long Only";
         case TRADE_RETCODE_SHORT_ONLY: return "Short Only";
         case TRADE_RETCODE_CLOSE_ONLY: return "Close Only";
         case TRADE_RETCODE_DIRECT_ONLY: return "Direct Only";
         case TRADE_RETCODE_SETTLEMENT_ONLY: return "Settlement Only";
         case TRADE_RETCODE_LOCKED: return "Locked";
         case TRADE_RETCODE_FROZEN: return "Frozen";
         case TRADE_RETCODE_INVALID_FILL: return "Invalid Fill";
         case TRADE_RETCODE_CONNECTION: return "Connection";
         default: return "Unknown Error #" + IntegerToString(retcode);
        }
     }
  };

//+------------------------------------------------------------------+
