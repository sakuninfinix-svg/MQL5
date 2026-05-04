//+------------------------------------------------------------------+
//|                                                    SIS EA (MT5)  |
//|     Grid Pending Buy/Sell Stop by Distance - TP di Next Layer    |
//|                       © 2025 HA (SIS EA)                |
//+------------------------------------------------------------------+
#property copyright "© 2025 HA"
#property version "1.01"
#property strict

#include <Trade/Trade.mqh>

enum DirectionMode
{
   DIR_BOTH = 0,
   DIR_BUY_ONLY = 1,
   DIR_SELL_ONLY = 2
};

input group "── SIS EA - Grid Settings ──" input DirectionMode Direction = DIR_BOTH; // Arah
input bool UsePips = true;                                                           // Step & SL input dalam pips?
input double StepSize = 50.0;                                                        // Jarak antar layer (pips jika UsePips=true, else points)
input int PendingPerSide = 10;                                                       // Minimal pending per sisi (total ≈ 2x)
input bool UseStaticAnchor = true;                                                   // Anchor grid saat start
input double RecenterAfterSteps = 0;                                                 // 0=off; recenter jika harga geser > N step dari anchor

input group "── Order & TP/SL ──" input bool UseNextLayerTP = true; // TP = next layer (disarankan ON)
input bool UseSL = false;                                           // Pakai SL?
input double SL_Size = 150.0;                                       // Besar SL (pips/points sesuai UsePips)
input int ExpirationMinutes = 0;                                    // 0 = GTC (tidak kadaluarsa)

input group "── Lot & Risk ──" input bool UseAutoLot = false; // Lot otomatis by Risk%
input double FixedLot = 0.10;                                 // Lot tetap
input double RiskPercent = 1.0;                               // % balance per trade (butuh SL aktif)
input double MinLot = 0.01;                                   // Batas lot
input double MaxLot = 100.0;                                  // Batas lot

input group "── Proteksi ──" input int MagicNumber = 556677; // Magic EA
input int MaxSpreadPoints = 200;                             // Maks spread (points)
input int CloseIfPositionsGT = 3;                            // Jika posisi aktif > nilai ini → close semua posisi EA
input int MaxTotalPositionsCap = 200;                        // Batas hard total posisi untuk EA ini
input bool UseEquityStop = false;                            // Hentikan & close semua bila ekuitas turun X%
input double EquityStopPercent = 20.0;                       // Turun % dari balance saat start

input group "── Sesi Trading (opsional) ──" input bool UseSession = false; // Batasi jam trading
input int SessionStartHour = 7;                                            // Jam mulai (broker time)
input int SessionEndHour = 22;                                             // Jam akhir (broker time)

input group "── Visual ──" input bool ShowPanel = true;

CTrade trade;

string EA_NAME = "SIS EA";
double g_anchor = 0.0;
double g_start_balance = 0.0;
datetime g_last_recenter = 0;

//--- util: normalisasi harga ke tick size
double NormalizePrice(double price)
{
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if (ts <= 0)
      ts = _Point;
   double p = MathRound(price / ts) * ts;
   return NormalizeDouble(p, (int)_Digits);
}

//--- util: nilai 1 pip dalam harga
double PipSize()
{
   if (_Digits == 3 || _Digits == 5)
      return 10.0 * _Point;
   return _Point;
}

//--- util: konversi step input → delta harga
double StepToPrice(double val)
{
   return UsePips ? (val * PipSize()) : (val * _Point);
}

//--- cek jam sesi (FIX untuk MT5: gunakan TimeToStruct)
bool InSession()
{
   if (!UseSession)
      return true;

   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm); // ambil waktu server saat ini
   int h = tm.hour;

   if (SessionStartHour == SessionEndHour)
      return true; // full day
   if (SessionStartHour < SessionEndHour)
      return (h >= SessionStartHour && h < SessionEndHour);
   // overnight window (contoh 22 → 7)
   return (h >= SessionStartHour || h < SessionEndHour);
}

//--- spread check
bool SpreadOK()
{
   double spread_points = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
   return (spread_points <= MaxSpreadPoints);
}

//--- hitung posisi aktif EA untuk symbol ini
int CountActivePositions()
{
   int cnt = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0)
         continue;
      if (!PositionSelectByTicket(ticket))
         continue;
      if ((string)PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if ((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      cnt++;
   }
   return cnt;
}

//--- close semua posisi EA di symbol
void CloseAllPositions()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0)
         continue;
      if (!PositionSelectByTicket(ticket))
         continue;
      if ((string)PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if ((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      trade.PositionClose(ticket);
   }
}

//--- order pending exist at price/type?
bool PendingExists(ENUM_ORDER_TYPE type, double price, double tol_points = 2.0)
{
   double tol = tol_points * _Point;
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if (ticket == 0)
         continue;
      if ((string)OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if ((int)OrderGetInteger(ORDER_MAGIC) != MagicNumber)
         continue;
      if ((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != type)
         continue;
      double p = OrderGetDouble(ORDER_PRICE_OPEN);
      if (MathAbs(p - price) <= tol)
         return true;
   }
   return false;
}

//--- hitung lot by risk
double CalcRiskLot(double entry, double sl)
{
   if (!UseAutoLot || !UseSL || SL_Size <= 0.0)
      return FixedLot;
   double dist = MathAbs(entry - sl);
   double tick_val = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_sz = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if (tick_val <= 0 || tick_sz <= 0 || dist <= 0)
      return FixedLot;
   double money_risk = (AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent) / 100.0;
   double money_per_lot = (dist / tick_sz) * tick_val;
   if (money_per_lot <= 0)
      return FixedLot;
   double lot = money_risk / money_per_lot;

   double minlot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxlot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double steplot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if (minlot <= 0)
      minlot = MinLot;
   if (maxlot <= 0)
      maxlot = MaxLot;
   if (steplot <= 0)
      steplot = 0.01;
   lot = MathMax(minlot, MathMin(maxlot, lot));
   lot = MathFloor(lot / steplot) * steplot;
   lot = NormalizeDouble(lot, 2);
   if (lot < minlot)
      lot = minlot;
   return lot;
}

//--- kirim pending
bool PlacePending(ENUM_ORDER_TYPE type, double price, double sl, double tp, double lot, datetime expi)
{
   if (lot <= 0)
      return false;
   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action = TRADE_ACTION_PENDING;
   req.symbol = _Symbol;
   req.magic = MagicNumber;
   req.type = type;
   req.volume = lot;
   req.price = NormalizePrice(price);
   req.sl = (sl > 0 ? NormalizePrice(sl) : 0.0);
   req.tp = (tp > 0 ? NormalizePrice(tp) : 0.0);
   req.type_time = (ExpirationMinutes > 0 ? ORDER_TIME_SPECIFIED : ORDER_TIME_GTC);
   req.expiration = (ExpirationMinutes > 0 ? (TimeCurrent() + ExpirationMinutes * 60) : 0);
   req.type_filling = ORDER_FILLING_FOK;
   req.comment = EA_NAME;
   bool ok = OrderSend(req, res);
   return ok;
}

//--- ensure grid
void EnsureGrid()
{
   if (PendingPerSide <= 0)
      return;

   double step = StepToPrice(StepSize);
   if (step <= 0)
      return;

   // recenter jika diminta
   if (RecenterAfterSteps > 0 && UseStaticAnchor)
   {
      double mid = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) + SymbolInfoDouble(_Symbol, SYMBOL_BID)) / 2.0;
      if (MathAbs(mid - g_anchor) >= (RecenterAfterSteps * step))
      {
         g_anchor = mid;
         g_last_recenter = TimeCurrent();
      }
   }

   int need_buy = (Direction != DIR_SELL_ONLY) ? PendingPerSide : 0;
   int need_sell = (Direction != DIR_BUY_ONLY) ? PendingPerSide : 0;

   int have_buy = 0, have_sell = 0;
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if (ticket == 0)
         continue;
      if ((string)OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if ((int)OrderGetInteger(ORDER_MAGIC) != MagicNumber)
         continue;
      ENUM_ORDER_TYPE t = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if (t == ORDER_TYPE_BUY_STOP)
         have_buy++;
      if (t == ORDER_TYPE_SELL_STOP)
         have_sell++;
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int stops_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double min_stop = stops_level * _Point;

   // BUY STOP di atas anchor
   for (int k = 1; (have_buy < need_buy) && k <= need_buy * 2; k++)
   {
      if (Direction == DIR_SELL_ONLY)
         break;
      double p = NormalizePrice((UseStaticAnchor ? g_anchor : ask) + k * step);
      if (p <= ask + min_stop)
         continue;
      if (PendingExists(ORDER_TYPE_BUY_STOP, p))
         continue;

      double tp = UseNextLayerTP ? NormalizePrice(p + step) : 0.0;
      double sl = 0.0;
      if (UseSL && SL_Size > 0)
      {
         sl = NormalizePrice(p - StepToPrice(SL_Size));
         if (sl >= p - min_stop)
            sl = 0.0;
      }
      double lot = CalcRiskLot(p, sl);
      if (!SpreadOK())
         break;
      if (PlacePending(ORDER_TYPE_BUY_STOP, p, sl, tp, lot, 0))
         have_buy++;
   }

   // SELL STOP di bawah anchor
   for (int k = 1; (have_sell < need_sell) && k <= need_sell * 2; k++)
   {
      if (Direction == DIR_BUY_ONLY)
         break;
      double p = NormalizePrice((UseStaticAnchor ? g_anchor : bid) - k * step);
      if (p >= bid - min_stop)
         continue;
      if (PendingExists(ORDER_TYPE_SELL_STOP, p))
         continue;

      double tp = UseNextLayerTP ? NormalizePrice(p - step) : 0.0;
      double sl = 0.0;
      if (UseSL && SL_Size > 0)
      {
         sl = NormalizePrice(p + StepToPrice(SL_Size));
         if (sl <= p + min_stop)
            sl = 0.0;
      }
      double lot = CalcRiskLot(p, sl);
      if (!SpreadOK())
         break;
      if (PlacePending(ORDER_TYPE_SELL_STOP, p, sl, tp, lot, 0))
         have_sell++;
   }
}

//--- OnInit
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   g_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   g_anchor = (ask + bid) / 2.0;
   return (INIT_SUCCEEDED);
}

//--- OnTick
void OnTick()
{
   if (!InSession())
      return;
   if (!SpreadOK())
      return;

   if (UseEquityStop)
   {
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      if (eq <= g_start_balance * (1.0 - EquityStopPercent / 100.0))
      {
         CloseAllPositions();
         return;
      }
   }

   int active = CountActivePositions();
   if (active > CloseIfPositionsGT)
   {
      CloseAllPositions();
   }

   int totalEA = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if (t == 0)
         continue;
      if (!PositionSelectByTicket(t))
         continue;
      if ((string)PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if ((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      totalEA++;
   }
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong t = OrderGetTicket(i);
      if (t == 0)
         continue;
      if ((string)OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if ((int)OrderGetInteger(ORDER_MAGIC) != MagicNumber)
         continue;
      totalEA++;
   }
   if (totalEA > MaxTotalPositionsCap)
      return;

   EnsureGrid();

   if (ShowPanel)
   {
      string s;
      double step = StepToPrice(StepSize);
      double spread_pts = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
      s += EA_NAME + "  |  " + _Symbol + "\n";
      s += "Anchor: " + DoubleToString(g_anchor, _Digits) + "  Step: " + DoubleToString(step, _Digits) + "\n";
      s += "Digits: " + (string)_Digits + "  SpreadPts: " + DoubleToString(spread_pts, 1) + "  Magic: " + (string)MagicNumber + "\n";
      s += "ActivePos: " + (string)CountActivePositions() + "  Pending: " + (string)OrdersTotal() + "\n";
      s += "CloseIfPos> " + (string)CloseIfPositionsGT + " | AutoLot=" + (UseAutoLot ? "ON" : "OFF") + " | SL=" + (UseSL ? "ON" : "OFF") + " | TP next layer=" + (UseNextLayerTP ? "ON" : "OFF") + "\n";
      Comment(s);
   }
}

//--- OnTradeTransaction (disengaja kosong)
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
}
