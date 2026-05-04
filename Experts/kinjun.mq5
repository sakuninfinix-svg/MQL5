//+------------------------------------------------------------------+
//|                                         Kijun_Bounce_Hybrid_v2.mq5|
//|                                   Copyright @2026, agsicentre    |
//+------------------------------------------------------------------+
#property copyright "Copyright @2026, agsicentre"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

enum ENUM_PYRAMID_MODE { PROFIT, SIGNAL };

//--- INPUT PARAMETERS
input string               EA_Name = "KijunBounce_Hybrid_v2.0";
input long                 MagicNumber = 163991;

// Timeframes & Ichimoku
input ENUM_TIMEFRAMES      HigherTimeframe = PERIOD_M15;
input ENUM_TIMEFRAMES      LowerTimeframe  = PERIOD_M5;

// Strategy Settings
input double               SL_ATR_Multiplier = 1.0;
input double               KijunSensitivity = 0.7;
input int                  MaxPyramidingLevel = 2;
input double               PyramidingATR_Multiplier = 0.7;
input ENUM_PYRAMID_MODE    PyramidingMode = PROFIT;

// MONEY MANAGEMENT
input bool                 UseAutoLot = true;
input double               RiskPercent = 1.0;
input double               FixedLotSize = 0.01;
input double               SoftLossThresholdPercent = 2.0;
input double               LotReductionFactor = 0.5;  
input int                  GlobalMaxPositions = 6;            

// Exit & Safety
input int                  BEP_Trigger_Points = 80;
input int                  BEP_Buffer_Points = 10;
input double               BasketProfitTarget = 50.0;
input double               BasketLossLimit = -150.0;
input bool                 UseTrailingKijun = true;
input bool                 UsePushNotification = true;      

// Filters
input int                  MaxSpread = 20;
input bool                 AvoidHighImpactNews = true;
input bool                 AvoidMediumImpactNews = true;
input bool                 AvoidLowImpactNews = false;
input int                  StopBeforeHigh = 60;
input int                  AfterHigh = 30;

// Session
input bool                 UseSessionFilter = true;
input string               Session1Start = "02:00";
input string               Session1End = "06:00";
input string               Session2Start = "09:00";
input string               Session2End = "15:00";

//--- HANDLES
int hIchimoku, hKijun, hTenkan, hATR; 

//--- GLOBAL VARIABLES
datetime lastBarTime = 0;
int pLevel = 0;
double lastEntry = 0.0;
int tradeDir = -1;
double todayProfit = 0;
int    lastFailedDir    = -1;
int    failedBlacklistBar = 0;

//+------------------------------------------------------------------+
int OnInit() {
   hIchimoku = iIchimoku(_Symbol, HigherTimeframe, 5, 13, 26);
   hKijun = iMA(_Symbol, LowerTimeframe, 13, 0, MODE_SMA, PRICE_MEDIAN);
   hTenkan = iMA(_Symbol, HigherTimeframe, 5, 0, MODE_SMA, PRICE_MEDIAN);
   hATR = iATR(_Symbol, LowerTimeframe, 14);
   
   if(hIchimoku == INVALID_HANDLE || hKijun == INVALID_HANDLE || hTenkan == INVALID_HANDLE || hATR == INVALID_HANDLE) return INIT_FAILED;
   
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(30);
   CreateDashboard();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   ObjectsDeleteAll(0, "Dashboard");
}

void OnTick() {
   if(Bars(_Symbol, LowerTimeframe) < 100 || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return;
   
   datetime bTime = iTime(_Symbol, LowerTimeframe, 0);
   if(bTime != lastBarTime) {
      if(failedBlacklistBar > 0) failedBlacklistBar--;
   }
   
   int myPos = CountPos();
   if(myPos == 0) { pLevel = 0; tradeDir = -1; lastEntry = 0; }
   
   todayProfit = GetTodayProfit();
   
   if(myPos > 0) {
      ManageExitLogic();
      if(BasketCloseCheck()) { CloseAll(); return; }
   }
   
   if(myPos >= GlobalMaxPositions) { UpdateStatus("MAX POS"); return; }
   
   if(GetSpread() > MaxSpread || !IsInTradingSession()) { UpdateStatus("FILTER ACTIVE"); return; }

   if(bTime != lastBarTime) {
      lastBarTime = bTime;
      if(myPos == 0) CheckInitialEntry();
      else if(pLevel < MaxPyramidingLevel) CheckLayering();
   }
   UpdateStatus("RUNNING");
}

//--- LOGIKA LAYERING
void CheckLayering() {
   if(failedBlacklistBar > 0 && tradeDir == lastFailedDir) return;
   
   if(PyramidingMode == PROFIT) {
      if(!PositionSelect(_Symbol)) return;
      if(PositionGetDouble(POSITION_PROFIT) <= 0) return;
   }

   double atr[1]; CopyBuffer(hATR,0,0,1,atr);
   double currentPrice = (tradeDir == 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   if(MathAbs(currentPrice - lastEntry) < atr[0] * PyramidingATR_Multiplier) return;
   
   double slPoints = (atr[0] * SL_ATR_Multiplier) / _Point;
   double lot = CalculateLot(slPoints);
   
   if(tradeDir == 0 && trade.Buy(lot, _Symbol, currentPrice, 0, 0)) { pLevel++; lastEntry = currentPrice; }
   else if(tradeDir == 1 && trade.Sell(lot, _Symbol, currentPrice, 0, 0)) { pLevel++; lastEntry = currentPrice; }
}

//--- EXIT LOGIC
void ManageExitLogic() {
   if(!PositionSelect(_Symbol)) return;

   double openPrice = PositionGetDouble(POSITION_OPEN_PRICE);
   double currSl    = PositionGetDouble(POSITION_SL);
   double currPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
   double slDist    = MathAbs(openPrice - currSl);
   double currDist  = MathAbs(currPrice - openPrice);

   if(currDist >= slDist * 0.8 && (currSl == 0 || MathAbs(currSl - openPrice) > 10*_Point)) {
      double nSl = openPrice + (tradeDir==0 ? BEP_Buffer_Points*_Point : -BEP_Buffer_Points*_Point);
      trade.PositionModify(_Symbol, nSl, 0);
   }

   if(currDist >= slDist * 1.1) {
      double vol = NormalizeLot(PositionGetDouble(POSITION_VOLUME) * 0.5);
      if(vol >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) trade.PositionClosePartial(_Symbol, vol);
   }

   if(UseTrailingKijun && currDist > slDist * 1.5) {
      double kijun[1]; CopyBuffer(hKijun, 0, 0, 1, kijun);
      if(tradeDir == 0 && kijun[0] > currSl) trade.PositionModify(_Symbol, kijun[0], 0);
      if(tradeDir == 1 && (kijun[0] < currSl || currSl == 0)) trade.PositionModify(_Symbol, kijun[0], 0);
   }
}

//--- MONEY MANAGEMENT
double CalculateLot(double slPoints) {
   if(!UseAutoLot) return FixedLotSize;
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent / 100.0);
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double lot = risk / (MathMax(slPoints, 10) * (tv / (ts / pt)));
   
   if(todayProfit <= -AccountInfoDouble(ACCOUNT_BALANCE) * (SoftLossThresholdPercent / 100.0)) lot *= LotReductionFactor;
   return NormalizeLot(lot);
}

double NormalizeLot(double lot) {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / step) * step;
   return MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), MathMin(lot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX)));
}

double GetTodayProfit() {
   double p = 0;
   if(HistorySelect(iTime(_Symbol, PERIOD_D1, 0), TimeCurrent())) {
      for(int i = HistoryDealsTotal()-1; i >= 0; i--) {
         ulong t = HistoryDealGetTicket(i);
         if(HistoryDealGetInteger(t, DEAL_MAGIC) == MagicNumber) p += HistoryDealGetDouble(t, DEAL_PROFIT);
      }
   }
   return p;
}

//--- ENTRY
void CheckInitialEntry() {
   if(failedBlacklistBar > 0 && tradeDir == lastFailedDir) return;
   
   double atr[1], l[1], h[1];
   CopyBuffer(hATR, 0, 0, 1, atr);
   CopyLow(_Symbol, LowerTimeframe, 1, 1, l);
   CopyHigh(_Symbol, LowerTimeframe, 1, 1, h);
   
   double lot = CalculateLot((atr[0] * SL_ATR_Multiplier) / _Point);
   if(lot <= 0) return;

   if(IsBullish() && IsBounce(true)) {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = ask - (atr[0] * SL_ATR_Multiplier);
      if(trade.Buy(lot, _Symbol, ask, sl, 0)) { pLevel = 1; tradeDir = 0; lastEntry = ask; }
   }
   else if(IsBearish() && IsBounce(false)) {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = bid + (atr[0] * SL_ATR_Multiplier);
      if(trade.Sell(lot, _Symbol, bid, sl, 0)) { pLevel = 1; tradeDir = 1; lastEntry = bid; }
   }
}

bool IsBounce(bool buy) {
   double k[1], t[1], c[2], h[2], l[2], atr[1];
   if(CopyBuffer(hKijun, 0, 1, 1, k) <= 0 || CopyBuffer(hTenkan, 0, 1, 1, t) <= 0 ||
      CopyClose(_Symbol, LowerTimeframe, 1, 2, c) <= 0 || CopyHigh(_Symbol, LowerTimeframe, 1, 2, h) <= 0 ||
      CopyLow(_Symbol, LowerTimeframe, 1, 2, l) <= 0 || CopyBuffer(hATR, 0, 1, 1, atr) <= 0) return false;

   double body = MathAbs(c[0] - c[1]); if(body <= 0) return false;
   double uWick = h[0] - MathMax(c[0], c[1]);
   double lWick = MathMin(c[0], c[1]) - l[0];

   bool near = (MathAbs(c[0] - k[0]) <= KijunSensitivity * atr[0]) || (MathAbs(c[0] - t[0]) <= KijunSensitivity * atr[0]);
   
   if(buy) return near && lWick > body * 0.7 && c[0] > c[1];
   return near && uWick > body * 0.7 && c[0] < c[1];
}

//--- UTILS
bool IsInTradingSession() {
   if(!UseSessionFilter) return true;
   MqlDateTime dt; TimeToStruct(TimeTradeServer(), dt);
   int m = dt.hour * 60 + dt.min;
   return (m >= 120 && m <= 360) || (m >= 540 && m <= 900); // Sesuai input string jam
}

int CountPos() {
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetInteger(POSITION_MAGIC) == MagicNumber) c++;
   }
   return c;
}

double GetSpread() { return (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD); }

bool BasketCloseCheck() {
   double p = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         p += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) + PositionGetDouble(POSITION_COMMISSION);
   }
   return (p >= BasketProfitTarget || p <= BasketLossLimit);
}

void CloseAll() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) && PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
         if(PositionGetDouble(POSITION_PROFIT) < 0) { lastFailedDir = (int)PositionGetInteger(POSITION_TYPE); failedBlacklistBar = 3; }
         trade.PositionClose(t);
      }
   }
}

bool IsBullish() {
   double a[1], b[1], c[1];
   CopyBuffer(hIchimoku, 2, 1, 1, a); CopyBuffer(hIchimoku, 3, 1, 1, b); CopyClose(_Symbol, HigherTimeframe, 1, 1, c);
   return c[0] > MathMax(a[0], b[0]);
}

bool IsBearish() {
   double a[1], b[1], c[1];
   CopyBuffer(hIchimoku, 2, 1, 1, a); CopyBuffer(hIchimoku, 3, 1, 1, b); CopyClose(_Symbol, HigherTimeframe, 1, 1, c);
   return c[0] < MathMin(a[0], b[0]);
}

void CreateDashboard() {
   ObjectCreate(0, "Dashboard", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "Dashboard", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "Dashboard", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, "Dashboard", OBJPROP_YDISTANCE, 30);
}

void UpdateStatus(string msg) {
   string text = StringFormat("🚀 %s | P/L Today: $%.2f\nStatus: %s", EA_Name, todayProfit, msg);
   ObjectSetString(0, "Dashboard", OBJPROP_TEXT, text);
   Comment(text);
}