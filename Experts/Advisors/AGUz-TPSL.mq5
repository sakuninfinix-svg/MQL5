//+------------------------------------------------------------------+
//|                               AguzAutoSLnTP_ATR_Magic.mq5      |
//|                              Copyright @2026, Perplexity Pro   |
//|                                             https://perplexity.ai |
//+------------------------------------------------------------------+
#property copyright "Copyright @2026, Perplexity"
#property version   "2.09"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

enum ENUM_CHARTSYMBOL { CurrentChartSymbol=0, AllOpenPositions=1 };
enum ENUM_SLTP_MODE { Server=0, Client=1 };
enum ENUM_LOCKPROFIT_ENABLE { LP_DISABLE=0, LP_ENABLE=1 };
enum ENUM_TRAILINGSTOP_METHOD { TS_NONE=0, TS_CLASSIC=1, TS_STEP_DISTANCE=2, TS_STEP_BY_STEP=3 };

// === SIGNAL INPUTS ===
sinput string note_signal = "=== SIGNAL SETTINGS ===";
input double LotSize = 0.01;              // Lot Size
input int    FastMA_Period = 10;          // Fast MA Period
input int    SlowMA_Period = 20;          // Slow MA Period
input int    TrendMA_Period = 100;        // Trend MA Period
input bool   UseSignalInTester = true;    // Enable Signal in Backtest

// === TP/SL INPUTS (sama seperti sebelumnya) ===
sinput string note1=""; 
input double ATR_SL_Multiplier=1.5;    // ATR Multiplier for SL (0=Fixed)
input double ATR_TP_Multiplier=3.0;    // ATR Multiplier for TP (0=Fixed)
input int    ATR_Period=14;            // ATR Period
input int    Fixed_SL_Points=250;      // Fixed SL if Multiplier=0
input int    Fixed_TP_Points=500;      // Fixed TP if Multiplier=0
input ENUM_SLTP_MODE SLnTPMode=Client; // SL & TP Mode

sinput string note2=""; 
input ENUM_LOCKPROFIT_ENABLE LockProfitEnable=LP_ENABLE; // Enable/Disable Profit Lock
input int    LockProfitAfter=100;      // Target Points to Lock Profit
input int    ProfitLock=60;            // Profit To Lock

sinput string note3=""; 
input ENUM_TRAILINGSTOP_METHOD TrailingStopMethod=TS_NONE; // Trailing Method
input int    TrailingStop=50;          // Trailing Stop Points
input int    TrailingStep=10;          // Trailing Stop Step

sinput string note4=""; 
input long   MagicNumber=123456;       // Magic Number (0=All Positions)
input ENUM_CHARTSYMBOL ChartSymbolSelection=AllOpenPositions; // Chart Selection
input bool   inpEnableAlert=false;     // Enable Alert

int atr_handle, fast_ma_handle, slow_ma_handle, trend_ma_handle;

//+------------------------------------------------------------------+ Get ATR
double GetATR(string symbol, int shift=0) {
   double atr[1]; 
   if(CopyBuffer(atr_handle, 0, shift, 1, atr) <= 0) return 0;
   return atr[0];
}

//+------------------------------------------------------------------+ Count positions dengan MAGIC filter
int CalculateCurrentPositions() {
   int buys=0, sells=0;
   for(int i=PositionsTotal()-1; i>=0; i--) {
      ulong t=PositionGetTicket(i); if(t<=0) continue;
      long pos_magic = PositionGetInteger(POSITION_MAGIC);
      if(MagicNumber != 0 && pos_magic != MagicNumber) continue;
      if(ChartSymbolSelection==CurrentChartSymbol && PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) buys++;
      else if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL) sells++;
   }
   return buys>0 ? buys : -sells;
}

//+------------------------------------------------------------------+ Lock Profit dengan MAGIC
bool LockProfit(ulong ticket, int target_points, int locked_points) {
   if(LockProfitEnable==LP_DISABLE || target_points==0 || locked_points==0) return false;
   if(!PositionSelectByTicket(ticket)) return false;
   long pos_magic = PositionGetInteger(POSITION_MAGIC);
   if(MagicNumber != 0 && pos_magic != MagicNumber) return false;
   
   string sym = PositionGetString(POSITION_SYMBOL);
   double op = PositionGetDouble(POSITION_PRICE_OPEN), current_sl = PositionGetDouble(POSITION_SL);
   if(current_sl == 0) current_sl = op;
   double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
   int dig = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK), bid = SymbolInfoDouble(sym, SYMBOL_BID);
   ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double profit_points = ptype == POSITION_TYPE_BUY ? (bid - op)/pt : (op - ask)/pt;
   
   double psl = 0;
   if(ptype == POSITION_TYPE_BUY && profit_points >= target_points && current_sl <= op)
      psl = NormalizeDouble(op + locked_points * pt, dig);
   else if(ptype == POSITION_TYPE_SELL && profit_points >= target_points && current_sl >= op)
      psl = NormalizeDouble(op - locked_points * pt, dig);
   else return false;
   
   if(trade.PositionModify(ticket, psl, PositionGetDouble(POSITION_TP))) {
      Print("Profit Lock #", ticket, " SL=", psl);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+ Trailing Stop dengan MAGIC
bool TrailingStopFunc(ulong ticket, int trail_points, int step, ENUM_TRAILINGSTOP_METHOD method) {
   if(trail_points == 0) return false;
   if(!PositionSelectByTicket(ticket)) return false;
   long pos_magic = PositionGetInteger(POSITION_MAGIC);
   if(MagicNumber != 0 && pos_magic != MagicNumber) return false;
   
   string sym = PositionGetString(POSITION_SYMBOL);
   double op = PositionGetDouble(POSITION_PRICE_OPEN), current_sl = PositionGetDouble(POSITION_SL);
   if(current_sl == 0) current_sl = op;
   double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
   int dig = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double minlevel = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * pt;
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK), bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double tsl = 0;
   
   trail_points += (int)(minlevel / pt);
   ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double profit_points = ptype == POSITION_TYPE_BUY ? (bid - op)/pt : (op - ask)/pt;
   
   if(profit_points > trail_points) {
      if(ptype == POSITION_TYPE_BUY && (bid - current_sl)/pt >= trail_points) {
         if(current_sl < op) current_sl = op;
         switch(method) {
            case TS_CLASSIC:        tsl = NormalizeDouble(bid - trail_points * pt, dig); break;
            case TS_STEP_DISTANCE:  tsl = NormalizeDouble(bid - (trail_points - step) * pt, dig); break;
            case TS_STEP_BY_STEP:   tsl = NormalizeDouble(current_sl + step * pt, dig); break;
         }
      } else if(ptype == POSITION_TYPE_SELL && (current_sl - ask)/pt >= trail_points) {
         if(current_sl > op) current_sl = op;
         switch(method) {
            case TS_CLASSIC:        tsl = NormalizeDouble(ask + trail_points * pt, dig); break;
            case TS_STEP_DISTANCE:  tsl = NormalizeDouble(ask + (trail_points - step) * pt, dig); break;
            case TS_STEP_BY_STEP:   tsl = NormalizeDouble(current_sl - step * pt, dig); break;
         }
      }
   }
   if(tsl == 0) return false;
   if(trade.PositionModify(ticket, tsl, PositionGetDouble(POSITION_TP))) {
      Print("Trailing Stop #", ticket, " SL=", tsl);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+ Set SL/TP dengan MAGIC
void SetSLnTP() {
   double atr = GetATR(_Symbol);
   double sl_points = ATR_SL_Multiplier > 0 ? ATR_SL_Multiplier * atr / _Point : Fixed_SL_Points;
   double tp_points = ATR_TP_Multiplier > 0 ? ATR_TP_Multiplier * atr / _Point : Fixed_TP_Points;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i); if(ticket <= 0) continue;
      long pos_magic = PositionGetInteger(POSITION_MAGIC);
      if(MagicNumber != 0 && pos_magic != MagicNumber) continue;
      if(ChartSymbolSelection == CurrentChartSymbol && PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      
      string sym = PositionGetString(POSITION_SYMBOL);
      double op = PositionGetDouble(POSITION_PRICE_OPEN);
      double curr_sl = PositionGetDouble(POSITION_SL), curr_tp = PositionGetDouble(POSITION_TP);
      double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
      int dig = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      double minlevel = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * pt;
      double ask = SymbolInfoDouble(sym, SYMBOL_ASK), bid = SymbolInfoDouble(sym, SYMBOL_BID);
      
      ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double close_price = ptype == POSITION_TYPE_BUY ? bid : ask;
      double points = ptype == POSITION_TYPE_BUY ? (close_price - op)/pt : (op - close_price)/pt;
      
      // Server Mode
      if(SLnTPMode == Server) {
         double new_sl = 0, new_tp = 0;
         if(ptype == POSITION_TYPE_BUY) {
            new_sl = sl_points > 0 ? NormalizeDouble(op - (sl_points + minlevel/pt) * pt, dig) : 0;
            new_tp = tp_points > 0 ? NormalizeDouble(op + (tp_points + minlevel/pt) * pt, dig) : 0;
         } else {
            new_sl = sl_points > 0 ? NormalizeDouble(op + (sl_points + minlevel/pt) * pt, dig) : 0;
            new_tp = tp_points > 0 ? NormalizeDouble(op - (tp_points + minlevel/pt) * pt, dig) : 0;
         }
         if(curr_sl == 0 || curr_tp == 0) {
            trade.PositionModify(ticket, new_sl, new_tp);
         }
      }
      // Client/Hidden Mode
      else if(SLnTPMode == Client) {
         bool hit_tp = tp_points > 0 && points >= tp_points;
         bool hit_sl = sl_points > 0 && points <= -sl_points;
         if(hit_tp || hit_sl) {
            if(trade.PositionClose(ticket, 3)) {
               if(inpEnableAlert) {
                  Alert("Virtual ", hit_tp ? "TP" : "SL", " #", ticket, " Points=", DoubleToString(points, 0));
               }
            }
         }
      }
      
      // Profit Lock & Trailing
      if(LockProfitAfter > 0 && ProfitLock > 0 && points >= LockProfitAfter) {
         if(points <= LockProfitAfter + TrailingStop)
            LockProfit(ticket, LockProfitAfter, ProfitLock);
         else
            TrailingStopFunc(ticket, TrailingStop, TrailingStep, TrailingStopMethod);
      } else if(LockProfitAfter == 0) {
         TrailingStopFunc(ticket, TrailingStop, TrailingStep, TrailingStopMethod);
      }
   }
}

//+------------------------------------------------------------------+ OnInit
int OnInit() {
   atr_handle = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   if(atr_handle == INVALID_HANDLE) {
      Print("Error creating ATR handle");
      return INIT_FAILED;
   }
   trade.SetExpertMagicNumber(MagicNumber);
   Print("EA started. Magic: ", MagicNumber, " ATR Period: ", ATR_Period);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+ OnDeinit
void OnDeinit(const int reason) {
   IndicatorRelease(atr_handle);
}

//+------------------------------------------------------------------+ OnTick
void OnTick() {
   if(Bars(_Symbol, PERIOD_CURRENT) < 100 || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return;
   if(CalculateCurrentPositions() != 0) SetSLnTP();
}
