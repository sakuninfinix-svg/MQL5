//+------------------------------------------------------------------+
//| ExitEngine.mqh                                             v2.01 |
//| Copyright (C) 2026, PASR Trading System                          |
//| https://pasr.trading                                             |
//|                                                                  |
//| Smart Exit Logic for Position Management                        |
//| - Chandelier Exit (ATR-based trailing stop)                     |
//| - Time-Based Exit (dead money prevention)                       |
//| - Structure Break Exit (swing high/low break)                   |
//| - Profit Fade Exit (momentum exhaustion)                        |
//|                                                                  |
//| CHANGELOG:                                                       |
//|   v2.01 (2026-05-24) Sprint 3A:                                 |
//|     BUG-T12: OnEvent(EMERGENCY_STOP) was re-dispatching the     |
//|              same event → infinite loop until queue overflow.   |
//|              Fix: log only. RecoveryManager handles EMERGENCY   |
//|              independently. ExitEngine does not need to relay.  |
//|   v2.00 (2026-05-24):                                           |
//|   BUG-T01: #include .h → .mqh (compile error fix)              |
//|   BUG-T02: IManager interface mismatch fixed. Now properly      |
//|            integrated with Init()/Deinit()/OnEvent() pipeline.  |
//|   BUG-T03: PROFIT_FADE short threshold tightened (0.35→35pts).  |
//|   BUG-T04: PrintStats() no longer calls Shutdown().            |
//|   BUG-T05: GetBarsSinceEntry() guard improved for early bars.  |
//+------------------------------------------------------------------+
#ifndef PASR_EXIT_ENGINE_MQH
#define PASR_EXIT_ENGINE_MQH

// BUG-T01 FIX: was #include <PASR/Core/IManager.h> — .h does not exist.
#include "../Core/IManager.mqh"
#include "PositionManager.mqh"

//+------------------------------------------------------------------+
//| Exit Configuration Constants                                     |
//+------------------------------------------------------------------+
#define CHANDELIER_ATR_MULT          3.0    // ATR multiplier for chandelier stop
#define CHANDELIER_PERIOD            22     // Lookback for highest high / lowest low
#define TIME_EXIT_BARS               10     // Exit if no profit after N bars
#define PROFIT_FADE_THRESHOLD        70.0   // RSI overbought level (long exit)
// BUG-T03 FIX: Dedicated short-fade threshold
#define PROFIT_FADE_SHORT_THRESHOLD  35.0   // RSI recovery level (short exit)
#define STRUCTURE_BREAK_SENSITIVITY  1      // Swing points to confirm break

//+------------------------------------------------------------------+
//| Exit Reason Enumeration                                          |
//+------------------------------------------------------------------+
enum ExitReason
  {
   EXIT_NONE           = 0,  // No exit signal
   EXIT_CHANDLER_HIT,        // Chandelier trailing stop hit
   EXIT_TIME_EXPIRED,        // Time-based exit triggered
   EXIT_STRUCTURE_BREAK,     // Market structure broken
   EXIT_PROFIT_FADE,         // Momentum exhaustion detected
   EXIT_REVERSAL_SIGNAL,     // Opposite signal generated
   EXIT_EMERGENCY            // Emergency close (circuit breaker)
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
      reason         = EXIT_NONE;
      trigger_price  = 0.0;
      current_profit = 0.0;
      bars_held      = 0;
      description    = "";
     }
  };

//+------------------------------------------------------------------+
//| CExitEngine                                                      |
//| BUG-T02 FIX: Properly extends IManager and implements the       |
//| pipeline interface (Init/Deinit/OnEvent/DeclareEvents).         |
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

   // Cached indicator handles
   int               m_hATR;
   int               m_hRSI;

   bool InitIndicators()
     {
      if(m_hATR == INVALID_HANDLE)
         m_hATR = iATR(_Symbol, PERIOD_CURRENT, CHANDELIER_PERIOD);
      if(m_hRSI == INVALID_HANDLE)
         m_hRSI = iRSI(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
      return (m_hATR != INVALID_HANDLE && m_hRSI != INVALID_HANDLE);
     }

   void CleanupIndicators()
     {
      if(m_hATR != INVALID_HANDLE) { IndicatorRelease(m_hATR); m_hATR = INVALID_HANDLE; }
      if(m_hRSI != INVALID_HANDLE) { IndicatorRelease(m_hRSI); m_hRSI = INVALID_HANDLE; }
     }

   double GetATRValue()
     {
      if(m_hATR == INVALID_HANDLE) return 0.0;
      double buf[1];
      if(CopyBuffer(m_hATR, 0, 0, 1, buf) <= 0) return 0.0;
      return buf[0];
     }

   bool GetRSIValues(double &current, double &prev)
     {
      current = 0.0; prev = 0.0;
      if(m_hRSI == INVALID_HANDLE) return false;
      double buf[2];
      if(CopyBuffer(m_hRSI, 0, 0, 2, buf) < 2) return false;
      current = buf[0]; prev = buf[1];
      return true;
     }

public:
   CExitEngine()
      : IManager(), m_initialized(false),
        m_chandelier_exits(0), m_time_exits(0),
        m_structure_exits(0), m_fade_exits(0),
        m_hATR(INVALID_HANDLE), m_hRSI(INVALID_HANDLE)
     {}

   ~CExitEngine() { CleanupIndicators(); }

   virtual string HandlerName() const override { return "ExitEngine"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      if(!InitIndicators())
        {
         Print("[Exit] Failed to init indicator handles");
         return false;
        }
      m_initialized = true;
      PrintFormat("[Exit] v2.01 Init OK — Chandelier ATR=%.1f Period=%d",
                  CHANDELIER_ATR_MULT, CHANDELIER_PERIOD);
      return true;
     }

   virtual void Deinit() override
     {
      if(!m_initialized) return;
      CleanupIndicators();
      m_initialized = false;
      IManager::Deinit();
     }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_PRICE_UPDATE);
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_EMERGENCY_STOP);
     }

   virtual void OnEvent(const PASREvent &ev) override
     {
      switch(ev.id)
        {
         case EVENT_ID_PRICE_UPDATE: OnPriceUpdate(); break;
         case EVENT_ID_NEW_BAR:      OnNewBar();      break;

         case EVENT_ID_EMERGENCY_STOP:
            // BUG-T12 FIX: Do NOT re-dispatch EVENT_ID_EMERGENCY_STOP.
            // Previous code called DispatchEvent(fwd) with the same event ID,
            // causing an infinite loop: ExitEngine receives → dispatches →
            // EventBus pushes → DrainQueue → ExitEngine receives again...
            // RecoveryManager handles EMERGENCY_STOP independently.
            // ExitEngine only needs to log; actual position close is
            // executed by Stage_PosMgmt + RecoveryManager.
            if(m_debugMode)
               Print("[Exit] EMERGENCY_STOP received — deferring to RecoveryManager.");
            break;

         default: break;
        }
     }

   virtual void OnPriceUpdate() override { /* Chandelier evaluated on-demand via CheckExit() */ }
   virtual void OnNewBar()      override { /* Called externally via CheckExit() on bar close  */ }

   //--- Core exit logic (on-demand, called by Stage_PosMgmt) --------
   ExitSignal CheckExit(const string symbol, ENUM_ORDER_TYPE position_type,
                        double entry_price, double current_price)
     {
      ExitSignal signal;
      signal.Clear();
      if(!m_initialized) return signal;

      double exit_level = 0.0;

      // 1. Chandelier Exit (highest priority — hard trailing stop)
      if(CheckChandelierExit(symbol, position_type, current_price, exit_level))
        {
         signal.reason         = EXIT_CHANDLER_HIT;
         signal.trigger_price  = exit_level;
         signal.current_profit = (position_type == ORDER_TYPE_BUY)
                                 ? current_price - entry_price
                                 : entry_price - current_price;
         signal.description    = StringFormat("Chandelier stop %.5f", exit_level);
         m_chandelier_exits++;
         return signal;
        }

      // 2. Structure Break
      if(CheckStructureBreak(symbol, position_type))
        {
         signal.reason         = EXIT_STRUCTURE_BREAK;
         signal.trigger_price  = current_price;
         signal.current_profit = (position_type == ORDER_TYPE_BUY)
                                 ? current_price - entry_price
                                 : entry_price - current_price;
         signal.description    = "Market structure broken";
         m_structure_exits++;
         return signal;
        }

      // 3. Profit Fade — only exit if in profit
      double profit_pts = (position_type == ORDER_TYPE_BUY)
                          ? current_price - entry_price
                          : entry_price - current_price;
      if(profit_pts > 0 && CheckProfitFade(symbol, position_type))
        {
         signal.reason         = EXIT_PROFIT_FADE;
         signal.trigger_price  = current_price;
         signal.current_profit = profit_pts;
         signal.description    = "Momentum exhaustion";
         m_fade_exits++;
         return signal;
        }

      return signal;
     }

   bool CheckChandelierExit(const string symbol, ENUM_ORDER_TYPE pos_type,
                             double current_price, double &exit_level)
     {
      exit_level = CalculateChandelierLevel(symbol, pos_type);
      if(exit_level == 0.0) return false;
      return (pos_type == ORDER_TYPE_BUY)
             ? current_price <= exit_level
             : current_price >= exit_level;
     }

   double CalculateChandelierLevel(const string symbol, ENUM_ORDER_TYPE pos_type)
     {
      double highs[], lows[];
      ArraySetAsSeries(highs, true);
      ArraySetAsSeries(lows, true);
      if(CopyHigh(symbol, PERIOD_CURRENT, 0, CHANDELIER_PERIOD, highs) < CHANDELIER_PERIOD) return 0.0;
      if(CopyLow (symbol, PERIOD_CURRENT, 0, CHANDELIER_PERIOD, lows)  < CHANDELIER_PERIOD) return 0.0;
      double current_atr = GetATRValue();
      if(current_atr <= 0.0) return 0.0;

      if(pos_type == ORDER_TYPE_BUY)
        {
         double hh = highs[0];
         for(int i = 1; i < CHANDELIER_PERIOD; i++) if(highs[i] > hh) hh = highs[i];
         return hh - (current_atr * CHANDELIER_ATR_MULT);
        }
      else
        {
         double ll = lows[0];
         for(int i = 1; i < CHANDELIER_PERIOD; i++) if(lows[i] < ll) ll = lows[i];
         return ll + (current_atr * CHANDELIER_ATR_MULT);
        }
     }

   bool CheckTimeExit(const string symbol, datetime entry_time, int min_bars)
     {
      if(entry_time == 0) return false;
      return (GetBarsSinceEntry(entry_time) >= min_bars);
     }

   bool CheckStructureBreak(const string symbol, ENUM_ORDER_TYPE pos_type)
     {
      int swing_bars = 5;
      int needed     = swing_bars * 3;
      double highs[], lows[];
      ArraySetAsSeries(highs, true);
      ArraySetAsSeries(lows,  true);
      if(CopyHigh(symbol, PERIOD_CURRENT, 0, needed, highs) < needed) return false;
      if(CopyLow (symbol, PERIOD_CURRENT, 0, needed, lows)  < needed) return false;

      if(pos_type == ORDER_TYPE_BUY)
        {
         int cnt = 0;
         for(int i = 0; i < STRUCTURE_BREAK_SENSITIVITY; i++)
            if(lows[0] < lows[swing_bars + i]) cnt++;
         return cnt >= STRUCTURE_BREAK_SENSITIVITY;
        }
      else
        {
         int cnt = 0;
         for(int i = 0; i < STRUCTURE_BREAK_SENSITIVITY; i++)
            if(highs[0] > highs[swing_bars + i]) cnt++;
         return cnt >= STRUCTURE_BREAK_SENSITIVITY;
        }
     }

   bool CheckProfitFade(const string symbol, ENUM_ORDER_TYPE pos_type)
     {
      double cur, prv;
      if(!GetRSIValues(cur, prv)) return false;

      if(pos_type == ORDER_TYPE_BUY)
         return (prv >= 70.0 && cur < PROFIT_FADE_THRESHOLD);
      else
         return (prv <= 30.0 && cur > PROFIT_FADE_SHORT_THRESHOLD);
     }

   // BUG-T05 FIX: Guard for early-bar iBarShift returning -1.
   int GetBarsSinceEntry(datetime entry_time)
     {
      if(entry_time == 0) return 0;
      int idx = iBarShift(_Symbol, PERIOD_CURRENT, entry_time);
      return (idx < 0) ? 0 : idx;
     }

   // BUG-T04 FIX: PrintStats() no longer calls Shutdown().
   void PrintStats()
     {
      ulong total = m_chandelier_exits + m_time_exits
                    + m_structure_exits + m_fade_exits;
      PrintFormat("[Exit] === STATS === Chandelier:%d Time:%d Structure:%d Fade:%d Total:%d",
                  m_chandelier_exits, m_time_exits,
                  m_structure_exits,  m_fade_exits, total);
     }
  };

#endif // PASR_EXIT_ENGINE_MQH
