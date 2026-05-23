//+------------------------------------------------------------------+
//| ExitEngine.mqh                                              v1.0 |
//| Copyright (C) 2024, PASR Trading System                          |
//| https://pasr.trading                                             |
//|                                                                  |
//| Smart Exit Logic for Position Management                        |
//| - Chandelier Exit (ATR-based trailing stop)                     |
//| - Time-Based Exit (dead money prevention)                       |
//| - Structure Break Exit (swing high/low break)                   |
//| - Profit Fade Exit (momentum exhaustion)                        |
//+------------------------------------------------------------------+
#ifndef PASR_EXIT_ENGINE_MQH
#define PASR_EXIT_ENGINE_MQH

#include <PASR/Core/IManager.h>
#include <PASR/Trade/PositionManager.mqh>

//+------------------------------------------------------------------+
//| Exit Configuration Constants                                     |
//+------------------------------------------------------------------+
#define CHANDELIER_ATR_MULT     3.0     // ATR multiplier for chandelier stop
#define CHANDELIER_PERIOD       22      // Lookback period for highest high/lowest low
#define TIME_EXIT_BARS          10      // Exit if no profit after N bars
#define PROFIT_FADE_THRESHOLD   0.70    // RSI threshold for momentum fade
#define STRUCTURE_BREAK_SENSITIVITY 1   // Number of swing points to confirm break

//+------------------------------------------------------------------+
//| Exit Reason Enumeration                                          |
//+------------------------------------------------------------------+
enum ExitReason
{
   EXIT_NONE = 0,           // No exit signal
   EXIT_CHANDLER_HIT,       // Chandelier trailing stop hit
   EXIT_TIME_EXPIRED,       // Time-based exit triggered
   EXIT_STRUCTURE_BREAK,    // Market structure broken
   EXIT_PROFIT_FADE,        // Momentum exhaustion detected
   EXIT_REVERSAL_SIGNAL,    // Opposite signal generated
   EXIT_EMERGENCY           // Emergency close (circuit breaker)
};

//+------------------------------------------------------------------+
//| Exit Signal Structure                                            |
//+------------------------------------------------------------------+
struct ExitSignal
{
   ExitReason reason;
   double     trigger_price;
   double     current_profit;
   int        bars_held;
   string     description;
   
   void Clear()
   {
      reason = EXIT_NONE;
      trigger_price = 0.0;
      current_profit = 0.0;
      bars_held = 0;
      description = "";
   }
};

//+------------------------------------------------------------------+
//| CExitEngine Class                                                |
//| Advanced exit logic for optimizing profit and limiting loss     |
//+------------------------------------------------------------------+
class CExitEngine : public IManager
{
private:
   bool              m_initialized;
   
   // Performance tracking
   ulong             m_chandelier_exits;
   ulong             m_time_exits;
   ulong             m_structure_exits;
   ulong             m_fade_exits;
   
   // Cached indicator handles to prevent spam
   int               m_hATR;
   int               m_hRSI;
   
   // Static buffers for zero-allocation
   double            m_highs[CHANDELIER_PERIOD];
   double            m_lows[CHANDELIER_PERIOD];
   double            m_atr_values[50];
   
   //--- Initialize indicator handles once
   bool InitIndicators()
   {
      if(m_hATR == INVALID_HANDLE)
         m_hATR = iATR(_Symbol, PERIOD_CURRENT, CHANDELIER_PERIOD);
      if(m_hRSI == INVALID_HANDLE)
         m_hRSI = iRSI(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
      
      return (m_hATR != INVALID_HANDLE && m_hRSI != INVALID_HANDLE);
   }
   
   //--- Cleanup indicator handles
   void CleanupIndicators()
   {
      if(m_hATR != INVALID_HANDLE) { IndicatorRelease(m_hATR); m_hATR = INVALID_HANDLE; }
      if(m_hRSI != INVALID_HANDLE) { IndicatorRelease(m_hRSI); m_hRSI = INVALID_HANDLE; }
   }
   
   //--- Helper to get ATR value from cached handle
   double GetATRValue(int period)
   {
      // For now use the cached handle; in production you might want multiple handles per period
      if(m_hATR == INVALID_HANDLE) return 0.0;
      
      double atrBuffer[1];
      if(CopyBuffer(m_hATR, 0, 0, 1, atrBuffer) <= 0)
         return 0.0;
      
      return atrBuffer[0];
   }
   
   //--- Helper to get RSI values from cached handle
   bool GetRSIValues(double &current, double &prev)
   {
      if(m_hRSI == INVALID_HANDLE)
      {
         current = 0.0;
         prev = 0.0;
         return false;
      }
      
      double rsiBuffer[2];
      if(CopyBuffer(m_hRSI, 0, 0, 2, rsiBuffer) < 2)
      {
         current = 0.0;
         prev = 0.0;
         return false;
      }
      
      current = rsiBuffer[0];
      prev = rsiBuffer[1];
      return true;
   }
   
public:
   CExitEngine();
   ~CExitEngine();
   
   // IManager interface
   virtual bool      Initialize() override;
   virtual void      Shutdown() override;
   virtual void      OnTick(const string symbol) override;
   virtual void      OnTimer() override;
   virtual void      OnTrade() override;
   
   // Core exit logic
   ExitSignal        CheckExit(const string symbol, ENUM_ORDER_TYPE position_type, 
                               double entry_price, double current_price);
   
   // Individual exit methods
   bool              CheckChandelierExit(const string symbol, ENUM_ORDER_TYPE pos_type, 
                                         double current_price, double &exit_level);
   bool              CheckTimeExit(const string symbol, datetime entry_time, int min_bars);
   bool              CheckStructureBreak(const string symbol, ENUM_ORDER_TYPE pos_type);
   bool              CheckProfitFade(const string symbol, ENUM_ORDER_TYPE pos_type);
   
   // Utility functions
   double            CalculateChandelierLevel(const string symbol, ENUM_ORDER_TYPE pos_type);
   int               GetBarsSinceEntry(datetime entry_time);
   void              PrintStats();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CExitEngine::CExitEngine()
{
   m_initialized = false;
   m_chandelier_exits = 0;
   m_time_exits = 0;
   m_structure_exits = 0;
   m_fade_exits = 0;
   m_hATR = INVALID_HANDLE;
   m_hRSI = INVALID_HANDLE;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CExitEngine::~CExitEngine()
{
   CleanupIndicators();
   Shutdown();
}

//+------------------------------------------------------------------+
//| Initialize engine                                                |
//+------------------------------------------------------------------+
bool CExitEngine::Initialize()
{
   if(m_initialized) return true;
   
   Print("[EXIT] Initializing ExitEngine...");
   Print("[EXIT] Chandelier ATR Multiplier: ", CHANDELIER_ATR_MULT);
   Print("[EXIT] Chandelier Period: ", CHANDELIER_PERIOD);
   Print("[EXIT] Time Exit Threshold: ", TIME_EXIT_BARS, " bars");
   Print("[EXIT] Profit Fade RSI Threshold: ", PROFIT_FADE_THRESHOLD);
   
   // Initialize cached indicator handles
   if(!InitIndicators())
   {
      Print("[EXIT] Failed to initialize indicator handles");
      return false;
   }
   
   m_initialized = true;
   
   return true;
}

//+------------------------------------------------------------------+
//| Shutdown engine                                                  |
//+------------------------------------------------------------------+
void CExitEngine::Shutdown()
{
   if(!m_initialized) return;
   
   Print("[EXIT] === EXIT STATISTICS ===");
   Print("[EXIT] Chandelier Exits:    ", m_chandelier_exits);
   Print("[EXIT] Time Exits:          ", m_time_exits);
   Print("[EXIT] Structure Exits:     ", m_structure_exits);
   Print("[EXIT] Profit Fade Exits:   ", m_fade_exits);
   Print("[EXIT] Total Exits:         ", m_chandelier_exits + m_time_exits + m_structure_exits + m_fade_exits);
   
   m_initialized = false;
}

//+------------------------------------------------------------------+
//| OnTick handler                                                   |
//+------------------------------------------------------------------+
void CExitEngine::OnTick(const string symbol)
{
   // Exit checks are performed on-demand in CheckExit()
}

//+------------------------------------------------------------------+
//| OnTimer handler                                                  |
//+------------------------------------------------------------------+
void CExitEngine::OnTimer()
{
   // No periodic actions needed
}

//+------------------------------------------------------------------+
//| OnTrade handler                                                  |
//+------------------------------------------------------------------+
void CExitEngine::OnTrade()
{
   // No action on trade events
}

//+------------------------------------------------------------------+
//| Main exit check - orchestrates all exit strategies             |
//+------------------------------------------------------------------+
ExitSignal CExitEngine::CheckExit(
   const string symbol, 
   ENUM_ORDER_TYPE position_type, 
   double entry_price, 
   double current_price)
{
   ExitSignal signal;
   signal.Clear();
   
   if(!m_initialized) return signal;
   
   double exit_level = 0.0;
   
   // 1. Check Chandelier Exit (highest priority - hard stop)
   if(CheckChandelierExit(symbol, position_type, current_price, exit_level))
   {
      signal.reason = EXIT_CHANDLER_HIT;
      signal.trigger_price = exit_level;
      signal.current_profit = (position_type == ORDER_TYPE_BUY) ? 
                              current_price - entry_price : entry_price - current_price;
      signal.description = StringFormat("Chandelier stop hit at %.5f", exit_level);
      m_chandelier_exits++;
      return signal;
   }
   
   // 2. Check Structure Break (market structure violation)
   if(CheckStructureBreak(symbol, position_type))
   {
      signal.reason = EXIT_STRUCTURE_BREAK;
      signal.trigger_price = current_price;
      signal.current_profit = (position_type == ORDER_TYPE_BUY) ? 
                              current_price - entry_price : entry_price - current_price;
      signal.description = "Market structure broken";
      m_structure_exits++;
      return signal;
   }
   
   // 3. Check Profit Fade (momentum exhaustion in profit)
   if(CheckProfitFade(symbol, position_type))
   {
      // Only exit if in profit
      double profit_pts = (position_type == ORDER_TYPE_BUY) ? 
                          current_price - entry_price : entry_price - current_price;
      
      if(profit_pts > 0)
      {
         signal.reason = EXIT_PROFIT_FADE;
         signal.trigger_price = current_price;
         signal.current_profit = profit_pts;
         signal.description = "Momentum exhaustion detected";
         m_fade_exits++;
         return signal;
      }
   }
   
   // Note: Time exit checked separately as it needs entry_time
   
   return signal;
}

//+------------------------------------------------------------------+
//| Check Chandelier Exit (ATR-based trailing stop)                |
//+------------------------------------------------------------------+
bool CExitEngine::CheckChandelierExit(
   const string symbol, 
   ENUM_ORDER_TYPE pos_type, 
   double current_price, 
   double &exit_level)
{
   exit_level = CalculateChandelierLevel(symbol, pos_type);
   if(exit_level == 0.0) return false;
   
   if(pos_type == ORDER_TYPE_BUY)
   {
      // Long position: exit if price falls below chandelier support
      return current_price <= exit_level;
   }
   else
   {
      // Short position: exit if price rises above chandelier resistance
      return current_price >= exit_level;
   }
}

//+------------------------------------------------------------------+
//| Calculate Chandelier Exit level                                  |
//+------------------------------------------------------------------+
double CExitEngine::CalculateChandelierLevel(const string symbol, ENUM_ORDER_TYPE pos_type)
{
   // Get highest high or lowest low for lookback period
   double highs[], lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   
   int copied_high = CopyHigh(symbol, PERIOD_CURRENT, 0, CHANDELIER_PERIOD, highs);
   int copied_low = CopyLow(symbol, PERIOD_CURRENT, 0, CHANDELIER_PERIOD, lows);
   
   if(copied_high < CHANDELIER_PERIOD || copied_low < CHANDELIER_PERIOD)
      return 0.0;
   
   // Get ATR from cached handle (no spam)
   double current_atr = GetATRValue(CHANDELIER_PERIOD);
   if(current_atr <= 0.0)
      return 0.0;
   
   if(pos_type == ORDER_TYPE_BUY)
   {
      // For long: Highest High - (ATR * multiplier)
      double highest_high = highs[0];
      for(int i = 1; i < CHANDELIER_PERIOD; i++)
      {
         if(highs[i] > highest_high) highest_high = highs[i];
      }
      
      return highest_high - (current_atr * CHANDELIER_ATR_MULT);
   }
   else
   {
      // For short: Lowest Low + (ATR * multiplier)
      double lowest_low = lows[0];
      for(int i = 1; i < CHANDELIER_PERIOD; i++)
      {
         if(lows[i] < lowest_low) lowest_low = lows[i];
      }
      
      return lowest_low + (current_atr * CHANDELIER_ATR_MULT);
   }
}

//+------------------------------------------------------------------+
//| Check Time-Based Exit (prevent dead money)                      |
//+------------------------------------------------------------------+
bool CExitEngine::CheckTimeExit(const string symbol, datetime entry_time, int min_bars)
{
   if(entry_time == 0) return false;
   
   int bars_since_entry = GetBarsSinceEntry(entry_time);
   
   if(bars_since_entry >= min_bars)
   {
      // Check if position is not profitable (optional: could also exit regardless)
      // For now, we exit if time threshold is met
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check Structure Break Exit                                      |
//+------------------------------------------------------------------+
bool CExitEngine::CheckStructureBreak(const string symbol, ENUM_ORDER_TYPE pos_type)
{
   // Detect swing points
   int swing_bars = 5; // Look left and right for swing detection
   
   double highs[], lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   
   int copied = CopyHigh(symbol, PERIOD_CURRENT, 0, swing_bars * 3, highs);
   if(copied < swing_bars * 3) return false;
   
   copied = CopyLow(symbol, PERIOD_CURRENT, 0, swing_bars * 3, lows);
   if(copied < swing_bars * 3) return false;
   
   if(pos_type == ORDER_TYPE_BUY)
   {
      // For long: check if recent low broke below previous swing low
      double current_low = lows[0];
      double prev_swing_low = lows[swing_bars];
      
      // Confirm with multiple swings
      int break_count = 0;
      for(int i = 0; i < STRUCTURE_BREAK_SENSITIVITY; i++)
      {
         if(current_low < lows[swing_bars + i]) break_count++;
      }
      
      return (break_count >= STRUCTURE_BREAK_SENSITIVITY);
   }
   else
   {
      // For short: check if recent high broke above previous swing high
      double current_high = highs[0];
      double prev_swing_high = highs[swing_bars];
      
      int break_count = 0;
      for(int i = 0; i < STRUCTURE_BREAK_SENSITIVITY; i++)
      {
         if(current_high > highs[swing_bars + i]) break_count++;
      }
      
      return (break_count >= STRUCTURE_BREAK_SENSITIVITY);
   }
}

//+------------------------------------------------------------------+
//| Check Profit Fade (momentum exhaustion)                         |
//+------------------------------------------------------------------+
bool CExitEngine::CheckProfitFade(const string symbol, ENUM_ORDER_TYPE pos_type)
{
   // Use RSI from cached handle (no spam)
   double current_rsi, prev_rsi;
   if(!GetRSIValues(current_rsi, prev_rsi))
      return false;
   
   if(pos_type == ORDER_TYPE_BUY)
   {
      // Long: look for RSI divergence or drop from overbought
      if(prev_rsi >= 70 && current_rsi < PROFIT_FADE_THRESHOLD * 100)
         return true;
   }
   else
   {
      // Short: look for RSI divergence or rise from oversold
      if(prev_rsi <= 30 && current_rsi > (1.0 - PROFIT_FADE_THRESHOLD) * 100)
         return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Get number of bars since entry                                   |
//+------------------------------------------------------------------+
int CExitEngine::GetBarsSinceEntry(datetime entry_time)
{
   if(entry_time == 0) return 0;
   
   datetime current_bar_time = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(current_bar_time == 0) return 0;
   
   int bar_index = iBarShift(_Symbol, PERIOD_CURRENT, entry_time);
   if(bar_index == -1) return 0;
   
   return bar_index;
}

//+------------------------------------------------------------------+
//| Print performance statistics                                     |
//+------------------------------------------------------------------+
void CExitEngine::PrintStats()
{
   Shutdown(); // Reuse shutdown stats
}

#endif // PASR_EXIT_ENGINE_MQH
