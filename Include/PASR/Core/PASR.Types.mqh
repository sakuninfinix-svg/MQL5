//+------------------------------------------------------------------+
//|                                             PASR.Types.mqh         |
//|                        Institutional Architecture - Core Types     |
//|                        (c) 2026 PASR Quant Development             |
//+------------------------------------------------------------------+
#property copyright "PASR Quant Team"
#property link      "https://pasr.quant"
#property version   "10.01"
#property description "Centralized state encapsulation for institutional architecture"

#ifndef __PASR_TYPES_MQH__
#define __PASR_TYPES_MQH__

#include <PASR/Core/ConfigTypes.mqh>

//+------------------------------------------------------------------+
//| Trading Context - Single Source of Truth for Runtime State       |
//| Encapsulates ALL mutable EA state in one structure               |
//+------------------------------------------------------------------+
struct STradingContext
  {
   //--- Core State
   bool              initialized;         // EA fully initialized flag
   bool              is_active;           // Trading enabled/disabled
   datetime          last_bar_time;       // Last processed bar time
   datetime          pos_open_time;       // Position open time
   ulong             open_ticket;         // Current position ticket
   
   //--- Market State
   ENUM_MARKET_REGIME  regime;            // Current market regime
   ENUM_TRADING_SESSION session;          // Current trading session
   double            current_spread;      // Current spread in pips
   double            current_atr;         // Current ATR value
   
   //--- Signal State
   bool              has_signal;          // Active signal flag
   TradeSignal       active_signal;       // Current active signal
   FeatureVector     last_fv;             // Last feature vector
   double            last_ai_score;       // Last AI score
   double            last_drift;          // Last drift score
   int               last_ens_model;      // Last ensemble model ID
   
   //--- Trade Plan State
   bool              has_plan;            // Active trade plan flag
   TradePlan         active_plan;         // Current trade plan
   
   //--- Position State
   bool              has_position;        // Has open position flag
   int               position_direction;  // Position direction
   double            position_entry;      // Position entry price
   double            position_sl;         // Position stop loss
   double            position_tp1;        // Position TP1
   double            position_tp2;        // Position TP2
   double            position_lots;       // Position volume
   double            position_pnl;        // Floating P&L
   bool              be_done;             // Break-even executed
   bool              partial_done;        // Partial close executed
   
   //--- Dashboard Context (cached for UI)
   DashContext       dash_ctx;            // Dashboard rendering context
   
   //--- Performance Metrics
   #ifdef PERF_METRICS
   ulong             tick_count;          // Total ticks processed
   ulong             bar_count;           // Total bars processed
   ulong             signal_count;        // Signals generated
   datetime          last_tick_time;      // For tick rate calculation
   #endif
   
   //--- QA State
   // BUG-016 FIX: was #ifdef QA_BUILD — must match PASR_MODULAR.mq5
   // which defines PASR_QA_BUILD (Sprint 1 fix). Changed throughout.
   #ifdef PASR_QA_BUILD
   int               tick_counter;        // Tick counter for chaos
   bool              chaos_active;        // Chaos mode active
   double            normal_spread;       // Baseline spread
   ulong             alloc_count;         // Allocation counter
   datetime          last_chaos_time;     // Last chaos trigger time
   #endif
   
   //--- Constructor
   STradingContext()
     {
      Reset();
     }
   
   //--- Full Reset
   void Reset()
     {
      // Core State
      initialized        = false;
      is_active          = true;
      last_bar_time      = 0;
      pos_open_time      = 0;
      open_ticket        = 0;
      
      // Market State
      regime             = REGIME_RANGING;
      session            = SESSION_OFF;
      current_spread     = 0.0;
      current_atr        = 0.0;
      
      // Signal State
      has_signal         = false;
      ZeroMemory(active_signal);
      ZeroMemory(last_fv);
      last_ai_score      = 0.0;
      last_drift         = 0.0;
      last_ens_model     = 0;
      
      // Trade Plan State
      has_plan           = false;
      ZeroMemory(active_plan);
      
      // Position State
      has_position       = false;
      position_direction = 0;
      position_entry     = 0.0;
      position_sl        = 0.0;
      position_tp1       = 0.0;
      position_tp2       = 0.0;
      position_lots      = 0.0;
      position_pnl       = 0.0;
      be_done            = false;
      partial_done       = false;
      
      // Dashboard
      ZeroMemory(dash_ctx);
      
      // Performance Metrics
      #ifdef PERF_METRICS
      tick_count         = 0;
      bar_count          = 0;
      signal_count       = 0;
      last_tick_time     = 0;
      #endif
      
      // QA State — BUG-016 FIX
      #ifdef PASR_QA_BUILD
      tick_counter       = 0;
      chaos_active       = false;
      normal_spread      = 0.0;
      alloc_count        = 0;
      last_chaos_time    = 0;
      #endif
     }
   
   //--- Validation Helpers
   bool IsValid() const { return initialized && is_active; }

   // CanTrade: standard entry — no open position.
   bool CanTrade() const { return is_active && !has_position && has_signal; }

   // BUG-017: CanTradePartial() — allows second entry when first TP
   // was hit (partial_done=true) but position is still open.
   // Used by RecoveryManager and SignalManager for scale-in logic.
   bool CanTradePartial() const
     { return is_active && has_position && partial_done && has_signal; }

   bool HasOpenPosition() const { return has_position && open_ticket > 0; }
   
   //--- State Update Helpers
   void SetInitialized(bool val) { initialized = val; }
   void SetActive(bool val) { is_active = val; }
   void SetRegime(ENUM_MARKET_REGIME r) { regime = r; }
   void SetSession(ENUM_TRADING_SESSION s) { session = s; }
   
   //--- Clear Signal State
   void ClearSignal()
     {
      has_signal     = false;
      ZeroMemory(active_signal);
      last_ai_score  = 0.0;
      last_drift     = 0.0;
     }
   
   //--- Clear Plan State
   void ClearPlan()
     {
      has_plan       = false;
      ZeroMemory(active_plan);
     }
   
   //--- Clear Position State
   void ClearPosition()
     {
      has_position       = false;
      position_direction = 0;
      position_entry     = 0.0;
      position_sl        = 0.0;
      position_tp1       = 0.0;
      position_tp2       = 0.0;
      position_lots      = 0.0;
      position_pnl       = 0.0;
      be_done            = false;
      partial_done       = false;
      open_ticket        = 0;
      pos_open_time      = 0;
     }
  };

//+------------------------------------------------------------------+
//| Initialization Phase Enum - For Fail-Fast Boot Sequence          |
//+------------------------------------------------------------------+
enum ENUM_INIT_PHASE
  {
   INIT_PHASE_NONE       = 0,  // Not started
   INIT_PHASE_CORE       = 1,  // Core system (timer, handles, globals)
   INIT_PHASE_MARKETDATA = 2,  // Market data (symbols, feeds)
   INIT_PHASE_STRATEGY   = 3,  // Strategy engine (SR, Pattern, AI)
   INIT_PHASE_EXECUTION  = 4,  // Execution layer (executor, risk)
   INIT_PHASE_COMPLETE   = 5   // Fully initialized
  };

//+------------------------------------------------------------------+
//| Initialization Result Structure                                  |
//+------------------------------------------------------------------+
struct SInitResult
  {
   ENUM_INIT_PHASE  phase;       // Phase where init occurred
   bool             success;     // Overall success flag
   string           module;      // Module name that failed
   string           error_msg;   // Error message if failed
   
   SInitResult()
     {
      phase     = INIT_PHASE_NONE;
      success   = true;
      module    = "";
      error_msg = "";
     }
   
   void Fail(ENUM_INIT_PHASE p, string mod, string err)
     {
      phase     = p;
      success   = false;
      module    = mod;
      error_msg = err;
     }
   
   bool IsSuccess() const { return success; }

   // BUG-018 FIX: Use string concatenation instead of StringFormat.
   // StringFormat misparses if module/error_msg contain '%' characters
   // (e.g. from file paths, percent-formatted values in error strings).
   string ToString() const
     {
      if(success) return "INIT_OK";
      return "INIT_FAILED@Phase" + IntegerToString((int)phase)
             + ":" + module + " - " + error_msg;
     }
  };

#endif // __PASR_TYPES_MQH__
//+------------------------------------------------------------------+
//| END OF PASR.Types.mqh                                            |
//+------------------------------------------------------------------+
