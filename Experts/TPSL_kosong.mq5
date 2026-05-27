//+------------------------------------------------------------------+
//|                               AguzAutoSLnTP_ATR_Magic.mq5        |
//|                              Copyright @2026, Perplexity Pro     |
//+------------------------------------------------------------------+
#property copyright "Copyright @2026, Perplexity"
#property version "2.10 Magic + ATR Full"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

enum ENUM_CHARTSYMBOL
  {
   CurrentChartSymbol = 0,
   AllOpenPositions = 1
  };

enum ENUM_SLTP_MODE
  {
   Server = 0,
   Client = 1
  };

enum ENUM_LOCKPROFIT_ENABLE
  {
   LP_DISABLE = 0,
   LP_ENABLE = 1
  };

enum ENUM_TRAILINGSTOP_METHOD
  {
   TS_NONE = 0,
   TS_CLASSIC = 1,
   TS_STEP_DISTANCE = 2,
   TS_STEP_BY_STEP = 3
  };

input string note1 = "";
input double ATR_SL_Multiplier = 1.5;
input double ATR_TP_Multiplier = 3.0;
input int ATR_Period = 14;
input int Fixed_SL_Points = 250;
input int Fixed_TP_Points = 500;
input ENUM_SLTP_MODE SLnTPMode = Client;

input string note2 = "";
input ENUM_LOCKPROFIT_ENABLE LockProfitEnable = LP_ENABLE;
input int LockProfitAfter = 100;
input int ProfitLock = 60;

input string note3 = "";
input ENUM_TRAILINGSTOP_METHOD TrailingStopMethod = TS_NONE;
input int TrailingStop = 50;
input int TrailingStep = 10;

input string note4 = "";
input long MagicNumber = 123456;
input ENUM_CHARTSYMBOL ChartSymbolSelection = AllOpenPositions;
input bool inpEnableAlert = false;

int atr_handle = INVALID_HANDLE;

double GetATR(string symbol, int shift = 0)
  {
   double atr[1];
   if(atr_handle == INVALID_HANDLE) return 0.0;
   if(CopyBuffer(atr_handle, 0, shift, 1, atr) <= 0) return 0.0;
   return atr[0];
  }

bool SelectManagedPositionByIndex(const int index, ulong &ticket)
  {
   ticket = PositionGetTicket(index);
   if(ticket == 0) return false;
   if(!PositionSelectByTicket(ticket)) return false;
   long pos_magic = PositionGetInteger(POSITION_MAGIC);
   if(MagicNumber != 0 && pos_magic != MagicNumber) return false;
   if(ChartSymbolSelection == CurrentChartSymbol && PositionGetString(POSITION_SYMBOL) != _Symbol) return false;
   return true;
  }

int CalculateCurrentPositions()
  {
   int buys = 0, sells = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = 0;
      if(!SelectManagedPositionByIndex(i, ticket)) continue;
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(type == POSITION_TYPE_BUY) buys++;
      else if(type == POSITION_TYPE_SELL) sells++;
     }
   return buys > 0 ? buys : -sells;
  }

bool LockProfit(ulong ticket, int target_points, int locked_points)
  {
   if(LockProfitEnable == LP_DISABLE || target_points == 0 || locked_points == 0) return false;
   if(!PositionSelectByTicket(ticket)) return false;
   long pos_magic = PositionGetInteger(POSITION_MAGIC);
   if(MagicNumber != 0 && pos_magic != MagicNumber) return false;

   string sym = PositionGetString(POSITION_SYMBOL);
   double op = PositionGetDouble(POSITION_PRICE_OPEN);
   double current_sl = PositionGetDouble(POSITION_SL);
   if(current_sl == 0.0) current_sl = op;
   double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
   int dig = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double profit_points = ptype == POSITION_TYPE_BUY ? (bid - op) / pt : (op - ask) / pt;

   double psl = 0.0;
   if(ptype == POSITION_TYPE_BUY && profit_points >= target_points && current_sl <= op)
      psl = NormalizeDouble(op + locked_points * pt, dig);
   else if(ptype == POSITION_TYPE_SELL && profit_points >= target_points && current_sl >= op)
      psl = NormalizeDouble(op - locked_points * pt, dig);
   else
      return false;

   if(trade.PositionModify(ticket, psl, PositionGetDouble(POSITION_TP)))
     {
      Print("Profit Lock #", ticket, " SL=", psl);
      return true;
     }
   return false;
  }

bool TrailingStopFunc(ulong ticket, int trail_points, int step, ENUM_TRAILINGSTOP_METHOD method)
  {
   if(trail_points == 0 || method == TS_NONE) return false;
   if(!PositionSelectByTicket(ticket)) return false;
   long pos_magic = PositionGetInteger(POSITION_MAGIC);
   if(MagicNumber != 0 && pos_magic != MagicNumber) return false;

   string sym = PositionGetString(POSITION_SYMBOL);
   double op = PositionGetDouble(POSITION_PRICE_OPEN);
   double current_sl = PositionGetDouble(POSITION_SL);
   if(current_sl == 0.0) current_sl = op;
   double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
   int dig = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double minlevel = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * pt;
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double tsl = 0.0;

   trail_points += (int)(minlevel / pt);
   ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double profit_points = ptype == POSITION_TYPE_BUY ? (bid - op) / pt : (op - ask) / pt;

   if(profit_points > trail_points)
     {
      if(ptype == POSITION_TYPE_BUY && (bid - current_sl) / pt >= trail_points)
        {
         if(current_sl < op) current_sl = op;
         switch(method)
           {
            case TS_CLASSIC:       tsl = NormalizeDouble(bid - trail_points * pt, dig); break;
            case TS_STEP_DISTANCE: tsl = NormalizeDouble(bid - (trail_points - step) * pt, dig); break;
            case TS_STEP_BY_STEP:  tsl = NormalizeDouble(current_sl + step * pt, dig); break;
            default: break;
           }
        }
      else if(ptype == POSITION_TYPE_SELL && (current_sl - ask) / pt >= trail_points)
        {
         if(current_sl > op) current_sl = op;
         switch(method)
           {
            case TS_CLASSIC:       tsl = NormalizeDouble(ask + trail_points * pt, dig); break;
            case TS_STEP_DISTANCE: tsl = NormalizeDouble(ask + (trail_points - step) * pt, dig); break;
            case TS_STEP_BY_STEP:  tsl = NormalizeDouble(current_sl - step * pt, dig); break;
            default: break;
           }
        }
     }
   if(tsl == 0.0) return false;
   if(trade.PositionModify(ticket, tsl, PositionGetDouble(POSITION_TP)))
     {
      Print("Trailing Stop #", ticket, " SL=", tsl);
      return true;
     }
   return false;
  }

void SetSLnTP()
  {
   double atr = GetATR(_Symbol);
   double sl_points = ATR_SL_Multiplier > 0.0 ? ATR_SL_Multiplier * atr / _Point : Fixed_SL_Points;
   double tp_points = ATR_TP_Multiplier > 0.0 ? ATR_TP_Multiplier * atr / _Point : Fixed_TP_Points;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = 0;
      if(!SelectManagedPositionByIndex(i, ticket)) continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      double op = PositionGetDouble(POSITION_PRICE_OPEN);
      double curr_sl = PositionGetDouble(POSITION_SL);
      double curr_tp = PositionGetDouble(POSITION_TP);
      double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
      int dig = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      double minlevel = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * pt;
      double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
      double bid = SymbolInfoDouble(sym, SYMBOL_BID);

      ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double close_price = ptype == POSITION_TYPE_BUY ? bid : ask;
      double points = ptype == POSITION_TYPE_BUY ? (close_price - op) / pt : (op - close_price) / pt;

      if(SLnTPMode == Server)
        {
         double new_sl = 0.0, new_tp = 0.0;
         if(ptype == POSITION_TYPE_BUY)
           {
            new_sl = sl_points > 0.0 ? NormalizeDouble(op - (sl_points + minlevel / pt) * pt, dig) : 0.0;
            new_tp = tp_points > 0.0 ? NormalizeDouble(op + (tp_points + minlevel / pt) * pt, dig) : 0.0;
           }
         else
           {
            new_sl = sl_points > 0.0 ? NormalizeDouble(op + (sl_points + minlevel / pt) * pt, dig) : 0.0;
            new_tp = tp_points > 0.0 ? NormalizeDouble(op - (tp_points + minlevel / pt) * pt, dig) : 0.0;
           }
         if(curr_sl == 0.0 || curr_tp == 0.0) trade.PositionModify(ticket, new_sl, new_tp);
        }
      else if(SLnTPMode == Client)
        {
         bool hit_tp = tp_points > 0.0 && points >= tp_points;
         bool hit_sl = sl_points > 0.0 && points <= -sl_points;
         if(hit_tp || hit_sl)
           {
            if(trade.PositionClose(ticket, 3) && inpEnableAlert)
               Alert("Virtual ", hit_tp ? "TP" : "SL", " #", ticket, " Points=", DoubleToString(points, 0));
           }
        }

      if(LockProfitAfter > 0 && ProfitLock > 0 && points >= LockProfitAfter)
        {
         if(points <= LockProfitAfter + TrailingStop) LockProfit(ticket, LockProfitAfter, ProfitLock);
         else TrailingStopFunc(ticket, TrailingStop, TrailingStep, TrailingStopMethod);
        }
      else if(LockProfitAfter == 0)
        {
         TrailingStopFunc(ticket, TrailingStop, TrailingStep, TrailingStopMethod);
        }
     }
  }

int OnInit()
  {
   atr_handle = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   if(atr_handle == INVALID_HANDLE)
     {
      Print("Error creating ATR handle");
      return INIT_FAILED;
     }
   trade.SetExpertMagicNumber(MagicNumber);
   Print("EA started. Magic: ", MagicNumber, " ATR Period: ", ATR_Period);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(atr_handle != INVALID_HANDLE) IndicatorRelease(atr_handle);
  }

void OnTick()
  {
   if(Bars(_Symbol, PERIOD_CURRENT) < 100 || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return;
   if(CalculateCurrentPositions() != 0) SetSLnTP();
  }
