//+------------------------------------------------------------------+
//|                            PASR V1.mq5                           |
//|                  Copyright 2026, Agsicentre                      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "1.01"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

input group "== Market Filters ==" input double InpMinATR = 10.0;
input double InpMaxSpread = 20.0;
input string InpTradingSession = "14:00-21:00";
input bool UseNewsFilter = true;
input int NewsFreezeMinutes = 30;
input bool BlockHigh = true;
input bool BlockMedium = true;

input group "== S&R & Price Action ==" input int InpSRLookback = 20;
input double InpMinWickRatio = 60.0;
input double InpAntiBreakoutPct = 0.7;
input int InpBufferPoints = 20;

input group "== Multi-Timeframe (MTF) ==" input bool InpUseMTF = true;
input ENUM_TIMEFRAMES InpHTF = PERIOD_H1;
input int InpHTFLookback = 50;

input group "== Risk Management ==" input double InpLotSize = 0.01;
input double InpPartialClosePct = 50.0;
input bool InpUseTrailing = true;
input int InpTrailingStart = 50;
input int InpTrailingStep = 20;

input group "== Hedging Recovery ==" input bool InpUseHedging = true;
input double InpHedgeMult = 1.5;

input group "== System ==" input long InpMagicNum = 20260403;
input bool InpSendPush = true;

double targetSupport, targetResistance;
double htfSupport, htfResistance;
string newsStatus = "Normal";
datetime nextNewsTime = 0;

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNum);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ObjectDelete(0, "ResLine");
   ObjectDelete(0, "SupLine");
   if(InpSendPush)
   {
      string deinitReason = "";
      switch(reason)
      {
         case REASON_PROGRAM:     deinitReason = "User removed"; break;
         case REASON_REMOVE:      deinitReason = "Chart removed"; break;
         case REASON_RECOMPILE:   deinitReason = "Recompiled"; break;
         case REASON_CHARTCHANGE: deinitReason = "Chart changed"; break;
         default:                 deinitReason = "Other"; break;
      }
      SendNotification("EA PASR Deinitialized: " + deinitReason);
   }
}

bool IsNewsTime()
{
   if(!UseNewsFilter) return false;

   MqlCalendarValue values[];
   datetime timeFrom = TimeCurrent() - (NewsFreezeMinutes * 60);
   datetime timeTo = TimeCurrent() + (NewsFreezeMinutes * 60);
   string currencies[2];
   currencies[0] = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
   currencies[1] = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);

   for(int c = 0; c < 2; c++)
   {
      if(CalendarValueHistory(values, timeFrom, timeTo, NULL, currencies[c]) <= 0) continue;
      for(int i = 0; i < ArraySize(values); i++)
      {
         MqlCalendarEvent event;
         if(!CalendarEventById(values[i].event_id, event)) continue;
         bool isHigh = (event.importance == CALENDAR_IMPORTANCE_HIGH && BlockHigh);
         bool isMedium = (event.importance == CALENDAR_IMPORTANCE_MODERATE && BlockMedium);
         if(isHigh || isMedium)
         {
            nextNewsTime = values[i].time;
            newsStatus = "NEWS ACTIVE: " + event.name;
            return true;
         }
      }
   }
   newsStatus = "Market Clear";
   return false;
}

void OnTick()
{
   if(!IsNewCandle()) return;
   if(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpread) return;

   UpdateSRLevels();
   if(InpUseMTF) UpdateHTFLevels();
   ManagePositions();
   if(PositionsTotal() == 0) CheckEntrySignals();
   DrawDashboard();
}

int HighestHighIndex(const string symbol, ENUM_TIMEFRAMES tf, int count, int start)
{
   int idx = iHighest(symbol, tf, MODE_HIGH, count, start);
   return (idx >= 0) ? idx : -1;
}

int LowestLowIndex(const string symbol, ENUM_TIMEFRAMES tf, int count, int start)
{
   int idx = iLowest(symbol, tf, MODE_LOW, count, start);
   return (idx >= 0) ? idx : -1;
}

void UpdateSRLevels()
{
   int highestIdx = HighestHighIndex(_Symbol, _Period, InpSRLookback, 1);
   int lowestIdx = LowestLowIndex(_Symbol, _Period, InpSRLookback, 1);

   if(highestIdx >= 0) targetResistance = iHigh(_Symbol, _Period, highestIdx);
   if(lowestIdx >= 0) targetSupport = iLow(_Symbol, _Period, lowestIdx);

   ObjectCreate(0, "ResLine", OBJ_HLINE, 0, 0, targetResistance);
   ObjectSetInteger(0, "ResLine", OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, "ResLine", OBJPROP_STYLE, STYLE_DOT);

   ObjectCreate(0, "SupLine", OBJ_HLINE, 0, 0, targetSupport);
   ObjectSetInteger(0, "SupLine", OBJPROP_COLOR, clrAqua);
   ObjectSetInteger(0, "SupLine", OBJPROP_STYLE, STYLE_DOT);
}

void UpdateHTFLevels()
{
   int highestIdx = HighestHighIndex(_Symbol, InpHTF, InpHTFLookback, 1);
   int lowestIdx = LowestLowIndex(_Symbol, InpHTF, InpHTFLookback, 1);

   if(highestIdx >= 0) htfResistance = iHigh(_Symbol, InpHTF, highestIdx);
   if(lowestIdx >= 0) htfSupport = iLow(_Symbol, InpHTF, lowestIdx);
}

bool IsValidRejection(int shift, double &wickType)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, _Period, shift, 1, rates) != 1) return false;

   double high = rates[0].high;
   double low = rates[0].low;
   double open = rates[0].open;
   double close = rates[0].close;
   double range = high - low;
   double body = MathAbs(open - close);
   if(range <= 0.0) return false;
   if((body / range) > InpAntiBreakoutPct) return false;

   double upperWick = high - MathMax(open, close);
   double lowerWick = MathMin(open, close) - low;

   if((lowerWick / range) * 100.0 >= InpMinWickRatio)
   {
      wickType = 1.0;
      return true;
   }
   if((upperWick / range) * 100.0 >= InpMinWickRatio)
   {
      wickType = -1.0;
      return true;
   }
   return false;
}

void CheckEntrySignals()
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double wickType = 0.0;
   if(!IsValidRejection(1, wickType)) return;

   bool mtfAllow = true;
   if(InpUseMTF)
      mtfAllow = (price <= htfSupport + (InpBufferPoints * _Point) ||
                  price >= htfResistance - (InpBufferPoints * _Point));
   if(!mtfAllow) return;

   if(wickType == 1.0 && price <= targetSupport + (InpBufferPoints * _Point))
   {
      double sl = targetSupport - (InpBufferPoints * _Point);
      double tp = targetResistance;
      if(trade.Buy(InpLotSize, _Symbol, 0.0, sl, tp, "Scalp Buy") && InpSendPush)
         SendNotification("EA Scalp: Buy Executed at Support");
   }

   if(wickType == -1.0 && price >= targetResistance - (InpBufferPoints * _Point))
   {
      double sl = targetResistance + (InpBufferPoints * _Point);
      double tp = targetSupport;
      if(trade.Sell(InpLotSize, _Symbol, 0.0, sl, tp, "Scalp Sell") && InpSendPush)
         SendNotification("EA Scalp: Sell Executed at Resistance");
   }
}

void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNum) continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double curPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      double tpPrice = PositionGetDouble(POSITION_TP);
      double lot = PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double midPoint = openPrice + (tpPrice - openPrice) * 0.5;
      if(lot > SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
      {
         if((type == POSITION_TYPE_BUY && curPrice >= midPoint) ||
            (type == POSITION_TYPE_SELL && curPrice <= midPoint))
         {
            trade.PositionClosePartial(ticket, lot * (InpPartialClosePct / 100.0));
            trade.PositionModify(ticket, openPrice, tpPrice);
            continue;
         }
      }

      if(!InpUseTrailing) continue;
      double stp = InpTrailingStep * _Point;
      double sl = PositionGetDouble(POSITION_SL);
      if(type == POSITION_TYPE_BUY)
      {
         if(curPrice - openPrice > InpTrailingStart * _Point && sl < curPrice - stp)
            trade.PositionModify(ticket, curPrice - stp, tpPrice);
      }
      else
      {
         if(openPrice - curPrice > InpTrailingStart * _Point && (sl > curPrice + stp || sl == 0.0))
            trade.PositionModify(ticket, curPrice + stp, tpPrice);
      }
   }
}

bool IsNewCandle()
{
   static datetime lastTime = 0;
   datetime currTime = iTime(_Symbol, _Period, 0);
   if(lastTime != currTime)
   {
      lastTime = currTime;
      return true;
   }
   return false;
}

void DrawDashboard()
{
   string text = "------------------------------------------\n";
   text += " EA NAME: PASR V1\n";
   text += " STATUS: " + (IsNewsTime() ? "WAITING (NEWS)" : "TRADING ACTIVE") + "\n";
   text += " NEWS INFO: " + newsStatus + "\n";
   text += "------------------------------------------\n";
   text += " S&R M5: " + DoubleToString(targetSupport, _Digits) + " / " + DoubleToString(targetResistance, _Digits) + "\n";
   if(InpUseMTF)
      text += " HTF ZONE (H1): " + DoubleToString(htfSupport, _Digits) + " / " + DoubleToString(htfResistance, _Digits) + "\n";
   text += " SPREAD: " + IntegerToString((int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)) + "\n";
   text += "------------------------------------------";
   Comment(text);
}
