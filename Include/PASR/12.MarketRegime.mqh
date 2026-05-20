//+------------------------------------------------------------------+
//|                                             12.MarketRegime.mqh |
//|                                       Copyright 2026, Agsicentre |
//|            Multi-Timeframe Market Regime & Volatility Filter     |
//|                                                                  |
//| VERSION 2.02 FIXES (post code-audit):                           |
//| - FIX: double-write history buffer → ReadADX/ReadATR helpers    |
//|         no side-effects; Update() shifts history ONCE per bar   |
//| - FIX: CalculateVolatilityRatio reads m_atrHistory[0] directly  |
//|         removes re-call to CalculateATR (was double-insert)     |
//| - FIX: Remove redundant CopyBuffer(50) in Update() — m_atrHistory|
//|         already is the sliding window, no need to re-copy        |
//| - FIX: DetectTransition logic — return true on any regime change |
//|         counter-based settling replaces broken < 3 check        |
//| - FIX: GetLotMultiplier baseMult default=1.0 — compile error    |
//|         when called without argument from DataManager           |
//| - FIX: GetHigherTF ceiling — PERIOD_W1 → MN1, MN1 stays MN1   |
//| - KEEP: all v2.01 fixes                                          |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "2.02"
#property strict

#ifndef __MARKET_REGIME_MQH__
#define __MARKET_REGIME_MQH__

#include "IManager.mqh"
// NOTE: Do NOT include 10.DataManager.mqh here to avoid circular dependency!

class DataManager;

//+------------------------------------------------------------------+
//| ENUMS
//+------------------------------------------------------------------+
enum ENUM_MARKET_REGIME
{
   REGIME_NONE = 0,
   REGIME_TRENDING_STRONG,
   REGIME_TRENDING_WEAK,
   REGIME_RANGING_SIDEWAYS,
   REGIME_CHOPPY_HIGH_VOL,
   REGIME_TRANSITION
};

enum ENUM_VOLATILITY_REGIME
{
   VOLATILITY_LOW = 0,
   VOLATILITY_MEDIUM,
   VOLATILITY_HIGH
};

//+------------------------------------------------------------------+
//| STRUCT: Regime Result
//+------------------------------------------------------------------+
struct RegimeResult
{
   ENUM_MARKET_REGIME    regime;
   ENUM_VOLATILITY_REGIME volRegime;
   double regimeScore;
   double volatilityScore;
   double trendStrength;
   double atrRatio;
   bool   isTransition;
   bool   mtfConfirmed;
   int    tfAlignment;

   RegimeResult()
   {
      regime        = REGIME_NONE;
      volRegime     = VOLATILITY_MEDIUM;
      regimeScore   = 0.0;
      volatilityScore = 0.5;
      trendStrength = 0.0;
      atrRatio      = 1.0;
      isTransition  = false;
      mtfConfirmed  = false;
      tfAlignment   = 0;
   }

   double GetMinSignalThreshold(double baseThreshold = 0.5) const
   {
      if(isTransition) return baseThreshold * 2.0;
      switch(regime)
      {
         case REGIME_TRENDING_STRONG:  return baseThreshold * 0.7;
         case REGIME_TRENDING_WEAK:    return baseThreshold * 0.85;
         case REGIME_RANGING_SIDEWAYS: return baseThreshold * 1.3;
         case REGIME_CHOPPY_HIGH_VOL:  return baseThreshold * 1.5;
         default:                      return baseThreshold * 2.0;
      }
   }

   string Description() const
   {
      string regimeStr;
      switch(regime)
      {
         case REGIME_TRENDING_STRONG:  regimeStr = "Strong Trend"; break;
         case REGIME_TRENDING_WEAK:    regimeStr = "Weak Trend";   break;
         case REGIME_RANGING_SIDEWAYS: regimeStr = "Ranging";      break;
         case REGIME_CHOPPY_HIGH_VOL:  regimeStr = "Choppy High Vol"; break;
         case REGIME_TRANSITION:       regimeStr = "Transition";   break;
         default:                      regimeStr = "Unknown";      break;
      }
      string volStr;
      switch(volRegime)
      {
         case VOLATILITY_LOW:    volStr = "Low Vol";  break;
         case VOLATILITY_MEDIUM: volStr = "Med Vol";  break;
         case VOLATILITY_HIGH:   volStr = "High Vol"; break;
         default:                volStr = "Unknown Vol"; break;
      }
      return StringFormat("%s + %s (Score: %.2f)%s",
                          regimeStr, volStr, regimeScore,
                          mtfConfirmed ? " [MTF Confirmed]" : "");
   }
};

//+------------------------------------------------------------------+
//| CLASS: MarketRegimeFilter
//+------------------------------------------------------------------+
class MarketRegimeFilter
{
private:
   string             m_symbol;
   ENUM_TIMEFRAMES    m_tfTrading;
   ENUM_TIMEFRAMES    m_tfHigher;
   ENUM_TIMEFRAMES    m_tfLongTerm;

   int  m_handleADX;
   int  m_handleATR;
   int  m_handleADX_Higher;
   int  m_handleATR_Higher;
   int  m_handleADX_LongTerm;
   int  m_handleATR_LongTerm;

   RegimeResult   m_currentResult;
   datetime       m_lastUpdate;

   double  m_adxHistory[];
   double  m_atrHistory[];
   int     m_historySize;

   ENUM_MARKET_REGIME m_previousRegime;
   int  m_transitionCounter;
   int  m_stableCounter;

   double   m_cachedRegimeScore;
   double   m_cachedVolatilityScore;
   datetime m_cachedScoreTime;

   DataManager *m_data;

private:

   //+------------------------------------------------------------------+
   //| [v2.01 FIX] Higher/LongTerm TF via lookup table                  |
   //| [v2.02 FIX] Added W1 and MN1 ceiling cases                       |
   //+------------------------------------------------------------------+
   static ENUM_TIMEFRAMES GetHigherTF(ENUM_TIMEFRAMES tf)
   {
      switch(tf)
      {
         case PERIOD_M1:  return PERIOD_M5;
         case PERIOD_M5:  return PERIOD_M15;
         case PERIOD_M15: return PERIOD_M30;
         case PERIOD_M30: return PERIOD_H1;
         case PERIOD_H1:  return PERIOD_H4;
         case PERIOD_H4:  return PERIOD_D1;
         case PERIOD_D1:  return PERIOD_W1;
         case PERIOD_W1:  return PERIOD_MN1;
         case PERIOD_MN1: return PERIOD_MN1;  // ceiling
         default:         return PERIOD_W1;
      }
   }

   static ENUM_TIMEFRAMES GetLongTermTF(ENUM_TIMEFRAMES tf)
   {
      switch(tf)
      {
         case PERIOD_M1:  return PERIOD_H1;
         case PERIOD_M5:  return PERIOD_H4;
         case PERIOD_M15: return PERIOD_D1;
         case PERIOD_M30: return PERIOD_D1;
         case PERIOD_H1:  return PERIOD_D1;
         case PERIOD_H4:  return PERIOD_W1;
         default:         return PERIOD_W1;
      }
   }

   bool CreateIndicators()
   {
      ReleaseIndicators();

      m_handleADX         = iADX(m_symbol, m_tfTrading,  14);
      m_handleATR         = iATR(m_symbol, m_tfTrading,  14);
      m_handleADX_Higher  = iADX(m_symbol, m_tfHigher,   14);
      m_handleATR_Higher  = iATR(m_symbol, m_tfHigher,   14);
      m_handleADX_LongTerm= iADX(m_symbol, m_tfLongTerm, 14);
      m_handleATR_LongTerm= iATR(m_symbol, m_tfLongTerm, 14);

      if(m_handleADX == INVALID_HANDLE || m_handleATR == INVALID_HANDLE ||
         m_handleADX_Higher == INVALID_HANDLE || m_handleATR_Higher == INVALID_HANDLE ||
         m_handleADX_LongTerm == INVALID_HANDLE || m_handleATR_LongTerm == INVALID_HANDLE)
      {
         PrintFormat("[MarketRegime] Failed to create indicator handles. ADX=%d ATR=%d",
                     m_handleADX, m_handleATR);
         return false;
      }

      ArrayResize(m_adxHistory, m_historySize);
      ArrayResize(m_atrHistory, m_historySize);
      ArrayInitialize(m_adxHistory, 25.0);
      ArrayInitialize(m_atrHistory, 0.001);
      return true;
   }

   void ReleaseIndicators()
   {
      if(m_handleADX         != INVALID_HANDLE) { IndicatorRelease(m_handleADX);          m_handleADX         = INVALID_HANDLE; }
      if(m_handleATR         != INVALID_HANDLE) { IndicatorRelease(m_handleATR);          m_handleATR         = INVALID_HANDLE; }
      if(m_handleADX_Higher  != INVALID_HANDLE) { IndicatorRelease(m_handleADX_Higher);   m_handleADX_Higher  = INVALID_HANDLE; }
      if(m_handleATR_Higher  != INVALID_HANDLE) { IndicatorRelease(m_handleATR_Higher);   m_handleATR_Higher  = INVALID_HANDLE; }
      if(m_handleADX_LongTerm!= INVALID_HANDLE) { IndicatorRelease(m_handleADX_LongTerm); m_handleADX_LongTerm= INVALID_HANDLE; }
      if(m_handleATR_LongTerm!= INVALID_HANDLE) { IndicatorRelease(m_handleATR_LongTerm); m_handleATR_LongTerm= INVALID_HANDLE; }
   }

   double GetIndicatorValue(int handle, int buffer, int shift, double fallback = 0.0) const
   {
      double value[1];
      if(CopyBuffer(handle, buffer, shift, 1, value) < 1) return fallback;
      return value[0];
   }

   //+------------------------------------------------------------------+
   //| [v2.02 FIX] ReadADX / ReadATR — pure read, NO history side-effect|
   //| History is updated ONCE per bar in Update() via ShiftAndInsert() |
   //+------------------------------------------------------------------+
   double ReadADX(int handle) const
   {
      if(handle == INVALID_HANDLE) return 25.0;
      return GetIndicatorValue(handle, 0, 1, 25.0);  // shift=1: use last closed bar
   }

   double ReadATR(int handle) const
   {
      if(handle == INVALID_HANDLE) return 0.001;
      return GetIndicatorValue(handle, 0, 1, 0.001);  // shift=1: use last closed bar
   }

   void ShiftAndInsertADX(double value)
   {
      for(int i = m_historySize - 1; i > 0; i--)
         m_adxHistory[i] = m_adxHistory[i - 1];
      m_adxHistory[0] = value;
   }

   void ShiftAndInsertATR(double value)
   {
      for(int i = m_historySize - 1; i > 0; i--)
         m_atrHistory[i] = m_atrHistory[i - 1];
      m_atrHistory[0] = value;
   }

   //+------------------------------------------------------------------+
   //| [v2.02 FIX] CalculateVolatilityRatio — reads m_atrHistory[0]    |
   //| directly, NO call to ReadATR/CalculateATR (eliminates double-    |
   //| insert that was caused by calling CalculateATR inside this fn)   |
   //+------------------------------------------------------------------+
   double CalculateVolatilityRatio(int lookback = 50) const
   {
      double currentATR = m_atrHistory[0];
      int historyCount  = ArraySize(m_atrHistory);
      if(historyCount < 2) return 1.0;

      int effectiveLookback = MathMin(lookback, historyCount);
      if(effectiveLookback < 2) return 1.0;

      double sum = 0.0;
      for(int i = 1; i < effectiveLookback; i++) sum += m_atrHistory[i];
      double avgATR = sum / (effectiveLookback - 1);
      if(avgATR <= 0.0) return 1.0;
      return currentATR / avgATR;
   }

   //+------------------------------------------------------------------+
   //| [v2.02 FIX] DetermineRegime — uses ReadADX (no history write)   |
   //| called AFTER history has already been updated in Update()        |
   //+------------------------------------------------------------------+
   ENUM_MARKET_REGIME DetermineRegime(int adxHandle)
   {
      double adx = ReadADX(adxHandle);
      double atrRatio = CalculateVolatilityRatio(20);

      if(adx > 35)                              return REGIME_TRENDING_STRONG;
      else if(adx > 25)                         return REGIME_TRENDING_WEAK;
      else if(adx < 20 && atrRatio < 0.9)       return REGIME_RANGING_SIDEWAYS;
      else if(adx < 25 && atrRatio > 1.4)       return REGIME_CHOPPY_HIGH_VOL;
      else                                      return REGIME_TRANSITION;
   }

   ENUM_VOLATILITY_REGIME DetermineVolatilityRegime() const
   {
      double ratio = CalculateVolatilityRatio(50);
      if(ratio < 0.7) return VOLATILITY_LOW;
      if(ratio > 1.3) return VOLATILITY_HIGH;
      return VOLATILITY_MEDIUM;
   }

   //+------------------------------------------------------------------+
   //| [v2.02 FIX] DetectTransition — always returns true on change     |
   //| counter-based decay replaces broken "< 3" settled check          |
   //+------------------------------------------------------------------+
   bool DetectTransition(ENUM_MARKET_REGIME current, ENUM_MARKET_REGIME previous)
   {
      if(current != previous)
      {
         m_stableCounter      = 0;
         m_transitionCounter  = MathMin(m_transitionCounter + 1, 10);
         return true;  // always transition when regime changes
      }
      else
      {
         m_transitionCounter  = MathMax(0, m_transitionCounter - 1);
         m_stableCounter++;
         return (m_transitionCounter > 0);  // still transition until fully settled
      }
   }

   double CalculateRegimeScore(ENUM_MARKET_REGIME regime, double adx, double atrRatio) const
   {
      double baseScore = 0.0;
      switch(regime)
      {
         case REGIME_TRENDING_STRONG:  baseScore = 0.9 + MathMin((adx - 35) / 15.0, 1.0) * 0.1; break;
         case REGIME_TRENDING_WEAK:    baseScore = 0.6 + MathMin((adx - 25) / 10.0, 1.0) * 0.29; break;
         case REGIME_RANGING_SIDEWAYS: baseScore = 0.45; break;
         case REGIME_CHOPPY_HIGH_VOL:  baseScore = 0.25; break;
         case REGIME_TRANSITION:       baseScore = 0.1;  break;
         default:                      baseScore = 0.0;  break;
      }
      double volAdj = MathMax(0.8, MathMin(1.0, 1.0 - MathMax(0.0, (atrRatio - 1.0) * 0.1)));
      return MathMax(0.0, MathMin(1.0, baseScore * volAdj));
   }

   double CalculateVolatilityScore(double atrRatio) const
   {
      if(atrRatio < 0.5) return 0.9;
      if(atrRatio > 2.0) return 0.1;
      return 0.9 - (atrRatio - 0.5) / 1.5 * 0.8;
   }

   //+------------------------------------------------------------------+
   //| [v2.01 FIX] Accept pre-computed regimes → no redundant CopyRates |
   //+------------------------------------------------------------------+
   int GetTrendAlignment(ENUM_MARKET_REGIME trading,
                         ENUM_MARKET_REGIME higher,
                         ENUM_MARKET_REGIME longTerm) const
   {
      int a = 0;
      if(trading  == REGIME_TRENDING_STRONG || trading  == REGIME_TRENDING_WEAK) a++;
      if(higher   == REGIME_TRENDING_STRONG || higher   == REGIME_TRENDING_WEAK) a++;
      if(longTerm == REGIME_TRENDING_STRONG || longTerm == REGIME_TRENDING_WEAK) a++;
      return a;
   }

   bool IsMTFConfirmed(ENUM_MARKET_REGIME trading,
                       ENUM_MARKET_REGIME higher,
                       ENUM_MARKET_REGIME longTerm) const
   {
      return GetTrendAlignment(trading, higher, longTerm) >= 2;
   }

   //+------------------------------------------------------------------+
   //| [v2.01 FIX] BuildReasoning() now actually used by GetReasoning() |
   //+------------------------------------------------------------------+
   string BuildReasoning() const
   {
      string regStr;
      switch(m_currentResult.regime)
      {
         case REGIME_TRENDING_STRONG:  regStr = "Strong Trend"; break;
         case REGIME_TRENDING_WEAK:    regStr = "Weak Trend";   break;
         case REGIME_RANGING_SIDEWAYS: regStr = "Ranging";      break;
         case REGIME_CHOPPY_HIGH_VOL:  regStr = "Choppy";       break;
         default:                      regStr = "Transition";   break;
      }
      string out = StringFormat("Regime: %s | Score: %.2f | Vol: %.2f",
                                regStr,
                                m_currentResult.regimeScore,
                                m_currentResult.volatilityScore);
      if(m_currentResult.mtfConfirmed) out += " | MTF Confirmed";
      out += StringFormat(" | TF Alignment: %d/3", m_currentResult.tfAlignment);
      if(m_currentResult.isTransition) out += " | WARNING: Transition Phase";
      return out;
   }

public:

   MarketRegimeFilter()
   {
      m_symbol  = _Symbol;
      m_tfTrading  = _Period;
      // [v2.01 FIX] use lookup table instead of PeriodSeconds()*N
      m_tfHigher   = GetHigherTF(_Period);
      m_tfLongTerm = GetLongTermTF(_Period);

      m_handleADX          = INVALID_HANDLE;
      m_handleATR          = INVALID_HANDLE;
      m_handleADX_Higher   = INVALID_HANDLE;
      m_handleATR_Higher   = INVALID_HANDLE;
      m_handleADX_LongTerm = INVALID_HANDLE;
      m_handleATR_LongTerm = INVALID_HANDLE;

      m_lastUpdate          = 0;
      m_historySize         = 100;
      m_previousRegime      = REGIME_NONE;
      m_transitionCounter   = 0;
      m_stableCounter       = 0;
      m_cachedRegimeScore   = 0.0;
      m_cachedVolatilityScore = 0.5;
      m_cachedScoreTime     = 0;
      m_data                = NULL;

      CreateIndicators();
   }

   ~MarketRegimeFilter() { ReleaseIndicators(); }

   void SetDataManager(DataManager *data) { m_data = data; }
   DataManager* GetDataManager() const    { return m_data; }

   bool Init(ENUM_TIMEFRAMES tfTrading, ENUM_TIMEFRAMES tfHigher, ENUM_TIMEFRAMES tfLongTerm)
   {
      m_tfTrading  = tfTrading;
      m_tfHigher   = tfHigher;
      m_tfLongTerm = tfLongTerm;
      return CreateIndicators();
   }

   //+------------------------------------------------------------------+
   //| [v2.02 FIX] Update — history shifted ONCE per bar.              |
   //| ReadADX/ReadATR are pure reads. DetermineRegime uses ReadADX.   |
   //| No redundant CopyBuffer(50) block — m_atrHistory covers this.   |
   //+------------------------------------------------------------------+
   void Update()
   {
      datetime currentBarTime = iTime(m_symbol, m_tfTrading, 0);
      if(currentBarTime == m_lastUpdate && m_lastUpdate != 0) return;
      m_lastUpdate = currentBarTime;

      // Step 1: Read all indicator values (pure read, no side effects)
      double adxTrading   = ReadADX(m_handleADX);
      double atrTrading   = ReadATR(m_handleATR);

      // Step 2: Update history ONCE per bar
      ShiftAndInsertADX(adxTrading);
      ShiftAndInsertATR(atrTrading);

      // Step 3: Compute regimes using ReadADX (no history write)
      ENUM_MARKET_REGIME tradingRegime  = DetermineRegime(m_handleADX);
      ENUM_MARKET_REGIME higherRegime   = DetermineRegime(m_handleADX_Higher);
      ENUM_MARKET_REGIME longTermRegime = DetermineRegime(m_handleADX_LongTerm);
      ENUM_VOLATILITY_REGIME volRegime  = DetermineVolatilityRegime();

      bool isTransition = DetectTransition(tradingRegime, m_previousRegime);

      // Step 4: ATR ratio from history (no extra CopyBuffer needed)
      double atrRatio = CalculateVolatilityRatio(50);

      double regimeScore     = CalculateRegimeScore(isTransition ? REGIME_TRANSITION : tradingRegime,
                                                    adxTrading, atrRatio);
      double volatilityScore = CalculateVolatilityScore(atrRatio);

      m_cachedRegimeScore     = regimeScore;
      m_cachedVolatilityScore = volatilityScore;
      m_cachedScoreTime       = currentBarTime;

      // [v2.01 FIX] pass pre-computed regimes — no extra CopyRates calls
      bool mtfConfirmed = IsMTFConfirmed(tradingRegime, higherRegime, longTermRegime);
      int  tfAlignment  = GetTrendAlignment(tradingRegime, higherRegime, longTermRegime);

      m_currentResult.regime          = isTransition ? REGIME_TRANSITION : tradingRegime;
      m_currentResult.volRegime       = volRegime;
      m_currentResult.regimeScore     = regimeScore;
      m_currentResult.volatilityScore = volatilityScore;
      m_currentResult.trendStrength   = adxTrading;
      m_currentResult.atrRatio        = atrRatio;
      m_currentResult.isTransition    = isTransition;
      m_currentResult.mtfConfirmed    = mtfConfirmed;
      m_currentResult.tfAlignment     = tfAlignment;

      m_previousRegime = tradingRegime;
   }

   const RegimeResult& GetResult()  const { return m_currentResult; }
   const RegimeResult& GetContext() const { return m_currentResult; }

   double GetRegimeScore()     const { return m_currentResult.regimeScore; }
   double GetVolatilityScore() const { return m_currentResult.volatilityScore; }

   double GetDynamicThreshold(double baseThreshold = 0.5) const
   { return m_currentResult.GetMinSignalThreshold(baseThreshold); }

   bool IsTradingAllowed(bool allowRanging = true, bool allowChoppy = false) const
   {
      if(m_currentResult.isTransition) return false;
      switch(m_currentResult.regime)
      {
         case REGIME_TRENDING_STRONG:
         case REGIME_TRENDING_WEAK:    return true;
         case REGIME_RANGING_SIDEWAYS: return allowRanging;
         case REGIME_CHOPPY_HIGH_VOL:  return allowChoppy;
         default:                      return false;
      }
   }

   ENUM_MARKET_REGIME GetMarketRegime() const { return m_currentResult.regime; }
   bool IsTrending() const { return m_currentResult.regime == REGIME_TRENDING_STRONG || m_currentResult.regime == REGIME_TRENDING_WEAK; }
   bool IsRanging()  const { return m_currentResult.regime == REGIME_RANGING_SIDEWAYS; }

   //+------------------------------------------------------------------+
   //| [v2.02 FIX] baseMult default=1.0 — fixes compile error when     |
   //| called without argument from DataManager::CalculateLotSize()    |
   //+------------------------------------------------------------------+
   double GetLotMultiplier(double baseMult = 1.0,
                           double strongMult = 1.5, double weakMult = 1.0,
                           double sideMult   = 0.7, double chopMult = 0.5) const
   {
      if(m_currentResult.isTransition) return 0.0;
      switch(m_currentResult.regime)
      {
         case REGIME_TRENDING_STRONG:  return baseMult * strongMult;
         case REGIME_TRENDING_WEAK:    return baseMult * weakMult;
         case REGIME_RANGING_SIDEWAYS: return baseMult * sideMult;
         case REGIME_CHOPPY_HIGH_VOL:  return baseMult * chopMult;
         default:                      return baseMult * 0.5;
      }
   }

   double GetVolatilityAdjustment() const
   {
      switch(m_currentResult.volRegime)
      {
         case VOLATILITY_LOW:  return 0.8;
         case VOLATILITY_HIGH: return 1.5;
         default:              return 1.0;
      }
   }

   bool   HasConfluence()    const { return m_currentResult.mtfConfirmed; }
   string GetDescription()   const { return m_currentResult.Description(); }

   // [v2.01 FIX] GetReasoning() now delegates to BuildReasoning() instead of duplicating
   string GetReasoning() const { return BuildReasoning(); }
};

#endif
