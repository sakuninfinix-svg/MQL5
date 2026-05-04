//+------------------------------------------------------------------+
//|               Price Action & Support Ressistance V1              |
//|         Optimized by Agsicentre (agsicentre.wordpress.com)       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "2.00"
#property strict

#include <Trade/Trade.mqh>
#include <PASR/3.MarketManager.mqh>
#include <PASR/4.SRManager.mqh>

CTrade trade;

enum ENUM_ENTRY_MODE
{
   MODE_SAFE,
   MODE_AGGRESSIVE
};
enum ENUM_SR_MODE
{
   SR_EXTREME,
   SR_SWING
};
enum ENUM_EXIT_MODE
{
   EXIT_SR_TARGET,
   EXIT_FIX_TP,
   EXIT_PARTIAL_LOCK
};

enum ENUM_NEWS_LEVEL
{
   NEWS_HIGH = 1,        // 1. High Only
   NEWS_HIGH_MEDIUM = 2, // 2. High + Medium
   NEWS_ALL = 3          // 3. All Block
};

enum ENUM_TRADE_STATE
{
   TRADE_STATE_NONE = 0,
   TRADE_STATE_NORMAL,
   TRADE_STATE_VSL_HIT,
   TRADE_STATE_SELF_RECOVERY,
   TRADE_STATE_FAILED_CONFIRMED,
   TRADE_STATE_HEDGE_ACTIVE,
   TRADE_STATE_BASKET_EXIT,
   TRADE_STATE_DONE
};

input group "== Market Filters ==" input int InpATRPeriod = 14;
input double InpATRMin = 80.0;
input double InpATRMax = 2500.0;
input double InpMaxSpread = 150.0;
input string InpTradingSession = "00:00-24:00";
input bool UseNewsFilter = true;
input int NewsFreezeMinutes = 60;
input ENUM_NEWS_LEVEL InpNewsLevel = NEWS_HIGH_MEDIUM;
input double InpMinTPDistanceATR = 0.3;
input double InpMinSRRangeATR = 0.5;

input group "== Strategy Settings ==" input ENUM_ENTRY_MODE InpEntryMode = MODE_SAFE;
input ENUM_SR_MODE InpSRMode = SR_EXTREME;
input int InpSRLookback = 20;
input int InpSignalLookback = 5;
input double InpMaxSignalSizeATR = 1.8;

input group "== Price Action Parameters ==" input double InpMinWickRatio = 45.0;
input double InpAntiBreakoutPct = 0.80;
input double InpATRBufferMult = 0.5;
input double InpAggressiveWickRel = 0.8;

input group "== Multi-Timeframe Confirmation ==" input bool InpUseMTF = false;
input ENUM_TIMEFRAMES InpHTF = PERIOD_H1;
input int InpHTFLookback = 50;
input bool InpBlockCounterHTF = false;

input group "== Risk Management ==" input double InpLotSize = 0.01;
input double InpMaxDailyLossPct = 5.0;
input int InpMaxOpenPositions = 3; // Total Max Open Positions

input group "== Anti Overtrade ==" input int InpEntryCooldownBars = 1;
input bool InpOneEntryPerZone = true;
input int InpLossCooldownBars = 3;
input int InpMaxConsecutiveLoss = 2;
input double InpZoneReuseATR = 0.20;

input group "== Exit & Trailing Strategy ==" input ENUM_EXIT_MODE InpExitMode = EXIT_SR_TARGET;
input double InpFixedTPATR = 1.2;
input double InpFixedSLATR = 0.8;
input bool InpUseTrailing = true;
input double InpTrailingStartPips = 8.0;
input double InpTrailingBufferPips = 1.5;

input group "== Adaptive Trailing (ATR) ==" input double InpTrailActivationATR = 1.8;
input double InpTrailStepATR = 0.7;
input double InpLockProfitATR = 1.2;
input double InpLockLevelATR = 0.3;

input group "== Advanced Hedging Recovery ==" input bool InpUseHedging = false;
input double InpATRHedgeSL = 0.5;
input double InpATRRecovery = 1.0;
input double InpATRBankProfit = 0.5;
input int InpMaxHedgeBars = 100;

input group "== Self Recovery Trade ==" input bool InpUseHardSL = true;
input double InpHardSLATR = 2.5;
input int InpRecoveryMaxBars = 6;
input double InpRecoveryPullbackATR = 0.30;
input double InpRecoveryMinNetMoney = 0.0;
input double InpRecoveryBEOffsetATR = 0.10;
input double InpFailureConfirmATR = 0.15;
input int InpFailureConfirmBars = 1;
input int InpMaxRecoveryLayers = 3;
input double InpLayer1LotMult = 1.00;

input group "== Partial Close Settings (Virtual TP) ==" input bool InpUsePartialClose = true;
input double InpPartialCloseLotPct = 0.5;
input double InpPartialCloseATR = 0.25; // Jarak profit dari entry sebelum partial

input group "== System ==" input long InpMagicNum = 20260403;
input bool InpSendPush = true;
input bool InpDebugMode = true;

// =========================
// STRUCT CACHE POSISI
// =========================
struct PositionScanResult
{
   int normalCount;
   int hedgeCount;
   int buyCount;
   int sellCount;
   double totalProfit;
};

struct RecoveryEngine
{
   bool active;
   ulong mainTicket;
   ulong hedgeTicket;
   int direction; // 1 buy, -1 sell
   ENUM_TRADE_STATE state;

   datetime entryTime;
   datetime vslHitTime;
   datetime recoveryStartTime;
   datetime failureTime;
   datetime hedgeOpenTime;

   double entryPrice;
   double initialTP;
   double brokerSL;
   double vslPrice;     // no buffer
   double failPrice;    // sl + buffer
   double hardStopLoss; // emergency hard stop (broker side)
   double recoveryTP;
   double partialTP; // Virtual TP untuk partial close
   double lastKnownATR;

   bool partialClosed;
   bool hedgeEligible;
   void Reset() { ZeroMemory(this); }
};

PositionScanResult posScan;
RecoveryEngine tradeEngines[10]; // Kapasitas 10 trade aktif simultan

int atrHandle = INVALID_HANDLE;
// --- Global Stats (will be refactored later) ---
int statSpread = 0, statATR = 0, statSRRange = 0;
int statMidpoint = 0, statTPDist = 0, statHTF = 0;
int statTotalSignals = 0, statSignalsPassed = 0, statTradesToday = 0;
// --- End Global Stats ---
int statHedgeSave = 0, statHedgeFail = 0;

int cachedNormalPositions = 0;
int cachedHedgePositions = 0;
double cachedTotalProfit = 0.0;

datetime lastEntryBarTime = 0;

double lastBuyZonePrice = 0.0;
double lastSellZonePrice = 0.0;
datetime lastBuyZoneBar = 0;
datetime lastSellZoneBar = 0;

MarketManager market; // Instantiate MarketManager
SRManager sr;         // Instantiate SRManager

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNum);
   market.Init(); // Initialize MarketManager
   for (int i = 0; i < 10; i++)
      tradeEngines[i].Reset();
   return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   Print("=== PASR STATS ===");
   Print("Signals: ", statTotalSignals, " | Passed: ", statSignalsPassed);
   Print("Spread: ", statSpread, " | ATR: ", statATR, " | SR Range: ", statSRRange);
   Print("Midpoint: ", statMidpoint, " | TP Dist: ", statTPDist, " | HTF: ", statHTF);
   Print("Hedge Saves: ", statHedgeSave, " | Hedge Fails: ", statHedgeFail);
   Print("==================");
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   // Kita memantau saat deal (transaksi) ditambahkan ke history
   if (trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      if (HistoryDealSelect(trans.deal))
      {
         long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
         string symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
         long entryType = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
         string comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);

         // Pastikan deal berasal dari EA ini, simbol ini, dan merupakan deal penutup (OUT)
         if (magic == InpMagicNum && symbol == _Symbol && (entryType == DEAL_ENTRY_OUT || entryType == DEAL_ENTRY_INOUT))
         {
            // Lindungi dari penghitungan loss streak jika yang tutup adalah posisi hedge
            if (StringFind(comment, "HEDGE") >= 0)
               return;

            double netProfit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) +
                               HistoryDealGetDouble(trans.deal, DEAL_COMMISSION) +
                               HistoryDealGetDouble(trans.deal, DEAL_SWAP);
            market.UpdateLossStreak(netProfit);
         }
      }
   }
}

void OnTick()
{
   // 1. Scan Posisi & Sync State
   MqlTick currentTick;
   if (!SymbolInfoTick(_Symbol, currentTick))
      return;

   ScanAndProcessPositions(currentTick);

   DrawDashboard(currentTick); // Pass tick for current spread/ATR

   // 2. New Candle Logic - Pindahkan ke atas agar filter di bawah hanya jalan 1x per bar
   datetime currTime = iTime(_Symbol, _Period, 0);
   if (!market.IsNewBar())
      return;

   double currentSpread, currentATR;
   if (!market.PassesGate(currentTick, currentSpread, currentATR))
   {
      // If any market filter fails, update lastBarTime to prevent re-checking on the same bar
      market.SetLastBarTime(currTime);
      return;
   }

   // If all filters pass, then officially process this bar
   market.SetLastBarTime(currTime);

   sr.UpdateMainZones();
   sr.UpdateHTFZones();
   if (!sr.IsTradableRange(market.GetATRPoints()))
   {
      statSRRange++;
      return;
   }
   if (market.IsDailyLossLimitHit())
      return;
   if (IsEntryCooldownActive())
      return;
   if (posScan.normalCount >= InpMaxOpenPositions)
      return;

   CheckEntrySignals();
}

bool IsValidRejection(int shift, double &wickType, double &signalPrice, bool &midpointFail)
{
   double high = iHigh(_Symbol, _Period, shift);
   double low = iLow(_Symbol, _Period, shift);
   double open = iOpen(_Symbol, _Period, shift);
   double close = iClose(_Symbol, _Period, shift);
   double mid = (high + low) / 2.0; // This should use market.GetATRPoints()
   double range = high - low;
   double body = MathAbs(open - close);
   double atr = GetATRPoints() * _Point;

   midpointFail = false;
   if (range <= 0.0)
      return false;
   if (range > InpMaxSignalSizeATR * atr)
      return false;
   if ((body / range) > InpAntiBreakoutPct)
      return false;

   double upperWick = high - MathMax(open, close);
   double lowerWick = MathMin(open, close) - low;

   double reqWick = InpMinWickRatio;
   if (InpEntryMode == MODE_AGGRESSIVE)
      reqWick *= InpAggressiveWickRel;

   double upperPct = (upperWick / range) * 100.0;
   double lowerPct = (lowerWick / range) * 100.0;

   if (lowerPct >= reqWick)
   {
      if (close > mid)
      {
         wickType = 1.0;
         signalPrice = low;
         return true;
      }
      midpointFail = true;
   }

   if (upperPct >= reqWick)
   {
      if (close < mid)
      {
         wickType = -1.0;
         signalPrice = high;
         return true;
      }
      midpointFail = true;
   }

   return false;
}

bool IsZoneReuseBlocked(bool isBuy, double zonePrice)
{
   if (!InpOneEntryPerZone)
      return false;

   datetime currBar = iTime(_Symbol, _Period, 0);
   double tol = GetATRPoints() * InpZoneReuseATR * _Point;

   if (isBuy)
      return (lastBuyZoneBar == currBar && MathAbs(zonePrice - lastBuyZonePrice) <= tol);
   else
      return (lastSellZoneBar == currBar && MathAbs(zonePrice - lastSellZonePrice) <= tol);
}

void CheckEntrySignals()
{
   double wickType = 0.0;
   double signalPrice = 0.0;
   int signalShift = -1;
   bool midFailFound = false;

   for (int shift = 1; shift <= InpSignalLookback; shift++)
   {
      bool midFail = false;
      if (IsValidRejection(shift, wickType, signalPrice, midFail))
      {
         signalShift = shift;
         statTotalSignals++;
         break;
      }
      if (midFail)
         midFailFound = true;
   }

   if (signalShift < 0)
   {
      if (midFailFound)
         statMidpoint++;
      market.DebugLog("No rejection signal");
      return;
   }

   double zoneWidth = (GetATRPoints() * InpATRBufferMult) * _Point;

   bool nearSupport = false;
   bool nearResistance = false;

   if (InpEntryMode == MODE_SAFE)
   {
      nearSupport = (signalPrice <= targetSupport + zoneWidth * 0.5);
      nearResistance = (signalPrice >= targetResistance - zoneWidth * 0.5);
   }
   else
   {
      nearSupport = (signalPrice <= targetSupport + zoneWidth);
      nearResistance = (signalPrice >= targetResistance - zoneWidth);
   }

   if (wickType == 1.0 && nearSupport)
   {
      if (IsZoneReuseBlocked(true, sr.Support()))
         return;
      ExecuteEntry(ORDER_TYPE_BUY, signalPrice);
   }
   else if (wickType == -1.0 && nearResistance)
   {
      if (IsZoneReuseBlocked(false, sr.Resistance()))
         return;
      ExecuteEntry(ORDER_TYPE_SELL, signalPrice);
   }
   else
   {
      market.DebugLog("Signal exists but not near SR");
   }
}
// GetCurrentPrices() removed, now handled by MarketManager
void ExecuteEntry(ENUM_ORDER_TYPE type, double signalPrice)
{
   double bid, ask;
   if (!GetCurrentPrices(bid, ask))
      return;

   double atr = GetATRPoints() * _Point;
   double entry = (type == ORDER_TYPE_BUY ? ask : bid);
   int mtfBias = InpUseMTF ? GetMTFBias(entry) : 0;
   double atrPoints = GetATRPoints();

   if (type == ORDER_TYPE_BUY && InpBlockCounterHTF && mtfBias < 0)
   {
      statHTF++;
      return;
   }
   if (type == ORDER_TYPE_SELL && InpBlockCounterHTF && mtfBias > 0)
   {
      statHTF++;
      return;
   }

   // Level logic baru
   double vsl, fail, hardSL;
   CalculateRecoveryLevels(type == ORDER_TYPE_BUY, signalPrice, vsl, fail, hardSL);

   // Broker hanya melihat Hard SL
   double brokerSL = (InpUseHardSL ? hardSL : 0.0);

   double tp = (InpExitMode == EXIT_FIX_TP) ? (type == ORDER_TYPE_BUY ? NormalizeDouble(ask + (atr * InpFixedTPATR), _Digits) : NormalizeDouble(bid - (atr * InpFixedTPATR), _Digits)) : (type == ORDER_TYPE_BUY ? NormalizeDouble(sr.Resistance(), _Digits) : NormalizeDouble(sr.Support(), _Digits));

   string reason;
   if (!ValidateOrderLevels(type, entry, brokerSL, tp, reason))
   {
      statTPDist++;
      market.DebugLog(reason);
      return;
   }

   bool result = false;
   if (type == ORDER_TYPE_BUY)
      result = trade.Buy(InpLotSize, _Symbol, ask, brokerSL, tp, BuildComment("BUY", mtfBias));
   else
      result = trade.Sell(InpLotSize, _Symbol, bid, brokerSL, tp, BuildComment("SELL", mtfBias));

   if (result)
   {
      statSignalsPassed++;
      ulong ticket = trade.ResultOrder(); // DebugLog removed, should be handled by ExecutionManager's own DebugLog
      if (ticket == 0)
         ticket = trade.ResultDeal(); // Safety for some brokers

      statTradesToday++;
      lastEntryBarTime = iTime(_Symbol, _Period, 0);

      if (type == ORDER_TYPE_BUY)
      {
         lastBuyZonePrice = sr.Support();
         lastBuyZoneBar = lastEntryBarTime;
      }
      else
      {
         lastSellZonePrice = sr.Resistance();
         lastSellZoneBar = lastEntryBarTime;
      }

      // Daftarkan ke Engine
      InitTradeEngine(ticket, type, entry, tp, brokerSL, vsl, fail, hardSL, atrPoints);

      if (InpSendPush)
      {
         string msg = (type == ORDER_TYPE_BUY ? "PASR BUY OPENED" : "PASR SELL OPENED");
         msg += "\nSupport: " + DoubleToString(sr.Support(), _Digits);
         msg += "\nResistance: " + DoubleToString(sr.Resistance(), _Digits);
         // SendNotification(msg); // This should be handled by a NotificationManager
      }
   }
}

void CalculateRecoveryLevels(bool isBuy, double signalPrice, double &vsl, double &fail, double &hardSL)
{
   double buffer = (GetATRPoints() * InpATRBufferMult) * _Point;
   double fixedSL = (GetATRPoints() * InpFixedSLATR) * _Point;
   double hardDist = (GetATRPoints() * InpHardSLATR) * _Point;

   if (isBuy)
   {
      vsl = MathMin(sr.Support(), signalPrice - fixedSL);
      fail = vsl - buffer;
      hardSL = fail - hardDist;
   }
   else
   {
      vsl = MathMax(sr.Resistance(), signalPrice + fixedSL);
      fail = vsl + buffer;
      hardSL = fail + hardDist;
   }
   vsl = NormalizeDouble(vsl, _Digits);
   fail = NormalizeDouble(fail, _Digits);
   hardSL = NormalizeDouble(hardSL, _Digits);
}
void InitTradeEngine(ulong ticket, ENUM_ORDER_TYPE type, double entry, double tp, double sl, double vsl, double fail, double hard, double atr)
{
   for (int i = 0; i < 10; i++)
   {
      if (!tradeEngines[i].active)
      {
         tradeEngines[i].Reset();
         tradeEngines[i].active = true;
         tradeEngines[i].mainTicket = ticket;
         tradeEngines[i].direction = (type == ORDER_TYPE_BUY ? 1 : -1);
         tradeEngines[i].state = TRADE_STATE_NORMAL;
         tradeEngines[i].entryPrice = entry;
         tradeEngines[i].initialTP = tp;
         tradeEngines[i].brokerSL = sl;
         tradeEngines[i].vslPrice = vsl;
         tradeEngines[i].failPrice = fail;
         tradeEngines[i].hardStopLoss = hard;
         tradeEngines[i].lastKnownATR = atr;
         tradeEngines[i].partialClosed = false;
         tradeEngines[i].entryTime = TimeCurrent();
         break;
      }
   }
}

void UpdateRecoveryEngine(RecoveryEngine &r, const MqlTick &tick)
{
   if (!r.active)
      return;
   if (!PositionSelectByTicket(r.mainTicket))
   {
      r.Reset();
      return;
   }

   double curPrice = (r.direction > 0 ? tick.bid : tick.ask);
   double atrPoints = GetATRPoints();

   switch (r.state)
   {
   case TRADE_STATE_NORMAL:
      // Cek apakah harga menyentuh VSL menggunakan curPrice yang sudah direction-aware
      if ((r.direction > 0 && curPrice <= r.vslPrice) || (r.direction < 0 && curPrice >= r.vslPrice))
      {
         r.state = TRADE_STATE_VSL_HIT;
         r.vslHitTime = TimeCurrent();
         DebugLog("VSL Hit on Ticket " + (string)r.mainTicket);
         // Fall-through: Lanjut eksekusi case VSL_HIT di tick yang sama
      }
      else
         break;

   case TRADE_STATE_VSL_HIT:
   {
      // Ambil SL aktual dari posisi (mungkin sudah berubah karena Trailing Stop di fase NORMAL)
      double currentSL = PositionGetDouble(POSITION_SL);

      // Hitung variabel jarak menggunakan ATR
      double beDist = (atrPoints * InpRecoveryBEOffsetATR) * _Point;
      double pcDist = (atrPoints * InpPartialCloseATR) * _Point;
      double pbDist = (atrPoints * InpRecoveryPullbackATR) * _Point;

      // Logic TP: Target minimal adalah BE, maksimal adalah Pullback dari harga saat ini
      if (r.direction > 0)
         r.recoveryTP = MathMax(r.entryPrice + beDist, curPrice + pbDist);
      else
         r.recoveryTP = MathMin(r.entryPrice - beDist, curPrice - pbDist);

      r.partialTP = NormalizeDouble(r.entryPrice + (r.direction * pcDist), _Digits);
      r.recoveryTP = NormalizeDouble(r.recoveryTP, _Digits);

      // Validasi SYMBOL_TRADE_STOPS_LEVEL agar modifikasi tidak ditolak broker
      double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      bool isTooClose = (r.direction > 0) ? (r.recoveryTP - curPrice < stopLevel) : (curPrice - r.recoveryTP < stopLevel);

      if (isTooClose)
      {
         if (r.direction > 0)
            r.recoveryTP = NormalizeDouble(curPrice + stopLevel + _Point, _Digits);
         else
            r.recoveryTP = NormalizeDouble(curPrice - stopLevel - _Point, _Digits);
      }

      // Lakukan modifikasi. r.brokerSL diupdate agar sinkron jika nanti butuh modifikasi SL lagi.
      if (trade.PositionModify(r.mainTicket, currentSL, r.recoveryTP))
      {
         r.state = TRADE_STATE_SELF_RECOVERY;
         r.recoveryStartTime = TimeCurrent();
         r.brokerSL = currentSL;
      }
      else
      {
         uint retCode = trade.ResultRetcode();
         // Error 10006 (No changes) atau 10025 (Request in progress) dianggap sukses transisi state
         if (retCode == 10006 || retCode == 10025)
         {
            r.state = TRADE_STATE_SELF_RECOVERY;
            r.recoveryStartTime = TimeCurrent();
            r.brokerSL = currentSL;
         } // DebugLog removed, should be handled by RecoveryManager's own DebugLog
         else
            market.DebugLog("VSL_HIT: Modify failed. Code: " + (string)retCode);
      }
      break;
   }

   case TRADE_STATE_SELF_RECOVERY:
   {
      // 1. Ambil data volume terbaru untuk kalkulasi Partial Close
      double currentLot = PositionGetDouble(POSITION_VOLUME);

      // Logic Partial Close (Virtual TP)
      if (InpUsePartialClose && !r.partialClosed && currentLot > 0)
      {
         bool pcTrigger = (r.direction > 0) ? (tick.bid >= r.partialTP) : (tick.ask <= r.partialTP);
         if (pcTrigger)
         {
            double closeLot = NormalizeVolume(currentLot * InpPartialCloseLotPct);
            if (trade.PositionClosePartial(r.mainTicket, closeLot))
            {
               r.partialClosed = true;
               market.DebugLog("Partial Close Executed (Virtual TP) on Ticket " + (string)r.mainTicket);
            }
            else
            {
               uint retCode = trade.ResultRetcode();
               // Kode 10009 (Done) atau 10008 (Placed) dianggap sukses agar tidak spam
               if (retCode == 10009 || retCode == 10008 || retCode == 10025)
                  r.partialClosed = true; // DebugLog removed, should be handled by RecoveryManager's own DebugLog
               else
                  market.DebugLog("Partial Close Failed. Code: " + (string)retCode);
            }
         }
      }

      // 2. Cek Kegagalan (Confirmed)
      double confirmDist = (atrPoints * InpFailureConfirmATR) * _Point;
      bool priceFailed = (r.direction > 0) ? (tick.bid < r.failPrice - confirmDist) : (tick.ask > r.failPrice + confirmDist);

      // Cek Close Candle Konfirmasi
      double lastClose = iClose(_Symbol, _Period, 1);
      bool candleFailed = (r.direction > 0) ? (lastClose < r.failPrice) : (lastClose > r.failPrice);

      if (priceFailed || candleFailed)
      {
         r.state = TRADE_STATE_FAILED_CONFIRMED;
         r.failureTime = TimeCurrent();
         r.hedgeEligible = true; // DebugLog removed, should be handled by RecoveryManager's own DebugLog
         market.DebugLog("Failure Confirmed on Ticket " + (string)r.mainTicket);
         break;
      }

      // 3. Cek Timeout (Berdasarkan jumlah bar sejak VSL tersentuh)
      int barsSinceVsl = (int)((TimeCurrent() - r.vslHitTime) / PeriodSeconds(_Period));
      if (barsSinceVsl >= InpRecoveryMaxBars)
      {
         r.state = TRADE_STATE_FAILED_CONFIRMED;
         r.failureTime = TimeCurrent();
         r.hedgeEligible = true; // DebugLog removed, should be handled by RecoveryManager's own DebugLog
         market.DebugLog("Recovery Timeout on Ticket " + (string)r.mainTicket);
      }
      break;
   }

   case TRADE_STATE_FAILED_CONFIRMED:
      if (InpUseHedging && r.hedgeEligible)
      {
         TryActivateHedge(r);
      }
      break;

   case TRADE_STATE_HEDGE_ACTIVE:
      ManageRecoveryBasketByEngine(r);
      break;
   }
}

bool IsRecoveryActive()
{
   for (int i = 0; i < 10; i++)
      if (tradeEngines[i].active && tradeEngines[i].state == TRADE_STATE_HEDGE_ACTIVE)
         return true;
   return false;
}

int GetMTFBias(double price)
{
   double zone = (GetATRPoints() * InpATRBufferMult) * _Point;
   bool nearHtfSupport = (price <= sr.HTFSupport() + zone);
   bool nearHtfResistance = (price >= sr.HTFResistance() - zone);

   if (nearHtfSupport && !nearHtfResistance)
      return 1;
   if (nearHtfResistance && !nearHtfSupport)
      return -1;
   return 0;
}

bool ValidateOrderLevels(ENUM_ORDER_TYPE type, double price, double sl, double tp, string &reason)
{
   double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double minTPDist = GetATRPoints() * InpMinTPDistanceATR * _Point;
   double requiredTP = MathMax(stopLevel, minTPDist);

   if (type == ORDER_TYPE_BUY)
   {
      if (tp <= price)
      {
         reason = "BUY TP invalid";
         return false;
      }
      if (sl >= price)
      {
         reason = "BUY SL invalid";
         return false;
      }
      if (tp - price < requiredTP)
      {
         reason = "BUY TP too close";
         return false;
      }
      if (price - sl < stopLevel)
      {
         reason = "BUY SL too close";
         return false;
      }
   }
   else
   {
      if (tp >= price)
      {
         reason = "SELL TP invalid";
         return false;
      }
      if (sl <= price)
      {
         reason = "SELL SL invalid";
         return false;
      }
      if (price - tp < requiredTP)
      {
         reason = "SELL TP too close";
         return false;
      }
      if (sl - price < stopLevel)
      {
         reason = "SELL SL too close";
         return false;
      }
   }

   reason = "OK";
   return true;
}

void ScanAndProcessPositions(const MqlTick &tick)
{
   posScan.normalCount = 0;
   posScan.hedgeCount = 0;
   posScan.buyCount = 0;
   posScan.sellCount = 0;
   posScan.totalProfit = 0.0;

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if (PositionGetInteger(POSITION_MAGIC) != InpMagicNum)
         continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      string comment = PositionGetString(POSITION_COMMENT);
      long posType = PositionGetInteger(POSITION_TYPE);
      double profit = PositionGetDouble(POSITION_PROFIT);

      posScan.totalProfit += profit;

      bool isHedge = (StringFind(comment, "HEDGE") >= 0);

      if (isHedge)
      {
         posScan.hedgeCount++;
      }
      else
      {
         posScan.normalCount++;
         if (posType == POSITION_TYPE_BUY)
            posScan.buyCount++;
         if (posType == POSITION_TYPE_SELL)
            posScan.sellCount++;
      }

      // Jalankan Engine untuk setiap posisi PASR (bukan hedge)
      if (!isHedge)
      {
         int engineIdx = GetEngineIndexForTicket(ticket);
         if (engineIdx != -1)
         {
            if (tradeEngines[engineIdx].state == TRADE_STATE_NORMAL)
               ApplyNormalTrailing(ticket, tick);
            UpdateRecoveryEngine(tradeEngines[engineIdx], tick);
         }
      }
   }

   // Update cache global untuk dashboard
   cachedNormalPositions = posScan.normalCount;
   cachedHedgePositions = posScan.hedgeCount;
   cachedTotalProfit = posScan.totalProfit;
}

int GetEngineIndexForTicket(ulong ticket)
{
   for (int i = 0; i < 10; i++)
      if (tradeEngines[i].active && tradeEngines[i].mainTicket == ticket)
         return i;
   return -1;
}

void ApplyNormalTrailing(ulong ticket, const MqlTick &tick)
{
   if (!PositionSelectByTicket(ticket))
      return;
   if (!InpUseTrailing)
      return;

   long type = PositionGetInteger(POSITION_TYPE);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double slPrice = PositionGetDouble(POSITION_SL);
   double tpPrice = PositionGetDouble(POSITION_TP);
   double atr = GetATRPoints() * _Point;

   // Gunakan snapshot harga dari tick yang di-pass agar konsisten
   double curPrice = (type == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
   double newSL = slPrice;

   if (type == POSITION_TYPE_BUY)
   {
      double profitPips = (curPrice - openPrice) / _Point;

      if (profitPips >= InpTrailingStartPips)
         newSL = MathMax(newSL, openPrice + (InpTrailingBufferPips * _Point));

      if (InpExitMode == EXIT_PARTIAL_LOCK && (curPrice - openPrice) >= (atr * InpLockProfitATR))
         newSL = MathMax(newSL, openPrice + (atr * InpLockLevelATR));

      if ((curPrice - openPrice) >= (atr * InpTrailActivationATR))
         newSL = MathMax(newSL, curPrice - (atr * InpTrailStepATR));

      if (newSL > slPrice && (curPrice - newSL) > SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point)
         trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), tpPrice);
   }
   else if (type == POSITION_TYPE_SELL)
   {
      double profitPips = (openPrice - curPrice) / _Point;

      if (profitPips >= InpTrailingStartPips)
      {
         double beLevel = openPrice - (InpTrailingBufferPips * _Point);
         newSL = (newSL == 0.0 ? beLevel : MathMin(newSL, beLevel));
      }

      if (InpExitMode == EXIT_PARTIAL_LOCK && (openPrice - curPrice) >= (atr * InpLockProfitATR))
      {
         double lockLevel = openPrice - (atr * InpLockLevelATR);
         newSL = (newSL == 0.0 ? lockLevel : MathMin(newSL, lockLevel));
      }

      if ((openPrice - curPrice) >= (atr * InpTrailActivationATR))
      {
         double trailLevel = curPrice + (atr * InpTrailStepATR);
         newSL = (newSL == 0.0 ? trailLevel : MathMin(newSL, trailLevel));
      }

      if ((slPrice == 0.0 || newSL < slPrice) && (newSL - curPrice) > SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point)
         trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), tpPrice);
   }
}

bool OpenHedgeOrder(long sourceType, double lot, double hedgeSL, ulong sourceTicket)
{
   string hedgeComment = "PASR_HEDGE_" + IntegerToString(sourceTicket);
   if (sourceType == POSITION_TYPE_BUY)
      return trade.Sell(lot, _Symbol, 0.0, hedgeSL, 0.0, hedgeComment);
   return trade.Buy(lot, _Symbol, 0.0, hedgeSL, 0.0, hedgeComment);
}

double CalcRecoveryTargetMoney(ulong sourceTicket)
{
   if (!PositionSelectByTicket(sourceTicket))
      return 0.0;

   double volume = PositionGetDouble(POSITION_VOLUME);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if (tickValue <= 0.0 || tickSize <= 0.0)
      return 0.0;

   double perPointValue = tickValue / tickSize;
   return GetATRPoints() * InpATRRecovery * volume * perPointValue;
}

void TryActivateHedge(RecoveryEngine &r)
{
   double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if (spread > InpMaxSpread)
      return;

   if (!PositionSelectByTicket(r.mainTicket))
      return;
   double lot = PositionGetDouble(POSITION_VOLUME);
   double hedgeLot = NormalizeVolume(lot * InpLayer1LotMult);

   double curPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
   double hedgeSLDist = (GetATRPoints() * InpATRHedgeSL) * _Point;
   double hedgeSL = (r.direction > 0) ? curPrice + hedgeSLDist : curPrice - hedgeSLDist;

   if (OpenHedgeOrder((r.direction > 0 ? POSITION_TYPE_BUY : POSITION_TYPE_SELL), hedgeLot, hedgeSL, r.mainTicket))
   {
      r.hedgeTicket = trade.ResultOrder();
      if (r.hedgeTicket == 0)
         r.hedgeTicket = trade.ResultDeal();
      r.state = TRADE_STATE_HEDGE_ACTIVE;
      r.hedgeOpenTime = TimeCurrent();
      r.recoveryStartTime = TimeCurrent(); // DebugLog removed, should be handled by RecoveryManager's own DebugLog
      market.DebugLog("Hedge Opened for Ticket " + (string)r.mainTicket);
   }
}

void ManageRecoveryBasketByEngine(RecoveryEngine &r)
{
   double totalNetProfit = 0.0;

   // 1. Hitung Profit Bersih posisi utama
   if (PositionSelectByTicket(r.mainTicket))
      totalNetProfit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) + PositionGetDouble(POSITION_COMMISSION);

   // 2. Tambahkan Profit Bersih posisi hedge
   if (PositionSelectByTicket(r.hedgeTicket))
      totalNetProfit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) + PositionGetDouble(POSITION_COMMISSION);

   double target = CalcRecoveryTargetMoney(r.mainTicket);
   double beTarget = target * InpATRBankProfit;
   int bars = (int)((TimeCurrent() - r.hedgeOpenTime) / PeriodSeconds(_Period));

   // 3. Cek Target Profit Basket
   if (totalNetProfit >= target)
   {
      CloseEngineBasket(r, "RECOVERY_TARGET");
      return;
   }

   // 4. Logic Break-even Pullback (Penyelamatan awal)
   double midDist = (GetATRPoints() * 0.5) * _Point;
   if (PositionSelectByTicket(r.mainTicket))
   {
      bool backAtMid = MathAbs(PositionGetDouble(POSITION_PRICE_CURRENT) - r.entryPrice) <= midDist;
      if (totalNetProfit >= beTarget && backAtMid)
      {
         CloseEngineBasket(r, "RECOVERY_BE_PULLBACK");
         return;
      }
   }

   // 5. Cek Batas Waktu (Timeout)
   if (bars >= InpMaxHedgeBars)
   {
      CloseEngineBasket(r, "RECOVERY_TIMEOUT");
      return;
   }
}

void CloseEngineBasket(RecoveryEngine &r, string reason)
{
   if (PositionSelectByTicket(r.mainTicket))
      trade.PositionClose(r.mainTicket);
   if (PositionSelectByTicket(r.hedgeTicket))
      trade.PositionClose(r.hedgeTicket);

   if (reason == "RECOVERY_TARGET" || reason == "RECOVERY_BE_PULLBACK")
      statHedgeSave++;
   else
      statHedgeFail++;

   r.Reset();
   market.DebugLog("Basket Closed: " + reason);
}

void DrawDashboard(const MqlTick &tick)
{
   string text = "------------------------------------------\n";
   text += " EA NAME: PASR V2\n";
   text += " STATUS: " + market.GetNewsStatus() + "\n";
   text += " SESSION: " + (IsTradingSession() ? "OPEN" : "CLOSED") + "\n";
   text += " MODE: " + EnumToString(InpEntryMode) + " | SR: " + EnumToString(InpSRMode) + "\n";
   text += " EXIT: " + EnumToString(InpExitMode) + " (" + (InpUseTrailing ? "Trail ON" : "Trail OFF") + ")\n";
   text += " TRADES TODAY: " + (string)statTradesToday + "\n";
   text += " SIGNALS (OK/REJ): " + (string)statSignalsPassed + " / " + (string)(statTotalSignals - statSignalsPassed) + "\n";
   text += " S&R: " + DoubleToString(sr.Support(), _Digits) + " / " + DoubleToString(sr.Resistance(), _Digits) + "\n";
   if (InpUseMTF)
      text += " HTF: " + DoubleToString(sr.HTFSupport(), _Digits) + " / " + DoubleToString(sr.HTFResistance(), _Digits) + "\n";
   text += " SPREAD: " + DoubleToString((tick.ask - tick.bid) / _Point, _Digits) + "\n";
   text += " ATR: " + DoubleToString(market.GetATRPoints(), 1) + " pts\n";
   text += " DD LOCK: " + string(market.IsDailyLossLimitHit() ? "ON" : "OFF") + "\n";
   text += " HEDGE: " + (IsRecoveryActive() ? "ACTIVE" : "OFF") + "\n"; // IsRecoveryActive() needs to be updated to use RecoveryManager
   text += "------------------------------------------";
   Comment(text);
}

// ResetDailyAnchor() moved to MarketManager
// ResetDailyAnchorIfNeeded() moved to MarketManager
// IsDailyLossLimitHit() moved to MarketManager

double NormalizeVolume(double vol)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   // This function should be in ExecutionManager or a utility class
   if (stepLot <= 0.0)
      return vol;

   vol = MathMax(minLot, MathMin(maxLot, vol));
   vol = MathFloor(vol / stepLot) * stepLot;

   int digits = 2;
   if (stepLot == 1.0)
      digits = 0;
   else if (stepLot == 0.1)
      digits = 1;
   else if (stepLot == 0.01)
      digits = 2;
   else if (stepLot == 0.001)
      digits = 3;

   return NormalizeDouble(vol, digits);
}

// GetATRPoints() moved to MarketManager

bool HasHedgePosition()
{
   return cachedHedgePositions > 0;
}

// IsEntryCooldownActive() moved to MarketManager

string BuildComment(string type, int bias)
{
   // This function should be in ExecutionManager
   string b = " [B0]";
   if (bias > 0)
      b = " [B+]";
   else if (bias < 0)
      b = " [B-]";
   return "PASR_" + type + b;
}

// DebugLog() moved to MarketManager (for market-related logs)
