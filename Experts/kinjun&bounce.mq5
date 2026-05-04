//+------------------------------------------------------------------+
//|                          KijunBounce               |
//|                          Copyright @2026 agsicentre              |
//+------------------------------------------------------------------+
#property copyright "Copyright @2026, agsicentre"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

enum ENUM_PYRAMID_MODE { PROFIT, SIGNAL };

//--- INPUT PARAMETERS
input string             EA_Name = "KijunBounce_Hybrid_v2.1";
input long               MagicNumber = 163991;

// Timeframes
input ENUM_TIMEFRAMES    HigherTimeframe = PERIOD_M15;
input ENUM_TIMEFRAMES    LowerTimeframe  = PERIOD_M5;

// Strategy Settings
input double             SL_ATR_Multiplier = 1.3;
input double             KijunSensitivity = 0.65;
input int                MaxPyramidingLevel = 2;
input double             PyramidingATR_Multiplier = 0.7;
input ENUM_PYRAMID_MODE  PyramidingMode = PROFIT;

// Money Management
input bool               UseAutoLot = true;
input double             RiskPercent = 1.0;
input double             FixedLotSize = 0.01;
input double             SoftLossThresholdPercent = 2.0;
input double             LotReductionFactor = 0.5;  
input int                GlobalMaxPositions = 4;          

// Exit
input double             BasketProfitTarget = 45.0;
input double             BasketLossLimit = -120.0;
input bool               UseTrailingKijun = true;
input bool               UsePushNotification = true;      

// Filters
input int                MaxSpread = 18;
input bool               UseSessionFilter = true;
input string             Session1Start = "02:00";
input string             Session1End = "06:00";
input string             Session2Start = "08:30";
input string             Session2End = "15:30";

//--- INDICATOR HANDLES
int hIchimoku, hKijun, hTenkan, hATR; 

//--- GLOBAL VARIABLES
datetime lastBarTime = 0;
int pLevel = 0;
double lastEntry = 0.0;
int tradeDir = -1;
double todayProfit = 0;
int    lastFailedDir    = -1;
int    failedBlacklistBar = 0;
int    winStreak        = 0;
int    lossStreak       = 0;

//+------------------------------------------------------------------+
int OnInit() {
   hIchimoku = iIchimoku(_Symbol, HigherTimeframe, 5, 13, 26);
   hKijun = iMA(_Symbol, LowerTimeframe, 13, 0, MODE_SMA, PRICE_MEDIAN);
   hTenkan = iMA(_Symbol, HigherTimeframe, 5, 0, MODE_SMA, PRICE_MEDIAN);
   hATR = iATR(_Symbol, LowerTimeframe, 14);
   
   if(hIchimoku == INVALID_HANDLE || hKijun == INVALID_HANDLE || 
      hTenkan == INVALID_HANDLE || hATR == INVALID_HANDLE) {
      Print("❌ Indicator handle failed!");
      return INIT_FAILED;
   }
   
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(30);
   CreateDashboard();
   Print("🚀 KijunBounce Final STARTED!");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   IndicatorRelease(hIchimoku);
   IndicatorRelease(hKijun);
   IndicatorRelease(hTenkan);
   IndicatorRelease(hATR);
   ObjectsDeleteAll(0, "Dashboard");
   Comment("");
}

//+------------------------------------------------------------------+
void OnTick() {
   if(Bars(_Symbol, LowerTimeframe) < 120 || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return;
   
   datetime bTime = iTime(_Symbol, LowerTimeframe, 0);
   if(bTime != lastBarTime){
      if(failedBlacklistBar > 0) failedBlacklistBar--;
      lastBarTime = bTime;
   }

   const int myPos = CountPos();
   if(myPos == 0) { pLevel = 0; tradeDir = -1; lastEntry = 0; }
   
   todayProfit = GetTodayProfit();
   
   if(myPos > 0) {
      ManageExitLogic();
      if(BasketCloseCheck()) { CloseAll(); return; }
   }
   
   if(myPos >= GlobalMaxPositions) { UpdateStatus("MAX POS"); return; }
   if(GetSpread() > MaxSpread || !IsInTradingSession()) { UpdateStatus("FILTER"); return; }

   const int barElapsed = (int)(TimeCurrent() - bTime);
   const int barTotal   = PeriodSeconds(LowerTimeframe);

   if(barElapsed >= barTotal * 0.85 && barElapsed <= barTotal * 0.95)
   {
      if(myPos == 0) CheckInitialEntry();
      else if(pLevel < MaxPyramidingLevel) CheckLayering();
   }

   UpdateStatus("RUNNING");
}

//+------------------------------------------------------------------+
void CheckInitialEntry() {
   if(failedBlacklistBar > 0 && tradeDir == lastFailedDir) return;
   
   double atr[1], l[1], h[1]; 
   if(CopyBuffer(hATR, 0, 0, 1, atr) <= 0) return;
   CopyLow(_Symbol, LowerTimeframe, 1, 1, l);
   CopyHigh(_Symbol, LowerTimeframe, 1, 1, h);
   
   double slPoints = (atr[0] * SL_ATR_Multiplier) / _Point;
   double lot = CalculateLot(slPoints);
   if(lot <= 0) return;
   
   if(IsBullish() && IsBounce(true)) {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = MathMin( ask - atr[0]*SL_ATR_Multiplier,  l[0] - 5*_Point );
      if(trade.Buy(lot, _Symbol, ask, sl, 0)) {
         pLevel = 1; tradeDir = 0; lastEntry = ask;
         if(UsePushNotification) SendNotification("🚀 BUY "+_Symbol+" Lot:"+DoubleToString(lot,2));
      }
   }
   else if(IsBearish() && IsBounce(false)) {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = MathMax( bid + atr[0]*SL_ATR_Multiplier,  h[0] + 5*_Point );
      if(trade.Sell(lot, _Symbol, bid, sl, 0)) {
         pLevel = 1; tradeDir = 1; lastEntry = bid;
         if(UsePushNotification) SendNotification("🔻 SELL "+_Symbol+" Lot:"+DoubleToString(lot,2));
      }
   }
}

void CheckLayering() {
   if(failedBlacklistBar > 0 && tradeDir == lastFailedDir) return;
   if(PyramidingMode == PROFIT) { if(PositionGetDouble(POSITION_PROFIT) <= 0) return; }

   double atr[1]; CopyBuffer(hATR,0,0,1,atr);
   if(MathAbs(SymbolInfoDouble(_Symbol,SYMBOL_BID) - lastEntry) < atr[0] * PyramidingATR_Multiplier ) return;
}

//+------------------------------------------------------------------+
void ManageExitLogic(){
   if(!PositionSelect(_Symbol)) return;

   const double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   const double currSl    = PositionGetDouble(POSITION_SL);
   const double slDist    = MathAbs(openPrice - currSl);
   const double currDist  = MathAbs(PositionGetDouble(POSITION_PRICE_CURRENT) - openPrice);

   // BEP
   if(currDist >= slDist * 0.8 && MathAbs(currSl - openPrice) > 10*_Point ){
      trade.PositionModify(_Symbol, openPrice + (tradeDir==0 ? 7*_Point : -7*_Point), 0);
      return;
   }

   // Partial Close 50%
   if(currDist >= slDist * 1.1 ){
      const double closeVol = NormalizeLot(PositionGetDouble(POSITION_VOLUME) * 0.5);
      if(closeVol >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) tradeDir==0 ? trade.Sell(closeVol) : trade.Buy(closeVol);
   }

   // Trailing Kijun
   if(UseTrailingKijun && currDist > slDist * 1.5 ){
      double kijun[1]; CopyBuffer(hKijun, 0, 0,1, kijun);
      if(tradeDir == 0 && kijun[0] > currSl ) trade.PositionModify(_Symbol, kijun[0] - 3*_Point, 0);
      if(tradeDir == 1 && kijun[0] < currSl ) trade.PositionModify(_Symbol, kijun[0] + 3*_Point, 0);
   }
}

//+------------------------------------------------------------------+
bool IsBounce(bool buy) {
   double k[1], t[1], c[2], h[2], l[2], atr[1];
   if(CopyBuffer(hKijun, 0, 1, 1, k) <=0 || CopyBuffer(hTenkan, 0, 1, 1, t) <=0 
   || CopyClose(_Symbol, LowerTimeframe, 1, 2, c) <=0 || CopyHigh(_Symbol, LowerTimeframe, 1, 2, h) <=0
   || CopyLow(_Symbol, LowerTimeframe, 1, 2, l) <=0 || CopyBuffer(hATR, 0, 1, 1, atr) <=0 ) return false;

   const double body = MathAbs(c[0] - c[1]);
   if(body <= 0) return false;

   const double upperWick = h[0] - MathMax(c[0], c[1]);
   const double lowerWick = MathMin(c[0], c[1]) - l[0];

   // Dynamic Wick Ratio
   double atrAvg[20]; CopyBuffer(hATR, 0, 0, 20, atrAvg);
   const double atrNormal = atrAvg[19];
   double dynamicWickRatio;
   if(atr[0] > atrNormal * 1.4)      dynamicWickRatio = 0.75;
   else if(atr[0] > atrNormal * 1.1) dynamicWickRatio = 0.95;
   else if(atr[0] > atrNormal * 0.8) dynamicWickRatio = 1.1;
   else                              dynamicWickRatio = 1.5;

   const bool nearKijun = MathAbs(c[0] - k[0]) <= (KijunSensitivity * atr[0]);
   const bool nearTenkan = MathAbs(c[0] - t[0]) <= (KijunSensitivity * atr[0]);
   const bool nearSupport = nearKijun || nearTenkan;
   
   if(buy) return nearSupport && (lowerWick >= dynamicWickRatio * body) && (c[0] > c[1]) && c[0] > k[0] && c[0] > t[0];
   else    return nearSupport && (upperWick >= dynamicWickRatio * body) && (c[0] < c[1]) && c[0] < k[0] && c[0] < t[0];
}

//+------------------------------------------------------------------+
double CalculateLot(double slPoints) {
   if(!UseAutoLot) return FixedLotSize;
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (RiskPercent / 100.0);
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lot = riskAmount / (slPoints * tv);
   
   // Soft Loss Protection
   double lossThreshold = balance * (SoftLossThresholdPercent / 100.0) * -1;
   if(todayProfit <= lossThreshold) lot *= LotReductionFactor;
   
   return NormalizeLot(lot);
}

double NormalizeLot(double lot) {
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lot = MathFloor(lot / step) * step;
   if(lot < minLot * 0.85) return 0.0;
   return MathMax(minLot, lot);
}

double GetTodayProfit() {
   double profit = 0;
   datetime today = iTime(_Symbol, PERIOD_D1, 0);
   if(HistorySelect(today, TimeCurrent())) {
      for(int i=0; i<HistoryDealsTotal(); i++) {
         ulong ticket = HistoryDealGetTicket(i);
         if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == MagicNumber && HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol)
            profit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
      }
   }
   return profit;
}

//+------------------------------------------------------------------+
int CountPos() {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol) count++;
   }
   return count;
}

double GetSpread() { return (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point; }

bool BasketCloseCheck() {
   double total = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         total += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   if(total >= BasketProfitTarget) { if(UsePushNotification) SendNotification("✅ BASKET PROFIT $"+DoubleToString(total,2)); return true; }
   if(total <= BasketLossLimit)   { if(UsePushNotification) SendNotification("🛑 BASKET STOP $"+DoubleToString(total,2)); return true; }
   return false;
}

void CloseAll() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         trade.PositionClose(ticket);
   }
   
   if(todayProfit < 0){ lastFailedDir = tradeDir; failedBlacklistBar = 3; winStreak=0; lossStreak++; }
   else { lossStreak=0; winStreak++; }

   pLevel = 0; tradeDir = -1; lastEntry = 0;
}

bool IsBullish() {
   double a[1], b[1], c[1];
   if(CopyBuffer(hIchimoku, 2, 1, 1, a) <=0 || CopyBuffer(hIchimoku, 3, 1, 1, b) <=0 || CopyClose(_Symbol, HigherTimeframe,1,1,c)<=0) return false;
   return c[0] > MathMax(a[0], b[0]);
}

bool IsBearish() {
   double a[1], b[1], c[1];
   if(CopyBuffer(hIchimoku, 2, 1, 1, a) <=0 || CopyBuffer(hIchimoku, 3, 1, 1, b) <=0 || CopyClose(_Symbol, HigherTimeframe,1,1,c)<=0) return false;
   return c[0] < MathMin(a[0], b[0]);
}

bool IsInTradingSession(){
   if(!UseSessionFilter) return true;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int nowMin = dt.hour * 60 + dt.min;
   
   int s1s = StringToInteger(StringSubstr(Session1Start,0,2))*60 + StringToInteger(StringSubstr(Session1Start,3,2));
   int s1e = StringToInteger(StringSubstr(Session1End,0,2))*60 + StringToInteger(StringSubstr(Session1End,3,2));
   int s2s = StringToInteger(StringSubstr(Session2Start,0,2))*60 + StringToInteger(StringSubstr(Session2Start,3,2));
   int s2e = StringToInteger(StringSubstr(Session2End,0,2))*60 + StringToInteger(StringSubstr(Session2End,3,2));
   
   return (nowMin >= s1s && nowMin <= s1e) || (nowMin >= s2s && nowMin <= s2e);
}

//+------------------------------------------------------------------+
void CreateDashboard() {
   ObjectCreate(0, "Dashboard", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "Dashboard", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "Dashboard", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, "Dashboard", OBJPROP_YDISTANCE, 30);
   ObjectSetInteger(0, "Dashboard", OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, "Dashboard", OBJPROP_FONT, "Consolas");
}

void UpdateStatus(string msg) {
   string bias = IsBullish() ? "🟢BULL" : IsBearish() ? "🔴BEAR" : "⚪NEUTRAL";
   string softLoss = (todayProfit <= -AccountInfoDouble(ACCOUNT_BALANCE) * SoftLossThresholdPercent/100) ? "🔴SOFT LOSS" : "🟢NORMAL";
   
   string text = StringFormat(
      "🚀 %s | Lvl:%d/%d | Bias:%s | Pos:%d/%d\n"
      "💰 Today: $%.1f | %s | %s",
      EA_Name, pLevel, MaxPyramidingLevel, bias, CountPos(), GlobalMaxPositions, todayProfit, softLoss, msg
   );
   
   ObjectSetString(0, "Dashboard", OBJPROP_TEXT, text);
   Comment(text);
}
//+------------------------------------------------------------------+