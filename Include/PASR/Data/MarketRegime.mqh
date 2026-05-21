//+------------------------------------------------------------------+
//|                                      Data/MarketRegime.mqh       |
//|  FIX #9 (2026-05-21): removed stale forward to ../12.MarketRegime|
//|  Self-contained stub with compilable CMarketRegime class.       |
//|  RecoveryManager and AIManager depend on this file.             |
//+------------------------------------------------------------------+
#property strict
#ifndef __DATA_MARKET_REGIME_MQH__
#define __DATA_MARKET_REGIME_MQH__

#include "../Core/IManager.mqh"

// Market regime classification
enum ENUM_MARKET_REGIME
  {
   REGIME_UNKNOWN   = 0,
   REGIME_TRENDING  = 1,   // ADX > threshold, strong directional move
   REGIME_RANGING   = 2,   // ADX low, price oscillating between S/R
   REGIME_VOLATILE  = 3,   // ATR spike, wide bars, unpredictable
   REGIME_BREAKOUT  = 4    // price breaking out of established range
  };

// Regime snapshot
struct RegimeSnapshot
  {
   ENUM_MARKET_REGIME regime;
   double             score;        // 0-100 confidence of regime classification
   double             adx;          // ADX value at time of snapshot
   double             atrNorm;      // ATR normalized to recent average
   datetime           updatedAt;    // time of last update

   void Init()
     {
      regime    = REGIME_UNKNOWN;
      score     = 0.0;
      adx       = 0.0;
      atrNorm   = 1.0;
      updatedAt = 0;
     }
  };

//+------------------------------------------------------------------+
//| CMarketRegime — market regime detection stub                     |
//| Full ADX + ATR + volatility regime logic is Phase 2 work.        |
//+------------------------------------------------------------------+
class CMarketRegime : public IManager
  {
private:
   RegimeSnapshot  m_current;
   RegimeSnapshot  m_previous;

public:
   CMarketRegime() : IManager() { m_current.Init(); m_previous.Init(); }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
     }

   virtual void OnNewBar() override
     {
      // TODO Phase 2: classify regime using ADX + ATR + bar structure
      // Pattern: ADX > 25 + directional move = TRENDING
      //          ADX < 20 + narrow ATR = RANGING
      //          ATR > 2x average + wide bars = VOLATILE
      m_previous  = m_current;
      // Placeholder: always UNKNOWN until Phase 2 implemented
      m_current.updatedAt = TimeCurrent();
     }

   RegimeSnapshot       GetCurrent()  const { return m_current;  }
   RegimeSnapshot       GetPrevious() const { return m_previous; }
   ENUM_MARKET_REGIME   GetRegime()   const { return m_current.regime; }
   double               GetScore()    const { return m_current.score; }

   bool IsTrending()  const { return m_current.regime == REGIME_TRENDING; }
   bool IsRanging()   const { return m_current.regime == REGIME_RANGING;  }
   bool IsVolatile()  const { return m_current.regime == REGIME_VOLATILE; }
   bool IsBreakout()  const { return m_current.regime == REGIME_BREAKOUT; }

   // Returns true if regime is suitable for normal trading
   bool IsTradeable() const
     {
      return (m_current.regime == REGIME_TRENDING ||
              m_current.regime == REGIME_BREAKOUT);
     }
  };

// Backward-compat alias
typedef CMarketRegime MarketRegime;

#endif // __DATA_MARKET_REGIME_MQH__
