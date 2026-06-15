//+------------------------------------------------------------------+
//| PASR_DATA_EXPORTER.mq5                                           |
//| Export trade data from MT5 Strategy Tester to CSV for ML training |
//|                                                                  |
//| How to use:                                                      |
//|   1. Open MT5 → Strategy Tester → Select this EA                 |
//|   2. Select symbol & timeframe (e.g., EURUSD H1)                 |
//|   3. Set date range (e.g., 2023-2024 for ~12 months)             |
//|   4. Run backtest                                                |
//|   5. CSV file saved to: MT5/MQL5/Files/PASR_trades_export.csv    |
//|   6. Copy CSV to project: MQL5/tools/output/                     |
//|   7. Run: python3 training/import_mt5_trades.py                  |
//+------------------------------------------------------------------+
#property strict
#property description "PASR Trade Data Exporter — exports trade log to CSV for ML training"
#property description "Run in Strategy Tester, then import CSV with import_mt5_trades.py"

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/HistoryOrderInfo.mqh>
#include <Trade/AccountInfo.mqh>

// --- Inputs ---
input group "=== PASR Data Exporter ==="
input long   InpMagicNumber = 123456;
input double InpLotSize = 0.1;
input double InpSLMultiplier = 1.8;    // Match generator config
input double InpTPMultiplier = 2.2;    // Match generator config
input int    InpATRPeriod = 14;
input string InpExportFileName = "PASR_trades_export.csv";  // Saved to MQL5/Files/
input string InpOHLCVFileName = "PASR_ohlcv_export.csv";   // OHLCV bars (for feature recomputation)

input group "=== Entry Strategy (simple trend-following) ==="
input int    InpMAPeriod = 20;          // MA for trend direction
input double InpEntryThreshold = 0.0005; // Min ATR-scaled move for entry

// --- Globals ---
CTrade g_trade;
CPositionInfo g_position;
int g_maHandle = INVALID_HANDLE;
double g_maBuffer[];
datetime g_lastBarTime = 0;
int g_fileHandle = INVALID_HANDLE;     // Trade CSV file
int g_ohlcvHandle = INVALID_HANDLE;    // OHLCV CSV file
int g_totalExported = 0;
int g_totalOHLCV = 0;
bool g_ohlcvHeaderWritten = false;

// Structure to track entry features per position
struct TradeRecord {
   ulong     ticket;
   datetime  entryTime;
   datetime  exitTime;
   int       direction;     // 1=buy, -1=sell
   double    entryPrice;
   double    exitPrice;
   double    slPrice;
   double    tpPrice;
   double    profitPips;
   double    profitR;
   bool      hitTP;
   bool      hitSL;
   int       durationBars;
   double    atrAtEntry;
   double    rsiAtEntry;
   double    maAtEntry;
};
TradeRecord g_pendingRecords[];  // Trades waiting for exit

//+------------------------------------------------------------------+
//| Helper: Get RSI value                                           |
//+------------------------------------------------------------------+
double GetRSI(int shift) {
   int rsiHandle = iRSI(_Symbol, _Period, 14, PRICE_CLOSE);
   if(rsiHandle == INVALID_HANDLE) return 50.0;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(rsiHandle, 0, shift, 1, buf) < 1) return 50.0;
   return buf[0];
}

//+------------------------------------------------------------------+
//| Helper: Get ATR value                                           |
//+------------------------------------------------------------------+
double GetATR(int shift) {
   int atrHandle = iATR(_Symbol, _Period, InpATRPeriod);
   if(atrHandle == INVALID_HANDLE) return 0.0;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(atrHandle, 0, shift, 1, buf) < 1) return 0.0;
   return buf[0];
}

//+------------------------------------------------------------------+
//| Write CSV header
//+------------------------------------------------------------------+
bool InitCSV() {
   g_fileHandle = FileOpen(InpExportFileName, FILE_WRITE|FILE_CSV|FILE_COMMON, ",");
   if(g_fileHandle == INVALID_HANDLE) {
      Print("ERROR: Cannot create file: ", InpExportFileName);
      return false;
   }
   // Header row
   FileWrite(g_fileHandle,
      "ticket", "symbol", "timeframe",
      "entry_time", "exit_time",
      "direction", "entry_price", "exit_price",
      "sl_price", "tp_price",
      "profit_pips", "profit_r",
      "hit_tp", "hit_sl", "duration_bars",
      "atr_at_entry", "rsi_at_entry", "ma_at_entry"
   );
   FileFlush(g_fileHandle);
   Print("CSV initialized: ", InpExportFileName);
   return true;
}

//+------------------------------------------------------------------+
//| Write OHLCV header (called once on first bar)
//+------------------------------------------------------------------+
bool InitOHLCV() {
   g_ohlcvHandle = FileOpen(InpOHLCVFileName, FILE_WRITE|FILE_CSV|FILE_COMMON, ",");
   if(g_ohlcvHandle == INVALID_HANDLE) {
      Print("ERROR: Cannot create OHLCV file: ", InpOHLCVFileName);
      return false;
   }
   FileWrite(g_ohlcvHandle,
      "timestamp", "open", "high", "low", "close", "volume"
   );
   FileFlush(g_ohlcvHandle);
   Print("OHLCV file initialized: ", InpOHLCVFileName);
   return true;
}

//+------------------------------------------------------------------+
//| Write one OHLCV bar to CSV
//+------------------------------------------------------------------+
void WriteOHLCVBar(datetime time) {
   if(g_ohlcvHandle == INVALID_HANDLE) return;
   double open  = iOpen(_Symbol, _Period, 0);
   double high  = iHigh(_Symbol, _Period, 0);
   double low   = iLow(_Symbol, _Period, 0);
   double close = iClose(_Symbol, _Period, 0);
   long volume  = iVolume(_Symbol, _Period, 0);
   
   FileWrite(g_ohlcvHandle,
      (string)time,
      DoubleToString(open, 5),
      DoubleToString(high, 5),
      DoubleToString(low, 5),
      DoubleToString(close, 5),
      (string)volume
   );
   FileFlush(g_ohlcvHandle);
   g_totalOHLCV++;
}

//+------------------------------------------------------------------+
//| Write a trade record to CSV
//+------------------------------------------------------------------+
void WriteTradeToCSV(const TradeRecord &rec) {
   if(g_fileHandle == INVALID_HANDLE) return;
   FileWrite(g_fileHandle,
      (string)rec.ticket,
      _Symbol,
      EnumToString((ENUM_TIMEFRAMES)_Period),
      (string)rec.entryTime,
      (string)rec.exitTime,
      (string)rec.direction,
      DoubleToString(rec.entryPrice, 5),
      DoubleToString(rec.exitPrice, 5),
      DoubleToString(rec.slPrice, 5),
      DoubleToString(rec.tpPrice, 5),
      DoubleToString(rec.profitPips, 1),
      DoubleToString(rec.profitR, 2),
      (string)(rec.hitTP ? 1 : 0),
      (string)(rec.hitSL ? 1 : 0),
      (string)rec.durationBars,
      DoubleToString(rec.atrAtEntry, 6),
      DoubleToString(rec.rsiAtEntry, 1),
      DoubleToString(rec.maAtEntry, 5)
   );
   FileFlush(g_fileHandle);
   g_totalExported++;
}

//+------------------------------------------------------------------+
//| Check for entry signal
//+------------------------------------------------------------------+
bool CheckEntry(int &signal) {
   // Simple trend-following: price > MA = buy, price < MA = sell
   double close = iClose(_Symbol, _Period, 1);
   double ma = iMA(_Symbol, _Period, InpMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 1);
   double atr = GetATR(1);

   if(atr <= 0) return false;

   // Need minimum momentum
   double maSlope = iMA(_Symbol, _Period, InpMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 5)
                  - iMA(_Symbol, _Period, InpMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 10);
   
   // Buy: price above MA, MA rising
   if(close > ma + atr * 0.3 && maSlope > 0) {
      signal = 1;
      return true;
   }
   // Sell: price below MA, MA falling
   if(close < ma - atr * 0.3 && maSlope < 0) {
      signal = -1;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Open a trade
//+------------------------------------------------------------------+
ulong OpenTrade(int signal) {
   double price = (signal == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double atr = GetATR(0);
   double sl, tp;
   
   if(signal == 1) {  // Buy
      sl = price - atr * InpSLMultiplier;
      tp = price + atr * InpTPMultiplier;
   } else {  // Sell
      sl = price + atr * InpSLMultiplier;
      tp = price - atr * InpTPMultiplier;
   }

   // Apply minimum stop distance
   double minStop = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(MathAbs(price - sl) < minStop) return 0;

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   if(signal == 1) {
      if(g_trade.Buy(InpLotSize, _Symbol, price, sl, tp, "PASR_EXPORT"))
         return g_trade.ResultOrder();
   } else {
      if(g_trade.Sell(InpLotSize, _Symbol, price, sl, tp, "PASR_EXPORT"))
         return g_trade.ResultOrder();
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Record a new position for tracking
//+------------------------------------------------------------------+
void RecordPosition(ulong ticket, int direction, double entryPrice,
                     double slPrice, double tpPrice) {
   int n = ArraySize(g_pendingRecords);
   ArrayResize(g_pendingRecords, n + 1);
   
   g_pendingRecords[n].ticket = ticket;
   g_pendingRecords[n].entryTime = TimeCurrent();
   g_pendingRecords[n].exitTime = 0;
   g_pendingRecords[n].direction = direction;
   g_pendingRecords[n].entryPrice = entryPrice;
   g_pendingRecords[n].exitPrice = 0;
   g_pendingRecords[n].slPrice = slPrice;
   g_pendingRecords[n].tpPrice = tpPrice;
   g_pendingRecords[n].profitPips = 0;
   g_pendingRecords[n].profitR = 0;
   g_pendingRecords[n].hitTP = false;
   g_pendingRecords[n].hitSL = false;
   g_pendingRecords[n].durationBars = 0;
   g_pendingRecords[n].atrAtEntry = GetATR(0);
   g_pendingRecords[n].rsiAtEntry = GetRSI(0);
   g_pendingRecords[n].maAtEntry = iMA(_Symbol, _Period, InpMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 0);
}

//+------------------------------------------------------------------+
//| Process closed position from history
//+------------------------------------------------------------------+
void ProcessClosedPosition(ulong ticket) {
   // Find in pending records
   int idx = -1;
   for(int i = 0; i < ArraySize(g_pendingRecords); i++) {
      if(g_pendingRecords[i].ticket == ticket) {
         idx = i;
         break;
      }
   }
   if(idx < 0) return;  // Not tracked by us
   
   // Get history order
   CHistoryOrderInfo history;
   if(!history.SelectByIndex(HistoryOrderSelect(ticket))) return;
   
   TradeRecord &rec = g_pendingRecords[idx];
   rec.exitTime = history.TimeDone();
   
   // Calculate profit
   double profit = history.Profit();
   double pointValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(rec.direction == 1) {
      rec.exitPrice = history.Price();
      rec.profitPips = (rec.exitPrice - rec.entryPrice) / pointSize;
   } else {
      rec.exitPrice = history.Price();
      rec.profitPips = (rec.entryPrice - rec.exitPrice) / pointSize;
   }
   
   double slDistPips = MathAbs(rec.entryPrice - rec.slPrice) / pointSize;
   rec.profitR = (slDistPips > 0) ? rec.profitPips / slDistPips : 0.0;
   
   // Determine if TP/SL was hit
   if(rec.direction == 1) {
      rec.hitTP = (rec.exitPrice >= rec.tpPrice - pointSize);
      rec.hitSL = (rec.exitPrice <= rec.slPrice + pointSize);
   } else {
      rec.hitTP = (rec.exitPrice <= rec.tpPrice + pointSize);
      rec.hitSL = (rec.exitPrice >= rec.slPrice - pointSize);
   }
   
   rec.durationBars = (int)((rec.exitTime - rec.entryTime) / PeriodSeconds(_Period));
   
   // Write to CSV
   WriteTradeToCSV(rec);
   
   // Remove from pending
   for(int j = idx; j < ArraySize(g_pendingRecords) - 1; j++)
      g_pendingRecords[j] = g_pendingRecords[j + 1];
   ArrayResize(g_pendingRecords, ArraySize(g_pendingRecords) - 1);
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   // Initialize CSV files
   if(!InitCSV()) {
      Print("Failed to initialize CSV export");
      return INIT_FAILED;
   }
   if(!InitOHLCV()) {
      Print("Failed to initialize OHLCV export");
      return INIT_FAILED;
   }
   
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_maHandle = iMA(_Symbol, _Period, InpMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
   if(g_maHandle == INVALID_HANDLE) {
      Print("ERROR: Cannot create MA indicator");
      return INIT_FAILED;
   }
   
   ArraySetAsSeries(g_maBuffer, true);
   g_totalExported = 0;
   
   // Write first OHLCV bar
   WriteOHLCVBar(iTime(_Symbol, _Period, 0));
   
   Print("PASR Data Exporter initialized");
   Print("  Symbol: ", _Symbol, " TF: ", EnumToString((ENUM_TIMEFRAMES)_Period));
   Print("  Export file: ", InpExportFileName);
   Print("  SL: ", InpSLMultiplier, "x ATR, TP: ", InpTPMultiplier, "x ATR");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   // Flush and close CSV files
   if(g_fileHandle != INVALID_HANDLE) {
      FileClose(g_fileHandle);
      g_fileHandle = INVALID_HANDLE;
   }
   if(g_ohlcvHandle != INVALID_HANDLE) {
      FileClose(g_ohlcvHandle);
      g_ohlcvHandle = INVALID_HANDLE;
   }
   
   // Clean up indicator handles
   if(g_maHandle != INVALID_HANDLE)
      IndicatorRelease(g_maHandle);
   
   Print("PASR Data Exporter deinitialized");
   Print("Total trades exported: ", g_totalExported);
   Print("Total OHLCV bars exported: ", g_totalOHLCV);
   Print("Pending (unclosed) trades: ", ArraySize(g_pendingRecords));
   Print("CSV files:");
   Print("  ", TerminalInfoString(TERMINAL_COMMONDATA_PATH), "\\Files\\", InpExportFileName);
   Print("  ", TerminalInfoString(TERMINAL_COMMONDATA_PATH), "\\Files\\", InpOHLCVFileName);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
   // Check for new bar
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == g_lastBarTime) return;
   g_lastBarTime = currentBarTime;
   
   // Export OHLCV bar on every new bar
   WriteOHLCVBar(currentBarTime);
   
   // --- Entry Logic (on new bar) ---
   // Only enter if no existing positions (simple single-position logic)
   if(PositionsTotal() == 0) {
      int signal = 0;
      if(CheckEntry(signal)) {
         ulong ticket = OpenTrade(signal);
         if(ticket > 0) {
            double entryPrice = (signal == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                              : SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double atr = GetATR(0);
            double sl = (signal == 1) ? entryPrice - atr * InpSLMultiplier
                                      : entryPrice + atr * InpSLMultiplier;
            double tp = (signal == 1) ? entryPrice + atr * InpTPMultiplier
                                      : entryPrice - atr * InpTPMultiplier;
            RecordPosition(ticket, signal, entryPrice, sl, tp);
            Print("Opened trade #", ticket, " direction=", (signal == 1 ? "BUY" : "SELL"),
                  " price=", entryPrice);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Trade transaction handler                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result) {
   // Detect closed position
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD) {
      // Get the history order info
      CHistoryOrderInfo history;
      if(history.SelectByIndex(HistoryOrderSelect(trans.order))) {
         if(history.Magic() == InpMagicNumber && history.OrderType() <= ORDER_TYPE_SELL) {
            ProcessClosedPosition(trans.order);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Return total exported for fitness (higher = better)              |
//+------------------------------------------------------------------+
double OnTester() {
   return (double)g_totalExported;
}

//+------------------------------------------------------------------+
//| Export OHLCV bar on every tick (fallback for tick-by-tick)       |
//+------------------------------------------------------------------+
// (already handled in OnTick above)
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
