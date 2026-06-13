//+------------------------------------------------------------------+
//| Analysis/MarketRegimeScorer.mqh — v1.0                           |
//| Scores current market regime confidence                          |
//+------------------------------------------------------------------+
#property strict
#ifndef __ANALYSIS_MARKET_REGIME_SCORER_MQH__
#define __ANALYSIS_MARKET_REGIME_SCORER_MQH__

#include "../Data/RegimeTypes.mqh"

class CMarketRegimeScorer
  {
private:
   int m_adxHandle;
   int m_atrHandle;

   double Clamp01(double v) const { return MathMax(0.0, MathMin(1.0, v)); }

public:
   CMarketRegimeScorer() : m_adxHandle(INVALID_HANDLE), m_atrHandle(INVALID_HANDLE) {}

   ~CMarketRegimeScorer()
     {
      if(m_adxHandle != INVALID_HANDLE) IndicatorRelease(m_adxHandle);
      if(m_atrHandle != INVALID_HANDLE) IndicatorRelease(m_atrHandle);
     }

   bool Init()
     {
      if(m_adxHandle == INVALID_HANDLE) m_adxHandle = iADX(_Symbol, _Period, 14);
      if(m_atrHandle == INVALID_HANDLE) m_atrHandle = iATR(_Symbol, _Period, 14);
      return (m_adxHandle != INVALID_HANDLE && m_atrHandle != INVALID_HANDLE);
     }

   // FIX: Implement actual scoring instead of stub returning 0.5
   double Score(EMarketRegime regime) const
     {
      if(regime == REGIME_UNKNOWN) return 0.0;

      double adxBuf[1], atrBuf[1];
      double adx = 0.0, atr = 0.0;
      if(m_adxHandle != INVALID_HANDLE && CopyBuffer(m_adxHandle, 0, 1, 1, adxBuf) > 0)
         adx = adxBuf[0];
      if(m_atrHandle != INVALID_HANDLE && CopyBuffer(m_atrHandle, 0, 1, 1, atrBuf) > 0)
         atr = atrBuf[0];

      double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double atrPct = (price > 0 && atr > 0) ? (atr / price) * 10000.0 : 0.0;

      switch(regime)
        {
         case REGIME_TREND_UP:
         case REGIME_TREND_DOWN:
            // Trend confidence driven by ADX strength
            return Clamp01(adx / 50.0);

         case REGIME_RANGE:
            // Range confidence: high when ADX is low and volatility is moderate
            {
               double adxScore = 1.0 - Clamp01(adx / 25.0);
               double volScore = (atrPct > 3.0 && atrPct < 20.0) ? 1.0 : 0.3;
               return (adxScore + volScore) * 0.5;
            }

         case REGIME_VOLATILE:
            // Volatile confidence: high ATR relative to baseline
            return Clamp01(atrPct / 30.0);

         case REGIME_SQUEEZE:
            // Squeeze confidence: low ADX + low ATR
            {
               double adxScore = 1.0 - Clamp01(adx / 20.0);
               double volScore = 1.0 - Clamp01(atrPct / 10.0);
               return (adxScore + volScore) * 0.5;
            }

         default:
            return 0.3;
        }
     }
  };

#endif // __ANALYSIS_MARKET_REGIME_SCORER_MQH__
