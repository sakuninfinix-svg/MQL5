//+------------------------------------------------------------------+
//| Signal/RegimeSignalSource.mqh — v1.00  (Phase 4)                 |
//| ISignalSource plugin: regime-based signal gate / suppressor.     |
//|                                                                  |
//| BEHAVIOUR:                                                       |
//|  VOLATILE  → always return SIGNAL_NONE (suppress all trades)    |
//|  TRENDING  → boost confidence of directional signal             |
//|  RANGING   → reduce confidence (PA/SR still valid, but careful) |
//|  SQUEEZE   → reduce confidence slightly (wait for breakout)     |
//|  UNKNOWN   → pass through (no data = neutral)                   |
//|                                                                  |
//| NOTE: RegimeSignalSource is typically registered with a          |
//|   NEGATIVE weight (-99) so it acts as a veto when VOLATILE,      |
//|   or with weight (0.5) as a modulator.                           |
//|   Use SetMode(REGIME_MODE_VETO) for hard block on VOLATILE.      |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_REGIME_SOURCE_MQH__
#define __SIGNAL_REGIME_SOURCE_MQH__

#include "ISignalSource.mqh"
#include "RegimeFilter.mqh"

enum ENUM_REGIME_SOURCE_MODE
  {
   REGIME_MODE_MODULATE = 0,   // adjust confidence (soft)
   REGIME_MODE_VETO     = 1    // VOLATILE = hard block (return NONE)
  };

class RegimeSignalSource : public ISignalSource
  {
private:
   CRegimeFilter           *m_regime;
   ENUM_REGIME_SOURCE_MODE  m_mode;

public:
   RegimeSignalSource(CRegimeFilter *regime, ENUM_REGIME_SOURCE_MODE mode=REGIME_MODE_VETO)
      : m_regime(regime), m_mode(mode) {}

   virtual string Name() override { return "RegimeSignalSource"; }

   virtual bool Evaluate(SignalResult &out) override
     {
      if(m_regime==NULL || !m_regime.IsReady())
        {
         // Not enough data yet — pass neutral
         out.direction  = SIGNAL_NONE;
         out.confidence = 0.5;
         out.reason     = "Regime:NotReady";
         return true;
        }

      ENUM_MARKET_REGIME r = m_regime.GetRegime();

      if(m_mode == REGIME_MODE_VETO && r == REGIME_VOLATILE)
        {
         out.direction  = SIGNAL_NONE;
         out.confidence = 0.0;
         out.reason     = StringFormat("RegimeVeto:VOLATILE(ADX=%.1f)", m_regime.GetADX());
         return true;
        }

      // Confidence modulation based on regime
      double confMult = 1.0;
      switch(r)
        {
         case REGIME_TRENDING:  confMult = 1.3;  break;  // boost
         case REGIME_RANGING:   confMult = 0.8;  break;  // reduce
         case REGIME_SQUEEZE:   confMult = 0.7;  break;  // cautious
         case REGIME_VOLATILE:  confMult = 0.2;  break;  // heavy reduce
         default:               confMult = 1.0;  break;
        }

      out.direction  = SIGNAL_NONE;  // regime doesn't vote direction
      out.confidence = confMult;
      out.reason     = StringFormat("Regime:%s(x%.1f)", RegimeName(r), confMult);
      return true;
     }

   ENUM_MARKET_REGIME GetCurrentRegime() const
     { return m_regime ? m_regime.GetRegime() : REGIME_UNKNOWN; }
  };

#endif // __SIGNAL_REGIME_SOURCE_MQH__
