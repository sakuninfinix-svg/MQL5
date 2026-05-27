//+------------------------------------------------------------------+
//|                                              PatternContext.mqh  |
//|                                 Copyright 2024, PASR Architecture|
//|                                     https://pasr-architecture.com|
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, PASR Architecture"
#property link      "https://pasr-architecture.com"
#property version   "1.00"
#ifndef __ANALYSIS_PATTERN_CORE_CONTEXT_MQH__
#define __ANALYSIS_PATTERN_CORE_CONTEXT_MQH__
//+------------------------------------------------------------------+
//| Context object untuk Pattern Pipeline                            |
//+------------------------------------------------------------------+
#include "..\PatternTypes.mqh"
#include "..\..\Data\RegimeTypes.mqh"
#include <Arrays\ArrayObj.mqh>

//+------------------------------------------------------------------+
//| Struct untuk menyimpan data candle yang dianalisis               |
//+------------------------------------------------------------------+
struct SCandleData
{
   datetime time;
   double   open;
   double   high;
   double   low;
   double   close;
   long     volume;
   int      index;
   
   // Derived values
   double   range;
   double   body;
   double   upperShadow;
   double   lowerShadow;
   bool     isBullish;
   
   void Calculate()
   {
      range = high - low;
      body = MathAbs(close - open);
      upperShadow = high - MathMax(open, close);
      lowerShadow = MathMin(open, close) - low;
      isBullish = (close > open);
   }
   
   string ToString() const
   {
      return StringFormat("Candle[%d]: O=%.5f H=%.5f L=%.5f C=%.5f Range=%.5f", 
                         index, open, high, low, close, range);
   }
};

//+------------------------------------------------------------------+
//| Struct untuk menyimpan hasil deteksi pattern                     |
//+------------------------------------------------------------------+
struct SPatternResult
{
   ENUM_PATTERN_TYPE type;
   int               direction;        // +1 bull, -1 bear, 0 neutral
   double            strength;         // 0.0 - 1.0
   double            confidence;       // 0.0 - 1.0
   int               candleIndex;      // Index candle utama
   datetime          timestamp;
   double            price;            // Price level pattern
   double            stopLossLevel;    // Suggested SL level
   double            takeProfitLevel;  // Suggested TP level
   
   // Metadata
   string            notes;
   double            regimeWeight;
   
   SPatternResult() : type(PATTERN_NONE), direction(0), strength(0), 
                      confidence(0), candleIndex(0), regimeWeight(1.0) {}
   
   bool IsValid() const { return type != PATTERN_NONE && strength > 0; }
   
   string ToString() const
   {
      string dirStr = (direction > 0) ? "BULL" : (direction < 0) ? "BEAR" : "NEUTRAL";
      return StringFormat("Pattern[%s] Dir[%s] Str=%.2f Conf=%.2f @ %s", 
                         EnumToString(type), dirStr, strength, confidence, TimeToString(timestamp));
   }
};

//+------------------------------------------------------------------+
//| Context Object untuk Pattern Pipeline                            |
//+------------------------------------------------------------------+
class CPatternContext
{
private:
   // Input data
   MqlRates         m_rates[];           // Raw rate data
   SCandleData      m_candles[];         // Processed candle data
   int              m_currentBar;        // Current bar index being analyzed
   ENUM_TIMEFRAMES  m_timeframe;         // Timeframe data
   symbol           m_symbol;            // Symbol being analyzed
   
   // Market context
   ENUM_REGIME_TYPE m_regime;            // Current market regime
   double           m_atr;               // ATR value for volatility
   double           m_volatilityRatio;   // Current vs average volatility
   
   // Results
   CArrayObj        m_results;           // Array of SPatternResult*
   double           m_overallScore;      // Aggregate score
   bool             m_isValid;           // Context validity flag
   
   // Metadata
   datetime         m_lastUpdate;        // Last update timestamp
   int              m_barsProcessed;     // Number of bars processed
   
public:
   CPatternContext() : m_currentBar(0), m_timeframe(PERIOD_CURRENT), 
                       m_regime(REGIME_UNKNOWN), m_atr(0), m_volatilityRatio(1.0),
                       m_overallScore(0), m_isValid(false), m_barsProcessed(0)
   {
      m_results.Init();
      ArraySetAsSeries(m_rates, true);
      ArraySetAsSeries(m_candles, true);
   }
   
   ~CPatternContext()
   {
      Clear();
   }
   
   //+------------------------------------------------------------------+
   //| Initialize context dengan data                                   |
   //+------------------------------------------------------------------+
   bool Init(const string symbol, ENUM_TIMEFRAMES tf, const MqlRates &rates[], 
             ENUM_REGIME_TYPE regime, double atr)
   {
      Clear();
      
      m_symbol = symbol;
      m_timeframe = tf;
      m_regime = regime;
      m_atr = atr;
      m_lastUpdate = TimeCurrent();
      
      // Copy rates
      int size = ArraySize(rates);
      if(size == 0)
      {
         LogStageMessage("Context", "Empty rates array", LOG_ERROR);
         return false;
      }
      
      ArrayResize(m_rates, size);
      ArrayCopy(m_rates, rates);
      ArraySetAsSeries(m_rates, true);
      
      // Process candles
      ArrayResize(m_candles, size);
      for(int i = 0; i < size; i++)
      {
         m_candles[i].time = rates[i].time;
         m_candles[i].open = rates[i].open;
         m_candles[i].high = rates[i].high;
         m_candles[i].low = rates[i].low;
         m_candles[i].close = rates[i].close;
         m_candles[i].volume = rates[i].tick_volume;
         m_candles[i].index = i;
         m_candles[i].Calculate();
      }
      
      m_barsProcessed = size;
      m_isValid = true;
      
      LogStageMessage("Context", StringFormat("Initialized with %d bars for %s %s", 
                        size, symbol, EnumToString(tf)), LOG_DEBUG);
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Clear all data                                                   |
   //+------------------------------------------------------------------+
   void Clear()
   {
      ArrayFree(m_rates);
      ArrayFree(m_candles);
      
      for(int i = m_results.Total() - 1; i >= 0; i--)
      {
         SPatternResult *result = m_results.At(i);
         if(result != NULL)
            delete result;
      }
      m_results.Clear();
      
      m_currentBar = 0;
      m_overallScore = 0;
      m_isValid = false;
      m_barsProcessed = 0;
   }
   
   //+------------------------------------------------------------------+
   //| Getters                                                          |
   //+------------------------------------------------------------------+
   int GetBarsCount() const { return ArraySize(m_candles); }
   const SCandleData& GetCandle(int index) const { return m_candles[index]; }
   const MqlRates& GetRate(int index) const { return m_rates[index]; }
   int GetCurrentBar() const { return m_currentBar; }
   ENUM_TIMEFRAMES GetTimeframe() const { return m_timeframe; }
   string GetSymbol() const { return m_symbol; }
   ENUM_REGIME_TYPE GetRegime() const { return m_regime; }
   double GetATR() const { return m_atr; }
   double GetVolatilityRatio() const { return m_volatilityRatio; }
   datetime GetLastUpdate() const { return m_lastUpdate; }
   bool IsValid() const { return m_isValid; }
   
   //+------------------------------------------------------------------+
   //| Setters                                                          |
   //+------------------------------------------------------------------+
   void SetCurrentBar(int index) { m_currentBar = index; }
   void SetVolatilityRatio(double ratio) { m_volatilityRatio = ratio; }
   
   //+------------------------------------------------------------------+
   //| Result management                                                |
   //+------------------------------------------------------------------+
   void AddResult(SPatternResult &result)
   {
      SPatternResult *pResult = new SPatternResult();
      *pResult = result;
      m_results.Add(pResult);
      
      // Update overall score
      RecalculateOverallScore();
      
      LogStageMessage("Context", StringFormat("Added result: %s", result.ToString()), LOG_DEBUG);
   }
   
   int GetResultCount() const { return m_results.Total(); }
   
   SPatternResult* GetResult(int index)
   {
      return m_results.At(index);
   }
   
   CArrayObj* GetAllResults() { return &m_results; }
   
   void ClearResults()
   {
      for(int i = m_results.Total() - 1; i >= 0; i--)
      {
         SPatternResult *result = m_results.At(i);
         if(result != NULL)
            delete result;
      }
      m_results.Clear();
      m_overallScore = 0;
   }
   
   //+------------------------------------------------------------------+
   //| Score calculation                                                |
   //+------------------------------------------------------------------+
   void RecalculateOverallScore()
   {
      if(m_results.Total() == 0)
      {
         m_overallScore = 0;
         return;
      }
      
      double totalStrength = 0;
      double totalConfidence = 0;
      int count = 0;
      
      for(int i = 0; i < m_results.Total(); i++)
      {
         SPatternResult *result = m_results.At(i);
         if(result != NULL && result->IsValid())
         {
            totalStrength += result->strength;
            totalConfidence += result->confidence;
            count++;
         }
      }
      
      if(count > 0)
      {
         m_overallScore = (totalStrength / count) * 0.6 + (totalConfidence / count) * 0.4;
      }
   }
   
   double GetOverallScore() const { return m_overallScore; }
   
   //+------------------------------------------------------------------+
   //| Helper methods                                                   |
   //+------------------------------------------------------------------+
   bool IsCandleValid(int index) const
   {
      return (index >= 0 && index < ArraySize(m_candles));
   }
   
   double GetAverageRange(int lookback = 20) const
   {
      if(lookback <= 0 || lookback > ArraySize(m_candles))
         return 0;
      
      double sum = 0;
      for(int i = 0; i < lookback; i++)
      {
         sum += m_candles[i].range;
      }
      
      return sum / lookback;
   }
   
   //+------------------------------------------------------------------+
   //| Debug output                                                     |
   //+------------------------------------------------------------------+
   string ToString() const
   {
      return StringFormat("PatternContext[%s %s] Bars=%d Results=%d Score=%.2f Valid=%s",
                         m_symbol, EnumToString(m_timeframe), 
                         m_barsProcessed, m_results.Total(), 
                         m_overallScore, m_isValid ? "YES" : "NO");
   }
};
//+------------------------------------------------------------------+
#endif // __ANALYSIS_PATTERN_CORE_CONTEXT_MQH__
//+------------------------------------------------------------------+
