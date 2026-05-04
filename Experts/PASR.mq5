//+------------------------------------------------------------------+
//|                            PASR V1.mq5                            |
//|                  Copyright 2026, Agsicentre                       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "1.00"
#property strict

//--- Include Trade Class
#include <Trade\Trade.mqh>
CTrade trade;

//--- INPUT PARAMETERS
input group "== Market Filters ==" input double InpMinATR = 10.0; // Min ATR (Points) untuk menghindari Choppy
input double InpMaxSpread = 20.0;                                 // Max Spread (Points)
input string InpTradingSession = "14:00-21:00";                   // Sesi Trading (GMT/Server Time)
input bool UseNewsFilter = true;
input int NewsFreezeMinutes = 30;
input bool BlockHigh = true;
input bool BlockMedium = true;

input group "== S&R & Price Action ==" input int InpSRLookback = 20; // Lookback Candle untuk S&R M5
input double InpMinWickRatio = 60.0;                                 // Min Wick % (Dynamic Wick)
input double InpAntiBreakoutPct = 0.7;                               // Body/Range Ratio (Max 0.7)
input int InpBufferPoints = 20;                                      // Jarak Entry dari Garis S&R

input group "== Multi-Timeframe (MTF) ==" input bool InpUseMTF = true; // Aktifkan Filter H1
input ENUM_TIMEFRAMES InpHTF = PERIOD_H1;                              // Timeframe Acuan (Anchor)
input int InpHTFLookback = 50;                                         // Lookback S&R di H1

input group "== Risk Management ==" input double InpLotSize = 0.01; // Lot Awal
input double InpPartialClosePct = 50.0;                             // % Lot ditutup di tengah Range
input bool InpUseTrailing = true;                                   // Aktifkan Trailing Stop
input int InpTrailingStart = 50;                                    // Jarak mulai Trailing (Points)
input int InpTrailingStep = 20;                                     // Step Trailing (Points)

input group "== Hedging Recovery ==" input bool InpUseHedging = true; // Aktifkan Hedging jika Breakout
input double InpHedgeMult = 1.5;                                      // Multiplier Lot Hedge

input group "== System ==" input long InpMagicNum = 20260403; // Magic Number
input bool InpSendPush = true;                                // Kirim Notif ke HP

//--- GLOBAL VARIABLES
double targetSupport, targetResistance;
double htfSupport, htfResistance;
string newsStatus = "Normal";
datetime nextNewsTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNum);
   return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| News Filter                                   |
//+------------------------------------------------------------------+
bool IsNewsTime()
{
   if (!UseNewsFilter)
      return false;

   MqlCalendarValue values[];
   datetime timeFrom = TimeCurrent() - (NewsFreezeMinutes * 60);
   datetime timeTo = TimeCurrent() + (NewsFreezeMinutes * 60);

   string baseCurrency = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);     // USD
   string profitCurrency = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT); // JPY

   string currencies[2];
   currencies[0] = baseCurrency;
   currencies[1] = profitCurrency;

   for (int c = 0; c < 2; c++)
   {

      if (CalendarValueHistory(values, timeFrom, timeTo, NULL, currencies[c]) > 0)
      {
         for (int i = 0; i < ArraySize(values); i++)
         {
            MqlCalendarEvent event;
            if (CalendarEventById(values[i].event_id, event))
            {

               // Filter Impact
               bool isHigh = (event.importance == CALENDAR_IMPORTANCE_HIGH && BlockHigh);
               bool isMedium = (event.importance == CALENDAR_IMPORTANCE_MODERATE && BlockMedium);

               if (isHigh || isMedium)
               {
                  nextNewsTime = values[i].time;
                  newsStatus = "NEWS ACTIVE: " + event.name;
                  return true;
               }
            }
         }
      }
   }
   newsStatus = "Market Clear";
   return false;
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{

   // 1. Basic Filters
   if (!IsNewCandle())
      return; // Cek per candle untuk efisiensi
   if (SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpread)
      return;

   // 2. Update S&R Levels
   UpdateSRLevels();
   if (InpUseMTF)
      UpdateHTFLevels();

   // 3. Check for Open Positions & Management
   ManagePositions();

   // 4. Entry Logic
   if (PositionsTotal() == 0)
   {
      CheckEntrySignals();
   }
}

//+------------------------------------------------------------------+
//| Update S&R Levels for M5 and HTF                                 |
//+------------------------------------------------------------------+
void UpdateSRLevels()
{
   int highestIdx = iHighest(_Symbol, _Period, MODE_HIGH, InpSRLookback, 1);
   int lowestIdx = iLowest(_Symbol, _Period, MODE_LOW, InpSRLookback, 1);
   targetResistance = iHigh(_Symbol, _Period, highestIdx);
   targetSupport = iLow(_Symbol, _Period, lowestIdx);

   // MEMBUAT GARIS VISUAL DI GRAFIK
   ObjectCreate(0, "ResLine", OBJ_HLINE, 0, 0, targetResistance);
   ObjectSetInteger(0, "ResLine", OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, "ResLine", OBJPROP_STYLE, STYLE_DOT);

   ObjectCreate(0, "SupLine", OBJ_HLINE, 0, 0, targetSupport);
   ObjectSetInteger(0, "SupLine", OBJPROP_COLOR, clrAqua);
   ObjectSetInteger(0, "SupLine", OBJPROP_STYLE, STYLE_DOT);
}

void UpdateHTFLevels()
{
   int highestIdx = iHighest(_Symbol, InpHTF, MODE_HIGH, InpHTFLookback, 1);
   int lowestIdx = iLowest(_Symbol, InpHTF, MODE_LOW, InpHTFLookback, 1);
   htfResistance = iHigh(_Symbol, InpHTF, highestIdx);
   htfSupport = iLow(_Symbol, InpHTF, lowestIdx);
}

//+------------------------------------------------------------------+
//| Logic to detect Wick Ratio & Anti-Breakout                       |
//+------------------------------------------------------------------+
bool IsValidRejection(int shift, double &wickType)
{
   double high = iHigh(_Symbol, _Period, shift);
   double low = iLow(_Symbol, _Period, shift);
   double open = iOpen(_Symbol, _Period, shift);
   double close = iClose(_Symbol, _Period, shift);
   double range = high - low;
   double body = MathAbs(open - close);

   if (range == 0)
      return false;

   // Anti-Breakout Filter (Marubozu check)
   if ((body / range) > InpAntiBreakoutPct)
      return false;

   double upperWick = high - MathMax(open, close);
   double lowerWick = MathMin(open, close) - low;

   // Check Buy Rejection (Lower Wick)
   if ((lowerWick / range) * 100 >= InpMinWickRatio)
   {
      wickType = 1; // Buy Signal
      return true;
   }
   // Check Sell Rejection (Upper Wick)
   if ((upperWick / range) * 100 >= InpMinWickRatio)
   {
      wickType = -1; // Sell Signal
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Entry Signal Detection                                           |
//+------------------------------------------------------------------+
void CheckEntrySignals()
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double wickType = 0;

   if (!IsValidRejection(1, wickType))
      return;

   // Filter MTF (H1) - Hanya OP jika di zona HTF
   bool mtfAllow = true;
   if (InpUseMTF)
   {
      mtfAllow = (price <= htfSupport + (InpBufferPoints * _Point) ||
                  price >= htfResistance - (InpBufferPoints * _Point));
   }
   if (!mtfAllow)
      return;

   // BUY Signal at Support
   if (wickType == 1 && price <= targetSupport + (InpBufferPoints * _Point))
   {
      double sl = targetSupport - (InpBufferPoints * _Point);
      double tp = targetResistance;
      if (trade.Buy(InpLotSize, _Symbol, price, sl, tp, "Scalp Buy"))
      {
         if (InpSendPush)
            SendNotification("EA Scalp: Buy Executed at Support");
      }
   }

   // SELL Signal at Resistance
   if (wickType == -1 && price >= targetResistance - (InpBufferPoints * _Point))
   {
      double sl = targetResistance + (InpBufferPoints * _Point);
      double tp = targetSupport;
      if (trade.Sell(InpLotSize, _Symbol, price, sl, tp, "Scalp Sell"))
      {
         if (InpSendPush)
            SendNotification("EA Scalp: Sell Executed at Resistance");
      }
   }
}

//+------------------------------------------------------------------+
//| Management: Partial Close & Trailing Stop                        |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == InpMagicNum)
      {

         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double curPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
         double tpPrice = PositionGetDouble(POSITION_TP);
         double lot = PositionGetDouble(POSITION_VOLUME);

         // 1. Partial Close at 50% Range
         double midPoint = openPrice + (tpPrice - openPrice) * 0.5;
         if (lot > SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
         {
            if ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && curPrice >= midPoint) ||
                (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && curPrice <= midPoint))
            {

               trade.PositionClosePartial(ticket, lot * (InpPartialClosePct / 100.0));
               // Move to Break Even
               trade.PositionModify(ticket, openPrice, tpPrice);
               continue;
            }
         }

         // 2. Trailing Stop
         if (InpUseTrailing)
         {
            double stp = InpTrailingStep * _Point;
            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
               if (curPrice - openPrice > InpTrailingStart * _Point)
               {
                  if (PositionGetDouble(POSITION_SL) < curPrice - stp)
                     trade.PositionModify(ticket, curPrice - stp, tpPrice);
               }
            }
            else
            {
               if (openPrice - curPrice > InpTrailingStart * _Point)
               {
                  if (PositionGetDouble(POSITION_SL) > curPrice + stp || PositionGetDouble(POSITION_SL) == 0)
                     trade.PositionModify(ticket, curPrice + stp, tpPrice);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Utility: Check New Candle                                        |
//+------------------------------------------------------------------+
bool IsNewCandle()
{
   static datetime lastTime = 0;
   datetime currTime = iTime(_Symbol, _Period, 0);
   if (lastTime != currTime)
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
   if (InpUseMTF)
      text += " HTF ZONE (H1): " + DoubleToString(htfSupport, _Digits) + " / " + DoubleToString(htfResistance, _Digits) + "\n";
   text += " SPREAD: " + IntegerToString((int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)) + "\n";
   text += "------------------------------------------";

   Comment(text);
}