//+------------------------------------------------------------------+
//|                        MQL5Compatibility.mqh                      |
//|                  Helper functions for MQL4->MQL5 migration        |
//+------------------------------------------------------------------+
#property copyright "Migration Helper"
#property version "1.00"

#ifndef __MQL5_COMPATIBILITY_H__
#define __MQL5_COMPATIBILITY_H__

//+------------------------------------------------------------------+
//| Copy OHLCV data using MQL5 CopyRates/Series functions            |
//+------------------------------------------------------------------+

// Get High price at specific index
double GetHigh(const string symbol, const ENUM_TIMEFRAMES timeframe, const int index)
{
   double highArray[];
   ArraySetAsSeries(highArray, true);
   if(CopyHigh(symbol, timeframe, index, 1, highArray) > 0)
      return highArray[0];
   return 0;
}

// Get Low price at specific index
double GetLow(const string symbol, const ENUM_TIMEFRAMES timeframe, const int index)
{
   double lowArray[];
   ArraySetAsSeries(lowArray, true);
   if(CopyLow(symbol, timeframe, index, 1, lowArray) > 0)
      return lowArray[0];
   return 0;
}

// Get Open price at specific index
double GetOpen(const string symbol, const ENUM_TIMEFRAMES timeframe, const int index)
{
   double openArray[];
   ArraySetAsSeries(openArray, true);
   if(CopyOpen(symbol, timeframe, index, 1, openArray) > 0)
      return openArray[0];
   return 0;
}

// Get Close price at specific index
double GetClose(const string symbol, const ENUM_TIMEFRAMES timeframe, const int index)
{
   double closeArray[];
   ArraySetAsSeries(closeArray, true);
   if(CopyClose(symbol, timeframe, index, 1, closeArray) > 0)
      return closeArray[0];
   return 0;
}

// Get Time at specific index
datetime GetTime(const string symbol, const ENUM_TIMEFRAMES timeframe, const int index)
{
   datetime timeArray[];
   ArraySetAsSeries(timeArray, true);
   if(CopyTime(symbol, timeframe, index, 1, timeArray) > 0)
      return timeArray[0];
   return 0;
}

// Get multiple OHLC values at once for efficiency
struct OHLCV
{
   datetime time;
   double open;
   double high;
   double low;
   double close;
   long volume;
};

bool GetOHLCV(const string symbol, const ENUM_TIMEFRAMES timeframe, const int index, OHLCV &result)
{
   MqlRate rateArray[];
   if(CopyRates(symbol, timeframe, index, 1, rateArray) > 0)
   {
      result.time = rateArray[0].time;
      result.open = rateArray[0].open;
      result.high = rateArray[0].high;
      result.low = rateArray[0].low;
      result.close = rateArray[0].close;
      result.volume = rateArray[0].tick_volume;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Find highest high in range (replacement for iHighest MODE_HIGH)  |
//+------------------------------------------------------------------+
int FindHighestHigh(const string symbol, const ENUM_TIMEFRAMES timeframe, const int count, const int start)
{
   double highArray[];
   ArraySetAsSeries(highArray, true);
   int copied = CopyHigh(symbol, timeframe, start, count, highArray);
   if(copied <= 0)
      return -1;
   
   int maxIndex = ArrayMaximum(highArray);
   if(maxIndex < 0)
      return -1;
   
   return start + maxIndex;
}

//+------------------------------------------------------------------+
//| Find lowest low in range (replacement for iLowest MODE_LOW)      |
//+------------------------------------------------------------------+
int FindLowestLow(const string symbol, const ENUM_TIMEFRAMES timeframe, const int count, const int start)
{
   double lowArray[];
   ArraySetAsSeries(lowArray, true);
   int copied = CopyLow(symbol, timeframe, start, count, lowArray);
   if(copied <= 0)
      return -1;
   
   int minIndex = ArrayMinimum(lowArray);
   if(minIndex < 0)
      return -1;
   
   return start + minIndex;
}

//+------------------------------------------------------------------+
//| Indicator wrapper classes for MQL5 style                         |
//+------------------------------------------------------------------+
class CIndicatorMA
{
private:
   int m_handle;
   string m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   int m_period;
   int m_shift;
   ENUM_MA_METHOD m_method;
   ENUM_APPLIED_PRICE m_price;
   bool m_initialized;

public:
   CIndicatorMA() : m_handle(INVALID_HANDLE), m_initialized(false) {}
   
   ~CIndicatorMA()
   {
      if(m_handle != INVALID_HANDLE)
         IndicatorRelease(m_handle);
   }
   
   bool Create(const string symbol, const ENUM_TIMEFRAMES timeframe, 
               const int period, const int shift, 
               const ENUM_MA_METHOD method, const ENUM_APPLIED_PRICE price)
   {
      m_symbol = symbol;
      m_timeframe = timeframe;
      m_period = period;
      m_shift = shift;
      m_method = method;
      m_price = price;
      
      m_handle = iMA(symbol, timeframe, period, shift, method, price);
      if(m_handle == INVALID_HANDLE)
      {
         Print("Error creating MA indicator: ", GetLastError());
         return false;
      }
      m_initialized = true;
      return true;
   }
   
   double GetValue(const int index)
   {
      if(!m_initialized || m_handle == INVALID_HANDLE)
         return 0;
      
      double buffer[];
      ArraySetAsSeries(buffer, true);
      if(CopyBuffer(m_handle, 0, index, 1, buffer) > 0)
         return buffer[0];
      return 0;
   }
   
   bool GetValues(const int start, const int count, double &values[])
   {
      if(!m_initialized || m_handle == INVALID_HANDLE)
         return false;
      
      ArraySetAsSeries(values, true);
      return CopyBuffer(m_handle, 0, start, count, values) > 0;
   }
};

//+------------------------------------------------------------------+
//| ATR Indicator Wrapper                                            |
//+------------------------------------------------------------------+
class CIndicatorATR
{
private:
   int m_handle;
   bool m_initialized;

public:
   CIndicatorATR() : m_handle(INVALID_HANDLE), m_initialized(false) {}
   
   ~CIndicatorATR()
   {
      if(m_handle != INVALID_HANDLE)
         IndicatorRelease(m_handle);
   }
   
   bool Create(const string symbol, const ENUM_TIMEFRAMES timeframe, const int period)
   {
      m_handle = iATR(symbol, timeframe, period);
      if(m_handle == INVALID_HANDLE)
      {
         Print("Error creating ATR indicator: ", GetLastError());
         return false;
      }
      m_initialized = true;
      return true;
   }
   
   double GetValue(const int index)
   {
      if(!m_initialized || m_handle == INVALID_HANDLE)
         return 0;
      
      double buffer[];
      ArraySetAsSeries(buffer, true);
      if(CopyBuffer(m_handle, 0, index, 1, buffer) > 0)
         return buffer[0];
      return 0;
   }
};

//+------------------------------------------------------------------+
//| Helper function to create MA handle (MQL5 style)                 |
//+------------------------------------------------------------------+
int CreateMAHandle(const ENUM_TIMEFRAMES timeframe, const int period, 
                   const ENUM_MA_METHOD method, const ENUM_APPLIED_PRICE price)
{
   return iMA(_Symbol, timeframe, period, 0, method, price);
}

//+------------------------------------------------------------------+
//| Helper function to create ATR handle (MQL5 style)                |
//+------------------------------------------------------------------+
int CreateATRHandle(const ENUM_TIMEFRAMES timeframe, const int period)
{
   return iATR(_Symbol, timeframe, period);
}

#endif // __MQL5_COMPATIBILITY_H__
